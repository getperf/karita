/// 状態の導出。**組合せは日常的に起こるので、どれを見せるかを機械で縛る。**
///
/// 前半は判定（`deriveState`）だけを純粋な関数として測り、事実の組合せを DB 無しで全て通す。
/// 後半は読み取り（`readSyncFacts`）を実 SQLite に対して測る — 「その事実をどこから読むか」も
/// 規則の一部であり、宣言だけでは滲む。
library;

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String _localDevice = 'windows-00000000-0000-4000-8000-000000000001';
const String _remoteDevice = 'android-00000000-0000-4000-8000-000000000002';
const String _bookId = 'aaaaaaaa-9001-4000-8000-000000000001';

/// 全ての停止条件が同時に立っている事実。優先順の試験はここから1つずつ外していく。
const SyncFacts _allWrong = SyncFacts(
  unsent: 3,
  blockedAuth: 1,
  expiredLeases: 1,
  schemaPending: 1,
  gapPending: 2,
  stalledGaps: 1,
  openConflicts: 1,
  dbSchemaAhead: true,
  running: true,
  offline: true,
  doctorFailed: true,
);

void main() {
  group('優先順', () {
    test('宣言順のとおりに、上から順で消えていく', () {
      // 全部立った状態から、上に来るものだけを1つずつ落とす。**残りは触らない。**
      // 期待列が `SyncState.values` と同じ並びになることが、表と実装の一致である。
      final peeled = <SyncFacts>[
        _allWrong,
        // アプリ更新の根拠を両方落とす。受理集合の外の封筒と、新しすぎる DB。
        _copy(_allWrong, schemaPending: 0, dbSchemaAhead: false),
        _copy(_allWrong, schemaPending: 0, dbSchemaAhead: false, blockedAuth: 0),
        _copy(_allWrong,
            schemaPending: 0,
            dbSchemaAhead: false,
            blockedAuth: 0,
            stalledGaps: 0,
            openConflicts: 0,
            doctorFailed: false),
        _copy(_allWrong,
            schemaPending: 0,
            dbSchemaAhead: false,
            blockedAuth: 0,
            stalledGaps: 0,
            openConflicts: 0,
            doctorFailed: false,
            running: false),
        _copy(_allWrong,
            schemaPending: 0,
            dbSchemaAhead: false,
            blockedAuth: 0,
            stalledGaps: 0,
            openConflicts: 0,
            doctorFailed: false,
            running: false,
            offline: false),
        _copy(_allWrong,
            schemaPending: 0,
            dbSchemaAhead: false,
            blockedAuth: 0,
            stalledGaps: 0,
            openConflicts: 0,
            doctorFailed: false,
            running: false,
            offline: false,
            unsent: 0),
      ];
      expect([for (final facts in peeled) deriveState(facts)],
          equals(SyncState.values));
    });

    test('7状態がすべて到達可能で、条件は互いに素ではない', () {
      // 到達不能な状態を宣言に残さない。**7つと決めた以上、7つとも出る。**
      final reached = {for (final facts in _oneEach.values) deriveState(facts)};
      expect(reached, equals(SyncState.values.toSet()));
      _oneEach.forEach((state, facts) {
        expect(deriveState(facts), equals(state), reason: '$state の単独条件');
      });
    });
  });

  group('個々の規則', () {
    test('アプリ更新は、再ログインでも復元でも解けないので最初に出る', () {
      // 受理集合の外の封筒は、認可を戻しても相手が新しい版で送り続ける。他を先に案内すると、
      // 済ませた後で同じ場所へ戻る。
      expect(
          deriveState(const SyncFacts(schemaPending: 1, blockedAuth: 1, unsent: 1)),
          equals(SyncState.appUpdateRequired));
      // DB が同梱のマイグレーションより新しいのも同じ意味である。
      expect(deriveState(const SyncFacts(dbSchemaAhead: true)),
          equals(SyncState.appUpdateRequired));
    });

    test('DB が古い・チェックサムが食い違うのは要対応であって、アプリ更新ではない', () {
      // 更新して直るのは「アプリが古い」場合だけである。逆向きを更新と案内すると、
      // 利用者は直らない操作を繰り返す。
      expect(deriveState(const SyncFacts(dbSchemaBehind: true)),
          equals(SyncState.needsAttention));
      expect(deriveState(const SyncFacts(checksumMismatch: true)),
          equals(SyncState.needsAttention));
    });

    test('再ログインは要対応より先に出る', () {
      // 認可を失っている間は取り込みが動かない。完全復元や手修正を案内する根拠が揃わない。
      expect(deriveState(const SyncFacts(blockedAuth: 1, openConflicts: 1)),
          equals(SyncState.signInRequired));
    });

    test('要対応は回線より先に出る', () {
      // 要対応は DB に記録された事実で、回線が戻っても消えない。オフラインを先に出すと
      // 「繋がれば直る」と読まれる。
      expect(deriveState(const SyncFacts(openConflicts: 1, offline: true)),
          equals(SyncState.needsAttention));
    });

    test('走行中の run は回線の観測より先に出る', () {
      // run はいま起きていることであり、回線は結果ではなく前提にすぎない。
      expect(deriveState(const SyncFacts(running: true, offline: true, unsent: 1)),
          equals(SyncState.syncing));
    });

    test('失効した lease だけでは状態が変わらない', () {
      // 送信中にプロセスが落ちれば正常に起こる。次の claimOutbox が拾い直す。要対応にすると
      // 正常な回復の途中が毎回赤くなる。
      expect(deriveState(const SyncFacts(unsent: 1, expiredLeases: 1)),
          equals(SyncState.unsent));
      expect(const SyncFacts(expiredLeases: 3).attention, isFalse);
    });

    test('猶予内の gap だけでは状態が変わらない', () {
      // 先行が未着なのは正常な途中状態である。ここを要対応にすると通常の往復が赤くなる。
      expect(deriveState(const SyncFacts(gapPending: 2)), equals(SyncState.synced));
      expect(deriveState(const SyncFacts(gapPending: 2, stalledGaps: 1)),
          equals(SyncState.needsAttention));
    });
  });

  group('DB からの読み取り', () {
    late Contracts contracts;
    late SqliteDb db;
    late EnvelopeCodec codec;

    Envelope book(String eventId,
            {required int base,
            required int result,
            String device = _remoteDevice,
            String now = '2026-08-05T09:00:00Z'}) =>
        codec.build(
          eventId: eventId,
          deviceId: device,
          createdAtUtc: now,
          entityType: 'book',
          entityId: _bookId,
          operation: 'upsert',
          baseVersion: base,
          resultVersion: result,
          payload: {'title': 'v$result'},
        );

    void outbox(String eventId, String state) {
      transaction(
          db,
          () => appendOutbox(db, book(eventId, base: 0, result: 1, device: _localDevice),
              state: state, updatedAtUtc: '2026-08-05T09:00:00Z', app: appBsync));
    }

    void run(String runId,
        {required String started,
        String? finished,
        String mode = 'run',
        String outcome = 'ok'}) {
      transaction(db, () {
        startRun(db, runId: runId, startedAtUtc: started, transport: 'dir', mode: mode);
        if (finished != null) {
          finishRun(db, runId,
              finishedAtUtc: finished, counts: const {}, outcome: outcome);
        }
      });
    }

    SyncFacts facts({required String now}) => readSyncFacts(db, now: now);

    setUp(() {
      contracts = Contracts.load();
      db = SqliteDb.memory();
      migrate(db, now: '2026-08-04T09:00:00Z');
      codec = EnvelopeCodec(contracts);
    });
    tearDown(() => db.close());

    test('初期状態は同期済みである', () {
      final snapshot = facts(now: '2026-08-05T09:00:00Z');
      expect(deriveState(snapshot), equals(SyncState.synced));
      expect(snapshot.lastSuccessAt, isNull);
      expect(snapshot.unsent, equals(0));
    });

    test('未送信は uploaded 以外の全てで、止まった行も含む', () {
      outbox('10900000-0000-4000-8000-000000000001', outboxPending);
      outbox('10900000-0000-4000-8000-000000000002', outboxUploading);
      outbox('10900000-0000-4000-8000-000000000003', outboxBlockedAuth);
      outbox('10900000-0000-4000-8000-000000000004', outboxUploaded);

      final snapshot = facts(now: '2026-08-05T09:00:00Z');
      // 止まった行を数から外すと、「未送信 0件」と「ログインが必要」が同時に出て、送るものが
      // 消えたように見える。
      expect(snapshot.unsent, equals(3));
      expect(snapshot.blockedAuth, equals(1));
      expect(deriveState(snapshot), equals(SyncState.signInRequired));
    });

    test('失効した lease は数えるが、未送信の内数である', () {
      outbox('10900000-0000-4000-8000-000000000001', outboxUploading);
      db.execute(
          'UPDATE outbox_events SET lease_owner = ?, lease_expires_at_utc = ?',
          ['run-1', '2026-08-05T08:00:00Z']);

      final snapshot = facts(now: '2026-08-05T09:00:00Z');
      expect(snapshot.expiredLeases, equals(1));
      expect(snapshot.unsent, equals(1));
      expect(deriveState(snapshot), equals(SyncState.unsent));
    });

    test('受理集合の外の封筒はアプリ更新になる', () {
      transaction(
          db,
          () => recordPending(db,
              eventId: '10900000-0000-4000-8000-000000000001',
              reason: 'schema',
              envelope: '{"schemaVersion": 99}',
              receivedAtUtc: '2026-08-05T09:00:00Z'));
      expect(deriveState(facts(now: '2026-08-05T09:00:00Z')),
          equals(SyncState.appUpdateRequired));
    });

    test('gap は成功した取り込みをまたいで初めて恒久になる', () {
      final envelope = book('10900000-0000-4000-8000-000000000005', base: 4, result: 5);
      transaction(
          db,
          () => recordPending(db,
              eventId: envelope.eventId,
              reason: 'gap',
              entityType: envelope.entityType,
              entityId: envelope.entityId,
              baseVersion: envelope.baseVersion,
              envelope: envelope.canonicalText(),
              receivedAtUtc: '2026-08-05T09:00:00Z'));

      // 猶予を過ぎても、取りに行けていなければ「来ない先行」ではない。オフラインや認可切れの
      // 端末を要対応に倒さないための条件である。
      var snapshot = facts(now: '2026-08-08T09:00:00Z');
      expect(snapshot.gapPending, equals(1));
      expect(snapshot.stalledGaps, equals(0));
      expect(deriveState(snapshot), equals(SyncState.synced));

      // 受信より後に取り込みが成功しても、猶予の内なら正常な途中状態である。
      run('bbbbbbbb-0000-4000-8000-000000000001',
          started: '2026-08-05T10:00:00Z', finished: '2026-08-05T10:00:05Z');
      snapshot = facts(now: '2026-08-05T12:00:00Z');
      expect(snapshot.stalledGaps, equals(0));

      // 両方そろって初めて恒久とみなす。
      snapshot = facts(now: '2026-08-08T09:00:00Z');
      expect(snapshot.stalledGaps, equals(1));
      expect(deriveState(snapshot), equals(SyncState.needsAttention));
    });

    test('最終同期は push だけの run を数えない', () {
      // 送っただけで相手の更新を取り込んでいない run は「この時刻の内容で最新」とは言えない。
      run('bbbbbbbb-0000-4000-8000-000000000001',
          started: '2026-08-05T09:00:00Z',
          finished: '2026-08-05T09:00:05Z',
          mode: 'push');
      expect(facts(now: '2026-08-05T12:00:00Z').lastSuccessAt, isNull);

      // 失敗した取り込みも数えない。
      run('bbbbbbbb-0000-4000-8000-000000000002',
          started: '2026-08-05T10:00:00Z',
          finished: '2026-08-05T10:00:05Z',
          outcome: 'error');
      expect(facts(now: '2026-08-05T12:00:00Z').lastSuccessAt, isNull);

      run('bbbbbbbb-0000-4000-8000-000000000003',
          started: '2026-08-05T11:00:00Z', finished: '2026-08-05T11:00:05Z');
      expect(facts(now: '2026-08-05T12:00:00Z').lastSuccessAt,
          equals('2026-08-05T11:00:05Z'));
    });

    test('走行中の run は同期中だが、古すぎるものは走行中と読まない', () {
      run('bbbbbbbb-0000-4000-8000-000000000001', started: '2026-08-05T09:00:00Z');
      expect(deriveState(facts(now: '2026-08-05T09:00:10Z')), equals(SyncState.syncing));

      // プロセスが落ちれば running の行は残る。上限を置かないと、一度落ちた端末が永久に
      // 「同期中」を名乗り、未送信も要対応も隠れる。
      final after = shiftSeconds('2026-08-05T09:00:00Z', runStaleAfterSeconds + 1);
      expect(facts(now: after).running, isFalse);
      expect(deriveState(facts(now: after)), equals(SyncState.synced));
    });

    test('自動解決の件数は直近の run が閉じたものだけを数える', () {
      void conflict(String id, String detected) {
        transaction(
            db,
            () => recordConflict(db,
                conflictId: id,
                entityType: 'book',
                entityId: _bookId,
                localVersion: 1,
                remoteEventId: '10900000-0000-4000-8000-00000000000$id',
                remoteBaseVersion: 1,
                remoteResultVersion: 2,
                remoteEnvelope: '{}',
                detectedAtUtc: detected));
      }

      // 前の run で閉じた分は、次の run の事後通知に混ぜない。
      run('bbbbbbbb-0000-4000-8000-000000000001',
          started: '2026-08-05T09:00:00Z', finished: '2026-08-05T09:00:05Z');
      conflict('1', '2026-08-05T09:00:01Z');
      transaction(
          db, () => resolveConflict(db, '1', resolvedAtUtc: '2026-08-05T09:00:02Z'));
      expect(facts(now: '2026-08-05T09:30:00Z').autoResolved, equals(1));

      run('bbbbbbbb-0000-4000-8000-000000000002',
          started: '2026-08-05T10:00:00Z', finished: '2026-08-05T10:00:05Z');
      expect(facts(now: '2026-08-05T10:30:00Z').autoResolved, equals(0));

      conflict('2', '2026-08-05T10:00:01Z');
      conflict('3', '2026-08-05T10:00:01Z');
      transaction(db, () {
        resolveConflict(db, '2', resolvedAtUtc: '2026-08-05T10:00:02Z');
        resolveConflict(db, '3', resolvedAtUtc: '2026-08-05T10:00:02Z');
      });
      final snapshot = facts(now: '2026-08-05T10:30:00Z');
      expect(snapshot.autoResolved, equals(2));
      // 自動解決済みは成功扱いである。要対応の件数へは入れない。
      expect(snapshot.openConflicts, equals(0));
      expect(deriveState(snapshot), equals(SyncState.synced));
    });

    test('開いたままの競合は要対応になる', () {
      // 製品では自動解決が既定なので、開いたまま残るのは反復ガードが止めたものである。
      transaction(
          db,
          () => recordConflict(db,
              conflictId: 'cccccccc-0000-4000-8000-000000000001',
              entityType: 'book',
              entityId: _bookId,
              localVersion: 1,
              remoteEventId: '10900000-0000-4000-8000-000000000009',
              remoteBaseVersion: 1,
              remoteResultVersion: 2,
              remoteEnvelope: '{}',
              detectedAtUtc: '2026-08-05T09:00:00Z'));
      expect(deriveState(facts(now: '2026-08-05T09:00:00Z')),
          equals(SyncState.needsAttention));
    });

    test('回線と自己診断は渡された分だけが効く。推測で埋めない', () {
      // 古い失敗から回線を決めると、一度失敗して放置された端末が延々とオフラインを名乗り、
      // 未送信があることを隠す。
      run('bbbbbbbb-0000-4000-8000-000000000001',
          started: '2026-08-05T09:00:00Z',
          finished: '2026-08-05T09:00:05Z',
          outcome: 'error');
      outbox('10900000-0000-4000-8000-000000000001', outboxPending);
      expect(deriveState(facts(now: '2026-08-06T09:00:00Z')), equals(SyncState.unsent));

      expect(
          deriveState(readSyncFacts(db, now: '2026-08-06T09:00:00Z', offline: true)),
          equals(SyncState.offline));
      expect(
          deriveState(
              readSyncFacts(db, now: '2026-08-06T09:00:00Z', doctorFailed: true)),
          equals(SyncState.needsAttention));
    });
  });
}

