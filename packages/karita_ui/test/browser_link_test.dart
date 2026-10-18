/// ブラウザープラグインのインストールの段（2026-10-15）。**出す条件と、届いたことで終わることを測る。**
///
/// 連携の状態は差し込む。届いた確認ページを端末設定へ書くのは合成層で、ここが見るのは
/// 「どの状態でどの画面と操作を出すか」である。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

class _FakeLink extends BrowserLink {
  _FakeLink(this.initial);

  final BrowserLinkStatus initial;
  int skips = 0;

  @override
  BrowserLinkStatus build() => initial;

  void put(BrowserLinkStatus next) => state = next;

  @override
  void skip() {
    skips++;
    state = BrowserLinkStatus(
      applicable: state.applicable,
      linkedAt: state.linkedAt,
      skipped: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition composition;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    home = Directory.systemTemp.createTempSync('karita-browser-link-');
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

  const unlinked = BrowserLinkStatus(applicable: true);

  ProviderContainer containerWith(
    _FakeLink link, {
    Map<String, LibrarySystem>? libraries,
    Set<String>? installed,
  }) {
    final container = ProviderContainer(
      overrides: [
        compositionProvider.overrideWithValue(composition),
        browserLinkProvider.overrideWith(() => link),
        if (libraries != null) librariesProvider.overrideWithValue(libraries),
        if (installed != null)
          installedBrowsersProvider.overrideWith((ref) async => installed),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('出す条件', () {
    test('この起動でセットアップを済ませていなければ出さない（既存の端末に割り込まない）', () {
      final container = containerWith(_FakeLink(unlinked));
      expect(container.read(browserLinkEnsureProvider), isFalse);
    });

    test('セットアップを済ませた Windows の未確認の端末にだけ出す', () {
      final container = containerWith(_FakeLink(unlinked));
      container.read(setupCompletedThisSessionProvider.notifier).mark();
      expect(container.read(browserLinkEnsureProvider), isTrue);
    });

    test('確認済み・見送り済み・Windows 以外では出さない', () {
      for (final status in const [
        BrowserLinkStatus(applicable: true, linkedAt: '2026-10-15T00:00:00Z'),
        BrowserLinkStatus(applicable: true, skipped: true),
        BrowserLinkStatus(applicable: false),
      ]) {
        final container = containerWith(_FakeLink(status));
        container.read(setupCompletedThisSessionProvider.notifier).mark();
        expect(container.read(browserLinkEnsureProvider), isFalse);
      }
    });

    test('届いても、［次へ］を押すまで出し続ける', () {
      final link = _FakeLink(unlinked);
      final container = containerWith(link);
      container.read(setupCompletedThisSessionProvider.notifier).mark();
      expect(container.read(browserLinkEnsureProvider), isTrue);

      link.put(
        const BrowserLinkStatus(
          applicable: true,
          linkedAt: '2026-10-15T00:00:00Z',
        ),
      );
      expect(
        container.read(browserLinkEnsureProvider),
        isTrue,
        reason: '「つながりました」を読む前に画面を替えない',
      );
      container.read(browserLinkEnsureProvider.notifier).finish();
      expect(container.read(browserLinkEnsureProvider), isFalse);
    });
  });

  group('画面', () {
    Future<ProviderContainer> pump(
      WidgetTester tester,
      _FakeLink link, {
      bool standalone = false,
      Map<String, LibrarySystem>? libraries,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1000);
      addTearDown(tester.view.reset);
      final container = containerWith(link, libraries: libraries);
      container.read(setupCompletedThisSessionProvider.notifier).mark();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: BrowserLinkScreen(standalone: standalone)),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('初回は2つの段と待機を出し、逃げ道を残す', (tester) async {
      await pump(tester, _FakeLink(unlinked));

      expect(find.text('ブラウザープラグインのインストール'), findsOneWidget);
      expect(find.text('入れ方を開く'), findsOneWidget);
      expect(find.text('確認用ページを開く'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('browser-link-waiting')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('browser-link-start')),
        findsNothing,
        reason: '届くまで先へ進めない',
      );
      expect(find.text('プラグインなしで進む（あとで設定）'), findsOneWidget);
    });

    testWidgets('届いたら「つながりました」と［karita を始める］に替わる（図書館のある端末）', (tester) async {
      final link = _FakeLink(unlinked);
      final container = await pump(tester, link);

      link.put(
        const BrowserLinkStatus(
          applicable: true,
          linkedAt: '2026-10-15T00:00:00Z',
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('browser-link-arrived')),
        findsOneWidget,
      );
      expect(find.text('プラグインなしで進む（あとで設定）'), findsNothing);
      expect(find.text('karita を始める'), findsOneWidget, reason: 'デモの台帳には図書館がある');
      await tester.tap(find.byKey(const ValueKey('browser-link-start')));
      await tester.pump();
      expect(container.read(browserLinkEnsureProvider), isFalse);
    });

    testWidgets('図書館がまだ無い端末では［次へ］（この後に図書館の登録が続く）', (tester) async {
      final link = _FakeLink(unlinked);
      await pump(tester, link, libraries: const <String, LibrarySystem>{});
      link.put(
        const BrowserLinkStatus(
          applicable: true,
          linkedAt: '2026-10-15T00:00:00Z',
        ),
      );
      await tester.pump();
      expect(find.text('次へ'), findsOneWidget);
      expect(find.text('karita を始める'), findsNothing);
    });

    testWidgets('［プラグインなしで進む］は見送りを記録して終える', (tester) async {
      final link = _FakeLink(unlinked);
      final container = await pump(tester, link);

      await tester.tap(find.byKey(const ValueKey('browser-link-skip')));
      await tester.pump();

      expect(link.skips, 1);
      expect(container.read(browserLinkEnsureProvider), isFalse);
    });

    testWidgets('確かめ直す画面では、確認済みでも新しく届くまで「つながりました」にしない', (tester) async {
      final link = _FakeLink(
        const BrowserLinkStatus(
          applicable: true,
          linkedAt: '2026-10-01T00:00:00Z',
        ),
      );
      await pump(tester, link, standalone: true);

      expect(find.textContaining('この端末は確認済みです'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('browser-link-waiting')),
        findsOneWidget,
      );

      link.put(
        const BrowserLinkStatus(
          applicable: true,
          linkedAt: '2026-10-15T00:00:00Z',
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('browser-link-arrived')),
        findsOneWidget,
      );
      expect(find.text('閉じる'), findsOneWidget);
    });
  });

  group('入口', () {
    Future<void> pumpHome(
      WidgetTester tester,
      Widget home,
      _FakeLink link, {
      Set<String>? installed,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: containerWith(link, installed: installed),
          child: MaterialApp(home: Scaffold(body: home)),
        ),
      );
      await tester.pump();
    }

    testWidgets('予約画面の「カーリルで検索・予約して戻る」から、つなぐ画面へ入れる', (tester) async {
      await pumpHome(tester, const ReservationView(), _FakeLink(unlinked));
      await tester.tap(find.text('カーリルで検索・予約して戻る'));
      await tester.pumpAndSettle();

      expect(find.text('この端末ではブラウザープラグインをまだ確かめていません。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reservation-browser-link')));
      // **`pumpAndSettle` にしない。** 待機中の表示が回り続ける。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('ブラウザープラグイン'), findsOneWidget, reason: '確かめ直す画面として開く');
    });

    testWidgets('Windows 以外（Android・デモ）では入口を出さない', (tester) async {
      await pumpHome(
        tester,
        const ReservationView(),
        _FakeLink(const BrowserLinkStatus(applicable: false)),
      );
      await tester.tap(find.text('カーリルで検索・予約して戻る'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reservation-browser-link')),
        findsNothing,
      );
    });

    testWidgets('設定の「開くブラウザー」で、見つかったものだけを選べる（2026-10-16）', (tester) async {
      await pumpHome(
        tester,
        const SettingsView(contentMaxWidth: 800),
        _FakeLink(unlinked),
        installed: {'chrome'},
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-browser-choice')),
        findsOneWidget,
      );
      await tester.tap(find.text('システムの既定'));
      await tester.pumpAndSettle();
      expect(find.text('Edge（見つかりません）'), findsOneWidget);
      expect(find.text('Firefox（見つかりません）'), findsOneWidget);

      await tester.tap(find.text('Chrome').last);
      await tester.pumpAndSettle();
      expect(composition.browserChoice, 'chrome');
      expect(find.text('Chrome'), findsOneWidget);
    });

    testWidgets('Windows 以外では「開くブラウザー」を出さない', (tester) async {
      await pumpHome(
        tester,
        const SettingsView(contentMaxWidth: 800),
        _FakeLink(const BrowserLinkStatus(applicable: false)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-browser-choice')),
        findsNothing,
      );
    });
  });
}
