import 'dart:convert';
import 'dart:typed_data';
import 'models.dart';

const shelfExportColumns = <String, String>{
  'title': 'タイトル',
  'authors': '著者',
  'isbn13': 'ISBN-13',
  'shelf_state': '本棚状態',
  'book_registered_at_utc': '登録日時',
  'read_registered_at_utc': '読んだ日時',
  'read_count': '読書記録件数',
  'rating': 'レーティング',
  'review': 'コメント',
};

String _cell(Object? value) {
  var text = value is List ? value.join('\n') : value?.toString() ?? '';
  // Quoting alone does not prevent spreadsheets from evaluating formulas.
  if (RegExp(r'^[\s\uFEFF]*[=+@-]').hasMatch(text) ||
      text.startsWith('\t') ||
      text.startsWith('\r')) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}

Uint8List encodeBookshelfCsv(BookshelfExportSnapshot snapshot) {
  final rows = <String>[shelfExportColumns.values.map(_cell).join(',')];
  for (final book in snapshot.books) {
    rows.add(
      shelfExportColumns.keys
          .map((key) {
            final value = book[key];
            return _cell(
              key == 'shelf_state'
                  ? (value == 'wanted' ? '読みたい' : '読んだ')
                  : value,
            );
          })
          .join(','),
    );
  }
  return Uint8List.fromList(utf8.encode('\uFEFF${rows.join('\r\n')}\r\n'));
}
