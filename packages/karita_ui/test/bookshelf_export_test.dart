import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

class _Delivery implements ExportDelivery {
  bool fail = false;
  Uint8List? bytes;
  @override
  ExportDeliveryKind kind = ExportDeliveryKind.save;
  ExportDeliveryResult result = ExportDeliveryResult.saved;
  @override
  Future<ExportDeliveryResult> deliver({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    if (fail) throw const FileSystemException('test');
    this.bytes = bytes;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;
  late _Delivery delivery;
  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-export-ui-');
    delivery = _Delivery();
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
      exportDelivery: delivery,
    );
  });
  tearDown(() {
    app.close();
    home.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(app)],
    );
    addTearDown(container.dispose);
    container.read(currentTabProvider.notifier).select(ShellTab.bookshelf);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: BookshelfView())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'export uses all books despite search and holds confirmed snapshot',
    (tester) async {
      await pump(tester);
      final count = app.prepareBookshelfExport().books.length;
      await tester.enterText(
        find.byKey(const ValueKey('shelf.search')),
        '一致しない検索',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shelf.export')));
      await tester.pumpAndSettle();
      expect(find.text('読みたい・読んだの全$count冊（レビューを含む）'), findsOneWidget);
      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();
      app.setShelfState(app.loadBookshelf().first.id, 'removed');
      await tester.tap(find.byKey(const ValueKey('shelf.export.confirm')));
      await tester.pumpAndSettle();
      final data =
          jsonDecode(utf8.decode(delivery.bytes!)) as Map<String, dynamic>;
      expect(data['books'], hasLength(count));
      expect(find.text('本棚を保存しました。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Android action opens sharing and reports handoff rather than mail delivery',
    (tester) async {
      delivery.kind = ExportDeliveryKind.share;
      delivery.result = ExportDeliveryResult.shared;
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('shelf.export')));
      await tester.pumpAndSettle();
      expect(find.text('共有する'), findsOneWidget);
      expect(find.text('保存先を選ぶ'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('shelf.export.confirm')));
      await tester.pumpAndSettle();
      expect(find.text('共有先にファイルを渡しました。'), findsOneWidget);
      expect(delivery.bytes, isNotNull);
    },
  );

  testWidgets('failure leaves dialog available for retry and closing', (
    tester,
  ) async {
    delivery.fail = true;
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('shelf.export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shelf.export.confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('本棚をエクスポートできませんでした'), findsOneWidget);
    delivery.fail = false;
    await tester.tap(find.byKey(const ValueKey('shelf.export.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('本棚を保存しました。'), findsOneWidget);
  });
}
