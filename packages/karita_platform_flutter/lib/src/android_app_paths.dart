/// Android の既定のデータ領域。
///
/// **アプリのデータを消せば「空の端末」になる。** 実機受入ケース1・2 の「空の端末」はこれで
/// 作れ、初回起動画面に依存しない。
///
/// **口は `karita_platform` の [AppPaths] にあり、ここは実装だけである。** `path_provider` が
/// Flutter プラグインを要るので、Windows の実装と同じ場所に置けない。
///
/// **`home` より下の配置は持たない。** [HomeAppPaths] を継ぎ、`AppLayout` から引く。この端末に
/// 無いもの（トークン・資格情報）だけを落とす。
library;

import 'dart:io';

import 'package:karita_contract/errors.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:path_provider/path_provider.dart';

/// Android の既定パス。
///
/// **[AppPaths] を非同期にしない。** `getApplicationSupportDirectory()` は `Future` を返すが、
/// 口を非同期化すると Windows の実装と全試験に波及する。**先に解決し、解決済みの文字列を持つ**
/// 二段構えにする。
final class AndroidAppPaths extends HomeAppPaths {
  const AndroidAppPaths._(super.home);

  /// 環境から解決する。**これが本番の経路である。**
  ///
  /// [homeEnvVar] は Android の本番では立たない。**検証と切り分けのためだけに見る** — Windows と
  /// 同じ1つの差し替え口に揃えておき、実機で赤が出たときに同じ手が使えるようにする。
  static Future<AndroidAppPaths> resolve({
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final override = env[homeEnvVar];
    if (override != null && override.trim().isNotEmpty) {
      return AndroidAppPaths._(override.trim());
    }
    final dir = await getApplicationSupportDirectory();
    return AndroidAppPaths._(dir.path);
  }

  /// 解決済みの場所から作る。**試験と、既に解決を済ませた合成層のためにある。**
  factory AndroidAppPaths.at(String home) => AndroidAppPaths._(home);

  /// **Android には無い。** 触ったら落とす。
  ///
  /// 端末はトークンを持たない — grant を保持するのは Play services である。ここで「使われない
  /// パス」を返すと、いつか誰かがそこを読み、**空のファイルを「認可が無い」と読み違える**。
  /// `%LOCALAPPDATA%` が無いときに推測で代わりを立てないのと同じ判断である。
  @override
  String get tokenPath => throw SyncDataError(
        'Android はトークンをファイルに持ちません。認可は Play services が保持します。',
        code: 'paths-not-applicable',
      );

  /// **Android には無い。** 触ったら落とす。
  ///
  /// Android の OAuth クライアントにシークレットは無く、Windows の Desktop クライアント JSON を
  /// Android のビルドへ入れないことは確認結果の結論そのものである。
  @override
  String get credentialsPath => throw SyncDataError(
        'Android は Desktop クライアントの資格情報を持ちません。'
        '認可は Play services がパッケージ名と署名証明書から解決します。',
        code: 'paths-not-applicable',
      );
}
