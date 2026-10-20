import 'package:karita_domain/karita_domain.dart';
import 'models.dart';

BookshelfExportSnapshot shelfExportSnapshot(
  List<ShelfExportBook> books,
  String now,
) => BookshelfExportSnapshot(
  now,
  books.map((book) {
    final shelf = book.shelf;
    return <String, Object?>{
      'title': shelf.title,
      'authors': List<String>.unmodifiable(shelf.authors),
      'isbn13': shelf.isbn13,
      'shelf_state': shelf.state,
      'book_registered_at_utc': book.registeredAt,
      'read_registered_at_utc': book.readAt,
      'read_count': shelf.histories.length,
      'rating': shelf.rating,
      'review': shelf.review,
    };
  }),
);
