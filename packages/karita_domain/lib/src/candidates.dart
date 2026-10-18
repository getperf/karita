/// 外部書誌検索から得る、一時的な候補の型。
///
/// 移送元: book-sync-model の `src/bops_domain/candidates.py`。
library;

/// 利用者が採用する前の書誌候補。
///
/// **検索結果は台帳の正本ではない**ため、価格・在庫・レビューは含めない。ISBN がない候補も
/// 表示できるが、所蔵照会の対象にはできない。
class BookCandidate {
  final String title;
  final List<String> authors;
  final String? publisherName;
  final String? isbn13;
  final String? imageUrl;
  final String? sourceUrl;
  final String provider;

  const BookCandidate({
    required this.title,
    required this.authors,
    required this.provider,
    this.publisherName,
    this.isbn13,
    this.imageUrl,
    this.sourceUrl,
  });

  @override
  bool operator ==(Object other) =>
      other is BookCandidate &&
      other.title == title &&
      _sameList(other.authors, authors) &&
      other.publisherName == publisherName &&
      other.isbn13 == isbn13 &&
      other.imageUrl == imageUrl &&
      other.sourceUrl == sourceUrl &&
      other.provider == provider;

  @override
  int get hashCode =>
      Object.hash(title, Object.hashAll(authors), publisherName, isbn13,
          imageUrl, sourceUrl, provider);

  @override
  String toString() => 'BookCandidate($title, isbn13: $isbn13, $provider)';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
