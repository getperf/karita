/// Android の認可を、**Play services 無しで**測る。
///
/// 実機で確かめるのは「Play services が実際にどう振る舞うか」であって、こちらの判断ではない。
/// 判断（無音で取る・取れなければ投げる・取り直しは捨ててから取る）は偽の口に対して固定できる。
/// **固定しておかないと、P4b の「refresh 不能時の `blocked_auth`」が実機で初めて壊れる。**
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_platform_flutter/karita_platform_flutter.dart';
import 'package:karita_sync/karita_sync.dart';

/// 台本どおりに返す偽の Play services。**呼ばれた順を記録する。**
class _FakeClient implements AndroidAuthorizationClient {
  /// `tokenForScopes` が順に返すもの。`null` は「無音では取れない」。
  final List<String?> silent;

  /// `requestScopes` が返すもの。`null` なら、呼ばれること自体を赤にする。
  final String? interactive;

  /// 渡せば `requestScopes` はこれが完了するまで戻らない。**画面を出している間**を作る。
  final Completer<String>? pendingInteractive;

  final List<String> calls = <String>[];
  int _initializeCount = 0;
  int _silentIndex = 0;

  _FakeClient({
    required this.silent,
    this.interactive,
    this.pendingInteractive,
  });

  int get initializeCount => _initializeCount;

  @override
  Future<void> initialize() async {
    _initializeCount++;
    calls.add('initialize');
  }

  @override
  Future<String?> tokenForScopes(List<String> scopes) async {
    expect(scopes, <String>[appDataScope]);
    calls.add('tokenForScopes');
    return _silentIndex < silent.length ? silent[_silentIndex++] : null;
  }

  @override
  Future<String> requestScopes(List<String> scopes) async {
    expect(scopes, <String>[appDataScope]);
    calls.add('requestScopes');
    final pending = pendingInteractive;
    if (pending != null) return pending.future;
    final token = interactive;
    if (token == null) {
      fail('画面を出す requestScopes が同期の経路から呼ばれた');
    }
    return token;
  }

  @override
  Future<void> clearToken(String accessToken) async {
    calls.add('clearToken($accessToken)');
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
  }
}

