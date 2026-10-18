/// URI 起動で届いた配送を溜める受信口。**Windows の入口である。**
///
/// Windows は `karita://share?url=…` で届く。届き方が stream（`app_links`）なので、**そのまま
/// では pull 型の口に合わない** — 受け取ったものを単調増加の番号付きで1件だけ持ち、Dart が
/// 取りに来るまで置いておく。Android の Kotlin 側 holder と同じ形である。
///
/// after(id)は未処理配送を順に返す。poll()の最新1件は既存利用側との互換用に残す。
///
/// **規則は持たない。** 内側の URL を取り出すのは `karita_handoff` の仕事なので、ここは
/// 配送 URI を文字列のまま運び、[InboxDeliveryForm.deliveryUri] と申告するだけである。
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:karita_platform/karita_platform.dart';

/// 素性。**どの入口から来たかを診断に残すためだけの値である。**
const String appLinkSource = 'uri';

class AppLinksShareInbox extends ShareInbox {
  final Stream<Uri> _links;
  StreamSubscription<Uri>? _subscription;
  InboxDelivery? _pending;
  final List<InboxDelivery> _queue = [];
  final _arrivals = StreamController<void>.broadcast();
  int _seq = 0;

  /// [links] を渡せるのは試験のためである。既定は `app_links` の stream で、**起動時の1件も
  /// ここに流れてくる。**
  AppLinksShareInbox({Stream<Uri>? links})
    : _links = links ?? AppLinks().uriLinkStream {
    _listen();
  }

  void _listen() {
    try {
      _subscription = _links.listen(_accept, onError: (Object _) {});
    } catch (_) {
      // **受信部を持たない場（単体試験・プラグインの無いビルド）がここを通る。**
      // 起動そのものは落とさない。
      _subscription = null;
    }
  }

  void _accept(Uri uri) {
    _seq++;
    _pending = InboxDelivery(
      id: _seq,
      url: uri.toString(),
      source: appLinkSource,
      form: InboxDeliveryForm.deliveryUri,
    );
    _queue.add(_pending!);
    _arrivals.add(null);
  }

  @override
  Future<InboxDelivery?> poll() async => _pending;

  @override
  Stream<void> get arrivals => _arrivals.stream;

  @override
  Future<List<InboxDelivery>> after(int id) async {
    _queue.removeWhere((item) => item.id <= id);
    return List.unmodifiable(_queue);
  }

  @override
  void close() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _queue.clear();
    unawaited(_arrivals.close());
  }
}
