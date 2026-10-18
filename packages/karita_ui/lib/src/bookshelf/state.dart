library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import '../composition.dart';
import '../libraries/state.dart';
import '../shell/navigation.dart';

final bookshelfProvider = FutureProvider<List<ShelfBook>>((ref) async {
  ref.watch(ledgerRevisionProvider);
  return ref.watch(compositionProvider).loadBookshelf(includeHidden: true);
});

String shelfSearchKey(String text) => unorm.nfkc(text).toLowerCase().trim();

/// 本1冊ぶんの照合用文字列。**投影1回につき1回だけ作る。**
///
/// NFKC は安くない。一覧は入力・状態変更・同期のたびに組み直すので、本ごとに正規化を回すと
/// 描画のたびに件数ぶんの正規化が走る（1万件で90ms＝フレーム予算の5倍超）。作った鍵は
/// [ShelfBook] に紐づけて持つので、台帳を読み直して新しい投影になれば一緒に捨たる。
final _searchKeys = Expando<String>('shelf.searchKey');
String shelfBookKey(ShelfBook b) =>
    _searchKeys[b] ??= shelfSearchKey('${b.title} ${b.authors.join(' ')}');

/// 正規化済みの検索語で照合する。**語の正規化は呼ぶ側が1回だけ行う。**
bool shelfMatchesKey(ShelfBook b, String key) =>
    key.isEmpty ||
    shelfBookKey(b).contains(key) ||
    (b.isbn13 != null && b.isbn13!.contains(key.replaceAll('-', '')));

bool shelfMatches(ShelfBook b, String query) =>
    shelfMatchesKey(b, shelfSearchKey(query));

/// ISBN10へ変換できる検証済み978だけをリンクする。979のURLは別途決定する。
Uri? shelfCalilUrl(String? isbn) {
  final isbn10 = _isbn10(isbn);
  return isbn10 == null ? null : Uri.https('calil.jp', '/book/$isbn10');
}

/// 本棚の［Amazonで見る］の行き先。**ISBN が無ければ作らない** — 書名検索へ落とすと別の本に当たる。
///
/// 978 は商品ページ（`/dp/<ISBN10>`）へ直に行く。その画面から共有した URL に ISBN が残るので、
/// 受信側が ISBN で本を引き当てられる（`非公開資料:2026-10-05-bookshelf-amazon-link-review.md`）。
/// 979 は ISBN10 が無いので ISBN13 の検索に落とす。
Uri? shelfAmazonUrl(String? isbn) {
  final normalized = isbn == null ? null : normalizeIsbn13(isbn);
  if (normalized == null) return null;
  final isbn10 = _isbn10(normalized);
  return isbn10 == null
      ? Uri.https('www.amazon.co.jp', '/s', {'k': normalized})
      : Uri.https('www.amazon.co.jp', '/dp/$isbn10');
}

/// 978 の ISBN13 を ISBN10 にする。979 と不正な値は `null`。
String? _isbn10(String? isbn) {
  final normalized = isbn == null ? null : normalizeIsbn13(isbn);
  if (normalized == null || !normalized.startsWith('978')) return null;
  final core = normalized.substring(3, 12);
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += int.parse(core[i]) * (10 - i);
  }
  final check = (11 - sum % 11) % 11;
  return '$core${check == 10 ? 'X' : check}';
}

/// 外から「この本の記録を開く」と頼む口。**一覧の選択そのものではない。**
///
/// 本棚の選択（`view.dart` の `selected`）は画面の状態で、検索欄や絞込みと同じ持ち主に
/// 居る。ここはその外から届く**1回きりの合図**で、受け取った側が選択へ移して空にする。
///
/// **選択ごと Riverpod へ移していない** — `TextEditingController` と変換確定の購読は
/// StatefulWidget に居る必要があり、移すと持ち主が2つに割れる（`view.dart`）。合図だけを
/// 外へ出せば、渡す側は本棚の画面状態を知らずに済む。
final shelfOpenRequestProvider = NotifierProvider<ShelfOpenRequest, String?>(
  ShelfOpenRequest.new,
);

class ShelfOpenRequest extends Notifier<String?> {
  @override
  String? build() => null;

  /// 開く本を頼む。**タブの切替えは [openShelfRecord] が行う。**
  void open(String bookId) => state = bookId;

  /// 受け取ったので空にする。**残すと、本棚へ戻るたびに同じ本が開く。**
  void taken() => state = null;
}

/// 本の記録を閉じたときに帰るタブ。**借りた画面を閉じたら借り手へ返す**
/// （`LibrariesRoute` の `_returnTo` と同じ考え方）。
///
/// 貸出しの区の行（［レビュー］と書影・書名）が入れる。本棚の一覧から開いたときは `null`
/// のままで、閉じても本棚の一覧へ戻る。**本棚から別のタブへ移ったら空にする** — 残すと、
/// 次に本棚で開いた本を閉じたときに貸出しへ飛ぶ。
final shelfReturnProvider = NotifierProvider<ShelfReturn, ShellTab?>(
  ShelfReturn.new,
);

class ShelfReturn extends Notifier<ShellTab?> {
  @override
  ShellTab? build() => null;

  void set(ShellTab? tab) => state = tab;
}

/// 本の記録を閉じる操作の名前。**帰り先を語にする** — 貸出しから開いた記録で「本棚へ戻る」と
/// 書くと、押した先と食い違う。
String shelfBackLabel(ShellTab? origin) => '${origin?.label ?? '本棚'}へ戻る';

/// 本の記録へ渡す。**貸出しの行から呼ぶ。**
///
/// `lending/shared.dart` の `openLibrariesFrom` と同じ形である — 相手の画面状態を先に置き、
/// それからタブを移す。**開く本が本棚に無くてもよい**（`bookshelfProvider` は
/// `includeHidden: true` で全冊を読む）。
///
/// [returnTo] を渡すと、記録を閉じたときにそのタブへ帰る（保存でも戻るでも）。
void openShelfRecord(WidgetRef ref, String bookId, {ShellTab? returnTo}) {
  ref.read(shelfReturnProvider.notifier).set(returnTo);
  ref.read(shelfOpenRequestProvider.notifier).open(bookId);
  ref.read(currentTabProvider.notifier).select(ShellTab.bookshelf);
}
