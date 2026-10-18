/// 受け渡しの排出と一時保持。**可変状態はここにある。**
///
/// 受理規則そのものは `karita_handoff`（純 Dart・純関数）が持つ。ここが持つのは、規則へ渡す
/// 前後の**状態**である — どこまで処理したか、いつブラウザーを開いたか。純 Dart の側へ持ち込むと
/// 受理規則の試験が無印の `dart test` で回らなくなる。
///
/// **用途（棚卸か URL 設定か）はここで決まる。** 書籍 URL だけが URL 単体で判定でき、残り2つは
/// どちらも「館サイトの一般 URL」で区別がつかない。手がかりは下の [LaunchContext] だけであり、
/// **それは候補であって証明ではない** — 共有元がその起動操作に対応している保証はないので、
/// 自動では確定しない（`../karita-ui-probe/docs/browser-handoff.md` §3）。
library;

import 'dart:async';

import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('karita.handoff');

class BookDelivery {
  final int id;
  final HandoffBook book;
  const BookDelivery(this.id, this.book);
}

/// ブラウザーを開いた目的。
enum LaunchPurpose {
  /// 貸出し（棚卸）へ戻る。**URL は保存しない。**
  lending,

  /// マイページ URL の設定。**保存は明示確定である。**
  mypageUrl,

  /// 本棚の［Amazonで見る］から元の一覧・記録へ戻る。**地区を持たない**
  /// （[LaunchContext.systemId] は空）。
  bookshelf,
}

/// ブラウザー起動情報の一時保持。**最新の1件だけをメモリに持つ。**
///
/// **期限を置かない**（2026-09-12 の決定）。古さを伝える手段が表示しか無くなるので、
/// [startedAt] を必ず画面へ出し、使ったときの年齢をログへ出す。後から期限を入れたくなったとき、
/// 実測なしでは数値を決められない。
class LaunchContext {
  final LaunchPurpose purpose;

  /// 開いた地区。**[LaunchPurpose.bookshelf] では空である。**
  final String systemId;

  /// 本棚の記録から開いたときの本。一覧から開いたとき・図書館の用途では `null`。
  final String? bookId;

  /// 起動先のホスト。**URL 全文は持たない** — 共有 URL にはセッション情報が入りうるので、
  /// 診断にも履歴にも残さない。
  final String host;

  final DateTime startedAt;

  const LaunchContext({
    required this.purpose,
    required this.systemId,
    required this.host,
    required this.startedAt,
    this.bookId,
  });

  @override
  String toString() => 'LaunchContext(${purpose.name}, $systemId)';
}

/// 受信の排出。**取りに行くのはこの層である。**
class HandoffQueue {
  final ShareInbox inbox;

  /// **処理した配送の番号。** 件数ではなく番号で見るので、画面再生成による再処理と、利用者が
  /// もう一度送った再共有を区別できる。
  int _lastHandled = 0;

  /// [latest]/[latestPurposeHint] を作った配送の番号。**遅れて購読した利用側が「もう見た値
  /// か」を区別するためにある。**
  ///
  /// `deliveries` は broadcast stream なので、購読が確立する前に届いた配送は再生されない
  /// （`build()` が `ledgerSessionProvider` 等の変化で何度も再実行される画面は、購読を
  /// 張り直す一瞬にイベントを取りこぼしうる）。`latest`/`latestPurposeHint` と対で持つこの番号
  /// を比べれば、pull 型で1回だけ拾える。
  int get latestId => _lastHandled;

  /// 直近の解析結果。**遅れて購読した利用側のために保持する** — 共有から起動された直後は、
  /// 画面が立つ前に1件目が届く。
  Handoff? latest;

  /// 直近の配送が主張していた用途ヒント。**`latest` と対で持つ、同じ「最新1件だけ」の型。**
  ///
  /// 共有テキスト（Android）はヒントを持たないので常に `null`。配送URI（Windows）だけが
  /// 持ちうる（2026-09-29 決定C' 改訂）。判定材料ではなく手がかりである
  /// （`../karita-ui-probe/docs/browser-handoff.md` §3）。
  DeliveryPurposeHint? latestPurposeHint;

  LaunchContext? _launch;

  final StreamController<Handoff> _controller =
      StreamController<Handoff>.broadcast();

  final List<BookDelivery> _books = [];
  int overflowBooks = 0;
  final _bookChanges = StreamController<void>.broadcast();
  Stream<void> get bookChanges => _bookChanges.stream;
  List<BookDelivery> takeBooks() {
    final result = List<BookDelivery>.of(_books);
    _books.clear();
    return result;
  }

  StreamSubscription<void>? _arrivals;
  Future<Handoff?>? _draining;
  bool _closed = false;

  HandoffQueue(this.inbox) {
    _arrivals = inbox.arrivals.listen((_) => unawaited(drain()));
  }

  /// 届いたものを流す。**購読していなくても [latest] に残る。**
  Stream<Handoff> get deliveries => _controller.stream;

  /// 保持している起動情報。**候補として画面へ出す値であり、確定ではない。**
  LaunchContext? get launch => _launch;

