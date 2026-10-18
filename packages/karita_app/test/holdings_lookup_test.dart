/// 蔵書を端末で抱える側。**分割・間欠・中止・上限の扱いを測る。**
///
/// クライアントそのものの試験（継続取得・2秒の下限・部分結果）は
/// `karita_public_api_client` にある。集約規則も同じくあちらである。**ここで見るのは端末の
/// 都合だけ**で、何回に分けて外へ出すか、間に待つか、離れたら止まるか、上限で打ち切るか。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';

/// 978 で始まる正規化済みの ISBN-13 を並べる。**クライアントが形を検査する。**
List<String> isbns(int count) => [
  for (var i = 0; i < count; i++) '97842740679${(10 + i).toString()}',
];

List<String> systems(int count) => [for (var i = 0; i < count; i++) 'Sys$i'];

/// 進められる時計と、待った長さの控え。
class _Clock {
  DateTime at = DateTime.utc(2026, 9, 21, 12);
  final List<Duration> waited = [];

  DateTime now() => at;

  Future<void> delay(Duration duration) async {
    waited.add(duration);
    at = at.add(duration);
    // 中止が伝わる隙を作る。**即座に返すと、止める試験が書けない。**
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late _Clock clock;

  /// 外へ出した「最初の1回」だけを控える。**session の聞き直しは枠を食わないので分ける。**
  late List<Uri> starts;
  late List<Uri> polls;

  /// 相手の答え。`libkey` を持たせると蔵書あり／貸出可になる。
  var statusCode = 200;
  var libkey = <String, String>{};
  var keepRunning = false;


  http.Client makeHttpClient() => MockClient((request) async {
    final isbn = request.url.queryParameters['isbn'];
    if (isbn == null) {
      polls.add(request.url);
      return http.Response(
        jsonEncode({'session': 's', 'continue': 0, 'books': <String, Object?>{}}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    starts.add(request.url);
    if (statusCode != 200) return http.Response('', statusCode);
    final requestedSystems =
        request.url.queryParameters['systemid']!.split(',');
    final books = <String, Object?>{
      for (final one in isbn.split(','))
        one: {
          for (final system in requestedSystems)
            system: {
              'status': keepRunning ? 'Running' : 'OK',
              if (libkey.isNotEmpty && !keepRunning) 'libkey': libkey,
            },
        },
    };
    return http.Response(
      jsonEncode({
        'session': 's',
        'continue': keepRunning ? 1 : 0,
        'books': books,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  HoldingsLookup makeLookup({
    Duration runDeadline = holdingsRunDeadline,
    int chunkBooks = holdingsChunkBooks,
  }) => HoldingsLookup(
    CalilCheckClient(
      appkey: 'test-key',
      httpClient: makeHttpClient(),
      delay: clock.delay,
      now: clock.now,
    ),
    now: clock.now,
    delay: clock.delay,
    chunkBooks: chunkBooks,
    runDeadline: runDeadline,
  );

  setUp(() {
    clock = _Clock();
    starts = [];
    polls = [];
    statusCode = 200;
    libkey = {'豊洲': '貸出可'};
    keepRunning = false;
  });

  group('塊への分け方', () {
    test('**10冊×3館は1塊である。** 刻んでも刻まないのと同じになる', () {
      final lookup = makeLookup();
      final chunks = lookup.planChunks(
        isbn13s: isbns(10),
        systemIds: systems(3),
      );
      expect(chunks, hasLength(1));
      expect(chunks.single.bookRequests, 30);
      lookup.close();
    });

    test('**館数6では10冊にしない。** 60書籍リクエストは向こうが投げる境界である', () {
      final lookup = makeLookup();
      final chunks = lookup.planChunks(
        isbn13s: isbns(10),
        systemIds: systems(6),
      );
      // 50 ÷ 6 = 8冊。10冊固定なら 60 で ArgumentError になっていた。
      expect(chunks.first.isbn13s, hasLength(8));
      for (final chunk in chunks) {
        expect(
          chunk.bookRequests,
          lessThanOrEqualTo(defaultBookRequestBudget),
          reason: 'どの塊も予算を超えないこと',
        );
      }
      lookup.close();
    });

    test('予算に余裕があっても上限の10冊で刻む', () {
      final lookup = makeLookup();
      final chunks = lookup.planChunks(
        isbn13s: isbns(25),
        systemIds: systems(2),
      );
      // 50 ÷ 2 = 25 冊ぶんの余裕が在るが、上限は10冊である。
      expect(chunks.map((c) => c.isbn13s.length), [10, 10, 5]);
      lookup.close();
    });

    test('館が予算を超える端末では館の側も分ける', () {
      final lookup = makeLookup();
      final chunks = lookup.planChunks(
        isbn13s: isbns(2),
        systemIds: systems(60),
      );
      // 1冊ずつ × 館2群。どの塊も予算に収まる。
      expect(chunks, hasLength(4));
      for (final chunk in chunks) {
        expect(chunk.isbn13s, hasLength(1));
        expect(chunk.bookRequests, lessThanOrEqualTo(defaultBookRequestBudget));
      }
      lookup.close();
    });

    test('重複した冊と館は数えない。**同じ館を2回渡しても枠は1つぶんである**', () {
      final lookup = makeLookup();
      final chunks = lookup.planChunks(
        isbn13s: [...isbns(3), ...isbns(3)],
        systemIds: const ['A', 'A', 'B'],
      );
      expect(chunks.single.isbn13s, hasLength(3));
      expect(chunks.single.systemIds, ['A', 'B']);
      lookup.close();
    });

    test('対象が無ければ塊も無い', () {
      final lookup = makeLookup();
      expect(lookup.planChunks(isbn13s: const [], systemIds: ['A']), isEmpty);
      expect(lookup.planChunks(isbn13s: isbns(1), systemIds: const []), isEmpty);
      lookup.close();
    });
  });

  group('間欠処理', () {
    test('塊の間だけ待つ。**最初の塊の前には待たない**', () async {
      final lookup = makeLookup();
      final result = await lookup.check(
        isbn13s: isbns(25),
        systemIds: systems(2),
      );
      expect(result.outcome, HoldingsRunOutcome.completed);
      expect(result.chunks, 3);
      expect(starts, hasLength(3));
      // 3塊なら待つのは2回。値は既定のまま。
      expect(clock.waited, [holdingsChunkPause, holdingsChunkPause]);
      lookup.close();
    });

    test('消費した書籍リクエストを数える。**枠の勘定は冊数×館数である**', () async {
      final lookup = makeLookup();
      final result = await lookup.check(
        isbn13s: isbns(10),
        systemIds: systems(3),
      );
      expect(result.bookRequests, 30);
      expect(result.chunks, 1);
      lookup.close();
    });

    test('**ポーリングは塊に数えない。** 聞き直しは枠を食わない', () async {
      keepRunning = true;
      final lookup = makeLookup();
      await lookup.check(isbn13s: isbns(1), systemIds: systems(1));
      expect(starts, hasLength(1), reason: '外へ出した照会は1回');
      expect(polls, isNotEmpty, reason: 'session で聞き直している');
      lookup.close();
    });
  });

  group('止める', () {
    test('**1塊目の答えが届いた後に離れたら、次の塊を出さない**', () async {
      final lookup = makeLookup();
      // 届いたところで画面を離れる。**利用者が実際に通る順序である。**
      final result = await lookup.check(
        isbn13s: isbns(25),
        systemIds: systems(2),
        onProgress: lookup.cancel,
      );
      expect(result.outcome, HoldingsRunOutcome.cancelled);
      expect(starts, hasLength(1), reason: '2塊目は出ない');
      // **待ちが解けていること。** 購読を切ると onDone が来ないので、ここが返ることが検査に
      // なっている（返らなければ試験は時間切れで落ちる）。
      expect(lookup.running, isFalse);
      lookup.close();
    });

    test('中止しても、取れている観測は捨てない', () async {
      final lookup = makeLookup();
      await lookup.check(
        isbn13s: isbns(25),
        systemIds: systems(2),
        onProgress: lookup.cancel,
      );
      final summary = lookup.summaryFor(
        isbn13: isbns(25).first,
        systemIds: systems(2),
      );
      expect(summary.state, HoldingsState.available);
      expect(summary.observedAt, isNotNull);
      // 2塊目の本は聞いていないので未照会のまま。**確認できませんに塗らない。**
      expect(
        lookup.summaryFor(isbn13: isbns(25)[10], systemIds: systems(2)).state,
        HoldingsState.notRequested,
      );
      lookup.close();
    });

    test('走り全体の期限で打ち切る。**60秒は1セッションぶんである**', () async {
      // 塊の間の待ちで時計が進むので、2塊目の手前で期限に達する。
      final lookup = makeLookup(runDeadline: const Duration(seconds: 1));
      final result = await lookup.check(
        isbn13s: isbns(25),
        systemIds: systems(2),
      );
      expect(result.outcome, HoldingsRunOutcome.deadline);
      expect(starts, hasLength(1));
      lookup.close();
    });

    test('走っている間に押し直しても二重に走らせない', () async {
      final lookup = makeLookup();
      final first = lookup.check(isbn13s: isbns(25), systemIds: systems(2));
      final second = await lookup.check(
        isbn13s: isbns(25),
        systemIds: systems(2),
      );
      expect(second.outcome, HoldingsRunOutcome.cancelled);
      expect(second.chunks, 0);
      await first;
      lookup.close();
    });
  });

  group('上限に達したとき', () {
    test('**残りの塊をやめる。** 続けても全部落ちる', () async {
      statusCode = 429;
      final lookup = makeLookup();
      final result = await lookup.check(
        isbn13s: isbns(25),
        systemIds: systems(2),
      );
      expect(result.outcome, HoldingsRunOutcome.rateLimited);
      expect(starts, hasLength(1), reason: '1塊目で打ち切る');
      expect(lookup.rateLimited, isTrue);
      lookup.close();
    });

    test('**頼まなかった本は未照会のままにする。** 確認できませんに塗らない', () async {
      statusCode = 429;
      final lookup = makeLookup();
      await lookup.check(isbn13s: isbns(25), systemIds: systems(2));
      // 1塊目（先頭10冊）は聞いた。11冊目は聞いていない。
      expect(
        lookup.summaryFor(isbn13: isbns(25)[0], systemIds: systems(2)).state,
        HoldingsState.rateLimited,
      );
      expect(
        lookup.summaryFor(isbn13: isbns(25)[10], systemIds: systems(2)).state,
        HoldingsState.notRequested,
      );
      lookup.close();
    });

    test('**10分は押し直しても外へ出さない。** 尽きた枠をさらに削らない', () async {
      statusCode = 429;
      final lookup = makeLookup();
      await lookup.check(isbn13s: isbns(1), systemIds: systems(1));
      final before = starts.length;

      statusCode = 200;
      final again = await lookup.check(isbn13s: isbns(1), systemIds: systems(1));
      expect(again.outcome, HoldingsRunOutcome.rateLimited);
      expect(starts, hasLength(before), reason: '外へ出ていない');

      // 10分経てば、また押せる。
      clock.at = clock.at.add(holdingsRateLimitedTtl);
      expect(lookup.rateLimited, isFalse);
      final third = await lookup.check(isbn13s: isbns(1), systemIds: systems(1));
      expect(third.outcome, HoldingsRunOutcome.completed);
      expect(starts.length, greaterThan(before));
      lookup.close();
    });
  });

  group('抱え方', () {
    test('**館の集合が変われば別の鍵になる。** 足した館を確認済みに見せない', () async {
      final lookup = makeLookup();
      await lookup.check(isbn13s: isbns(1), systemIds: ['A']);
      expect(
        lookup.summaryFor(isbn13: isbns(1).first, systemIds: ['A']).state,
        HoldingsState.available,
      );
      expect(
        lookup.summaryFor(isbn13: isbns(1).first, systemIds: ['A', 'B']).state,
        HoldingsState.notRequested,
        reason: '館を足したら未照会へ戻る',
      );
      lookup.close();
    });

    test('館を分けた塊の答えが1冊ぶんに揃う', () async {
      final lookup = makeLookup();
      await lookup.check(isbn13s: isbns(1), systemIds: systems(60));
      final summary = lookup.summaryFor(
        isbn13: isbns(1).first,
        systemIds: systems(60),
      );
      expect(summary.settled, 60, reason: '2塊ぶんの館が溜まっている');
      expect(summary.pending, 0);
      lookup.close();
    });

    test('観測は期限で消える。**古い観測を今の確定結果に見せない**', () async {
      final lookup = makeLookup();
      await lookup.check(isbn13s: isbns(1), systemIds: systems(1));
      expect(lookup.entryCount, 1);
      clock.at = clock.at.add(holdingsTtl + const Duration(seconds: 1));
      expect(
        lookup.summaryFor(isbn13: isbns(1).first, systemIds: systems(1)).state,
        HoldingsState.notRequested,
      );
      lookup.close();
    });

    test('ISBNなし・登録館なしでは外へ出ない', () async {
      final lookup = makeLookup();
      expect(
        lookup.summaryFor(isbn13: null, systemIds: systems(1)).state,
        HoldingsState.noIsbn,
      );
      expect(
        lookup.summaryFor(isbn13: isbns(1).first, systemIds: const []).state,
        HoldingsState.noLibrary,
      );
      final result = await lookup.check(
        isbn13s: isbns(1),
        systemIds: const [],
      );
      expect(result.outcome, HoldingsRunOutcome.nothingToDo);
      expect(starts, isEmpty);
      lookup.close();
    });

    test('閉じたら走らせない', () async {
      final lookup = makeLookup();
      lookup.close();
      expect(
        () => lookup.check(isbn13s: isbns(1), systemIds: systems(1)),
        throwsStateError,
      );
    });
  });
}
