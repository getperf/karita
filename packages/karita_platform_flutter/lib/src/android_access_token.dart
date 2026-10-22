/// Android の [AccessTokenProvider]。**Play services が grant を持ち、端末は持たない。**
///
/// Windows は loopback + PKCE で自分で refresh token を握るが、Android は握れない — カスタム
/// URI スキームは使えず、Android クライアント型では loopback リダイレクトが廃れており、
/// Authorization API が返すのは短命の access token だけである。refresh token を得るには
/// backend が要り、この製品は持たない。
///
/// **だから共有する抽象は「必要時に access token を取得すること」1点しかない。**
/// 保存の場所も、refresh token の有無すら違う。
///
/// 移送元: `../drive-appdata-pkce-probe-flutter/lib/src/oauth/android_authorization.dart`。
library;

import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';

import 'authorization_client.dart';

/// 保存された grant から access token を出す。**画面を出さない。**
///
/// [authorize] だけが画面を出す。同期の経路（[accessToken]）からは決して呼ばない — 同期の途中で
/// アカウント選択が出ると、背景同期が無言で止まったまま利用者を待つことになる。Windows で
/// 「同期はブラウザを開かない」としたのと同じ線である。
class AndroidAccessTokenProvider implements AccessTokenProvider {
  final AndroidAuthorizationClient client;

  /// 直近に配った access token。[clearToken] に渡すためだけに持つ。
  String? _lastAccessToken;

  /// 進行中の [authorize]。**画面が閉じるまで、無音の経路を走らせない。**
  ///
  /// iOS の Google Sign-In SDK は進行中の操作を1つしか持たない。アカウント選択の画面を
  /// 出している間に無音の復元が来ると、SDK の完了先がそちらへ置き換わり、**画面の側の完了が
  /// 呼ばれなくなる** — ［サインイン］が進行中のまま戻らない（2026-10-22、iOS シミュレーターで
  /// 実測）。周期の同期や状態の再読込は、ここで待たせる。
  Future<void>? _authorizing;

  /// [_authorizing] が終わるまで待つ。**失敗は [authorize] の呼び手が受ける**ので、ここでは
  /// 握るだけにする。
  Future<void> _settled() async {
    final pending = _authorizing;
    if (pending == null) return;
    try {
      await pending;
    } on Object {
      // 上の理由で握る。
    }
  }

  AndroidAccessTokenProvider(this.client);

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    await client.initialize();
    await _settled();

    // **[forceRefresh] の意味が Windows と反転する。** Windows は refresh token で取り直すが、
    // Android に取り直す口は無い。あるのは「いま持っているものを捨てる」だけで、捨てた後に
    // 無音で取れなければ**それが認可を失ったということである。**
    if (forceRefresh) {
      final stale = _lastAccessToken;
      _lastAccessToken = null;
      if (stale != null) await client.clearToken(stale);
    }

    // **無音の経路だけを通る。** 取れなければここで投げる。`authorizeScopes` へ落とさない —
    // 落とすと、401 を受けた送信の途中でアカウント選択が出る。
    final token = await client.tokenForScopes(const <String>[appDataScope]);
    if (token == null) {
      // [AccessTokenProvider.accessToken] の契約どおり、空文字や null を返さない。
      // これが outbox の行を `blocked_auth` へ落とす根拠になる。
      throw TransportAuthError('サインインしていません。認可してください。');
    }
    _lastAccessToken = token;
    return token;
  }

  /// **ここだけが画面を出す。** 利用者が明示した操作（harness の [サインイン]）から呼ぶ。
  ///
  /// 無音で取れるならそれを使う。**初回の同意を二度求めない。**
  ///
  /// **重ねて押されても画面は1つである。** 進行中なら同じ完了を返す。
  Future<void> authorize() =>
      _authorizing ??= _authorize().whenComplete(() => _authorizing = null);

  Future<void> _authorize() async {
    await client.initialize();
    final silent = await client.tokenForScopes(const <String>[appDataScope]);
    _lastAccessToken =
        silent ?? await client.requestScopes(const <String>[appDataScope]);
  }

  /// 端末に残っている access token を捨てる。
  ///
  /// **Google の grant は取り消さない。** Android に「ローカルの認可を消す」は無く、消せるのは
  /// 配られた token だけである。次の [accessToken] は無音で取り直せる。
  Future<void> clearLocalState() async {
    final token = _lastAccessToken;
    _lastAccessToken = null;
    if (token == null) return;
    await client.clearToken(token);
  }

  /// 無音で取れるかどうかだけを返す。**値は出さない。**
  ///
  /// harness の状態タブが使う。access token を表示しない — 要るのは「あるか」だけである。
  Future<bool> authorized() async {
    await client.initialize();
    await _settled();
    return await client.tokenForScopes(const <String>[appDataScope]) != null;
  }
}