  /// 取りに行って1件だけ処理する。
  ///
  /// 呼ぶのは**起動直後と前面復帰の2箇所**である（合成層の [Composition] が配線する）。
  /// **初期化中は呼ばれない** — このオブジェクトは台帳と fixture が整ってから作られるので、
  /// 初期化中に届いた配送は OS 側の holder に残り、ここが起きてから取りに来る。pull 型に
  /// した理由そのものである。
  Future<Handoff?> drain() =>
      _draining ??= _drainAll().whenComplete(() => _draining = null);

  Future<Handoff?> _drainAll() async {
    Handoff? last;
    while (true) {
      final batch = await inbox.after(_lastHandled);
      if (_closed) return last;
      final fresh = batch.where((d) => d.id > _lastHandled).toList();
      if (fresh.isEmpty) return last;
      for (final delivery in fresh) {
        last = _accept(delivery);
      }
    }
  }

  Handoff _accept(InboxDelivery delivery) {
    _lastHandled = delivery.id;

    // **外側の封筒を剥ぐかどうかは端末の入口で決まる。** Windows は `karita://share?url=…` で
    // 届き、Android は共有テキストがそのまま届く。復号は1回だけである。
    final result = switch (delivery.form) {
      InboxDeliveryForm.sharedText => parseHandoff(delivery.url),
      InboxDeliveryForm.deliveryUri => parseDelivery(delivery.url),
    };
    // 用途ヒントは配送URI（Windows）だけが持ちうる。共有テキスト（Android）には無い。
    final hint = delivery.form == InboxDeliveryForm.deliveryUri
        ? decodePurposeHint(delivery.url)
        : null;
    final via = delivery.form == InboxDeliveryForm.deliveryUri
        ? decodeVia(delivery.url)
        : null;
    latest = result;
    latestPurposeHint = hint;
    if (result is HandoffBook) {
      if (_books.any((d) => d.book.isbn13 == result.isbn13)) {
        // A repeated share is acknowledged without consuming another slot.
      } else if (_books.length < 21) {
        _books.add(BookDelivery(delivery.id, result));
      } else {
        overflowBooks++;
      }
      _bookChanges.add(null);
    }
    // **URL 全文を出さない。** 出してよいのは素性と分類とホストだけである。
    _log.info('handoff.received', {
      'id': delivery.id,
      'source': delivery.source,
      'kind': _kind(result),
      if (hint != null) 'purpose_hint': hint.name,
      if (via != null) 'via': via.name,
      if (result is HandoffWebUrl) 'host': result.url.host,
      if (result is HandoffBook) 'host': result.source.host,
      // **パスも ISBN の値も出さない。** 形の名前と、取れたかどうかだけである。
      if (result is HandoffAmazon) ...{
        'host': result.host,
        'shape': result.shape.name,
        'isbn': result.isbn13 != null,
      },
      if (result is HandoffNotice) 'reason': result.reason.name,
    });
    if (!_controller.isClosed) _controller.add(result);
    return result;
  }

  /// 取りに行って捨てる。**リセットで旧い共有待ちを持ち越さない。**
  ///
  /// 捨てるのは「処理済みにする」ことであって、OS 側の holder を書き換えることではない。
  Future<void> discardPending() async {
    final pending = await inbox.after(_lastHandled);
    latest = null;
    latestPurposeHint = null;
    _launch = null;
    _books.clear();
    overflowBooks = 0;
    for (final delivery in pending) {
      if (delivery.id > _lastHandled) _lastHandled = delivery.id;
    }
  }

  /// ブラウザーを開くときに置く。**最新1件へ置き換える。**
  ///
  /// タブごとの履歴は作らない。起動が失敗したと分かったら [clearLaunch] で今回の候補を捨てる
  /// （**以前の候補を復活させない**）。
  void remember(LaunchContext context) {
    _launch = context;
    _log.fine('handoff.launch.remembered', {
      'purpose': context.purpose.name,
      'system_id': context.systemId,
      'host': context.host,
    });
  }

  /// 使ったので消す。**確定（貸出しへ戻る・URL を保存する）のときだけ呼ぶ。**
  ///
  /// **年齢をログへ出す。** 期限を置かないと決めた代償であり、後から期限を決めるときの実測値に
  /// なる。受信画面を閉じただけ・候補を拒否しただけでは消さない。
  LaunchContext? consume({DateTime? now}) {
    final context = _launch;
    if (context == null) return null;
    _launch = null;
    _log.info('handoff.candidate.used', {
      'purpose': context.purpose.name,
      'system_id': context.systemId,
      'age_sec': (now ?? DateTime.now())
          .difference(context.startedAt)
          .inSeconds,
    });
    return context;
  }

  /// 起動に失敗した、元の作業を明示的に中止した。
  void clearLaunch() => _launch = null;

  void dispose() {
    _closed = true;
    unawaited(_arrivals?.cancel());
    unawaited(_bookChanges.close());
    inbox.close();
    unawaited(_controller.close());
  }

  static String _kind(Handoff result) => switch (result) {
    HandoffBook() => 'book',
    HandoffAmazon() => 'amazon',
    HandoffWebUrl() => 'web_url',
    HandoffLinkCheck() => 'link_check',
    HandoffNotice() => 'notice',
  };
}
