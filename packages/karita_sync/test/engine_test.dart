/// エンジンの既定を機械で縛る。
///
/// 「LWW を利用者設定にしない」は画面の話ではなくエンジンの既定の話である。既定が動くと、
/// 同じ競合が端末ごとに違う結末になり、二端末の収束が組み立て側の都合に依存する。宣言だけでは
/// 滲むので、既定値そのものを試験に置く。
library;

import 'dart:io';

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

/// 何も置かれていない転送先。既定の検査に転送は要らない。
class _NoTransport implements TransportPort {
  @override
  String get kind => 'none';
  @override
  Future<String> put(String eventId, String text) async => eventId;
  @override
  Future<List<RemoteEvent>> list({KnownEvent? known}) async => const [];
  @override
  Future<RemoteEvent?> find(String eventId) async => null;
  @override
  Future<void> delete(String remoteId) async {}
}

/// baseline を1つも持たない保管先。世代の解決は別の試験（`generation_test.dart`）で測る。
class _EmptyStore implements BackupStorePort {
  @override
  String get kind => 'none';
  @override
  Future<String> put(String backupId, String path) async => backupId;
  @override
  Future<BackupListing> list() async => const BackupListing();
  @override
  Future<String> get(String backupId, String destPath) async => destPath;
  @override
  Future<int> delete(String backupId) async => 0;
  @override
  Future<String> putBaseline(int seq, String generationId, String path) async =>
      generationId;
  @override
  Future<List<BaselineRef>> listBaselines() async => const [];
  @override
  Future<String> getBaseline(BaselineRef ref, String destPath) async => destPath;
}

/// 起点を1つ持つ保管先。世代の解決が `adopt` に落ちるので、`run` が起点を置きに行かない。
///
/// 起点を置く経路はファイルの DB を要る（`VACUUM INTO` の行き先が要る）。ここで測りたいのは
/// 世代ではなく重なりなので、世代の解決は済んだところから始める。
class _AdoptStore extends _EmptyStore {
  @override
  Future<List<BaselineRef>> listBaselines() async => const [
        BaselineRef(
            seq: 1,
            generationId: '99999999-0000-4000-8000-000000000009',
            remoteId: 'baseline1'),
      ];
}

