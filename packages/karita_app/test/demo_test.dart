/// デモの差し替え。**合成層の1箇所に閉じていることを測る。**
///
/// 正本は `非公開資料:demo-mode.md`、受入 ID は
/// `非公開資料:demo-mode-acceptance.md`（DM-04 / DM-10 / DM-11 / DM-14）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';

void main() {
  group('旗の読み取り', () {
    test('既定は off', () {
      expect(AppMode.resolve(demo: 'off').demo, DemoMode.off);
      expect(AppMode.resolve(demo: 'off').isDemo, isFalse);
    });

    test('memory と temp を採る', () {
      expect(AppMode.resolve(demo: 'memory').demo, DemoMode.memory);
      expect(AppMode.resolve(demo: 'TEMP').demo, DemoMode.temp);
    });

    test('読めない値は起動エラー。本番へ戻さない', () {
      expect(() => AppMode.resolve(demo: 'sample'), throwsFormatException);
    });

    test('空文字は「未指定」である。不正値ではない', () {
      // `--dart-define-from-file` は `KARITA_DEMO=` の空の値もそのまま渡す。落とすと、
      // `.env` を雛形から作った人の手元で起動しなくなる。
      expect(AppMode.resolve(demo: '').demo, DemoMode.off);
      expect(AppMode.resolve(demo: '  ').isDemo, isFalse);
      expect(AppMode.resolve(demo: 'off', seed: '').seed, isNull);
    });

    test('ログの最初の行で本番と見分けられる', () {
      expect(AppMode.resolve(demo: 'off').toLogFields()['mode'], 'production');
      expect(AppMode.resolve(demo: 'memory').toLogFields()['mode'], 'demo');
      expect(AppMode.resolve(demo: 'temp').toLogFields()['ledger'], 'temp');
      expect(AppMode.resolve(demo: 'off').toLogFields().containsKey('seed'),
          isFalse);
    });
  });

  group('種（KARITA_SEED）', () {
    AppMode seeded({bool releaseMode = false, bool mobile = false}) =>
        AppMode.resolve(
          demo: 'off',
          seed: 'standard',
          releaseMode: releaseMode,
          mobile: mobile,
        );

    test('デモとは直交する。本番のまま種だけが立つ', () {
      final mode = seeded();
      expect(mode.demo, DemoMode.off);
      expect(mode.isDemo, isFalse);
      expect(mode.seed, 'standard');
      expect(mode.seedMode, isTrue);
      // **検証モードは本番である。** 操作入口は素通りし、周期リフレッシュも回る。
      expect(mode.gate.open, isTrue);
      expect(mode.autoRefreshAllowed, isTrue);
    });

    test('ガード① Android・iOS では立たない（データ領域を分けられない）', () {
      // **`KARITA_HOME` を渡す経路が無く、アプリの領域は1つしかない。** 種を撒けば実データの
      // 台帳を消すことになるので、Android・iOS は同期で受ける側に固定する。
      expect(() => seeded(mobile: true), throwsStateError);
    });

    test('ガード② release ビルドでは受け付けない', () {
      expect(() => seeded(releaseMode: true), throwsStateError);
    });

    test('ガード③ 本番のデータ領域には撒けない。**行き先そのもので見る**', () {
      const env = {'LOCALAPPDATA': r'C:\Users\x\AppData\Local'};
      // 既定の本番領域。**`KARITA_HOME` で明示しても止まる** — 守るのは「明示したか」では
      // なく「消してよい台帳か」である。
      expect(
        () => refuseSeedOnProductionHome(
          r'C:\Users\x\AppData\Local\Karita',
          environment: env,
        ),
        throwsStateError,
      );
      // 大文字小文字と区切りの違いでは抜けられない。
      expect(
        () => refuseSeedOnProductionHome(
          r'c:/users/x/appdata/local/karita\',
          environment: env,
        ),
        throwsStateError,
      );
      // 別の場所は通る。
      refuseSeedOnProductionHome(seedHome(), environment: env);
      refuseSeedOnProductionHome(r'C:\tmp\verify', environment: env);
    });

    test('種の既定の置き場所は OS の一時領域の下で、名前が固定である', () {
      // **固定の名前である。** `token.json` と `credentials/` を跨いで残すため、デモの
      // 一時台帳（`karita-demo-<乱数>`）とは違う形にしてある。
      expect(seedHome(), startsWith(Directory.systemTemp.path));
      expect(seedHome(), endsWith('karita-verify'));
      expect(seedHome(), seedHome());
    });

    test('デモに種を足しても、台帳の作り直しもシナリオの上書きも起きない', () {
      // デモは自分の起動準備で fixture を入れる。**消してよい本番の台帳がそこに無い。**
      final mode = AppMode.resolve(
        demo: 'memory',
        seed: 'standard',
        releaseMode: false,
        mobile: false,
      );
      expect(mode.seed, 'standard');
      expect(mode.seedMode, isFalse);
    });

    test('この起動が種入りだったことがログから読める', () {
      expect(seeded().toLogFields()['seed'], 'standard');
      expect(seeded().toLogFields()['mode'], 'production');
    });
  });

  group('対象外の操作', () {
    test('本番では素通りする', () async {
      var called = false;
      final attempt = await AppMode.resolve(demo: 'off').gate.run(() async {
        called = true;
        return 1;
      });
      expect(called, isTrue);
      expect(attempt.wasSkipped, isFalse);
      expect(attempt.value, 1);
    });

    test('デモでは本体を呼ばない（DM-04）', () async {
      var called = false;
      final attempt = await AppMode.resolve(demo: 'memory').gate.run(() async {
        called = true;
        return 1;
      });
      // **通信もファイル操作も始まっていない。**
      expect(called, isFalse);
      expect(attempt.wasSkipped, isTrue);
      expect(attempt.skipped, SkipReason.demoMode);
    });

    test('飛ばした結果を読むと落ちる', () {
      const attempt = Attempt<int>.skipped(SkipReason.demoMode);
      expect(() => attempt.value, throwsStateError);
    });

    test('デモは自動同期を登録しない（DM-05）', () {
      expect(AppMode.resolve(demo: 'memory').autoRefreshAllowed, isFalse);
      expect(AppMode.resolve(demo: 'temp').autoRefreshAllowed, isFalse);
      expect(AppMode.resolve(demo: 'off').autoRefreshAllowed, isTrue);
    });
  });

  group('業務DBの保管方式', () {
    late Directory home;
    late AppPaths paths;

    setUp(() {
      home = Directory.systemTemp.createTempSync('karita-demo-ledger-');
      paths = WindowsAppPaths.at(home.path);
    });
    tearDown(() {
      if (home.existsSync()) home.deleteSync(recursive: true);
    });

    test('本番はファイル台帳を開く', () {
      final ledger = openLedger(DemoMode.off, paths);
      addTearDown(ledger.session.close);
      expect(File(paths.dbPath).existsSync(), isTrue);
    });

    test('memory は本番DBを作らない（DM-11）', () {
      final ledger = openLedger(DemoMode.memory, paths);
      addTearDown(ledger.session.close);
      migrate(ledger.session.db, now: '2026-09-14T00:00:00Z');
      expect(File(paths.dbPath).existsSync(), isFalse);
    });

    test('temp は本番と分けた場所に置き、終了後に残さない（DM-10）', () {
      final ledger = openLedger(DemoMode.temp, paths);
      migrate(ledger.session.db, now: '2026-09-14T00:00:00Z');
      expect(File(paths.dbPath).existsSync(), isFalse);
      ledger.session.close();
      ledger.dispose();
    });

    test('デモの認可は呼ばれたら落ちる', () async {
      expect(
        const DemoAccessTokenProvider().accessToken(),
        throwsA(isA<TransportAuthError>()),
      );
    });

    test('デモの環境検査は書けるかだけを見る', () async {
      final report = await DemoEnvironmentDoctor(paths).check();
      expect(report.checked, {DoctorCheck.homeWritable});
      expect(report.notChecked, contains(DoctorCheck.credentials));
      expect(report.failed, isFalse);
    });
  });
}
