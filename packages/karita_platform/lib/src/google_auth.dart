/// 保存したトークンと、そこから access token を出す [AccessTokenProvider]。
///
/// **同期はブラウザを開かない。** 開くのは `login` の1経路だけである。同期の途中で認可画面が
/// 出ると、背景同期が無言で止まったまま利用者を待つことになる。
///
/// 移送元: book-sync-model の `src/bsync_core/gauth.py`（保存と `token_for`）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:karita_sync/karita_sync.dart';

import 'access_token.dart';
import 'oauth.dart';
import 'token_protection.dart';

/// 読込の結果の種別。**原因を分ける** — 破損・復号不可・I/O 失敗を同じ「無い」として
/// 記録しない（`非公開資料:2026-10-18-windows-token-protection-probe.md`）。
enum TokenLoadState {
  /// ファイルが無い。
  missing,

  /// 保護形式から読めた。
  protected,

  /// 旧版の平文から読み、保護形式へ置き換えた。
  migrated,

  /// 旧版の平文から読めたが、置き換えに失敗した。**認可はそのまま使う。** 次の読込で
  /// やり直す。
  legacyPlaintext,

  /// 壊れている、知らない版、または開けない（別ユーザー・別 PC・改変）。再サインインで
  /// 置き換わる。**ファイルは消さない。**
  unreadable,

  /// 読めなかった（権限・共有違反など）。一時的なものとして扱う。
  ioFailed,
}

/// [TokenStore.read] の結果。**値を出さない** — 種別と、秘密を含まない補足だけを持つ。
class TokenLoad {
  final Token? token;
  final TokenLoadState state;

  /// 秘密を含まない補足（例外の種別、Win32 の番号）。
  final String? detail;

  const TokenLoad(this.state, {this.token, this.detail});
}

/// トークンをファイルに置く。**Windows ではユーザー単位の DPAPI で保護して置く。**
///
/// **台帳とは別のファイルにする。** 資格情報は端末固有で、`.blib` に混ぜて復元先へ持ち越す
/// ものではない。
///
/// 形式は `KRTK` 4 バイト + 版 1 バイト + 保護済み blob。**パスは旧版と同じ `token.json`
/// のまま中身の形式を変える** — 名前を変えると、旧版との併用で2つのファイルが並び、どちらが
/// 正か分からなくなる。識別子の付いたファイルは平文として読み直さない。識別子が無いものだけを
/// 旧版の平文 JSON として読み、読めたらその場で保護形式へ置き換える。
///
/// **保護に失敗しても平文へ戻さない。** 保存は例外になる。
///
/// 守れる範囲は「同じ Windows ユーザー」までである（[TokenProtector]）。
class TokenStore {
  final String path;
  final TokenProtector protector;

  /// [protector] を省くと端末の既定（Windows は DPAPI）を使う。
  TokenStore(this.path, {TokenProtector? protector})
    : protector = protector ?? TokenProtector.platform();

  static const List<int> _magic = [0x4B, 0x52, 0x54, 0x4B]; // "KRTK"
  static const int _formatVersion = 1;

  /// 旧版が使っていた固定名の一時ファイル。**平文を含みうる**ので、見つけたら消す。
  String get _legacyStagedPath => '$path.part';

  /// 一時ファイル。**プロセス番号を入れる** — 固定名は同時保存で互いを壊した（probe で実測）。
  String get _stagedPath => '$path.$pid.part';

  Token? load() => read().token;

  /// 読む。**旧版の平文なら、ここで保護形式へ置き換える。**
  ///
  /// 読めないトークンは「無い」とする（[TokenLoad.token] が null）。**落とさない** —
  /// 認可し直せば回復する状態であり、起動そのものを止める理由にならない。
  TokenLoad read() {
    final file = File(path);
    final Uint8List bytes;
    try {
      if (!file.existsSync()) return const TokenLoad(TokenLoadState.missing);
      bytes = file.readAsBytesSync();
    } on FileSystemException catch (e) {
      return TokenLoad(
        TokenLoadState.ioFailed,
        detail: 'os=${e.osError?.errorCode}',
      );
    }

    if (_hasMagic(bytes)) {
      final (token, detail) = _openProtected(bytes);
      return token == null
          ? TokenLoad(TokenLoadState.unreadable, detail: detail)
          : TokenLoad(TokenLoadState.protected, token: token);
    }

    final legacy = _decode(bytes);
    if (legacy == null) {
      return const TokenLoad(TokenLoadState.unreadable, detail: 'not-a-token');
    }
    // **置き換えに失敗しても認可は失わない。** 平文は元のまま残り、次の読込でやり直す。
    try {
      save(legacy);
      return TokenLoad(TokenLoadState.migrated, token: legacy);
    } on Exception catch (e) {
      return TokenLoad(
        TokenLoadState.legacyPlaintext,
        token: legacy,
        detail: '${e.runtimeType}',
      );
    }
  }

