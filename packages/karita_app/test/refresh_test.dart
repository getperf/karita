/// 周期リフレッシュ。**いつ走らないかを固定する。**
///
/// 正本は `非公開資料:production-sync-small-changes.md`「背面同期を持たない」。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';

void main() {
  late List<RefreshTrigger> ran;
  late bool ready;

  RefreshLoop loop({
    bool enabled = true,
    Duration interval = const Duration(milliseconds: 20),
    Future<void> Function(RefreshTrigger)? run,
  }) => RefreshLoop(
    run: run ?? (trigger) async => ran.add(trigger),
    ready: () => ready,
    enabled: enabled,
    interval: interval,
  );

  setUp(() {
    ran = [];
    ready = true;
  });

  test('起動時に1回走る', () async {
    final refresh = loop(enabled: false);
    await refresh.start();
    expect(ran, [RefreshTrigger.startup]);
    refresh.stop();
  });

  test('初回起動の2択が済むまで回さない', () async {
    ready = false;
    final refresh = loop(enabled: false);
    await refresh.start();
    expect(ran, isEmpty);
    refresh.stop();
  });

  test('周期は enabled が false なら刻まない', () async {
    final refresh = loop(enabled: false);
    await refresh.start();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(refresh.running, isFalse);
    expect(ran, [RefreshTrigger.startup]);
    refresh.stop();
  });

  test('起きている間は周期で走る', () async {
    final refresh = loop();
    await refresh.start();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    refresh.stop();
    expect(ran, contains(RefreshTrigger.periodic));
  });

  test('前面から外れたら刻むのをやめ、戻せば刻み直す', () async {
    final refresh = loop();
    await refresh.start();
    refresh.pause();
    expect(refresh.running, isFalse);
    refresh.resume();
    expect(refresh.running, isTrue);
    refresh.stop();
  });

  test('前の1回が走っている間は重ねない', () async {
    final gate = Completer<void>();
    final refresh = loop(
      run: (trigger) async {
        ran.add(trigger);
        await gate.future;
      },
    );
    final first = refresh.trigger(RefreshTrigger.startup);
    expect(await refresh.trigger(RefreshTrigger.periodic), isFalse);
    gate.complete();
    await first;
    expect(ran, [RefreshTrigger.startup]);
    refresh.stop();
  });

  for (final fail in [false, true]) {
    test('同期中の複数保存を1回にまとめる（失敗=$fail）', () async {
      final gate = Completer<void>();
      final refresh = loop(
        run: (trigger) async {
          ran.add(trigger);
          if (ran.length == 1) {
            await gate.future;
            if (fail) throw StateError('offline');
          }
        },
      );
      final first = refresh.trigger(RefreshTrigger.startup);
      await refresh.trigger(RefreshTrigger.domainWrite);
      await refresh.trigger(RefreshTrigger.domainWrite);
      expect(ran, [RefreshTrigger.startup]);
      gate.complete();
      await first;
      expect(ran, [RefreshTrigger.startup, RefreshTrigger.domainWrite]);
      refresh.stop();
    });
  }

  test('終了時は追加同期を起動しない', () async {
    final gate = Completer<void>();
    final refresh = loop(
      run: (trigger) async {
        ran.add(trigger);
        await gate.future;
      },
    );
    final first = refresh.start();
    await refresh.trigger(RefreshTrigger.domainWrite);
    refresh.stop();
    gate.complete();
    await first;
    expect(ran, [RefreshTrigger.startup]);
    expect(refresh.running, isFalse);
  });

  test('背面では追加同期を保留し、復帰時に実行する', () async {
    final gate = Completer<void>();
    final refresh = loop(
      enabled: false,
      run: (trigger) async {
        ran.add(trigger);
        await gate.future;
      },
    );
    final first = refresh.trigger(RefreshTrigger.startup);
    await refresh.trigger(RefreshTrigger.domainWrite);
    refresh.pause();
    gate.complete();
    await first;
    expect(ran, [RefreshTrigger.startup]);
    refresh.resume();
    await Future<void>.delayed(Duration.zero);
    expect(ran, [RefreshTrigger.startup, RefreshTrigger.domainWrite]);
    refresh.stop();
  });

  group('前面復帰で取りに行く（2026-10-08）', () {
    late DateTime now;

    RefreshLoop clocked() => RefreshLoop(
      run: (trigger) async => ran.add(trigger),
      ready: () => ready,
      enabled: false,
      interval: const Duration(seconds: 30),
      clock: () => now,
    );

    setUp(() => now = DateTime.utc(2026, 10, 8, 9));

    test('直前の run から 30 秒以上空いていれば、復帰で1回走る', () async {
      final refresh = clocked();
      await refresh.start();
      refresh.pause();
      now = now.add(const Duration(seconds: 31));
      refresh.resume();
      await Future<void>.delayed(Duration.zero);
      expect(ran, [RefreshTrigger.startup, RefreshTrigger.resume]);
      refresh.stop();
    });

    test('間もない復帰は飛ばす（Windows のフォーカスの出入り）', () async {
      final refresh = clocked();
      await refresh.start();
      refresh.pause();
      now = now.add(const Duration(seconds: 5));
      refresh.resume();
      await Future<void>.delayed(Duration.zero);
      expect(ran, [RefreshTrigger.startup]);
      refresh.stop();
    });

    test('一度も走っていなければ復帰で走る', () async {
      final refresh = clocked();
      refresh.resume();
      await Future<void>.delayed(Duration.zero);
      expect(ran, [RefreshTrigger.resume]);
      refresh.stop();
    });

    test('初回起動の2択が済むまでは復帰でも回さない', () async {
      ready = false;
      final refresh = clocked();
      refresh.resume();
      await Future<void>.delayed(Duration.zero);
      expect(ran, isEmpty);
      refresh.stop();
    });
  });

  test('失敗しても止まらない', () async {
    final refresh = loop(run: (_) async => throw StateError('boom'));
    expect(await refresh.trigger(RefreshTrigger.startup), isFalse);
    expect(await refresh.trigger(RefreshTrigger.domainWrite), isFalse);
    refresh.stop();
  });

  test('手動は残るが、呼ぶのはデバッグ専用の口だけである', () async {
    final refresh = loop(enabled: false);
    expect(await refresh.trigger(RefreshTrigger.manual), isTrue);
    expect(ran, [RefreshTrigger.manual]);
    refresh.stop();
  });
}
