/// Google OAuth（Desktop クライアント + PKCE）。**ここが認可の実装である。**
///
/// **scope は `drive.appdata` の一つだけ**にする。広げると、利用者の同意画面が要求するものが
/// 増え、`appDataFolder` の外を触れる資格情報が端末に残る。
///
/// **`error_description` を写さない。** 診断に要るのは種別（`error`）だけで、説明文は入力を
/// 含みうる。記録と画面に出るものへ入力を混ぜない。
///
/// 移送元: book-sync-model の `src/bsync_core/gauth.py`。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';


const String appDataScope = 'https://www.googleapis.com/auth/drive.appdata';
const String defaultAuthUri = 'https://accounts.google.com/o/oauth2/auth';
const String defaultTokenUri = 'https://oauth2.googleapis.com/token';

/// 期限のこれだけ手前で「切れている」とみなす。
///
/// **0 にしない。** 要求を組んでからサーバに届くまでの間に切れると、その1回が必ず 401 になる。
const int expiryMarginSeconds = 60;

/// Desktop クライアントの素性。
class DesktopClient {
  final String clientId;
  final String clientSecret;
  final String authUri;
  final String tokenUri;

  const DesktopClient({
    required this.clientId,
    required this.clientSecret,
    this.authUri = defaultAuthUri,
    this.tokenUri = defaultTokenUri,
  });
}

/// 保存するトークン。
///
/// `expiryUtc` は RFC3339 秒精度・Z 終端で持つ。**文字列の昇順が時刻の昇順と一致する**ので、
/// 比較に日時の解析を要らない（封筒の `createdAtUtc` と同じ規約である）。
class Token {
  final String accessToken;
  final String? refreshToken;
  final String? expiryUtc;
  final List<String> scopes;

  const Token({
    required this.accessToken,
    this.refreshToken,
    this.expiryUtc,
    this.scopes = const [appDataScope],
  });

  /// 期限が切れているか。**期限が分からないものは切れていないとみなす。**
  ///
  /// 分からないことを理由に毎回 refresh すると、refresh token を持たない端末が毎回落ちる。
  /// 本当に切れていればサーバが 401 を返し、そこで取り直す。
  bool expired(String now) {
    final expiry = expiryUtc;
    if (expiry == null) return false;
    return expiry.compareTo(shiftSeconds(now, expiryMarginSeconds)) <= 0;
  }

  Map<String, Object?> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expiry_utc': expiryUtc,
        'scopes': scopes,
      };

  static Token? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final accessToken = raw['access_token'];
    if (accessToken is! String || accessToken.isEmpty) return null;
    final scopes = raw['scopes'];
    return Token(
      accessToken: accessToken,
      refreshToken: raw['refresh_token'] as String?,
      expiryUtc: raw['expiry_utc'] as String?,
      scopes: scopes is List
          ? [for (final scope in scopes) '$scope']
          : const [appDataScope],
    );
  }
}

/// PKCE の verifier。**43〜128 文字**の範囲に収める。
///
/// 呼び出し側が乱数を渡す。生成を差し替えられる形にしておかないと、認可の手順を機械で
/// 検査するときに毎回違う値が出て、要求の組み立てを突き合わせられない。
String codeChallengeOf(String verifier) =>
    base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

/// 認可 URL を組む。**scope は appdata の一つだけである。**
///
/// `access_type=offline` と `prompt=consent` を必ず付ける。**refresh token を返させるため**で、
/// 付け忘れると、二度目以降の認可で refresh token が返らず、その端末は access token が切れた
/// 時点で再ログインを要求し続ける。
Uri authorizationUrl(
  DesktopClient client, {
  required String redirectUri,
  required String verifier,
  required String state,
}) =>
    Uri.parse(client.authUri).replace(queryParameters: {
      'access_type': 'offline',
      'client_id': client.clientId,
      'code_challenge': codeChallengeOf(verifier),
      'code_challenge_method': 'S256',
      'prompt': 'consent',
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': appDataScope,
      'state': state,
    });

