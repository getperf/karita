/// 本棚の2画面が両方使う部品。**どちらの持ち物でもないものだけを置く。**
///
/// 一覧（`row.dart` を含む `view.dart`）と本の記録（`record.dart`）を別のライブラリへ
/// 割ったので、`_` の付いた名前は共有できない。**公開するのはここに置いたものだけ**で、
/// `karita_ui.dart` からは export しない — package の外から触れる必要は無い
/// （`lending/shared.dart` と同じ扱いである）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_domain/karita_domain.dart';

import '../composition.dart';
import '../density.dart';
import '../libraries/state.dart';
import 'state.dart';

ButtonStyle shelfButtonStyle(WidgetRef ref) => TextButton.styleFrom(
  minimumSize: Size(44, ref.watch(densityProvider).control),
);

Map<String, LibrarySystem> shelfLibraries(WidgetRef ref) {
  try {
    return ref.watch(librariesProvider);
  } catch (_) {
    // 館カタログの失敗でも書誌とレビューは読める。履歴は保存済みIDで示す。
    return const {};
  }
}

/// ［Amazonで見る］。**ISBN が無ければ何も出さない**（[shelfAmazonUrl]）。
///
/// 書影・書名はリンクにしない（2026-10-06）。貸出し画面では同じ見た目が「記録を開く」なので、
/// 外へ出る操作は名前の付いたボタンに分ける。[wide] は詳細の横幅いっぱいの形。
/// 一覧は「読みたい ›」「蔵書あり ›」と同じく `›` で行き先を示し、幅を詰めて1段に収める。
///
/// **開く前に元の画面を記録する**（`openAmazon`）。Amazon から［karita に送る］で戻ると、
/// 詳細（[wide]）から出たならその本の記録、一覧から出たなら一覧へ着地する
/// （`非公開資料:amazon-share-handoff.md` §2）。
class ShelfAmazonButton extends ConsumerWidget {
  const ShelfAmazonButton({required this.book, this.wide = false});
  final ShelfBook book;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = shelfAmazonUrl(book.isbn13);
    if (url == null) return const SizedBox.shrink();
    Future<void> open() async {
      try {
        await ref
            .read(compositionProvider)
            .openAmazon(url, bookId: wide ? book.id : null);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ブラウザーを開けませんでした。')));
        }
      }
    }

    final height = ref.watch(densityProvider).control;
    if (wide) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: ValueKey('shelf.amazon.${book.id}'),
          style: OutlinedButton.styleFrom(minimumSize: Size(0, height + 8)),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Amazonで見る'),
          onPressed: open,
        ),
      );
    }
    return TextButton(
      key: ValueKey('shelf.amazon.${book.id}'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size(0, height),
      ),
      onPressed: open,
      child: const Text(
        'Amazon ›',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        semanticsLabel: 'Amazonで見る',
      ),
    );
  }
}
