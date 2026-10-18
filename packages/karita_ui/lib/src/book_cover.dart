/// 書影1枚。**予約・貸出し・（いずれ）本棚が同じ絵を出す。**
///
/// 規則は[共通書影仕様](`../../../karita-ui-probe/docs/cover-fallback.md`)にある —
/// **openBD の書影を直接取り、取得中・欠損・失敗は DiceBear Initials を出す。** 3つを
/// 区別して別の絵を出さない。利用者から見ればどれも「絵が無い」であり、区別して得るものが
/// 無い（失敗の詳細は `BookLookup` が抱えている）。
///
/// ## なぜ feature の下に置かないか
///
/// `lib/src/` の直下は**継ぎ目と全 feature が使うものだけ**である（`karita_ui.dart` の
/// 「中の並べ方」）。書影はまさに後者で、予約の下に置くと貸出しが予約を import することに
/// なる。
///
/// ## 取得の口が2つある
///
/// 貸出しは **ISBN しか持っていない**ので、書誌（openBD）→ 書影 URL → 画像 の2段を
/// [bookCoverProvider] に踏ませる。予約は**書誌を既に引いてある**（下書きが `coverUrl` を
/// 持つ）ので、取れたバイトを [BookCoverView.bytes] へ渡す。**絵の出し方は1箇所である。**
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:karita_cover/karita_cover.dart';

import 'composition.dart';

/// ISBN 1つぶんの書影のバイト。**無ければ `null`。**
///
/// **`autoDispose` である。** 棚を繰って画面から外れた行のバイトをここで掴み続けると、
/// `BookLookup` が上限付きで持っている意味が消える（`external-data-access.md`
/// 「openBD書影は上限付きメモリに決定。永続キャッシュは作らない」）。戻ってきたときは
/// キャッシュから即座に返るので、外へ出る要求は増えない。
///
/// **コード生成を使わない。** 生成した family は `.g.dart` を1本増やすが、ここは引数1つの
/// 素直な非同期で、`density.dart` と同じく手で書いたほうが読める。
final bookCoverProvider = FutureProvider.autoDispose.family<Uint8List?, String>(
  (ref, isbn13) async {
    final lookup = ref.watch(compositionProvider).bookInfo;
    final url = (await lookup.book(isbn13)).record?.coverUrl;
    if (url == null) return null;
    return _asBytes((await lookup.cover(url)).bytes);
  },
);

/// [Image.memory] は `Uint8List` しか受けない。**写すのはその都合だけである。**
Uint8List? _asBytes(List<int>? bytes) => switch (bytes) {
  null => null,
  Uint8List value => value,
  final value => Uint8List.fromList(value),
};

/// 書影の枠。**縦横比は 1:1.42 で固定する。**
///
/// 幅だけを渡して高さを計算で出すのは、**呼ぶ側が比を間違えられないようにする**ためである。
/// 初期画面のサマリは 28、貸出しの詳細は 48、予約は 76（2026-09-20 に決めた値）。
class BookCoverView extends ConsumerWidget {
  /// ISBN から自分で取りに行く。**貸出しの一覧はこちらである。**
  const BookCoverView({
    super.key,
    required this.width,
    required this.colorSeed,
    required this.title,
    this.isbn13,
  }) : _bytes = null;

  /// 取れたバイトを受け取る。**呼ぶ側が既に書誌を引いてある場合である。**
  ///
  /// `bytes` が `null` の間は代替ラベルが出る — **取得中と欠損を区別しない**のは
  /// [BookCoverView] と同じである。
  const BookCoverView.bytes({
    super.key,
    required this.width,
    required this.colorSeed,
    required this.title,
    required List<int>? bytes,
  }) : isbn13 = null,
       _bytes = bytes;

  /// 枠の幅。**高さはここから決まる。**
  final double width;

  /// 代替ラベルの色の種。**書籍 ID を渡す** — 書名を種にすると、書名を直しただけで色が変わる
  /// （`cover-fallback.md`「本番で使う種は安定した書籍IDを想定」）。
  final String colorSeed;

  /// 代替ラベルの頭文字の元。
  final String title;

  /// 正規化済みの ISBN-13。**無ければ取りに行かず、代替ラベルだけを出す。**
  final String? isbn13;

  final List<int>? _bytes;

  /// 縦横比。**文庫から単行本までの実寸のだいたい中央である。**
  static const double _aspect = 1.42;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isbn = isbn13;
    final bytes = isbn == null || isbn.isEmpty
        ? _asBytes(_bytes)
        : ref.watch(bookCoverProvider(isbn)).asData?.value;
    final label = coverLabel(colorSeed: colorSeed, title: title);
    return Semantics(
      label: '書影',
      child: ClipRRect(
        // **角を落とす。** 小さい枠では直角だと行の罫線と見分けが付かない。
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          width: width,
          height: (width * _aspect).roundToDouble(),
          // **地色は絵の有無にかかわらず敷く。** 書影の縦横比は版元ごとに違い、`contain` で
          // 置くと上下か左右が余る。そこが透けると、取得の前後で枠の明るさが変わる。
          child: ColoredBox(
            color: Color(int.parse('ff${label.colorHex}', radix: 16)),
            child: bytes == null
                ? _initials(label)
                : Image.memory(
                    bytes,
                    // **引き伸ばさず、切り取らない**（`cover-fallback.md`）。表紙の題字を
                    // 端で切ると、書影を出した意味が薄れる。
                    fit: BoxFit.contain,
                    // 要求した幅の3倍で復号する。端末の devicePixelRatio の上限に合わせて
                    // あり、これより大きく持っても画面には出ない。
                    cacheWidth: (width * 3).round(),
                    errorBuilder: (_, _, _) => _initials(label),
                  ),
          ),
        ),
      ),
    );
  }

  /// 取得中・欠損・失敗の絵。**DiceBear Initials。**
  ///
  /// `karita_cover` は正方形の SVG を返すので、**縦長の枠へ引き伸ばさずに中央へ置く**
  /// （`cover-fallback.md`「正方形SVGを同色の縦長枠へ中央配置し、画像を引き伸ばさない」）。
  Widget _initials(CoverLabel label) => Center(
    child: label.svg == null
        ? Icon(Icons.book, color: Colors.white, size: width * 0.6)
        : SvgPicture.string(label.svg!, width: width, height: width),
  );
}
