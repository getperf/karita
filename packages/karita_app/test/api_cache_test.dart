/// 外部 API を抱える容れ物。**期限と上限と、要求の相乗りだけを測る。**
///
/// 何を何秒持つかはここでは決めない（`api_defaults.dart`）。ここで固定するのは
/// 「言われた長さを守る」「溢れたら古いほうから落ちる」「切れたものが生きているものを
/// 押し出さない」の3つである。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';

void main() {
  late DateTime now;
  DateTime clock() => now;

  setUp(() => now = DateTime.utc(2026, 9, 16, 12));

  group('期限', () {
    test('入れたものを読める', () {
      final cache = ExpiringCache<String, int>(maxEntries: 8, now: clock);
      cache.write('a', 1, const Duration(minutes: 5));

      expect(cache.read('a'), 1);
      expect(cache.length, 1);
    });

    test('**切れたら読めない。** そのとき捨てている', () {
      final cache = ExpiringCache<String, int>(maxEntries: 8, now: clock);
      cache.write('a', 1, const Duration(minutes: 5));

      now = now.add(const Duration(minutes: 5));
      expect(cache.read('a'), isNull);
      expect(cache.length, 0);
    });

    test('結末ごとに違う長さで持てる', () {
      final cache = ExpiringCache<String, String>(maxEntries: 8, now: clock);
      cache.write('found', 'ok', const Duration(hours: 1));
      cache.write('failed', 'ng', const Duration(seconds: 60));

      now = now.add(const Duration(minutes: 5));
      expect(cache.read('found'), 'ok');
      expect(cache.read('failed'), isNull);
    });

    test('**0 以下の期限では持たない。** 「持たない」を表せるようにしておく', () {
      final cache = ExpiringCache<String, int>(maxEntries: 8, now: clock);
      cache.write('a', 1, Duration.zero);

      expect(cache.read('a'), isNull);
      expect(cache.length, 0);
    });
  });

  group('上限', () {
    test('件数を超えたら、いちばん古く入れたものから落ちる', () {
      final cache = ExpiringCache<String, int>(maxEntries: 2, now: clock);
      cache.write('a', 1, const Duration(hours: 1));
      cache.write('b', 2, const Duration(hours: 1));
      cache.write('c', 3, const Duration(hours: 1));

      expect(cache.read('a'), isNull);
      expect(cache.read('b'), 2);
      expect(cache.read('c'), 3);
    });

    test('重さで縛れる。**1件の大きさが桁違いのものに使う**', () {
      final cache = ExpiringCache<String, List<int>>(
        maxEntries: 100,
        maxWeight: 10,
        weigh: (value) => value.length,
        now: clock,
      );
      cache.write('a', List.filled(6, 0), const Duration(hours: 1));
      cache.write('b', List.filled(6, 0), const Duration(hours: 1));

      expect(cache.read('a'), isNull);
      expect(cache.weight, 6);
    });

    test('同じ鍵を入れ直しても重さが二重にならない', () {
      final cache = ExpiringCache<String, List<int>>(
        maxEntries: 100,
        maxWeight: 100,
        weigh: (value) => value.length,
        now: clock,
      );
      cache.write('a', List.filled(6, 0), const Duration(hours: 1));
      cache.write('a', List.filled(3, 0), const Duration(hours: 1));

      expect(cache.length, 1);
      expect(cache.weight, 3);
    });

    test('**切れたものを先に捨てる。** 生きているものを押し出さない', () {
      final cache = ExpiringCache<String, int>(maxEntries: 2, now: clock);
      cache.write('old', 1, const Duration(seconds: 30));
      cache.write('live', 2, const Duration(hours: 1));

      now = now.add(const Duration(minutes: 1));
      cache.write('new', 3, const Duration(hours: 1));

      expect(cache.read('live'), 2);
      expect(cache.read('new'), 3);
      expect(cache.read('old'), isNull);
    });
  });

  group('捨てる', () {
    test('鍵ごとに捨てられる。**明示の取り直しがこれを使う**', () {
      final cache = ExpiringCache<String, int>(maxEntries: 8, now: clock);
      cache.write('a', 1, const Duration(hours: 1));
      cache.remove('a');

      expect(cache.read('a'), isNull);
    });

    test('全部捨てられる', () {
      final cache = ExpiringCache<String, int>(maxEntries: 8, now: clock);
      cache.write('a', 1, const Duration(hours: 1));
      cache.write('b', 2, const Duration(hours: 1));
      cache.clear();

      expect(cache.length, 0);
      expect(cache.weight, 0);
    });
  });

  group('要求の相乗り', () {
    test('**走っている間は1本にまとまる**', () async {
      final shared = SharedRequests<String, int>();
      final gate = Completer<int>();
      var started = 0;

      final first = shared.run('a', () {
        started++;
        return gate.future;
      });
      final second = shared.run('a', () {
        started++;
        return gate.future;
      });
      expect(started, 1);
      expect(shared.inFlight, 1);

      gate.complete(7);
      expect(await first, 7);
      expect(await second, 7);
    });

    test('終われば次は新しく始まる', () async {
      final shared = SharedRequests<String, int>();
      var started = 0;

      await shared.run('a', () async {
        started++;
        return 1;
      });
      await shared.run('a', () async {
        started++;
        return 2;
      });

      expect(started, 2);
      expect(shared.inFlight, 0);
    });

    test('**失敗しても控えから外れる。** 二度と走らないことにしない', () async {
      final shared = SharedRequests<String, int>();

      await expectLater(
        shared.run('a', () async => throw StateError('落ちた')),
        throwsStateError,
      );
      expect(shared.inFlight, 0);
      expect(await shared.run('a', () async => 5), 5);
    });

    test('鍵が違えば別に走る', () async {
      final shared = SharedRequests<String, int>();
      final gate = Completer<int>();

      unawaited(shared.run('a', () => gate.future));
      unawaited(shared.run('b', () => gate.future));
      expect(shared.inFlight, 2);

      gate.complete(1);
    });
  });
}
