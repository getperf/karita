import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:test/test.dart';

import 'fake_public_api_server.dart';

const String _isbn = '9784274067921';
const String _other = '9784873119038';

const String _running = '{"session":"abc","continue":1,'
    '"books":{"$_isbn":{"Tokyo_Koto":{"status":"Running"}}}}';

const String _settled = '{"session":"abc","continue":0,'
    '"books":{"$_isbn":{"Tokyo_Koto":{"status":"OK",'
    '"libkey":{"豊洲":"貸出可","東雲":"貸出中"},'
    '"reserveurl":"https://calil.jp/book/4274067920"}}}}';

/// 進めることのできる時計と、待った長さの控え。
///
/// **待たずに回すためだけのものではない。** 本物と同じ [Duration] が渡るので、試験はその値を
/// 見て「2秒を下回っていないこと」を測れる。
class _Clock {
  DateTime at = DateTime.utc(2026, 9, 15, 12);
  final List<Duration> waited = [];

  DateTime now() => at;

  Future<void> delay(Duration duration) async {
    waited.add(duration);
    at = at.add(duration);
    // 購読をやめたことが伝わる隙を作る。**即座に返すと、止める試験が書けない。**
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late FakePublicApiServer server;
  late _Clock clock;

  CalilCheckClient makeClient({
    Duration overallTimeout = const Duration(seconds: 60),
    int budget = defaultBookRequestBudget,
  }) =>
      CalilCheckClient(
        appkey: 'test-key',
        apiBase: server.calilBase,
        overallTimeout: overallTimeout,
        bookRequestBudget: budget,
        delay: clock.delay,
        now: clock.now,
      );

  setUp(() async {
    server = await FakePublicApiServer.start();
    clock = _Clock();
  });

  tearDown(() async => server.close());

  group('蔵書の照会', () {
    test('1回で答えが揃うなら、それで終わる', () async {
      server.checkBodies = [_settled];
      final snapshots = await makeClient()
          .check(isbn13s: [_isbn], systemIds: ['Tokyo_Koto']).toList();

      expect(snapshots.length, 1);
      expect(snapshots.single.complete, isTrue);
      final holding = snapshots.single.byIsbn[_isbn]!.single;
      expect(holding.systemId, 'Tokyo_Koto');
      expect(holding.isSettled, isTrue);
      expect(holding.libkeyStatuses, {'豊洲': '貸出可', '東雲': '貸出中'});
      expect(holding.reserveUrl.toString(), 'https://calil.jp/book/4274067920');
      expect(server.requests.length, 1);
    });

    test('**走っている間は聞き直す。** 届いたところまでを順に出す', () async {
      server.checkBodies = [_running, _running, _settled];
      final snapshots = await makeClient()
          .check(isbn13s: [_isbn], systemIds: ['Tokyo_Koto']).toList();

      expect(snapshots.length, 3);
      expect(snapshots.map((s) => s.complete), [false, false, true]);
      expect(snapshots.first.byIsbn[_isbn]!.single.isRunning, isTrue);
      expect(snapshots.last.byIsbn[_isbn]!.single.isSettled, isTrue);
    });

    test('**聞き直しは session だけで送る。** ISBN を送り直すと枠を二重に使う', () async {
      server.checkBodies = [_running, _settled];
      await makeClient().check(
          isbn13s: [_isbn, _other], systemIds: ['Tokyo_Koto', 'Tokyo_Minato']).toList();

      final first = server.requests.first.queryParameters;
      expect(first['isbn'], '$_isbn,$_other');
      expect(first['systemid'], 'Tokyo_Koto,Tokyo_Minato');
      expect(first['callback'], 'no');
      expect(first['format'], 'json');

      final second = server.requests[1].queryParameters;
      expect(second['session'], 'abc');
      expect(second.containsKey('isbn'), isFalse);
      expect(second.containsKey('systemid'), isFalse);
      expect(second['callback'], 'no');
    });

    test('**聞き直す間隔は2秒を下回らない**', () async {
      server.checkBodies = [_running, _running, _settled];
      await makeClient().check(isbn13s: [_isbn], systemIds: ['Tokyo_Koto']).toList();

      expect(clock.waited.length, 2);
      for (final waited in clock.waited) {
        expect(waited >= minPollInterval, isTrue, reason: '$waited');
      }
    });

    test('知らない状態も、そのまま持って上へ渡す', () async {
      server.checkBodies = [
        '{"continue":0,"books":{"$_isbn":{"Tokyo_Koto":'
            '{"status":"Renovating","libkey":{"豊洲":"改装中につき未定"}}}}}'
      ];
      final snapshot = await makeClient()
          .check(isbn13s: [_isbn], systemIds: ['Tokyo_Koto']).first;
      final holding = snapshot.byIsbn[_isbn]!.single;

      expect(holding.status, 'Renovating');
      expect(holding.isSettled, isFalse);
      expect(holding.isRunning, isFalse);
      expect(holding.isError, isFalse);
      expect(holding.libkeyStatuses['豊洲'], '改装中につき未定');
    });

    test('館の Error は「蔵書なし」ではない', () async {
      server.checkBodies = [
        '{"continue":0,"books":{"$_isbn":{"Tokyo_Koto":{"status":"Error"}}}}'
      ];
      final snapshot = await makeClient()
          .check(isbn13s: [_isbn], systemIds: ['Tokyo_Koto']).first;

      expect(snapshot.byIsbn[_isbn]!.single.isError, isTrue);
      expect(snapshot.complete, isTrue);
    });
  });

  group('止まり方', () {
    test('**全体の期限で打ち切る。** 取れている分は残す', () async {
      server.checkBodies = [_running];
      final snapshots = await makeClient(overallTimeout: const Duration(seconds: 5))
          .check(isbn13s: [_isbn], systemIds: ['Tokyo_Koto']).toList();

      expect(snapshots.last.failure, ApiFailure.timeout);
      expect(snapshots.last.complete, isFalse);
      expect(snapshots.last.byIsbn[_isbn]!.single.isRunning, isTrue);
    });

    test('途中で失敗しても、前に届いた分は消さない', () async {
      server.checkBodies = [_running];
      final client = makeClient();
      final events = <HoldingsSnapshot>[];
      final done = client
          .check(isbn13s: [_isbn], systemIds: ['Tokyo_Koto'])
          .listen((event) {
            events.add(event);
            if (events.length == 1) server.checkStatus = 500;
          })
          .asFuture<void>();
      await done;

      expect(events.last.failure, ApiFailure.server);
      expect(events.last.byIsbn[_isbn]!.single.isRunning, isTrue);
    });

    test('**購読をやめれば聞き直しも止まる。** 閉じた画面のために枠を使わない', () async {
      server.checkBodies = [_running];
      final subscription = makeClient()
          .check(isbn13s: [_isbn], systemIds: ['Tokyo_Koto']).listen(null);
      subscription.onData((_) => subscription.cancel());

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.requests.length, 1);
    });

    test('continue が立っているのに session が無ければ読めない応答である', () async {
      server.checkBodies = ['{"continue":1,"books":{}}'];
      final snapshot = await makeClient()
          .check(isbn13s: [_isbn], systemIds: ['Tokyo_Koto']).first;

      expect(snapshot.failure, ApiFailure.invalidData);
    });
  });

