import 'bookshelf.dart';
import 'context.dart';

/// Business facts for the app export mapper; this type is never serialized.
class ShelfExportBook {
  final ShelfBook shelf;
  final String? readAt;
  final String? registeredAt;
  const ShelfExportBook(
    this.shelf, {
    required this.registeredAt,
    this.readAt,
  });
}

class BookshelfExport {
  final DomainContext context;
  const BookshelfExport(this.context);

  List<ShelfExportBook> read() {
    final books = {
      for (final row in context.db.select('SELECT * FROM books'))
        row['id']: row,
    };
    // Derive registration at export time; never persist or estimate it.
    final origins = <Object?, String>{};
    for (final row in context.db.select(
      "SELECT aggregate_id AS id, MIN(occurred_at_utc) AS at FROM domain_events WHERE aggregate_type = 'book' AND event_type = 'BookRegisteredFromReference' GROUP BY aggregate_id",
    )) {
      origins[row['id']] = row['at'] as String;
    }
    for (final row in context.db.select(
      "SELECT entity_id AS id, MIN(created_at_utc) AS at FROM outbox_events WHERE entity_type = 'book' AND base_version = 0 AND operation = 'upsert' GROUP BY entity_id",
    )) {
      final at = row['at'] as String;
      final previous = origins[row['id']];
      if (previous == null || at.compareTo(previous) < 0) {
        origins[row['id']] = at;
      }
    }
    final prefs = {
      for (final row in context.db.select(
        'SELECT * FROM book_preferences WHERE is_deleted = 0',
      ))
        row['book_id']: row,
    };
    final returns = <Object?, List<Map<String, Object?>>>{};
    for (final row in context.db.select(
      "SELECT book_id, first_return_basis, first_return_at_utc FROM loans WHERE status = 'returned' AND first_return_basis <> 'legacy' AND first_return_at_utc IS NOT NULL",
    )) {
      (returns[row['book_id']] ??= []).add(row);
    }
    return List.unmodifiable(
      Bookshelf(context).read().map((shelf) {
        final book = books[shelf.id]!;
        final pref = prefs[shelf.id];
        final basis = pref?['shelf_token'] ?? '';
        final times = [
          for (final returned in returns[shelf.id] ?? <Map<String, Object?>>[])
            if (returned['first_return_basis'] == basis)
              returned['first_return_at_utc'] as String,
          if (pref?['read_registered_at_utc'] != null)
            pref!['read_registered_at_utc'] as String,
        ]..sort();
        // Old manual dates describe reading days, not registration times.
        // Never reconstruct a timestamp from those dates or updated_at_utc.
        return ShelfExportBook(
          shelf,
          registeredAt:
              origins[shelf.id] ??
              (book['version'] == 1 ? book['updated_at_utc'] as String : null),
          readAt: times.isEmpty ? null : times.last,
        );
      }),
    );
  }
}
