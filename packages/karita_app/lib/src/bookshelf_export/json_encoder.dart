import 'dart:convert';
import 'dart:typed_data';
import 'models.dart';

Uint8List encodeBookshelfJson(BookshelfExportSnapshot snapshot) =>
    Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'schema_version': 2,
          'exported_at_utc': snapshot.exportedAt,
          'books': snapshot.books,
        }),
      ),
    );