  /// 保護して一時ファイルへ書き、読み戻して開けることを確かめてから置き換える。
  ///
  /// 途中で落ちた書き込みが半端なトークンを残すと、次の起動は「読めないから無い」と判断して
  /// 再ログインを求める。**保存の失敗で認可を失わない。** 置き換えは確認の後にしか起きないので、
  /// 平文からの移行の途中で落ちても元のファイルは残る。
  ///
  /// 失敗すると [TokenProtectionException] か [FileSystemException] を投げる。
  void save(Token token) {
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(token.toJson())));
    final Uint8List sealed;
    try {
      sealed = protector.protect(plain);
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
    final bytes = Uint8List(_magic.length + 1 + sealed.length)
      ..setAll(0, _magic)
      ..[_magic.length] = _formatVersion
      ..setAll(_magic.length + 1, sealed);

    final file = File(path);
    file.parent.createSync(recursive: true);
    final staged = File(_stagedPath);
    try {
      staged.writeAsBytesSync(bytes, flush: true);
      final (check, _) = _openProtected(staged.readAsBytesSync());
      if (check == null) {
        throw const TokenProtectionException('verify');
      }
      staged.renameSync(path);
    } catch (_) {
      _deleteQuietly(staged);
      rethrow;
    }
    _sweepStaged();
  }

  bool clear() {
    final file = File(path);
    final existed = file.existsSync();
    if (existed) file.deleteSync();
    _sweepStaged();
    return existed;
  }

  (Token?, String?) _openProtected(Uint8List bytes) {
    if (bytes.length <= _magic.length + 1) return (null, 'truncated');
    final version = bytes[_magic.length];
    if (version != _formatVersion) return (null, 'unknown-version:$version');
    final Uint8List plain;
    try {
      plain = protector.unprotect(
        Uint8List.sublistView(bytes, _magic.length + 1),
      );
    } on TokenProtectionException catch (e) {
      return (
        null,
        e.win32Error == null ? e.operation : 'win32=${e.win32Error}',
      );
    }
    try {
      final token = _decode(plain);
      return token == null ? (null, 'not-a-token') : (token, null);
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  /// 旧版の固定名と、落ちたプロセスが残した一時ファイルを消す。
  ///
  /// **他のプロセスが書いている最中のものは消さない。** 自分のもの以外は、しばらく前の
  /// ものだけを消す。
  void _sweepStaged() {
    _deleteQuietly(File(_legacyStagedPath));
    final dir = File(path).parent;
    final prefix = '${File(path).uri.pathSegments.last}.';
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    try {
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (!name.startsWith(prefix) || !name.endsWith('.part')) continue;
        if (entry.path == _stagedPath ||
            entry.statSync().modified.isBefore(cutoff)) {
          _deleteQuietly(entry);
        }
      }
    } on FileSystemException {
      // 掃除は次の保存でやり直せる。
    }
  }
}

bool _hasMagic(Uint8List bytes) {
  if (bytes.length < TokenStore._magic.length) return false;
  for (var i = 0; i < TokenStore._magic.length; i++) {
    if (bytes[i] != TokenStore._magic[i]) return false;
  }
  return true;
}

Token? _decode(List<int> bytes) {
  try {
    return Token.fromJson(jsonDecode(utf8.decode(bytes)));
  } on FormatException {
    return null;
  } on TypeError {
    // `refresh_token` などの型が違う。
    return null;
  }
}

void _deleteQuietly(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // 消せなくても保護済みのバイト列か旧版の残りである。次の保存でやり直す。
  }
}

/// 保存したトークンから access token を出す。**ブラウザを開かない。**
///
/// [AccessTokenProvider.accessToken] の契約どおり、取れなければ [TransportAuthError] を投げる。
/// 空文字を返さない — 呼び出し側が「認可が無い」と「トークンが空だった」を区別できないまま
/// 要求を組むことになる。
class GoogleAccessTokenProvider implements AccessTokenProvider {
  final TokenStore store;
  final GoogleOAuth oauth;

