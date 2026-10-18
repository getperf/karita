/// 外殻。**ゲートが開くこと・幅で形が入れ替わること・選択が保たれることを測る。**
///
/// 足場は `karita_app` のデモ（`DemoMode.memory`）である
/// （`非公開資料:ui-state-model.md` §4 段階1）。**デモは台帳に fixture があるのに
/// `localGeneration` が `null`** なので、ゲートが本番の述語をそのまま書いていればここで閉じる。
///
/// **合成は `setUp` で立てる。** `testWidgets` の本体は fake async の中を走るので、そこで
/// `compose()` を待つと asset の読み出しが返らずに固まる。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

/// 下部 Navbar 側。**Android スマホの上限 412 の内側。**
const Size _phone = Size(400, 800);

/// レール側。**probe の最小 Window 幅（予約 460）。**
const Size _window = Size(460, 800);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition composition;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-shell-');
    composition = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
  });
  tearDown(() {
    composition.close();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  /// 幅を変える。**`tester.view` は物理ピクセルなので、倍率を 1 に固定して論理 px で書く。**
  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pump();
  }

  /// 差し込みは名前で受ける。**`Override` は flutter_riverpod 3 が export していない。**
  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    Size size = _phone,
    bool? bootReady,
    Density? density,
    Brightness brightness = Brightness.light,
    AppSyncStatus? sync,
  }) async {
    await resize(tester, size);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compositionProvider.overrideWithValue(composition),
          if (bootReady != null) bootReadyProvider.overrideWithValue(bootReady),
          if (density != null) densityProvider.overrideWithValue(density),
          if (sync != null) ...[
            syncStatusProvider.overrideWith((ref) => Stream.value(sync)),
            // **本番では同じ旗から来る**（`Composition._generationChanged`）。片方だけ
            // 立てると、ダイアログの選択の先頭に「合わせる」が出ない。
            backupFactsProvider.overrideWithValue(
              AppBackupFacts(generationChanged: sync.generationChanged != null),
            ),
            // **［合わせる］で開く復元のダイアログが保管先を読まない。** デモの合成は
            // 一覧を持たないので、空を返す。
            restoreCandidatesProvider.overrideWith(
              (ref) async => const AppBackupListing(items: []),
            ),
          ],
        ],
        child: MaterialApp(
          // **`ThemeData(brightness: …)` では配色が入れ替わらない** — 既定の配色が明暗の
          // どちらにも出る。明暗を測るので `light()` / `dark()` を直に渡す。
          theme: brightness == Brightness.dark
              ? ThemeData.dark()
              : ThemeData.light(),
          home: const KaritaShell(),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byType(KaritaShell)));
  }

  group('起動ゲート', () {
    testWidgets('デモでは開く（台帳に世代が無くても）', (tester) async {
      await pumpShell(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('karita をはじめる'), findsNothing);
    });

    testWidgets('閉じている間は Navbar もレールも出さない', (tester) async {
      await pumpShell(tester, bootReady: false);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      // **行き先は初回起動の画面1つである**（2026-09-23。段階5 の段2）。
      // 中の段（サインイン／2択／一覧）は `test/first_run/` が見る。
      expect(find.byType(FirstRunScreen), findsOneWidget);
      expect(find.text('karita をはじめる'), findsOneWidget);
    });

    testWidgets('レールの幅でも、閉じていれば出さない', (tester) async {
      await pumpShell(tester, size: _window, bootReady: false);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('開くと4タブが出る（4つ目は設定）', (tester) async {
      await pumpShell(tester);
      expect(ShellTab.values, hasLength(4));
      expect(ShellTab.values.last, ShellTab.settings);
      for (final tab in ShellTab.values) {
        expect(find.text(tab.label), findsOneWidget, reason: tab.name);
      }
    });
  });

  group('幅で形が入れ替わる', () {
    testWidgets('閾値の内側は下部 Navbar', (tester) async {
      await pumpShell(tester, size: const Size(shellRailBreakpoint - 1, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('閾値ちょうどはレール', (tester) async {
      await pumpShell(tester, size: const Size(shellRailBreakpoint, 800));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('probe の最小 Window 幅（460）はレール', (tester) async {
      await pumpShell(tester, size: _window);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('Android スマホの上限（412）は下部 Navbar', (tester) async {
      await pumpShell(tester, size: const Size(412, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('選択状態は1つである', () {
    testWidgets('起動は常に先頭（予約）。ui.lastTab を読まない', (tester) async {
      final container = await pumpShell(tester);
      expect(container.read(currentTabProvider), ShellTab.reserve);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        ShellTab.reserve.index,
      );
    });

    testWidgets('下部 Navbar で選ぶと状態が動く', (tester) async {
      final container = await pumpShell(tester);
      await tester.tap(find.text('本棚'));
      await tester.pumpAndSettle();
      expect(container.read(currentTabProvider), ShellTab.bookshelf);
    });

    testWidgets('レールで選ぶと同じ状態が動く', (tester) async {
      final container = await pumpShell(tester, size: _window);
      await tester.tap(find.text('設定'));
      await tester.pumpAndSettle();
      expect(container.read(currentTabProvider), ShellTab.settings);
    });

    testWidgets('幅が変わっても選択は保たれる', (tester) async {
      final container = await pumpShell(tester);
      await tester.tap(find.text('貸出し'));
      await tester.pumpAndSettle();

      await resize(tester, _window);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(container.read(currentTabProvider), ShellTab.lending);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        ShellTab.lending.index,
      );

      // 戻しても同じである。**写しているのではなく、はじめから1つしかない。**
      await resize(tester, _phone);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        ShellTab.lending.index,
      );
    });
  });

  group('幅で切り替わっても本文を初期化しない', () {
    /// 本文の Element。**作り直されれば別の instance になる。**
    ///
    /// `IndexedStack` は選んでいない行き先も build するので `skipOffstage: false` で拾う。
    Element bodyOf(WidgetTester tester, ShellTab tab) =>
        tester.element(find.byKey(ValueKey(tab), skipOffstage: false));

    testWidgets('下部 Navbar ⇄ レールで Element が同じである', (tester) async {
      await pumpShell(tester);
      final before = bodyOf(tester, ShellTab.reserve);

      await resize(tester, _window);
      expect(find.byType(NavigationRail), findsOneWidget);
      // **GlobalKey を付けた subtree は、新しい親へ同じ Element のまま移る。**
      // 付け忘れると Element が捨てられ、State も Draft も初期化される。
      expect(identical(bodyOf(tester, ShellTab.reserve), before), isTrue);

      await resize(tester, _phone);
      expect(identical(bodyOf(tester, ShellTab.reserve), before), isTrue);
    });

    testWidgets('選んでいない行き先も生きたままである', (tester) async {
      await pumpShell(tester);
      final bookshelf = bodyOf(tester, ShellTab.bookshelf);

      await resize(tester, _window);
      await tester.tap(find.text('本棚'));
      await tester.pumpAndSettle();

      expect(identical(bodyOf(tester, ShellTab.bookshelf), bookshelf), isTrue);
    });
  });

  group('本文の最大幅', () {
    testWidgets('予約は 520、貸出し・本棚は 640', (tester) async {
      await pumpShell(tester);
      expect(ShellTab.reserve.contentMaxWidth, 520);
      expect(ShellTab.lending.contentMaxWidth, 640);
      expect(ShellTab.bookshelf.contentMaxWidth, 640);
    });

    testWidgets('広い Window では最大幅で止まる', (tester) async {
      await pumpShell(tester, size: const Size(1200, 800));
      expect(
        tester.getSize(find.byKey(const ValueKey(ShellTab.reserve))).width,
        ShellTab.reserve.contentMaxWidth,
      );
    });

    testWidgets('狭い Window では幅いっぱいである', (tester) async {
      await pumpShell(tester);
      expect(
        tester.getSize(find.byKey(const ValueKey(ShellTab.reserve))).width,
        _phone.width,
      );
    });
  });

  group('密度はポインタで切る。幅ではない', () {
    testWidgets('触る端末は 44px のままである（幅 800 のレールでも）', (tester) async {
      final container = await pumpShell(
        tester,
        size: const Size(800, 1200),
        density: const Density(PointerKind.touch),
      );
      // **レール側に入っても密度は下がらない。** Android タブレットがここである。
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(container.read(densityProvider).control, 44);
    });

    testWidgets('指さない端末は詰める', (tester) async {
      final container = await pumpShell(
        tester,
        size: const Size(800, 1200),
        density: const Density(PointerKind.precise),
      );
      expect(container.read(densityProvider).control, 32);
    });

    testWidgets('下部 Navbar の高さはポインタで変わる（描けること込み）', (tester) async {
      // **precise で 440dp を切るのは、Window を probe の最小（460）より縮めたときだけ
      // である。** 値は仮なので、少なくとも溢れずに描けることを測る。
      await pumpShell(tester, density: const Density(PointerKind.precise));
      expect(
        tester.getSize(find.byType(NavigationBar)).height,
        const Density(PointerKind.precise).navigationBarHeight,
      );

      await pumpShell(tester, density: const Density(PointerKind.touch));
      expect(
        tester.getSize(find.byType(NavigationBar)).height,
        const Density(PointerKind.touch).navigationBarHeight,
      );
    });

    testWidgets('レールは 44px に収まる（インジケータを落としてある）', (tester) async {
      await pumpShell(tester, size: _window);
      expect(
        tester.getSize(find.byType(NavigationRail)).width,
        const Density(PointerKind.precise).railWidth,
      );
    });

    testWidgets('OS からの決まり方（全枝）', (tester) async {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          densityFor(platform).pointer,
          PointerKind.touch,
          reason: platform.name,
        );
      }
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(
          densityFor(platform).pointer,
          PointerKind.precise,
          reason: platform.name,
        );
      }
    });
  });

  group('レールの文字とアイコンが読めること', () {
    NavigationRail railOf(WidgetTester tester) =>
        tester.widget<NavigationRail>(find.byType(NavigationRail));

    testWidgets('色が落ちていない（4つとも）', (tester) async {
      // **2026-09-16 に実機で踏んだ。** 素の `TextStyle(fontSize: …)` を渡すと Material が
      // 持っていた色ごと消え、**白地に白**になってラベルが読めなかった。
      // **寸法だけを変えたいときも `copyWith` にする。**
      await pumpShell(tester, size: _window);
      final rail = railOf(tester);
      expect(rail.selectedLabelTextStyle?.color, isNotNull);
      expect(rail.unselectedLabelTextStyle?.color, isNotNull);
      expect(rail.selectedIconTheme?.color, isNotNull);
      expect(rail.unselectedIconTheme?.color, isNotNull);
    });

    testWidgets('寸法は probe のままである', (tester) async {
      await pumpShell(tester, size: _window);
      final rail = railOf(tester);
      final density = const Density(PointerKind.precise);
      expect(rail.selectedLabelTextStyle?.fontSize, density.railLabelSize);
      expect(rail.selectedIconTheme?.size, density.railIconSize);
    });

    testWidgets('地の色と同じ色で書かない', (tester) async {
      await pumpShell(tester, size: _window);
      final rail = railOf(tester);
      final background = Theme.of(
        tester.element(find.byType(NavigationRail)),
      ).colorScheme.surface;
      for (final color in [
        rail.selectedLabelTextStyle?.color,
        rail.unselectedLabelTextStyle?.color,
        rail.selectedIconTheme?.color,
        rail.unselectedIconTheme?.color,
      ]) {
        expect(color, isNot(background));
      }
    });

    testWidgets('明暗で色が入れ替わる（テーマに追従する）', (tester) async {
      // **`MaterialApp` はテーマを `AnimatedTheme` で 200ms かけて移す。** pump 直後は
      // 前のテーマが残っているので、測る前に落ち着かせる。
      await pumpShell(tester, size: _window);
      await tester.pumpAndSettle();
      final light = railOf(tester);
      final lightSelected = light.selectedLabelTextStyle?.color;
      final lightUnselected = light.unselectedLabelTextStyle?.color;

      await pumpShell(tester, size: _window, brightness: Brightness.dark);
      await tester.pumpAndSettle();
      final dark = railOf(tester);

      // **外殻は色を1つも持たない。** 配色（`ColorScheme`）から採っているので、テーマの選択
      // （`device.json` の `ui.theme`）は外殻を触らずに効く。
      expect(dark.selectedLabelTextStyle?.color, isNot(lightSelected));
      expect(dark.unselectedLabelTextStyle?.color, isNot(lightUnselected));
      expect(dark.selectedIconTheme?.color, isNotNull);
      expect(dark.unselectedIconTheme?.color, isNotNull);
    });

    testWidgets('暗いテーマでも地の色と同じ色で書かない', (tester) async {
      await pumpShell(tester, size: _window, brightness: Brightness.dark);
      final rail = railOf(tester);
      final background = Theme.of(
        tester.element(find.byType(NavigationRail)),
      ).colorScheme.surface;
      expect(rail.selectedLabelTextStyle?.color, isNot(background));
      expect(rail.unselectedLabelTextStyle?.color, isNot(background));
    });

    testWidgets('現在地とそれ以外を色で見分けられる', (tester) async {
      await pumpShell(tester, size: _window);
      final rail = railOf(tester);
      // **インジケータを落としてあるので、色と太さだけが現在地を示す。**
      expect(
        rail.selectedLabelTextStyle?.color,
        isNot(rail.unselectedLabelTextStyle?.color),
      );
      expect(
        rail.selectedIconTheme?.color,
        isNot(rail.unselectedIconTheme?.color),
      );
    });
  });

  group('共通ヘッダーを持たない', () {
    testWidgets('AppBar がどちらの形にも無い', (tester) async {
      await pumpShell(tester);
      expect(find.byType(AppBar), findsNothing);
      await resize(tester, _window);
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('世代変更の帯は全画面に出る', () {
    const issue = AppIssue('generation-changed', '同期世代が変わりました。');
    const stopped = AppSyncStatus(
      state: AppSyncState.synced,
      generationChanged: issue,
    );

    /// 「合わせる」の行が選ばれているか。**行は非公開の器に包まれているので、中の
    /// [ListTile] を見る。**
    bool rejoinSelected(WidgetTester tester) => tester
        .widget<ListTile>(
          find.descendant(
            of: find.byKey(const ValueKey('restore-rejoin')),
            matching: find.byType(ListTile),
          ),
        )
        .selected;

    Future<void> select(ProviderContainer container, ShellTab tab) async {
      container.read(currentTabProvider.notifier).select(tab);
    }

    for (final size in [_phone, _window]) {
      testWidgets('予約・貸出し・本棚に出て、設定では二重にならない（幅 ${size.width}）', (tester) async {
        final container = await pumpShell(tester, size: size, sync: stopped);
        await tester.pump();
        for (final tab in ShellTab.values) {
          await select(container, tab);
          await tester.pump();
          expect(
            find.text(generationChangedNotice),
            findsOneWidget,
            reason: tab.name,
          );
          expect(
            find.byKey(const ValueKey('shell-generation-notice')),
            tab == ShellTab.settings ? findsNothing : findsOneWidget,
            reason: tab.name,
          );
        }
      });
    }

    testWidgets('旗が無ければ出さない', (tester) async {
      await pumpShell(
        tester,
        sync: const AppSyncStatus(state: AppSyncState.synced),
      );
      await tester.pump();
      expect(find.text(generationChangedNotice), findsNothing);
      expect(
        find.byKey(const ValueKey('shell-generation-notice')),
        findsNothing,
      );
    });

    testWidgets('帯には［手順］［詳細］だけを置く（合わせるは手順の中）', (tester) async {
      await pumpShell(tester, sync: stopped);
      await tester.pump();
      final notice = find.byKey(const ValueKey('shell-generation-notice'));
      expect(
        find.descendant(of: notice, matching: find.byType(TextButton)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: notice, matching: find.text('合わせる')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('generation-steps')), findsOneWidget);
    });

    testWidgets('［手順］は設定から辿る道を書き、そこからも合わせられる', (tester) async {
      await pumpShell(tester, sync: stopped);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('generation-steps')));
      await tester.pumpAndSettle();

      expect(find.text('同期が停止しています'), findsOneWidget);
      expect(find.textContaining('［設定］を開き'), findsOneWidget);
      expect(find.textContaining('変更は失われます'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('generation-steps-rejoin')));
      await tester.pumpAndSettle();
      expect(find.text('同期が停止しています'), findsNothing);
      expect(find.byType(RestoreDialog), findsOneWidget);
      expect(rejoinSelected(tester), isTrue);
      // **確認画面は飛ばさない。** 1回目の［復元］は影響の確認へ進むだけである。
      await tester.tap(find.byKey(const ValueKey('restore-proceed')));
      await tester.pump();
      expect(find.text('選択: 別の端末で復元されたデータ'), findsOneWidget);
    });
  });
}
