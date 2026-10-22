/// 認可の入口と、端末ごとの組み立て。**端末を足すときに触るのはここである。**
library;

import 'dart:io';

import 'package:karita_platform/karita_platform.dart';
import 'package:karita_platform_flutter/karita_platform_flutter.dart';

import '../demo.dart';
import 'clock.dart';
import 'ids.dart';

/// 認可の入口。**Windows と Android で形が違うところを、ここだけに閉じる。**
///
/// 同期の経路が使うのは [tokens] だけである。[signIn] は利用者が明示した操作からしか
/// 呼ばない — Windows はブラウザを開き、Android はアカウント選択を出す。
class Authorization {
  final AccessTokenProvider tokens;
  final Future<void> Function() signIn;
  final Future<void> Function() signOut;

  /// 接続を持っているかを**軽く**読む口。**画面を出さない。**
  ///
  /// `EnvironmentDoctor.check()` でも読めるが、あちらは全表走査（`runDoctor()`）の一部で
  /// あり、［アカウント］行のために毎回走らせるものではない
  /// （`非公開資料:production-wiring-auth-backup-sync.md`「結合の穴」③）。
  ///
  /// **`Future` なのは Android の都合である。** Windows は保存したトークンの有無を同期に
  /// 読めるが、Android は Play services へ無音で訊くしかない。**速い側に合わせて型を
  /// 分けない** — 分けると読み手（合成層）が端末を知ることになる。
  ///
  /// **`blocked_auth` とは別のことを見ている。** ここが見るのは「そもそも接続があるか」で、
  /// 認可を失って止まった outbox は7状態が持つ。3状態はその2つから組む（[Composition.authStatus]）。
  final Future<bool> Function() authorized;

  /// 何で認可しているか。**enum ではなく素性の識別子**を出す。
  final String kind;

  /// 環境の自己診断。**ここで一緒に作る** — 具象のトークン提供者を要るのはこの分岐だけで、
  /// 外へ出すと合成層が Windows と Android の型を両方知ることになる。
  final EnvironmentDoctor doctor;

  const Authorization({
    required this.tokens,
    required this.signIn,
    required this.signOut,
    required this.authorized,
    required this.kind,
    required this.doctor,
  });
}

Authorization androidAuth(AppPaths paths) => _signInSdkAuth(
  paths,
  kind: 'play-services-authorization-api',
  signOut: (provider) => provider.clearLocalState,
);

/// iOS の認可。**Android と同じ口に乗る。** grant を持つのは Google Sign-In SDK（Keychain）で、
/// 端末のファイルはトークンを持たない。`google_sign_in` の Authorization API が両方を包む。
///
/// クライアント ID は `Info.plist` の `GIDClientID` から SDK が読む。**ここでは渡さない。**
///
/// **［サインアウト］だけが Android と違う。** SDK が Keychain に持つサインインを消せるので、
/// Windows と同じ「この端末の接続の解除」になる（Android は消しても無音で取り直される）。
Authorization iosAuth(AppPaths paths) => _signInSdkAuth(
  paths,
  kind: 'google-sign-in-ios',
  signOut: (provider) => provider.signOut,
);

Authorization _signInSdkAuth(
  AppPaths paths, {
  required String kind,
  required Future<void> Function() Function(AndroidAccessTokenProvider)
  signOut,
}) {
  final provider = AndroidAccessTokenProvider(
    PlayServicesAuthorizationClient(),
  );
  return Authorization(
    tokens: provider,
    signIn: provider.authorize,
    signOut: signOut(provider),
    // **無音で取れるかを訊く。** 画面は出さない（`AndroidEnvironmentDoctor` と同じ口）。
    authorized: provider.authorized,
    kind: kind,
    doctor: AndroidEnvironmentDoctor(paths: paths, tokens: provider),
  );
}

Authorization windowsAuth(AppPaths paths) {
  final oauth = GoogleOAuth(
    loadDesktopClient(resolveDesktopCredentialsPath(paths.credentialsPath)),
  );
  final store = TokenStore(paths.tokenPath);
  final provider = GoogleAccessTokenProvider(
    store: store,
    oauth: oauth,
    now: nowUtc,
  );
  return Authorization(
    tokens: provider,
    signIn: () async {
      // **ここだけがブラウザを開く。** 同期の経路からは決して呼ばない。
      final login = LoopbackLogin(
        oauth: oauth,
        store: store,
        now: nowUtc,
        randomToken: randomToken,
        openBrowser: openSystemBrowser,
      );
      await login.login();
    },
    signOut: () async {
      store.clear();
      // **`provider` のメモリキャッシュも落とす。** ファイルを消すだけでは、直後の
      // `authorized()` が古いトークンを覚えたままの `provider` に答えさせてしまい、
      // ［アカウント］行が「サインイン済み」のままになる。
      provider.forget();
    },
    // **保存したトークンの有無だけを見る。** 期限は見ない（`WindowsEnvironmentDoctor` と
    // 同じ理由 — access token の寿命は1時間程度で、アイドルを跨げば必ず切れる。切れている
    // ことは異常ではなく時計であり、refresh が回復させる）。
    authorized: () async => provider.status().present,
    kind: 'loopback-pkce',
    doctor: WindowsEnvironmentDoctor(paths: paths, tokens: provider),
  );
}

/// デモの認可。**操作入口は `gate` が先に止める。**
///
/// 資格情報を読まないので、Desktop クライアントを置いていない端末でもデモは立つ。
Authorization demoAuth(AppPaths paths) => Authorization(
  tokens: const DemoAccessTokenProvider(),
  signIn: () async => throw UnsupportedError('デモモードでは認証しません。'),
  signOut: () async => throw UnsupportedError('デモモードでは認証しません。'),
  // **接続は持たない。** 画面には `available: false` として出るので、この値は
  // 「サインインしていない」以上の意味を持たない。
  authorized: () async => false,
  kind: 'demo',
  doctor: DemoEnvironmentDoctor(paths),
);

/// ブラウザーを開く。**端末を足すときに触る4箇所の1つである**（`compose` の `_shareInbox` と同じ形）。
///
/// **Windows は `rundll32` のままにする。** 認可（`LoopbackLogin`）が実物で通っている経路で
/// あり、図書館サイトを開くために置き換えない。**Android には実装が1つも無かった**ので、
/// そちらだけ `url_launcher` を入れた（2026-09-18）。Android の認可は Play services なので、
/// この分岐の読み手は**図書館サイトを開く操作だけ**である。
Future<void> openSystemBrowser(Uri url) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await openInExternalBrowser(url);
    return;
  }
  // 引数を1つとして渡せる経路を使う。`start` はクエリの `&` で切れる。
  await Process.start('rundll32.exe', ['url.dll,FileProtocolHandler', '$url']);
}
