/// 前面の周期リフレッシュ。**アプリが起きている間だけ回る。**
///
/// 正本は `非公開資料:production-sync-small-changes.md`「背面同期を持たない」。同期が
/// 走るのは**起動時・業務更新直後・前面復帰の3トリガと、起動中の周期リフレッシュ**である。
/// 閉じている間は何もしない。
///
/// **前面復帰は 2026-10-08 に足した**（同「前面同期の短縮」）。Android はプロセスが生きたまま
/// 戻るので「起動」にならず、復帰で取りに行かないと他の端末の変更が周期まで見えない。
///
/// **手動は本番の画面に置かない**（2026-09-14）。[RefreshTrigger.manual] は残してあるが、
/// 呼ぶのはデバッグ専用の画面と harness だけである。
///
/// **純 Dart である。** ライフサイクルの観測（Flutter）は合成層の側が繋ぐ。ここは「いつ回るか」
/// の規則だけを持つ。
library;

import 'dart:async';

import 'package:logging/logging.dart';

final Logger _log = Logger('karita.app.refresh');

/// 同期が走った理由。**ログの `trigger=` に出る。**
enum RefreshTrigger {
  /// 起動直後の1回。
  startup,

  /// 業務を書いた直後。
  domainWrite,

  /// 起きている間の周期。
  periodic,

  /// 前面へ戻った。**直前の run が終わってから [RefreshLoop.resumeMinGap] 未満なら飛ばす。**
  resume,

  /// **デバッグ専用。** 本番の画面には置かない。
  manual,
}

/// なぜ走らなかったか。
enum RefreshSkip {
  /// **初回起動の2択が済んでいない。** `run()` は起点を置いてしまうので回さない。
  notReady,

  /// 前の1回がまだ走っている。**重ねない。**
  busy,

  /// `sync.autoRefreshEnabled` が `false`、またはデモである。
  disabled,

  /// アプリが前面にいない。
  paused,

  /// 前面復帰だが、直前の run が終わってから間もない。**Windows はフォーカスの出入りでも
  /// 復帰になる**ので、切り替えのたびに走らせない。
  recent,
}

/// 走らせるかどうかを決め、周期を刻む。
class RefreshLoop {
  /// 1回ぶんの同期。**中身は合成層が渡す** — ここは `SyncEngine` を知らない。
  final Future<void> Function(RefreshTrigger trigger) run;

  /// 初回起動の2択が済んでいるか。**済むまで回さない。**
  final bool Function() ready;

  /// 周期を回してよいか。`device.json` とデモの旗から決まる。
  final bool enabled;

  final Duration interval;

  /// 前面復帰で走らせるのに要る、直前の run の終了からの間隔。
  final Duration resumeMinGap;

  /// 時計。**試験だけが差し替える。**
  final DateTime Function() clock;

  /// 直前の run が終わった時刻。失敗で終わった run も数える — 失敗の直後に復帰で叩き直さない。
  DateTime? _lastFinished;

  Timer? _timer;
  bool _busy = false;
  bool _paused = false;
  bool _pendingWrite = false;
  bool _stopped = false;

  RefreshLoop({
    required this.run,
    required this.ready,
    required this.enabled,
    required this.interval,
    this.resumeMinGap = defaultResumeMinGap,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// 前面復帰の間隔の既定。**周期の既定（30 秒）と同じにする。**
  static const Duration defaultResumeMinGap = Duration(seconds: 30);

  bool get running => _timer != null;

  /// 起動時の1回を走らせ、周期を始める。
  ///
  /// **起動時のトリガは `enabled` に関わらず走る。** 周期を止めるのは「起きている間くり返す
  /// のをやめる」ことであって、起動時に最新へ揃えないことではない。**デモはこの環そのものを
  /// 作らない** — 「自動処理を登録しない」を旗ではなく不在で表す。
  Future<void> start() async {
    _stopped = false;
    await trigger(RefreshTrigger.startup);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!enabled || _paused || _stopped) return;
    _timer = Timer.periodic(interval, (_) => trigger(RefreshTrigger.periodic));
  }

  /// 前面から外れた。**刻むのをやめる。**
  void pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// 前面へ戻った。周期を刻み直し、同期を1回走らせる。
  ///
  /// 保留した業務更新があればそれを送る1回（`domainWrite`）にまとめる。無ければ他の端末の
  /// 変更を取りに行く1回（`resume`）で、直前の run から間もなければ飛ばす（2026-10-08）。
  void resume() {
    _paused = false;
    _schedule();
    if (_pendingWrite && !_busy && !_stopped && ready()) {
      _pendingWrite = false;
      unawaited(trigger(RefreshTrigger.domainWrite));
      return;
    }
    unawaited(trigger(RefreshTrigger.resume));
  }

  void stop() {
    _stopped = true;
    _pendingWrite = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 1回ぶんを走らせる。**走らせたら `true`。**
  /// 実行中の業務更新は1回の追加同期へまとめ、受付時には `false` を返す。
  ///
  /// 飛ばした理由は必ずログに出す — 「走らなかった」と「走って何もなかった」を実機で
  /// 区別するためである。
  Future<bool> trigger(RefreshTrigger reason) async {
    if (_stopped) return false;
    if (_busy && reason == RefreshTrigger.domainWrite) {
      _pendingWrite = true;
      _log.fine('sync.refresh.queued', {'trigger': reason.name});
      return false;
    }
    final skip = _skipFor(reason);
    if (skip != null) {
      _log.fine('sync.refresh.skipped', {
        'trigger': reason.name,
        'reason': skip.name,
      });
      return false;
    }
    _busy = true;
    // **周期の回は FINE にする**（2026-10-08）。30 秒ごとに INFO を2行書くと、何も無い回で
    // ログが埋まる。取り込みや送信があった回は合成層が `sync.run.changed` を INFO で出す。
    final level = reason == RefreshTrigger.periodic ? Level.FINE : Level.INFO;
    _log.log(level, 'sync.refresh.begin', {'trigger': reason.name});
    try {
      await run(reason);
      _log.log(level, 'sync.refresh.done', {'trigger': reason.name});
      return true;
    } catch (error) {
      // **止めない。** 転送の失敗は次の周期でまた試す。状態は `SyncFacts` が持つ。
      //
      // **例外は付随値の `error` に入れる。** `package:logging` の第2引数は付随値に使って
      // いるので、第3引数（stackTrace）へ渡すと行から消える。
      _log.warning('sync.refresh.failed', {
        'trigger': reason.name,
        'error': '$error',
      });
      return false;
    } finally {
      _busy = false;
      _lastFinished = clock();
      // Coalesce writes during this run into one follow-up. Pausing retains the
      // request until resume; closing discards it without starting more work.
      if (_pendingWrite && !_paused && !_stopped && ready()) {
        _pendingWrite = false;
        await trigger(RefreshTrigger.domainWrite);
      }
    }
  }

  RefreshSkip? _skipFor(RefreshTrigger reason) {
    if (_busy) return RefreshSkip.busy;
    if (!ready()) return RefreshSkip.notReady;
    if (reason == RefreshTrigger.periodic) {
      if (!enabled) return RefreshSkip.disabled;
      if (_paused) return RefreshSkip.paused;
    }
    if (reason == RefreshTrigger.resume) {
      final last = _lastFinished;
      if (last != null && clock().difference(last) < resumeMinGap) {
        return RefreshSkip.recent;
      }
    }
    return null;
  }
}
