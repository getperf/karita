/// 認可。**ネットワークにも本物の Google にも触らない。**
///
/// token endpoint を偽サーバで立て、loopback のコールバックは試験が自分で叩く。実 Drive に
/// 残る問いは「Google が実際にどう応答するか」だけになる。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String t0 = '2026-09-02T09:00:00Z';

/// token endpoint だけを話す偽サーバ。
class _FakeTokenEndpoint {
  final HttpServer _server;

  /// 受け取ったフォーム。**要求の組み立てを検査するためにある。**
  final List<Map<String, String>> forms = [];

  /// 次の応答。null なら既定の成功を返す。
  Map<String, Object?>? nextPayload;

  /// 次の応答の status。
  int nextStatus = 200;

  _FakeTokenEndpoint._(this._server);

  static Future<_FakeTokenEndpoint> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeTokenEndpoint._(server);
    fake._serve();
    return fake;
  }

  String get uri => 'http://127.0.0.1:${_server.port}/token';

  Future<void> close() => _server.close(force: true);

  void _serve() async {
    await for (final request in _server) {
      final body = await utf8.decoder.bind(request).join();
      forms.add(Uri.splitQueryString(body));
      final payload =
          nextPayload ??
          {
            'access_token': 'fresh-access',
            'refresh_token': 'the-refresh',
            'expires_in': 3600,
            'scope': appDataScope,
          };
      request.response
        ..statusCode = nextStatus
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(payload));
      await request.response.close();
      nextStatus = 200;
      nextPayload = null;
    }
  }
}

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('karita-auth-'));
  tearDown(() => work.deleteSync(recursive: true));

  String pathIn(String name) => '${work.path}${Platform.pathSeparator}$name';

  group('PKCE と認可 URL', () {
    test('challenge は verifier の SHA-256 を padding 無しで base64url にしたもの', () {
      // RFC 7636 の例。**外部の定義に対して固定する** — 自前の実装同士で一致しても意味が無い。
      expect(
        codeChallengeOf('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('scope は appdata の一つだけである', () {
      final url = authorizationUrl(
        const DesktopClient(clientId: 'id', clientSecret: 'secret'),
        redirectUri: 'http://127.0.0.1:1234/oauth2callback',
        verifier: 'v' * 64,
        state: 'st',
      );
      expect(url.queryParameters['scope'], appDataScope);
      // 広げると、appDataFolder の外を触れる資格情報が端末に残る。
      expect(url.queryParameters['scope'], isNot(contains(' ')));
    });

    test('refresh token を返させる2つを必ず付ける', () {
      // 付け忘れると、二度目以降の認可で refresh token が返らず、その端末は access token が
      // 切れた時点で再ログインを要求し続ける。
      final url = authorizationUrl(
        const DesktopClient(clientId: 'id', clientSecret: 'secret'),
        redirectUri: 'http://127.0.0.1:1234/oauth2callback',
        verifier: 'v' * 64,
        state: 'st',
      );
      expect(url.queryParameters['access_type'], 'offline');
      expect(url.queryParameters['prompt'], 'consent');
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(url.queryParameters['response_type'], 'code');
    });
  });

  group('コールバックの検査', () {
    test('state が一致しなければ拒む', () {
      // 通すと、他所で始まった認可の結果を取り込む。
      expect(
        () => authorizationCodeFrom({'code': 'c', 'state': 'other'}, 'mine'),
        throwsA(isA<TransportAuthError>()),
      );
    });

    test('拒否は拒否として出す', () {
      expect(
        () => authorizationCodeFrom({'error': 'access_denied'}, 'mine'),
        throwsA(isA<TransportAuthError>()),
      );
    });

    test('code が無ければ拒む', () {
      expect(
        () => authorizationCodeFrom({'state': 'mine'}, 'mine'),
        throwsA(isA<TransportAuthError>()),
      );
    });

    test('文言に認可コードを入れない', () {
      try {
        authorizationCodeFrom({
          'code': 'secret-code',
          'state': 'other',
        }, 'mine');
        fail('落ちるはずである');
      } on TransportAuthError catch (exc) {
        expect(exc.message, isNot(contains('secret-code')));
      }
    });
  });

  group('token endpoint', () {
    late _FakeTokenEndpoint endpoint;
    late GoogleOAuth oauth;

    setUp(() async {
      endpoint = await _FakeTokenEndpoint.start();
      oauth = GoogleOAuth(
        DesktopClient(
          clientId: 'client-id',
          clientSecret: 'client-secret',
          tokenUri: endpoint.uri,
        ),
      );
    });

    tearDown(() async {
      oauth.close();
      await endpoint.close();
    });

    test('認可コードの交換は verifier を送る', () async {
      final token = await oauth.exchangeCode(
        code: 'the-code',
        verifier: 'the-verifier',
        redirectUri: 'http://127.0.0.1:1/oauth2callback',
        now: t0,
      );

      expect(token.accessToken, 'fresh-access');
      expect(token.refreshToken, 'the-refresh');
      expect(token.expiryUtc, '2026-09-02T10:00:00Z');

      final form = endpoint.forms.single;
      expect(form['grant_type'], 'authorization_code');
      expect(form['code_verifier'], 'the-verifier');
      expect(form['code'], 'the-code');
    });

    test('refresh token を返さない交換は保存に進ませない', () async {
      // 保存すると、access token が切れた時点で回復手段の無い端末ができる。
      endpoint.nextPayload = {'access_token': 'a', 'expires_in': 3600};
      await expectLater(
        oauth.exchangeCode(code: 'c', verifier: 'v', redirectUri: 'r', now: t0),
        throwsA(isA<TransportAuthError>()),
      );
    });

    test('更新は前の refresh token を引き継ぐ', () async {
      // **refresh の応答は refresh token を返さない。** 引き継がないと、1回更新しただけで
      // その端末は回復手段を失う。
      endpoint.nextPayload = {'access_token': 'newer', 'expires_in': 3600};
      final refreshed = await oauth.refresh(
        const Token(accessToken: 'old', refreshToken: 'keep-me'),
        now: t0,
      );
      expect(refreshed.accessToken, 'newer');
      expect(refreshed.refreshToken, 'keep-me');
    });

    test('invalid_grant は認可の失敗である', () async {
      // 再ログイン以外に回復手段は無い。
      endpoint
        ..nextStatus = 400
        ..nextPayload = {
          'error': invalidGrant,
          'error_description': 'Token has been expired or revoked.',
        };
      await expectLater(
        oauth.refresh(
          const Token(accessToken: 'a', refreshToken: 'r'),
          now: t0,
        ),
        throwsA(
          isA<TransportAuthError>().having(
            (e) => e.message,
            'message',
            contains(invalidGrant),
          ),
        ),
      );
    });

    test('error_description は写さない', () async {
      // 入力を含みうる。診断に要るのは種別だけである。
      endpoint
        ..nextStatus = 400
        ..nextPayload = {
          'error': invalidGrant,
          'error_description': 'SENSITIVE',
        };
      try {
        await oauth.refresh(
          const Token(accessToken: 'a', refreshToken: 'r'),
          now: t0,
        );
        fail('落ちるはずである');
      } on TransportAuthError catch (exc) {
        expect(exc.message, isNot(contains('SENSITIVE')));
      }
    });

    test('到達できないことは認可喪失ではない', () async {
      // 通信が落ちているだけの状態を認可喪失として記録すると、blocked_auth が
      // 「送れなかった理由」を取り違える。
      final dead = GoogleOAuth(
        const DesktopClient(
          clientId: 'id',
          clientSecret: 'secret',
          tokenUri: 'http://127.0.0.1:1/token',
        ),
      );
      await expectLater(
        dead.refresh(
          const Token(accessToken: 'a', refreshToken: 'r'),
          now: t0,
        ),
        throwsA(
          isA<SyncDataError>().having((e) => e.code, 'code', 'transport-io'),
        ),
      );
      dead.close();
    });

    test('refresh token が無ければ更新に行かない', () async {
      await expectLater(
        oauth.refresh(const Token(accessToken: 'a'), now: t0),
        throwsA(isA<TransportAuthError>()),
      );
      expect(endpoint.forms, isEmpty, reason: '送る値が無いのに要求している');
    });
  });

  group('保存と取り出し', () {
    late _FakeTokenEndpoint endpoint;
    late GoogleOAuth oauth;
    late TokenStore store;

    setUp(() async {
      endpoint = await _FakeTokenEndpoint.start();
      oauth = GoogleOAuth(
        DesktopClient(
          clientId: 'client-id',
          clientSecret: 'client-secret',
          tokenUri: endpoint.uri,
        ),
      );
      store = TokenStore(pathIn('token.json'));
    });

    tearDown(() async {
      oauth.close();
      await endpoint.close();
    });

    GoogleAccessTokenProvider providerAt(String at) =>
        GoogleAccessTokenProvider(store: store, oauth: oauth, now: () => at);

    test('往復する', () {
      store.save(
        const Token(
          accessToken: 'a',
          refreshToken: 'r',
          expiryUtc: '2026-09-02T10:00:00Z',
        ),
      );
      final loaded = store.load()!;
      expect(loaded.accessToken, 'a');
      expect(loaded.refreshToken, 'r');
      expect(loaded.scopes, [appDataScope]);
    });

    test('読めないトークンは「無い」とする', () {
      File(pathIn('token.json')).writeAsStringSync('{ broken');
      expect(store.load(), isNull);
      // 落とさない。認可し直せば回復する状態であり、起動そのものを止める理由にならない。
    });

    test('保存は途中の実体を残さない', () {
      store.save(const Token(accessToken: 'a', refreshToken: 'r'));
      expect(work.listSync().map((e) => e.uri.pathSegments.last), [
        'token.json',
      ]);
    });

    test('サインインしていなければ認可の失敗である', () async {
      // 空文字を返さない。呼び出し側が「認可が無い」と区別できないまま要求を組むことになる。
      await expectLater(
        providerAt(t0).accessToken(),
        throwsA(isA<TransportAuthError>()),
      );
    });

    test('期限内なら保存されたものをそのまま返す', () async {
      store.save(
        const Token(
          accessToken: 'still-good',
          refreshToken: 'r',
          expiryUtc: '2026-09-02T10:00:00Z',
        ),
      );
      expect(await providerAt(t0).accessToken(), 'still-good');
      expect(endpoint.forms, isEmpty, reason: '要らない更新に行っている');
    });

    test('期限が近ければ更新して保存する', () async {
      // **余裕を持って切る。** 要求を組んでから届くまでの間に切れると、その1回が必ず 401 に
      // なる。
      store.save(
        const Token(
          accessToken: 'stale',
          refreshToken: 'r',
          expiryUtc: '2026-09-02T09:00:30Z',
        ),
      );
      expect(await providerAt(t0).accessToken(), 'fresh-access');
      expect(
        store.load()!.accessToken,
        'fresh-access',
        reason: '更新した結果を保存していない',
      );
    });

    test('更新した結果を保存できなくても、同期は止めない', () async {
      // **平文へは戻さない。** 失うのは新しい access token の永続化だけで、保存済みの
      // refresh token が次の起動で取り直す。
      final protector = _SwitchableProtector();
      final failingStore =
          TokenStore(pathIn('token.json'), protector: protector)..save(
            const Token(
              accessToken: 'stale',
              refreshToken: 'r',
              expiryUtc: '2026-09-02T09:00:30Z',
            ),
          );
      protector.failProtect = true;
      final provider = GoogleAccessTokenProvider(
        store: failingStore,
        oauth: oauth,
        now: () => t0,
      );
      expect(await provider.accessToken(), 'fresh-access');
      protector.failProtect = false;
      expect(failingStore.load()!.accessToken, 'stale');
    });

    test('期限が分からないものは切れていないとみなす', () async {
      // 分からないことを理由に毎回 refresh すると、refresh token を持たない端末が毎回落ちる。
      // 本当に切れていればサーバが 401 を返し、そこで取り直す。
      store.save(const Token(accessToken: 'unknown-expiry', refreshToken: 'r'));
      expect(await providerAt(t0).accessToken(), 'unknown-expiry');
      expect(endpoint.forms, isEmpty);
    });

    test('取り直しを求められたら期限内でも更新する', () async {
      // これがサーバの 401 に応える経路である。
      store.save(
        const Token(
          accessToken: 'still-good',
          refreshToken: 'r',
          expiryUtc: '2026-09-02T23:00:00Z',
        ),
      );
      final provider = providerAt(t0);
      expect(await provider.accessToken(), 'still-good');
      expect(await provider.accessToken(forceRefresh: true), 'fresh-access');
      expect(endpoint.forms.single['grant_type'], 'refresh_token');
    });

    test('status は有無と期限だけを出す', () async {
      // access token も refresh token も表示しない。
      expect(providerAt(t0).status().present, isFalse);
      store.save(
        const Token(
          accessToken: 'a',
          refreshToken: 'r',
          expiryUtc: '2026-09-02T10:00:00Z',
        ),
      );
      final status = providerAt(t0).status();
      expect(status.present, isTrue);
      expect(status.expiryUtc, '2026-09-02T10:00:00Z');
      expect(status.expired, isFalse);
    });

    test('forget しないと、ファイルを消しても status がキャッシュを見続ける', () async {
      store.save(
        const Token(
          accessToken: 'a',
          refreshToken: 'r',
          expiryUtc: '2026-09-02T10:00:00Z',
        ),
      );
      final provider = providerAt(t0);
      await provider.accessToken(); // ここで _cached に載る。
      store.clear();
      expect(
        provider.status().present,
        isTrue,
        reason: 'forget を呼ぶ前は、消したファイルではなくキャッシュを見る',
      );

      provider.forget();
      expect(
        provider.status().present,
        isFalse,
        reason: 'forget の後は、消えたファイルどおり「無い」と答える',
      );
    });

    test('clear で消える', () {
      store.save(const Token(accessToken: 'a', refreshToken: 'r'));
      expect(store.clear(), isTrue);
      expect(store.load(), isNull);
      expect(store.clear(), isFalse);
    });
  });

  group('loopback の認可', () {
    test('ブラウザから戻ってきたコードを交換して保存する', () async {
      final endpoint = await _FakeTokenEndpoint.start();
      final oauth = GoogleOAuth(
        DesktopClient(
          clientId: 'client-id',
          clientSecret: 'client-secret',
          tokenUri: endpoint.uri,
        ),
      );
      final store = TokenStore(pathIn('token.json'));
      var counter = 0;

      final login = LoopbackLogin(
        oauth: oauth,
        store: store,
        now: () => t0,
        randomToken: () => 'fixed-${++counter}',
        // ブラウザの代わりに、試験がコールバックを叩く。**ポートは OS が選ぶ**ので、
        // 認可 URL から読み取るしかない。
        openBrowser: (url) async {
          final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
          final state = url.queryParameters['state']!;
          // **応答を待たない。** ブラウザは開いて去るだけで、認可の完了を待つのは
          // こちら側である。待つと、応答を書く前の時点で互いに止まる。
          unawaited(
            http.get(
              redirect.replace(
                queryParameters: {'code': 'the-code', 'state': state},
              ),
            ),
          );
        },
      );

      final token = await login.login();
      expect(token.accessToken, 'fresh-access');
      expect(store.load()!.refreshToken, 'the-refresh');

      // 交換には、認可 URL に載せた challenge に対応する verifier が送られる。
      expect(endpoint.forms.single['code_verifier'], 'fixed-1');
      expect(endpoint.forms.single['code'], 'the-code');

      oauth.close();
      await endpoint.close();
    });

    test('state が違うコールバックは交換に進まない', () async {
      final endpoint = await _FakeTokenEndpoint.start();
      final oauth = GoogleOAuth(
        DesktopClient(
          clientId: 'id',
          clientSecret: 'secret',
          tokenUri: endpoint.uri,
        ),
      );
      final store = TokenStore(pathIn('token.json'));

      final login = LoopbackLogin(
        oauth: oauth,
        store: store,
        now: () => t0,
        randomToken: () => 'fixed',
        openBrowser: (url) async {
          final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
          // **応答を待たない。** ブラウザは開いて去るだけで、認可の完了を待つのは
          // こちら側である。待つと、応答を書く前の時点で互いに止まる。
          unawaited(
            http.get(
              redirect.replace(
                queryParameters: {'code': 'the-code', 'state': 'someone-else'},
              ),
            ),
          );
        },
      );

      await expectLater(login.login(), throwsA(isA<TransportAuthError>()));
      expect(endpoint.forms, isEmpty, reason: '他所の認可の結果を交換している');
      expect(store.load(), isNull);

      oauth.close();
      await endpoint.close();
    });
  });

  group('既定パス', () {
    test('Windows は LOCALAPPDATA の下の Karita', () {
      final paths = WindowsAppPaths.resolve(
        environment: {'LOCALAPPDATA': r'C:\Users\x\AppData\Local'},
      );
      expect(paths.home, r'C:\Users\x\AppData\Local\Karita');
      // **参照実装の `blib` と衝突させない。** 同じ機械で両方を走らせ、ローカルは別・Drive は
      // 同じ、という形で言語間の往復を測る。
      expect(paths.home, isNot(contains('blib')));
    });

    test('KARITA_HOME が丸ごと差し替える', () {
      final paths = WindowsAppPaths.resolve(
        environment: {
          'LOCALAPPDATA': r'C:\Users\x\AppData\Local',
          homeEnvVar: r'D:\tmp\one',
        },
      );
      expect(paths.home, r'D:\tmp\one');
    });

    test('決められないときは推測しない', () {
      // 代わりを立てると、環境ごとに違う場所へ台帳ができ、「前の台帳が見つからない」が起こる。
      expect(
        () => WindowsAppPaths.resolve(environment: const {}),
        throwsA(
          isA<SyncDataError>().having(
            (e) => e.code,
            'code',
            'paths-unresolved',
          ),
        ),
      );
    });

    test('台帳とトークンは別のファイルである', () {
      final paths = WindowsAppPaths.resolve(
        environment: {homeEnvVar: pathIn('h')},
      );
      expect(paths.dbPath, isNot(paths.tokenPath));
      paths.ensure();
      expect(Directory(paths.home).existsSync(), isTrue);
    });
  });
}

/// 可逆な置換。**保存の失敗を注入するためにある。**
class _SwitchableProtector implements TokenProtector {
  bool failProtect = false;

  @override
  Uint8List protect(Uint8List plain) {
    if (failProtect) throw const TokenProtectionException('protect');
    return Uint8List.fromList([for (final b in plain) b ^ 0x5A]);
  }

  @override
  Uint8List unprotect(Uint8List sealed) =>
      Uint8List.fromList([for (final b in sealed) b ^ 0x5A]);
}
