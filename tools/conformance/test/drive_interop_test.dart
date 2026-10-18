/// **P2c の受入③ — Python ↔ Dart が実 Drive を挟んで往復する。**
///
/// `blib_interop_test.dart` はローカルの `.blib` を手渡しするだけで、共有される名前空間を
/// 通らない。ここが足すのは**その名前空間そのもの** — 同じ Google アカウントの同じ
/// `appDataFolder` に、Python が封筒を置き、Dart がそれを拾い、逆向きも成立することである。
///
/// 通るのは**両側とも製品の経路**である。Python は `bsync sync push` / `pull`、Dart は
/// `SyncEngine.run` で、片方だけの裏口を作らない。転送も保管先も差し替えるのは**場所だけ**で、
/// 「保管先は転送先と同じ場所」という不変条件は保つ（`Harness.create` がそれを強制する）。
///
/// ## 実データの上で走ることの意味
///
/// **`appDataFolder` は OAuth クライアントの Cloud プロジェクト単位である。** `karita-core`
/// も `bsync Desktop personal` も同じプロジェクトにあるので、**同じ場所を見る** — それが
/// この受入を成立させている当のものであり、同時に、ここが**ユーザの実データと同じ場所**で
/// あることを意味する。
///
/// 有効世代は `baseline-<seq>-<generation-id>.blib` の最大 `seq` で決まり、単調に進む。
/// だから、この試験が世代を宣言している間、**同じ場所を見ている実端末は `generation-changed`
/// で止まる。** 避ける道は無い — 参加（既存世代へ乗る）を選べば、今度は試験の封筒が実世代の
/// 名前空間に入り、実端末がそれを実ライブラリへ取り込む。**どちらかには必ず触る。**
///
/// そこで、
///
/// - **宣言する側を採る。** 実データの中身を汚さない方である。封筒は試験世代にしか置かれない
/// - **書いたものは自分で消す。** 起点・封筒・バックアップを、この run が作った remote id
///   だけで消す。名前で拾って消さない — 同居している他のものに当たる
/// - **始める前の有効世代を控え、終わったら戻っていることを確かめる。** 戻っていなければ
///   **消し残した remote id を名指しで出す。** 黙って緑にすると、実端末が止まったままになる
///
/// 落ちても残るのは起点1つと封筒数個で、どれも手で消せる。**それが復旧の全部である。**
///
/// 正本（`../book-sync-model`）・`uv`・token のどれかが無ければ**この試験だけを飛ばす。**
@Tags(['drive'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:conformance/src/harness.dart';
import 'package:conformance/src/repo.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String t0 = '2026-09-02T09:00:00Z';
const String t1 = '2026-09-02T09:10:00Z';
const String t2 = '2026-09-02T09:20:00Z';
const String t3 = '2026-09-02T09:30:00Z';

/// fixture `03-concurrent-loan` が step 0 で作る Book と Loan。
const String book1 = 'aaaaaaaa-0001-4000-8000-000000000001';
const String loan1 = 'aaaaaaaa-0002-4000-8000-000000000002';

/// Dart 側がこの試験で作る Book。**両側の名前空間で衝突しない値を選ぶ。**
const String dartBook = 'aaaaaaaa-0202-4000-8000-000000000001';

/// 凍結した参照実装の場所。**karita-core の隣にある前提である。**
Directory get modelRoot => Directory(
    '${Repo.coreRoot().parent.path}${Platform.pathSeparator}book-sync-model');

String nowUtc() =>
    '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

/// 飛ばす理由。**3つとも要る** — Dart 側の認可、Python 側の CLI、正本の fixture である。
String? skipReason() {
  final AppPaths paths;
  try {
    paths = WindowsAppPaths.resolve();
  } on SyncDataError catch (exc) {
    return '既定のデータ領域を決められない: ${exc.message}';
  }
  if (!File(paths.credentialsPath).existsSync()) {
    return '資格情報が無い（${paths.credentialsPath}）';
  }
  if (TokenStore(paths.tokenPath).load() == null) {
    return 'token が無い（dart run drive_probe:drive_probe login で認可する）';
  }
  if (!modelRoot.existsSync()) {
    return '正本 (${modelRoot.path}) がありません。言語間の往復は測れません。';
  }
  final probe = Process.runSync('uv', ['--version'], runInShell: true);
  if (probe.exitCode != 0) {
    return 'uv を実行できません。Python 側の CLI を呼べません。';
  }
  // Python 側も同じ appDataFolder へ行ける資格情報と token を持っていないと、往復にならない。
  final blibHome = Platform.environment['LOCALAPPDATA'];
  if (blibHome == null) return 'LOCALAPPDATA が無い';
  final sep = Platform.pathSeparator;
  final pyToken = '$blibHome${sep}blib${sep}profiles${sep}windows-a${sep}token.json';
  if (!File(pyToken).existsSync()) {
    return 'Python 側の token が無い（$pyToken）。'
        'uv run bsync --profile windows-a auth login で認可する';
  }
  return null;
}

void main() {
  final skip = skipReason();
  if (skip != null) {
    // 飛ばした理由は必ず見えるところへ出す。黙って 0 件成功にしない。
    print('実 Drive の相互運用を飛ばす: $skip');
  }

  late AppPaths paths;
  late GoogleOAuth oauth;
  late RestDriveClient client;
  late DriveBackupStore store;
  late Directory work;
  late Directory pyHome;
  late String pyCredentials;

  /// この試験を始める前の有効世代。**戻すべき状態である。**
  BaselineRef? before;

  /// この run が Drive に作った remote id。**消すのはここにあるものだけ。**
  final createdBaselines = <String>[];
  final createdBackups = <String>[];

  /// Python が宣言した世代。封筒の名前空間であり、片付けの範囲でもある。
  String? testGeneration;

  final sep = Platform.pathSeparator;
  String path(Directory base, String name) => '${base.path}$sep$name';

  /// Python 側の CLI。**製品の経路をそのまま呼ぶ。**
  ///
  /// 入出力を UTF-8 に固定する。Windows の既定コードページ（cp932）のままだと、CLI が返す
  /// 日本語の JSON が化けて読めなくなる。
  ProcessResult bsync(List<String> args, {bool allowFailure = false}) {
    final result = Process.runSync(
      'uv',
      ['run', 'bsync', ...args],
      workingDirectory: modelRoot.path,
      environment: {'BLIB_HOME': pyHome.path, 'PYTHONIOENCODING': 'utf-8'},
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (!allowFailure) {
      expect(result.exitCode, equals(0),
          reason: 'bsync ${args.join(' ')} が失敗しました:\n'
              '${result.stderr}\n${result.stdout}');
    }
    return result;
  }

  Map<String, Object?> bsyncJson(List<String> args) =>
      jsonDecode(bsync(args).stdout as String) as Map<String, Object?>;

  /// Dart 側の台帳を数える。
  int rows(Db db, String table) =>
      db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;

  /// **件数だけでは往復を測れない。** 中身が渡ったことまで見る。
  String? bookTitle(Db db, String id) {
    final found = db.select('SELECT title FROM books WHERE id = ?', [id]);
    return found.isEmpty ? null : found.first['title'] as String?;
  }

  String? loanStatus(Db db, String id) {
    final found = db.select('SELECT status FROM loans WHERE id = ?', [id]);
    return found.isEmpty ? null : found.first['status'] as String?;
  }

  /// Python 側の DB を直接読む。**判定の材料であって、書き込みはしない。**
  T pyRead<T>(String profile, T Function(Db db) read) {
    final db = SqliteDb.open(
        '${pyHome.path}${sep}profiles$sep$profile${sep}library.db');
    try {
      return read(db);
    } finally {
      db.close();
    }
  }

  int pyRows(String profile, String table) =>
      pyRead(profile, (db) => rows(db, table));

  String? pyBookTitle(String id) =>
      pyRead('windows-a', (db) => bookTitle(db, id));

  setUpAll(() async {
    if (skip != null) return;
    paths = WindowsAppPaths.resolve();
    oauth = GoogleOAuth(loadDesktopClient(paths.credentialsPath));
    client = RestDriveClient(
      tokens: GoogleAccessTokenProvider(
        store: TokenStore(paths.tokenPath),
        oauth: oauth,
        now: nowUtc,
      ),
    );
    store = DriveBackupStore(client);

    // **始める前の状態を控える。** 片付けが済んだかどうかは、これと突き合わせて判定する。
    before = activeBaseline(await store.listBaselines());
    print('始める前の有効世代: '
        '${before == null ? "無し" : "${before!.seq} / ${before!.generationId}"}');

    work = Directory.systemTemp.createTempSync('karita-drive-interop-');
    pyHome = Directory(path(work, 'pyhome'))..createSync(recursive: true);

    // **両側が同じ Desktop クライアントを使う。** `appDataFolder` はアプリ（Cloud
    // プロジェクト）単位なので、同じ場所を見るのはこれが理由である。
    //
    // **token と credentials は対で揃っていなければ refresh が通らない**（揃っていないと
    // `unauthorized_client` で落ちる）。だから token は「その資格情報で取った方」を写す —
    // 実 bsync の `windows-a` がそれである。
    final blibHome = '${Platform.environment['LOCALAPPDATA']}${sep}blib';
    pyCredentials = paths.credentialsPath;
    final pyProfile = Directory(path(pyHome, 'profiles${sep}windows-a'))
      ..createSync(recursive: true);
    File('$blibHome${sep}profiles${sep}windows-a${sep}token.json')
        .copySync('${pyProfile.path}${sep}token.json');
  });

  tearDownAll(() async {
    if (skip != null) return;

    // **自分が作ったものだけを消す。** 順序は封筒 → 起点 → バックアップ。起点を先に消すと、
    // 途中で落ちたときに封筒だけが宙に浮く。
    final failed = <String>[];

    if (testGeneration != null) {
      try {
        final transport = DriveTransport(client, testGeneration!);
        for (final event in await transport.list()) {
          for (final id in [event.remoteId, ...event.duplicateRemoteIds]) {
            try {
              await client.delete(id);
            } on SyncDataError {
              failed.add('封筒 $id');
            }
          }
        }
      } on SyncDataError catch (exc) {
        failed.add('封筒の一覧が引けなかった（${exc.message}）');
      }
    }

    for (final remoteId in createdBaselines) {
      try {
        await client.delete(remoteId);
      } on SyncDataError {
        failed.add('起点 $remoteId');
      }
    }
    for (final backupId in createdBackups) {
      try {
        await store.delete(backupId);
      } on BackupError {
        failed.add('バックアップ $backupId');
      }
    }

    // **戻ったことを確かめる。** ここが合わなければ、実端末は止まったままである。
    try {
      final after = activeBaseline(await store.listBaselines());
      final restored = (before == null && after == null) ||
          (before != null &&
              after != null &&
              after.seq == before!.seq &&
              after.generationId == before!.generationId);
      if (!restored) {
        failed.add('有効世代が戻っていない（いま '
            '${after == null ? "無し" : "${after.seq}/${after.generationId}"}、'
            '始める前 '
            '${before == null ? "無し" : "${before!.seq}/${before!.generationId}"}）');
      }
    } on SyncDataError catch (exc) {
      failed.add('有効世代を確かめられなかった（${exc.message}）');
    }

    if (failed.isNotEmpty) {
      // **黙って緑にしない。** 消し残しは実端末を止めたままにする。
      stderr.writeln('■ 実 Drive に消し残しがある。手で消すこと:');
      for (final line in failed) {
        stderr.writeln('  - $line');
      }
      stderr.writeln('  世代: ${testGeneration ?? "（宣言前）"}');
    }

    client.close();
    oauth.close();
    try {
      work.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows では WAL のハンドルが残って消せないことがある。判定には関わらない。
    }
    expect(failed, isEmpty, reason: '片付けが済んでいない');
  });

  test('Python が置いた封筒を Dart が実 Drive 越しに拾い、逆向きも成立する', () async {
    // ---- Python: 台帳を作り、実 Drive へ向ける ----
    bsync(['init', 'db', '--profile', 'windows-a', '--now', t0]);
    bsync(['--profile', 'windows-a', 'config', 'set', 'transport', 'drive']);
    bsync(['config', 'set', 'google.credentials_json', pyCredentials]);
    // ページ跨ぎを通常の経路にする。**実 Drive で 100 件を積まないため。**
    bsync(['--profile', 'windows-a', 'config', 'set', 'transport.page_size', '2']);

    final fixture = [
      modelRoot.path, 'contracts', 'fixtures', 'sync', '03-concurrent-loan.json',
    ].join(sep);
    bsync(['--profile', 'windows-a', 'admin', 'fixture', 'seed', '--case', fixture,
      '--step', '0', '--now', t0, '--json']);
    expect(pyRows('windows-a', 'books'), greaterThan(0),
        reason: 'fixture が Python 側に入っていない');

    // ---- Python: 新しい世代を宣言する ----
    //
    // **参加ではなく宣言を選ぶ。** 参加すると封筒が実世代の名前空間へ入り、実端末が試験の
    // データを取り込む。宣言なら封筒は試験世代にしか置かれない。片付けはこの後の
    // `tearDownAll` が持つ。
    final local = path(work, 'declare.blib');
    bsync(['--profile', 'windows-a', 'export', '--out', local, '--now', t0, '--json']);
    bsync(['--profile', 'windows-a', 'import', local, '--yes', '--now', t1, '--json']);

    final generation = bsyncJson(['--profile', 'windows-a', 'admin', 'generation',
      '--json']);
    final active = generation['active'] as Map<String, Object?>;
    testGeneration = active['generation_id'] as String;
    final activeSeq = active['seq'] as int;

    expect(testGeneration, isNot(equals(before?.generationId)),
        reason: '宣言が新しい世代を作っていない');
    expect(activeSeq, equals((before?.seq ?? 0) + 1),
        reason: '宣言は世代を1つだけ進める');
    print('この run の世代: $activeSeq / $testGeneration');

    // 宣言が Drive へ置いた起点を控える。**片付ける対象である。**
    final declared = (await store.listBaselines())
        .where((ref) => ref.generationId == testGeneration)
        .toList();
    expect(declared, hasLength(1), reason: '宣言した起点が実 Drive に1つだけ在るはず');
    createdBaselines.add(declared.single.remoteId);

    // ---- Python: 封筒を実 Drive へ押す ----
    bsync(['--profile', 'windows-a', 'admin', 'fixture', 'seed', '--case', fixture,
      '--step', '1', '--now', t1, '--json']);
    final pushed = bsyncJson(['--profile', 'windows-a', 'sync', 'push',
      '--now', t1, '--json']);
    expect((pushed['pushed'] as List), isNotEmpty,
        reason: 'Python が封筒を1つも押していない');

    final onDrive = await DriveTransport(client, testGeneration!).list();
    expect(onDrive, isNotEmpty, reason: '押した封筒が実 Drive の一覧に出てこない');

    // ---- Dart: 同じ appDataFolder に参加して拾う ----
    //
    // **転送先と保管先を揃えて差し替える。** 場所が `appDataFolder` になるだけで、組み立ての
    // 手順は `Harness` の既定と同じものを通る。
    final harness = Harness.create(
      Contracts.load(),
      prefix: 'karita-drive-interop-dart-',
      store: store,
      transportFor: (generationId) => DriveTransport(client, generationId),
    );
    try {
      final device = harness.device('android-b', now: t2);

      // **参加は起点への復元である。** 封筒だけを拾っても、fixture の版の連なり
      // （loan v1 → v2）は受信側に v1 が無ければ繋がらない。二台目が有効世代に乗る本来の
      // 経路が `restoreFromBaseline` で、**世代を進めない。**
      //
      // ここが通ると、**Python が実 Drive へ載せた `.blib` を Dart が取り出して復元した**
      // ことになる。`blib_interop_test` がローカルで測っているものが、resumable upload と
      // チャンク download を挟んで成立している。
      final joined = await device.engine.restoreFromBaseline(now: t2);
      expect(joined.declared, isFalse, reason: '参加は宣言ではない。世代を進めない');
      expect(rows(device.db, 'books'), equals(1),
          reason: 'Python の起点が Dart 側に復元されていない');
      expect(bookTitle(device.db, book1), equals('達人プログラマー'),
          reason: '実 Drive を通った .blib の中身が壊れている');
      expect(loanStatus(device.db, loan1), equals('borrowed'),
          reason: '起点は step 0 の時点であるはず');

      final afterJoin = activeBaseline(await store.listBaselines());
      expect(afterJoin!.seq, equals(activeSeq), reason: '参加が世代を進めている');

      // ---- Dart: Python が押した封筒を拾う ----
      final run = await device.engine.run(modeRun, now: t2);
      expect(run.generation.state, equals(generationCurrent),
          reason: '起点へ復元した端末はもうその世代に乗っている');
      expect(run.generation.generationId, equals(testGeneration),
          reason: 'Dart が Python の世代に乗っていない');
      expect(run.pullError, isNull, reason: '取り込みが失敗している');

      // **Python の step 1 が実 Drive を越えて届いた。** 版が v1 から v2 へ進んでいる。
      expect(loanStatus(device.db, loan1), equals('returned'),
          reason: 'Python が押した封筒が Dart の台帳に届いていない');

      // ---- Dart: 自分の封筒を押す ----
      final codec = EnvelopeCodec(harness.contracts);
      device.engine.emitLocal([
        codec.build(
          eventId: harness.uuid(),
          deviceId: device.deviceId,
          createdAtUtc: t2,
          entityType: 'book',
          entityId: 'aaaaaaaa-0202-4000-8000-000000000001',
          operation: 'upsert',
          baseVersion: 0,
          resultVersion: 1,
          payload: {'title': 'Dart から実 Drive へ', 'authors': ['karita-core']},
        ),
      ]);
      final sent = await device.engine.run(modePush, now: t3);
      expect(sent.pushed, hasLength(1), reason: 'Dart が封筒を押していない');
      expect(sent.stopped, isEmpty, reason: '押せずに止まった封筒がある');

      // ---- Python: Dart の封筒を拾う ----
      final beforePull = pyRows('windows-a', 'books');
      bsyncJson(['--profile', 'windows-a', 'sync', 'pull', '--now', t3, '--json']);

      expect(pyRows('windows-a', 'books'), equals(beforePull + 1),
          reason: 'Dart が押した封筒が Python の台帳に届いていない');
      expect(pyBookTitle(dartBook), equals('Dart から実 Drive へ'),
          reason: 'Dart が書いた本文が Python 側で読めていない');

      // **両側が同じものを見ている。** 往復が閉じたということである。
      expect(pyRows('windows-a', 'books'), equals(rows(device.db, 'books')),
          reason: '往復の後で両側の件数が揃っていない');
    } finally {
      harness.dispose();
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));
}
