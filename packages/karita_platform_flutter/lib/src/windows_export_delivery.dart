import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:karita_platform/karita_platform.dart';

class WindowsExportDelivery implements ExportDelivery {
  const WindowsExportDelivery();
  @override
  ExportDeliveryKind get kind => ExportDeliveryKind.save;

  @override
  Future<ExportDeliveryResult> deliver({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final extension = filename.split('.').last;
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: [
        XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
      ],
    );
    if (location == null) return ExportDeliveryResult.dismissed;
    await XFile.fromData(
      bytes,
      mimeType: mimeType,
      name: filename,
    ).saveTo(location.path);
    return ExportDeliveryResult.saved;
  }
}
