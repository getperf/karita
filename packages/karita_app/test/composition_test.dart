/// 組み立て。**合成が通ることと、デモが本番の保存先へ触らないことを測る。**
///
/// harness が捕まえてきた不具合は、どれも**引数の組み方**だった（2026-09-04 の UUID、
/// 2026-09-05 の `branches: const []`）。P5a 以降その組み立ては全部ここに集まるので、
/// 通ること自体を試験に置く。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:logging/logging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late AppPaths paths;

  setUp(() {
    home = Directory.systemTemp.createTempSync('karita-compose-');
    paths = WindowsAppPaths.at(home.path);
    paths.ensure();
  });
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  Future<Composition> composeDemo([DemoMode demo = DemoMode.memory]) =>
      compose(
        paths: paths,
        settings: const DeviceSettings(),
        mode: AppMode(demo),
      );

  test('デモで組み上がる（DM-01 の合成の分）', () async {
    final composition = await composeDemo();
    addTearDown(composition.close);

    // 台帳は立ち、device_id は `<platform>-<uuid4>` である。
    expect(composition.deviceId, startsWith(Platform.operatingSystem));
    expect(composition.mode.isDemo, isTrue);
    expect(composition.auth.kind, 'demo');
    // **セットアップを省略しても、migration と台帳の前提は省略しない。**
    expect(latestVersion(), greaterThan(0));
  });

  test('デモは周期リフレッシュを登録しない（DM-05）', () async {
    final composition = await composeDemo();
    addTearDown(composition.close);
    expect(composition.refresh, isNull);
    // 環が無いので、業務更新直後のトリガも何も起こさない。
    await composition.syncAfterDomainWrite();
  });

  test('デモは本番の台帳を作らない（DM-11）', () async {
    final composition = await composeDemo();
    addTearDown(composition.close);
    expect(File(paths.dbPath).existsSync(), isFalse);
  });

  test('デモの操作入口は本体を呼ばない（DM-04）', () async {
    final composition = await composeDemo();
    addTearDown(composition.close);
    var called = false;
    final attempt = await composition.gate.run(() async => called = true);
    expect(called, isFalse);
    expect(attempt.wasSkipped, isTrue);
  });

  test('背面の口はあるが、実装は無い', () async {
    final composition = await composeDemo();
    addTearDown(composition.close);
    expect(composition.background.available, isFalse);
    await composition.background.register();
  });

  test('端末設定が壊れていたら合成層の所見になる', () async {
    final composition = await compose(
      paths: paths,
      settings: const DeviceSettings(issues: [
        DeviceSettingIssue(DeviceSettingProblem.unreadable, detail: 'broken'),
      ]),
      mode: const AppMode(DemoMode.memory),
    );
    addTearDown(composition.close);

    final report = composition.compositionDoctor();
    expect(report.checked,
        {DoctorCheck.deviceConfig, DoctorCheck.danglingReference});
    expect(report.findings.single.check, DoctorCheck.deviceConfig);
    expect(report.failed, isTrue);
  });


  test('マイページURLを出典つきで解決する（既定値表・取り込み値・公式サイト）', () async {
    final composition = await composeDemo();
    addTearDown(composition.close);

    // **江東だけ取り込み値を持たせてある。** 5区すべてに焼くと `既定値` が一度も出ない。
    final koto = composition.mypageUrlFor('Tokyo_Koto');
    expect(koto.source, MypageUrlSource.imported);
    expect(koto.checkedOn, isNotNull, reason: '取り込んだ日を出す');

    // 残り4区は保存値が無いので既定値表から引く。**焼き込まず実行時に引いている。**
    final minato = composition.mypageUrlFor('Tokyo_Minato');
    expect(minato.source, MypageUrlSource.bundled);
    expect(minato.value, contains('lib.city.minato.tokyo.jp'));
    expect(minato.checkedOn, equals(composition.mypageDefaults.checkedOn));
    expect(composition.mypageDefaults.length, 5);

    // 表に無い区は公式サイトへ落ちる。**マイページではないので一手余分にかかるが着地する。**
    composition.librarySystems.register(
      system: const LibrarySystem(
        id: 'Tokyo_Setagaya',
        pref: '東京都',
        city: '世田谷区',
        name: '世田谷区立図書館',
        homepageUrl: 'https://libweb.city.setagaya.tokyo.jp/',
        branches: [
          Branch(id: 'setagaya-main', calilLibkey: '世田谷中央', name: '中央館'),
        ],
      ),
      now: nowUtc(),
    );
    expect(composition.mypageUrlFor('Tokyo_Setagaya').source,
        MypageUrlSource.official);
    // 未登録は未設定である。
    expect(composition.mypageUrlFor('Tokyo_Nerima').source,
        MypageUrlSource.unset);
  });

  test('業務の参照切れを合成層が拾う。①② は業務集約を知らない', () async {
    // **分館が消えた常用館は正常に適用されうる。** 同期で届いた集約行は登録経路の検査を
    // 通らないので、拾えるのは診断の側だけである。
    final composition = await composeDemo();
    addTearDown(composition.close);

    expect(composition.compositionDoctor().failed, isFalse,
        reason: 'fixture の常用館は分館一覧に在る');

    // 分館を洗い替えて、常用館の指す先を消す。**カタログの洗い替えは利用者値に触れない。**
    final koto = composition.librarySystems.read('Tokyo_Koto')!;
    composition.librarySystems.register(
      system: koto.copyWith(branches: [koto.branches.last]),
      now: nowUtc(),
    );

    final report = composition.compositionDoctor();
    expect(report.failed, isTrue);
    expect(report.findings.single.check, DoctorCheck.danglingReference);
    expect(report.findings.single.detail, 'Tokyo_Koto/preferred_branch');
  });

  test('範囲外の値だけなら所見にしない', () async {
    final composition = await compose(
      paths: paths,
      settings: const DeviceSettings(issues: [
        DeviceSettingIssue(DeviceSettingProblem.valueIgnored,
            key: 'sync.autoRefreshSeconds', detail: '0'),
      ]),
      mode: const AppMode(DemoMode.memory),
    );
    addTearDown(composition.close);
    expect(composition.compositionDoctor().failed, isFalse);
  });

  test('本番では周期リフレッシュを持ち、起点が無いうちは回さない', () async {
    // 本番の経路は Desktop クライアントの資格情報を読む。**手で置くもの**なので、試験も
    // 同じ場所へ置く（`AppPaths.credentialsPath`）。
    File(paths.credentialsPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
          '{"installed": {"client_id": "x", "client_secret": "y"}}');

    final composition = await compose(
      paths: paths,
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.off),
    );
    addTearDown(composition.close);

    final refresh = composition.refresh;
    expect(refresh, isNotNull);
    expect(refresh!.enabled, isTrue);
    // **周期は 30 秒**（2026-10-08。`production-sync-small-changes.md`「前面同期の短縮」）。
    expect(refresh.interval, const Duration(seconds: 30));
    // **初回起動の2択が済むまで回さない。** 起点が無いので `run()` は呼ばれない。
    expect(await refresh.trigger(RefreshTrigger.startup), isFalse);
  });


  /// 本番の合成に要る最小の資格情報。**中身は読まれるが、通信はしない。**
  void putCredentials() {
    File(paths.credentialsPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '{"installed": {"client_id": "x", "client_secret": "y"}}',
      );
  }

  Future<Composition> composeProduction() => compose(
    paths: paths,
    settings: const DeviceSettings(),
    mode: const AppMode(DemoMode.off),
  );

  group('［アカウント］の3状態', () {
    test('トークンが無ければ未サインインである。**期限は見ない**', () async {
      putCredentials();
      final composition = await composeProduction();
      addTearDown(composition.close);

      final status = await composition.authStatus();
      expect(status.state, AppAuthState.signedOut);
      expect(status.available, isTrue);
      expect(status.kind, 'loopback-pkce');
    });

    test('トークンが在ればサインイン済みである', () async {
      putCredentials();
      // **期限切れのトークンでも「在る」である。** 切れていることは異常ではなく時計で、
      // refresh が回復させる（`WindowsEnvironmentDoctor` と同じ判断）。
      File(paths.tokenPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"access_token": "a", "refresh_token": "r", '
          '"expiry_utc": "2000-01-01T00:00:00Z"}',
        );
      final composition = await composeProduction();
      addTearDown(composition.close);

      expect((await composition.authStatus()).state, AppAuthState.signedIn);
    });

    test('デモでは操作できないと出る。**本体は呼ばれない**', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      final status = await composition.authStatus();
      expect(status.available, isFalse);
      expect(status.state, AppAuthState.signedOut);
      expect(status.kind, 'demo');

      // デモの `signIn` / `signOut` は呼ばれたら投げる。**`false` が返るのは、
      // 本体の手前で止めた証拠である。**
      expect(await composition.signIn(), isFalse);
      expect(await composition.signOut(), isFalse);
    });
  });

  group('［バックアップ］［復元］', () {
    test('2行の事実は台帳の端末ごとの記録から読む', () async {
      putCredentials();
      final composition = await composeProduction();
      addTearDown(composition.close);

      var facts = composition.backupFacts();
      expect(facts.lastBackupAt, isNull);
      expect(facts.lastRestoreAt, isNull);
      expect(facts.generationChanged, isFalse);
      expect(facts.available, isTrue);

      setState(composition.db, stateLastBackupAt, '2026-09-24T01:00:00Z');
      setState(composition.db, stateLastRestoreAt, '2026-09-24T02:00:00Z');
      setState(
        composition.db,
        stateLastRestoreCreatedAt,
        '2026-09-20T01:30:00Z',
      );
      setState(composition.db, stateLastRestorePlatform, 'android');
      facts = composition.backupFacts();
      expect(facts.lastBackupAt, '2026-09-24T01:00:00Z');
      expect(facts.lastRestoreAt, '2026-09-24T02:00:00Z');
      expect(facts.lastRestoreCreatedAt, '2026-09-20T01:30:00Z');
      expect(facts.lastRestorePlatform, 'android');
    });

    test('デモでは操作できないと出る。**本体は呼ばれない**', () async {
      final composition = await composeDemo(DemoMode.temp);
      addTearDown(composition.close);
      final token = composition.ledgerSessionToken;

      expect(composition.backupFacts().available, isFalse);
      // 本体まで行けば保管先へ出て落ちる。**`false` は手前で止めた証拠である。**
      expect(await composition.createBackup(), isFalse);
      expect(await composition.restoreFromBackup('b'), isFalse);
      expect(await composition.rejoinGeneration(), isFalse);
      expect(await composition.restoreEmpty(), isFalse);
      // 台帳は替わっていない。
      expect(identical(token, composition.ledgerSessionToken), isTrue);
    });
  });

  test('デモの起動ゲートは開く（台帳に世代が無くても）', () async {
    final composition = await composeDemo();
    addTearDown(composition.close);

    // **デモは `setupFresh` を通らない。** fixture は載っているのに世代は無い。
    expect(localGeneration(composition.db), isNull);
    expect(composition.librarySystems.load().librarySystems, hasLength(5));
    // それでも開く。**デモが省略する「起動準備」がこれである。**
    expect(composition.bootReady, isTrue);
  });

  test('本番の起動ゲートは、初回起動の2択が済むまで閉じている', () async {
    File(paths.credentialsPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
          '{"installed": {"client_id": "x", "client_secret": "y"}}');

    final composition = await compose(
      paths: paths,
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.off),
    );
    addTearDown(composition.close);

    expect(composition.bootReady, isFalse);

    // 世代が載れば開く。**周期リフレッシュの `ready:` と同じ述語である** — 2つの口が
    // 同じ1点で動く。
    setLocalGeneration(composition.db, 'gen-a', firstSeq);
    expect(composition.bootReady, isTrue);
    expect(await composition.refresh!.trigger(RefreshTrigger.startup), isTrue);
  });

  test('検証モードは種を撒き、起動ゲートは閉じたままである', () async {
    File(paths.credentialsPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
          '{"installed": {"client_id": "x", "client_secret": "y"}}');

    final composition = await compose(
      paths: paths,
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.off, seed: 'standard'),
    );
    addTearDown(composition.close);

    // **台帳はまだ空である**（2026-09-23。実機で踏んだ）。fixture は業務 API を通るので
    // `outbox_events` に行を残し、**`SyncEngine.isSetUp` が真になる。** そのまま2択を押すと
    // エンジンが `setup-already-done` で断るので、**種は `setupFresh()` の後に撒く。**
    expect(File(paths.dbPath).existsSync(), isTrue);
    expect(composition.fixtureReport, isNull);
    expect(composition.librarySystems.load().librarySystems, isEmpty);
    expect(
      composition.engine.isSetUp,
      isFalse,
      reason: '2択を押せる状態であること。ゲートの述語とエンジンの述語を食い違わせない',
    );

    // **デモではない。** 操作入口は素通りし、周期リフレッシュも回る。
    expect(composition.mode.isDemo, isFalse);
    expect(composition.gate.open, isTrue);
    expect(composition.refresh, isNotNull);

    // **ゲートは閉じている。** 検証で押したいのは `setupFresh` なので、2択の画面から入る。
    expect(localGeneration(composition.db), isNull);
    expect(composition.bootReady, isFalse);

    // 作り直しの操作入口は出さない（起動時に一度だけ走るものである）。
    expect(composition.resetDemo, throwsStateError);
  });

  test('検証モードの種は、世代ができた後に撒いても検証を通る', () async {
    // **2026-09-24 に実機で踏んだ。** 種を `setupFresh` の後へ移したのに、検証はデモの
    // 「世代0」を見続けていた。30冊を書いた直後に投げ、通知も同期の契機も飛んで、Windows の
    // 88件が一度も送られなかった。
    putCredentials();
    final composition = await compose(
      paths: paths,
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.off, seed: 'standard'),
    );
    addTearDown(composition.close);
    setLocalGeneration(composition.db, 'gen-a', firstSeq);

    final fixture = DemoFixture(
      await rootBundle.loadString(
        'packages/karita_app/assets/demo/standard.json',
      ),
      DateTime.now(),
    );
    final report = fixture.seed(
      composition.domain,
      now: nowUtc(),
      generations: 1,
    );
    expect(report.toJson()['passed'], isTrue);
    // デモの前提（世代0）のままなら落ちる。**その区別がこの引数である。**
    expect(() => fixture.verify(composition.db), throwsStateError);
  });

  test('デモは従来どおり起動時に種を撒く（2択を通らないため）', () async {
    final composition = await composeDemo();
    addTearDown(composition.close);

    // **デモはゲートを開けてしまうので、初回起動の2択を通らない。** 撒く場所は起動準備の
    // ままでよく、`isSetUp` が真でも困らない。
    expect(composition.fixtureReport?.counts['books'], 30);
    expect(composition.engine.isSetUp, isTrue);
    expect(composition.bootReady, isTrue);
  });

  test('検証モードは起動のたびに台帳を作り直し、台帳以外を消さない', () async {
    File(paths.credentialsPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
          '{"installed": {"client_id": "x", "client_secret": "y"}}');
    // **リセットが残すもの。** 消すと、毎回サインインし直しになり、ログ水準の設定が飛び、
    // 復元前の記録が読めなくなる。
    final token = File(paths.tokenPath)..writeAsStringSync('{"kept": true}');
    final deviceConfig =
        File(AppLayout.under(paths.configDir, AppLayout.deviceConfig))
          ..writeAsStringSync('{"log": {"level": "FINE"}}');
    final log = File(AppLayout.under(paths.logDir, AppLayout.logFile))
      ..writeAsStringSync('前の周回の記録\n');

    const seeded = AppMode(DemoMode.off, seed: 'standard');
    final first = await compose(
      paths: paths,
      settings: const DeviceSettings(),
      mode: seeded,
    );
    // 台帳に、次の起動まで残りうるものを書く。
    setLocalGeneration(first.db, 'gen-a', firstSeq);
    expect(first.bootReady, isTrue);
    first.close();

    // **2回目も2択から始まる。** リセットが無いと世代が残ってゲートが開いたままになり、
    // 撒く段（`setupFresh` の後）にも辿り着けない。
    final second = await compose(
      paths: paths,
      settings: const DeviceSettings(),
      mode: seeded,
    );
    addTearDown(second.close);
    expect(localGeneration(second.db), isNull);
    expect(second.bootReady, isFalse);
    expect(second.engine.isSetUp, isFalse, reason: '2択を押せる状態へ戻ること');

    expect(token.readAsStringSync(), contains('kept'));
    expect(deviceConfig.readAsStringSync(), contains('FINE'));
    expect(log.readAsStringSync(), contains('前の周回の記録'));
  });

  test('台帳の版が動いたら1行残す。二度目は出ない', () async {
    // **後から「いつ上がったか」を知る手段が SQL しか無かった。** migration は台帳の形を変える
    // 一度きりの事象なので、動いたときだけ記録する。
    final logHome = Directory.systemTemp.createTempSync('karita-migrate-log-');
    addTearDown(() {
      uninstallLogging();
      if (logHome.existsSync()) logHome.deleteSync(recursive: true);
    });
    installLogging(
        logDir: logHome.path, level: Level.INFO, format: LogFormat.text);
    String read() =>
        File(AppLayout.under(logHome.path, AppLayout.logFile)).readAsStringSync();

    // **本番の経路で同じ台帳を二度開く。** `temp` は毎回新しい台帳を作るので二度目が測れない。
    File(paths.credentialsPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
          '{"installed": {"client_id": "x", "client_secret": "y"}}');

    final first = await compose(
      paths: paths,
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.off),
    );
    expect(read(), contains('ledger.migrated'));
    expect(read(), contains('to=${latestVersion()}'));
    first.close();

    // 同じ台帳をもう一度開く。**版は動かないので出ない。**
    final before = read().length;
    final second = await compose(
      paths: paths,
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.off),
    );
    addTearDown(second.close);
    expect(read().substring(before), isNot(contains('ledger.migrated')));
  });

  test('ブラウザを開く口は合成層から出る', () async {
    final composition = await composeDemo();
    addTearDown(composition.close);
    // 実装（`rundll32.exe`）は合成層の中にあり、外へは関数だけが出る。
    expect(composition.openBrowser, isA<Future<void> Function(Uri)>());
  });

  group('ホスト逆引き（用途ヒント）', () {
    // fixture の5館。**`mypage-defaults.json` の実採取値と同じ。**
    // Tokyo_Koto だけ取り込み値（demo_fixture.dart の `_importedMypageUrl`）を持ち、残り4区は
    // 既定値表（`assets/libraries/mypage-defaults.json`）から引く。
    const hosts = {
      'Tokyo_Edogawa': 'www.library.city.edogawa.tokyo.jp',
      'Tokyo_Katsushika': 'www.lib.city.katsushika.lg.jp',
      'Tokyo_Koto': 'www.koto-lib.tokyo.jp',
      'Tokyo_Minato': 'www.lib.city.minato.tokyo.jp',
      'Tokyo_Sumida': 'www.library.sumida.tokyo.jp',
    };

    test('5館の imported/bundled ホストが衝突しない', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      // 5つとも異なるホストである（2026-09-28 検討の実証と同じ表）。
      expect(hosts.values.toSet().length, hosts.length);
      hosts.forEach((systemId, host) {
        expect(composition.systemIdsByMypageHost(host), [systemId],
            reason: systemId);
      });
    });

    test('official（公式サイト）のみでは逆引きしない', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      // 世田谷区は homepageUrl だけを持ち、imported/bundled を持たない
      // （`mypageUrlFor` は official へ落ちる、上の別試験と同じ登録）。
      composition.librarySystems.register(
        system: const LibrarySystem(
          id: 'Tokyo_Setagaya',
          pref: '東京都',
          city: '世田谷区',
          name: '世田谷区立図書館',
          homepageUrl: 'https://libweb.city.setagaya.tokyo.jp/',
          branches: [
            Branch(id: 'setagaya-main', calilLibkey: '世田谷中央', name: '中央館'),
          ],
        ),
        now: nowUtc(),
      );
      expect(composition.mypageUrlFor('Tokyo_Setagaya').source,
          MypageUrlSource.official);
      expect(composition.systemIdsByMypageHost('libweb.city.setagaya.tokyo.jp'),
          isEmpty);
    });

    test('一致0件・複数件は DistrictChoiceNeeded、一致1件は候補確定', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      final url = Uri.parse('https://${hosts['Tokyo_Koto']}/login');

      // 一致1件 → 候補確定（用途はヒントどおり）。
      final single = composition.triageOf(
        HandoffWebUrl(url),
        null,
        DeliveryPurposeHint.mypageUrl,
      );
      expect(single, isA<MypageTriageCandidate>());
      expect((single as MypageTriageCandidate).systemId, 'Tokyo_Koto');

      // 一致1件・lending ヒント → 貸出し候補確定（実機で拾えていなかった不具合の再現）。
      final singleLending = composition.triageOf(
        HandoffWebUrl(url),
        null,
        DeliveryPurposeHint.lending,
      );
      expect(singleLending, isA<LendingTriageCandidate>());
      expect((singleLending as LendingTriageCandidate).systemId, 'Tokyo_Koto');

      // 一致0件 → 地区選択。
      final none = composition.triageOf(
        HandoffWebUrl(Uri.parse('https://unknown.example/login')),
        null,
        DeliveryPurposeHint.lending,
      );
      expect(none, isA<DistrictChoiceNeeded>());
      expect((none as DistrictChoiceNeeded).systemIdChoices, isEmpty);
      expect(none.purpose, LaunchPurpose.lending);

      // 一致複数件 → 地区選択。江東と同じホストの館をもう1つ登録する。
      composition.librarySystems.register(
        system: const LibrarySystem(
          id: 'Tokyo_Koto2',
          pref: '東京都',
          city: '江東区',
          name: '江東区立図書館（テスト用の重複館）',
          homepageUrl: 'https://example.invalid/',
          branches: [Branch(id: 'dup-main', calilLibkey: '重複', name: '本館')],
        ),
        now: nowUtc(),
      );
      // homepageUrl（official）は逆引きの母集団に入らないので、取り込み値として同じホストを
      // 与える（`imported`/`bundled` のみを見る、という設計を守ったまま衝突させる）。
      await composition.saveMypageUrl('Tokyo_Koto2', url);
      final multiple = composition.triageOf(
        HandoffWebUrl(url),
        null,
        DeliveryPurposeHint.mypageUrl,
      );
      expect(multiple, isA<DistrictChoiceNeeded>());
      expect(
        (multiple as DistrictChoiceNeeded).systemIdChoices,
        containsAll(['Tokyo_Koto', 'Tokyo_Koto2']),
      );
    });

    test('一時保持と不一致のヒント → 古い地区を使わず再逆引きする', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      // 貸出しの用途で「江東区」を開いた一時保持があるが、ヒントは mypage_url。
      composition.handoff.remember(LaunchContext(
        purpose: LaunchPurpose.lending,
        systemId: 'Tokyo_Koto',
        host: hosts['Tokyo_Sumida']!,
        startedAt: DateTime.now(),
      ));
      final url = Uri.parse('https://${hosts['Tokyo_Sumida']}/login');
      final result = composition.triageOf(
        HandoffWebUrl(url),
        composition.handoff.launch,
        DeliveryPurposeHint.mypageUrl,
      );
      // 古い一時保持（江東・貸出し）は使わず、ヒント（マイページ）＋ホスト逆引き（墨田）を使う。
      expect(result, isA<MypageTriageCandidate>());
      expect((result as MypageTriageCandidate).systemId, 'Tokyo_Sumida');
    });

    test('目的が同じでもホストが違う一時保持は信用しない（実機で発生した不具合の再現）', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      // 何日も前に「江東区」を貸出し用途で開いた一時保持が残ったまま（期限を置かない設計）、
      // 今回は港区の URL が lending ヒント付きで届く。目的（lending）は一致するが、
      // ホストが違うので古い一時保持を信用してはいけない。
      composition.handoff.remember(LaunchContext(
        purpose: LaunchPurpose.lending,
        systemId: 'Tokyo_Koto',
        host: hosts['Tokyo_Koto']!,
        startedAt: DateTime.now().subtract(const Duration(days: 1)),
      ));
      final url = Uri.parse('https://${hosts['Tokyo_Minato']}/login');
      final result = composition.triageOf(
        HandoffWebUrl(url),
        composition.handoff.launch,
        DeliveryPurposeHint.lending,
      );
      expect(result, isA<LendingTriageCandidate>());
      expect((result as LendingTriageCandidate).systemId, 'Tokyo_Minato');
    });

    test('一時保持がありヒント無し・一致 → 一時保持をそのまま使う', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      composition.handoff.remember(LaunchContext(
        purpose: LaunchPurpose.lending,
        systemId: 'Tokyo_Koto',
        host: hosts['Tokyo_Koto']!,
        startedAt: DateTime.now(),
      ));
      final result = composition.triageOf(
        HandoffWebUrl(Uri.parse('https://${hosts['Tokyo_Koto']}/login')),
        composition.handoff.launch,
        null,
      );
      expect(result, isA<LendingTriageCandidate>());
      expect((result as LendingTriageCandidate).systemId, 'Tokyo_Koto');
    });

    test('一時保持もヒントも無い → PurposeChoiceNeeded', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      final result = composition.triageOf(
        HandoffWebUrl(Uri.parse('https://unknown.example/')),
        null,
        null,
      );
      expect(result, isA<PurposeChoiceNeeded>());
    });
  });

  // `非公開資料:amazon-share-handoff.md` §3 の表を1行ずつ。
  group('Amazon の受信', () {
    const www = 'www.amazon.co.jp';

    LaunchContext shelfLaunch({String? bookId}) => LaunchContext(
      purpose: LaunchPurpose.bookshelf,
      systemId: '',
      host: www,
      startedAt: DateTime.now(),
      bookId: bookId,
    );

    test('1: 本棚の記録あり → URL を見ずに元の画面へ', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      for (final bookId in [null, 'book-1']) {
        // 別の本（ISBN 付き）でも、ISBN の無いページでも同じ。
        for (final delivery in const [
          HandoffAmazon('9784274219337', AmazonShape.isbn10, www),
          HandoffAmazon(null, AmazonShape.asin, www),
        ]) {
          final result = composition.triageOf(
            delivery,
            shelfLaunch(bookId: bookId),
            null,
          );
          expect(result, isA<ShelfReturnCandidate>());
          expect((result as ShelfReturnCandidate).bookId, bookId);
        }
      }
    });

    test('2: 記録なし・本棚にある ISBN → その本', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      final book = composition.loadReservationBooks().firstWhere(
        (b) => b.isbn13 != null,
      );
      final result = composition.triageOf(
        HandoffAmazon(book.isbn13, AmazonShape.isbn10, www),
        null,
        null,
      );
      expect(result, isA<ShelfBookFound>());
      expect((result as ShelfBookFound).bookId, book.id);
    });

    test('3: 記録なし・本棚に無い ISBN → 下書き。source はホストだけ', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      const missing = '9784000000000';
      expect(normalizeIsbn13(missing), missing);
      expect(composition.findReservationBook(missing), isNull);
      final result = composition.triageOf(
        const HandoffAmazon(missing, AmazonShape.isbn10, www),
        null,
        null,
      );
      expect(result, isA<ShelfBookDraft>());
      final book = (result as ShelfBookDraft).book;
      expect(book.isbn13, missing);
      expect(book.source, Uri.parse('https://$www/'));
    });

    test('4: 記録なし・ISBN なし → notice', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      final result = composition.triageOf(
        const HandoffAmazon(null, AmazonShape.asin, www),
        null,
        null,
      );
      expect(result, isA<AmazonNoIsbn>());
      expect((result as AmazonNoIsbn).shape, AmazonShape.asin);
    });

    test('図書館の記録は Amazon の着地に使わない', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      final library = LaunchContext(
        purpose: LaunchPurpose.lending,
        systemId: 'Tokyo_Koto',
        host: www,
        startedAt: DateTime.now(),
      );
      expect(
        composition.triageOf(
          const HandoffAmazon(null, AmazonShape.other, www),
          library,
          null,
        ),
        isA<AmazonNoIsbn>(),
      );
    });

    test('本棚の記録は図書館の URL に使わない', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      final result = composition.triageOf(
        HandoffWebUrl(Uri.parse('https://$www/login')),
        shelfLaunch(),
        null,
      );
      expect(result, isA<PurposeChoiceNeeded>());
    });

    test('判定は記録を消さない（配送1件につき複数回呼ばれる）', () async {
      final composition = await composeDemo();
      addTearDown(composition.close);

      composition.handoff.remember(shelfLaunch(bookId: 'book-1'));
      for (var i = 0; i < 2; i++) {
        expect(
          composition.triageOf(
            const HandoffAmazon(null, AmazonShape.asin, www),
            composition.handoff.launch,
            null,
          ),
          isA<ShelfReturnCandidate>(),
        );
      }
    });

    test('openAmazon は開く前に記録し、失敗したら捨てる', () async {
      final opened = <Uri>[];
      var fail = false;
      final composition = await compose(
        paths: paths,
        settings: const DeviceSettings(),
        mode: AppMode(DemoMode.memory),
        openBrowser: (url) async {
          if (fail) throw StateError('no browser');
          opened.add(url);
        },
      );
      addTearDown(composition.close);

      final url = Uri.parse('https://$www/dp/427421933X');
      await composition.openAmazon(url, bookId: 'book-1');
      expect(opened, [url]);
      final launch = composition.handoff.launch!;
      expect(launch.purpose, LaunchPurpose.bookshelf);
      expect(launch.host, www);
      expect(launch.bookId, 'book-1');

      fail = true;
      await expectLater(composition.openAmazon(url), throwsStateError);
      expect(composition.handoff.launch, isNull);
    });

    test('選んだブラウザーで開き、開けなければ OS の既定で開き直す（2026-10-16）', () async {
      final viaDefault = <Uri>[];
      final launcher = _FakeLauncher();
      final composition = await compose(
        paths: paths,
        settings: const DeviceSettings(browserApp: 'chrome'),
        mode: AppMode(DemoMode.memory),
        openBrowser: (url) async => viaDefault.add(url),
        browsers: launcher,
      );
      addTearDown(composition.close);

      final url = Uri.parse('https://$www/dp/427421933X');
      await composition.openAmazon(url);
      expect(launcher.opened, [('chrome', url)]);
      expect(viaDefault, isEmpty);

      launcher.fail = true;
      await composition.openAmazon(url);
      expect(viaDefault, [url]);
      expect(composition.handoff.launch, isNotNull, reason: '開き直せたので記録は残す');
    });
  });
}

class _FakeLauncher implements BrowserLauncher {
  final opened = <(String, Uri)>[];
  bool fail = false;

  @override
  Future<Set<String>> installed() async => {'chrome'};

  @override
  Future<void> open(String choice, Uri url) async {
    if (fail) throw StateError('not found');
    opened.add((choice, url));
  }
}
