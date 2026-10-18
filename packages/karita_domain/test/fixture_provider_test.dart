/// 検証用 provider。**fixture の形を読めることだけを測る。**
///
/// 実 API は叩かない。叩く実装は karita-core の外にあり、実 API の可用性を CI の条件に
/// しないためである。
library;

import 'package:karita_domain/karita_domain.dart';
import 'package:test/test.dart';

/// 正本の `contracts/fixtures/operations/rakuten-total-keyword-*.json` と同じ形。
const String twoHits = '''
{
  "http": {"status": 200, "headers": {"content-type": "application/json"}},
  "body": {
    "count": 2, "page": 1, "pageCount": 1,
    "items": [
      {"title": "達人プログラマー", "author": "Andrew Hunt/David Thomas",
       "publisherName": "オーム社", "isbn": "9784274226298",
       "largeImageUrl": "https://example.invalid/images/pragmatic.jpg",
       "itemUrl": "https://books.example.invalid/item/9784274226298"},
      {"title": "達人プログラマー 第2版", "author": "David Thomas/Andrew Hunt",
       "publisherName": "オーム社", "isbn": "9784295009709",
       "mediumImageUrl": "https://example.invalid/images/pragmatic-2.jpg",
       "itemUrl": "https://books.example.invalid/item/9784295009709"}
    ]
  }
}
''';

void main() {
  group('parseCandidates', () {
    test('項目を候補へ写す', () {
      final candidates = parseCandidates(twoHits);
      expect(candidates, hasLength(2));
      final first = candidates.first;
      expect(first.title, equals('達人プログラマー'));
      expect(first.isbn13, equals('9784274226298'));
      expect(first.publisherName, equals('オーム社'));
      expect(first.provider, equals(fixtureProviderName));
      expect(first.sourceUrl,
          equals('https://books.example.invalid/item/9784274226298'));
    });

    test('large が無ければ medium を採る', () {
      expect(parseCandidates(twoHits)[1].imageUrl,
          equals('https://example.invalid/images/pragmatic-2.jpg'));
    });

    test('limit で切る', () {
      expect(parseCandidates(twoHits, limit: 1), hasLength(1));
    });

    test('タイトルの無い項目は候補ごと落とす', () {
      // 空文字で通すと、空の本が台帳に入る手前まで進む。
      const noTitle = '{"body": {"items": [{"isbn": "9784274226298"}, '
          '{"title": "   ", "isbn": "9784274226298"}]}}';
      expect(parseCandidates(noTitle), isEmpty);
    });

    test('13桁でない ISBN は持たない候補として扱う', () {
      // ISBN は採用の id の種になる。形が崩れたものを通すと表記ゆれの数だけ別の実体になる。
      const bad = '{"body": {"items": ['
          '{"title": "a", "isbn": "123"},'
          '{"title": "b", "isbn": "97842742262X8"},'
          '{"title": "c", "isbn": "978-4-274-22629-8"}]}}';
      final candidates = parseCandidates(bad);
      expect(candidates.map((c) => c.isbn13),
          equals([null, null, '9784274226298']),
          reason: 'ハイフンだけは落として読む');
    });

    test('形の崩れた本文は空を返す。落とさない', () {
      expect(parseCandidates('{'), isEmpty);
      expect(parseCandidates('[]'), isEmpty);
      expect(parseCandidates('{"body": {}}'), isEmpty);
      expect(parseCandidates('{"body": {"items": {}}}'), isEmpty);
    });
  });

  group('FixtureBooksProvider', () {
    test('keyword で引く', () async {
      const provider = FixtureBooksProvider({'達人': twoHits});
      expect(await provider.searchKeyword('達人'), hasLength(2));
      expect(await provider.searchKeyword('無い語'), isEmpty);
    });

    test('当たらないときは fallback を返す', () async {
      const provider = FixtureBooksProvider({}, fallback: twoHits);
      expect(await provider.searchKeyword('何でも'), hasLength(2));
    });

    test('searchBooks は ISBN を先に見る', () async {
      // 一意に決まる問い合わせを、語の一致より先に見る。
      const provider = FixtureBooksProvider({
        '9784274226298': twoHits,
        '達人': '{"body": {"items": []}}',
      });
      final found =
          await provider.searchBooks(title: '達人', isbn: '9784274226298');
      expect(found, hasLength(2));
    });
  });
}
