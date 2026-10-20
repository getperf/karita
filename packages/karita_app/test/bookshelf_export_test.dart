import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';

const _testTitle = '=危険,"本"\n二行';

class Delivery implements ExportDelivery {
  Uint8List? bytes;
  String? filename, mimeType;
  bool fail = false;
  ExportDeliveryResult result = ExportDeliveryResult.saved;
  @override
  ExportDeliveryKind get kind => ExportDeliveryKind.save;
  @override
  Future<ExportDeliveryResult> deliver({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    if (fail) throw const FileSystemException('test failure');
    this.bytes = bytes;
    this.filename = filename;
    this.mimeType = mimeType;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Composition app;
  late Directory home;
  late Delivery delivery;
  late String id;
  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-export-');
    delivery = Delivery();
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
      exportDelivery: delivery,
    );
    id = app.reservationBookId(null);
    app.saveReservation(
      book: ReservationBook(id: id, title: _testTitle, authors: ['著者A', '著者B']),
      operationId: app.newReservationId(),
      systems: [],
      wanted: true,
    );
  });
  tearDown(() {
    app.close();
    home.deleteSync(recursive: true);
  });

  Map<String, Object?> row() => app.prepareBookshelfExport().books.singleWhere(
    (b) => b['title'] == _testTitle,
  );

  test(
    'book registration stays fixed through state changes, reviews and missing shelf dates',
    () {
      final initialRegistration = row()['book_registered_at_utc'];
      expect(initialRegistration, isNotNull);
      final shelf = Bookshelf(app.domain);
      shelf.setState(
        id,
        'read',
        now: '2026-10-20T01:00:00Z',
        readOn: '2026-10-01',
      );
      shelf.setState(id, 'read', now: '2026-10-20T02:00:00Z');
      expect(row()['read_registered_at_utc'], '2026-10-20T01:00:00Z');
      app.saveBookReview(id, rating: 4, review: '感想\n二行', expectedRevision: '');
      shelf.setState(id, 'wanted', now: '2026-10-20T03:00:00Z');
      expect(row()['read_registered_at_utc'], '2026-10-20T01:00:00Z');
      expect(row()['book_registered_at_utc'], initialRegistration);
      shelf.setState(id, 'read', now: '2026-10-20T04:00:00Z');
      expect(row()['read_registered_at_utc'], '2026-10-20T04:00:00Z');
      expect(row()['rating'], 4);
      app.db.execute(
        'UPDATE book_preferences SET wanted_registered_at_utc = NULL, read_registered_at_utc = NULL WHERE book_id = ?',
        [id],
      );
      expect(row()['read_registered_at_utc'], isNull);
      expect(row()['book_registered_at_utc'], initialRegistration);
    },
  );

  test(
    'snapshot includes both states, excludes removed, stays fixed through later changes',
    () async {
      final removed = app.loadBookshelf().firstWhere((b) => b.id != id).id;
      final removedTitle = app.loadBookshelf(bookId: removed).single.title;
      app.setShelfState(removed, 'removed');
      final snapshot = app.prepareBookshelfExport();
      expect(snapshot.books.any((b) => b['title'] == removedTitle), isFalse);
      expect(
        snapshot.books.map((b) => b['shelf_state']).toSet(),
        containsAll(['wanted', 'read']),
      );
      app.setShelfState(id, 'removed');
      await app.exportBookshelf(snapshot, BookshelfExportFormat.json);
      final data =
          jsonDecode(utf8.decode(delivery.bytes!)) as Map<String, dynamic>;
      expect(data['schema_version'], 2);
      final books = data['books'] as List;
      expect(books.length, snapshot.books.length);
      expect(
        books.where((b) => b['title'] == _testTitle).single['shelf_state'],
        'wanted',
      );
      expect(books.first.keys.toSet(), {
        'title',
        'authors',
        'isbn13',
        'shelf_state',
        'book_registered_at_utc',
        'read_registered_at_utc',
        'read_count',
        'rating',
        'review',
      });
      expect(books.where((b) => b['title'] == _testTitle).single['authors'], [
        '著者A',
        '著者B',
      ]);
      expect(delivery.filename, endsWith('.json'));
      expect(delivery.mimeType, 'application/json');
    },
  );

  test(
    'CSV has BOM, quoted multiline cells, formula protection; JSON preserves original',
    () async {
      final snapshot = app.prepareBookshelfExport();
      await app.exportBookshelf(snapshot, BookshelfExportFormat.csv);
      expect(delivery.bytes!.take(3), [0xef, 0xbb, 0xbf]);
      final csv = utf8.decode(delivery.bytes!);
      expect(csv, contains('"\'=危険,""本""\n二行"'));
      expect(csv, contains('"著者A\n著者B"'));
      expect(csv, endsWith('\r\n'));
      expect(csv.split('\r\n').first, contains('"登録日時"'));
      expect(
        csv.split('\r\n').first,
        '"タイトル","著者","ISBN-13","本棚状態","登録日時","読んだ日時","読書記録件数","レーティング","コメント"',
      );
      expect(csv, isNot(contains('初期登録日時は推定')));
      expect(delivery.mimeType, 'text/csv');
      await app.exportBookshelf(snapshot, BookshelfExportFormat.json);
      expect(utf8.decode(delivery.bytes!), contains('=危険,'));
    },
  );

  test('delivery cancellation and failure do not mutate records', () async {
    final snapshot = app.prepareBookshelfExport();
    final count = app.db
        .select('SELECT count(*) AS n FROM outbox_events')
        .single['n'];
    delivery.result = ExportDeliveryResult.dismissed;
    expect(
      await app.exportBookshelf(snapshot, BookshelfExportFormat.csv),
      BookshelfExportResult.dismissed,
    );
    delivery.fail = true;
    await expectLater(
      app.exportBookshelf(snapshot, BookshelfExportFormat.json),
      throwsA(isA<AppIssue>()),
    );
    expect(
      app.db.select('SELECT count(*) AS n FROM outbox_events').single['n'],
      count,
    );
  });

  test(
    'return registration is preserved across corrections and a later wanted state',
    () {
      app.saveReservation(
        book: ReservationBook(id: id, title: '返却日時', authors: ['著者']),
        operationId: app.newReservationId(),
        systems: ['Tokyo_Koto'],
        wanted: false,
      );
      final loan =
          app.db.select('SELECT id FROM loans WHERE book_id = ?', [
                id,
              ]).single['id']
              as String;
      Loans(app.domain).update(
        loanId: loan,
        action: 'return',
        now: '2026-10-20T01:00:00Z',
        returnedOn: '2026-10-01',
      );
      expect(row()['read_registered_at_utc'], '2026-10-20T01:00:00Z');
      Loans(app.domain).update(
        loanId: loan,
        action: 'return',
        now: '2026-10-20T02:00:00Z',
        returnedOn: '2026-10-02',
      );
      expect(row()['read_registered_at_utc'], '2026-10-20T01:00:00Z');
      Bookshelf(app.domain).setState(id, 'wanted', now: '2026-10-20T03:00:00Z');
      expect(row()['read_registered_at_utc'], '2026-10-20T01:00:00Z');
      expect(row()['book_registered_at_utc'], isNotNull);
      expect(row()['shelf_state'], 'wanted');
    },
  );

  test(
    'unobserved return does not fabricate registration after a manual change',
    () {
      app.saveReservation(
        book: ReservationBook(id: id, title: 'オフライン', authors: ['著者']),
        operationId: app.newReservationId(),
        systems: ['Tokyo_Koto'],
        wanted: false,
      );
      final loan =
          app.db.select('SELECT id FROM loans WHERE book_id = ?', [
                id,
              ]).single['id']
              as String;
      final oldBasis = Bookshelf(app.domain).token(id);
      Bookshelf(
        app.domain,
      ).setState(id, 'removed', now: '2026-10-20T01:00:00Z');
      Bookshelf(app.domain).setState(id, 'wanted', now: '2026-10-20T02:00:00Z');
      // This is the resulting aggregate of a return from a device which never saw the removal.
      app.db.execute(
        "UPDATE loans SET status = 'returned', first_return_basis = ?, first_return_at_utc = '2026-10-20T03:00:00Z' WHERE id = ?",
        [oldBasis, loan],
      );
      expect(row()['shelf_state'], 'wanted');
      expect(row()['read_registered_at_utc'], isNull);
      Bookshelf(
        app.domain,
      ).setState(id, 'removed', now: '2026-10-20T04:00:00Z');
      Bookshelf(app.domain).setState(id, 'wanted', now: '2026-10-20T05:00:00Z');
      expect(row()['read_registered_at_utc'], isNull);
    },
  );

  test(
    'preparation and both formats work with SQLite query_only and perform no writes',
    () async {
      final before = app.db.select('SELECT total_changes() AS n').single['n'];
      app.db.execute('PRAGMA query_only = ON');
      try {
        final snapshot = app.prepareBookshelfExport();
        await app.exportBookshelf(snapshot, BookshelfExportFormat.csv);
        await app.exportBookshelf(snapshot, BookshelfExportFormat.json);
        expect(
          app.db.select('SELECT total_changes() AS n').single['n'],
          before,
        );
        expect(
          snapshot.books.every(
            (book) => book['book_registered_at_utc'] != null,
          ),
          isTrue,
        );
      } finally {
        app.db.execute('PRAGMA query_only = OFF');
      }
    },
  );

  test('v3 writer cannot erase registration timestamps', () {
    final prefId = deterministicId(entityBookPreference, id);
    final r = app.domain.aggregates.read(app.db, entityBookPreference, prefId)!;
    final payload = app.domain.mapping.rowToPayload(entityBookPreference, r)
      ..remove('wanted_registered_at_utc')
      ..remove('read_registered_at_utc');
    final e = EnvelopeCodec(Contracts.load()).build(
      eventId: app.newReservationId(),
      deviceId: 'v3-device',
      createdAtUtc: '2026-10-20T05:00:00Z',
      entityType: entityBookPreference,
      entityId: prefId,
      operation: 'upsert',
      baseVersion: r['version'],
      resultVersion: (r['version'] as int) + 1,
      payload: payload,
      schemaVersion: 3,
    );
    Applier(Contracts.load()).applyIncoming(
      app.db,
      [
        RemoteEvent(
          remoteId: 'old',
          eventId: e.eventId,
          text: e.canonicalText(),
          createdAtUtc: e.createdAtUtc,
        ),
      ],
      now: e.createdAtUtc,
      runId: app.newReservationId(),
      conflictIdFactory: app.newReservationId,
    );
    expect(
      app.domain.aggregates.read(
        app.db,
        entityBookPreference,
        prefId,
      )!['wanted_registered_at_utc'],
      isNotNull,
    );
    expect(
      app.db.select('SELECT * FROM pending_events WHERE event_id = ?', [
        e.eventId,
      ]),
      hasLength(1),
    );
  });
}
