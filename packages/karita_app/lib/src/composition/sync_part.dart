part of '../composition.dart';

/// 同期の状態。同期の状態・世代変更とアカウント違いの旗・run の結果の受け取り・前面復帰の契機。
///
/// **状態（フィールド）は持たない** — 拡張は持てないので、本体（`composition.dart`）に置く。
extension CompositionSync on Composition {
  AppSyncStatus get syncStatus => appSyncStatus(
    engine.status(now: nowUtc(), doctorFailed: lastDoctor?.failed ?? false),
    generationChanged: _generationChanged,
    accountMismatch: _accountMismatch,
  );

  /// **同じ内容で出し直さない。** 15分ごとに同じ通知が復活すると、読んだ利用者が閉じられない。
  void _markGenerationChanged(SyncDataError error) {
    final issue = AppIssue(error.code, error.message);
    if (_generationChanged?.message == issue.message) return;
    _generationChanged = issue;
    _log.warning('sync.generation.changed', {'reason': error.message});
    _notifyStatus();
  }

  /// **成功したら下ろす。** 起点へ戻った端末が異常を名乗り続けない。
  void _clearGenerationChanged() {
    if (_generationChanged == null) return;
    _generationChanged = null;
    _log.info('sync.generation.rejoined');
    _notifyStatus();
  }

  void _markAccountMismatch() {
    if (_accountMismatch != null) return;
    _accountMismatch = const AppIssue(
      'account-mismatch',
      'Connected to a different Google account than the one recorded on this device.',
    );
    _log.warning('sync.account.mismatch');
    _notifyStatus();
  }

  void _clearAccountMismatch() {
    if (_accountMismatch == null) return;
    _accountMismatch = null;
    _log.info('sync.account.matched');
    _notifyStatus();
  }

  /// 記録済みの `drive_account_id` と、いま繋がっているアカウントを突き合わせる。
  ///
  /// **保管先を読めなければ判定しない**（[_generationChanged] と同じ理由。オフラインや
  /// 認可切れの端末を「別アカウント」と誤判定しない）。**未記録なら、読めた値をここで
  /// 記録する** — 初回セットアップの成功時と、この判定そのものが同じ経路を通ることで、
  /// 記録漏れが起こらない。
  ///
  /// 戻り値は「通常同期を続けてよいか」。`false` なら呼び出し側は `engine.run` を呼ばない
  /// （`非公開資料:production-wiring-auth-backup-sync.md`「違えば通常同期を止める」）。
  Future<bool> _checkAccountIdentity() async {
    final DriveAccountInfo info;
    try {
      info = await client.about();
    } catch (error) {
      _log.fine('sync.account.check.unreadable', {'reason': '$error'});
      return true;
    }
    if (info.permissionId.isEmpty) return true;
    final recorded = getState(session.db, stateDriveAccountId);
    if (recorded == null) {
      transaction(
        session.db,
        () => setState(session.db, stateDriveAccountId, info.permissionId),
      );
      _clearAccountMismatch();
      return true;
    }
    if (recorded == info.permissionId) {
      _clearAccountMismatch();
      return true;
    }
    _markAccountMismatch();
    return false;
  }

  /// 同期 run の結果を画面と記録へ渡す。
  ///
  /// **業務データを書いた run だけが一覧を読み直させる。** 何かあった回（送信・受信・適用の
  /// どれか）は INFO で件数を残す — 周期の begin/done は FINE なので、ここが無いと「届いた」が
  /// INFO の水準から見えない。
  void _afterRun(RunResult result) {
    if (!result.idle) {
      _log.info('sync.run.changed', {
        'pushed': result.pushed.length,
        'fetched': result.report.fetched,
        'applied': result.report.applied,
        'conflicted': result.report.conflicted,
        'auto_resolved': result.auto.resolved.length,
      });
    }
    if (result.ledgerChanged) {
      _notifyStatus();
    } else {
      _notifySyncStatus();
    }
  }

  /// 転送を要る操作が今どの一手を進めているかを記録する。**ログの語彙はここが決める** —
  /// エンジンは事実（[SyncEngine.onProgress]）を渡すだけである。
  ///
  /// **待ちが長引いたときの手がかりにする。** Drive との通信（push・pull・バックアップの
  /// upload/download）は明示のタイムアウトを持たない。通信が詰まると `await` が返らないまま
  /// 待ち続け、ここが無いとどの一手で止まっているかがログのどこにも残らない。
  void _onSyncProgress(String step) {
    if (_closed) return;
    _log.fine('sync.progress', {'step': step});
  }

  /// 業務を書いた直後のトリガ。**同期は利用者の操作ではない。**
  ///
  /// 呼ぶのは業務を書いた側である。**デモでは環が無いので何も起きない。**
  Future<void> syncAfterDomainWrite() async {
    _notifyStatus();
    await refresh?.trigger(RefreshTrigger.domainWrite);
  }

  /// 前面にいる間だけ回す。**観測するのは合成層である。**
  ///
  /// 利用側（harness と本番 GUI）に置くと配線が2本になり、「合成が1つ」の証明が崩れる。
  /// **binding が無い場（単体試験）では黙って繋がない** — ライフサイクルは製品の経路の話で
  /// あって、組み立ての成否ではない。
  void _attachLifecycle() {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    } catch (error) {
      _log.fine('lifecycle.unavailable', error);
    }
  }

  /// **デモでも繋ぐ。** 周期リフレッシュはデモに無いが、受け渡しの排出は本番と同じ経路である。
  void _onLifecycle(AppLifecycleState state) {
    final loop = refresh;
    if (state != AppLifecycleState.resumed) {
      loop?.pause();
      // **背面へ回ったら蔵書の照会を止める。** 見えていない画面のために書籍リクエストの枠を
      // 使わない。取れている観測は捨てないので、戻ってきたら同じ結果が同じ確認時刻で出る。
      // **画面側へ配線を増やさない** — 背面を観測しているのは合成層だけである。
      _holdings?.cancel();
      return;
    }
    loop?.resume();
    _notifyStatus();
    // **前面へ戻ったときに取りに行く。** ブラウザーから戻った直後がここを通る。
    unawaited(handoff.drain());
  }
}
