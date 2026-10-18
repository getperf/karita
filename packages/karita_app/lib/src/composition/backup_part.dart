part of '../composition.dart';

/// バックアップと初回セットアップ。バックアップ・復元・初回起動の2択・検証モードの種。
///
/// **状態（フィールド）は持たない** — 拡張は持てないので、本体（`composition.dart`）に置く。
extension CompositionBackup on Composition {
  /// 窓口の失敗を**記録してから**、画面へ出せる1件にする。
  ///
  /// **記録が無いと診断できない。** 2026-09-23 の実機で「新しく始める」が落ちたとき、ログには
  /// 1行も残っておらず、画面に出たのは `Unexpected failure (SyncDataError)` という型名だけ
  /// だった。**どちらからも原因に辿り着けない。**
  ///
  /// **出すのはコードとメッセージの2つだけである。** `SyncDataError` の `code` は
  /// `setup-already-done` のように何が起きたかを名指しており、メッセージも利用者向けの
  /// 日本語で書かれている。生の例外・HTTP 本文・設定の生値はここを通らない
  /// （`非公開資料:ui-state-model.md`「設定でこの段に決めたこと」）。
  Never _failed(String event, Object error) {
    final issue = switch (error) {
      AppIssue issue => issue,
      // `TransportAuthError` は `SyncDataError` の子で、code は `transport-auth` である。
      SyncDataError error => AppIssue(error.code, error.message),
      _ => AppIssue('unexpected', 'Unexpected failure (${error.runtimeType}).'),
    };
    _log.severe(event, {'code': issue.code, 'reason': issue.message});
    throw issue;
  }

  /// 選べるバックアップの一覧。**保管先の識別子は渡さない**（[AppBackup]）。
  ///
  /// **`skipped` も渡す。** 索引を読めなかった `.blib` を黙って落とすと、索引を書けていない
  /// 不具合が「1つも無い」という形でしか現れない。
  Future<AppBackupListing> listBackups() async {
    _requireOpen();
    final BackupListing listing;
    try {
      listing = await engine.listBackups();
    } catch (error) {
      _failed('backup.list.failed', error);
    }
    return AppBackupListing(
      items: [for (final ref in listing.refs) appBackup(ref)],
      skipped: listing.skipped,
    );
  }

  /// 初回起動の2択を出し分ける事実。**ほかの端末が使っている記録が保管先にあるか。**
  ///
  /// あれば2択は「今の記録に合流する」と「バックアップの時点に戻して始める」になり、後者には
  /// 他の端末が止まることの確認が付く（2026-10-15）。**世代の語彙は渡さない** — 画面が持つのは
  /// 「ある／無い」だけである。
  ///
  /// **種モードでは常に無いと答える。** 「新しく始める」が転送先を先に空にするので、合流は
  /// 起きない（[setupFresh]）。
  Future<bool> hasSharedRecords() async {
    _requireOpen();
    if (mode.seedMode) return false;
    try {
      return await engine.hasActiveGeneration();
    } catch (error) {
      _failed('setup.shared_records.failed', error);
    }
  }

  /// ［バックアップ］［復元］の2行に出す事実。**台帳から同期に読む**（保管先へは行かない）。
  AppBackupFacts backupFacts() {
    _requireOpen();
    final db = session.db;
    return AppBackupFacts(
      lastBackupAt: getState(db, stateLastBackupAt),
      lastRestoreAt: getState(db, stateLastRestoreAt),
      lastRestoreCreatedAt: getState(db, stateLastRestoreCreatedAt),
      lastRestorePlatform: getState(db, stateLastRestorePlatform) ?? '',
      unsent: engine
          .status(now: nowUtc(), doctorFailed: lastDoctor?.failed ?? false)
          .facts
          .unsent,
      generationChanged: _generationChanged != null,
      available: mode.gate.open,
    );
  }

  /// ［バックアップ］。**その場で作って保管先へ入れる。走ったときだけ `true`**（デモでは走らない）。
  ///
  /// 最終作成日時はエンジンが**保管に成功した後にだけ**進める。
  Future<bool> createBackup() async {
    _requireOpen();
    _log.info('backup.create.begin');
    final Attempt<ExportOutcome> attempt;
    try {
      attempt = await mode.gate.run(() => engine.exportBackup(now: nowUtc()));
    } catch (error) {
      _failed('backup.create.failed', error);
    }
    if (attempt.wasSkipped) return false;
    final outcome = attempt.value;
    _log.info('backup.created', {
      'backup_id': outcome.backupId,
      'bytes': outcome.bytes,
    });
    _notifyStatus();
    return true;
  }

