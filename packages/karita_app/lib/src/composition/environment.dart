/// データ領域の解決と、種モードの守り。**合成より先に要る** — [boot] がログより先に呼ぶ。
library;

import 'dart:io';

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_platform_flutter/karita_platform_flutter.dart';
import 'package:logging/logging.dart';

import '../demo.dart';

final Logger _log = Logger('karita.app');

/// 既定パスの解決だけを取り出したもの。
///
/// **背面同期がここを使っていた。** 背面の isolate は `compose()` が落ちたときにも記録を残す
/// 必要があり、そのために合成より先に置き場所が要った。背面は落ちた（2026-09-13 の決定。
/// P5a で `workmanager` ごと削除）が、**[boot] がログより先に呼ぶのでこの関数は残る。**
Future<AppPaths> appPaths({AppMode? mode}) async {
  if (Platform.isAndroid) return AndroidAppPaths.resolve();
  final explicit = Platform.environment[homeEnvVar];
  // **種モードには専用の既定がある**（2026-09-23）。`KARITA_HOME` を明示すればそちらが勝つ。
  if ((mode?.seedMode ?? false) &&
      (explicit == null || explicit.trim().isEmpty)) {
    return WindowsAppPaths.at(seedHome());
  }
  return WindowsAppPaths.resolve();
}

/// 種モード（検証モード）の既定のデータ領域。**OS の一時領域の下に、固定の名前で持つ。**
///
/// **毎回リセットされる台帳を、本番と同じ場所に置かない。** かといって人が毎回 `KARITA_HOME`
/// を打つ形にもしない — 守りたいのは「本番の台帳を消さない」ことであって「明示すること」では
/// なく、打ち間違いはむしろ危ない（2026-09-23 の決定）。
///
/// **名前を固定する。** デモの一時台帳（`karita-demo-<乱数>`）と違い、ここは
/// `token.json`・`credentials/`・`device.json`・`logs/` を**跨いで残す**ためである。起動の
/// たびに作り直すのは `library.db` だけで、毎回サインインし直しになる形にはしない。
///
/// **OS の掃除に任せる。** 一時領域なので、しばらく使わなければ消えうる。消えて困るのは
/// 手で置いた `credentials/` だけで、それは1ファイルの複製で戻る。
String seedHome() =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}karita-verify';

/// ガード③：**本番のデータ領域では種を立てない。**
///
/// ①（デスクトップ限定）と ②（release 禁止）は `AppMode.resolve` が見る。ここが見るのは
/// **消してよい台帳か**であり、`KARITA_HOME` で本番の領域を指した場合もここで止まる。
///
/// **「明示したか」では守れない。** 明示したうえで既定の領域を指すことはできてしまう。
/// 見るべきなのは行き先そのものである。
void refuseSeedOnProductionHome(
  String home, {
  Map<String, String>? environment,
}) {
  final env = Map<String, String>.of(environment ?? Platform.environment)
    ..remove(homeEnvVar);
  final String production;
  try {
    production = WindowsAppPaths.resolve(environment: env).home;
  } on SyncDataError {
    // 本番の領域が決まらない環境では、消す相手も存在しない。**推測で止めない。**
    return;
  }
  if (!_sameDirectory(home, production)) return;
  throw StateError(
    '本番のデータ領域には種を撒けない: $home。'
    '$homeEnvVar を外すか、別の場所を指してください。',
  );
}

/// 同じ場所を指しているか。**Windows は大文字小文字を区別しない。**
bool _sameDirectory(String a, String b) {
  String normalize(String value) {
    var path = value.trim().replaceAll('/', Platform.pathSeparator);
    while (path.length > 1 && path.endsWith(Platform.pathSeparator)) {
      path = path.substring(0, path.length - 1);
    }
    return Platform.isWindows ? path.toLowerCase() : path;
  }

  return normalize(a) == normalize(b);
}

/// 種モードの自動リセット。**台帳を開く前に、台帳だけを消す。**
///
/// 消すのは `library.db`（`-wal` / `-shm` を含む）だけで、**`token.json`・`credentials/`・
/// `config/device.json`・`logs/` は残す** — 毎回サインインし直しになり、ログ水準の設定が飛び、
/// 復元前の記録が読めなくなる（`非公開資料:p5b-verification-mode.md`「自動リセット」）。
///
/// **静かにやらない。** 不可逆な操作なので、起動のたびに1行残す。転送先（`appDataFolder`）の
/// 掃除はここではない — この時点ではまだ認可が済んでいないので、[Composition.setupFresh] の
/// 直前に分ける。
void resetSeededLedger(AppPaths paths) {
  var removed = 0;
  for (final suffix in const ['', '-wal', '-shm']) {
    final file = File('${paths.dbPath}$suffix');
    if (!file.existsSync()) continue;
    file.deleteSync();
    removed += 1;
  }
  _log.warning('seed.ledger.reset', {'path': paths.dbPath, 'removed': removed});
}
