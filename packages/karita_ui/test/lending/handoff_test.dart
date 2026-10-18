/// 貸出しの候補到着でタブが切り替わる。**widget を立てずに、通知メソッドを直接呼んで測る**
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
  late LendingRoute route;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    home = Directory.systemTemp.createTempSync('karita-lending-handoff-ui-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
    container = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(app)],
    );
    route = container.read(lendingRouteProvider.notifier);
  });
  tearDown(() {
    container.dispose();
    app.close();
    home.deleteSync(recursive: true);
  });

  test('候補到着で対象地区の詳細へ移り、貸出しタブへ切り替わる', () {
    expect(container.read(currentTabProvider), ShellTab.reserve);

    route.onLendingCandidate('Tokyo_Koto');

    expect(
      container.read(lendingRouteProvider),
      LendingRouteState.area('Tokyo_Koto'),
    );
    expect(container.read(currentTabProvider), ShellTab.lending);
  });
}
