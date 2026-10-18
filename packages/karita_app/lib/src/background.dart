/// 背面の口。**実装は持たない。**
///
/// **背面同期を持たないと決めた**（2026-09-13）。アプリが閉じている間は何もしない。`workmanager`
/// は P5a で3本とも削除した。**それでも口はここに残す** — 背面の戦略を ③ へ焼くと、本番アプリが
/// 別の戦略を採れなくなる。iOS の BGTaskScheduler を採るなら、実装が入るのはここである。
///
/// **通知は別の話である。** 返却期限のリマインドは自端末の台帳から作れるので、ローカル通知の
/// 予約で足り、背面同期を要さない。混ぜない。
library;

import 'package:logging/logging.dart';

final Logger _log = Logger('karita.app.background');

/// 背面で走らせる口。
abstract interface class BackgroundScheduler {
  /// この端末が背面を持つか。**いまはどの端末も `false` である。**
  bool get available;

  /// 背面の仕事を登録する。
  Future<void> register();

  /// 登録した仕事を落とす。
  Future<void> cancelAll();
}

/// 背面を持たない端末。**現状これが全端末の実装である。**
///
/// 呼ばれても落とさず、呼ばれた事実だけを残す。落とすと、口を持つ意味（差し替えられること）が
/// 呼び出し側の分岐に化ける。
class NoBackgroundScheduler implements BackgroundScheduler {
  const NoBackgroundScheduler();

  @override
  bool get available => false;

  @override
  Future<void> register() async =>
      _log.fine('background.unavailable', {'call': 'register'});

  @override
  Future<void> cancelAll() async =>
      _log.fine('background.unavailable', {'call': 'cancelAll'});
}
