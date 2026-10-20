enum BookshelfExportFormat { csv, json }

enum BookshelfExportAction { save, share }

enum BookshelfExportResult { saved, shared, dismissed, opened }

/// Immutable snapshot shared by preview and encoding.
class BookshelfExportSnapshot {
  final String exportedAt;
  final List<Map<String, Object?>> books;
  BookshelfExportSnapshot(this.exportedAt, Iterable<Map<String, Object?>> books)
    : books = List.unmodifiable(books.map(Map<String, Object?>.unmodifiable));
}