/// 単独で立てたときにその状態になる事実。**7つとも到達可能であることを示す。**
const Map<SyncState, SyncFacts> _oneEach = {
  SyncState.appUpdateRequired: SyncFacts(schemaPending: 1),
  SyncState.signInRequired: SyncFacts(blockedAuth: 1, unsent: 1),
  SyncState.needsAttention: SyncFacts(openConflicts: 1),
  SyncState.syncing: SyncFacts(running: true),
  SyncState.offline: SyncFacts(offline: true),
  SyncState.unsent: SyncFacts(unsent: 1),
  SyncState.synced: SyncFacts(),
};

SyncFacts _copy(
  SyncFacts base, {
  int? unsent,
  int? blockedAuth,
  int? schemaPending,
  int? stalledGaps,
  int? openConflicts,
  bool? dbSchemaAhead,
  bool? running,
  bool? offline,
  bool? doctorFailed,
}) =>
    SyncFacts(
      unsent: unsent ?? base.unsent,
      blockedAuth: blockedAuth ?? base.blockedAuth,
      expiredLeases: base.expiredLeases,
      schemaPending: schemaPending ?? base.schemaPending,
      gapPending: base.gapPending,
      stalledGaps: stalledGaps ?? base.stalledGaps,
      openConflicts: openConflicts ?? base.openConflicts,
      dbSchemaAhead: dbSchemaAhead ?? base.dbSchemaAhead,
      dbSchemaBehind: base.dbSchemaBehind,
      checksumMismatch: base.checksumMismatch,
      running: running ?? base.running,
      lastSuccessAt: base.lastSuccessAt,
      autoResolved: base.autoResolved,
      offline: offline ?? base.offline,
      doctorFailed: doctorFailed ?? base.doctorFailed,
    );
