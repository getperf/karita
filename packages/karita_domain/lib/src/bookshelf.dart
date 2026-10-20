/// Book単位の本棚。返却履歴はLoanを正本とし、別の同期集約へ複製しない。
library;

import 'dart:convert';
import 'package:karita_contract/karita_contract.dart';
import 'context.dart';
import 'errors.dart';

class ShelfIssue extends DomainError {
  const ShelfIssue(super.message, {required super.code});
}

class ShelfHistory {
  final String id;
  final String? systemId, branchId, returnedOn;
  final bool manual;
  const ShelfHistory(
    this.id,
    this.systemId,
    this.branchId,
    this.returnedOn, {
    this.manual = false,
  });
}

class ShelfBook {
  final String id, title, state, changedAt, reason, review, reviewRevision;
  final List<String> authors;
  final String? isbn13;
  final int? rating;
  final List<ShelfHistory> histories;

  /// 進行中のLoanの状態（`reserved`・`ready_for_pickup`・`borrowed`）。
  /// 読みたいと予約中は併存するので、本棚からも手続き中だと分かるようにする。
  final List<String> activeStatuses;
  const ShelfBook({
    required this.id,
    required this.title,
    required this.authors,
    required this.isbn13,
    required this.state,
    required this.changedAt,
    required this.reason,
    required this.histories,
    required this.activeStatuses,
    required this.rating,
    required this.review,
    required this.reviewRevision,
  });
  String? get latestReturn {
    final dates =
        histories
            .where((h) => !h.manual)
            .map((h) => h.returnedOn)
            .whereType<String>()
            .toList()
          ..sort();
    return dates.isEmpty ? null : dates.last;
  }
}

class Bookshelf {
  final DomainContext context;
  const Bookshelf(this.context);

  Map<String, Object?>? preference(String bookId) => context.aggregates.read(
    context.db,
    entityBookPreference,
    deterministicId(entityBookPreference, bookId),
  );

  /// 空文字は手動指定を一度も観測していないことを表す。
  String token(String bookId) =>
      preference(bookId)?['shelf_token'] as String? ?? '';

  List<ShelfBook> read({String? bookId, bool includeHidden = false}) {
    // **1冊の読み取りで台帳を全部読まない。** 状態変更・レビュー保存・予約保存はどれも
    // この口を通るので、全件走査のままだと書込みが件数に比例して重くなる。索引は
    // `book_preferences(book_id)`・`book_reviews(book_id)`・`loans(book_id)` と `books` の主鍵。
    final one = bookId != null;
    final args = one ? [bookId] : const <Object?>[];
    final preferences = {
      for (final r in context.db.select(
        'SELECT * FROM book_preferences WHERE is_deleted = 0'
        '${one ? ' AND book_id = ?' : ''}',
        args,
      ))
        r['book_id']: r,
    };
    final reviews = {
      for (final r in context.db.select(
        'SELECT * FROM book_reviews${one ? ' WHERE book_id = ?' : ''}',
        args,
      ))
        r['book_id']: r,
    };
    final loans = <Object?, List<Map<String, Object?>>>{};
    for (final r in context.db.select(
      "SELECT * FROM loans WHERE status = 'returned'"
      '${one ? ' AND book_id = ?' : ''}',
      args,
    )) {
      (loans[r['book_id']] ??= []).add(r);
    }
    // 手続き中のLoanは状態だけ持つ。館・期限の正本は貸出し画面にある。
    final active = <Object?, Set<String>>{};
    for (final r in context.db.select(
      "SELECT book_id, status FROM loans WHERE status IN ('reserved','ready_for_pickup','borrowed')"
      '${one ? ' AND book_id = ?' : ''}',
      args,
    )) {
      (active[r['book_id']] ??= <String>{}).add(r['status'] as String);
    }
    final result = <ShelfBook>[];
    for (final b in context.db.select(
      'SELECT * FROM books WHERE is_deleted = 0${one ? ' AND id = ?' : ''}',
      args,
    )) {
      final id = b['id'] as String;
      final p = preferences[id];
      final returns = loans[id] ?? [];
      final manual = _array(p?['manual_reads']);
      final explicit = p?['shelf_state'] as String?;
      final basis = p?['shelf_token'] as String? ?? '';
      // 初回返却だけが、その時点で観測した手動指定を超えられる。
      // 再送・日付訂正・再返却はbasisを変えない。未知の旧返却も指定を超えない。
      final newReturns = returns
          .where((r) => r['first_return_basis'] == basis)
          .toList();
      String state;
      if (newReturns.isNotEmpty) {
        state = 'read';
      } else if (explicit != null && explicit != 'none') {
        state = explicit;
      } else if (explicit == null && p?['want_to_read'] == 1) {
        state = 'wanted';
      } else {
        state = returns.isNotEmpty || manual.isNotEmpty ? 'read' : 'none';
      }
      if (!includeHidden && state != 'read' && state != 'wanted') continue;
      final history = <ShelfHistory>[
        for (final r in returns)
          ShelfHistory(
            r['id'] as String,
            r['system_id'] as String?,
            (r['pickup_library_id'] ?? r['library_id']) as String?,
            r['returned_on'] as String?,
          ),
        for (final r in manual)
          ShelfHistory(
            r['id'] as String,
            null,
            null,
            r['on'] as String?,
            manual: true,
          ),
      ]..sort((a, b) => (b.returnedOn ?? '').compareTo(a.returnedOn ?? ''));
      final dates = <String>[
        p?['shelf_changed_at_utc'] as String? ??
            p?['updated_at_utc'] as String? ??
            '',
        for (final r in returns)
          r['first_return_at_utc'] as String? ??
              r['returned_on'] as String? ??
              '',
      ]..sort();
      final review = reviews[id];
      result.add(
        ShelfBook(
          id: id,
          title: b['title'] as String? ?? '書名なし',
          authors: (jsonDecode(b['authors'] as String) as List).cast<String>(),
          isbn13: b['isbn13'] as String?,
          state: state,
          changedAt: dates.last,
          reason:
              returns.isNotEmpty &&
                  (newReturns.isNotEmpty || explicit != 'read')
              ? '返却済み'
              : '手動登録',
          histories: List.unmodifiable(history),
          activeStatuses: List.unmodifiable([
            for (final s in const ['reserved', 'ready_for_pickup', 'borrowed'])
              if (active[id]?.contains(s) ?? false) s,
          ]),
          rating: review?['rating'] as int?,
          review: review?['review'] as String? ?? '',
          reviewRevision: _revision(review),
        ),
      );
    }
    result.sort((a, b) {
      final n = b.changedAt.compareTo(a.changedAt);
      return n == 0 ? a.id.compareTo(b.id) : n;
    });
    return result;
  }