  /// ［復元］でバックアップを選んだとき。**これは宣言である** — 新しい世代を始め、他の端末を
  /// 止める。順序（検証 → 起点を公開 → 置換）はエンジンの中で閉じている。
  Future<bool> restoreFromBackup(String backupId) => _restore(
    'backup',
    () => engine.restoreFromBackup(now: nowUtc(), backupId: backupId),
  );

  /// ［復元］の「別の端末で復元されたデータに合わせる」。**これは参加である** — 有効世代の
  /// 起点へ戻り、世代を進めない。**他の端末を止めない。**
  ///
  /// 画面が出すのは旗（[AppBackupFacts.generationChanged]）が立っているときだけだが、呼べる
  /// 条件はここで縛らない。乗る先が無ければエンジンが `generation-no-baseline` で止める。
  Future<bool> rejoinGeneration() =>
      _restore('baseline', () => engine.restoreFromBaseline(now: nowUtc()));

  /// ［復元］の「空にしてやり直す」。**これも宣言である** — 空の台帳を新しい正本として
  /// 起点を公開し、他の端末を止める。手順は [restoreFromBackup] と同じで、エンジンの中で
  /// 閉じている。
  ///
  /// **アカウントや保管先の過去のバックアップ・イベントは変えない。** 消えるのはこの端末が
  /// 置換する業務データだけである。
  Future<bool> restoreEmpty() =>
      _restore('empty', () => engine.restoreEmpty(now: nowUtc()));

  /// 復元2つの共通部分。**成功後に3つ打つ。**
  ///
  /// - 旗を下ろす。どちらの復元でも、端末は保管先の有効世代に乗った
  /// - 画面への通知。**台帳の接続が替わったので、画面の保持は [ledgerSessionToken] で捨てる**
  /// - 同期の契機。宣言なら起点を他の端末へ知らせ、参加なら起点より後の封筒を取りに行く
  Future<bool> _restore(
    String kind,
    Future<RestoreOutcome> Function() body,
  ) async {
    _requireOpen();
    _log.info('restore.$kind.begin');
    final Attempt<RestoreOutcome> attempt;
    try {
      attempt = await mode.gate.run(body);
    } catch (error) {
      _failed('restore.$kind.failed', error);
    }
    if (attempt.wasSkipped) return false;
    final outcome = attempt.value;
    _log.info('restore.completed', {
      'kind': kind,
      'seq': outcome.seq,
      'declared': outcome.declared,
      'counts': outcome.counts,
    });
    _generationChanged = null;
    _notifyStatus();
    unawaited(refresh?.trigger(RefreshTrigger.startup));
    return true;
  }

  /// 初回起動の2択の「バックアップから引き継ぐ」。**エンジンを包むだけである。**
  ///
  /// 「一覧 → 選択 → 検証 → 起点を公開 → 置換」は `setupFromBackup` の中で閉じている。
  /// **画面が持つのは2択の提示と、一覧から1件を選ばせることだけである。**
  ///
  /// **種モードでも転送先を空にしない。** 掃除すると、引き継ぐ相手のバックアップごと消える
  /// （「新しく始める」は `bootstrap` を踏みたいので掃除する。こちらは逆である）。
  Future<RestoreOutcome> setupFromBackup(String backupId) async {
    _requireOpen();
    _log.info('setup.from_backup.begin');
    final RestoreOutcome outcome;
    try {
      outcome = await engine.setupFromBackup(backupId, now: nowUtc());
    } catch (error) {
      _failed('setup.from_backup.failed', error);
    }
    // **接続先のアカウントをここで記録する。** 読めなくても初回起動そのものは止めない —
    // 次の同期チェックが読めたときに記録する（[_checkAccountIdentity]）。
    await _checkAccountIdentity();
    _notifyStatus();
    // 起点を公開した直後の端末である。**他の端末へ届くのは次の同期から**なので、ここで打つ。
    unawaited(refresh?.trigger(RefreshTrigger.startup));
    return outcome;
  }

