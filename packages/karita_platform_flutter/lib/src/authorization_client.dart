/// Play services の Authorization API への口と、その実装。
///
/// **口を開けてあるのは試験のためである。** `google_sign_in` の
/// `GoogleSignInAuthorizationClient` は具象クラスで、偽物を作れない。Play services を要る
/// 呼び出しを1枚の口に押し込め、[AndroidAccessTokenProvider] の判断（無音で取る・取れなければ
/// 投げる・取り直しは捨ててから取る）を**実機なしで測れる**ようにする。
///
/// **口は Play services の言葉のままにする。** ここで意味を足すと、実機で確かめたふるまいと
/// 試験が測るものがずれる。判断は [AndroidAccessTokenProvider] が持つ。
///
/// 移送元: `../drive-appdata-pkce-probe-flutter/lib/src/oauth/android_authorization.dart`
/// （2026-08-02 に Pixel 8a で `drive.appdata` の認可・書込み・読戻しを通したもの）。
library;

import 'package:google_sign_in/google_sign_in.dart';

abstract interface class AndroidAuthorizationClient {
  /// **一度きり**。二度目以降は何もしない。
  Future<void> initialize();

  /// **利用者に何も見せずに**取れるものを取る。無ければ `null`。
  Future<String?> tokenForScopes(List<String> scopes);

  /// **アカウント選択と同意の画面を出す。** 呼べるのは利用者が明示した操作の直後だけである。
  Future<String> requestScopes(List<String> scopes);

  /// 端末に残っている access token を捨てる。**Google の grant は取り消さない。**
  Future<void> clearToken(String accessToken);
}

/// `google_sign_in` の Authorization API を [AndroidAuthorizationClient] として見せる。
///
/// **認証（sign-in）を通さない。** `google_sign_in` は「利用者を認証する」と「scope を認可する」を
/// 分けており、認証の側は Credential Manager を通るので **Web** の OAuth クライアント ID を
/// `serverClientId` として要求する。利用者の識別を使わない以上、それを登録する理由が無い。
///
/// `GoogleSignIn.instance.authorizationClient` を（`account.authorizationClient` ではなく）
/// 取ると Authorization API を直に使う。**null の利用者を受け、アカウントの選択を認可の中で
/// 尋ね、Android の OAuth クライアントだけで足りる** — Play services がパッケージ名と署名証明書
/// から解決するので、**端末にクライアント ID もシークレットも置かない。**
class PlayServicesAuthorizationClient implements AndroidAuthorizationClient {
  final GoogleSignIn _signIn;

  /// **`initialize()` は一度きりで、二度呼べない。** package の側で守る — 合成層が2つ作っても
  /// 一度しか通らないよう、状態は package のこの1箇所に持つ。
  static bool _initialized = false;

  PlayServicesAuthorizationClient({GoogleSignIn? signIn})
      : _signIn = signIn ?? GoogleSignIn.instance;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _signIn.initialize();
    _initialized = true;
  }

  @override
  Future<String?> tokenForScopes(List<String> scopes) async {
    final authorization =
        await _signIn.authorizationClient.authorizationForScopes(scopes);
    return authorization?.accessToken;
  }

  @override
  Future<String> requestScopes(List<String> scopes) async {
    final authorization =
        await _signIn.authorizationClient.authorizeScopes(scopes);
    return authorization.accessToken;
  }

  @override
  Future<void> clearToken(String accessToken) =>
      _signIn.authorizationClient.clearAuthorizationToken(
        accessToken: accessToken,
      );
}
