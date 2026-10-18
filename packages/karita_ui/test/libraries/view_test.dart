/// 図書館管理の画面。**設定から入り、詳細まで降りて、戻ってくるところを測る。**
///
/// 外殻ごと立てる（`KaritaShell`）— 図書館管理は設定タブの本文を置き換える形で出るので、
/// タブ切替・幅変更・戻るボタンの振る舞いは外殻を抜きにしては測れない。
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

const String _koto = 'Tokyo_Koto';
const String _sumida = 'Tokyo_Sumida';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    home = Directory.systemTemp.createTempSync('karita-lib-view-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
  });
  tearDown(() {
    app.close();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  /// 候補の取得だけを差し替えられるようにする。**通信そのものはクライアントの試験と live が
  /// 見る側で、ここが測るのは画面である。**
  ///
  /// **合成層に試験用の口を足さない** — 足すと製品に「差し替えられる合成」が生まれる。
  /// 差し込むのは Provider の側で、しかもこの1本だけである。
  ///
  /// **`List<Override>` と書けない。** Riverpod 3 は `Override` を export していないので、
  /// 差し込みは型を名乗らずに済む場所（下の list literal）で組む。
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Size size = const Size(400, 900),
    double scale = 1,
    Brightness brightness = Brightness.light,
    String candidatePref = '東京都',
    LibraryCandidates? candidates,
    Object? candidatesError,
    Future<int> Function()? refreshBranches,
    // **手入力欄の出し分けを測るために差す**（2026-09-18）。寸法の軸を使っているが、
    // 理由は寸法ではない — `Ctrl+V` が既定で効き、クリップボードが排他で失敗しうる端末か。
    PointerKind? pointer,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compositionProvider.overrideWithValue(app),
          if (refreshBranches != null)
            branchRefreshProvider(
              _koto,
            ).overrideWith((ref) => refreshBranches()),
          if (pointer != null)
            densityProvider.overrideWithValue(Density(pointer)),
          if (candidates != null || candidatesError != null)
            libraryCandidatesProvider(candidatePref).overrideWith(
              (ref) => candidatesError != null
                  ? Future<LibraryCandidates>.error(candidatesError)
                  : candidates!,
            ),
        ],
        child: MaterialApp(
          theme: _renderTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const RepaintBoundary(
            key: ValueKey('screen'),
            child: KaritaShell(),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KaritaShell)),
    );
    container.read(currentTabProvider.notifier).select(ShellTab.settings);
    await tester.pumpAndSettle();
    return container;
  }

  /// 設定の［図書館設定］行から一覧を開く。**専用の Navbar タブは無い。**
  Future<void> openLibraries(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, '設定'));
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester, String name) async {
    await openLibraries(tester);
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  /// Android の戻るボタン相当。**OS から `popRoute` が来た形にする。**
  Future<void> pressBack(WidgetTester tester) async {
    await WidgetsBinding.instance.handlePopRoute();
    await tester.pumpAndSettle();
  }

  group('導線', () {
    testWidgets('設定 → 一覧 → 詳細 → 常用館 と降り、［戻る］で戻る', (tester) async {
      final container = await pump(tester);
      expect(find.text('設定'), findsWidgets);

      await openLibraries(tester);
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.list,
      );
      expect(find.text('図書館'), findsOneWidget);

      await tester.tap(find.text('東京都江東区'));
      await tester.pumpAndSettle();
      expect(container.read(librariesRouteProvider).systemId, _koto);

      await tester.tap(find.text('常用館登録'));
      await tester.pumpAndSettle();
      expect(find.text('常用館'), findsWidgets);

      for (final screen in [
        LibrariesScreen.detail,
        LibrariesScreen.list,
        LibrariesScreen.closed,
      ]) {
        await tester.tap(find.byTooltip('戻る'));
        await tester.pumpAndSettle();
        expect(container.read(librariesRouteProvider).screen, screen);
      }
      // 設定画面へ戻っている。
      expect(find.text('テーマ'), findsOneWidget);
    });

    testWidgets('専用の Navbar タブを増やしていない（4つのままである）', (tester) async {
      await pump(tester);
      await openLibraries(tester);
      expect(ShellTab.values.length, 4);
      expect(find.text('本棚'), findsOneWidget);
    });

    testWidgets('戻るボタンは設定タブに居るときだけ図書館管理が受ける', (tester) async {
      final container = await pump(tester);
      await openDetail(tester, '東京都江東区');

      // 本棚タブへ移る。**IndexedStack は設定タブの PopScope も生かしたままである。**
      container.read(currentTabProvider.notifier).select(ShellTab.bookshelf);
      await tester.pumpAndSettle();
      await pressBack(tester);
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.detail,
        reason: '別のタブの戻る操作を図書館管理が飲まない',
      );

      container.read(currentTabProvider.notifier).select(ShellTab.settings);
      await tester.pumpAndSettle();
      await pressBack(tester);
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.list,
      );
    });

    testWidgets('タブ切替と幅変更で画面を保つ', (tester) async {
      final container = await pump(tester);
      await openDetail(tester, '東京都江東区');

      container.read(currentTabProvider.notifier).select(ShellTab.reserve);
      await tester.pumpAndSettle();
      container.read(currentTabProvider.notifier).select(ShellTab.settings);
      await tester.pumpAndSettle();
      expect(find.text('東京都江東区'), findsWidgets);

      // 440dp を跨いでレールへ入れ替える。
      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();
      expect(
        container.read(librariesRouteProvider),
        const LibrariesRouteState.detail(_koto),
      );
      tester.view.physicalSize = const Size(400, 900);
      await tester.pumpAndSettle();
      expect(
        container.read(librariesRouteProvider),
        const LibrariesRouteState.detail(_koto),
      );
    });

    testWidgets('本文は設定タブの最大幅（560）で止まる', (tester) async {
      await pump(tester, size: const Size(1200, 900));
      await openLibraries(tester);
      expect(
        tester.getSize(find.byKey(const ValueKey('libraries-content'))).width,
        ShellTab.settings.contentMaxWidth,
      );
    });
  });

  group('一覧', () {
    testWidgets('都道府県 → 名称順に並び、常用館とマイページの出典を出す', (tester) async {
      await pump(tester);
      await openLibraries(tester);

      final names = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .where((text) => text.startsWith('東京都'))
          .toList();
      expect(names, ['東京都墨田区', '東京都江戸川区', '東京都江東区', '東京都港区', '東京都葛飾区']);

      // fixture は各区の branches.first を常用館にし、墨田だけ空にしてある。
      expect(find.text('常用館：江東区立こどもプラザ図書館'), findsOneWidget);
      expect(find.text('常用館：未設定'), findsOneWidget);
      // 江東だけ取り込み値、他4区は既定値表。
      expect(find.text('マイページ：取り込み値'), findsOneWidget);
      expect(find.text('マイページ：既定値'), findsNWidgets(4));
    });

    testWidgets('参照切れは「登録していた館が見つかりません」と出す', (tester) async {
      final container = await pump(tester);
      final koto = app.librarySystems.read(_koto)!;
      app.librarySystems.register(
        system: koto.copyWith(branches: [koto.branches.last]),
        now: nowUtc(),
      );
      await app.syncAfterDomainWrite();
      await tester.pumpAndSettle();

      await openLibraries(tester);
      expect(find.text('常用館：登録していた館が見つかりません'), findsOneWidget);
      expect(
        container.read(preferredBranchProvider(_koto)).state,
        PreferredBranchState.dangling,
      );
    });

    testWidgets('未登録は「登録した図書館はありません。」であり、失敗ではない', (tester) async {
      for (final id in app.loadLibraries().map((s) => s.id).toList()) {
        app.librarySystems.remove(systemId: id, now: nowUtc());
      }
      await app.syncAfterDomainWrite();
      await pump(tester);
      await openLibraries(tester);
      expect(find.text('登録した図書館はありません。'), findsOneWidget);
      expect(find.textContaining('読み込めません'), findsNothing);
    });

    testWidgets('読込失敗は未登録と別で、コードとメッセージを出せる', (tester) async {
      // **台帳が読めない端末を作る。** 偽の Provider を差し込むのではなく、実際に読めない
      // 台帳にして `loadLibraries()` の包みを通す。
      //
      // **開く前に壊す。** Riverpod 3 は、購読者が居る状態で再読込が失敗すると**前の値を
      // 保って背後で再試行する**（2026-09-17 実測）。後から壊すと、一覧は古い値を出したまま
      // になり、ここで測りたい「読めない端末の一覧」にならない。
      app.db.execute('DROP TABLE library_systems');
      await pump(tester);
      await openLibraries(tester);

      expect(find.text('図書館を読み込めません。'), findsWidgets);
      expect(
        find.text('登録した図書館はありません。'),
        findsNothing,
        reason: '読込失敗を未登録に変換しない',
      );

      await tester.tap(find.text('詳細').first);
      await tester.pumpAndSettle();
      // **コードとメッセージの2つだけである。** 例外の toString もパスも出さない。
      expect(find.textContaining('libraries-load'), findsOneWidget);
    });

    testWidgets('［図書館追加］は一覧のヘッダーにだけ出る', (tester) async {
      final container = await pump(tester);
      await openLibraries(tester);
      expect(find.widgetWithText(TextButton, '図書館追加'), findsOneWidget);

      await tester.tap(find.text('東京都江東区'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextButton, '図書館追加'),
        findsNothing,
        reason: '詳細のヘッダーには出ない',
      );
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.detail,
      );
    });
  });

  group('詳細', () {
    testWidgets('名称・常用館・マイページの出典と確認日を出す', (tester) async {
      await pump(tester);
      await openDetail(tester, '東京都江東区');
      expect(find.text('東京都江東区'), findsOneWidget);
      expect(find.text('江東区立こどもプラザ図書館'), findsOneWidget);
      // 確認日は取り込んだ日（デモは基準日）。**値そのものは fixture 由来なので固定しない。**
      expect(find.textContaining('取り込み値・'), findsOneWidget);
      expect(find.textContaining('確認'), findsOneWidget);
    });

    testWidgets('分館の一覧は出さない。分館が出るのは常用館を選ぶときだけである', (tester) async {
      await pump(tester);
      await openDetail(tester, '東京都江東区');
      // 常用館に選ばれていない側の分館は、詳細のどこにも出ない。
      expect(find.text('江東区立亀戸図書館'), findsNothing);
      expect(find.text('分館'), findsNothing);

      await tester.tap(find.text('常用館登録'));
      await tester.pumpAndSettle();
      expect(find.text('江東区立亀戸図書館'), findsOneWidget);
    });

    testWidgets('マイページの編集へ入れる', (tester) async {
      final container = await pump(tester);
      await openDetail(tester, '東京都江東区');
      await tester.tap(find.text('マイページ登録'));
      await tester.pumpAndSettle();
      expect(
        container.read(librariesRouteProvider),
        const LibrariesRouteState.mypageUrl(_koto),
      );
      expect(find.text('マイページ URL 登録'), findsOneWidget);
    });

    testWidgets('参照切れは詳細の現在値に出る', (tester) async {
      final koto = app.librarySystems.read(_koto)!;
      app.librarySystems.register(
        system: koto.copyWith(branches: [koto.branches.last]),
        now: nowUtc(),
      );
      await app.syncAfterDomainWrite();
      await pump(tester);
      await openDetail(tester, '東京都江東区');
      // **操作の名前は状態で変えない**（2026-09-18）。状態は現在値の行が出す。
      expect(find.text('常用館登録'), findsOneWidget);
      expect(find.text('登録していた館が見つかりません'), findsOneWidget);
    });

    testWidgets('見ている館が他端末で消えたら、そう出す。黙って一覧へ戻さない', (tester) async {
      final container = await pump(tester);
      await openDetail(tester, '東京都江東区');

      app.librarySystems.remove(systemId: _koto, now: nowUtc());
      await app.syncAfterDomainWrite();
      await tester.pumpAndSettle();

      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.detail,
        reason: '画面が黙って切り替わらない',
      );
      expect(find.textContaining('この図書館は登録されていません。'), findsOneWidget);

      await tester.tap(find.text('一覧へ戻る'));
      await tester.pumpAndSettle();
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.list,
      );
      expect(find.text('東京都江東区'), findsNothing);
    });
  });

  group('常用館', () {
    testWidgets('取得中も既存館を表示し、再入場は再利用、明示更新で再取得する', (tester) async {
      var calls = 0;
      final gate = Completer<int>();
      await pump(
        tester,
        refreshBranches: () {
          calls++;
          return calls == 1 ? gate.future : Future.value(0);
        },
      );
      await openDetail(tester, '東京都江東区');
      await tester.tap(find.text('常用館登録'));
      await tester.pump();
      await tester.pump();
      expect(find.text('分館リストを確認中…'), findsOneWidget);
      expect(find.text('江東区立亀戸図書館'), findsOneWidget);
      gate.complete(0);
      await tester.pumpAndSettle();
      expect(find.text('変更はありません'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('常用館登録'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('リストを更新'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
    testWidgets('選んで保存すると詳細へ戻り、一覧にも出る', (tester) async {
      final container = await pump(tester);
      await openDetail(tester, '東京都墨田区');
      await tester.tap(find.text('常用館登録'));
      await tester.pumpAndSettle();
      expect(find.text('現在：未設定'), findsOneWidget);

      await tester.tap(find.text('墨田区立八広図書館'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.detail,
      );
      expect(find.text('墨田区立八広図書館'), findsWidgets);

      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('常用館：墨田区立八広図書館'), findsOneWidget);
    });

    testWidgets('未設定を選ぶと解除される', (tester) async {
      final container = await pump(tester);
      await openDetail(tester, '東京都江東区');
      await tester.tap(find.text('常用館登録'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('未設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(
        container.read(preferredBranchProvider(_koto)).state,
        PreferredBranchState.unset,
      );
    });

    testWidgets('キャンセルでは台帳を変えない', (tester) async {
      final container = await pump(tester);
      final before = container.read(preferredBranchProvider(_koto));
      await openDetail(tester, '東京都江東区');
      await tester.tap(find.text('常用館登録'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('江東区立亀戸図書館'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
      await tester.pumpAndSettle();

      expect(container.read(preferredBranchProvider(_koto)), before);
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.detail,
      );
    });

    testWidgets('編集中に選んでいた分館が消えたら、黙って上書きせず選び直させる', (tester) async {
      await pump(tester);
      await openDetail(tester, '東京都江東区');
      await tester.tap(find.text('常用館登録'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      final koto = app.librarySystems.read(_koto)!;
      app.librarySystems.register(
        system: koto.copyWith(branches: [koto.branches.last]),
        now: nowUtc(),
      );
      await app.syncAfterDomainWrite();
      await tester.pumpAndSettle();

      expect(find.text('選択していた分館がなくなりました。選び直してください。'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: '選び直すまで保存させない',
      );
    });

    testWidgets('分館が多くても保存が画面の外へ出ない（実測の最大21件）', (tester) async {
      // **デモ fixture の2分館は本番の規則ではない。** 自治体の分館は中央値7・最大21
      // （2026-09-17 の実カーリル実測）。**そこで器を選択リストの縦並びへ変えた**ので、
      // 下端の操作が流れてしまわないことを測る。
      final koto = app.librarySystems.read(_koto)!;
      app.librarySystems.register(
        system: koto.copyWith(
          branches: [
            for (var i = 0; i < 21; i++)
              Branch(
                id: 'calil:$i',
                calilLibkey: '館$i',
                name: '江東区立とても長い名前の図書館その$i',
              ),
          ],
        ),
        now: nowUtc(),
      );
      await app.syncAfterDomainWrite();

      await pump(tester, size: const Size(360, 640));
      await openDetail(tester, '東京都江東区');
      await tester.tap(find.text('常用館登録'));
      await tester.pumpAndSettle();

      // 21件は1画面に収まらない。**一覧はスクロールし、操作は下端に残る。**
      // （`ListView` の子が1つの `Column` なので木には全部居る。**画面の外に在ること**を
      // 位置で見る）
      expect(
        tester.getRect(find.text('江東区立とても長い名前の図書館その0')).top,
        lessThan(640),
      );
      expect(
        tester.getRect(find.text('江東区立とても長い名前の図書館その20')).top,
        greaterThan(640),
      );

      final save = find.widgetWithText(FilledButton, '保存');
      expect(save, findsOneWidget);
      final box = tester.getRect(save);
      expect(box.bottom, lessThanOrEqualTo(640));
      expect(box.top, greaterThan(0));

      await tester.scrollUntilVisible(
        find.text('江東区立とても長い名前の図書館その20'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      // スクロールしても操作は同じ場所に在る。
      expect(tester.getRect(find.widgetWithText(FilledButton, '保存')), box);
    });

    testWidgets('保存に失敗したら前の設定のままで、コードとメッセージが出る', (tester) async {
      final container = await pump(tester);
      await openDetail(tester, '東京都江東区');
      await tester.tap(find.text('常用館登録'));
      await tester.pumpAndSettle();

      // **業務が弾く値を直に渡す。** 画面の選択リストからは出せない値である。
      await container
          .read(preferredBranchSaveProvider.notifier)
          .save(_koto, 'calil:not-a-branch');
      await tester.pumpAndSettle();

      expect(find.textContaining('常用館を保存できませんでした'), findsOneWidget);
      expect(
        container.read(preferredBranchProvider(_koto)).state,
        PreferredBranchState.resolved,
      );
      await tester.tap(find.text('詳細').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('library-setting'), findsOneWidget);
    });
  });

  group('削除', () {
    testWidgets('確認に残るものの件数を出し、キャンセルでは消えない', (tester) async {
      final container = await pump(tester);
      await openDetail(tester, '東京都江東区');
      await tester.tap(find.widgetWithText(TextButton, '削除'));
      await tester.pumpAndSettle();

      final impact = container.read(libraryRemovalImpactProvider(_koto));
      expect(find.text('東京都江東区 を削除しますか？'), findsOneWidget);
      expect(
        find.text('この図書館で借りた記録 ${impact.loans} 件は残りますが、図書館名は表示されなくなります。'),
        findsOneWidget,
      );
      expect(find.text('棚卸の記録 1 件は残ります。'), findsOneWidget);
      expect(find.text('常用館とマイページ URLの設定は参照先を失います。'), findsOneWidget);
      expect(find.text('削除はほかの端末にも伝わります。'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
      await tester.pumpAndSettle();
      expect(container.read(librariesProvider).containsKey(_koto), isTrue);
    });

    testWidgets('実行すると一覧へ戻り、その館が消える', (tester) async {
      final container = await pump(tester);
      await openDetail(tester, '東京都墨田区');
      await tester.tap(find.widgetWithText(TextButton, '削除'));
      await tester.pumpAndSettle();
      // 確認ダイアログの［削除］。
      await tester.tap(find.widgetWithText(TextButton, '削除').last);
      await tester.pumpAndSettle();

      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.list,
      );
      expect(container.read(librariesProvider).containsKey(_sumida), isFalse);
      expect(find.text('東京都墨田区'), findsNothing);
      expect(find.text('東京都江東区'), findsOneWidget);
    });
  });

  group('図書館追加', () {
    LibrarySystemCandidate candidate(
      String systemId,
      String systemName,
      String city, {
      int branches = 2,
      // 実応答の値（2026-09-17 実測。`SMALL` / `MEDIUM` / `LARGE` / `BM` / `UNIV` / `SPECIAL`）。
      Set<String> categories = const {'SMALL'},
    }) => LibrarySystemCandidate(
      systemId: systemId,
      systemName: systemName,
      pref: '東京都',
      city: city,
      categories: categories,
      homepageUrl: 'https://example.invalid/$systemId',
      branches: [
        for (var i = 0; i < branches; i++)
          BranchCandidate(
            id: 'calil:$systemId-$i',
            libkey: '$systemName$i',
            name: '$systemName立第$i図書館',
          ),
      ],
    );

    Future<void> openAdd(WidgetTester tester) async {
      await openLibraries(tester);
      await tester.tap(find.widgetWithText(TextButton, '図書館追加'));
      await tester.pumpAndSettle();
    }

    Future<void> choosePref(WidgetTester tester) async {
      await tester.ensureVisible(find.text('東京都'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('東京都'));
      await tester.pumpAndSettle();
    }

    testWidgets('都道府県を先に選ぶ。**47件が出て、通信しない**', (tester) async {
      final container = await pump(tester);
      await openAdd(tester);
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.addPrefecture,
      );
      expect(find.text('都道府県'), findsOneWidget);
      expect(find.text('北海道'), findsOneWidget);
      // **47件は1画面に入らない。**  は遅延構築なので、末尾は送ってから見る。
      await tester.scrollUntilVisible(find.text('沖縄県'), 300);
      await tester.pumpAndSettle();
      expect(find.text('沖縄県'), findsOneWidget);
      expect(prefectures, hasLength(47));
    });

    testWidgets('県を選ぶと候補が出る。**公共が先、大学・専門が後**', (tester) async {
      await pump(
        tester,
        candidates: LibraryCandidates(
          systems: [
            candidate(
              'Univ_Kaiyodai',
              '東京海洋大学',
              '港区',
              categories: const {'UNIV'},
            ),
            candidate('Tokyo_Chiyoda', '東京都千代田区', '千代田区'),
          ],
        ),
      );
      await openAdd(tester);
      await choosePref(tester);

      expect(find.text('東京都'), findsOneWidget, reason: 'ヘッダーが県名になる');
      expect(find.text('東京都の図書館：2件'), findsOneWidget);
      final names = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((t) => t == '東京海洋大学' || t == '東京都千代田区')
          .toList();
      expect(names, ['東京都千代田区', '東京海洋大学']);
    });

    testWidgets('キーワードは端末側で即時に絞る。0件なら解除を出す', (tester) async {
      await pump(
        tester,
        candidates: LibraryCandidates(
          systems: [
            candidate('Tokyo_Chiyoda', '東京都千代田区', '千代田区'),
            candidate('Tokyo_Chuo', '東京都中央区', '中央区'),
          ],
        ),
      );
      await openAdd(tester);
      await choosePref(tester);

      await tester.enterText(find.byType(TextField), '千代田');
      await tester.pumpAndSettle();
      expect(find.text('1件 / 東京都の2件'), findsOneWidget);
      expect(find.text('東京都中央区'), findsNothing);

      await tester.enterText(find.byType(TextField), '見つからない語');
      await tester.pumpAndSettle();
      expect(find.text('0件 / 東京都の2件'), findsOneWidget);
      // **「無い」と「打ち間違い」を利用者が区別できるようにする**（2026-09-16 決定）。
      await tester.tap(find.widgetWithText(TextButton, '絞り込みを解除'));
      await tester.pumpAndSettle();
      expect(find.text('東京都の図書館：2件'), findsOneWidget);
    });

    testWidgets('［登録］で台帳に入り、一覧に出る。二度は押せない', (tester) async {
      final container = await pump(
        tester,
        candidates: LibraryCandidates(
          systems: [candidate('Tokyo_Chiyoda', '東京都千代田区', '千代田区')],
        ),
      );
      await openAdd(tester);
      await choosePref(tester);

      await tester.tap(find.widgetWithText(FilledButton, '登録'));
      await tester.pumpAndSettle();

      expect(
        container.read(librariesProvider).containsKey('Tokyo_Chiyoda'),
        isTrue,
      );
      // **登録の直後は常用館の選択へ進む。** 選ばずに戻ると、行に［常用館を選ぶ］が残る。
      expect(find.textContaining('受け取る常用館を選んでください'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(find.text('常用館を選ぶ'), findsOneWidget);
      expect(find.text('常用館：未設定'), findsOneWidget);
      // **二重追加しない。** 登録済みは無効化して、そう見せる。
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '登録済み'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.list,
      );
      expect(find.text('東京都千代田区'), findsOneWidget);
    });

    testWidgets('［登録］から続けて常用館を選ぶと、候補の行に常用館が出る', (tester) async {
      final container = await pump(
        tester,
        candidates: LibraryCandidates(
          systems: [candidate('Tokyo_Chiyoda', '東京都千代田区', '千代田区')],
        ),
      );
      await openAdd(tester);
      await choosePref(tester);

      await tester.tap(find.widgetWithText(FilledButton, '登録'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('東京都千代田区立第1図書館'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(
        container.read(preferredBranchProvider('Tokyo_Chiyoda')).branchId,
        'calil:Tokyo_Chiyoda-1',
      );
      // **候補の一覧へ戻る。** 図書館管理の詳細へは飛ばない。
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.addSearch,
      );
      expect(find.text('常用館：東京都千代田区立第1図書館'), findsOneWidget);
      expect(find.text('常用館を選ぶ'), findsNothing);
    });

    testWidgets('切り詰めを黙って隠さない', (tester) async {
      await pump(
        tester,
        candidates: LibraryCandidates(
          systems: [candidate('Tokyo_Chiyoda', '東京都千代田区', '千代田区')],
          truncated: true,
        ),
      );
      await openAdd(tester);
      await choosePref(tester);
      expect(find.text('図書館が多すぎて、一部しか取得できませんでした。'), findsOneWidget);
    });

    testWidgets('キーが空と通信失敗を、候補0件と同一視しない', (tester) async {
      await pump(
        tester,
        candidatesError: const AppIssue('calil-key-missing', 'no key'),
      );
      await openAdd(tester);
      await choosePref(tester);

      expect(find.textContaining('図書館を探せません'), findsOneWidget);
      expect(find.textContaining('0件'), findsNothing);
      await tester.tap(find.text('詳細').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('calil-key-missing'), findsOneWidget);
    });

    testWidgets('戻るは 候補 → 都道府県 → 一覧 と降りる', (tester) async {
      final container = await pump(
        tester,
        candidates: const LibraryCandidates(systems: []),
      );
      await openAdd(tester);
      await choosePref(tester);

      for (final screen in [
        LibrariesScreen.addPrefecture,
        LibrariesScreen.list,
        LibrariesScreen.closed,
      ]) {
        await tester.tap(find.byTooltip('戻る'));
        await tester.pumpAndSettle();
        expect(container.read(librariesRouteProvider).screen, screen);
      }
    });
  });

  group('マイページ URL 登録', () {
    Future<void> openMypage(WidgetTester tester, String name) async {
      await openDetail(tester, name);
      await tester.tap(find.text('マイページ登録'));
      await tester.pumpAndSettle();
    }

    /// 欄へ入れる。**貼り付けも手入力も同じ経路である**（2026-09-18）。
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }

    Finder save() => find.widgetWithText(FilledButton, '保存');
    Finder clearSave() => find.widgetWithText(FilledButton, '解除して保存');

    testWidgets('読み順は 今の値 → ブラウザーから登録 → 新しい URL である', (tester) async {
      await pump(tester);
      await openMypage(tester, '東京都墨田区');
      expect(find.text('マイページ URL 登録'), findsOneWidget);
      expect(find.textContaining('現在：既定値'), findsOneWidget);
      expect(find.text('ブラウザーから登録'), findsOneWidget);
      expect(
        find.text('ログイン画面からマイページ（利用状況）へ移動して、［karita に送る］を押してください。'),
        findsOneWidget,
      );
      expect(find.text('新しい URL'), findsOneWidget);
      // **取り込み・解除・破棄のボタンを置かない。** キャンセルと保存だけである。
      expect(find.widgetWithText(TextButton, '貼り付けから取り込む'), findsNothing);
      expect(find.widgetWithText(TextButton, '取り込み値を解除'), findsNothing);
      expect(find.widgetWithText(TextButton, '候補を捨てる'), findsNothing);
      expect(find.text('確認してから保存します。共有だけでは保存しません。'), findsNothing);
    });

    testWidgets('欄は両方の端末に出る', (tester) async {
      for (final pointer in PointerKind.values) {
        await pump(tester, pointer: pointer);
        await openMypage(tester, '東京都墨田区');
        expect(find.byType(TextField), findsOneWidget, reason: pointer.name);
        await tester.tap(find.byTooltip('戻る'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('戻る'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('戻る'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('欄へ入れて保存すると、出典が取り込み値になる', (tester) async {
      final container = await pump(tester);
      await openMypage(tester, '東京都墨田区');
      expect(
        tester.widget<FilledButton>(save()).onPressed,
        isNull,
        reason: '空で、取り込み値も無いので何もできない',
      );

      await type(tester, 'https://www.library.sumida.tokyo.jp/idcheck');
      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(
        container.read(mypageUrlProvider(_sumida)).source,
        MypageUrlSource.imported,
      );
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.detail,
      );
    });

    testWidgets('セッション付きは拒否し、理由を出して保存させない', (tester) async {
      final container = await pump(tester);
      await openMypage(tester, '東京都墨田区');
      await type(
        tester,
        'https://www.library.sumida.tokyo.jp/idcheck;jsessionid=abc',
      );

      expect(find.textContaining('セッション ID が含まれています'), findsOneWidget);
      expect(tester.widget<FilledButton>(save()).onPressed, isNull);
      expect(
        container.read(mypageUrlProvider(_sumida)).source,
        MypageUrlSource.bundled,
        reason: '台帳は変わらない',
      );
    });

    testWidgets('URL として読めない文字列は保存させない', (tester) async {
      await pump(tester);
      await openMypage(tester, '東京都墨田区');
      await type(tester, 'これは URL ではない');
      expect(find.text('URL として読み取れません。'), findsOneWidget);
      expect(tester.widget<FilledButton>(save()).onPressed, isNull);
    });

    testWidgets('別ホストでも警告せず保存できる', (tester) async {
      final container = await pump(tester);
      await openMypage(tester, '東京都墨田区');
      await type(tester, 'https://opac.example.net/login');

      expect(find.textContaining('が異なります'), findsNothing);
      await tester.tap(save());
      await tester.pumpAndSettle();
      // **外部 OPAC への正常な遷移でも起こる。** 一律に拒否しない。
      expect(
        container.read(mypageUrlProvider(_sumida)).value,
        'https://opac.example.net/login',
      );
    });

    testWidgets('空にして保存すると解除になる。既定値には解除を出さない', (tester) async {
      final container = await pump(tester);
      // 墨田は既定値表から引いている。**解除する保存値が無い。**
      await openMypage(tester, '東京都墨田区');
      expect(clearSave(), findsNothing);
      expect(tester.widget<FilledButton>(save()).onPressed, isNull);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('戻る'));
        await tester.pumpAndSettle();
      }

      // 江東だけ取り込み値を持つ fixture である。
      await openMypage(tester, '東京都江東区');
      await type(tester, '');
      expect(find.text('空のまま保存すると、取り込んだ値を解除して既定値に戻します。'), findsOneWidget);
      await tester.tap(clearSave());
      await tester.pumpAndSettle();

      // **「未設定」ではなく、既定値表へ戻る。**
      expect(
        container.read(mypageUrlProvider(_koto)).source,
        MypageUrlSource.bundled,
      );
    });

    testWidgets('キャンセルでは台帳を変えない', (tester) async {
      final container = await pump(tester);
      final before = container.read(mypageUrlProvider(_sumida));
      await openMypage(tester, '東京都墨田区');
      await type(tester, 'https://www.library.sumida.tokyo.jp/idcheck');
      await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
      await tester.pumpAndSettle();

      expect(container.read(mypageUrlProvider(_sumida)), before);
      await tester.tap(find.text('マイページ登録'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
        reason: '捨てた候補を持ち越さない',
      );
    });

    testWidgets('開く先が無ければ開けない', (tester) async {
      final container = await pump(tester);
      // 既定値も公式サイトも持たない館を作る。
      container
          .read(compositionProvider)
          .librarySystems
          .register(
            system: const LibrarySystem(
              id: 'Tokyo_Chuo',
              pref: '東京都',
              city: '中央区',
              name: '東京都中央区',
              branches: [
                Branch(id: 'calil:1', calilLibkey: '京橋', name: '中央区立京橋図書館'),
              ],
            ),
            now: nowUtc(),
          );
      await app.syncAfterDomainWrite();
      await tester.pumpAndSettle();

      await openMypage(tester, '東京都中央区');
      expect(find.textContaining('現在：未設定'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '図書館サイトを開く'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('開く先がありません。図書館を登録し直すと公式サイトが入ります。'), findsOneWidget);
    });

    testWidgets('見ている館が他端末で消えたら、そう出す', (tester) async {
      await pump(tester);
      await openMypage(tester, '東京都江東区');
      app.librarySystems.remove(systemId: _koto, now: nowUtc());
      await app.syncAfterDomainWrite();
      await tester.pumpAndSettle();
      expect(find.textContaining('この図書館は登録されていません。'), findsOneWidget);
    });
  });

  group('読みやすさ', () {
    testWidgets('狭幅・文字拡大で横にはみ出さない', (tester) async {
      await pump(tester, size: const Size(360, 900), scale: 1.6);
      await openDetail(tester, '東京都港区');
      // 長い分館名（港区男女平等参画センター｢リーブラ｣図書資料室）が入っている区である。
      expect(tester.takeException(), isNull);
      for (final box in tester.renderObjectList<RenderBox>(find.byType(Text))) {
        expect(box.size.width, lessThanOrEqualTo(360));
      }
    });

    testWidgets('暗いテーマでも地の色と同じ色で書かない', (tester) async {
      await pump(tester, brightness: Brightness.dark);
      await openLibraries(tester);
      final context = tester.element(find.byType(LibrariesView));
      final scheme = Theme.of(context).colorScheme;
      final styles = tester
          .widgetList<Text>(find.text('東京都江東区'))
          .map(
            (text) =>
                text.style?.color ?? DefaultTextStyle.of(context).style.color,
          );
      expect(styles, isNotEmpty);
      for (final color in styles) {
        expect(color, isNotNull);
        expect(color, isNot(scheme.surface));
      }
    });
  });

  testWidgets('実描画の確認用画像（指定時だけ保存）', (tester) async {
    final output = Platform.environment['KARITA_TEST_RENDER'];
    if (output == null) return;
    await _loadRenderFonts();

    for (final brightness in [Brightness.light, Brightness.dark]) {
      final container = await pump(
        tester,
        size: const Size(480, 900),
        brightness: brightness,
        // 追加画面を撮るぶん。**通信しない。**
        candidates: LibraryCandidates(
          systems: [
            for (final row in const [
              ('Tokyo_Chiyoda', '東京都千代田区', '千代田区', 'SMALL'),
              ('Tokyo_Chuo', '東京都中央区', '中央区', 'SMALL'),
              ('Univ_Kaiyodai', '東京海洋大学', '港区', 'UNIV'),
            ])
              LibrarySystemCandidate(
                systemId: row.$1,
                systemName: row.$2,
                pref: '東京都',
                city: row.$3,
                categories: {row.$4},
                branches: const [
                  BranchCandidate(id: 'calil:1', libkey: 'a', name: '第1図書館'),
                  BranchCandidate(id: 'calil:2', libkey: 'b', name: '第2図書館'),
                ],
              ),
          ],
        ),
      );
      final route = container.read(librariesRouteProvider.notifier);
      final name = brightness.name;
      Future<void> shoot(String label) async {
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('screen')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output/libraries-$label-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      // **2周目は同じ ProviderScope を使い回す。** `pumpWidget` は要素を更新するだけなので、
      // 1周目の画面状態が残る。タップではなく状態を直に置いて撮る。
      route.openList();
      await shoot('list');
      route.openDetail(_koto);
      await shoot('detail');
      route.openPreferredBranch(_koto);
      await shoot('branch');
      route.openMypageUrl(_koto);
      await shoot('mypage');
      route.openAdd();
      await shoot('add-prefecture');
      route.openAddSearch('東京都');
      await shoot('add-search');
      route.back();
      route.back();
      route.back();
    }
  });
}

/// 実描画に日本語と Material のアイコンを載せる。**通常の試験では読み込まない。**
Future<void> _loadRenderFonts() async {
  final font = FontLoader(_renderFamily)
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('C:/Windows/Fonts/meiryo.ttc').readAsBytesSync(),
        ),
      ),
    );
  await font.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File(
            'C:/flutter/bin/cache/artifacts/material_fonts/'
            'MaterialIcons-Regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

const String _renderFamily = 'LibrariesRender';

/// 画像を出すときだけ日本語フォントを差す。**製品のテーマは触らない。**
ThemeData _renderTheme(Brightness brightness) {
  final theme = karitaTheme(brightness);
  return Platform.environment['KARITA_TEST_RENDER'] == null
      ? theme
      : theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: _renderFamily),
        );
}
