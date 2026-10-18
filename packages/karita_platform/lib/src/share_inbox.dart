/// 受け渡しの受信口。**pull 型である。**
///
/// OS 側（Android の受信 Activity、Windows の URI 起動）が受けた URL を、Dart が**取りに行く。**
/// push にすると、Flutter が起きる前に届いた配送を落とす — 共有から起動された直後がまさに
/// その場面である。
///
/// **id は単調増加させる。** 件数では「同じ配送の再処理」（画面再生成）と「意図した再共有」
/// （同じ URL をもう一度送った）を区別できない。
///
/// **ここは規則を持たない。** 運ぶのは文字列と素性だけで、URL として読めるか・書籍かどうかは
/// `karita_handoff` が決める。OS 側に残すのも「URL がちょうど1件あるか」だけである
/// （`非公開資料:browser-handoff-implementation.md` 決定 A・D）。
library;

/// 受け取ったものの形。**外側の封筒が付いているかどうかだけである。**
///
/// **端末の入口で決まる。** Android は共有テキストがそのまま届き、Windows は
/// `karita://share?url=…` という配送 URI で届く。剥ぐ必要があるかを素性の文字列から推測すると、
/// 診断のための値が振る舞いを決めることになる。
enum InboxDeliveryForm {
  /// 共有テキスト・貼り付け。そのまま共通解析へ渡す。
  sharedText,

  /// 配送 URI。**内側の URL を1回だけ復号してから共通解析へ渡す。**
  deliveryUri,
}

/// 受け取った1件。**検証していない入力である。**
class InboxDelivery {
  /// 単調増加する配送の番号。**0 は「まだ何も来ていない」。**
  final int id;

  /// 受け取った文字列。URL とは限らない。
  final String url;

  /// どこから来たか（共有・拡張・貼り付け）。**診断のためだけに持つ。**
  final String source;

  /// 外側の封筒が付いているか。
  final InboxDeliveryForm form;

  const InboxDelivery({
    required this.id,
    required this.url,
    required this.source,
    this.form = InboxDeliveryForm.sharedText,
  });

  @override
  String toString() => 'InboxDelivery($id, $source, ${form.name})';
}

/// 受信口。**実装は端末ごとに違う。**
abstract class ShareInbox {
  const ShareInbox();

  /// 最新の1件を取りに行く。**無ければ `null`。**
  ///
  /// 読むことで件数が進んではならない — 同じ配送を二度処理しないための判断は、id を持つ
  /// 呼び出し側（合成層）が行う。
  Future<InboxDelivery?> poll();

  /// Ordered pending deliveries. Implementations retain them until acknowledged.
  Future<List<InboxDelivery>> after(int id) async {
    final item = await poll();
    return item != null && item.id > id ? [item] : [];
  }

  Stream<void> get arrivals => const Stream.empty();

  /// 片付ける。**購読を持つ実装だけが中身を持つ。**
  void close() {}
}

/// 受信口を持たない端末。**口だけを残す。**
///
/// 単体試験と、受信部をまだ持たない端末がここを通る。**「来ていない」であって「壊れている」
/// ではない** — 例外にすると、受信部の無い場で起動そのものが落ちる。
class NoShareInbox extends ShareInbox {
  const NoShareInbox();

  @override
  Future<InboxDelivery?> poll() async => null;
}
