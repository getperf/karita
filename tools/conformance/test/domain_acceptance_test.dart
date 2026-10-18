/// **P3 の受入 — 実 DB に対する B1（完全バックアップ）と B3（同期世代）の再現。**
///
/// 「モック集約ではない」がここの全部である。他の試験は `admin fixture seed` 相当の経路で
/// 封筒を作って台帳を埋めていた。ここは**業務の入口だけ**を通って埋める — 本を採用し、
/// 図書館システムを登録し、Loan を開始して遷移させ、棚卸を完了する。そのうえで
///
/// - **B1**: その台帳が `.blib` に出て、別の端末へ復元でき、件数と中身が一致する
/// - **B3**: その台帳が世代の宣言・参加・世代変更の検出を通る
///
/// を測る。**業務が作った outbox がそのまま同期を通る**ことも同時に見る — 業務と同期が同じ
/// 台帳を触る形は、両方を組んで初めて測れる。
///
/// **ネットワークを要さない。** 転送も保管先も `dir` で完結する。
library;

import 'package:conformance/src/harness.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String t0 = '2026-08-04T09:00:00Z';
const String t1 = '2026-08-05T09:00:00Z';
const String t2 = '2026-08-06T09:00:00Z';
const String t3 = '2026-08-07T09:00:00Z';
const String t4 = '2026-08-08T09:00:00Z';

const String isbnA = '9784274226298';
const String isbnB = '9784295009709';

const LibrarySystem minato = LibrarySystem(
  id: 'Tokyo_Minato',
  pref: '東京都',
  city: '港区',
  name: '港区立図書館',
  branches: [
    Branch(id: 'minato-main', calilLibkey: '港区中央', name: '中央館'),
    Branch(id: 'minato-mita', calilLibkey: '港区三田', name: '三田館'),
  ],
);

const LibrarySystem chuo = LibrarySystem(
  id: 'Tokyo_Chuo',
  pref: '東京都',
  city: '中央区',
  name: '中央区立図書館',
  branches: [Branch(id: 'chuo-main', calilLibkey: '中央区中央', name: '中央館')],
);

/// **業務の入口だけを通って台帳を作る。** 封筒を直に組み立てない。
///
/// できあがるのは「図書館システム2件・本2冊・Loan 2件（借出中と取置中）・棚卸1件」で、
/// これが B1 と B3 が運ぶ中身になる。
({String borrowedLoan, String readyLoan}) buildLibrary(Device device) {
  device.librarySystems.register(system: minato, now: t0);
  device.librarySystems.register(system: chuo, now: t0);

  device.books.adopt(
    title: '達人プログラマー',
    authors: const ['David Thomas', 'Andrew Hunt'],
    isbn13: isbnA,
    publisher: 'オーム社',
    provider: 'rakuten',
    now: t0,
  );

  final borrowed = 'aaaaaaaa-1000-4000-8000-000000000001';
  device.loans.start(
    loanId: borrowed,
    bookId: deterministicId(entityBook, isbnA),
    status: 'borrowed',
    systemId: minato.id,
    pickupLibraryId: 'minato-main',
    now: t0,
  );

  // 2冊目は候補からの開始。**採用と開始が一つのトランザクションで確定する経路**を通す。
  final ready = 'aaaaaaaa-1000-4000-8000-000000000002';
  device.loans.startFromCandidate(
    loanId: ready,
    candidate: const BookCandidateInput(
      title: '達人プログラマー 第2版',
      authors: ['David Thomas'],
      isbn13: isbnB,
      provider: 'rakuten',
    ),
    status: 'reserved',
    systemId: chuo.id,
    pickupLibraryId: 'chuo-main',
    now: t1,
  );
  device.loans.update(loanId: ready, action: 'ready-for-pickup', now: t2);

  device.memberships.completePatrol(systemId: minato.id, now: t2);

  return (borrowedLoan: borrowed, readyLoan: ready);
}

int rowsOf(Db db, String table) =>
    db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;

