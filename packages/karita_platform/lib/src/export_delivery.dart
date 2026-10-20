import 'dart:typed_data';

enum ExportDeliveryKind { save, share }

enum ExportDeliveryResult { saved, shared, dismissed, opened }

/// Receives an already encoded file; knows nothing about bookshelf data.
abstract interface class ExportDelivery {
  ExportDeliveryKind get kind;
  Future<ExportDeliveryResult> deliver({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  });
}
