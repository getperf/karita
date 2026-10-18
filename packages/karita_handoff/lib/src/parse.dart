/// 受け渡しの共通解析。**用途は決めない。**
///
/// 返すのは5つの枝だけである — 書籍、Amazon、連携の確認、一般の Web URL、断り。**棚卸か URL 設定かはここで
/// 判定できない。** どちらも「館サイトの一般 URL」であり、手がかりは「karita からブラウザーを
/// 開いたときの目的・地区」の一時保持にしかない。それは可変状態なので合成層が持つ。ここへ
/// 持ち込むと、受理規則の試験が無印の `dart test` で回らなくなる。
///
/// **文言を持たない。** 断りの理由は [HandoffReason] までで、表示は `../karita-ui-probe` が
/// 正本である。デモの `SkipReason` と同じ形である。
library;

import 'isbn.dart';

/// 共有テキストの上限。OS 側の受信部が同じ値で先に落とす。
const int maxInputLength = 4096;

/// URL 1件の上限。Windows の配送 URI に載せる長さでもある。
const int maxUrlLength = 2048;

/// 配送 URI の scheme と操作。**操作名も版も作らない。** 渡すのは URL だけである。
const String deliveryScheme = 'karita';
const String deliveryHost = 'share';

/// 解析の結果。
sealed class Handoff {
  const Handoff();
}

/// カーリルの書籍ページ。**正規化済みの ISBN-13 を持つ。**
final class HandoffBook extends Handoff {
  final String isbn13;
  final Uri source;

  const HandoffBook(this.isbn13, this.source);

  @override
  bool operator ==(Object other) =>
      other is HandoffBook && other.isbn13 == isbn13 && other.source == source;

  @override
  int get hashCode => Object.hash(isbn13, source);

  @override
  String toString() => 'HandoffBook($isbn13, $source)';
}

/// それ以外の Web URL。**図書館サイトと認定したことにはならない。**
final class HandoffWebUrl extends Handoff {
  final Uri url;

  const HandoffWebUrl(this.url);

  @override
  bool operator ==(Object other) => other is HandoffWebUrl && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'HandoffWebUrl($url)';
}

/// karita ガイドの連携確認ページ。**拡張から karita まで届いたことの合図であり、業務の入力ではない。**
///
/// 初回のウィザードの「ブラウザーとつなぐ」で、利用者がこのページを拡張で送る
/// （2026-10-15）。拡張のインストール・ピン留め・`karita://` の起動許可・Windows の関連付けの
/// どれが欠けても届かないので、1回届けば全部そろっている。**照合用の値は付けない** — 別の
/// ブラウザーで手で開いたページから送っても通るようにするためで、偽って得るものも無い。
///
/// 用途の選択・予約の下書きへは流さない。届いたことだけを使う。
final class HandoffLinkCheck extends Handoff {
  const HandoffLinkCheck();

  @override
  bool operator ==(Object other) => other is HandoffLinkCheck;

  @override
  int get hashCode => (HandoffLinkCheck).hashCode;

  @override
  String toString() => 'HandoffLinkCheck()';
}

/// 連携確認ページ。**ホストとパスの完全一致で見る**（末尾の `/` と `index.html` は許す）。
const String linkCheckHost = 'karita.getperf.net';
const String linkCheckPath = '/extensions/check/';
final Uri linkCheckUrl = Uri.https(linkCheckHost, linkCheckPath);

/// Amazon の商品・検索ページ。**URL 全文を持たない** — 持つのは ISBN-13・形・ホストだけで
/// ある。Amazon の URL には検索語と追跡値が付いてくるので、ここで捨てる
/// （`非公開資料:amazon-share-handoff.md` §1）。
///
/// **用途も着地もここでは決めない。** ISBN が取れても本棚にあるかは台帳を読まないと分からず、
/// 元の画面へ戻すかは起動記録で決まる。どちらも合成層の仕事である。
final class HandoffAmazon extends Handoff {
  /// 取れなければ `null`（電子版の ASIN・検索語・その他のページ）。
  final String? isbn13;
  final AmazonShape shape;

  /// 小文字化したホスト（`www.amazon.co.jp` または `amazon.co.jp`）。
  final String host;

  const HandoffAmazon(this.isbn13, this.shape, this.host);

  @override
  bool operator ==(Object other) =>
      other is HandoffAmazon &&
      other.isbn13 == isbn13 &&
      other.shape == shape &&
      other.host == host;

