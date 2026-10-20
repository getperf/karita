import 'package:flutter_test/flutter_test.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_sync/karita_sync.dart';

void main() {
  test(
    'registration reads events first, then first-version time; edited unknown books stay null',
    () {
      final db = SqliteDb.memory();
      addTearDown(db.close);
      migrate(db, now: '2026-10-20T00:00:00Z');
      for (final id in ['history', 'first-version', 'unknown', 'outbox']) {
        db.execute(
          "INSERT INTO books(id,title,version,updated_at_utc,updated_by_device_id) VALUES(?,?,?,'2026-10-19T00:00:00Z','old')",
          [id, id, id == 'first-version' ? 1 : 3],
        );
        db.execute(
          "INSERT INTO book_preferences(id,book_id,shelf_state,version,updated_at_utc,updated_by_device_id) VALUES(?,?,'wanted',1,'2026-10-20T00:00:00Z','old')",
          ['pref-$id', id],
        );
      }
      db.execute(
        "INSERT INTO domain_events VALUES ('event','BookRegisteredFromReference','book','history','2026-09-01T00:00:00Z','old','{}')",
      );
      db.execute(
        "INSERT INTO outbox_events(event_id,device_id,created_at_utc,entity_type,entity_id,operation,base_version,result_version,payload_hash,payload,state,updated_at_utc) VALUES('outbox-event','old','2026-09-02T00:00:00Z','book','outbox','upsert',0,1,'hash','{}','uploaded','2026-10-20T00:00:00Z')",
      );
      final context = DomainContext.fixed(
        db: db,
        contracts: Contracts.load(),
        deviceId: 'test',
        uuid: () => throw StateError('read only'),
      );
      final before = db.select('SELECT total_changes() AS n').single['n'];
      db.execute('PRAGMA query_only = ON');
      final rows = {
        for (final row in BookshelfExport(context).read()) row.shelf.id: row,
      };
      expect(rows['history']!.registeredAt, '2026-09-01T00:00:00Z');
      expect(rows['outbox']!.registeredAt, '2026-09-02T00:00:00Z');
      expect(rows['first-version']!.registeredAt, '2026-10-19T00:00:00Z');
      expect(rows['unknown']!.registeredAt, isNull);
      expect(db.select('SELECT total_changes() AS n').single['n'], before);
      expect(
        db.select('PRAGMA table_info(books)').map((r) => r['name']),
        isNot(contains('registered_at_utc')),
      );
    },
  );

  test('repeated loans and state changes do not change initial registration', () {
    final db = SqliteDb.memory();
    addTearDown(db.close);
    migrate(db, now: '2026-10-20T00:00:00Z');
    var counter = 0;
    String uuid() =>
        '00000000-0000-4000-8000-${(++counter).toString().padLeft(12, '0')}';
    final context = DomainContext.fixed(
      db: db,
      contracts: Contracts.load(),
      deviceId: 'test',
      uuid: uuid,
    );
    final first = Books(context).adopt(
      title: '再貸出し',
      authors: ['著者'],
      isbn13: '9784101010014',
      provider: 'manual',
      now: '2026-09-01T00:00:00Z',
    );
    final id = first.entityId;
    Bookshelf(context).setState(id, 'wanted', now: '2026-09-01T00:00:00Z');
    for (final day in ['10', '20']) {
      final loan = uuid();
      Loans(context).start(
        loanId: loan,
        bookId: id,
        status: 'borrowed',
        systemId: 'Tokyo_Koto',
        pickupLibraryId: 'Tokyo_Koto_Toyosu',
        now: '2026-09-${day}T00:00:00Z',
      );
      Loans(
        context,
      ).update(loanId: loan, action: 'return', now: '2026-09-${day}T01:00:00Z');
    }
    // A restored first-version book has no event history but retains its original time.
    db.execute('DELETE FROM domain_events');
    db.execute('DELETE FROM outbox_events');
    final exported = BookshelfExport(context).read().single;
    expect(exported.registeredAt, '2026-09-01T00:00:00Z');
    expect(exported.shelf.histories, hasLength(2));
  });
}
