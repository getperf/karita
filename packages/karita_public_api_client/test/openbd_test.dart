import 'dart:convert';

import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:test/test.dart';

import 'fake_public_api_server.dart';

/// 実 OpenBD が返す形。**要る項目だけを写す。**
String _record({
  String title = '宇宙エレベーター',
  String? author = '山田太郎／著',
  String? publisher = 'オーム社',
  String? pubdate = '20180301',
  String? cover = 'https://cover.example/9784274067921.jpg',
}) =>
    jsonEncode([
      {
        'summary': {
          'isbn': '9784274067921',
          'title': title,
          if (author != null) 'author': author,
          if (publisher != null) 'publisher': publisher,
          if (pubdate != null) 'pubdate': pubdate,
          if (cover != null) 'cover': cover,
        }
      }
    ]);

void main() {
  late FakePublicApiServer server;
  late OpenBdClient client;

  setUp(() async {
    server = await FakePublicApiServer.start();
    client = OpenBdClient(apiBase: server.openBdBase);
  });

  tearDown(() async {
    client.close();
    await server.close();
  });

  group('書誌の照会', () {
    test('取れたら書誌と書影 URL が返る', () async {
      server.openBdBody = _record();
      final result = await client.fetchBook('9784274067921');

      expect(result.outcome, OpenBdOutcome.found);
      expect(result.record!.title, '宇宙エレベーター');
      expect(result.record!.authorLine, '山田太郎／著');
      expect(result.record!.publisher, 'オーム社');
      expect(result.record!.pubdate, '20180301');
      expect(result.record!.coverUrl.toString(),
          'https://cover.example/9784274067921.jpg');
      expect(server.requests.single.queryParameters['isbn'], '9784274067921');
    });

    test('**未収録は失敗ではない。** 相手は答えている', () async {
      server.openBdBody = '[null]';
      final result = await client.fetchBook('9784274067921');

      expect(result.outcome, OpenBdOutcome.notListed);
      expect(result.failure, isNull);
    });

    test('任意の項目が欠けても、書誌は取れたことにする', () async {
      server.openBdBody = _record(author: null, publisher: null, pubdate: null);
      final result = await client.fetchBook('9784274067921');

      expect(result.outcome, OpenBdOutcome.found);
      expect(result.record!.title, '宇宙エレベーター');
      expect(result.record!.authorLine, isNull);
    });

    test('**書影が無いことは書誌の失敗ではない。** 空文字も「無い」である', () async {
      for (final body in [_record(cover: null), _record(cover: '')]) {
        server.openBdBody = body;
        final result = await client.fetchBook('9784274067921');
        expect(result.outcome, OpenBdOutcome.found);
        expect(result.record!.coverUrl, isNull);
      }
    });

    test('https でない書影 URL は「書影なし」にする。**叩きに行かない**', () async {
      for (final cover in [
        'http://cover.example/x.jpg',
        'https://user:pass@cover.example/x.jpg',
        'ほんとうにURLではない',
      ]) {
        server.openBdBody = _record(cover: cover);
        final result = await client.fetchBook('9784274067921');
        expect(result.outcome, OpenBdOutcome.found, reason: cover);
        expect(result.record!.coverUrl, isNull, reason: cover);
      }
    });

    test('約束した形でなければ invalidData にする', () async {
      for (final body in ['{}', '[]', '[{"x":1}]', 'これはJSONではない']) {
        server.openBdBody = body;
        final result = await client.fetchBook('9784274067921');
        expect(result.outcome, OpenBdOutcome.failed, reason: body);
        expect(result.failure, ApiFailure.invalidData, reason: body);
      }
    });

    test('status ごとに失敗を分ける。**429 を server に畳まない**', () async {
      const expected = {
        500: ApiFailure.server,
        503: ApiFailure.server,
        429: ApiFailure.rateLimited,
        401: ApiFailure.unauthorized,
        403: ApiFailure.unauthorized,
      };
      for (final entry in expected.entries) {
        server.openBdStatus = entry.key;
        final result = await client.fetchBook('9784274067921');
        expect(result.failure, entry.value, reason: 'HTTP ${entry.key}');
      }
    });

    test('正規化していない ISBN は呼び方の間違いとして弾く', () async {
      for (final input in ['427421933X', '978-4-274-06792-1', '', '97842740679211']) {
        await expectLater(client.fetchBook(input), throwsArgumentError,
            reason: input);
      }
    });

    test('**チェック桁はここでは見ない。** 見るのは karita_handoff の1箇所だけである', () async {
      // 桁数と接頭辞は合っていて、チェック桁だけが違う値。ここで検め直すと、正規化の規則の
      // 写しが2つになる — 片方だけが直ると、同じ本が別の entityId になる経路ができる。
      server.openBdBody = '[null]';
      final result = await client.fetchBook('9784274067922');

      expect(result.outcome, OpenBdOutcome.notListed);
    });
  });

  group('書影の取得', () {
    test('バイトが返る。**画像として読めるかは見ない**', () async {
      server.imageBytes = List<int>.filled(64, 7);
      final result = await client.fetchCoverImage(server.imageUri('a.jpg'));

      expect(result.outcome, CoverImageOutcome.fetched);
      expect(result.bytes!.length, 64);
    });

    test('**404 は「URL は在るのに画像が無い」である。** 失敗と分ける', () async {
      server.imageStatus = 404;
      final result = await client.fetchCoverImage(server.imageUri('a.jpg'));

      expect(result.outcome, CoverImageOutcome.notFound);
      expect(result.failure, isNull);
    });

    test('404 以外の status は失敗になる', () async {
      server.imageStatus = 500;
      final result = await client.fetchCoverImage(server.imageUri('a.jpg'));

      expect(result.outcome, CoverImageOutcome.failed);
      expect(result.failure, ApiFailure.server);
    });

    test('**上限を超えたら読むのをやめる。** 数え終わってからでは遅い', () async {
      final small = OpenBdClient(apiBase: server.openBdBase, maxImageBytes: 100);
      server.imageBytes = List<int>.filled(1024, 7);
      final result = await small.fetchCoverImage(server.imageUri('big.jpg'));

      expect(result.outcome, CoverImageOutcome.failed);
      expect(result.failure, ApiFailure.tooLarge);
      small.close();
    });

    test('資格情報つきの URL は叩かない', () {
      expect(
        () => client.fetchCoverImage(Uri.parse('https://u:p@cover.example/a.jpg')),
        throwsArgumentError,
      );
    });
  });
}