void main() {
  late DbSession session;

  SyncEngine engine({AutoResolvePolicy? policy}) => SyncEngine(
        session: session,
        profile: 'windows-a',
        deviceId: 'windows-00000000-0000-4000-8000-000000000001',
        transportFor: (_) => _NoTransport(),
        store: _EmptyStore(),
        contracts: Contracts.load(),
        uuid: () => 'dddddddd-0000-4000-8000-000000000001',
        autoResolve: policy ?? AutoResolvePolicy.lww,
      );

  setUp(() {
    session = DbSession.memory();
    migrate(session.db, now: '2026-08-04T09:00:00Z');
  });
  tearDown(() => session.close());

  test('開始記録後と終了後に状態を通知する。失敗時も通知する', () async {
    final states = <SyncState>[];
    late SyncEngine e;
    e = SyncEngine(
      session: session,
      profile: 'windows-a',
      deviceId: 'windows-00000000-0000-4000-8000-000000000001',
      transportFor: (_) => _NoTransport(),
      store: _AdoptStore(),
      contracts: Contracts.load(),
      uuid: () => 'dddddddd-0000-4000-8000-000000000001',
      onStatusChanged: () =>
          states.add(e.status(now: '2026-08-05T09:00:00Z').state),
    );
    await e.run(modePull, now: '2026-08-05T09:00:00Z');
    expect(states, [SyncState.syncing, SyncState.synced]);
    states.clear();
    // 同じ run_id の重複で失敗しても finally の通知は届く。
    await expectLater(
      e.run(modePull, now: '2026-08-05T09:00:00Z'),
      throwsA(isA<Exception>()),
    );
    expect(states, isNotEmpty);
  });

  test('再サインイン後の再開で blocked_auth が送信待ちへ戻り、再ログインの状態を抜ける', () async {
    final e = engine();
    final db = session.db;
    final event = e.codec.build(
      eventId: '10900000-0000-4000-8000-000000000001',
      deviceId: 'windows-00000000-0000-4000-8000-000000000001',
      createdAtUtc: '2026-08-05T09:00:00Z',
      entityType: 'book',
      entityId: 'aaaaaaaa-9001-4000-8000-000000000001',
      operation: 'upsert',
      baseVersion: 0,
      resultVersion: 1,
      payload: {'title': 'v1'},
    );
    transaction(
        db,
        () => appendOutbox(db, event,
            state: outboxBlockedAuth,
            updatedAtUtc: '2026-08-05T09:00:00Z',
            app: appBsync));
    expect(e.status(now: '2026-08-05T09:00:00Z').state,
        equals(SyncState.signInRequired));

    expect(await e.retryBlockedAuth(now: '2026-08-05T09:01:00Z'), equals(1));
    expect(countOutbox(db, outboxBlockedAuth), equals(0));
    expect(countOutbox(db, outboxPending), equals(1));
    expect(e.status(now: '2026-08-05T09:01:00Z').state, equals(SyncState.unsent));
    // 止まった行が無ければ何もしない。
    expect(await e.retryBlockedAuth(now: '2026-08-05T09:02:00Z'), equals(0));
  });

  test('製品の既定は lww に固定である', () {
    // 引数を省いた組み立てが製品の形である。
    final e = SyncEngine(
      session: session,
      profile: 'windows-a',
      deviceId: 'windows-00000000-0000-4000-8000-000000000001',
      transportFor: (_) => _NoTransport(),
      store: _EmptyStore(),
      contracts: Contracts.load(),
      uuid: () => 'dddddddd-0000-4000-8000-000000000001',
    );
    expect(e.autoResolve, equals(AutoResolvePolicy.lww));
    expect(e.autoResolveEnabled, isTrue);
  });

  test('手動競合モードは検証専用の明示的な選択である', () {
    expect(engine(policy: AutoResolvePolicy.manual).autoResolveEnabled, isFalse);
  });

  test('検証ランナーの config は自動解決の切替だけを受ける', () {
    final driver = FixtureDriver(
        Contracts.load(), (name) => DriverProfile(name, engine()));
    driver.config('windows-a', 'conflict.auto_resolve', 'manual');
    expect(driver.profile('windows-a').engine.autoResolveEnabled, isFalse);

    // 綴り間違いを黙って受けると、「設定したつもりで効いていない」まま緑になる。
    expect(() => driver.config('windows-a', 'conflict.autoresolve', 'lww'),
        throwsA(isA<SyncDataError>()));
    expect(() => driver.config('windows-a', 'conflict.auto_resolve', 'yes'),
        throwsA(isA<SyncDataError>()));
  });

  test('メモリ DB ではバックアップと復元を扱えないと明示する', () async {
    // 黙って何もしないと、復元したつもりの試験が古い内容のまま緑になる。
    await expectLater(engine().exportBackup(now: '2026-08-05T09:00:00Z'),
        throwsA(isA<SyncDataError>()));
    expect(() => session.reopen(), throwsA(isA<SyncDataError>()));
  });

  test('run() は push/pull の一手を onProgress へ通知する', () async {
    // **Drive 通信はタイムアウトを持たない。** 待ちが長引いたとき、どの一手で止まっているかが
    // ログに残る唯一の手がかりがこの通知である。
    //
    // **`_AdoptStore` を使う。** 起点が無い `_EmptyStore` だと世代解決が `bootstrap` に倒れ、
    // 起点をファイルの DB へ書きに行く（`publishFirstBaseline`）— ここで測りたいのは push/pull
    // の一手なので、世代の解決は済んだところから始める（既存の「開始記録後と終了後に状態を
    // 通知する」と同じ選択）。
    final steps = <String>[];
    final e = SyncEngine(
      session: session,
      profile: 'windows-a',
      deviceId: 'windows-00000000-0000-4000-8000-000000000001',
      transportFor: (_) => _NoTransport(),
      store: _AdoptStore(),
      contracts: Contracts.load(),
      uuid: () => 'dddddddd-0000-4000-8000-000000000005',
      onProgress: steps.add,
    );
    await e.run(modeRun, now: '2026-08-05T09:00:00Z');
    expect(steps, [
      'run.generation.resolving',
      'run.generation.resolved',
      'run.push.begin',
      'run.push.done',
      'run.pull.list.begin',
      'run.pull.list.done',
      'run.pull.apply.done',
    ]);
  });

  group('転送を要る操作は重ならない', () {
    // 同期だったころ、この保証は型が持っていた — `run` の中に待ち点が無いので、二つの run が
    // 交互に進みようがなかった。非同期にした以上、機械で縛る。**lease では足りない** — lease は
    // プロセス跨ぎの重複送信を守る道具で、同じエンジンの中で重なった二つの操作は同じ lease の
    // 持ち主として振る舞う。

    // **run ごとに違う id を配る。** `sync_runs.run_id` は一意で、固定値のままだと2本目が
    // 制約違反で落ちる — 重なりの試験ではなく id の試験になってしまう。
    var counter = 0;
    String nextUuid() =>
        'dddddddd-0000-4000-8000-${(++counter).toString().padLeft(12, '0')}';

    SyncEngine tracing(List<String> trace, {String label = 'list'}) => SyncEngine(
          session: session,
          profile: 'windows-a',
          deviceId: 'windows-00000000-0000-4000-8000-000000000001',
          transportFor: (_) => _TracingTransport(trace, label: label),
          store: _AdoptStore(),
          contracts: Contracts.load(),
          uuid: nextUuid,
        );

    test('二つ目の run は一つ目が終わるまで始まらない', () async {
      final trace = <String>[];
      final e = tracing(trace);

      // **await せずに二つ同時に始める。** 直列に呼べば重なりようがなく、何も測れない。
      await Future.wait([
        e.run(modePull, now: '2026-08-05T09:00:00Z'),
        e.run(modePull, now: '2026-08-05T09:00:01Z'),
      ]);

      // 交互に進んでいれば in,in,out,out になる。
      expect(trace, ['list:in', 'list:out', 'list:in', 'list:out']);
    });

    test('待たされた run も取りこぼされない', () async {
      final trace = <String>[];
      final e = tracing(trace);
      final results = await Future.wait([
        e.run(modePull, now: '2026-08-05T09:00:00Z'),
        e.run(modePull, now: '2026-08-05T09:00:01Z'),
        e.run(modePull, now: '2026-08-05T09:00:02Z'),
      ]);
      expect(results, hasLength(3));
      expect(trace.where((entry) => entry == 'list:in'), hasLength(3));
    });

    test('走り終われば待ち行列は空へ戻る', () async {
      // 鎖を切らないと、次の呼び出しが完了済みの Future を1つ余計に待つ。
      final e = tracing(<String>[]);
      await e.run(modePull, now: '2026-08-05T09:00:00Z');
      expect(e.debugIdle, isTrue);
    });

    test('落ちた run も待ち行列を空けて出る', () async {
      // finally で開けないと、一度の失敗で以後すべての操作が永久に待つ。
      final e = SyncEngine(
        session: session,
        profile: 'windows-a',
        deviceId: 'windows-00000000-0000-4000-8000-000000000001',
        transportFor: (_) => _NoTransport(),
        store: _AdoptStore(),
        contracts: Contracts.load(),
        uuid: nextUuid,
      );
      await expectLater(e.exportBackup(now: '2026-08-05T09:00:00Z'),
          throwsA(isA<SyncDataError>()));
      expect(e.debugIdle, isTrue);
      // 続く操作が待たされずに通る。
      await e.run(modePull, now: '2026-08-05T09:00:01Z');
    });
  });

  group('前面同期の短縮（2026-10-08）', () {
    const gen = '99999999-0000-4000-8000-000000000009';
    var counter = 0;
    String nextUuid() =>
        'eeeeeeee-0000-4000-8000-${(++counter).toString().padLeft(12, '0')}';

    SyncEngine engineWith(TransportPort transport, BackupStorePort store) => SyncEngine(
          session: session,
          profile: 'windows-a',
          deviceId: 'windows-00000000-0000-4000-8000-000000000001',
          transportFor: (_) => transport,
          store: store,
          contracts: Contracts.load(),
          uuid: nextUuid,
        );

    test('世代を読めない（通信断）と、送りも受けもしない', () async {
      // 端末は世代 0007 を持っている。保管先が 0008 へ進んでいても、読めなければ分からない。
      setLocalGeneration(session.db, gen, 1);
      final trace = <String>[];
      final e = engineWith(_TracingTransport(trace),
          _UnreadableStore(SyncDataError('届きません', code: 'transport-io')));

      await expectLater(e.run(modeRun, now: '2026-10-08T09:00:00Z'),
          throwsA(isA<SyncDataError>()));
      // **一覧も送信も起きていない。** 旧世代の名前で書かない。
      expect(trace, isEmpty);
      expect(session.db.select('SELECT * FROM sync_runs'), isEmpty);
    });

    test('認可切れは先へ進める（再サインインの状態へ届かせる）', () async {
      setLocalGeneration(session.db, gen, 1);
      final trace = <String>[];
      final e = engineWith(_TracingTransport(trace),
          _UnreadableStore(TransportAuthError('認可されません')));

      await e.run(modeRun, now: '2026-10-08T09:00:00Z');
      expect(trace, contains('list:in'));
    });

    test('何も無い run の行は最新の1つだけ残る', () async {
      final e = engineWith(_NoTransport(), _AdoptStore());
      await e.run(modeRun, now: '2026-10-08T09:00:00Z');
      await e.run(modeRun, now: '2026-10-08T09:00:30Z');
      final last = await e.run(modeRun, now: '2026-10-08T09:01:00Z');

      expect(last.idle, isTrue);
      expect(last.ledgerChanged, isFalse);
      final rows = session.db.select('SELECT run_id FROM sync_runs');
      expect([for (final row in rows) row['run_id']], [last.runId]);
      // 最終同期の時刻は最新の run のものである。
      expect(lastSuccessAt(session.db), '2026-10-08T09:01:00Z');
    });

    test('一覧へ既知の eventId を渡す（適用済み・保留中・競合済み）', () async {
      transaction(session.db, () {
        recordApplied(session.db,
            eventId: 'applied-1',
            entityType: 'book',
            entityId: 'b1',
            resultVersion: 1,
            payloadHash: 'h',
            origin: originLocal,
            appliedAtUtc: '2026-10-08T09:00:00Z');
      });
      final transport = _KnownCapture();
      await engineWith(transport, _AdoptStore())
          .run(modeRun, now: '2026-10-08T09:00:00Z');

      expect(transport.known, isNotNull);
      expect(transport.known!('applied-1'), isTrue);
      expect(transport.known!('unseen-1'), isFalse);
    });
  });

  group('空にしてやり直す（restoreEmpty）', () {
    // 置換の対象は台帳ファイルなので、メモリ DB ではなくファイルの DB を要る
    // （[SyncEngine._requireDbPath]、他の復元系と同じ制約）。
    late Directory work;
    late DbSession fileSession;

    setUp(() {
      work = Directory.systemTemp.createTempSync('karita-reset-test-');
      fileSession =
          DbSession.open('${work.path}${Platform.pathSeparator}library.db');
      migrate(fileSession.db, now: '2026-08-04T09:00:00Z');
    });
    tearDown(() {
      fileSession.close();
      if (work.existsSync()) work.deleteSync(recursive: true);
    });

    SyncEngine fileEngine() => SyncEngine(
          session: fileSession,
          profile: 'windows-a',
          deviceId: 'windows-00000000-0000-4000-8000-000000000001',
          transportFor: (_) => _NoTransport(),
          store: _EmptyStore(),
          contracts: Contracts.load(),
          uuid: () => 'dddddddd-0000-4000-8000-000000000002',
        );

    test('業務データを消し、新しい世代を宣言する', () async {
      final e = fileEngine();
      e.emitLocal([
        e.codec.build(
          eventId: 'eeeeeeee-0000-4000-8000-000000000001',
          deviceId: e.deviceId,
          createdAtUtc: '2026-08-05T09:00:00Z',
          entityType: 'book',
          entityId: '11111111-0000-4000-8000-000000000001',
          operation: 'upsert',
          baseVersion: 0,
          resultVersion: 1,
          payload: {'title': '消えるはずの本'},
        ),
      ]);
      expect(fileSession.db.select('SELECT 1 FROM books'), isNotEmpty);

      final outcome = await e.restoreEmpty(now: '2026-08-05T10:00:00Z');

      // 宣言である（起点を新しく置いた）。参加（baseline への復元）ではない。
      expect(outcome.declared, isTrue);
      expect(outcome.counts['books'] ?? 0, 0);
      expect(fileSession.db.select('SELECT 1 FROM books'), isEmpty);
      expect(localGeneration(fileSession.db)?.id, outcome.generationId);
    });

    test('主要な一手を onProgress へ通知する', () async {
      final steps = <String>[];
      final e = SyncEngine(
        session: fileSession,
        profile: 'windows-a',
        deviceId: 'windows-00000000-0000-4000-8000-000000000001',
        transportFor: (_) => _NoTransport(),
        store: _EmptyStore(),
        contracts: Contracts.load(),
        uuid: () => 'dddddddd-0000-4000-8000-000000000006',
        onProgress: steps.add,
      );

      await e.restoreEmpty(now: '2026-08-05T09:00:00Z');

      expect(steps, [
        'reset.empty_db.begin',
        'reset.empty_db.done',
        'restore.precheck.begin',
        'restore.precheck.done',
        'restore.generation.seq.resolving',
        'restore.baseline.publish.begin',
        'restore.baseline.publish.done',
        'restore.replace.begin',
        'restore.replace.done',
      ]);
    });

    test('メモリ DB では扱えないと明示する', () async {
      final memory = DbSession.memory();
      migrate(memory.db, now: '2026-08-04T09:00:00Z');
      final e = SyncEngine(
        session: memory,
        profile: 'windows-a',
        deviceId: 'windows-00000000-0000-4000-8000-000000000001',
        transportFor: (_) => _NoTransport(),
        store: _EmptyStore(),
        contracts: Contracts.load(),
        uuid: () => 'dddddddd-0000-4000-8000-000000000003',
      );
      await expectLater(e.restoreEmpty(now: '2026-08-05T09:00:00Z'),
          throwsA(isA<SyncDataError>()));
    });
  });
}

