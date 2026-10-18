/// 検証用の [BooksProvider]。**fixture を読むだけである。**
///
/// **adapter はここに入れない。** 実 API を叩く実装は `karita-provider-gateway` のクライアント
/// として karita-core の外に置く。実 API の可用性を CI の条件にしないためである。
///
/// **正本の fixture をそのまま読む。** `contracts/fixtures/operations/*.json` は外部 API の
/// 応答をそのまま写したもので、Python の provider が同じものを読んでいる。写しを作ると、
/// 応答の形が変わったときに片方だけが直る。
///
/// `dart:io` を持たない — 読み込みは呼び出し側が済ませ、ここへは JSON の文字列を渡す。
/// `karita_domain` がファイルシステムに触ると、Flutter 側で同じコードが動かなくなる。
library;

import 'dart:convert';

import 'candidates.dart';
import 'provider_ports.dart';

/// fixture が写している外部 API の名前。**候補の出所として payload に残る。**
const String fixtureProviderName = 'rakuten';

class FixtureBooksProvider implements BooksProvider {
  /// keyword → その応答の JSON 文字列。
  final Map<String, String> responses;

  /// どの keyword にも当たらなかったときに返すもの。**空を返すのが既定である** — 落とすと、
  /// 「その語では見つからない」という正常な結果を試験が書けない。
  final String? fallback;

  const FixtureBooksProvider(this.responses, {this.fallback});

  @override
  Future<List<BookCandidate>> searchKeyword(String keyword,
      {int limit = 10}) async {
    final text = responses[keyword] ?? fallback;
    if (text == null) return const [];
    return parseCandidates(text, limit: limit);
  }

  @override
  Future<List<BookCandidate>> searchBooks({
    String? title,
    String? author,
    String? isbn,
    int limit = 10,
  }) async {
    // **ISBN が最も強い。** 一意に決まる問い合わせを、語の一致より先に見る。
    for (final key in [isbn, title, author]) {
      if (key == null || key.isEmpty) continue;
      final text = responses[key];
      if (text != null) return parseCandidates(text, limit: limit);
    }
    return fallback == null
        ? const []
        : parseCandidates(fallback!, limit: limit);
  }
}

/// fixture の本文を候補へ写す。
///
/// **形の崩れた項目は候補ごと落とす。** タイトルの無い項目を空文字で通すと、採用の入口が
/// 「タイトルと13桁ISBNが要る」で落ちるのではなく、空の本が台帳に入る手前まで進む。
///
/// 移送元: book-sync-model の `src/bops_providers/rakuten.py`（`_to_candidate`）。
List<BookCandidate> parseCandidates(String text, {int limit = 10}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map<String, Object?>) return const [];
  final body = decoded['body'];
  if (body is! Map<String, Object?>) return const [];
  final items = body['items'];
  if (items is! List) return const [];

  final candidates = <BookCandidate>[];
  for (final item in items) {
    if (candidates.length >= limit) break;
    if (item is! Map) continue;
    final title = item['title'];
    if (title is! String || title.trim().isEmpty) continue;
    final author = item['author'];
    final publisher = item['publisherName'];
    candidates.add(BookCandidate(
      title: title.trim(),
      authors: author is String && author.trim().isNotEmpty
          ? [author.trim()]
          : const [],
      publisherName: publisher is String && publisher.trim().isNotEmpty
          ? publisher.trim()
          : null,
      isbn13: _isbn13(item['isbn']),
      imageUrl: _url(item['largeImageUrl']) ?? _url(item['mediumImageUrl']),
      sourceUrl: _url(item['itemUrl']),
      provider: fixtureProviderName,
    ));
  }
  return candidates;
}

/// 13桁の数字だけを ISBN として認める。ハイフンは落とす。
String? _isbn13(Object? value) {
  if (value is! String) return null;
  final normalized = value.replaceAll('-', '').trim();
  return normalized.length == 13 && RegExp(r'^\d+$').hasMatch(normalized)
      ? normalized
      : null;
}

String? _url(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