  group('呼び方の間違い', () {
    test('**予算は ISBN 数 × systemid 数で数える。** HTTP の回数ではない', () {
      final client = makeClient(budget: 4);
      expect(
        () => client.check(
            isbn13s: [_isbn, _other, '9784780802047'],
            systemIds: ['Tokyo_Koto', 'Tokyo_Minato']),
        throwsArgumentError,
      );
      // 4件ちょうどは通る。
      expect(
        client.check(
            isbn13s: [_isbn, _other], systemIds: ['Tokyo_Koto', 'Tokyo_Minato']),
        isA<Stream<HoldingsSnapshot>>(),
      );
    });

    test('重複を除いてから数える。同じ館を2回渡しても枠は1つぶん', () {
      expect(
        makeClient(budget: 1).check(
            isbn13s: [_isbn, _isbn], systemIds: ['Tokyo_Koto', 'Tokyo_Koto']),
        isA<Stream<HoldingsSnapshot>>(),
      );
    });

    test('ISBN も systemid も空では照会しない', () {
      expect(() => makeClient().check(isbn13s: [], systemIds: ['Tokyo_Koto']),
          throwsArgumentError);
      expect(() => makeClient().check(isbn13s: [_isbn], systemIds: []),
          throwsArgumentError);
    });

    test('正規化していない ISBN を弾く', () {
      expect(
        () => makeClient().check(isbn13s: ['427421933X'], systemIds: ['Tokyo_Koto']),
        throwsArgumentError,
      );
    });

    test('2秒を下回る間隔では作らせない。キー無しでも作らせない', () {
      expect(
        () => CalilCheckClient(
            appkey: 'k', pollInterval: const Duration(milliseconds: 500)),
        throwsArgumentError,
      );
      expect(() => CalilCheckClient(appkey: ''), throwsArgumentError);
    });
  });
}
