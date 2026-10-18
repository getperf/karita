/// 初回起動の2択。**順序はエンジンが閉じ、画面は2択を出すだけである。**
///
/// 「新しく始める」は有効世代へ乗るだけ、「バックアップから開始」は
/// 「一覧 → 選択 → 検証 → 起点を公開 → 置換」を1関数で通す。順序を画面へ出すと、順序事故が
/// 画面ごとに起こる。
///
/// 保管先の実物（`dir`）を要るのでここに置く。判定だけの試験は `karita_sync` 側にある。
library;

import 'package:conformance/src/harness.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String t0 = '2026-08-04T09:00:00Z';
const String t1 = '2026-08-05T09:00:00Z';
const String t2 = '2026-08-06T09:00:00Z';

const String bookId = 'aaaaaaaa-0201-4000-8000-000000000001';

void main() {
  late Harness harness;
  late Device windows;

  void seedBook(Device device,
      {required String title, required int base, required String now}) {
    final codec = EnvelopeCodec(harness.contracts);
    device.engine.emitLocal([
      codec.build(
        eventId: harness.uuid(),
        deviceId: device.deviceId,
        createdAtUtc: now,
        entityType: 'book',
        entityId: bookId,
        operation: 'upsert',
        baseVersion: base,
        resultVersion: base + 1,
        payload: {'title': title},
      ),
    ]);
  }

  String? titleOf(Device device) {
    final rows = device.db.select('SELECT title FROM books WHERE id = ?', [bookId]);
    return rows.isEmpty ? null : rows.first['title'] as String?;
  }

  setUp(() {
    harness = Harness.create(Contracts.load(), prefix: 'karita-setup-');
    windows = harness.device('windows-a');
  });
  tearDown(() => harness.dispose());

  test('空の端末は未セットアップで、新しく始めると起点を置く', () async {
    expect(windows.engine.isSetUp, isFalse);

    final resolution = await windows.engine.setupFresh(now: t0);
    expect(resolution.state, equals(generationBootstrap));
    expect(resolution.seq, equals(firstSeq));
    expect((await harness.store.listBaselines()).length, equals(1));
    expect(windows.engine.isSetUp, isTrue);
  });

  test('有効世代の有無は、二台目の2択を出し分ける事実になる', () async {
    final android = harness.device('android-b');
    expect(await android.engine.hasActiveGeneration(), isFalse);

    await windows.engine.setupFresh(now: t0);
    // **二台目から見て「ほかの端末が使っている記録がある」。** 画面はここで合流を先に出す。
    expect(await android.engine.hasActiveGeneration(), isTrue);
    expect(android.engine.isSetUp, isFalse, reason: '問い合わせで端末を使い始めにしない');
  });

  test('二台目が新しく始めると、有効世代へ参加する。世代は進まない', () async {
    await windows.engine.setupFresh(now: t0);
    final android = harness.device('android-b');

    final resolution = await android.engine.setupFresh(now: t1);
    // **参加であって宣言ではない。** 進めると、乗ってきた端末が相手を止める。
    expect(resolution.state, equals(generationAdopt));
    expect(resolution.seq, equals(firstSeq));
    expect((await harness.store.listBaselines()).length, equals(1));
    expect(localGeneration(android.db)?.id, equals(localGeneration(windows.db)?.id));
  });

  test('バックアップから開始すると、選んだ時点が新しい世代の起点になる', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    await windows.engine.run(modeRun, now: t0);
    final exported = await windows.engine.exportBackup(now: t1);

    final android = harness.device('android-b');
    expect(android.engine.isSetUp, isFalse);
    expect(titleOf(android), isNull);

    final outcome = await android.engine.setupFromBackup(exported.backupId, now: t2);

    // 初期セットアップは**宣言**である（新世代を始める）。セットアップ前の全イベント再生を
    // 避けるための取り決めで、相手は世代変更を検出して同じ起点へ戻る。
    expect(outcome.declared, isTrue);
    expect(outcome.seq, equals(firstSeq + 1));
    expect(outcome.backupId, equals(exported.backupId));
    expect(titleOf(android), equals('リファクタリング'));

    // 復元先が作成元の素性を名乗らない。
    expect(getState(android.db, stateDeviceId), equals(android.deviceId));
    expect(localGeneration(android.db)?.seq, equals(firstSeq + 1));

    // 元の端末は世代変更を検出して通常同期を止める。
    await expectLater(windows.engine.run(modeRun, now: t2),
        throwsA(isA<GenerationChangedError>()));
  });

  test('一覧に出ないバックアップは選べない', () async {
    await windows.engine.setupFresh(now: t0);
    final android = harness.device('android-b');
    // 画面に出していないものを id 指定で正本にできると、一覧の意味が無くなる。
    expect(
        () => android.engine
            .setupFromBackup('99999999-0000-4000-8000-000000000009', now: t1),
        throwsA(isA<BackupNotFound>()));
    expect(android.engine.isSetUp, isFalse);
  });

  test('使い始めた端末では初回起動の操作を受け付けない', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    await windows.engine.run(modeRun, now: t0);
    final exported = await windows.engine.exportBackup(now: t1);

    final android = harness.device('android-b');
    await android.engine.setupFresh(now: t1);
    // まだ同期していないが、業務操作は受けている端末。
    seedBook(android, title: '達人プログラマー', base: 0, now: t1);

    // 2択はアプリの最初の1回だけの問いである。二度目に押せると、未送信を抱えた台帳を置換する。
    await expectLater(android.engine.setupFresh(now: t2),
        throwsA(isA<SyncDataError>().having((e) => e.code, 'code', 'setup-already-done')));
    await expectLater(android.engine.setupFromBackup(exported.backupId, now: t2),
        throwsA(isA<SyncDataError>().having((e) => e.code, 'code', 'setup-already-done')));
    expect(titleOf(android), equals('達人プログラマー'));
  });

  test('世代を持たなくても、業務操作を受けた端末は使い始めている', () async {
    // 世代だけを見ると、世代の解決に失敗したまま使われた端末が「未セットアップ」に見え、
    // 初回起動の復元がその台帳を置換できてしまう。
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    expect(localGeneration(windows.db), isNull);
    expect(windows.engine.isSetUp, isTrue);
  });

  test('状態は転送も保管先も読まない', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);

    // 保管先を読めない端末でも件数は見られる。読みに行くと、認可の切れた端末で状態そのものが
    // 出せなくなる。
    final broken = harness.device('linux-c');
    final status = broken.engine.status(now: t1);
    expect(status.state, equals(SyncState.synced));
    expect(status.lastSuccessAt, isNull);

    var mine = windows.engine.status(now: t0);
    expect(mine.state, equals(SyncState.unsent));
    expect(mine.facts.unsent, equals(1));

    await windows.engine.run(modeRun, now: t0);
    mine = windows.engine.status(now: t1);
    expect(mine.state, equals(SyncState.synced));
    expect(mine.lastSuccessAt, equals(t0));
    expect(mine.facts.unsent, equals(0));
  });
}
