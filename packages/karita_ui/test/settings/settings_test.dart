import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

ThemeData renderTheme(Brightness brightness) {
  final theme = karitaTheme(brightness);
  return Platform.environment['KARITA_TEST_RENDER'] == null
      ? theme
      : theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'SettingsRender'),
        );
}

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
    if (Platform.environment['KARITA_TEST_RENDER'] != null) {
      final font = FontLoader('SettingsRender')
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
                'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
    }
    home = Directory.systemTemp.createTempSync('karita-settings-ui-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
  });
  tearDown(() {
    app.close();
    home.deleteSync(recursive: true);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    AppSyncState? sync,
    Size size = const Size(400, 800),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compositionProvider.overrideWithValue(app),
          if (sync != null)
            syncStatusProvider.overrideWith(
              (ref) => Stream.value(
                AppSyncStatus(
                  state: sync,
                  issue: const AppIssue('sample-code', 'Sample error message.'),
                ),
              ),
            ),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: renderTheme(Brightness.light),
            darkTheme: renderTheme(Brightness.dark),
            themeMode: ref.watch(themeModeProvider),
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
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KaritaShell)),
    );
    container.read(currentTabProvider.notifier).select(ShellTab.settings);
    await tester.pumpAndSettle();
    return container;
  }

  test('不正値の読み取りは system', () {
    expect(themeModeFor('unknown'), ThemeMode.system);
    expect(themeModeFor('light'), ThemeMode.light);
    expect(themeModeFor('dark'), ThemeMode.dark);
  });

  testWidgets('選択から保存・配色反映、2回以上の変更と再起動用の保存値', (tester) async {
    final container = await pump(tester);
    for (final entry in {
      'ダーク': ThemeMode.dark,
      'ライト': ThemeMode.light,
      'システムに合わせる': ThemeMode.system,
    }.entries) {
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key).last);
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), entry.value);
      expect(DeviceSettings.read(app.paths.configDir).theme, entry.value.name);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        entry.value,
      );
    }
  });

  testWidgets('保存失敗では前の配色・選択が残り、再試行できる', (tester) async {
    final container = await pump(tester);
    final blocked = Directory('${app.paths.configDir}/device.json')
      ..createSync();
    await container.read(themeSaveProvider.notifier).save('dark');
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(find.textContaining('テーマを保存できません'), findsOneWidget);
    blocked.deleteSync();
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('system は OS の明暗変更に追従し、明示選択は追従しない', (tester) async {
    final container = await pump(tester);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(SettingsView))).brightness,
      Brightness.dark,
    );
    await container.read(themeSaveProvider.notifier).save('light');
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(SettingsView))).brightness,
      Brightness.light,
    );
  });

  for (final state in AppSyncState.values) {
    testWidgets('同期表示 ${state.name}', (tester) async {
      await pump(tester, sync: state);
      final abnormal = [
        AppSyncState.appUpdateRequired,
        AppSyncState.signInRequired,
        AppSyncState.needsAttention,
      ].contains(state);
      expect(find.text('詳細'), abnormal ? findsOneWidget : findsNothing);
      if (abnormal) {
        await tester.tap(find.text('詳細'));
        await tester.pumpAndSettle();
        expect(find.text('sample-code\nSample error message.'), findsOneWidget);
      }
    });
  }

  testWidgets('狭幅・文字拡大・異常文でも横にはみ出さない', (tester) async {
    await pump(
      tester,
      sync: AppSyncState.needsAttention,
      size: const Size(360, 800),
      scale: 1.6,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('幅・タブ切替でテーマを保持、設定本文は560', (tester) async {
    final container = await pump(tester);
    await container.read(themeSaveProvider.notifier).save('dark');
    container.read(currentTabProvider.notifier).select(ShellTab.reserve);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1000, 800);
    container.read(currentTabProvider.notifier).select(ShellTab.settings);
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(
      tester.getSize(find.byKey(const ValueKey('settings-content'))).width,
      560,
    );
    expect(tester.getSize(find.byType(SettingsView)).width, greaterThan(560));
    expect(tester.takeException(), isNull);
  });

  test('明暗の文字色と primary 対のコントラスト', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    for (final brightness in Brightness.values) {
      final scheme = karitaTheme(brightness).colorScheme;
      expect(
        contrast(scheme.onSurface, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onSurfaceVariant, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('実描画の確認用画像（指定時だけ保存）', (tester) async {
    final output = Platform.environment['KARITA_TEST_RENDER'];
    if (output == null) return;
    final container = await pump(
      tester,
      sync: AppSyncState.needsAttention,
      size: const Size(480, 800),
    );
    for (final mode in ['light', 'dark']) {
      await container.read(themeSaveProvider.notifier).save(mode);
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('screen')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$output/settings-$mode.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