void main() {
  group('accessToken', () {
    test('無音で取れたものをそのまま返す', () async {
      final client = _FakeClient(silent: <String?>['at-1']);
      final provider = AndroidAccessTokenProvider(client);

      expect(await provider.accessToken(), 'at-1');
      expect(client.calls, <String>['initialize', 'tokenForScopes']);
    });

    test('無音で取れなければ TransportAuthError を投げ、画面を出さない', () async {
      // interactive を渡さないので、requestScopes が呼ばれたら fail する。
      final client = _FakeClient(silent: <String?>[null]);
      final provider = AndroidAccessTokenProvider(client);

      await expectLater(
        provider.accessToken(),
        throwsA(isA<TransportAuthError>()),
      );
      expect(client.calls, isNot(contains('requestScopes')));
    });

    test('forceRefresh は捨ててから無音で取り直す', () async {
      final client = _FakeClient(silent: <String?>['at-1', 'at-2']);
      final provider = AndroidAccessTokenProvider(client);

      expect(await provider.accessToken(), 'at-1');
      expect(await provider.accessToken(forceRefresh: true), 'at-2');

      // **捨てるのが先で、取り直すのが後である。** 逆だと、サーバに拒まれたものを
      // そのまま配り直す。
      expect(client.calls, <String>[
        'initialize',
        'tokenForScopes',
        'initialize',
        'clearToken(at-1)',
        'tokenForScopes',
      ]);
    });

    test('forceRefresh の後に取れなければ、それが認可の喪失である', () async {
      final client = _FakeClient(silent: <String?>['at-1', null]);
      final provider = AndroidAccessTokenProvider(client);

      expect(await provider.accessToken(), 'at-1');
      await expectLater(
        provider.accessToken(forceRefresh: true),
        throwsA(isA<TransportAuthError>()),
      );
      expect(client.calls, isNot(contains('requestScopes')));
    });

    test('配っていないうちの forceRefresh は捨てるものを持たない', () async {
      final client = _FakeClient(silent: <String?>['at-1']);
      final provider = AndroidAccessTokenProvider(client);

      expect(await provider.accessToken(forceRefresh: true), 'at-1');
      expect(client.calls, isNot(contains('clearToken(at-1)')));
    });
  });

  group('authorize', () {
    test('無音で取れるなら画面を出さない', () async {
      final client = _FakeClient(silent: <String?>['at-1']);
      await AndroidAccessTokenProvider(client).authorize();

      expect(client.calls, isNot(contains('requestScopes')));
    });

    test('無音で取れないときだけ画面を出す', () async {
      final client = _FakeClient(silent: <String?>[null], interactive: 'at-9');
      final provider = AndroidAccessTokenProvider(client);

      await provider.authorize();
      expect(client.calls, contains('requestScopes'));

      // 画面で得たものが、次の clearLocalState の対象になっている。
      await provider.clearLocalState();
      expect(client.calls, contains('clearToken(at-9)'));
    });
  });

  group('clearLocalState', () {
    test('配ったものを捨てる', () async {
      final client = _FakeClient(silent: <String?>['at-1']);
      final provider = AndroidAccessTokenProvider(client);

      await provider.accessToken();
      await provider.clearLocalState();
      expect(client.calls, contains('clearToken(at-1)'));
    });

    test('二度目は捨てるものを持たない', () async {
      final client = _FakeClient(silent: <String?>['at-1']);
      final provider = AndroidAccessTokenProvider(client);

      await provider.accessToken();
      await provider.clearLocalState();
      final before = client.calls.length;
      await provider.clearLocalState();
      expect(client.calls.length, before);
    });
  });

  group('authorized', () {
    test('有無だけを返す', () async {
      expect(
        await AndroidAccessTokenProvider(_FakeClient(silent: <String?>['at-1']))
            .authorized(),
        isTrue,
      );
      expect(
        await AndroidAccessTokenProvider(_FakeClient(silent: <String?>[null]))
            .authorized(),
        isFalse,
      );
    });
  });

  group('画面を出している間', () {
    // iOS の Google Sign-In SDK は進行中の操作を1つしか持たない。画面の途中で無音の復元が
    // 来ると、画面の側の完了が呼ばれなくなる（2026-10-22、iOS シミュレーターで実測）。
    test('無音の経路は、画面が閉じるまで client を呼ばない', () async {
      final screen = Completer<String>();
      final client = _FakeClient(
        silent: <String?>[null, 'at-2', 'at-2'],
        pendingInteractive: screen,
      );
      final provider = AndroidAccessTokenProvider(client);

      final signingIn = provider.authorize();
      await pumpEventQueue();
      final present = provider.authorized();
      final token = provider.accessToken();
      await pumpEventQueue();
      expect(
        client.calls.where((c) => c == 'tokenForScopes'),
        hasLength(1),
        reason: '画面の前の1回だけ。画面の途中で無音の経路を走らせない',
      );

      screen.complete('at-1');
      await signingIn;
      expect(await present, isTrue);
      expect(await token, 'at-2');
    });

    test('重ねて押しても画面は1つである', () async {
      final screen = Completer<String>();
      final client = _FakeClient(
        silent: <String?>[null],
        pendingInteractive: screen,
      );
      final provider = AndroidAccessTokenProvider(client);

      final first = provider.authorize();
      final second = provider.authorize();
      await pumpEventQueue();
      screen.complete('at-1');
      await Future.wait([first, second]);

      expect(client.calls.where((c) => c == 'requestScopes'), hasLength(1));
    });

    test('画面が失敗しても、待っていた無音の経路は進む', () async {
      final screen = Completer<String>();
      final client = _FakeClient(
        silent: <String?>[null, null],
        pendingInteractive: screen,
      );
      final provider = AndroidAccessTokenProvider(client);

      final signingIn = provider.authorize();
      await pumpEventQueue();
      final present = provider.authorized();
      screen.completeError(StateError('canceled'));

      await expectLater(signingIn, throwsStateError);
      expect(await present, isFalse);
    });
  });

  group('signOut', () {
    test('SDK のサインインを消す。画面は出さない', () async {
      final client = _FakeClient(silent: <String?>[]);
      final provider = AndroidAccessTokenProvider(client);

      await provider.signOut();

      expect(client.calls, <String>['initialize', 'signOut']);
    });

    test('画面を出している間は、閉じるまで消さない', () async {
      // 画面の途中で SDK を触ると、画面の側の完了が呼ばれなくなる（無音の経路と同じ理由）。
      final screen = Completer<String>();
      final client = _FakeClient(
        silent: <String?>[null],
        pendingInteractive: screen,
      );
      final provider = AndroidAccessTokenProvider(client);

      final signingIn = provider.authorize();
      await pumpEventQueue();
      final signingOut = provider.signOut();
      await pumpEventQueue();
      expect(client.calls, isNot(contains('signOut')));

      screen.complete('at-1');
      await signingIn;
      await signingOut;
      expect(client.calls.last, 'signOut');
    });
  });
}
