/// One book, all selected systems, and its preference commit together.
library;

import 'dart:convert';
import 'package:karita_contract/karita_contract.dart';
import 'context.dart';
import 'bookshelf.dart';
import 'errors.dart';
import 'library_settings.dart';
import 'library_systems.dart';

class ReservationBook {
  final String id;
  final String title;
  final List<String> authors;
  final String? isbn13;
  final String provider;
  final String? sourceUrl;
  const ReservationBook({
    required this.id,
    required this.title,
    this.authors = const [],
    this.isbn13,
    this.provider = 'manual',
    this.sourceUrl,
  });
}

class ReservationIssue extends DomainError {
  final List<String> systems;
  const ReservationIssue(
    super.message, {
    required super.code,
    this.systems = const [],
  });
}

class Reservations {
  final DomainContext context;
  const Reservations(this.context);

  ReservationBook? findBook(String isbn) {
    final rows = context.db.select(
      'SELECT * FROM books WHERE isbn13 = ? AND is_deleted = 0 ORDER BY id',
      [isbn],
    );
    if (rows.length > 1) {
      throw const ReservationIssue(
        'Multiple saved books have this ISBN.',
        code: 'ambiguous-book',
      );
    }
    return rows.isEmpty ? null : _book(rows.single);
  }

  List<ReservationBook> books() => context.db
      .select('SELECT * FROM books WHERE is_deleted = 0 ORDER BY id')
      .map(_book)
      .toList();

  static ReservationBook _book(Map<String, Object?> row) => ReservationBook(
    id: row['id'] as String,
    title: row['title'] as String? ?? '',
    isbn13: row['isbn13'] as String?,
    authors: (jsonDecode(row['authors'] as String) as List).cast<String>(),
    provider: 'saved',
  );

  List<String> activeSystems(String bookId) => context.db
      .select(
        "SELECT DISTINCT system_id FROM loans WHERE book_id = ? AND status IN "
        "('reserved','ready_for_pickup','borrowed')",
        [bookId],
      )
      .map((r) => r['system_id'])
      .whereType<String>()
      .toList();

  /// Reuses an existing book without writing it. Validation is inside the lock.
  String save({
    required ReservationBook book,
    required String operationId,
    required List<String> systems,
    required bool wanted,
    required String reservedOn,
    required String now,
  }) => transaction(context.db, () {
    final existing = book.isbn13 == null ? null : findBook(book.isbn13!);
    final bookId = existing?.id ?? book.id;
    final row = context.aggregates.read(context.db, entityBook, bookId);
    if (existing == null && row != null && row['isbn13'] != book.isbn13) {
      throw const ReservationIssue(
        'This book identity has a different ISBN.',
        code: 'book-identity-conflict',
      );
    }
    if (row != null && row['is_deleted'] == 1) {
      throw const ReservationIssue('Book was deleted.', code: 'book-deleted');
    }
    final selected = systems.toSet().toList();
    if (!wanted && selected.isEmpty) {
      throw const ReservationIssue(
        'Select a library system.',
        code: 'no-system',
      );
    }
    final ids = {
      for (final s in selected)
        s: deterministicId(entityLoan, '$operationId/$s'),
    };
    // An exact retry of a completed operation must not emit another event.
    if (!wanted &&
        ids.values.every((id) {
          final previous = context.aggregates.read(context.db, entityLoan, id);
          return previous != null && previous['book_id'] == bookId;
        })) {
      return bookId;
    }
    final active = activeSystems(bookId);
    // **読みたいは館を持たないので、進行中の記録とも併存する**（2026-09-21）。止めるのは
    // 同じ館の予約を二重に作る操作だけである。
    final duplicates = wanted
        ? const <String>[]
        : selected.where(active.contains).toList();
    if (duplicates.isNotEmpty) {
      throw ReservationIssue(
        'An active loan already exists.',
        code: 'active-wip',
        systems: duplicates,
      );
    }
    final branches = <String, String>{};
    if (!wanted) {
      final date = DateTime.tryParse(reservedOn);
      if (date == null ||
          date.toIso8601String().substring(0, 10) != reservedOn) {
        throw const ReservationIssue(
          'Invalid reservation date.',
          code: 'reservation-date',
        );
      }
      for (final s in selected) {
        final system = LibrarySystems(context).read(s);
        final branch = LibrarySettings(
          context,
        ).valueOf(s, settingPreferredBranch);
        if (system == null || branch == null || !system.hasBranch(branch)) {
          throw ReservationIssue(
            'Set a valid preferred branch.',
            code: 'preferred-branch',
            systems: [s],
          );
        }
        branches[s] = branch;
      }
    }
    if (row == null) {
      // **書名は必須である**（2026-10-08）。書名が無いと何の本か分からない。openBD に無い
      // ISBN でも、利用者が図書館サイトなどから書名を写してから登録する。
      if (book.title.trim().isEmpty) {
        throw const ReservationIssue(
          'A title is required.',
          code: 'book-title',
        );
      }
      if (book.isbn13 != null &&
          book.id != deterministicId(entityBook, book.isbn13!)) {
        throw const ReservationIssue('Invalid book identity.', code: 'book-id');
      }
      context.emit(
        entityType: entityBook,
        entityId: bookId,
        payload: {
          'title': book.title.trim().isEmpty ? null : book.title.trim(),
          'authors': book.authors,
          'isbn13': book.isbn13,
          'book_references': [
            {
              'provider': book.provider,
              if (book.isbn13 != null) 'external_id': book.isbn13,
              if (book.sourceUrl != null) 'source_url': book.sourceUrl,
              'retrieved_at_utc': now,
              'field_snapshot': {'title': book.title, 'authors': book.authors},
            },
          ],
        },
        domainEventType: 'BookRegisteredFromReference',
        aggregateType: 'book',
        now: now,
      );
    } else if (row['title'] == null && book.title.trim().isNotEmpty) {
      // **空の書名を埋めるときだけ既存 Book を書く**（2026-10-08）。書名の在る Book は
      // 従来どおり上書きしない。著者も空のときだけ埋める。
      final payload = context.mapping.rowToPayload(entityBook, row);
      payload['title'] = book.title.trim();
      if ((payload['authors'] as List?)?.isEmpty ?? true) {
        payload['authors'] = book.authors;
      }
      context.emit(
        entityType: entityBook,
        entityId: bookId,
        payload: payload,
        domainEventType: 'BookTitleCompleted',
        aggregateType: 'book',
        now: now,
      );
    }
    for (final s in wanted ? <String>[] : selected) {
      context.emit(
        entityType: entityLoan,
        entityId: ids[s]!,
        payload: {
          'book_id': bookId,
          'system_id': s,
          'status': 'reserved',
          'pickup_library_id': branches[s],
          'reserved_on': reservedOn,
        },
        domainEventType: 'LoanReserved',
        aggregateType: 'loan',
        now: now,
      );
    }
    final shelf = Bookshelf(context);
    // **予約した本も本棚の「読みたい」に入れる**（2026-09-21）。予約は読む意思を消さない。
    // 読んだ・本棚から外すの明示指定は上書きしない。返却は既存の規則で読んだへ移す。
    final current = shelf
        .read(bookId: bookId, includeHidden: true)
        .firstOrNull
        ?.state;
    if (wanted || current == 'none') {
      shelf.emitState(bookId, 'wanted', now: now);
    }
    return bookId;
  });
}
