part of '../composition.dart';

/// 組む。**[boot] が立てた前提を受け取るだけで、自分では解決しない。**
Future<Composition> compose({
  required AppPaths paths,
  required DeviceSettings settings,
  required AppMode mode,
  String? demoCatalog,
  DateTime? demoDate,
  String demoScenario = defineDemoScenario,
  // 試験が実ブラウザーを起こさないための差し替え口。**本番は渡さない。**
  Future<void> Function(Uri url)? openBrowser,
  BrowserLauncher? browsers,
}) async {
  // **種はデモと直交する。** デモは自分の起動準備として fixture を入れ、検証モードは
  // `KARITA_SEED` で同じ fixture を本番の台帳へ入れる
  // （`非公開資料:p5b-verification-mode.md`）。**入れるものは同じ1つである。**
  //
  // **シナリオを名指す旗は、モードごとに1つだけである。** デモは `KARITA_DEMO_SCENARIO`、
  // 検証モードは `KARITA_SEED` の値そのものが名前になる。2つが同時に効く場はないので、
  // **どちらが強いかを決める必要が無い** — 決めると、誰も決めていない優先順位ができる。
  final wantedScenario = (mode.seedMode ? mode.seed! : demoScenario).trim();
  final scenario = wantedScenario.isEmpty ? 'standard' : wantedScenario;
  DemoFixture? fixture;
  if (mode.isDemo || mode.seedMode) {
    if (scenario != 'standard') {
      throw const FormatException('Unknown demo scenario');
    }
    fixture = DemoFixture(
      demoCatalog ??
          await rootBundle.loadString(
            'packages/karita_app/assets/demo/standard.json',
          ),
      demoDate ?? DateTime.now(),
    );
  }

  // **既定値表が読めないことを起動の失敗にしない。** 引けなければ `公式サイト` へ落ちるだけで
  // 業務は続く（`MypageDefaults.parse` が空の表を返す）。
  MypageDefaults defaults = const MypageDefaults.empty();
  try {
    defaults = MypageDefaults.parse(
      await rootBundle.loadString(
        'packages/karita_app/assets/libraries/mypage-defaults.json',
      ),
    );
  } catch (error) {
    _log.warning('mypage.defaults.unavailable', {'reason': '$error'});
  }
  final auth = mode.isDemo
      ? demoAuth(paths)
      : Platform.isAndroid
      ? androidAuth(paths)
      : windowsAuth(paths);
  final client = RestDriveClient(tokens: auth.tokens);
  final store = DriveBackupStore(client);

  // **種モードは起動のたびに台帳を作り直す。** `DemoFixture.seed` が空でない台帳を拒むので、
  // リセットが無いと2回目の起動が落ちる — 便利機能ではなく、この旗を使える形にする条件である。
  if (mode.seedMode) resetSeededLedger(paths);

  // **デモは本番の台帳を開かない。** `memory` はメモリ、`temp` は本番と分けた一時領域である。
  final ledger = openLedger(mode.demo, paths);
  try {
    final session = ledger.session;
    final at = nowUtc();
    // **版が動いたときだけ1行出す。** migration は台帳の形を変える一度きりの事象で、後から
    // 「いつ上がったか」を知る手段が `schema_migrations` を SQL で読むことしかなかった。
    //
    // **毎回は出さない。** 現在の版は `doctor` の側が持っており、起動のたびに出すと同じことを
    // 2箇所から言うことになる（`非公開資料:logging-and-diagnostics.md`）。
    final migrated = migrate(session.db, now: at);
    if (migrated.isNotEmpty) {
      _log.info('ledger.migrated', {
        'to': latestVersion(),
        'applied': [for (final m in migrated) m.version],
        'names': [for (final m in migrated) m.name],
      });
    }

    // **device_id は台帳が持つ。** 一度決めたら動かさない — 動かすと、転送先に残っている封筒の
    // 書き手が誰だったのか分からなくなる。
    final deviceId = ensureDeviceId(session.db, at: at);

    final contracts = Contracts.load();
    final uuid = newUuid;
    final domain = DomainContext(
      db: () => session.db,
      contracts: contracts,
      deviceId: deviceId,
      uuid: uuid,
    );
    // 業務の発行にDrive世代は不要。setupFreshは呼ばず、上の端末・profile初期化を使う。
    //
    // **検証モード（種）はここで撒かない**（2026-09-23。実機で踏んだ）。fixture は業務 API を
    // 通るので `outbox_events` と `applied_events` に行を残し、**`SyncEngine.isSetUp` が真に
    // なる。** すると初回起動の2択が `setup-already-done` で断られる — 起動ゲートの述語
    // （`localGeneration != null`）とエンジンの述語（3条件）が食い違っていた。
    //
    // **種は `setupFresh()` が通った後に撒く**（[_seedFixture]）。撒いた88件は outbox に載り、
    // 次の同期で push される。Android が `adopt` でそれを再生して30冊を受けるのは変わらない。
    final report = mode.isDemo ? fixture?.seed(domain, now: at) : null;

    Composition? readyComposition;
    final engine = SyncEngine(
      session: session,
      profile: defaultProfile,
      deviceId: deviceId,
      transportFor: (generationId) => DriveTransport(client, generationId),
      store: store,
      contracts: contracts,
      uuid: uuid,
      // **状態だけを伝える。** 開始と終了で台帳の通知まで打つと、何も無い回ごとに一覧を
      // 読み直す。台帳を書いた run は下のクロージャが [_afterRun] で伝える。
      onStatusChanged: () => readyComposition?._notifySyncStatus(),
      onProgress: (step) => readyComposition?._onSyncProgress(step),
    );

    final composition = Composition(
      paths: paths,
      settings: settings,
      mode: mode,
      auth: auth,
      client: client,
      session: session,
      deviceId: deviceId,
      environmentDoctor: auth.doctor,
      background: const NoBackgroundScheduler(),
      handoff: HandoffQueue(_shareInbox()),
      mypageDefaults: defaults,
      calilKey: resolveCalilAppkey(deviceOverride: settings.calilAppkey),
      openBrowser: openBrowser ?? openSystemBrowser,
      // **試験が差し替えた口があれば、選んだブラウザーも使わない** — 実ブラウザーを起こさない。
      browsers:
          browsers ??
          (openBrowser == null && Platform.isWindows
              ? const WindowsBrowserLauncher()
              : const NoBrowserLauncher()),
      disposeLedger: ledger.dispose,
      // **業務は同期を知らない。** 同じ台帳と同じ素性を渡すだけで、繋がりは outbox の一点である。
      domain: domain,
      engine: engine,
      refresh: mode.autoRefreshAllowed
          ? RefreshLoop(
              // **世代変更は旗にして握る。** `RefreshLoop` の catch は warning を出すだけで、
              // 画面へは届かない。再 throw しない — 旗のほうが情報が残る。
              run: (trigger) async {
                // **別アカウントに繋がっていれば通常同期を止める。** 読めなければ判定せず
                // そのまま進む（[_checkAccountIdentity]）。
                //
                // **照合は起動時・前面復帰・手動だけにする**（2026-10-08）。別アカウントへ
                // 繋ぐのはサインインの操作で、その後は起動時の run が走る。30 秒周期と業務更新
                // ごとに `about.get` を足さない。**旗が立っている間は照合しない回も止める。**
                final identity = readyComposition;
                if (identity != null) {
                  final check = trigger == RefreshTrigger.startup ||
                      trigger == RefreshTrigger.resume ||
                      trigger == RefreshTrigger.manual;
                  if (check) {
                    if (!await identity._checkAccountIdentity()) return;
                  } else if (identity._accountMismatch != null) {
                    return;
                  }
                }
                try {
                  final result = await engine.run('run', now: nowUtc());
                  // **世代を確かめられなかった回は旗を下ろさない。** 認可切れでは先へ進むが
                  // （`SyncEngine` の run）、起点へ戻れたわけではない。
                  if (result.generation.state != generationUnknown) {
                    readyComposition?._clearGenerationChanged();
                  }
                  readyComposition?._afterRun(result);
                } on GenerationChangedError catch (error) {
                  readyComposition?._markGenerationChanged(error);
                } catch (_) {
                  // **失敗でも読み直させる。** 失敗の前に適用したコミットは残っている
                  // （§2「同期での適用」）。
                  readyComposition?._notifyStatus();
                  rethrow;
                }
              },
              // **初回起動の2択が済むまで回さない。** `run()` は
              // `useGeneration(establish: true)` を通るので、起点が無ければ置いてしまう。
              // **外殻のゲート（`Composition.bootReady`）と同じ述語である。**
              ready: () => _setupComplete(session.db),
              enabled: settings.autoRefreshEnabled,
              interval: Duration(seconds: settings.autoRefreshSeconds),
            )
          : null,
    );

    readyComposition = composition;
    composition._fixture = fixture;
    composition.fixtureReport = report;
    if (report != null) {
      _log.info('demo.ready', {
        ...report.toJson(),
        'session_id': deviceId,
        'ledger': mode.demo.name,
        'db_path': session.path,
      });
    }
    composition._attachLifecycle();
    composition._watchBrowserLink();
    // **組み上がった端末が何を持っているか。** 外殻のゲートが開くか、外部取得の口が
    // 使えるか（キーの値は出さない）、周期リフレッシュを登録したか。
    // **「取りに行かなかった」を後から切り分けられるようにする** — カーリルの図書館候補は
    // まだ合成していないので、`calil_library=false` がそのまま出る。
    _log.fine('app.composed', {
      'gate': composition.bootReady,
      'calil_usable': composition.calilKey.usable,
      'calil_library': false,
      'refresh': composition.refresh != null,
    });
    return composition;
  } catch (_) {
    client.close();
    ledger.session.close();
    ledger.dispose();
    rethrow;
  }
}

/// 受信口を選ぶ。**端末を足すときに触る4箇所の1つである。**
///
/// Android は標準共有（`ACTION_SEND`）を受信 Activity が受け、単調増加の holder に置く。Windows
/// は `karita://share?url=…` の URI 起動で、`app_links` の stream に流れてくる。**どちらも
/// 「最新の1件を番号付きで持ち、Dart が取りに行く」形に揃えてある。**
///
/// **受信部を持たない端末でも口は繋ぐ。** 実装がまだ無い側は「届いていない」を返すので、起動は
/// 落ちない。
ShareInbox _shareInbox() =>
    Platform.isAndroid ? ChannelShareInbox() : AppLinksShareInbox();
