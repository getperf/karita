/// 本番の起動順。**組み立ては `compose` が持つ。**
library;

import 'dart:async';

import 'package:karita_platform/karita_platform.dart';
import 'package:logging/logging.dart';

import '../composition.dart';
import '../demo.dart';
import '../logging.dart';
import '../public_api.dart';

final Logger _log = Logger('karita.app');

/// 立てる。**これが本番の経路である。**
///
/// 順序は `appPaths() → device.json → installLogging() → compose()` である
/// （`非公開資料:logging-and-diagnostics.md`）。**合成より先にログを立てる** —
/// `compose()` が落ちたときにも記録が要る。**`device.json` はログより先に読む** — 水準と書式が
/// そこにあるためである。
///
/// `KARITA_HOME` の差し替えは `AppPaths` の中に閉じている。ここでは何も足さない — 差し替えを
/// 引数で受けると、既定の解決が一度も通らないまま製品に出る。
Future<Composition> boot() async {
  // **モードを先に決める。置き場所がモードで変わるためである**（2026-09-23）。種モードは
  // 本番のデータ領域を使わず、OS の一時領域の下の専用の場所へ行く（[seedHome]）。
  //
  // **落ちてもここでは投げない。** 記録を残す先（ログ）がまだ立っていないので、置き場所の
  // 解決とログの設置まで進めてから出す。**解決できなかったときは本番の領域を開く** — 種が
  // 立っていないのと同じ場所であり、そこがこの端末の記録の置き場である。
  AppMode? wanted;
  Object? modeError;
  try {
    wanted = AppMode.resolve();
  } catch (error) {
    modeError = error;
  }

  final paths = await appPaths(mode: wanted);
  paths.ensure();

  final settings = DeviceSettings.read(paths.configDir);
  final choice = resolveLogging(
    configLevel: settings.logLevel,
    configFormat: settings.logFormat,
  );
  installLogging(
    logDir: paths.logDir,
    level: choice.level,
    format: choice.format,
  );

  if (modeError != null) {
    // **不正値（`FormatException`）と、種のガード（`StateError`）の両方がここへ来る。**
    // どちらも「起動を止める」であって、片方だけを記録すると落ちた理由が読めない。
    _log.severe('app.start.failed', {
      'reason': modeError is FormatException ? modeError.message : '$modeError',
    });
    throw modeError;
  }
  final mode = wanted!;

  // ガード③。**消してよい台帳かを、行き先そのもので見る。**
  if (mode.seedMode) {
    try {
      refuseSeedOnProductionHome(paths.home);
    } catch (error) {
      _log.severe('app.start.failed', {'reason': '$error'});
      rethrow;
    }
  }

  _log.info('app.start', {
    ...mode.toLogFields(),
    // **種のときは置き場所も出す。** 機械が選んだ場所なので、証拠から読めないと追えない。
    if (mode.seedMode) 'home': paths.home,
    'level': choice.level.name,
    'format': choice.format.name,
    ...settings.toLogFields(),
    // **どちらのキーを採ったかだけを出す。** 値は出さない。
    ...resolveCalilAppkey(deviceOverride: settings.calilAppkey).toLogFields(),
  });
  // **黙って既定にしない。** 水準を上げたつもりの実機で「出ていない」と「その値で動いて
  // いない」を区別できなくなる。
  for (final ignored in choice.ignored) {
    _log.warning('log.setting.ignored', ignored);
  }
  for (final issue in settings.issues) {
    _log.warning('device.config.issue', issue.toMap());
  }

  try {
    final composition = await compose(
      paths: paths,
      settings: settings,
      mode: mode,
    );
    // **起動直後に1回取りに行く。** 共有や拡張から起動された場合、配送は Flutter が起きる前に
    // 届いている。前面復帰の観測だけでは、その1件目を拾えない。**台帳と fixture が整った後で
    // ある** — 初期化中に届いたものは OS 側の holder に残っており、ここで拾う。
    await composition.handoff.drain();
    // **周期リフレッシュを始める。** 起動時の1回を走らせ、周期を刻む。2択が済むまでは
    // `ready:` が止めるので、未セットアップの端末では何も起きない。
    //
    // **2026-09-24 まで誰も呼んでいなかった。** `RefreshLoop.start()` を呼ぶのは試験だけで、
    // 本番では起動時の同期も周期も走らず、Android が［新しく始める］の後 0件のまま止まった。
    // **待たない** — 同期は通信を伴い、起動の画面を止める理由が無い。
    unawaited(composition.refresh?.start());
    return composition;
  } catch (error) {
    _log.severe('app.start.failed', {'reason': '$error'});
    rethrow;
  }
}
