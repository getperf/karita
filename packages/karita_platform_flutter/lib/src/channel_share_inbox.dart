/// OS 側の受信部から配送を取りに行く実装。
///
/// **口は `karita_platform` の [ShareInbox] にあり、ここは実装だけである。** `MethodChannel` が
/// Flutter を要るので、純 Dart の側に置けない。
///
/// **Android も Windows も同じ口を通る。** Android は受信 Activity が持つ単調増加の holder、
/// Windows は URI 起動の引数を受けた runner 側が同じ形で答える。入口が違うだけで、Dart から
/// 見える形は1つである。
///
/// **規則は持たない。** 運ぶのは文字列と素性だけで、受理するかどうかは `karita_handoff` が
/// 決める（`非公開資料:browser-handoff-implementation.md` 決定 A）。
library;

import 'package:flutter/services.dart';
import 'package:karita_platform/karita_platform.dart';

/// OS 側と合わせる名前。**操作は `snapshot` の1つだけである。**
const String shareChannelName = 'karita/share';
const String shareSnapshotMethod = 'snapshot';

/// OS 側が「外側の封筒が付いている」と申告する値。
const String deliveryUriForm = 'delivery_uri';

/// `MethodChannel` 越しの受信口。
class ChannelShareInbox extends ShareInbox {
  final MethodChannel _channel;

  ChannelShareInbox([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(shareChannelName);

  @override
  Future<List<InboxDelivery>> after(int id) async {
    try {
      final rows = await _channel.invokeListMethod<Object?>('pending', {
        'after': id,
      });
      return [
        for (final row in rows ?? const [])
          if (row is Map && row['id'] is int && row['url'] is String)
            InboxDelivery(
              id: row['id'] as int,
              url: row['url'] as String,
              source: row['source'] as String? ?? 'unknown',
            ),
      ];
    } on MissingPluginException {
      return super.after(id);
    } on PlatformException {
      return super.after(id);
    }
  }

  @override
  Future<InboxDelivery?> poll() async {
    final Map<Object?, Object?>? snapshot;
    try {
      snapshot = await _channel.invokeMapMethod<Object?, Object?>(
        shareSnapshotMethod,
      );
    } on MissingPluginException {
      // **受信部を持たない端末がここを通る。** 例外にすると、まだ受信部の無いビルドで
      // 「届いていない」が「壊れている」として上がる。
      return null;
    } on PlatformException {
      return null;
    }
    if (snapshot == null) return null;

    final id = snapshot['id'];
    final url = snapshot['url'];
    if (id is! int || id <= 0 || url is! String || url.isEmpty) return null;
    final source = snapshot['source'];
    return InboxDelivery(
      id: id,
      url: url,
      source: source is String && source.isNotEmpty ? source : 'unknown',
      // **既定は共有テキストである。** 外側の封筒を剥ぐ必要があるのは、OS 側がそう申告した
      // ときだけにする。
      form: snapshot['form'] == deliveryUriForm
          ? InboxDeliveryForm.deliveryUri
          : InboxDeliveryForm.sharedText,
    );
  }
}
