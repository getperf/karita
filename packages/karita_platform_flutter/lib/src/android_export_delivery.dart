import 'dart:io';
import 'dart:typed_data';
import 'package:karita_platform/karita_platform.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AndroidExportDelivery implements ExportDelivery {
  const AndroidExportDelivery();
  @override
  ExportDeliveryKind get kind => ExportDeliveryKind.share;

  @override
  Future<ExportDeliveryResult> deliver({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final root = Directory(
      '${(await getTemporaryDirectory()).path}/bookshelf-exports',
    );
    await root.create(recursive: true);
    // Retain recent attachments so receiving apps can read after the sheet closes.
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    await for (final entry in root.list()) {
      if (entry is Directory &&
          (await entry.stat()).modified.isBefore(cutoff)) {
        await entry.delete(recursive: true);
      }
    }
    final directory = await root.createTemp('export-');
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: 'karita 本棚',
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => ExportDeliveryResult.shared,
      ShareResultStatus.dismissed => ExportDeliveryResult.dismissed,
      ShareResultStatus.unavailable => ExportDeliveryResult.opened,
    };
  }
}
