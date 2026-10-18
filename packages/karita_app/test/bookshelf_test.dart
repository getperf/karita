import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_contract/src/generated/migrations.g.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bookshelf session token changes only when the database is replaced',
    () async {
      final root = Directory.systemTemp.createTempSync('karita-shelf-session-');
      final composition = await compose(
        paths: WindowsAppPaths.at(root.path)..ensure(),
        settings: const DeviceSettings(),
        mode: const AppMode(DemoMode.temp),
      );
      try {
        final token = composition.ledgerSessionToken;
        expect(identical(token, composition.ledgerSessionToken), isTrue);
        composition.session.reopen();
        expect(identical(token, composition.ledgerSessionToken), isFalse);
      } finally {
        composition.close();
        root.deleteSync(recursive: true);
      }
    },
  );
  late Directory home;
  late Composition app;
  late ReservationBook book;
  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-bookshelf-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
    book = ReservationBook(
      id: app.reservationBookId(null),
      title: '本棚のテスト',
      authors: ['著者'],
    );
    app.saveReservation(
      book: book,
      operationId: app.newReservationId(),
      systems: [],
      wanted: true,
    );
  });
  tearDown(() {
    app.close();
    home.deleteSync(recursive: true);
  });
  ShelfBook row() =>
      app.loadBookshelf(bookId: book.id, includeHidden: true).single;
  String reserve() {
    app.saveReservation(
      book: book,
      operationId: app.newReservationId(),
      systems: ['Tokyo_Koto'],
      wanted: false,
    );
    return app.db.select(
          "SELECT id FROM loans WHERE book_id = ? AND status = 'reserved'",
          [book.id],
        ).single['id']
        as String;
  }

  test(
    'return, correction, exclusion and a different loan; review survives',
    () {
      final loan = reserve();
      // 予約は読む意思を消さない。読みたいのまま手続き中と併存する。
      expect(row().state, 'wanted');
      expect(row().activeStatuses, ['reserved']);
      app.updateLoan(loanId: loan, action: 'return');
      expect(row().state, 'read');
      app.saveBookReview(
        book.id,
        rating: 4,
        review: '記録',
        expectedRevision: '',
      );
      app.setShelfState(book.id, 'removed');
      app.updateLoan(loanId: loan, action: 'return', returnedOn: '2026-09-18');
      expect(row().state, 'removed');
      app.updateLoan(loanId: loan, action: 'borrow');
      expect(row().histories, isEmpty);
      app.updateLoan(loanId: loan, action: 'return');
      expect(row().state, 'removed');
      expect(row().histories, hasLength(1));
      final another = reserve();
      app.updateLoan(loanId: another, action: 'return');
      expect(row().state, 'read');
      expect(row().histories, hasLength(2));
      expect(row().rating, 4);
      expect(row().review, '記録');
      app.updateLoan(loanId: another, action: 'reserve');
      expect(row().state, 'removed');
    },
  );

  test('manual read survives return correction; wanted coexists with a loan', () {
    final loan = reserve();
    // 手続き中でも本棚の指定は自由に変えられる（2026-09-21）。
    app.setShelfState(book.id, 'removed');
    app.setShelfState(book.id, 'wanted');
    expect(row().state, 'wanted');
    expect(row().activeStatuses, ['reserved']);
    app.setShelfState(book.id, 'read');
    app.updateLoan(loanId: loan, action: 'return');
    app.updateLoan(loanId: loan, action: 'cancel');
    expect(row().state, 'read');
    expect(row().histories.single.manual, isTrue);
    app.setShelfState(book.id, 'wanted');
    expect(row().state, 'wanted');
    expect(
      () => app.saveBookReview(
        book.id,
        rating: 3,
        review: '',
        expectedRevision: '',
      ),
      throwsA(isA<ShelfIssue>()),
    );
  });

  test(
    'cancel keeps the shelf as it is; ratings and review deletion are independent',
    () {
      final loan = reserve();
      // 取消は本棚を動かさない。予約で入れた読みたいはそのまま残る。
      app.updateLoan(loanId: loan, action: 'cancel');
      expect(row().state, 'wanted');
      expect(row().activeStatuses, isEmpty);
      app.setShelfState(book.id, 'read');
      app.saveBookReview(book.id, rating: 5, review: '', expectedRevision: '');
      final version = row().reviewRevision;
      app.saveBookReview(
        book.id,
        rating: null,
        review: '本文だけ',
        expectedRevision: version,
      );
      expect(
        () => app.saveBookReview(
          book.id,
          rating: 1,
          review: '古い入力',
          expectedRevision: version,
        ),
        throwsA(isA<ShelfIssue>()),
      );
      app.saveBookReview(
        book.id,
        rating: null,
        review: '',
        expectedRevision: row().reviewRevision,
      );
      expect(row().review, '');
      expect(row().rating, isNull);
      expect(row().state, 'read');
    },
  );

  test('failed shelf write rolls back book adoption and all emission tables', () {
    final before = {
      for (final t in [
        'books',
        'book_preferences',
        'outbox_events',
        'applied_events',
        'domain_events',
      ])
        t: app.db.select('SELECT * FROM $t').length,
    };
    app.db.executeScript(
      "CREATE TRIGGER fail_shelf BEFORE INSERT ON book_preferences BEGIN SELECT RAISE(ABORT, 'injected'); END;",
    );
    expect(
      () => app.saveReservation(
        book: ReservationBook(id: app.reservationBookId(null), title: '失敗'),
        operationId: app.newReservationId(),
        systems: [],
        wanted: true,
      ),
      throwsA(anything),
    );
    for (final t in before.keys) {
      expect(app.db.select('SELECT * FROM $t'), hasLength(before[t]!));
    }
  });

  test(
    'reverse delivery and replay reproduce projection without local emissions',
    () {
      final loan = reserve();
      app.updateLoan(loanId: loan, action: 'return');
      app.setShelfState(book.id, 'removed');
      final target = SqliteDb.memory();
      addTearDown(target.close);
      migrate(target, now: '2026-09-20T00:00:00Z');
      final applier = Applier(Contracts.load());
      final events = app.db.select('SELECT * FROM outbox_events');
      final incoming = [
        for (final r in events.reversed)
          RemoteEvent(
            remoteId: '${r['event_id']}.json',
            eventId: r['event_id'] as String,
            text: envelopeFromOutboxRow(
              EnvelopeCodec(Contracts.load()),
              r,
            ).canonicalText(),
            createdAtUtc: '2026-09-20T00:00:00Z',
          ),
      ];
      for (var i = 0; i < 2; i++) {
        applier.applyIncoming(
          target,
          incoming,
          now: '2026-09-20T00:00:00Z',
          runId: app.newReservationId(),
          conflictIdFactory: app.newReservationId,
        );
      }
      final shelf = Bookshelf(
        DomainContext.fixed(
          db: target,
          contracts: Contracts.load(),
          deviceId: 'receiver',
          uuid: app.newReservationId,
        ),
      );
      final received = shelf.read(bookId: book.id, includeHidden: true).single;
      expect(received.state, 'removed');
      expect(received.histories, hasLength(1));
      expect(target.select('SELECT * FROM outbox_events'), isEmpty);
    },
  );

  test('0012 legacy data migrate without emits; wanted wins over old returned', () {
    final db = SqliteDb.memory();
    addTearDown(db.close);
    migrate(
      db,
      now: '2026-09-01T00:00:00Z',
      sources: {
        for (final e in migrationSources.entries)
          if (!e.key.startsWith('0013')) e.key: e.value,
      },
    );
    db.execute(
      "INSERT INTO books(id,title,authors,version,updated_at_utc,updated_by_device_id) VALUES(?, '旧本', '[]', 1, '2026-09-01T00:00:00Z', 'old')",
      [book.id],
    );
    db.execute(
      "INSERT INTO loans(id,book_id,status,version,updated_at_utc,updated_by_device_id) VALUES(?,?,'returned',1,'2026-09-01T00:00:00Z','old')",
      [app.newReservationId(), book.id],
    );
    db.execute(
      "INSERT INTO book_preferences(id,book_id,want_to_read,version,updated_at_utc,updated_by_device_id) VALUES(?,?,1,1,'2026-09-01T00:00:00Z','old')",
      [deterministicId(entityBookPreference, book.id), book.id],
    );
    migrate(db, now: '2026-09-20T00:00:00Z');
    expect(migrate(db, now: '2026-09-20T00:00:00Z'), isEmpty);
    final shelf = Bookshelf(
      DomainContext.fixed(
        db: db,
        contracts: Contracts.load(),
        deviceId: 'new',
        uuid: app.newReservationId,
      ),
    );
    expect(shelf.read().single.state, 'wanted');
    expect(shelf.read().single.histories.single.returnedOn, isNull);
    expect(db.select('SELECT * FROM outbox_events'), isEmpty);
    db.execute('UPDATE book_preferences SET want_to_read = 0');
    expect(shelf.read().single.state, 'read');
  });

  test('legacy writer cannot erase shelf metadata and is retained pending', () {
    final loan = reserve();
    app.updateLoan(loanId: loan, action: 'return');
    final r = app.domain.aggregates.read(app.db, entityLoan, loan)!;
    final payload = app.domain.mapping.rowToPayload(entityLoan, r)
      ..remove('first_return_basis')
      ..remove('first_return_at_utc');
    final e = EnvelopeCodec(Contracts.load()).build(
      eventId: app.newReservationId(),
      deviceId: 'old-device',
      createdAtUtc: '2026-09-20T01:00:00Z',
      entityType: entityLoan,
      entityId: loan,
      operation: 'upsert',
      baseVersion: r['version'],
      resultVersion: (r['version'] as int) + 1,
      payload: payload,
      schemaVersion: 2,
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
      now: '2026-09-20T01:00:00Z',
      runId: app.newReservationId(),
      conflictIdFactory: app.newReservationId,
    );
    expect(
      app.db.select('SELECT * FROM pending_events WHERE event_id = ?', [
        e.eventId,
      ]),
      hasLength(1),
    );
    expect(
      app.domain.aggregates.read(
        app.db,
        entityLoan,
        loan,
      )!['first_return_at_utc'],
      isNotNull,
    );
  });

  test('two offline devices: unobserved return cannot undo removal', () {
    final loan = reserve();
    final copy = '${home.path}/offline.db';
    app.db.execute('VACUUM INTO ?', [copy]);
    final db = SqliteDb.open(copy);
    addTearDown(db.close);
    final remote = DomainContext.fixed(
      db: db,
      contracts: Contracts.load(),
      deviceId: 'offline-device',
      uuid: app.newReservationId,
    );
    Loans(
      remote,
    ).update(loanId: loan, action: 'return', now: '2026-09-20T10:00:00Z');
    app.setShelfState(book.id, 'removed');
    void transfer(Db from, Db to) {
      final codec = EnvelopeCodec(Contracts.load());
      final incoming = [
        for (final r in from.select('SELECT * FROM outbox_events'))
          RemoteEvent(
            remoteId: r['event_id'] as String,
            eventId: r['event_id'] as String,
            text: envelopeFromOutboxRow(codec, r).canonicalText(),
            createdAtUtc: r['created_at_utc'] as String,
          ),
      ];
      Applier(Contracts.load()).applyIncoming(
        to,
        incoming,
        now: '2026-09-20T11:00:00Z',
        runId: app.newReservationId(),
        conflictIdFactory: app.newReservationId,
      );
    }

    transfer(db, app.db);
    transfer(app.db, db);
    expect(row().state, 'removed');
    expect(
      Bookshelf(remote).read(bookId: book.id, includeHidden: true).single.state,
      'removed',
    );
    expect(row().histories, hasLength(1));
  });

  test('review on one device and shelf change on another do not conflict', () {
    app.setShelfState(book.id, 'read');
    final copy = '${home.path}/review-offline.db';
    app.db.execute('VACUUM INTO ?', [copy]);
    final db = SqliteDb.open(copy);
    addTearDown(db.close);
    final remote = DomainContext.fixed(
      db: db,
      contracts: Contracts.load(),
      deviceId: 'review-device',
      uuid: app.newReservationId,
    );
    Bookshelf(remote).saveReview(
      book.id,
      rating: 3,
      review: '別端末のレビュー',
      expectedRevision: '',
      now: '2026-09-20T10:00:00Z',
    );
    app.setShelfState(book.id, 'wanted');
    final r = db.select(
      'SELECT * FROM outbox_events WHERE entity_type = ? AND entity_id = ?',
      [entityBookReview, deterministicId(entityBookReview, book.id)],
    ).single;
    final e = envelopeFromOutboxRow(EnvelopeCodec(Contracts.load()), r);
    final report = Applier(Contracts.load()).applyIncoming(
      app.db,
      [
        RemoteEvent(
          remoteId: e.eventId,
          eventId: e.eventId,
          text: e.canonicalText(),
          createdAtUtc: e.createdAtUtc,
        ),
      ],
      now: '2026-09-20T11:00:00Z',
      runId: app.newReservationId(),
      conflictIdFactory: app.newReservationId,
    );
    expect(report.conflicted, 0);
    expect(row().state, 'wanted');
    expect(row().rating, 3);
    expect(row().review, '別端末のレビュー');
  });

  test(
    'backup restore keeps review, history and exclusion without audit events',
    () {
      final loan = reserve();
      app.updateLoan(loanId: loan, action: 'return');
      app.saveBookReview(
        book.id,
        rating: 4,
        review: 'バックアップ',
        expectedRevision: '',
      );
      app.setShelfState(book.id, 'removed');
      final source = '${home.path}/source.db';
      app.db.execute('VACUUM INTO ?', [source]);
      final backupId = app.newReservationId();
      final archive = '${home.path}/${backupName(backupId)}';
      createBackup(
        source,
        archive,
        now: '2026-09-20T01:00:00Z',
        backupId: backupId,
        sourceDeviceId: app.deviceId,
        sourceProfile: 'default',
        sourcePlatform: 'windows',
      );
      final target = '${home.path}/restored.db';
      restoreBackup(
        archive,
        target,
        now: '2026-09-20T02:00:00Z',
        deviceId: 'restored',
        profile: 'default',
        generationId: app.newReservationId(),
        generationSeq: 1,
      );
      final db = SqliteDb.open(target);
      addTearDown(db.close);
      final shelf = Bookshelf(
        DomainContext.fixed(
          db: db,
          contracts: Contracts.load(),
          deviceId: 'restored',
          uuid: app.newReservationId,
        ),
      );
      final b = shelf.read(bookId: book.id, includeHidden: true).single;
      expect(b.state, 'removed');
      expect(b.review, 'バックアップ');
      expect(b.rating, 4);
      expect(b.histories, hasLength(1));
      expect(db.select('SELECT * FROM domain_events'), isEmpty);
    },
  );
}
