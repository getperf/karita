/// マイグレーションの適用。**台帳まで含めて Python と同一になることが要である。**
///
/// 同じ SQL を同じ順で実行すれば、Python が作った DB と Dart が作った DB は
/// `schema_migrations` まで含めて同一になる。これが P1b の相互運用受入の土台である。
library;

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

void main() {
  late SqliteDb db;

  setUp(() => db = SqliteDb.memory());
  tearDown(() => db.close());

  test('素の DB へ全て適用でき、台帳が版・名前・チェックサムを持つ', () {
    final applied = migrate(db, now: '2026-08-04T09:00:00Z');
    expect(applied.length, equals(discover().length));
    expect(currentVersion(db), equals(latestVersion()));

    final ledger = db.select('SELECT * FROM schema_migrations ORDER BY version');
    expect(ledger.length, equals(discover().length));
    for (final m in discover()) {
      final row = ledger[m.version - 1];
      expect(row['version'], equals(m.version));
      expect(row['name'], equals(m.name));
      expect(row['checksum'], equals(m.checksum));
      expect(row['applied_at_utc'], equals('2026-08-04T09:00:00Z'));
    }
  });

  test('同期テーブルと集約テーブルが揃う。0009 が落とした表は無い', () {
    migrate(db, now: '2026-08-04T09:00:00Z');
    for (final name in [...syncTables, 'sync_state', 'books', 'loans',
      'library_memberships', 'library_systems']) {
      expect(tableExists(db, name), isTrue, reason: '$name がありません');
    }
    // L4 で落とした表。0007 は台帳に残るが、表そのものは 0009 が落としている。
    expect(tableExists(db, 'synced_files'), isFalse);
    expect(tableExists(db, 'synced_file_materialized'), isFalse);
  });

  test('再実行は冪等', () {
    migrate(db, now: '2026-08-04T09:00:00Z');
    final again = migrate(db, now: '2026-08-05T09:00:00Z');
    expect(again, isEmpty);
    expect(currentVersion(db), equals(latestVersion()));
  });

  test('適用後に SQL を書き換えたら移行を拒む', () {
    migrate(db, now: '2026-08-04T09:00:00Z');
    final tampered = {
      for (final m in discover())
        m.filename: m.version == 1 ? '${m.sql}\n-- 手で足した行\n' : m.sql,
    };
    expect(checksumMismatches(db, tampered), isNotEmpty);
    expect(() => migrate(db, now: '2026-08-05T09:00:00Z', sources: tampered),
        throwsA(isA<SyncDataError>()));
  });

  test('DDL と台帳は同一トランザクションで確定する', () {
    // 途中の版で落とせば、その版の DDL も台帳の行も残らない。
    final broken = {
      for (final m in discover())
        m.filename: m.version == 3 ? 'CREATE TABLE これは不正 (' : m.sql,
    };
    expect(() => migrate(db, now: '2026-08-04T09:00:00Z', sources: broken),
        throwsA(anything));
    expect(currentVersion(db), equals(2), reason: '0003 は台帳にも DDL にも残らない');
    expect(tableExists(db, 'sync_runs'), isFalse);
  });
}
