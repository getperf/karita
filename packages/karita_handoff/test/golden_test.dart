/// 受理規則の golden。**仕様の行から書いてある。**
///
/// 素材は凍結 spike の3写し（`karita-ui-calil-probe/lib/isbn.dart`、
/// `karita-ui-calil-android-probe` の `BookInput.kt`、拡張の `popup.js`）とその試験だが、
/// **3写しは既にずれている** — ホストの見方、URL の数え方、生の ISBN 文字列を受けるかが違う。
/// 和を取ると誰も決めていない規則になるので、期待値は仕様
/// （`../karita-ui-probe/docs/calil-book-discovery.md` §2、`browser-handoff.md` §4）から書く。
library;

import 'package:karita_handoff/karita_handoff.dart';
import 'package:test/test.dart';

const String _isbn10 = '427421933X';
const String _isbn13 = '9784274219337';
final Uri _bookUrl = Uri.parse('https://calil.jp/book/$_isbn10');

void main() {
  group('書籍として受理する', () {
    final accepted = <String, String>{
      'ISBN-10': 'https://calil.jp/book/$_isbn10',
      'ISBN-10 の小文字 x': 'https://calil.jp/book/427421933x',
      'ISBN-13': 'https://calil.jp/book/$_isbn13',
      '末尾のスラッシュ': 'https://calil.jp/book/$_isbn10/',
      'クエリ付き': 'https://calil.jp/book/$_isbn10?x=1',
      'フラグメント付き': 'https://calil.jp/book/$_isbn10#top',
      'ホストの大文字': 'https://CALIL.JP/book/$_isbn10',
      '別行のタイトル付き': '達人プログラマー\nhttps://calil.jp/book/$_isbn10',
      '前後の空行': '\n\n  https://calil.jp/book/$_isbn10  \n\n',
    };
    accepted.forEach((name, input) {
      test(name, () {
        final result = parseHandoff(input);
        expect(result, isA<HandoffBook>(), reason: input);
        expect((result as HandoffBook).isbn13, _isbn13);
      });
    });
  });

  group('断る', () {
    final rejected = <String, (String, HandoffReason)>{
      '空': ('', HandoffReason.noUrl),
      'URL が無い': ('カーリルで見つけた本', HandoffReason.noUrl),
      '同じ行に説明文': (
        '読みたい https://calil.jp/book/$_isbn10',
        HandoffReason.inlineText
      ),
      '1行に2つ': (
        'https://calil.jp/book/$_isbn10 https://example.jp',
        HandoffReason.inlineText
      ),
      '別行に2つ': (
        'https://calil.jp/book/$_isbn10\nhttps://example.jp',
        HandoffReason.multipleUrl
      ),
      'http(s) ではない': ('ftp://calil.jp/book/$_isbn10', HandoffReason.badScheme),
      'userinfo 付き': (
        'https://user:pw@calil.jp/book/$_isbn10',
        HandoffReason.hasUserInfo
      ),
      'ホストが無い': ('https://', HandoffReason.brokenUrl),
      '制御文字': (
        'https://calil.jp/book/$_isbn10${''}',
        HandoffReason.brokenUrl
      ),
      'カーリルの検索結果': (
        'https://calil.jp/search?q=%E6%BC%B1%E7%9F%B3',
        HandoffReason.calilNonBook
      ),
      'カーリルのトップ': ('https://calil.jp/', HandoffReason.calilNonBook),
      'カーリルだが http': (
        'http://calil.jp/book/$_isbn10',
        HandoffReason.calilNonBook
      ),
      'カーリルだがポート付き': (
        'https://calil.jp:8443/book/$_isbn10',
        HandoffReason.calilNonBook
      ),
      'ISBN-10 のチェック桁が不正': (
        'https://calil.jp/book/4274219330',
        HandoffReason.invalidIsbn
      ),
      'ISBN-13 のチェック桁が不正': (
        'https://calil.jp/book/9784274219330',
        HandoffReason.invalidIsbn
      ),
      'ISBN ではない EAN': (
        'https://calil.jp/book/1234567890128',
        HandoffReason.invalidIsbn
      ),
    };
    rejected.forEach((name, row) {
      test(name, () {
        expect(parseHandoff(row.$1), HandoffNotice(row.$2), reason: row.$1);
      });
    });

    test('入力が長すぎる', () {
      final long = 'a' * (maxInputLength + 1);
      expect(parseHandoff(long), const HandoffNotice(HandoffReason.tooLong));
    });

    test('URL が長すぎる', () {
      final long = 'https://example.jp/${'a' * maxUrlLength}';
      expect(parseHandoff(long), const HandoffNotice(HandoffReason.tooLong));
    });
  });

  group('一般の Web URL として渡す', () {
    // **図書館サイトと認定したわけではない。** 目的・地区の候補表示へ進むだけである。
    final passed = <String, String>{
      '館のログイン入口':
          'https://www.lib.city.minato.tokyo.jp/licsxp-opac/WOpacInitLoginActiontemp.do?smtFlg=0',
      '館のトップ': 'https://www.koto-lib.tokyo.jp/',
      // 仕様は「calil.jp の完全一致」なので、偽ホストは書籍に分類されない。一般 URL の候補には
      // なるが、候補は保存も遷移も伴わない（正規館と認定したことにはならない）。
      '偽ホスト': 'https://calil.jp.evil/book/$_isbn10',
      // **www 付きも完全一致から外れる。** 実サイトが www へ飛ばすかは実測が要る
      // （browser-handoff-implementation.md の決定 I の節）。
      'www 付きのカーリル': 'https://www.calil.jp/book/$_isbn10',
    };
    passed.forEach((name, input) {
      test(name, () {
        final result = parseHandoff(input);
        expect(result, isA<HandoffWebUrl>(), reason: input);
        expect((result as HandoffWebUrl).url, Uri.parse(input));
      });
    });
  });

  group('連携の確認（2026-10-15）', () {
    final accepted = <String, String>{
      '確認ページ': 'https://karita.getperf.net/extensions/check/',
      '末尾の / が無い': 'https://karita.getperf.net/extensions/check',
      'index.html 付き': 'https://karita.getperf.net/extensions/check/index.html',
      // 照合用の値は付けない。付いていても見ない。
      'クエリ・フラグメント付き':
          'https://karita.getperf.net/extensions/check/?from=app#top',
    };
    accepted.forEach((name, input) {
      test(name, () {
        expect(parseHandoff(input), const HandoffLinkCheck(), reason: input);
      });
    });
    test('配送 URI から届いても同じ', () {
      final url = Uri.encodeComponent(linkCheckUrl.toString());
      expect(
        parseDelivery('karita://share?url=$url'),
        const HandoffLinkCheck(),
      );
    });

    final others = <String, String>{
      'ガイドの別ページ': 'https://karita.getperf.net/extensions/',
      'http': 'http://karita.getperf.net/extensions/check/',
      'ポート付き': 'https://karita.getperf.net:8443/extensions/check/',
      '偽ホスト': 'https://karita.getperf.net.evil/extensions/check/',
    };
    others.forEach((name, input) {
      test('$name は一般の Web URL', () {
        expect(parseHandoff(input), isA<HandoffWebUrl>(), reason: input);
      });
    });
  });

  // `非公開資料:amazon-share-handoff.md` §1 の表から書く。
  group('Amazon', () {
    const www = 'www.amazon.co.jp';
    final rows = <String, (String, String?, AmazonShape, String)>{
      '/dp/<ISBN10>': (
        'https://www.amazon.co.jp/dp/$_isbn10',
        _isbn13,
        AmazonShape.isbn10,
        www
      ),
      // 2026-10-06 Windows で実測した形。クエリは見ない。
      'Windows 実測（クエリ付き）': (
        'https://www.amazon.co.jp/dp/4540251430?tag=calil-22&linkCode=ogi&th=1&psc=1',
        '9784540251436',
        AmazonShape.isbn10,
        www
      ),
      '末尾 x の小文字': (
        'https://www.amazon.co.jp/dp/427421933x',
        _isbn13,
        AmazonShape.isbn10,
        www
      ),
      'スラッグ付き': (
        'https://www.amazon.co.jp/%E9%81%94%E4%BA%BA/dp/$_isbn10',
        _isbn13,
        AmazonShape.isbn10,
        www
      ),
      '後ろに ref': (
        'https://www.amazon.co.jp/dp/$_isbn10/ref=sr_1_1',
        _isbn13,
        AmazonShape.isbn10,
        www
      ),
      '/gp/product/': (
        'https://amazon.co.jp/gp/product/$_isbn10',
        _isbn13,
        AmazonShape.isbn10,
        'amazon.co.jp'
      ),
      'ホストの大文字': (
        'https://WWW.AMAZON.CO.JP/dp/$_isbn10',
        _isbn13,
        AmazonShape.isbn10,
        www
      ),
      'フラグメント付き': (
        'https://www.amazon.co.jp/dp/$_isbn10#top',
        _isbn13,
        AmazonShape.isbn10,
        www
      ),
      '検索 978': (
        'https://www.amazon.co.jp/s?k=$_isbn13',
        _isbn13,
        AmazonShape.searchIsbn,
        www
      ),
      '検索 979': (
        'https://www.amazon.co.jp/s?k=9791234567896',
        '9791234567896',
        AmazonShape.searchIsbn,
        www
      ),
      '検索 ISBN13 のチェック桁が不正': (
        'https://www.amazon.co.jp/s?k=9784274219330',
        null,
        AmazonShape.search,
        www
      ),
      '検索 ISBN10 は受けない': (
        'https://www.amazon.co.jp/s?k=$_isbn10',
        null,
        AmazonShape.search,
        www
      ),
      '検索語': (
        'https://www.amazon.co.jp/s?k=%E6%BC%B1%E7%9F%B3',
        null,
        AmazonShape.search,
        www
      ),
      'Kindle（ASIN）': (
        'https://www.amazon.co.jp/%E6%9B%B8%E5%90%8D-ebook/dp/B0HGXY43PQ?s=digital-text',
        null,
        AmazonShape.asin,
        www
      ),
      'ISBN10 のチェック桁が不正': (
        'https://www.amazon.co.jp/dp/4274219330',
        null,
        AmazonShape.other,
        www
      ),
      'トップ': ('https://www.amazon.co.jp/', null, AmazonShape.other, www),
      'http': (
        'http://www.amazon.co.jp/dp/$_isbn10',
        null,
        AmazonShape.other,
        www
      ),
      'ポート付き': (
        'https://www.amazon.co.jp:8443/dp/$_isbn10',
        null,
        AmazonShape.other,
        www
      ),
    };
    rows.forEach((name, row) {
      test(name, () {
        expect(parseHandoff(row.$1), HandoffAmazon(row.$2, row.$3, row.$4),
            reason: row.$1);
      });
    });

    test('ISBN13 が採番と同じ正規化を通る', () {
      final result = parseHandoff('https://www.amazon.co.jp/dp/$_isbn10');
      expect((result as HandoffAmazon).isbn13, normalizeIsbn13(_isbn10));
    });

    // **完全一致から外れるものは Amazon にしない。** 短縮 URL も展開しない。
    final others = <String, String>{
      'amazon.com': 'https://www.amazon.com/dp/$_isbn10',
      '偽ホスト': 'https://www.amazon.co.jp.evil/dp/$_isbn10',
      '短縮 URL': 'https://amzn.asia/d/abcdefg',
      '別のサブドメイン': 'https://smile.amazon.co.jp/dp/$_isbn10',
    };
    others.forEach((name, input) {
      test('一般の Web URL: $name', () {
        expect(parseHandoff(input), isA<HandoffWebUrl>(), reason: input);
      });
    });

    test('説明文と短縮 URL の同じ行は断る（Amazon アプリの共有）', () {
      expect(parseHandoff('達人プログラマー https://amzn.asia/d/abcdefg'),
          const HandoffNotice(HandoffReason.inlineText));
    });

    test('Windows の配送でも同じ', () {
      final inner = Uri.encodeComponent('https://www.amazon.co.jp/dp/$_isbn10');
      expect(parseDelivery('karita://share?url=$inner'),
          const HandoffAmazon(_isbn13, AmazonShape.isbn10, www));
    });
  });

  group('Windows の配送', () {
    final encoded = Uri.encodeComponent(_bookUrl.toString());

    test('空パスと / の両方を受理する', () {
      for (final path in ['', '/']) {
        expect(parseDelivery('karita://share$path?url=$encoded'),
            HandoffBook(_isbn13, _bookUrl));
      }
    });

    final rejected = <String, String>{
      '別のパス': 'karita://share/other?url=$encoded',
      '別の操作名': 'karita://import?url=$encoded',
      '別の scheme': 'karita-calil-probe://share?url=$encoded',
      'url が無い': 'karita://share',
      'url が2つ': 'karita://share?url=$encoded&url=$encoded',
      '未知の第3キー(url+foo)': 'karita://share?url=$encoded&foo=bar',
      '未知の第3キー(url+purpose+foo)':
          'karita://share?url=$encoded&purpose=lending&foo=bar',
      'ポート付き': 'karita://share:8080?url=$encoded',
      'フラグメント付き': 'karita://share?url=$encoded#x',
    };
    rejected.forEach((name, input) {
      test(name, () {
        expect(
            parseDelivery(input), const HandoffNotice(HandoffReason.badDelivery));
      });
    });

    test('復号は1回だけである', () {
      // 二重に符号化された値を二度復号すると、ここが書籍として通ってしまう。
      final twice = Uri.encodeComponent(encoded);
      expect(decodeDelivery('karita://share?url=$twice'), encoded);
      expect(parseDelivery('karita://share?url=$twice'),
          const HandoffNotice(HandoffReason.noUrl));
    });

    test('内側の URL も共通解析を通る', () {
      final search = Uri.encodeComponent('https://calil.jp/search?q=x');
      expect(parseDelivery('karita://share?url=$search'),
          const HandoffNotice(HandoffReason.calilNonBook));
    });

    group('用途ヒント（purpose）', () {
      test('省略時は null（後方互換）', () {
        expect(decodePurposeHint('karita://share?url=$encoded'), isNull);
        expect(decodeDelivery('karita://share?url=$encoded'),
            _bookUrl.toString());
      });

      test('lending を読み取る', () {
        final input = 'karita://share?url=$encoded&purpose=lending';
        expect(decodePurposeHint(input), DeliveryPurposeHint.lending);
        expect(decodeDelivery(input), _bookUrl.toString());
        expect(parseDelivery(input), HandoffBook(_isbn13, _bookUrl));
      });

      test('mypage_url を読み取る', () {
        final input = 'karita://share?url=$encoded&purpose=mypage_url';
        expect(decodePurposeHint(input), DeliveryPurposeHint.mypageUrl);
      });

      test('不正な値は封筒ごと拒否する', () {
        final input = 'karita://share?url=$encoded&purpose=unknown';
        expect(decodePurposeHint(input), isNull);
        expect(decodeDelivery(input), isNull);
        expect(parseDelivery(input),
            const HandoffNotice(HandoffReason.badDelivery));
      });

      test('大文字小文字は区別する', () {
        final input = 'karita://share?url=$encoded&purpose=Lending';
        expect(decodeDelivery(input), isNull);
        expect(decodePurposeHint(input), isNull);
      });

      test('purpose の重複は封筒ごと拒否する', () {
        final input =
            'karita://share?url=$encoded&purpose=lending&purpose=mypage_url';
        expect(decodeDelivery(input), isNull);
        expect(decodePurposeHint(input), isNull);
      });

      test('url の重複は purpose があっても拒否する', () {
        final input =
            'karita://share?url=$encoded&url=$encoded&purpose=lending';
        expect(parseDelivery(input),
            const HandoffNotice(HandoffReason.badDelivery));
      });
    });

    group('起動の経路（via）', () {
      test('省略時は null（後方互換）', () {
        expect(decodeVia('karita://share?url=$encoded'), isNull);
        expect(decodeVia('karita://share?url=$encoded&purpose=lending'),
            isNull);
      });

      test('retry を読み取り、解析結果は変えない', () {
        final input = 'karita://share?url=$encoded&via=retry';
        expect(decodeVia(input), DeliveryVia.retry);
        expect(decodePurposeHint(input), isNull);
        expect(parseDelivery(input), HandoffBook(_isbn13, _bookUrl));
      });

      test('purpose と併用できる', () {
        final input = 'karita://share?url=$encoded&purpose=lending&via=retry';
        expect(decodeVia(input), DeliveryVia.retry);
        expect(decodePurposeHint(input), DeliveryPurposeHint.lending);
        expect(decodeDelivery(input), _bookUrl.toString());
      });

      test('不正な値は封筒ごと拒否する', () {
        final input = 'karita://share?url=$encoded&via=auto';
        expect(decodeVia(input), isNull);
        expect(decodeDelivery(input), isNull);
        expect(parseDelivery(input),
            const HandoffNotice(HandoffReason.badDelivery));
      });

      test('via の重複は封筒ごと拒否する', () {
        final input = 'karita://share?url=$encoded&via=retry&via=retry';
        expect(decodeVia(input), isNull);
        expect(decodeDelivery(input), isNull);
      });

      test('その他の鍵は via があっても拒否する', () {
        final input = 'karita://share?url=$encoded&via=retry&x=1';
        expect(parseDelivery(input),
            const HandoffNotice(HandoffReason.badDelivery));
      });
    });
  });
}