  @override
  int get hashCode => Object.hash(isbn13, shape, host);

  @override
  String toString() => 'HandoffAmazon($isbn13, ${shape.name}, $host)';
}

/// Amazon の URL の形。**ログに出してよいのはこの名前までである。**
enum AmazonShape {
  /// `/dp/<ISBN10>`・`/<スラッグ>/dp/<ISBN10>`・`/gp/product/<ISBN10>`。
  isbn10,

  /// `/s?k=<ISBN13>`。
  searchIsbn,

  /// `/dp/B0…`（電子版など）。ISBN へ換算する規則は無い。
  asin,

  /// `/s` だが `k` が ISBN13 ではない。
  search,

  /// それ以外。http・ポート付き・チェック桁の合わない10桁も含む。
  other,
}

/// 受け取らない。**業務状態も一時保持も変えない。**
final class HandoffNotice extends Handoff {
  final HandoffReason reason;

  const HandoffNotice(this.reason);

  @override
  bool operator ==(Object other) =>
      other is HandoffNotice && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'HandoffNotice(${reason.name})';
}

/// 断る理由。**文言ではない。**
enum HandoffReason {
  /// URL が1件も無い。
  noUrl,

  /// URL が2件以上ある。
  multipleUrl,

  /// 行まるごとが URL ではない（説明文が付いている、1行に2つ入っている）。
  inlineText,

  /// 入力または URL が長すぎる。
  tooLong,

  /// 配送 URI の形が違う（`karita://share?url=` ではない）。
  badDelivery,

  /// URL として読めない。制御文字を含む、ホストが無い。
  brokenUrl,

  /// http(s) ではない。
  badScheme,

  /// userinfo が付いている。
  hasUserInfo,

  /// カーリルだが書籍ページではない（検索結果・トップなど）。
  calilNonBook,

  /// カーリルの書籍 URL だが ISBN が不正。
  invalidIsbn,
}

/// Windows の配送 URI から共通解析まで一息で通す。
Handoff parseDelivery(String raw) {
  final inner = decodeDelivery(raw);
  if (inner == null) return const HandoffNotice(HandoffReason.badDelivery);
  return parseHandoff(inner);
}

/// 配送 URI が主張する用途。**送り手（拡張）の自己申告であり、証明ではない。**
///
/// `karita_app` の `LaunchPurpose` とは別の型である — こちらは「配送 URI が主張する値」、
/// あちらは「karita 自身がブラウザーを開いたときに覚えた値」で、信頼度が異なる
/// （`../karita-ui-probe/docs/browser-handoff.md` §3 の優先順位）。**用途を決めるのは
/// ここではない** — ここは構文として復号するだけで、`LaunchContext` との優劣判断は
/// 合成層（`karita_app`）が行う（2026-09-29 決定R）。
enum DeliveryPurposeHint { lending, mypageUrl }

const Map<String, DeliveryPurposeHint> _purposeTokens = {
  'lending': DeliveryPurposeHint.lending,
  'mypage_url': DeliveryPurposeHint.mypageUrl,
};

/// 配送 URI が申告する起動の経路。**ログで経路を区別するためだけにあり、受理・用途には使わない。**
///
/// 拡張は送信先を開けなかったときの［ここから karita を開く］リンクにだけ `via=retry` を付ける。
/// 自動の起動がブラウザーで止まったかどうかは karita に届かないので、届いた側で区別する
/// （2026-10-13 決定S）。
enum DeliveryVia { retry }

const Map<String, DeliveryVia> _viaTokens = {
  'retry': DeliveryVia.retry,
};

/// `karita://share?url=…&purpose=…&via=…` を剥いだ結果。
typedef _Envelope = ({String url, DeliveryPurposeHint? purpose, DeliveryVia? via});

