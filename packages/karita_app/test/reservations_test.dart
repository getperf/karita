import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;
  late ReservationBook book;
  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-reservation-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
    book = ReservationBook(
      id: app.reservationBookId('9784274219337'),
      isbn13: '9784274219337',
      title: '予約のテスト',
      authors: const ['著者'],
    );
  });
  tearDown(() {
    app.close();
    home.deleteSync(recursive: true);
  });
  String save({
    ReservationBook? candidate,
    List<String> systems = const ['Tokyo_Koto', 'Tokyo_Edogawa'],
    bool wanted = false,
    String? operation,
  }) => app.saveReservation(
    book: candidate ?? book,
    operationId: operation ?? app.newReservationId(),
    systems: systems,
    wanted: wanted,
  );

  test('one book and two loans commit; exact retry emits nothing', () {
    final operation = app.newReservationId();
    save(operation: operation);
    expect(
      app.db.select('SELECT * FROM loans WHERE book_id = ?', [book.id]),
      hasLength(2),
    );
    final count = app.db.select('SELECT * FROM outbox_events').length;
    save(operation: operation);
    expect(app.db.select('SELECT * FROM outbox_events'), hasLength(count));
  });

  test('a new book needs a title even with an ISBN (2026-10-08)', () {
    expect(
      () => save(
        candidate: ReservationBook(
          id: book.id,
          isbn13: book.isbn13,
          title: ' ',
        ),
        wanted: true,
      ),
      throwsA(
        isA<ReservationIssue>().having((e) => e.code, 'code', 'book-title'),
      ),
    );
    expect(app.findReservationBook(book.isbn13!), isNull);
  });

  test('a saved book without a title is filled, a titled one is kept', () {
    app.db.execute(
      "INSERT INTO books (id, title, authors, isbn13, version, updated_at_utc, "
      "updated_by_device_id) VALUES (?, NULL, '[]', ?, 1, "
      "'2026-10-01T00:00:00Z', 'x')",
      [book.id, book.isbn13],
    );
    save(wanted: true);
    final filled = app.findReservationBook(book.isbn13!)!;
    expect(filled.title, '予約のテスト');
    expect(filled.authors, ['著者']);
    save(
      candidate: ReservationBook(
        id: book.id,
        isbn13: book.isbn13,
        title: '別の書名',
      ),
      wanted: true,
    );
    expect(app.findReservationBook(book.isbn13!)!.title, '予約のテスト');
    expect(
      app.db.select(
        "SELECT * FROM domain_events WHERE event_type = 'BookTitleCompleted'",
      ),
      hasLength(1),
    );
  });

  test('failure on the second loan rolls back book, loan, and every event', () {
    final before = {
      for (final t in [
        'books',
        'loans',
        'outbox_events',
        'applied_events',
        'domain_events',
      ])
        t: app.db.select('SELECT * FROM $t').length,
    };
    app.db.executeScript("""
      CREATE TRIGGER fail_reservation BEFORE INSERT ON loans
      WHEN NEW.system_id = 'Tokyo_Edogawa'
      BEGIN SELECT RAISE(ABORT, 'injected'); END;
    """);
    expect(save, throwsA(anything));
    for (final entry in before.entries) {
      expect(
        app.db.select('SELECT * FROM ${entry.key}'),
        hasLength(entry.value),
      );
    }
  });

  for (final status in ['reserved', 'ready_for_pickup', 'borrowed']) {
    test('$status rejects entire batch including the other system', () {
      save(systems: ['Tokyo_Koto']);
      app.db.execute('UPDATE loans SET status = ? WHERE book_id = ?', [
        status,
        book.id,
      ]);
      expect(
        save,
        throwsA(
          isA<ReservationIssue>().having((e) => e.code, 'code', 'active-wip'),
        ),
      );
      expect(
        app.db.select('SELECT * FROM loans WHERE book_id = ?', [book.id]),
        hasLength(1),
      );
    });
  }

  // **予約は読む意思を消さない**（2026-09-21）。予約した本はそのまま読みたいに入り、
  // 館を選ばない読みたいの操作も進行中の記録とは衝突しない。
  test(
    'reserving keeps the book wanted; want-to-read coexists with a loan',
    () {
      save(systems: ['Tokyo_Koto']);
      expect(
        app.db.select(
          'SELECT shelf_state FROM book_preferences WHERE book_id = ?',
          [book.id],
        ).single['shelf_state'],
        'wanted',
      );
      save(wanted: true);
      expect(
        app.db.select('SELECT * FROM loans WHERE book_id = ?', [book.id]),
        hasLength(1),
        reason: '読みたいは館を持たないので予約を増やさない',
      );
      expect(app.loadBookshelf(bookId: book.id).single.state, 'wanted');
    },
  );

  test('returned record allows another reservation', () {
    save(systems: ['Tokyo_Koto']);
    app.db.execute("UPDATE loans SET status = 'returned' WHERE book_id = ?", [
      book.id,
    ]);
    save(systems: ['Tokyo_Koto']);
    expect(
      app.db.select('SELECT * FROM loans WHERE book_id = ?', [book.id]),
      hasLength(2),
    );
  });

  test('existing bibliography stays byte-for-byte unchanged', () {
    save(wanted: true);
    final before = app.db.select('SELECT * FROM books WHERE id = ?', [
      book.id,
    ]).single;
    save(
      candidate: ReservationBook(
        id: book.id,
        isbn13: book.isbn13,
        title: 'APIの別タイトル',
        authors: const ['別の著者'],
      ),
    );
    expect(
      app.db.select('SELECT * FROM books WHERE id = ?', [book.id]).single,
      before,
    );
    // 予約しても読みたいは解除しない（2026-09-21）。
    expect(
      app.db.select(
        'SELECT want_to_read FROM book_preferences WHERE book_id = ?',
        [book.id],
      ).single['want_to_read'],
      1,
    );
  });

  test('missing preferred branch leaves everything uncommitted', () {
    expect(
      () => save(systems: ['Tokyo_Koto', 'Tokyo_Sumida']),
      throwsA(
        isA<ReservationIssue>().having(
          (e) => e.code,
          'code',
          'preferred-branch',
        ),
      ),
    );
    expect(app.findReservationBook(book.isbn13!), isNull);
  });

  test('ISBN-less drafts with equal titles remain distinct', () {
    final first = ReservationBook(
      id: app.reservationBookId(null),
      title: '同じ題名',
    );
    final second = ReservationBook(
      id: app.reservationBookId(null),
      title: '同じ題名',
    );
    save(candidate: first, wanted: true);
    save(candidate: second, wanted: true);
    expect(first.id, isNot(second.id));
    expect(
      app.db.select("SELECT * FROM books WHERE title = '同じ題名'"),
      hasLength(2),
    );
  });

  test(
    'preference snapshot roundtrips through SQLite and envelope validation',
    () {
      save(wanted: true);
      final row = app.db.select(
        'SELECT * FROM book_preferences WHERE book_id = ?',
        [book.id],
      ).single;
      final payload = app.domain.mapping.rowToPayload('book_preference', row);
      expect(payload['want_to_read'], true);
      app.domain.contracts.validatePayload('book_preference', payload);
      expect(
        app.domain.mapping.payloadToRow(
          'book_preference',
          payload,
        )['want_to_read'],
        1,
      );
    },
  );
}