/// 一覧の出入りを記録し、**途中で必ず一度譲る**転送。
///
/// 譲らないと、非同期の口でも実際には切れ目が生まれず、重なりを作れない。試験が測りたいのは
/// 「切れ目があっても重ならないこと」なので、切れ目の方を確実に作る。
class _TracingTransport implements TransportPort {
  final List<String> trace;
  final String label;

  _TracingTransport(this.trace, {this.label = 'list'});

  @override
  String get kind => 'none';

  @override
  Future<List<RemoteEvent>> list({KnownEvent? known}) async {
    trace.add('$label:in');
    await Future<void>.delayed(Duration.zero);
    trace.add('$label:out');
    return const [];
  }

  @override
  Future<String> put(String eventId, String text) async => eventId;
  @override
  Future<RemoteEvent?> find(String eventId) async => null;
  @override
  Future<void> delete(String remoteId) async {}
}

/// baseline の一覧で必ず落ちる保管先。**落ち方（理由）を差し替える。**
class _UnreadableStore extends _EmptyStore {
  final SyncDataError error;
  _UnreadableStore(this.error);

  @override
  Future<List<BaselineRef>> listBaselines() async => throw error;
}

/// 一覧に渡された既知の判定を覚えておく転送。
class _KnownCapture extends _NoTransport {
  KnownEvent? known;

  @override
  Future<List<RemoteEvent>> list({KnownEvent? known}) async {
    this.known = known;
    return const [];
  }
}