/// コールバックを検査して認可コードを返す。
///
/// **`state` の不一致を通さない。** 通すと、他所で始まった認可の結果を取り込むことになる。
/// 例外の文言に `code` を入れない。
String authorizationCodeFrom(Map<String, String> query, String expectedState) {
  final error = query['error'];
  if (error != null && error.isNotEmpty) {
    throw TransportAuthError('Google が認可を拒否しました: $error');
  }
  final code = query['code'];
  if (code == null || code.isEmpty) {
    throw TransportAuthError('認可コードを受け取れませんでした。');
  }
  if (query['state'] != expectedState) {
    throw TransportAuthError('認可コールバックの state が一致しません。やり直してください。');
  }
  return code;
}

/// token endpoint を叩く側。
class GoogleOAuth {
  final DesktopClient client;
  final http.Client httpClient;

  GoogleOAuth(this.client, {http.Client? httpClient})
      : httpClient = httpClient ?? http.Client();

  void close() => httpClient.close();

  Future<Token> exchangeCode({
    required String code,
    required String verifier,
    required String redirectUri,
    required String now,
  }) async {
    final payload = await _postForm({
      'client_id': client.clientId,
      'client_secret': client.clientSecret,
      'code': code,
      'code_verifier': verifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
    }, label: '認可コードの交換');

    final token = _tokenFrom(payload, now: now, fallback: null);
    if (token.refreshToken == null) {
      // **refresh token が無い資格情報を保存しない。** 保存すると、access token が切れた時点で
      // 回復手段の無い端末ができ、次の同期まで気づけない。
      throw TransportAuthError(
        'Google が refresh token を返しませんでした。アカウントの「サードパーティ アプリとの'
        '連携」からアクセスを取り消してやり直してください。',
      );
    }
    return token;
  }

  Future<Token> refresh(Token token, {required String now}) async {
    final refreshToken = token.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw TransportAuthError('refresh token がありません。認可し直してください。');
    }
    final payload = await _postForm({
      'client_id': client.clientId,
      'client_secret': client.clientSecret,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    }, label: 'アクセストークンの更新');
    return _tokenFrom(payload, now: now, fallback: token);
  }

  /// **応答の拒否と到達不能を分ける。**
  ///
  /// 拒否（4xx）は認可の問題として [TransportAuthError] にするが、到達できない場合は
  /// `transport-io` にする。**通信が落ちているだけの状態を認可喪失として記録すると、
  /// `blocked_auth` が「送れなかった理由」を取り違える。**
  Future<Map<String, Object?>> _postForm(Map<String, String> form,
      {required String label}) async {
    final http.Response response;
    try {
      response = await httpClient.post(
        Uri.parse(client.tokenUri),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: form,
      );
    } on Object catch (exc) {
      throw SyncDataError('$labelの宛先に到達できません（${exc.runtimeType}）。',
          code: 'transport-io');
    }

    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 400) {
      throw TransportAuthError(
          '$labelを拒否されました（HTTP ${response.statusCode}: ${_errorId(body)}）');
    }

    final Object? payload;
    try {
      payload = jsonDecode(body);
    } on FormatException {
      throw SyncDataError('$labelの応答を読めません。', code: 'transport-io');
    }
    if (payload is! Map<String, Object?> || payload['access_token'] is! String) {
      throw TransportAuthError('$labelの応答にアクセストークンがありません。');
    }
    return payload;
  }

  Token _tokenFrom(Map<String, Object?> payload,
      {required String now, required Token? fallback}) {
    final expiresIn = payload['expires_in'];
    final scope = payload['scope'];
    return Token(
      accessToken: payload['access_token'] as String,
      // **refresh の応答は refresh token を返さない。** 前のものを引き継がないと、1回
      // 更新しただけでその端末は回復手段を失う。
      refreshToken:
          (payload['refresh_token'] as String?) ?? fallback?.refreshToken,
      expiryUtc: expiresIn is int ? shiftSeconds(now, expiresIn) : null,
      scopes: scope is String && scope.isNotEmpty
          ? scope.split(' ')
          : const [appDataScope],
    );
  }
}

/// 応答から `error` の識別子だけを取る。
///
/// **`error_description` は写さない。** 入力を含みうるうえ、診断に要るのは種別だけである。
/// `invalid_grant` かどうかが分かれば、再ログイン以外に回復手段が無いことまで決まる。
String _errorId(String body) {
  final Object? payload;
  try {
    payload = jsonDecode(body);
  } on FormatException {
    return 'unknown';
  }
  if (payload is! Map) return 'unknown';
  final value = payload['error'];
  return value is String && value.isNotEmpty ? value : 'unknown';
}
