/// 適用の、9ケースが測らない部分。**gap の再走査と自動解決の反復ガード。**
///
/// 受入の9ケースは `dir` 転送を通るため、`transport.list()` が毎回全件を返す。そのため滞留した
/// gap は次の run の**本ループ**で解けてしまい、`pending_events` の再走査を通らない経路がある。
/// 反復ガードも同様に、9ケースでは踏まない（踏ませるには上限のインプロセス上書きが要る）。
/// どちらも規則としては決まっているので、ここで直接測る。
library;

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String _localDevice = 'windows-00000000-0000-4000-8000-000000000001';
const String _remoteDevice = 'android-00000000-0000-4000-8000-000000000002';
const String _bookId = 'aaaaaaaa-9001-4000-8000-000000000001';

void main() {
  late Contracts contracts;
  late SqliteDb db;
  late Applier applier;
  var uuidCounter = 0;

  String uuid() {
    uuidCounter++;
    return 'dddddddd-0000-4000-8000-${uuidCounter.toRadixString(16).padLeft(12, '0')}';
  }

  Envelope book(
    String eventId, {
    required int base,
    required int result,
    required String title,
    String device = _remoteDevice,
    String now = '2026-08-05T09:00:00Z',
  }) =>
      applier.codec.build(
        eventId: eventId,
        deviceId: device,
        createdAtUtc: now,
        entityType: 'book',
        entityId: _bookId,
        operation: 'upsert',
        baseVersion: base,
        resultVersion: result,
        payload: {'title': title},
      );

  RemoteEvent remote(Envelope e) => RemoteEvent(
        remoteId: 'event-${e.eventId}.json',
        eventId: e.eventId,
        text: e.canonicalText(),
        createdAtUtc: e.createdAtUtc,
      );

  setUp(() {
    contracts = Contracts.load();
    db = SqliteDb.memory();
    migrate(db, now: '2026-08-04T09:00:00Z');
    applier = Applier(contracts);
    uuidCounter = 0;
  });
  tearDown(() => db.close());

  group('gap の再走査', () {
    test('先行が未着なら保持する。競合にしない', () {
      final report = applier.applyIncoming(
        db,
        [
          remote(book('10900000-0000-4000-8000-000000000003',
              base: 2, result: 3, title: 'v3')),
          remote(book('10900000-0000-4000-8000-000000000002',
              base: 1, result: 2, title: 'v2')),
        ],
        now: '2026-08-05T09:00:00Z',
        runId: uuid(),
        conflictIdFactory: uuid,
      );
      expect(report.applied, equals(0));
      expect(report.conflicted, equals(0), reason: 'baseVersion > 現在版 は gap であって競合ではない');
      expect(pendingCountsByReason(db), equals({'gap': 2}));
      expect(countApplied(db), equals(0));
    });

    test('先行が届くと鎖がほどけ、版順に適用される', () {
      applier.applyIncoming(
        db,
        [
          remote(book('10900000-0000-4000-8000-000000000003',
              base: 2, result: 3, title: 'v3')),
          remote(book('10900000-0000-4000-8000-000000000002',
              base: 1, result: 2, title: 'v2')),
        ],
        now: '2026-08-05T09:00:00Z',
        runId: uuid(),
        conflictIdFactory: uuid,
      );

      // **v1 だけを渡す。** 残り2件は本ループではなく `pending_events` の再走査から解ける。
      final report = applier.applyIncoming(
        db,
        [remote(book('10900000-0000-4000-8000-000000000001',
            base: 0, result: 1, title: 'v1'))],
        now: '2026-08-06T09:00:00Z',
        runId: uuid(),
        conflictIdFactory: uuid,
      );

      expect(report.applied, equals(3), reason: 'v1 の適用が v2・v3 の gap を解く');
      expect(listPending(db), isEmpty);
      expect(countApplied(db), equals(3));
      final row = applier.aggregates.read(db, 'book', _bookId)!;
      expect(row['version'], equals(3));
      expect(row['title'], equals('v3'));
    });
  });

  group('自動解決（LWW）と反復ガード', () {
    /// 同一集約に競合を1件立てる。ローカル v2、リモートは v1→v2。
    void openOneConflict({String remoteNow = '2026-08-06T09:00:00Z'}) {
      // v1 をリモートから受けてローカルを v1 にする。
      applier.applyIncoming(
        db,
        [remote(book('10900000-0000-4000-8000-000000000001',
            base: 0, result: 1, title: 'v1'))],
        now: '2026-08-05T09:00:00Z',
        runId: uuid(),
        conflictIdFactory: uuid,
      );
      // 自端末が v2 を発行する。
      final local = book('10900000-0000-4000-8000-0000000000a2',
          base: 1, result: 2, title: 'local-v2', device: _localDevice);
      applier.store
          .commit(db, [applier.planner.localEmit(local, currentVersion: 1)]);
      // 相手も v1 の上に v2 を積んでいた。baseVersion < 現在版 なので競合になる。
      applier.applyIncoming(
        db,
        [
          remote(book('10900000-0000-4000-8000-0000000000b2',
              base: 1, result: 2, title: 'remote-v2', now: remoteNow))
        ],
        now: '2026-08-07T09:00:00Z',
        runId: uuid(),
        conflictIdFactory: uuid,
      );
    }


    test('ローカルが勝ったのにリモートが tombstone でも、行を消さない', () {
      // **操作は採った側から決める。** リモートの操作をそのまま使っていたため、ローカルが
      // 勝った解決なのに行が消えていた。
      applier.applyIncoming(
        db,
        [remote(book('10900000-0000-4000-8000-000000000001',
            base: 0, result: 1, title: 'v1'))],
        now: '2026-08-05T09:00:00Z',
        runId: uuid(),
        conflictIdFactory: uuid,
      );
      // 自端末が v2 を **新しい時刻で**発行する（LWW でローカルが勝つ）。
      final local = book('10900000-0000-4000-8000-0000000000a2',
          base: 1, result: 2, title: 'local-v2', device: _localDevice,
          now: '2026-08-09T09:00:00Z');
      applier.store
          .commit(db, [applier.planner.localEmit(local, currentVersion: 1)]);
      // 相手は同じ本を**削除**していた。時刻は古い。
      final removal = applier.codec.build(
        eventId: '10900000-0000-4000-8000-0000000000b2',
        deviceId: _remoteDevice,
        createdAtUtc: '2026-08-06T09:00:00Z',
        entityType: 'book',
        entityId: _bookId,
        operation: operationTombstone,
        baseVersion: 1,
        resultVersion: 2,
        payload: const {},
      );
      applier.applyIncoming(db, [remote(removal)],
          now: '2026-08-10T09:00:00Z', runId: uuid(), conflictIdFactory: uuid);
      expect(countOpenConflicts(db), equals(1));

      final report = applier.autoResolveOpenConflicts(db,
          deviceId: _localDevice, now: '2026-08-10T09:00:00Z',
          uuidFactory: uuid);
      expect(report.resolved.single['take'], equals('local'));

      final row = applier.aggregates.read(db, 'book', _bookId)!;
      expect(row['is_deleted'], equals(0), reason: 'ローカルが勝ったのに消えている');
      expect(row['title'], equals('local-v2'));
    });

    test('ローカルが削除済みで勝ったら、解決も tombstone である', () {
      // **復元直後に踏みやすい形の逆側。** ローカルの今が「消えている」なら、解決もそれを運ぶ。
      applier.applyIncoming(
        db,
        [remote(book('10900000-0000-4000-8000-000000000001',
            base: 0, result: 1, title: 'v1'))],
        now: '2026-08-05T09:00:00Z',
        runId: uuid(),
        conflictIdFactory: uuid,
      );
      // 自端末が**削除**を発行する（新しい時刻＝LWW で勝つ）。
      final removal = applier.codec.build(
        eventId: '10900000-0000-4000-8000-0000000000a2',
        deviceId: _localDevice,
        createdAtUtc: '2026-08-09T09:00:00Z',
        entityType: 'book',
        entityId: _bookId,
        operation: operationTombstone,
        baseVersion: 1,
        resultVersion: 2,
        payload: const {},
      );
      applier.store
          .commit(db, [applier.planner.localEmit(removal, currentVersion: 1)]);
      // 相手は同じ本を書き換えていた。時刻は古い。
      applier.applyIncoming(
        db,
        [
          remote(book('10900000-0000-4000-8000-0000000000b2',
              base: 1, result: 2, title: 'remote-v2',
              now: '2026-08-06T09:00:00Z'))
        ],
        now: '2026-08-10T09:00:00Z',
        runId: uuid(),
        conflictIdFactory: uuid,
      );

      final report = applier.autoResolveOpenConflicts(db,
          deviceId: _localDevice, now: '2026-08-10T09:00:00Z',
          uuidFactory: uuid);
      expect(report.resolved.single['take'], equals('local'));

      final row = applier.aggregates.read(db, 'book', _bookId)!;
      expect(row['is_deleted'], equals(1), reason: '消したはずの行が復活している');
    });
    test('開いた競合を決定キーで解き、解決イベントを outbox へ積む', () {
      openOneConflict();
      expect(countOpenConflicts(db), equals(1));

      final report = applier.autoResolveOpenConflicts(db,
          deviceId: _localDevice, now: '2026-08-08T09:00:00Z', uuidFactory: uuid);

      expect(report.resolved.length, equals(1));
      expect(report.guarded, isEmpty);
      expect(countOpenConflicts(db), equals(0));
      // 業務時刻が後のリモートが勝つ。版は max(ローカル版, リモートの resultVersion) + 1。
      expect(report.resolved.first['take'], equals('remote'));
      final row = applier.aggregates.read(db, 'book', _bookId)!;
      expect(row['version'], equals(3));
      expect(row['title'], equals('remote-v2'));
      // **黙って上書きしない。** 解決イベントは outbox に積まれ、続く push が送る。
      expect(countOutbox(db, outboxPending), equals(2),
          reason: '自端末の v2 と、解決イベントの v3');
    });

    test('決定キーは両端末で同値なので、ローカルが後なら local を採る', () {
      // 業務時刻を巻き戻すとローカル（2026-08-05T09:00:00Z 発行の v2）が後になる。
      openOneConflict(remoteNow: '2026-08-04T09:00:00Z');
      final report = applier.autoResolveOpenConflicts(db,
          deviceId: _localDevice, now: '2026-08-08T09:00:00Z', uuidFactory: uuid);
      expect(report.resolved.first['take'], equals('local'));
      expect(applier.aggregates.read(db, 'book', _bookId)!['title'],
          equals('local-v2'));
    });

    test('上限に達したら自動を止め、競合を開いたまま残す（要対応へ落とす）', () {
      openOneConflict();
      final report = applier.autoResolveOpenConflicts(db,
          deviceId: _localDevice,
          now: '2026-08-08T09:00:00Z',
          uuidFactory: uuid,
          guardMax: 0);

      expect(report.resolved, isEmpty);
      expect(report.guarded.length, equals(1));
      expect(countOpenConflicts(db), equals(1), reason: '開いたまま残す。捨てない');
    });

    test('上限は窓で数える。窓の外の解決済みは数えない', () {
      openOneConflict();
      // 窓（24時間）の外に解決済みを積む。累計で数えるならここで上限に達する。
      for (var i = 0; i < autoResolveGuardMax + 5; i++) {
        final id = 'cccccccc-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}';
        recordConflict(db,
            conflictId: id,
            entityType: 'book',
            entityId: _bookId,
            localVersion: 1,
            remoteEventId: id,
            remoteBaseVersion: 0,
            remoteResultVersion: 1,
            remoteEnvelope: '{}',
            detectedAtUtc: '2026-01-01T00:00:00Z');
        resolveConflict(db, id,
            resolvedAtUtc: '2026-01-01T00:00:00Z', resolutionEventId: null);
      }

      final report = applier.autoResolveOpenConflicts(db,
          deviceId: _localDevice, now: '2026-08-08T09:00:00Z', uuidFactory: uuid);
      expect(report.guarded, isEmpty,
          reason: '窓を切らずに累計で数えると、長く使う集約が正常な利用のまま上限へ達する');
      expect(report.resolved.length, equals(1));
    });
  });
}