  /// 初回起動の2択の「新しく始める」。**エンジンを包むだけで、順序は書き直さない。**
  ///
  /// **種モードでは転送先を先に空にする。** 掃除しないと、残った baseline に `adopt` して
  /// 古い世代へ乗る — `bootstrap` を踏みたい検証で `adopt` になると、測りたい経路が一度も
  /// 通らない（`非公開資料:p5b-verification-mode.md`）。
  ///
  /// **本番では何も挟まらない。** `mode.seedMode` が立つのは検証モードだけである。
  Future<GenerationResolution> setupFresh() async {
    _requireOpen();
    _log.info('setup.fresh.begin');
    final GenerationResolution resolution;
    try {
      if (mode.seedMode) {
        final removed = await _purgeSeededAppData();
        _log.warning('seed.appdata.purged', {'removed': removed});
      }
      resolution = await engine.setupFresh(now: nowUtc());
    } catch (error) {
      _failed('setup.fresh.failed', error);
    }
    // **接続先のアカウントをここで記録する。** 読めなくても初回起動そのものは止めない —
    // 次の同期チェックが読めたときに記録する（[_checkAccountIdentity]）。
    await _checkAccountIdentity();
    // **種はここで撒く。** 台帳が空でないと `SyncEngine.isSetUp` が真になり、この2択そのものが
    // 断られる（`setup-already-done`）。撒いた分は outbox に載り、次の同期で push される。
    //
    // **失敗を素通りさせない。** ここは上の `try` の外で、投げると `_failed` を通らず、通知も
    // 同期の契機も飛ぶ。台帳には書き込み済みなので起動ゲートは開き、画面の失敗表示も隠れる —
    // 2026-09-24 の実機では、ログに1行も残らないまま88件が送られずに残った。
    if (mode.seedMode) {
      try {
        _seedFixture();
      } catch (error) {
        _notifyStatus();
        _failed('seed.failed', error);
      }
    }
    // **台帳が変わった。** 起動ゲートの述語（[bootReady]）もここで初めて真になるので、
    // 画面が読み直す契機を打つ。**戻り値は画面へ渡さない** — 世代の語彙は同期の側である。
    _notifyStatus();
    // **同期の契機を打つ。** 参加（`adopt`）した端末は世代の封筒を取りに行くまで0件のままで、
    // 種を撒いた端末は撒いた分を送るまで他の端末へ届かない。
    unawaited(refresh?.trigger(RefreshTrigger.startup));
    return resolution;
  }

  /// 検証モードの種を撒く。**初回起動の2択が済んだ後にだけ呼ぶ。**
  ///
  /// **「バックアップから引き継ぐ」では撒かない。** あちらは選んだバックアップの内容が正本で
  /// あり、種を足せば選んだ時点と違うものになる。
  void _seedFixture() {
    final fixture = _fixture;
    if (fixture == null) return;
    // **世代は1つある。** `setupFresh` が作った後に撒くので、デモの「世代0」で検証しない。
    final report = fixture.seed(domain, now: nowUtc(), generations: 1);
    fixtureReport = report;
    _log.info('demo.ready', {
      ...report.toJson(),
      'session_id': deviceId,
      'ledger': mode.demo.name,
      'db_path': session.path,
    });
  }

  /// `appDataFolder` を空にする。**合成層に置く。**
  ///
  /// [RestDriveClient.listPage] と [RestDriveClient.delete] は public なので、
  /// `BackupStorePort` を汚さずに書ける。**`BackupStorePort` には足さない** — `store.delete`
  /// が `backup-` だけを対象にしているのは「消してよいのはどれかを機械に判断させない」と
  /// いう保持方針そのもので、`baseline-` を消せる口を製品の port に開けるとその方針が崩れる。
  ///
  /// **一覧を取り切ってから消す。** 消しながら `pageToken` を辿ると、繰り上がった分を飛ばす。
  Future<int> _purgeSeededAppData() async {
    final ids = <String>[];
    String? pageToken;
    do {
      final page = await client.listPage(pageToken: pageToken);
      ids.addAll([for (final file in page.files) file.fileId]);
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    for (final id in ids) {
      await client.delete(id);
    }
    return ids.length;
  }
}