  void setState(
    String bookId,
    String target, {
    required String now,
    String? readOn,
  }) => transaction(
    context.db,
    () => emitState(bookId, target, now: now, readOn: readOn),
  );

  /// 予約の複数館保存と同じ取引で呼ぶ。自分では取引を開かない。
  void emitState(
    String bookId,
    String target, {
    required String now,
    String? readOn,
  }) {
    if (!['wanted', 'read', 'removed', 'none'].contains(target)) {
      throw const ShelfIssue('Unknown shelf state.', code: 'shelf-state');
    }
    final current = read(bookId: bookId, includeHidden: true);
    if (current.isEmpty) {
      throw const ShelfIssue('Book unavailable.', code: 'book-missing');
    }
    // 読みたいは館を持たない読む意思なので、予約中・取置中・貸出中と併存させる（2026-09-21）。
    if (current.single.state == target) return;
    final p = preference(bookId);
    final payload = p == null || p['is_deleted'] == 1
        ? <String, Object?>{'book_id': bookId}
        : context.mapping.rowToPayload(entityBookPreference, p);
    // Preserve an observed read registration before changing the manual basis.
    // A stale, unobserved return must not create a new registration.
    final returnTimes = context.db
        .select(
          "SELECT first_return_at_utc FROM loans WHERE book_id = ? AND status = 'returned' AND first_return_basis = ? AND first_return_at_utc IS NOT NULL",
          [bookId, p?['shelf_token'] ?? ''],
        )
        .map((r) => r['first_return_at_utc'] as String)
        .toList();
    final previousRead = payload['read_registered_at_utc'] as String?;
    if (previousRead != null) returnTimes.add(previousRead);
    if (returnTimes.isNotEmpty) {
      returnTimes.sort();
      payload['read_registered_at_utc'] = returnTimes.last;
    }
    final operation = context.uuid();
    payload.addAll({
      'want_to_read': target == 'wanted',
      'shelf_state': target,
      'shelf_token': operation,
      'shelf_changed_at_utc': now,
    });
    if (target == 'wanted') payload['wanted_registered_at_utc'] = now;
    if (target == 'read') {
      payload['read_registered_at_utc'] = now;
      payload['manual_reads'] = [
        ..._array(p?['manual_reads']),
        {'id': operation, 'on': readOn ?? now.substring(0, 10)},
      ];
    }
    context.emit(
      entityType: entityBookPreference,
      entityId: deterministicId(entityBookPreference, bookId),
      payload: payload,
      domainEventType: 'BookShelfChanged',
      aggregateType: entityBookPreference,
      now: now,
    );
  }

  void saveReview(
    String bookId, {
    required int? rating,
    required String review,
    required String expectedRevision,
    required String now,
  }) => transaction(context.db, () {
    final books = read(bookId: bookId);
    if (books.isEmpty || books.single.state != 'read') {
      throw const ShelfIssue('Review is read only.', code: 'review-read-only');
    }
    if (rating != null && (rating < 1 || rating > 5)) {
      throw const ShelfIssue('Rating must be 1..5.', code: 'review-rating');
    }
    final id = deterministicId(entityBookReview, bookId);
    final previous = context.aggregates.read(context.db, entityBookReview, id);
    if (_revision(previous) != expectedRevision) {
      throw const ShelfIssue(
        'Review changed on another device.',
        code: 'review-conflict',
      );
    }
    if (books.single.rating == rating && books.single.review == review.trim()) {
      return;
    }
    context.emit(
      entityType: entityBookReview,
      entityId: id,
      payload: {'book_id': bookId, 'rating': rating, 'review': review.trim()},
      domainEventType: 'BookReviewSaved',
      aggregateType: entityBookReview,
      now: now,
    );
  });
}

List<Map<String, dynamic>> _array(Object? value) => value == null
    ? []
    : (jsonDecode(value as String) as List).cast<Map<String, dynamic>>();
String _revision(Map<String, Object?>? r) => r == null
    ? ''
    : '${r['version']}/${r['updated_by_device_id']}/${r['updated_at_utc']}/${r['rating']}/${r['review']}';