/// **業務集約だけを数える。** `.blib` が運ぶのはここだけである。
Map<String, int> aggregateCounts(Db db) => {
      for (final table in [
        'books',
        'loans',
        'library_systems',
        'library_memberships',
      ])
        table: rowsOf(db, table),
    };

void main() {
  late Harness harness;

  setUp(() =>
      harness = Harness.create(Contracts.load(), prefix: 'karita-p3-accept-'));
  tearDown(() => harness.dispose());

  group('B1 — 実 DB の完全バックアップ', () {
    test('業務が作った台帳が .blib へ出て、別端末へ復元できる', () async {
      final source = harness.device('windows-a', now: t0);
      final ids = buildLibrary(source);

      // **業務の入口だけで埋まっていること**をまず確かめる。ここが崩れていれば、以降が
      // 測っているのはモック集約である。
      final before = aggregateCounts(source.db);
      expect(before,
          equals({
            'books': 2,
            'loans': 2,
            'library_systems': 2,
            'library_memberships': 1,
          }));
      expect(rowsOf(source.db, 'outbox_events'), equals(8),
          reason: 'システム2・本2・Loan2・遷移1・棚卸1 で 8 件');
      expect(rowsOf(source.db, 'applied_events'), equals(8),
          reason: 'outbox と applied は二つで一組である');
      expect(rowsOf(source.db, 'domain_events'), equals(8));
      expect(ownershipViolations(source.db), isEmpty);

      final path = '${harness.root.path}/from-domain.blib';
      final exported = await source.engine.exportBackup(now: t3, outPath: path);

      // 復元先は**空の別端末**である。
      final target = harness.device('android-b', now: t3);
      expect(rowsOf(target.db, 'books'), equals(0));

      final restored =
          await target.engine.restoreFromBackup(now: t3, path: path);

      expect(restored.counts, equals(exported.manifest['counts']),
          reason: '書き出した件数と復元した件数が違う');
      expect(aggregateCounts(target.db), equals(before),
          reason: '業務が作った集約が全部渡っていない');

      // **同期テーブルと業務記録は運ばない。** outbox は「この端末がまだ上げていないもの」、
      // `applied_events` は「この端末が適用したもの」で、どちらも端末ごとの事実である。
      // `domain_events` は集約から再生成できる監査記録なので入れない。復元先へ持ち込むと、
      // **他端末が既に上げた封筒をもう一度上げる**ことになる。
      for (final table in ['outbox_events', 'applied_events', 'domain_events']) {
        expect(rowsOf(target.db, table), equals(0),
            reason: '$table が .blib に混ざっている');
      }

      // **中身まで見る。** 件数だけだと、列が全部 NULL でも通る。
      final book = target.domain.aggregates
          .read(target.db, entityBook, deterministicId(entityBook, isbnA))!;
      expect(book['title'], equals('達人プログラマー'));
      expect(book['isbn13'], equals(isbnA));

      final loan =
          target.domain.aggregates.read(target.db, entityLoan, ids.readyLoan)!;
      expect(loan['status'], equals('ready_for_pickup'));
      expect(loan['pickup_due_on'], equals('2026-08-13'));

      expect(target.librarySystems.read(minato.id)!.branches, hasLength(2),
          reason: '分館は payload の配列として渡る');
      expect(target.memberships.lastReconciledAtUtc(minato.id), equals(t2));

      // **復元先は作成元の素性を名乗らない。**
      expect(getState(target.db, stateDeviceId), equals(target.deviceId));
      expect(getState(target.db, stateProfileName), equals('android-b'));
    });

    test('復元した台帳の上で業務を続けられる', () {
      // 復元は「新しい正本にする」宣言である。**その後に版が続く**ことまで見ないと、
      // 復元した台帳が読めるだけの死んだ写しになっていても気づけない。
      final source = harness.device('windows-a', now: t0);
      buildLibrary(source);
      final path = '${harness.root.path}/continue.blib';

      return source.engine.exportBackup(now: t3, outPath: path).then((_) async {
        final target = harness.device('android-b', now: t3);
        await target.engine.restoreFromBackup(now: t3, path: path);

        final event = target.loans.update(
            loanId: 'aaaaaaaa-1000-4000-8000-000000000001',
            action: 'return',
            now: t3);
        expect(event.baseVersion, equals(1),
            reason: '復元した集約の版の上に積む');
        expect(event.resultVersion, equals(2));
        expect(event.deviceId, equals(target.deviceId));
      });
    });

    test('レポートが復元の前後で同じものを出す', () {
      // 参照側も渡っていることの確認である。**読取モデルは集約行から組み立てる**ので、
      // 行が渡っていれば同じレポートになる。
      final source = harness.device('windows-a', now: t0);
      buildLibrary(source);
      final path = '${harness.root.path}/report.blib';

      return source.engine.exportBackup(now: t3, outPath: path).then((_) async {
        final expected = source.reporting.buildLoanReport(
            source.librarySystems.load(),
            asOf: '2026-08-07');

        final target = harness.device('android-b', now: t3);
        await target.engine.restoreFromBackup(now: t3, path: path);
        final actual = target.reporting.buildLoanReport(
            target.librarySystems.load(),
            asOf: '2026-08-07');

        expect(actual.borrowedCount, equals(expected.borrowedCount));
        expect(actual.readyForPickupCount, equals(expected.readyForPickupCount));
        expect(actual.areas.map((a) => a.city),
            equals(expected.areas.map((a) => a.city)));
        expect(actual.areas.expand((a) => a.items).map((i) => i.loanId),
            equals(expected.areas.expand((a) => a.items).map((i) => i.loanId)));
      });
    });
  });

  group('B3 — 実 DB の同期世代', () {
    test('業務が作った outbox がそのまま同期を通り、二台目が参加する', () async {
      final first = harness.device('windows-a', now: t0);
      buildLibrary(first);

      // **業務が積んだものを同期がそのまま押す。** ここが繋がっていることが、業務と同期が
      // 同じ台帳を触る形の要である。
      final pushed = await first.engine.run(modeRun, now: t3);
      expect(pushed.generation.state, equals(generationBootstrap),
          reason: '最初の端末が起点を置く');
      expect(pushed.pushed, hasLength(8));
      expect(pushed.stopped, isEmpty);
      expect(countOutbox(first.db, outboxPending), equals(0));

      // 二台目は起点へ復元して**参加**する。世代は進まない。
      final second = harness.device('android-b', now: t3);
      final joined = await second.engine.restoreFromBaseline(now: t3);
      expect(joined.declared, isFalse);
      expect((await harness.store.listBaselines()), hasLength(1));

      expect(second.librarySystems.load().librarySystems.map((s) => s.id),
          equals([chuo.id, minato.id]));
      expect(second.memberships.lastReconciledAtUtc(minato.id), equals(t2));
    });

    test('二台目の業務更新が一台目へ届く', () async {
      final first = harness.device('windows-a', now: t0);
      buildLibrary(first);
      await first.engine.run(modeRun, now: t3);

      final second = harness.device('android-b', now: t3);
      await second.engine.restoreFromBaseline(now: t3);

      // 二台目が返却を記録する。**業務の入口を通る。**
      second.loans.update(
          loanId: 'aaaaaaaa-1000-4000-8000-000000000001',
          action: 'return',
          now: t3);
      await second.engine.run(modeRun, now: t3);

      await first.engine.run(modeRun, now: t3);
      final loan = first.domain.aggregates.read(
          first.db, entityLoan, 'aaaaaaaa-1000-4000-8000-000000000001')!;
      expect(loan['status'], equals('returned'),
          reason: '二台目の業務更新が一台目の台帳に届いていない');
      expect(loan['updated_by_device_id'], equals(second.deviceId));
    });

    test('二端末が常用館とマイページURLを別々に変えても、どちらも消えない', () async {
      // **これが `0011` を入れた理由そのものである。** 同じ集約に入れていたときは、LWW が
      // payload 全体を差し替えるので後勝ちで片方が消えた。行を分けたので両方が残る。
      final first = harness.device('windows-a', now: t0);
      buildLibrary(first);
      await first.engine.run(modeRun, now: t3);

      final second = harness.device('android-b', now: t3);
      await second.engine.restoreFromBaseline(now: t3);

      // 一台目が常用館を、二台目がマイページ URL を、**同期を挟まずに**変える。
      first.librarySettings.setPreferredBranch(
          systemId: minato.id, branchId: 'minato-main', now: t3);
      second.librarySettings.setMypageUrl(
          systemId: minato.id,
          url: 'https://example.invalid/minato',
          checkedOn: '2026-08-07',
          now: t3);

      await first.engine.run(modeRun, now: t3);
      await second.engine.run(modeRun, now: t3);
      await first.engine.run(modeRun, now: t3);

      for (final device in [first, second]) {
        expect(
            device.librarySettings.valueOf(minato.id, settingPreferredBranch),
            equals('minato-main'),
            reason: '${device.deviceId} で常用館が消えている');
        expect(
            device.librarySettings.valueOf(minato.id, settingMypageUrl),
            equals('https://example.invalid/minato'),
            reason: '${device.deviceId} でマイページURLが消えている');
      }
    });

    test('同じ鍵を二端末で変えたときだけ競合になり、LWW が一件へ収束する', () async {
      // **鍵を分けたので、競合が立つのは同じ鍵のときだけである。**
      final first = harness.device('windows-a', now: t0);
      buildLibrary(first);
      await first.engine.run(modeRun, now: t3);

      final second = harness.device('android-b', now: t3);
      await second.engine.restoreFromBaseline(now: t3);

      first.librarySettings.setPreferredBranch(
          systemId: minato.id, branchId: 'minato-main', now: t3);
      second.librarySettings.setPreferredBranch(
          systemId: minato.id, branchId: 'minato-mita', now: t4);

      await first.engine.run(modeRun, now: t4);
      await second.engine.run(modeRun, now: t4);
      await first.engine.run(modeRun, now: t4);

      // 二端末が独立に設定しても**同じ entityId** を指すので競合として立ち、収束する。
      final resolved =
          first.librarySettings.valueOf(minato.id, settingPreferredBranch);
      expect(resolved,
          equals(second.librarySettings.valueOf(minato.id, settingPreferredBranch)),
          reason: '収束していない');
      expect(resolved, equals('minato-mita'), reason: '後から書いた側が残る');
    });

    test('未解決の競合が残ったまま解除が届いても、行は復活しない', () async {
      // **2026-09-15 に踏んだ穴の回帰試験である。** 復元の直後は起点の封筒を引き戻すので、
      // **全集約に競合が1件立つ。** それを片付ける前に相手端末の削除が届くと、同じ run の中で
      // 「tombstone を適用 → 自動解決がローカルの今を発行」の順に走る。**採った側から操作を
      // 決めていなかったため、消したはずの行が「値の無い、消えていない行」として復活していた。**
      final first = harness.device('windows-a', now: t0);
      buildLibrary(first);
      first.librarySettings.setPreferredBranch(
          systemId: minato.id, branchId: 'minato-main', now: t2);
      await first.engine.run(modeRun, now: t3);

      final second = harness.device('android-b', now: t3);
      await second.engine.restoreFromBaseline(now: t3);
      // **競合を片付けないまま**削除を送る。
      first.librarySettings.clearPreferredBranch(systemId: minato.id, now: t4);
      await first.engine.run(modeRun, now: t4);
      await second.engine.run(modeRun, now: t4);

      expect(second.librarySettings.valueOf(minato.id, settingPreferredBranch),
          isNull, reason: '解除された行が復活している');
      expect(
          second.db
              .select('SELECT is_deleted FROM library_settings')
              .single['is_deleted'],
          equals(1));
    });

    test('解除が相手端末へ届く。行は消えない', () async {
      final first = harness.device('windows-a', now: t0);
      buildLibrary(first);
      first.librarySettings.setPreferredBranch(
          systemId: minato.id, branchId: 'minato-main', now: t2);
      await first.engine.run(modeRun, now: t3);

      final second = harness.device('android-b', now: t3);
      await second.engine.restoreFromBaseline(now: t3);
      expect(second.librarySettings.valueOf(minato.id, settingPreferredBranch),
          equals('minato-main'));

      // **復元の直後は全集約に競合が1件立ち、自動解決が走る**（起点の封筒を引き戻すため）。
      // それを片付けてから解除を送る — 未解決の競合が残ったまま tombstone を受けると、
      // **後から走る自動解決が「ローカルの今」を upsert として発行し、消したはずの行が復活する**
      // （`resolveOne` が take=local のとき `is_deleted` を運ばない）。**これは 0011 とは独立の
      // 同期側の穴であり、ここでは踏まないようにして先へ進む。**
      await second.engine.run(modeRun, now: t3);
      await first.engine.run(modeRun, now: t3);
      expect(second.db.select(
              "SELECT 1 FROM conflicts WHERE state = 'open'"), isEmpty);

      first.librarySettings.clearPreferredBranch(systemId: minato.id, now: t4);
      await first.engine.run(modeRun, now: t4);
      await second.engine.run(modeRun, now: t4);

      expect(second.librarySettings.valueOf(minato.id, settingPreferredBranch),
          isNull);
      // **tombstone は行を残す。** 消すと「解除が届いた」と「まだ届いていない」を区別できない。
      expect(
          second.db
              .select('SELECT is_deleted FROM library_settings')
              .single['is_deleted'],
          equals(1));
    });

    test('世代が変わると通常同期が止まる', () async {
      final first = harness.device('windows-a', now: t0);
      buildLibrary(first);
      await first.engine.run(modeRun, now: t3);

      final second = harness.device('android-b', now: t3);
      await second.engine.restoreFromBaseline(now: t3);

      // 二台目が**バックアップを指して**復元する。これは宣言であり、世代が1つ進む。
      final path = '${harness.root.path}/declare.blib';
      await second.engine.exportBackup(now: t3, outPath: path);
      final declared = await second.engine.restoreFromBackup(now: t3, path: path);
      expect(declared.declared, isTrue);
      expect(activeBaseline(await harness.store.listBaselines())!.seq, equals(2));

      // 一台目は止まる。**業務は続けられる** — 止まるのは同期であって台帳ではない。
      await expectLater(
          first.engine.run(modeRun, now: t3),
          throwsA(isA<GenerationChangedError>()
              .having((e) => e.code, 'code', 'generation-changed')));

      final event = first.memberships.completePatrol(systemId: chuo.id, now: t3);
      expect(event.resultVersion, equals(1));
      expect(countOutbox(first.db, outboxPending), equals(1),
          reason: '止まっている間の業務更新は outbox に積まれたまま待つ');

      // 起点へ戻れば**参加**であり、世代は進まない。積んだ分はそのまま流れる。
      await first.engine.restoreFromBaseline(now: t3);
      expect(activeBaseline(await harness.store.listBaselines())!.seq, equals(2),
          reason: '参加は世代を進めない');
      final resumed = await first.engine.run(modeRun, now: t3);
      expect(resumed.generation.state, equals(generationCurrent));
    });

    test('業務の書込みは所有検査を通り続ける', () async {
      // 同期と業務が同じ台帳へ書いた後でも、押印は分かれたままである。
      final first = harness.device('windows-a', now: t0);
      buildLibrary(first);
      await first.engine.run(modeRun, now: t3);

      final second = harness.device('android-b', now: t3);
      await second.engine.restoreFromBaseline(now: t3);
      second.memberships.completePatrol(systemId: chuo.id, now: t3);
      await second.engine.run(modeRun, now: t3);
      await first.engine.run(modeRun, now: t3);

      expect(ownershipViolations(first.db), isEmpty);
      expect(ownershipViolations(second.db), isEmpty);
    });
  });
}
