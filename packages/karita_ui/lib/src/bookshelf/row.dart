/// 本棚一覧の1行と、一覧ヘッダーの「蔵書を確認」。
///
/// **行は一覧の持ち物である。** `view.dart` から割ったのは大きさの都合だけで、層で切った
/// のではない（`karita_ui.dart` の「中の並べ方」）。行が知っているのは1冊の `ShelfBook` と
/// 「開く」の合図だけで、絞込みも選択も `view.dart` の側に残してある。
///
/// 蔵書の状態・語・色は `holdings.dart`、色の数値は `../theme.dart` が持つ。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';

import '../book_cover.dart';
import '../composition.dart';
import '../density.dart';
import '../theme.dart';
import 'holdings.dart';
import 'shared.dart';
import 'state.dart';

/// 「蔵書を確認」と、押した結果の案内。**未照会はこのボタンの存在が表す。**
///
/// 照会できない端末・登録館が無い端末では、ボタンの代わりに理由を出す（正本の表の語）。
/// **ボタンを黙って消さない** — 消すと「蔵書は出ないもの」に見え、設定で直せることが伝わらない。
class CheckHoldingsButton extends ConsumerWidget {
  const CheckHoldingsButton({required this.wanted});

  /// いま絞込みに出ている読みたての行。**全読みたてではない。**
  final List<ShelfBook> wanted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usable = ref.watch(holdingsLookupProvider) != null;
    final libraries = shelfLibraries(ref);
    if (!usable) {
      return Text('蔵書照会を利用できません。', style: theme.textTheme.bodySmall);
    }
    if (libraries.isEmpty) {
      return Text('図書館を登録してください。', style: theme.textTheme.bodySmall);
    }
    final run = ref.watch(shelfHoldingsProvider);
    final notice = shelfHoldingsNotice(run, canCheck: true);
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          key: const ValueKey('shelf.holdings.check'),
          style: shelfButtonStyle(ref),
          icon: run.running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.local_library_outlined),
          label: Text(run.running ? '確認中…' : '蔵書を確認'),
          // **走っている間は押せない。** 二重に走らせると枠を二重に使う。
          onPressed: run.running || wanted.isEmpty
              ? null
              : () => unawaited(
                  ref.read(shelfHoldingsProvider.notifier).run(wanted),
                ),
        ),
        if (notice.isNotEmpty)
          Text(
            notice,
            key: const ValueKey('shelf.holdings.notice'),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// 一覧の1行。**モックの `.book-row`。**
///
/// 書影と書名を先に置き、状態と蔵書は本文の下段に置く。
/// 狭い Android でも書影を隠さず、Windows でも書名の幅を確保する。
///
/// **［Amazon ›］は書名の右、下段は 開く・外す・蔵書 の3列である**（2026-10-14）。
/// 外へ出るリンクを上へ離し、下段を本棚の中の操作にそろえた。代わりに書名の幅が
/// Amazon ぶん減る。
class ShelfRow extends ConsumerWidget {
  const ShelfRow({required this.book, required this.onOpen});
  final ShelfBook book;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final url = shelfCalilUrl(book.isbn13);
    // 補助情報は1行にまとめる。**行ごとに1本増えると、件数ぶん縦に効く。**
    final meta = [
      if (book.state == 'read')
        '${book.reason}'
            '${book.latestReturn == null ? '' : '・返却日 ${book.latestReturn}'}',
      // 読みたいと予約中は併存する。手続き中は本棚からも分かるようにする。
      if (book.activeStatuses.isNotEmpty)
        book.activeStatuses.map(_loanLabel).join('・'),
    ].join('・');
    return Container(
      key: ValueKey('shelf.row.${book.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCoverView(
            width: 48,
            colorSeed: book.id,
            title: book.title,
            isbn13: book.isbn13,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // **Amazon は書名と著者の2行ぶんの右に置く。** 押せる高さ（44px）を書名の
                // 1行だけに並べると、1行の書名の下に著者との隙間が空く。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            book.authors.join('・'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    // ISBN が無ければ出さず、書名が幅いっぱいを使う。
                    if (shelfAmazonUrl(book.isbn13) != null)
                      ShelfAmazonButton(book: book),
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(meta, style: theme.textTheme.bodySmall),
                // 未確認の館が残っているときだけ出す。語は下段のバッジが持つ。
                if (book.state == 'wanted') _HoldingsDetail(book: book),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final status = _StateBadge(book: book, onOpen: onOpen);
                    final rating = book.rating == null
                        ? null
                        : Row(
                            key: ValueKey('shelf.rating.${book.id}'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              Text(
                                '${book.rating}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          );
                    final holdings = book.state == 'wanted'
                        ? _HoldingsBadge(book: book, url: url)
                        : null;
                    final remove = _RemoveButton(book: book);
                    // 拡大文字や狭い幅では2行に逃がし、蔵書表示を右に揃える。
                    // 240 は「読みたい ›」「外す」「蔵書未確認」が標準の文字で1段に収まる幅
                    // （Android 実機の行幅は約280）。
                    final stacked =
                        holdings != null &&
                        (constraints.maxWidth < 240 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.3);
                    // 左の札は足りなければ縮めて省略する。**はみ出させない** — 文字の幅は
                    // 書体と拡大率で変わり、上の閾値だけでは守り切れない。
                    final leading = Row(
                      children: [
                        Flexible(child: status),
                        const SizedBox(width: 4),
                        remove,
                        if (rating != null) ...[
                          const SizedBox(width: 8),
                          rating,
                        ],
                      ],
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          leading,
                          Align(
                            alignment: Alignment.centerRight,
                            child: holdings,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: leading),
                        if (holdings != null) holdings,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 本の記録へ入る札。書名の下に置き、書影と書名の幅を奪わない。
class _StateBadge extends ConsumerWidget {
  const _StateBadge({required this.book, required this.onOpen});
  final ShelfBook book;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final wanted = book.state == 'wanted';
    final tone = wanted
        ? karitaWantedTone(theme.brightness)
        : karitaReadTone(theme.brightness);
    final height = ref.watch(densityProvider).control;
    return TextButton(
      key: ValueKey('shelf.open.${book.id}'),
      onPressed: onOpen,
      style: TextButton.styleFrom(
        backgroundColor: tone.background,
        foregroundColor: tone.foreground,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size(0, height),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        // **配色の書体から作る** — 素の [TextStyle] は `fontFamily` ごと置き換える。
        textStyle: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(
        '${wanted ? '読みたい' : '読んだ'} ›',
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 一覧から本棚を外す。**誤って載せた本を、記録を開かずに外すための口**（2026-10-14）。
///
/// 語は2文字にする — 「本棚から外す」では狭い Android で3列が1段に収まらない。何を外すかは
/// 確認の文で言う。**確認は省かない**（よく押す［読みたい ›］の隣に全行並ぶ）。地を塗らず
/// 控えめな色にして、行の主役より目立たせない。
///
/// 外した行は台帳の読み直しで一覧から落ちる。一覧には留まり、結果は SnackBar で出す。
class _RemoveButton extends ConsumerWidget {
  const _RemoveButton({required this.book});
  final ShelfBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Future<void> remove() async {
      final ok =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              content: const Text('本棚から外しますか？レビューと履歴は保持します。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('やめる'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('続ける'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok || !context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      String text;
      try {
        ref.read(compositionProvider).setShelfState(book.id, 'removed');
        text = '本棚から外しました。';
      } catch (_) {
        text = '本棚から外せませんでした。';
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(text),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }

    return TextButton(
      key: ValueKey('shelf.remove.${book.id}'),
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size(44, ref.watch(densityProvider).control),
      ),
      onPressed: remove,
      child: const Text('外す', maxLines: 1, semanticsLabel: '本棚から外す'),
    );
  }
}

/// 蔵書サマリのバッジ。**これ自体がカーリルへのリンクである。**
///
/// バッジと `カーリル ›` を2行に分けていたのをやめた（2026-09-21 の実機確認）— 同じことを
/// 2回言っており、行が縦に伸びていた。状態を見た人がそのまま押せる形を保ち、
/// 書名の下段に置く。
///
/// 色は4つ。**借りられる見込みの順**である。
///
/// | 状態 | 語 | 色 |
/// |---|---|---|
/// | `貸出可` | 蔵書あり | 主色の塗り（緑） |
/// | `貸出中` | 貸出し中 | 琥珀 |
/// | `予約中`・`準備中` | 準備中 | 水色 |
/// | `館内のみ`・`休館中`・`不明`・未知 | 貸出し不可 | 灰 |
/// | 全館完了で所蔵なし | 蔵書なし | 灰 |
/// | 確認中・確認できません | それぞれの語 | 灰 |
/// | 未照会・館なし・キーなし | 蔵書未確認 | 灰・**押せない** |
/// | ISBNなし | 照会不可 | 灰・**行き先が無い** |
class _HoldingsBadge extends ConsumerWidget {
  const _HoldingsBadge({required this.book, required this.url});
  final ShelfBook book;
  final Uri? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = shelfHoldings(ref, book);
    final label = shelfHoldingsBadge(summary);
    if (label.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // ISBN が無ければリンクは作れない。**状態が押せても URL が無ければ押せない。**
    final linked = shelfHoldingsLinked(summary) && url != null;
    final tone = switch (summary.state) {
      HoldingsState.available => (
        background: scheme.primary,
        foreground: scheme.onPrimary,
      ),
      HoldingsState.borrowed => karitaBorrowedTone(theme.brightness),
      HoldingsState.preparing => karitaPreparingTone(theme.brightness),
      // 貸出し不可・蔵書なし・未確認・確認中・失敗。**地に近い灰である。**
      _ => (background: scheme.surface, foreground: scheme.onSurfaceVariant),
    };
    final filled = summary.state == HoldingsState.available;
    return TextButton(
      key: ValueKey('shelf.holdings.${book.id}'),
      // **押せないのは `蔵書未確認` と `照会不可` だけである。** 前者はまだ何も聞いておらず、
      // 後者は行き先が作れない。確認中・確認できませんは押せる — **こちらが答えを持って
      // いないときこそ、実サイトで見たい場面である。**
      onPressed: linked
          ? () async {
              try {
                await ref.read(compositionProvider).openSite(url!);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ブラウザーを開けませんでした。')),
                  );
                }
              }
            }
          : null,
      style: TextButton.styleFrom(
        backgroundColor: tone.background,
        foregroundColor: tone.foreground,
        // **押せなくても色を保つ。** 既定の `disabledForegroundColor` は地に沈むので、
        // 「蔵書未確認」が読めなくなる。淡くするのは文字ではなく押せることの側である。
        disabledBackgroundColor: tone.background,
        disabledForegroundColor: tone.foreground,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size(0, ref.watch(densityProvider).control),
        shape: RoundedRectangleBorder(
          // 角丸の四角で、押せる札として示す。
          borderRadius: BorderRadius.circular(12),
          // 塗りのないものは輪郭で形を出す。**押せるものは実線、押せないものは点で示す**
          // ほどの差は付けず、色と反応だけで区別する。
          side: filled
              ? BorderSide.none
              : BorderSide(
                  color: linked ? tone.foreground : scheme.outlineVariant,
                ),
        ),
        // **配色の書体から作る** — 素の [TextStyle] は `fontFamily` ごと置き換える。
        textStyle: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(
        linked ? '$label ›' : label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 未確認の館の数。**語そのものは右端のバッジが持つ。**
///
/// 分けてあるのは幅のためである。丸バッジに「2館未確認」まで入れると、行の主役である書名より
/// 幅を取る。**照会結果で本棚状態も Loan も書き換えない。**
class _HoldingsDetail extends ConsumerWidget {
  const _HoldingsDetail({required this.book});
  final ShelfBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(shelfHoldingsProvider.select((run) => run.checked))) {
      return const SizedBox.shrink();
    }
    final detail = shelfHoldingsDetail(shelfHoldings(ref, book));
    if (detail.isEmpty) return const SizedBox.shrink();
    return Text(
      detail,
      key: ValueKey('shelf.holdings.detail.${book.id}'),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

String _loanLabel(String status) => switch (status) {
  'reserved' => '予約中',
  'ready_for_pickup' => '取置中',
  'borrowed' => '貸出中',
  _ => status,
};
