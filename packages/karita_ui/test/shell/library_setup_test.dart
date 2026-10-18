/// 図書館の登録を促す段。**出す条件と、出ている間の操作を測る。**
///
/// 足場は `shell_test.dart` と同じデモ合成である。**台帳の件数と同期の状態は差し込む** —
/// 「同期が一巡した後の0件」を本物の同期で作ると、時間に依存する。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition composition;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-library-setup-');
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

  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    required bool empty,
    required AppSyncStatus status,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compositionProvider.overrideWithValue(composition),
          if (empty) librariesProvider.overrideWithValue(const {}),
          syncStatusProvider.overrideWith((ref) => Stream.value(status)),
        ],
        child: MaterialApp(theme: ThemeData.light(), home: const KaritaShell()),
      ),
    );
    await tester.pump();
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(KaritaShell)));
  }

  const synced = AppSyncStatus(
    state: AppSyncState.synced,
    lastSuccessAt: '2026-10-01T00:00:00Z',
  );

  testWidgets('同期が一巡して0件なら、登録を促す。ヘッダーに必要な旨を出す', (tester) async {
    await pumpShell(tester, empty: true, status: synced);
    expect(find.byType(LibrarySetupScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('図書館を登録してください'), findsOneWidget);
    expect(find.text('karita を使い始めるには、図書館の登録が必要です。'), findsOneWidget);
    // 1段目は県を選ぶ。
    expect(find.text('図書館を探す都道府県を選んでください。'), findsOneWidget);
  });

  testWidgets('まだ一度も取り込めていなければ促さない（他端末の登録が未着かもしれない）', (tester) async {
    await pumpShell(
      tester,
      empty: true,
      status: const AppSyncStatus(state: AppSyncState.unsent),
    );
    expect(find.byType(LibrarySetupScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('同期中は促さない', (tester) async {
    await pumpShell(
      tester,
      empty: true,
      status: const AppSyncStatus(
        state: AppSyncState.syncing,
        lastSuccessAt: '2026-10-01T00:00:00Z',
      ),
    );
    expect(find.byType(LibrarySetupScreen), findsNothing);
  });

  testWidgets('登録済みなら促さない', (tester) async {
    await pumpShell(tester, empty: false, status: synced);
    expect(find.byType(LibrarySetupScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('［あとで］でタブへ進む。この起動のあいだは戻らない', (tester) async {
    final container = await pumpShell(tester, empty: true, status: synced);
    await tester.tap(find.text('あとで'));
    await tester.pump();
    expect(find.byType(LibrarySetupScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(container.read(libraryEnsureProvider), isFalse);
  });

  testWidgets('1段目の戻る矢印で終わる', (tester) async {
    final container = await pumpShell(tester, empty: true, status: synced);
    await tester.tap(find.byTooltip('戻る'));
    await tester.pump();
    expect(find.byType(LibrarySetupScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(container.read(libraryEnsureProvider), isFalse);
  });

  testWidgets('1件登録しても閉じない。終えるのは［完了］か戻る矢印である', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    final registered = NotifierProvider<_Registered, Map<String, LibrarySystem>>(
      _Registered.new,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compositionProvider.overrideWithValue(composition),
          librariesProvider.overrideWith((ref) => ref.watch(registered)),
          syncStatusProvider.overrideWith((ref) => Stream.value(synced)),
        ],
        child: MaterialApp(theme: ThemeData.light(), home: const KaritaShell()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(LibrarySetupScreen), findsOneWidget);

    // 登録が1件入る（画面の外から）。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KaritaShell)),
    );
    container.read(registered.notifier).fill(composition.loadLibraries());
    await tester.pump();
    await tester.pump();

    expect(find.byType(LibrarySetupScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('完了'), findsOneWidget);

    await tester.tap(find.byTooltip('戻る'));
    await tester.pump();
    expect(find.byType(LibrarySetupScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('県を選ぶと2段目へ進み、戻るで1段目へ帰る', (tester) async {
    await pumpShell(tester, empty: true, status: synced);
    await tester.tap(find.text('北海道'));
    await tester.pump();
    expect(find.text('図書館を探す都道府県を選んでください。'), findsNothing);
    // ヘッダーは選んだ県になるが、必要な旨は出し続ける。
    expect(find.text('karita を使い始めるには、図書館の登録が必要です。'), findsOneWidget);
    await tester.tap(find.byTooltip('戻る'));
    await tester.pump();
    expect(find.text('図書館を探す都道府県を選んでください。'), findsOneWidget);
  });
}

/// 台帳の代わり。**画面の外から登録が入ったことを作る。**
class _Registered extends Notifier<Map<String, LibrarySystem>> {
  @override
  Map<String, LibrarySystem> build() => const {};

  void fill(List<LibrarySystem> systems) =>
      state = {for (final system in systems) system.id: system};
}