/// 封筒を剥ぐ唯一の実体。**[decodeDelivery]・[decodePurposeHint]・[decodeVia] はここだけを呼ぶ。**
///
/// 許すのは `url` 必須1個・`purpose` 任意1個・`via` 任意1個までである（2026-09-29 決定C' 改訂、
/// 2026-10-13 決定S）。それ以外の
/// 鍵・重複・`purpose` の不正な値は**封筒ごと**拒否する（決定D「OS 側で止めるのは URL が1件か
/// だけ」と同じ形を保つ — 一部だけ信用すると、[decodeDelivery] と [decodePurposeHint] が
/// 食い違う余地ができる）。
///
/// **空パスと `/` の両方を受理する。** Edge が `/` を足す（2026-09-07 実測）。
_Envelope? _decodeEnvelope(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  if (uri.scheme != deliveryScheme || uri.host != deliveryHost) return null;
  if (uri.userInfo.isNotEmpty || uri.hasPort || uri.hasFragment) return null;
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  final all = uri.queryParametersAll;
  if (all.isEmpty || all.length > 3) return null;
  if (!all.keys.every((key) => key == 'url' || key == 'purpose' || key == 'via')) {
    return null;
  }
  final urlValues = all['url'];
  if (urlValues == null || urlValues.length != 1) return null;
  final purposeValues = all['purpose'];
  DeliveryPurposeHint? purpose;
  if (purposeValues != null) {
    if (purposeValues.length != 1) return null;
    purpose = _purposeTokens[purposeValues.single];
    if (purpose == null) return null;
  }
  final viaValues = all['via'];
  DeliveryVia? via;
  if (viaValues != null) {
    if (viaValues.length != 1) return null;
    via = _viaTokens[viaValues.single];
    if (via == null) return null;
  }
  return (url: urlValues.single, purpose: purpose, via: via);
}

/// `karita://share?url=<percent-encoded>` から内側の URL の文字列を取り出す。
///
/// **復号は1回だけである。** [Uri.queryParametersAll] が復号した値をそのまま返し、呼び出し側は
/// 二度目の復号をしない。内側の URL の検証はここでは行わない — それは [parseHandoff] の仕事で
/// ある。外側と内側を別々に検証するために関数を分けてある。
String? decodeDelivery(String raw) => _decodeEnvelope(raw)?.url;

/// 配送 URI が主張する用途ヒントを取り出す。**[decodeDelivery] が `null` を返す入力では、
/// これも常に `null`。**
DeliveryPurposeHint? decodePurposeHint(String raw) => _decodeEnvelope(raw)?.purpose;

/// 配送 URI が申告する起動の経路を取り出す。**[decodeDelivery] が `null` を返す入力では、
/// これも常に `null`。**
DeliveryVia? decodeVia(String raw) => _decodeEnvelope(raw)?.via;

/// 共有テキスト・貼り付け・拡張から来た入力を解析する。**4経路すべてがここを通る。**
Handoff parseHandoff(String input) {
  if (input.length > maxInputLength) {
    return const HandoffNotice(HandoffReason.tooLong);
  }
  // 別行のタイトル ＋ URL 1件を受理する。同じ行に説明文が付いたものは受けない。
  final urls = <String>[];
  var sawInline = false;
  for (final raw in input.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (_urlLine.hasMatch(line)) {
      urls.add(line);
    } else if (line.contains('://')) {
      // 「説明文 https://…」と「1行に2つ」の両方がここへ来る。**どちらも断りであり、
      // 送り直しの案内は同じである。** 理由を分けるほどの違いが無い。
      sawInline = true;
    }
  }
  if (urls.length > 1) return const HandoffNotice(HandoffReason.multipleUrl);
  if (urls.isEmpty) {
    return HandoffNotice(
        sawInline ? HandoffReason.inlineText : HandoffReason.noUrl);
  }
  return _classify(urls.single);
}

Handoff _classify(String text) {
  if (text.length > maxUrlLength) {
    return const HandoffNotice(HandoffReason.tooLong);
  }
  if (_hasControlChar(text)) {
    return const HandoffNotice(HandoffReason.brokenUrl);
  }
  final url = Uri.tryParse(text);
  // **`Uri.isAbsolute` を使わない。** Dart のそれは「scheme があり、かつフラグメントが無い」で
  // あり、`…/book/427421933X#top` を絶対 URL と認めない。共有されるのはブラウザーのアドレス欄の
  // 値であり、フラグメントは普通に付いてくる。見るのは scheme とホストの有無だけでよい。
  if (url == null || !url.hasScheme || url.host.isEmpty) {
    return const HandoffNotice(HandoffReason.brokenUrl);
  }
  if (url.scheme != 'http' && url.scheme != 'https') {
    return const HandoffNotice(HandoffReason.badScheme);
  }
  if (url.userInfo.isNotEmpty) {
    return const HandoffNotice(HandoffReason.hasUserInfo);
  }
  // **ホストは完全一致で見る。** 文字列の部分一致で分類すると `calil.jp.evil` が通る。
  // `www.calil.jp` はここでは一般の Web URL になる（仕様が完全一致と決めている）。
  final host = url.host.toLowerCase();
  // **Amazon もホストの完全一致で見る。** 広げると図書館サイトの共有を壊す。
  if (_amazonHosts.contains(host)) return _classifyAmazon(url, host);
  if (host == linkCheckHost && url.scheme == 'https' && !url.hasPort &&
      _linkCheckPaths.contains(url.path)) {
    return const HandoffLinkCheck();
  }
  if (host != _calilHost) return HandoffWebUrl(url);
  // カーリルだと分かった以上、一般の Web URL の候補にはしない。書籍として受理できなければ
  // 「書籍ページから送り直してください」の案内へ落とす。
  if (url.scheme != 'https' || url.hasPort) {
    return const HandoffNotice(HandoffReason.calilNonBook);
  }
  final match = _bookPath.firstMatch(url.path);
  if (match == null) return const HandoffNotice(HandoffReason.calilNonBook);
  final isbn13 = normalizeIsbn13(match.group(1)!);
  if (isbn13 == null) return const HandoffNotice(HandoffReason.invalidIsbn);
  return HandoffBook(isbn13, url);
}

