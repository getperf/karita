/// ③ プラットフォーム適配の **Flutter 分**。`karita_platform` が持てないものだけが入る。
///
/// **③ を2つに割るのは、P2 の受入を Dart VM で回すためである。** Android の認可（Play services）
/// と既定パスの解決（`path_provider`）はいずれも Flutter プラグインを要る。1つのパッケージに
/// 混ぜると、`karita_platform` を使う試験が Dart VM でプラグインを解決できずに落ちる。
///
/// **Flutter に依存するのはこの package と harness の2つだけ**である。`karita_contract`・
/// `karita_sync`・`karita_domain`・`karita_platform` はいずれも純 Dart のままで、conformance
/// runner と単体試験は Dart VM で回り続ける。
///
/// 持つのは3つ。
///
/// - **Android の認可** — Play services の Authorization API で `drive.appdata` を取る。
///   refresh token は無い。[AndroidAccessTokenProvider]
/// - **Android の既定パス** — `getApplicationSupportDirectory()`。[AndroidAppPaths]
/// - **Android のネイティブ SQLite** — `sqlite3_flutter_libs`。依存として運ぶだけで、
///   ここに書くコードは無い。Android には dlopen できるシステム sqlite が無く、Windows の
///   `winsqlite3.dll` に当たるものが無い
///
/// **トークンの保護は持たない。** 端末にトークンが無いためである。Windows の `token.json` の
/// 保護は `karita_platform` の `TokenStore`（DPAPI）が持つ。
///
/// **合成はここでしない。** どの実装を使うかを決めるのは harness と本番 app である。
library;

export 'src/android_access_token.dart';
export 'src/android_app_paths.dart';
export 'src/android_environment_doctor.dart';
export 'src/app_links_share_inbox.dart';
export 'src/authorization_client.dart';
export 'src/channel_share_inbox.dart';
export 'src/external_browser.dart';

export 'src/windows_export_delivery.dart';
export 'src/android_export_delivery.dart';
