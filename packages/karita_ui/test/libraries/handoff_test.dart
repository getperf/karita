/// マイページの候補到着でタブが切り替わる。**widget を立てずに、通知メソッドを直接呼んで測る**
/// （`reservation_test.dart` の `actions.receive(delivery)` と同じ扱い）。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;
  late ProviderContainer container;
  late LibrariesRoute route;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    home = Directory.systemTemp.createTempSync('karita-mypage-handoff-ui-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
    container = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(app)],
    );
    route = container.read(librariesRouteProvider.notifier);
  });
  tearDown(() {
    container.dispose();
    app.close();
    home.deleteSync(recursive: true);
  });

  final url = Uri.parse('https://www.koto-lib.tokyo.jp/login');

  test('候補到着でマイページ URL 画面へ移り、設定タブへ切り替わる。URL は直接渡す', () {
    container.read(currentTabProvider.notifier).select(ShellTab.lending);

    route.onMypageCandidate('Tokyo_Koto', url);

    final state = container.read(librariesRouteProvider);
    expect(state.screen, LibrariesScreen.mypageUrl);
    expect(state.systemId, 'Tokyo_Koto');
    expect(state.prefillUrl, url.toString());
    expect(container.read(currentTabProvider), ShellTab.settings);
  });

  test('画面を閉じると、候補到着前に居たタブへ戻る', () {
    container.read(currentTabProvider.notifier).select(ShellTab.lending);
    route.onMypageCandidate('Tokyo_Koto', url);

    route.back();

    expect(container.read(currentTabProvider), ShellTab.lending);
    expect(container.read(librariesRouteProvider).isOpen, isFalse);
  });
}
