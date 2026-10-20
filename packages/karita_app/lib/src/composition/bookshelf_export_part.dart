part of '../composition.dart';

extension CompositionBookshelfExport on Composition {
  BookshelfExportAction get bookshelfExportAction =>
      _exportDelivery.kind == ExportDeliveryKind.save
      ? BookshelfExportAction.save
      : BookshelfExportAction.share;

  BookshelfExportSnapshot prepareBookshelfExport() {
    _requireOpen();
    final db = domain.db;
    // A deferred read transaction also works with SQLite query_only enabled.
    db.execute('BEGIN');
    try {
      final snapshot = shelfExportSnapshot(
        BookshelfExport(domain).read(),
        nowUtc(),
      );
      db.execute('COMMIT');
      return snapshot;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<BookshelfExportResult> exportBookshelf(
    BookshelfExportSnapshot snapshot,
    BookshelfExportFormat format,
  ) async {
    _requireOpen();
    try {
      final bytes = format == BookshelfExportFormat.csv
          ? encodeBookshelfCsv(snapshot)
          : encodeBookshelfJson(snapshot);
      final stamp = snapshot.exportedAt.replaceAll(RegExp('[:-]'), '');
      final result = await _exportDelivery.deliver(
        bytes: bytes,
        filename: 'karita-bookshelf-$stamp.${format.name}',
        mimeType: format == BookshelfExportFormat.csv
            ? 'text/csv'
            : 'application/json',
      );
      _log.info('bookshelf.export.completed', {
        'format': format.name,
        'count': snapshot.books.length,
        'result': result.name,
      });
      return BookshelfExportResult.values.byName(result.name);
    } catch (error) {
      _log.warning('bookshelf.export.failed', {
        'type': error.runtimeType.toString(),
      });
      throw const AppIssue(
        'bookshelf-export',
        '本棚をエクスポートできませんでした。もう一度お試しください。',
      );
    }
  }
}
