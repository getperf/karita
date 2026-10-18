/// 既定のデータ領域を決める口と、Windows の実装。
///
/// **本番に profile は無い。** 1端末1台帳である。`windows-a` / `android-b` は検証装置の概念で
/// あって製品のものではない。複数を並べたいときだけ `KARITA_HOME` で丸ごと差し替える。
///
/// **既定を解決する経路が本番の経路である。** 差し替えを常用すると、既定の解決が一度も通らない
/// まま製品に出る。だから差し替えは環境変数の1つだけにし、引数では受けない。
///
/// **口を純 Dart に置き、Windows の実装をここに置く。** Android の `path_provider` は Flutter
/// プラグインを要るので `karita_platform_flutter` が持つ。`BackupStorePort` を定義側と実装側に
/// 割ったのと同じ形である。
///
/// **`home` より下の相対配置は [AppLayout] が1箇所で持つ。** 端末ごとの実装が決めるのは `home`
/// だけである。その下の名前を実装ごとに書くと、端末を足すたびに写しが増える
/// （`非公開資料:settings-and-parameters.md`）。
///
/// 移送元: book-sync-model の `src/contracts/paths.py`。
library;

import 'dart:io';

import 'package:karita_contract/errors.dart';

/// 丸ごと差し替える環境変数。**検証と切り分けのためだけにある。**
const String homeEnvVar = 'KARITA_HOME';

/// Windows の既定の置き場。
///
/// **`%LOCALAPPDATA%\blib` と衝突させない。** 同じ機械で参照実装（`bsync`）と本実装を並べ、
/// **ローカルは別・Drive は同じ**という形で言語間の往復を測る。同じ場所を使うと、その検証が
/// 「同じ台帳を2つの実装が触る」になってしまう。
const String windowsDirName = 'Karita';

/// `home` より下の配置。**これが唯一の写しである。**
///
/// 表の正本は `非公開資料:settings-and-parameters.md` の「管理対象ファイルの定義」で、
/// ここはその1行1行に対応する。**端末を足すときに決めるのは `home` の1行だけ**にするために
/// ある。
///
/// **すべてのパスが `home` から決まる。** 個別の絶対パスを持つ口を作らない — 作った時点で
/// `KARITA_HOME` の差し替えがその1つだけ届かなくなる。
abstract final class AppLayout {
  /// 台帳。
  static const String db = 'library.db';

  /// 保存したトークン。**台帳とは別ファイルである。**
  static const String token = 'token.json';

  /// 端末設定と gateway 設定を置く場所。
  static const String configDirName = 'config';

  /// 端末設定。**ログより先に読む**（水準と書式がここにあるため）。
  static const String deviceConfig = 'device.json';

  /// 資格情報を置く場所。**用途別の固定名で持つ。**
  static const String credentialsDirName = 'credentials';

  /// Desktop クライアントの資格情報。**手で置くものである。**
  static const String desktopClient = 'karita-core-desktop.json';

  /// ログを置く場所。
  static const String logDirName = 'logs';

  /// ログ本体。**1本である。**
  ///
  /// **拡張子は書式に依らず `.log` である。** 書式は実行時に決まるので、名前に書式を書くと
  /// `jsonl` へ切り替えた端末でファイル名と中身がずれる
  /// （`非公開資料:logging-and-diagnostics.md`）。
  static const String logFile = 'karita.log';

  /// 区切りは端末のものを使う。
  static String under(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';
}

abstract interface class AppPaths {
  /// この端末の台帳・設定・資格情報を置く場所。
  String get home;

  /// 台帳そのもの。
  String get dbPath;

  /// 保存したトークン。**台帳とは別のファイルにする** — バックアップの `.blib` に混ぜないため
  /// で、資格情報は端末固有であって復元先へ持ち越すものではない。
  String get tokenPath;

  /// Desktop クライアントの資格情報。**手で置くものである。**
  ///
  /// client secret を持つので Git に入れず、生成もされない。無ければ認可を始められない。
  String get credentialsPath;

  /// 端末設定を置く場所。**ファイル名は [AppLayout.deviceConfig] が持つ。**
  ///
  /// 返すのはディレクトリである — 同じ場所へ gateway 設定も来るので、読み手ごとにファイル名が
  /// 違う。
  String get configDir;

  /// ログを置く場所。**ファイル名は [AppLayout.logFile] が持つ。**
  String get logDir;

  /// 無ければ作る。
  void ensure();
}

/// `home` の下の配置を [AppLayout] から引く土台。**端末ごとの実装はこれを継ぐ。**
///
/// 継がずに [AppPaths] を直に implement すると、`'$home/library.db'` の形が実装の数だけ
/// 増える。**実装が決めてよいのは `home` と、その端末に無いものを落とすことだけである。**
abstract base class HomeAppPaths implements AppPaths {
  @override
  final String home;

  const HomeAppPaths(this.home);

  @override
  String get dbPath => AppLayout.under(home, AppLayout.db);

  @override
  String get tokenPath => AppLayout.under(home, AppLayout.token);

  @override
  String get credentialsPath => AppLayout.under(
        AppLayout.under(home, AppLayout.credentialsDirName),
        AppLayout.desktopClient,
      );

  @override
  String get configDir => AppLayout.under(home, AppLayout.configDirName);

  @override
  String get logDir => AppLayout.under(home, AppLayout.logDirName);

  /// `home` と、その下の設定・ログの場所を作る。
  ///
  /// **資格情報の場所は作らない。** 中身を手で置くものなので、空の `credentials\` があると
  /// 「置いたつもり」と「置いていない」が見分けにくくなる。
  @override
  void ensure() {
    Directory(home).createSync(recursive: true);
    Directory(configDir).createSync(recursive: true);
    Directory(logDir).createSync(recursive: true);
  }
}

/// Windows の既定パス。`KARITA_HOME` があればそちらを丸ごと使う。
final class WindowsAppPaths extends HomeAppPaths {
  const WindowsAppPaths._(super.home);

  /// 環境から解決する。**これが本番の経路である。**
  factory WindowsAppPaths.resolve({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final override = env[homeEnvVar];
    if (override != null && override.trim().isNotEmpty) {
      return WindowsAppPaths._(override.trim());
    }
    final localAppData = env['LOCALAPPDATA'];
    if (localAppData == null || localAppData.trim().isEmpty) {
      // **推測で代わりを立てない。** `%USERPROFILE%` などへ落とすと、環境ごとに違う場所へ
      // 台帳ができ、「前の台帳が見つからない」が起こる。
      throw SyncDataError(
        'LOCALAPPDATA が無いためデータ領域を決められません。$homeEnvVar で指定してください。',
        code: 'paths-unresolved',
      );
    }
    return WindowsAppPaths._(
        AppLayout.under(localAppData.trim(), windowsDirName));
  }

  /// 解決済みの場所から作る。**試験と、領域を分けて立てる合成層のためにある。**
  factory WindowsAppPaths.at(String home) => WindowsAppPaths._(home);
}