/// Amazon の URL から ISBN-13 を取る。**取れない形はすべて `isbn13 == null` で返す。**
///
/// 規則は Amazon probe の分類（`../karita-ui-amazon-android-probe` の `ShareShapes`）と同じで
/// ある。`/gp/aw/d/` と `/exec/obidos/ASIN/` は使われた実績が無いので数えない。**短縮 URL
/// （`amzn.asia` 等）は別ホストなので、ここへ来ずに一般の Web URL になる。**
HandoffAmazon _classifyAmazon(Uri url, String host) {
  HandoffAmazon shaped(AmazonShape shape, [String? isbn13]) =>
      HandoffAmazon(isbn13, shape, host);
  if (url.scheme != 'https' || url.hasPort) return shaped(AmazonShape.other);
  final product = _amazonProductPath.firstMatch(url.path);
  if (product != null) {
    final id = (product.group(1) ?? product.group(2))!.toUpperCase();
    if (_isbn10Id.hasMatch(id)) {
      final isbn13 = normalizeIsbn13(id);
      return isbn13 == null
          ? shaped(AmazonShape.other)
          : shaped(AmazonShape.isbn10, isbn13);
    }
    return shaped(_asin.hasMatch(id) ? AmazonShape.asin : AmazonShape.other);
  }
  if (url.path == '/s' || url.path == '/s/') {
    final k = url.queryParametersAll['k'];
    final value = k != null && k.length == 1 ? k.single : null;
    // **13桁だけを受ける。** 10桁の検索語は書名の一部（数字）とも区別がつかない。
    final isbn13 = value != null && _isbn13Text.hasMatch(value)
        ? normalizeIsbn13(value)
        : null;
    return isbn13 == null
        ? shaped(AmazonShape.search)
        : shaped(AmazonShape.searchIsbn, isbn13);
  }
  return shaped(AmazonShape.other);
}

bool _hasControlChar(String text) {
  for (final unit in text.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return true;
  }
  return false;
}

const String _calilHost = 'calil.jp';

const Set<String> _linkCheckPaths = {
  '/extensions/check',
  linkCheckPath,
  '${linkCheckPath}index.html',
};

const Set<String> _amazonHosts = {'www.amazon.co.jp', 'amazon.co.jp'};

/// `/dp/<id>`（前にスラッグ1段を許す）と `/gp/product/<id>`。後ろの `/ref=…` 等は許す。
final RegExp _amazonProductPath =
    RegExp(r'^(?:/[^/]+)?/dp/([^/]+)(?:/.*)?$|^/gp/product/([^/]+)(?:/.*)?$');
final RegExp _isbn10Id = RegExp(r'^[0-9]{9}[0-9X]$');
final RegExp _asin = RegExp(r'^B0[0-9A-Z]{8}$');
final RegExp _isbn13Text = RegExp(r'^97[89][0-9]{10}$');

/// 行まるごとが URL であること。空白を含む行はここで落ちる。
///
/// **`://` の後ろが空でも URL 行として数える。** `https://` だけの行を「説明文つき」として
/// 断ると理由が嘘になる。読めない URL は [_classify] が `brokenUrl` として断る。
final RegExp _urlLine = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://\S*$');

/// 末尾の `/` は許す。クエリとフラグメントは [Uri] が別に持つので path には現れない。
final RegExp _bookPath = RegExp(r'^/book/([0-9]{9}[0-9Xx]|[0-9]{13})/?$');
