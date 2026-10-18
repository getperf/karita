/// 台帳の自己診断。**実 SQLite に対して測る。**
///
/// 「どこから読むか」も規則の一部である。事実を組み立てて渡す試験にすると、SQL が違うものを
/// 数えていても緑になる。
///
/// **`SyncFacts` と重ならないことも測る。** スキーマ版・失効 lease・滞留を doctor が二重に
/// 数えると、同じ異常が2箇所から出て、どちらを直したのか分からなくなる。
library;

import 'dart:io';

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String _device = 'windows-00000000-0000-4000-8000-000000000001';
const String _now = '2026-08-05T09:00:00Z';
const String _bookId = 'aaaaaaaa-9001-4000-8000-000000000001';

void main() {
  late SqliteDb db;
  late Mapping mapping;

  DoctorReport doctor() => ledgerDoctor(db, mapping);

  /// 引っかかった検査の識別子だけを取り出す。
  Set<DoctorCheck> failedChecks() =>
      doctor().findings.map((f) => f.check).toSet();

  setUp(() {
    final contracts = Contracts.load();
    mapping = Mapping(contracts);
    db = SqliteDb.memory();
    migrate(db, now: '2026-08-04T09:00:00Z');
    transaction(db, () => setState(db, stateDeviceId, _device));
  });
  tearDown(() => db.close());

  group('健全な台帳', () {
    test('立ち上げ直後は何も引っかからない', () {
      final report = doctor();
      expect(report.findings, isEmpty);
      expect(report.failed, isFalse);
    });

    test('メモリ上の DB では journal_mode を検査しない', () {
      // **「異常が無い」と「検査していない」を混ぜない。** `SqliteDb.memory()` は
      // `journal_mode = memory` のままで、そこには本体もジャーナルも無い。
      final report = doctor();
      expect(report.checked, isNot(contains(DoctorCheck.journalMode)));
      expect(report.notChecked, contains(DoctorCheck.journalMode));
    });

    test('台帳から読める検査は全部走っている', () {
      expect(
        doctor().checked,
        containsAll(<DoctorCheck>[
          DoctorCheck.deviceId,
          DoctorCheck.tableOwnership,
          DoctorCheck.orphanedOutbox,
          DoctorCheck.appliedWithoutEntity,
          DoctorCheck.versionGap,
        ]),
      );
    });

    test('環境の検査はここに無い', () {
      // 資格情報と認可は OS で形が違うので `karita_platform` 側が持つ。
      expect(
        doctor().notChecked,
        containsAll(<DoctorCheck>[
          DoctorCheck.homeWritable,
          DoctorCheck.credentials,
          DoctorCheck.authorization,
        ]),
      );
    });
  });

  group('device_id', () {
    test('無ければ引っかかる', () {
      db.execute('DELETE FROM sync_state WHERE key = ?', [stateDeviceId]);
      expect(failedChecks(), contains(DoctorCheck.deviceId));
      expect(
        doctor().findings.first.detail,
        equals('(none)'),
      );
    });

    test('platform の前半が無い形は引っかかる', () {
      // `platformOf` が読むのは `-` の前である。形が崩れると、一覧と診断で端末の種別が
      // 分からなくなる。
      transaction(db, () => setState(db, stateDeviceId, 'windows'));
      expect(failedChecks(), contains(DoctorCheck.deviceId));
    });

    test('値そのものを出す', () {
      // 形が違うことが問題なので、伏せると直しようがない。
      transaction(db, () => setState(db, stateDeviceId, 'BAD ID'));
      expect(doctor().findings.single.detail, equals('BAD ID'));
    });
  });

  group('所有', () {
    test('押印の無い行を数える', () {
      // 業務が生 SQL で同期テーブルへ直接書いた形を作る。`karita_contract` の書込みヘルパを
      // 通していないので `written_by_app` が空のままになる。
      db.execute(
        'INSERT INTO applied_events '
        '(event_id, entity_type, entity_id, result_version, payload_hash, origin, applied_at_utc) '
        'VALUES (?, ?, ?, 1, ?, ?, ?)',
        ['10900000-0000-4000-8000-000000000001', entityBook, _bookId, 'h', 'local', _now],
      );
      final findings = doctor().findings;
      expect(findings.map((f) => f.check), contains(DoctorCheck.tableOwnership));
      expect(
        findings.firstWhere((f) => f.check == DoctorCheck.tableOwnership).detail,
        equals('applied_events'),
      );
    });
  });

  group('孤児 outbox', () {
    test('applied_events に対応の無い outbox を数える', () {
      // ローカル発行は集約更新・applied_events・outbox_events を同一トランザクションで確定する。
      // 対応が無い outbox は、その原子性が崩れた跡である。
      _insertOutbox(db, '10900000-0000-4000-8000-000000000002');
      final findings = doctor().findings;
      final orphan =
          findings.firstWhere((f) => f.check == DoctorCheck.orphanedOutbox);
      expect(orphan.count, equals(1));
    });

    test('対応があれば引っかからない', () {
      const eventId = '10900000-0000-4000-8000-000000000003';
      _insertOutbox(db, eventId);
      _insertApplied(db, eventId, version: 1);
      _insertBook(db, version: 1);
      expect(failedChecks(), isNot(contains(DoctorCheck.orphanedOutbox)));
    });
  });

  group('実体のない applied_events', () {
    test('集約の行が無ければ数え、テーブル名を出す', () {
      _insertApplied(db, '10900000-0000-4000-8000-000000000004', version: 1);
      final missing = doctor()
          .findings
          .firstWhere((f) => f.check == DoctorCheck.appliedWithoutEntity);
      expect(missing.count, equals(1));
      expect(missing.detail, equals('books'));
    });

    test('行があれば引っかからない', () {
      _insertApplied(db, '10900000-0000-4000-8000-000000000005', version: 1);
      _insertBook(db, version: 1);
      expect(failedChecks(), isNot(contains(DoctorCheck.appliedWithoutEntity)));
    });
  });

  group('版の飛び', () {
    test('1..max のうち欠けている版があれば数える', () {
      _insertBook(db, version: 3);
      _insertApplied(db, '10900000-0000-4000-8000-000000000006', version: 1);
      // 版 2 が無い。
      _insertApplied(db, '10900000-0000-4000-8000-000000000007', version: 3);
      expect(failedChecks(), contains(DoctorCheck.versionGap));
    });

    test('連番なら引っかからない', () {
      _insertBook(db, version: 2);
      _insertApplied(db, '10900000-0000-4000-8000-000000000008', version: 1);
      _insertApplied(db, '10900000-0000-4000-8000-000000000009', version: 2);
      expect(failedChecks(), isNot(contains(DoctorCheck.versionGap)));
    });
  });

  group('ファイルの DB', () {
    test('WAL なら journal_mode は引っかからず、検査済みになる', () {
      final dir = Directory.systemTemp.createTempSync('karita-doctor-');
      final file = SqliteDb.open('${dir.path}${Platform.pathSeparator}library.db');
      try {
        migrate(file, now: '2026-08-04T09:00:00Z');
        transaction(file, () => setState(file, stateDeviceId, _device));

        final report = ledgerDoctor(file, mapping);
        expect(report.checked, contains(DoctorCheck.journalMode));
        expect(report.findings, isEmpty);
      } finally {
        file.close();
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('DoctorReport', () {
    test('merge は checked も findings も足し合わせる', () {
      const ledger = DoctorReport(
        checked: {DoctorCheck.deviceId},
        findings: [DoctorFinding(DoctorCheck.deviceId, 1, '(none)')],
      );
      const environment = DoctorReport(checked: {DoctorCheck.credentials});

      final merged = DoctorReport.merge([ledger, environment]);
      expect(merged.checked,
          equals({DoctorCheck.deviceId, DoctorCheck.credentials}));
      expect(merged.findings, hasLength(1));
      expect(merged.failed, isTrue);
    });

    test('1件でも引っかかれば失敗である', () {
      // **重みづけをしない。** 「軽い異常」を作ると、どこまで無視してよいかの判断が UI 側へ漏れる。
      const one = DoctorReport(
        checked: {DoctorCheck.versionGap},
        findings: [DoctorFinding(DoctorCheck.versionGap, 1, 'applied_events')],
      );
      expect(one.failed, isTrue);
      expect(const DoctorReport(checked: {DoctorCheck.versionGap}).failed, isFalse);
    });

    test('toMap は識別子と件数だけを出す', () {
      const report = DoctorReport(
        checked: {DoctorCheck.deviceId},
        findings: [DoctorFinding(DoctorCheck.deviceId, 2, 'x')],
      );
      final map = report.toMap();
      expect(map['failed'], isTrue);
      expect(map['checked'], equals(['deviceId']));
      expect(
        (map['findings'] as List).single,
        equals({'check': 'deviceId', 'count': 2, 'detail': 'x'}),
      );
    });
  });

  group('SyncFacts と重ならない', () {
    test('失効した lease は doctor が数えない', () {
      // 導出が `expiredLeases` で持っている。二重に数えると、同じ異常が2箇所から出る。
      _insertOutbox(db, '10900000-0000-4000-8000-00000000000a',
          state: outboxUploading);
      _insertApplied(db, '10900000-0000-4000-8000-00000000000a', version: 1);
      _insertBook(db, version: 1);
      db.execute(
          'UPDATE outbox_events SET lease_owner = ?, lease_expires_at_utc = ?',
          ['run-1', '2026-08-05T08:00:00Z']);

      expect(readSyncFacts(db, now: _now).expiredLeases, equals(1));
      expect(doctor().findings, isEmpty);
    });

    test('受理集合の外の封筒は doctor が数えない', () {
      transaction(
        db,
        () => recordPending(db,
            eventId: '10900000-0000-4000-8000-00000000000b',
            reason: 'schema',
            envelope: '{"schemaVersion": 99}',
            receivedAtUtc: _now),
      );
      expect(readSyncFacts(db, now: _now).schemaPending, equals(1));
      expect(doctor().findings, isEmpty);
    });
  });
}

void _insertOutbox(Db db, String eventId, {String state = outboxPending}) {
  db.execute(
    'INSERT INTO outbox_events '
    '(event_id, device_id, created_at_utc, entity_type, entity_id, operation, '
    ' base_version, result_version, payload_hash, payload, state, updated_at_utc, '
    ' written_by_app) '
    'VALUES (?, ?, ?, ?, ?, ?, 0, 1, ?, ?, ?, ?, ?)',
    [eventId, _device, _now, entityBook, _bookId, 'upsert', 'h', '{}', state, _now,
        appBsync],
  );
}

void _insertApplied(Db db, String eventId, {required int version}) {
  db.execute(
    'INSERT INTO applied_events '
    '(event_id, entity_type, entity_id, result_version, payload_hash, origin, '
    ' applied_at_utc, written_by_app) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [eventId, entityBook, _bookId, version, 'h', 'local', _now, appBsync],
  );
}

void _insertBook(Db db, {required int version}) {
  db.execute(
    'INSERT INTO books (id, title, version, updated_at_utc, updated_by_device_id) '
    'VALUES (?, ?, ?, ?, ?)',
    [_bookId, 'title', version, _now, _device],
  );
}
