import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_platform_flutter/karita_platform_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporary;
  late List<MethodCall> calls;
  var response = 'test.mail/ShareActivity';

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('karita-android-export-');
    calls = [];
    response = 'test.mail/ShareActivity';
    messenger.setMockMethodCallHandler(paths, (call) async {
      expect(call.method, 'getTemporaryDirectory');
      return temporary.path;
    });
    messenger.setMockMethodCallHandler(share, (call) async {
      calls.add(call);
      return response;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(share, null);
    temporary.deleteSync(recursive: true);
  });

  for (final format in [('csv', 'text/csv'), ('json', 'application/json')]) {
    test(
      '${format.$1} is delivered with the filename, MIME type and original bytes',
      () async {
        const delivery = AndroidExportDelivery();
        final bytes = Uint8List.fromList([0xef, 0xbb, 0xbf, 65, 66, 67]);
        expect(delivery.kind, ExportDeliveryKind.share);
        expect(
          await delivery.deliver(
            bytes: bytes,
            filename: 'karita-bookshelf-test.${format.$1}',
            mimeType: format.$2,
          ),
          ExportDeliveryResult.shared,
        );
        final call = calls.single;
        expect(call.method, 'share');
        final arguments = call.arguments as Map;
        expect(arguments['mimeTypes'], [format.$2]);
        expect(arguments['subject'], 'karita 本棚');
        final path = (arguments['paths'] as List).single as String;
        expect(
          File(path).parent.parent.path.replaceAll(r'\', '/'),
          '${temporary.path.replaceAll(r'\', '/')}/bookshelf-exports',
        );
        expect(path, endsWith('/karita-bookshelf-test.${format.$1}'));
        // Closing the share sheet must not remove the attachment immediately.
        expect(await File(path).readAsBytes(), bytes);
      },
    );
  }

  test(
    'cancelling and unavailable callbacks are distinct from delivery',
    () async {
      const delivery = AndroidExportDelivery();
      response = '';
      expect(
        await delivery.deliver(
          bytes: Uint8List.fromList([65]),
          filename: 'cancel.csv',
          mimeType: 'text/csv',
        ),
        ExportDeliveryResult.dismissed,
      );
      response = 'dev.fluttercommunity.plus/share/unavailable';
      expect(
        await delivery.deliver(
          bytes: Uint8List.fromList([66]),
          filename: 'unknown.json',
          mimeType: 'application/json',
        ),
        ExportDeliveryResult.opened,
      );
      final first = File(
        ((calls.first.arguments as Map)['paths'] as List).single as String,
      );
      expect(first.existsSync(), isTrue);
    },
  );

  test(
    'native share failure is surfaced and the attachment is retained',
    () async {
      messenger.setMockMethodCallHandler(share, (call) async {
        calls.add(call);
        throw PlatformException(code: 'share-failed');
      });
      await expectLater(
        const AndroidExportDelivery().deliver(
          bytes: Uint8List.fromList([65]),
          filename: 'retry.csv',
          mimeType: 'text/csv',
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(
        File(
          ((calls.single.arguments as Map)['paths'] as List).single as String,
        ).existsSync(),
        isTrue,
      );
    },
  );
}
