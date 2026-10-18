/// 書誌と書影を端末で抱える側。**外へ出す要求の数を測る。**
///
/// クライアントそのものの試験（未収録・壊れた JSON・404・上限超過）は
/// `karita_public_api_client` にある。**ここで見るのは端末の都合だけ**である — 同じものを
/// 何度も取りに行かないこと、走っている要求に相乗りすること、結末ごとに持つ長さが違うこと。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';

const String _isbn = '9784274067921';
final Uri _coverUrl = Uri.parse('https://cover.example/a.jpg');

String _record({String? cover}) => jsonEncode([
  {
    'summary': {
      'isbn': _isbn,
      'title': '宇宙エレベーター',
      if (cover != null) 'cover': cover,
    },
  },
]);

void main() {
  late DateTime now;
  late List<Uri> requests;

  /// 相手の応答を差し替える。**実物を CI の条件にしない。**
  String recordBody = _record();
  int recordStatus = 200;
  List<int> imageBytes = const [1, 2, 3, 4];
  Completer<void>? hold;

  BookLookup makeLookup({int maxImageBytes = maxCoverBytes}) => BookLookup(
    OpenBdClient(
      httpClient: MockClient((request) async {
        requests.add(request.url);
        if (hold != null) await hold!.future;
        if (request.url.path.endsWith('/get')) {
          return http.Response(
            recordBody,
            recordStatus,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response.bytes(imageBytes, 200);
      }),
    ),
    now: () => now,
    maxImageBytes: maxImageBytes,
  );

  setUp(() {
    now = DateTime.utc(2026, 9, 16, 12);
    requests = [];
    recordBody = _record();
    recordStatus = 200;
    imageBytes = const [1, 2, 3, 4];
    hold = null;
  });

  group('書誌', () {
    test('消去中の応答はキャッシュを復活させない', () async {
      hold = Completer<void>();
      final lookup = makeLookup();
      final pending = lookup.book(_isbn);
      lookup.clearCache();
      hold!.complete();
      await pending;
      expect(lookup.recordCount, 0);
      lookup.close();
    });

    test('同時HTTPは4本まで、待機分も完了する', () async {
      hold = Completer<void>();
      final lookup = makeLookup();
      final pending = List.generate(10, (_) => lookup.book(_isbn));
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(4));
      expect(lookup.inFlight, 4);
      hold!.complete();
      await Future.wait(pending);
      expect(requests, hasLength(10));
      expect(lookup.inFlight, 0);
      lookup.close();
    });
    test('消去中の応答はキャッシュを復活させない', () async {
      hold = Completer<void>();
      final lookup = makeLookup();
      final pending = lookup.book(_isbn);
      lookup.clearCache();
      hold!.complete();
      await pending;
      expect(lookup.recordCount, 0);
      lookup.close();
    });

    test('同時HTTPは4本まで、待機分も完了する', () async {
      hold = Completer<void>();
      final lookup = makeLookup();
      final pending = List.generate(10, (_) => lookup.book(_isbn));
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(4));
      expect(lookup.inFlight, 4);
      hold!.complete();
      await Future.wait(pending);
      expect(requests, hasLength(10));
      expect(lookup.inFlight, 0);
      lookup.close();
    });
    test('**2回目は外へ出さない**', () async {
      final lookup = makeLookup();

      expect((await lookup.book(_isbn)).outcome, OpenBdOutcome.found);
      expect((await lookup.book(_isbn)).outcome, OpenBdOutcome.found);
      expect(requests.length, 1);
      expect(lookup.recordCount, 1);
    });

    test('期限が切れたら取り直す', () async {
      final lookup = makeLookup();
      await lookup.book(_isbn);

      now = now.add(bookRecordTtl);
      await lookup.book(_isbn);

      expect(requests.length, 2);
    });

    test('**未収録は取れた書誌より短く持つ**', () async {
      recordBody = '[null]';
      final lookup = makeLookup();
      expect((await lookup.book(_isbn)).outcome, OpenBdOutcome.notListed);

      now = now.add(bookNotListedTtl);
      await lookup.book(_isbn);

      expect(requests.length, 2);
      expect(bookNotListedTtl, lessThan(bookRecordTtl));
    });

    test('**失敗も持つ。** 再描画のたびに外へ出さない', () async {
      recordStatus = 500;
      final lookup = makeLookup();

      expect((await lookup.book(_isbn)).failure, ApiFailure.server);
      await lookup.book(_isbn);
      await lookup.book(_isbn);
      expect(requests.length, 1);

      // ただし、圏外から戻った利用者がすぐ試し直せる長さである。
      now = now.add(apiFailureTtl);
      await lookup.book(_isbn);
      expect(requests.length, 2);
      expect(apiFailureTtl, lessThan(bookNotListedTtl));
    });

    test('要求共有はRiverpod側。取得口は独立した要求を実行する', () async {
      hold = Completer<void>();
      final lookup = makeLookup();

      final first = lookup.book(_isbn);
      final second = lookup.book(_isbn);
      expect(lookup.inFlight, 2);

      hold!.complete();
      await Future.wait([first, second]);
      expect(requests.length, 2);
    });

    test('明示の取り直しは削除の反映でもある', () async {
      final lookup = makeLookup();
      expect((await lookup.book(_isbn)).outcome, OpenBdOutcome.found);

      recordBody = '[null]';
      final again = await lookup.book(_isbn, refresh: true);

      expect(again.outcome, OpenBdOutcome.notListed);
      expect(requests.length, 2);
    });
  });

  group('書影', () {
    test('2回目は外へ出さない', () async {
      final lookup = makeLookup();
      await lookup.cover(_coverUrl);
      await lookup.cover(_coverUrl);

      expect(requests.length, 1);
      expect(lookup.coverBytes, 4);
    });

    test('**合計のバイトで縛る。** 溢れたら古いほうから落ちる', () async {
      imageBytes = List.filled(6, 0);
      final lookup = makeLookup(maxImageBytes: 10);

      await lookup.cover(Uri.parse('https://cover.example/1.jpg'));
      await lookup.cover(Uri.parse('https://cover.example/2.jpg'));
      expect(lookup.coverBytes, 6);

      await lookup.cover(Uri.parse('https://cover.example/1.jpg'));
      expect(requests.length, 3);
    });

    test('**404 は一時的な失敗より長く持つ。** 欠損であって不調ではない', () {
      expect(coverMissingTtl, greaterThan(apiFailureTtl));
      expect(coverMissingTtl, coverImageTtl);
    });
  });

  test('抱えているものを捨てられる', () async {
    final lookup = makeLookup();
    await lookup.book(_isbn);
    await lookup.cover(_coverUrl);

    lookup.clearCache();

    expect(lookup.recordCount, 0);
    expect(lookup.coverBytes, 0);
    await lookup.book(_isbn);
    expect(requests.length, 3);
  });
}