  /// いまの時刻。**引数で受ける。** ここが実時計を直に読むと、試験が期限の境目を作れない。
  final String Function() now;

  Token? _cached;

  GoogleAccessTokenProvider({
    required this.store,
    required this.oauth,
    required this.now,
  });

  /// メモリのキャッシュだけを落とす。**呼び出し側が [store] のファイルも消す。**
  ///
  /// [store.clear] だけではここが直らない — [_cached] はファイルを読み直さずに答える
  /// ためのものなので、サインアウト後も古いトークンを [status] が「ある」と言い続ける。
  void forget() {
    _cached = null;
  }

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    final token = _cached ??= store.load();
    if (token == null) {
      throw TransportAuthError('サインインしていません。認可してください。');
    }

    final at = now();
    if (!forceRefresh && !token.expired(at)) return token.accessToken;

    // **期限切れも、サーバに拒まれた後の取り直しも、同じ1本の経路を通る。** 分けると、
    // 片方だけが `refresh token を引き継ぐ` を忘れる。
    final refreshed = await oauth.refresh(token, now: at);
    _cached = refreshed;
    // **保存に失敗しても同期を止めない。** 失うのは新しい access token の永続化だけで、
    // refresh token は保存済みのものが生きている。次の起動はそれで取り直す。平文へは戻さない。
    try {
      store.save(refreshed);
    } on TokenProtectionException {
      // 同上
    } on FileSystemException {
      // 同上
    }
    return refreshed.accessToken;
  }

  /// 保存されているものの有無と期限だけを返す。**値は出さない。**
  ///
  /// `auth status` が使う。access token も refresh token も表示しない — 診断に要るのは
  /// 「あるか」と「いつまでか」だけである。
  ///
  /// [state] は読込の種別である。**無いことと、あるが開けないことを分ける** — 後者は
  /// 「保存済みの認可を開けない」として再サインインへ案内する。
  ({bool present, String? expiryUtc, bool expired, TokenLoadState state})
  status() {
    final cached = _cached;
    final load = cached == null
        ? store.read()
        : TokenLoad(TokenLoadState.protected, token: cached);
    final token = load.token;
    if (token == null) {
      return (
        present: false,
        expiryUtc: null,
        expired: false,
        state: load.state,
      );
    }
    return (
      present: true,
      expiryUtc: token.expiryUtc,
      expired: token.expired(now()),
      state: load.state,
    );
  }
}

/// loopback + PKCE でブラウザから認可を受ける。**ここだけがブラウザを開く。**
///
/// **ポートを固定しない。** 0 で bind して OS に選ばせる。固定すると、別のものが同じポートを
/// 使っている端末で認可そのものが始められない。Google の Desktop クライアントは
/// `http://127.0.0.1` の任意ポートを受ける。
class LoopbackLogin {
  final GoogleOAuth oauth;
  final TokenStore store;

  /// ブラウザを開く手。**差し替えられる形にする** — 試験でブラウザを起動しないためと、
  /// 端末によっては開けないので URL を表示する経路が要るためである。
  final Future<void> Function(Uri url) openBrowser;

  final String Function() now;
  final String Function() randomToken;

  LoopbackLogin({
    required this.oauth,
    required this.store,
    required this.openBrowser,
    required this.now,
    required this.randomToken,
  });

  Future<Token> login() async {
    final verifier = randomToken();
    final state = randomToken();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/oauth2callback';

    try {
      // **開く前に受け口を張る。** ブラウザは開いた直後に叩きうる。順序を逆にすると、
      // その1回を取りこぼす経路が残る。
      final pending = server.first;
      await openBrowser(
        authorizationUrl(
          oauth.client,
          redirectUri: redirectUri,
          verifier: verifier,
          state: state,
        ),
      );

      final request = await pending;
      final query = request.uri.queryParameters;

      // **先に画面を閉じる。** 交換で落ちてもブラウザは応答を受け取っている必要がある —
      // 待たせたまま失敗すると、利用者はブラウザの読み込み中の画面だけを見ることになる。
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body>認可を受け取りました。この画面は閉じてかまいません。'
          '</body></html>',
        );
      await request.response.close();

      final code = authorizationCodeFrom(query, state);
      final token = await oauth.exchangeCode(
        code: code,
        verifier: verifier,
        redirectUri: redirectUri,
        now: now(),
      );
      store.save(token);
      return token;
    } finally {
      await server.close(force: true);
    }
  }
}
