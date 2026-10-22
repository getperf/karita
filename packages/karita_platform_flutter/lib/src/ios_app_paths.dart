/// iOS の既定のデータ領域。
///
/// **アプリを削除すれば「空の端末」になる。** Android の「アプリのデータを消す」に当たる。
///
/// **`AndroidAppPaths` と同じ二段構えである。** `getApplicationSupportDirectory()` を先に解決し、
/// 解決済みの文字列を持つ。iOS では `Library/Application Support` を指す。
///
/// **`home` より下の配置は持たない。** [HomeAppPaths] を継ぎ、`AppLayout` から引く。この端末に
/// 無いもの（トークン・資格情報）だけを落とす。
library;

import 'dart:io';

import 'package:karita_contract/errors.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:path_provider/path_provider.dart';

/// iOS の既定パス。
final class IosAppPaths extends HomeAppPaths {
  const IosAppPaths._(super.home);

  /// 環境から解決する。**これが本番の経路である。**
  ///
  /// [homeEnvVar] は iOS の本番では立たない。Android と同じく**検証と切り分けのためだけに見る。**
  static Future<IosAppPaths> resolve({
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final override = env[homeEnvVar];
    if (override != null && override.trim().isNotEmpty) {
      return IosAppPaths._(override.trim());
    }
    final dir = await getApplicationSupportDirectory();
    return IosAppPaths._(dir.path);
  }

  /// 解決済みの場所から作る。**試験と、既に解決を済ませた合成層のためにある。**
  factory IosAppPaths.at(String home) => IosAppPaths._(home);

  /// **iOS には無い。** 触ったら落とす。
  ///
  /// 端末のファイルはトークンを持たない — grant を保持するのは Google Sign-In SDK（Keychain）
  /// である。理由は Android と同じで、使われないパスを返すと空を「認可が無い」と読み違える。
  @override
  String get tokenPath => throw SyncDataError(
        'iOS はトークンをファイルに持ちません。認可は Google Sign-In SDK が保持します。',
        code: 'paths-not-applicable',
      );

  /// **iOS には無い。** 触ったら落とす。
  ///
  /// iOS の OAuth クライアントにシークレットは無い。クライアント ID はビルド設定
  /// （`Info.plist` の `GIDClientID`）が持ち、Desktop クライアント JSON を入れない。
  @override
  String get credentialsPath => throw SyncDataError(
        'iOS は Desktop クライアントの資格情報を持ちません。'
        '認可は Google Sign-In SDK が iOS クライアント ID から解決します。',
        code: 'paths-not-applicable',
      );
}
