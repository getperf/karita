/// 詳細の下部に固定する操作バーと、そこから開く追加ダイアログ（2026-09-20）。
///
/// ## 置き場所は仕様が決めている
///
/// **Navbar の直上に置く**（`../karita-ui-probe/docs/ui-plan.md` §2「`貸出し` の取消バーなど、
/// 画面固有の下部操作がある場合は Navbar の直上に置く。本文には両方と重ならない下余白を
/// 確保する」）。
///
/// **外殻（`shell/shell.dart`）は触らない。** 詳細の本文を [Column] にして [Expanded] の下へ
/// 並べれば、`Scaffold` の `bottomNavigationBar` のすぐ上に出る。**下余白も計算しなくてよい**
/// — モックが `.selection-mode .screen { padding-bottom: 134px }` でやっているのは、
/// `position: fixed` のバーが本文へ重なるからである。
///
/// ## 取消は一括、追加はこの画面の中
///
/// どちらもモックに合わせた。理由は [LendingSelection]（一括）と [Lending.addBook]（追加）に
/// 書いてある。**バーを1つ作れば両方が載る。**
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';

import '../book_cover.dart';
import '../density.dart';
import '../libraries/state.dart';
import '../libraries/wording.dart';
import '../reservation/state.dart';
import '../shell/navigation.dart';
import 'shared.dart';
import 'state.dart';
import 'wording.dart';

/// 詳細の下部バー。**追加はいつでも、取消の確定は選択中だけ出る。**
class LendingActionBar extends ConsumerWidget {
  const LendingActionBar(this.systemId, {super.key});

  final String systemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selection = ref.watch(lendingSelectionProvider);
    final density = ref.watch(densityProvider);
    // **台帳から消えたシステムでは追加を出さない**（2026-09-20）。常用館を設定しに行く先が
    // 無く、受取館のリンクを押せなくしてあるのと同じ理由である。取消はそれでもできる。
    final known = ref.watch(libraryProvider(systemId)) != null;
    if (!known && !selection.active) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          // 取消の選択中は確定ボタンを優先して隠す。
          if (known && !selection.active)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('lending.calil.open'),
                style: FilledButton.styleFrom(
                  minimumSize: Size(0, density.control),
                ),
                onPressed: () => _openCalil(context, ref),
                child: const Text('カーリルで予約'),
              ),
            ),
          if (known)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey('lending.add.open'),
                // **破線の枠は採らない**（モックの `.bar-add` は `border-style: dashed`）。
                // [BorderSide] に破線が無く、1つのボタンのために [CustomPainter] を増やす
                // ほどの意味は無い。主色の枠で「本文ではなく足す操作」は十分に読める。
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, density.control),
                  foregroundColor: scheme.primary,
                  side: BorderSide(color: scheme.primary),
                ),
                onPressed: () => _openAdd(context, ref),
                child: const Text('台帳から追加'),
              ),
            ),
          if (selection.active)
            Row(
              spacing: 8,
              children: [
                // モックの `.bar-selection` は `.8fr 2fr`。**確定のほうを広く取る。**
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    key: const ValueKey('lending.cancel.dismiss'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, density.control),
                    ),
                    onPressed: ref.read(lendingSelectionProvider.notifier).end,
                    child: const Text('解除'),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: FilledButton(
                    key: const ValueKey('lending.cancel.commit'),
                    style: FilledButton.styleFrom(
                      minimumSize: Size(0, density.control),
                    ),
                    onPressed: selection.count == 0
                        ? null
                        : () {
                            ref
                                .read(lendingProvider.notifier)
                                .cancelSelected(selection.loanIds);
                            ref.read(lendingSelectionProvider.notifier).end();
                          },
                    child: Text(
                      lendingCancelCommitLabel(selection.count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 追加を開く。**常用館が決まっていない区では、そこで止めて図書館管理へ渡す。**
  ///
  /// `lending.md` §4 は「予約画面が保存直前に止め、図書館管理での設定へ誘導する」としている。
  /// **同じ規則を、保存まで進ませずに満たす** — 受取館は記録の必須項目なので、常用館が
  /// 決まっていない区では本を選んでも必ず `preferred-branch` で弾かれる。
  /// カーリルを開いて予約を始める。この区を初期選択にし、保存後はここへ戻る。
  Future<void> _openCalil(BuildContext context, WidgetRef ref) async {
    final preferred = ref.read(preferredBranchProvider(systemId));
    if (preferred.state != PreferredBranchState.resolved) {
      await _openPreferredBranchGate(context, ref, preferred);
      return;
    }
    await ref.read(reservationProvider.notifier).startFromLending(systemId);
  }

  Future<void> _openAdd(BuildContext context, WidgetRef ref) async {
    final preferred = ref.read(preferredBranchProvider(systemId));
    if (preferred.state != PreferredBranchState.resolved) {
      await _openPreferredBranchGate(context, ref, preferred);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _AddDialog(systemId),
    );
  }

  Future<void> _openPreferredBranchGate(
    BuildContext context,
    WidgetRef ref,
    PreferredBranch preferred,
  ) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('lending.add.preferred'),
        title: const Text('常用館が決まっていません'),
        content: Text(
          'この地区の受取館は常用館から決まります'
          '（いまは「${preferredBranchValue(preferred)}」）。'
          '図書館管理で選んでから追加してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('閉じる'),
          ),
          TextButton(
            key: const ValueKey('lending.add.preferred.open'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('図書館管理へ'),
          ),
        ],
      ),
    );
    if (go != true) return;
    // **直したら元の区へ帰す**（2026-09-19 の前例。区ヘッダーの［変更］と同じ経路）。
    openLibrariesFrom(
      ref,
      (notifier) =>
          notifier.openPreferredBranch(systemId, returnTo: ShellTab.lending),
    );
  }
}

/// 追加ダイアログ。**台帳に在る書誌から1冊選んで、予約中として記録する。**
///
/// **受取館は選ばせない**（`lending.md` §5「`予約` では館を選ばせない」）。モックには
/// `pickup-branch` の `<select>` があるが、`Reservations.save` は常用館を引く側で、選ばせる
/// 引数を持たない。**常用館を読み取り専用で出し**、違う館へ行くなら足した行の受取館リンク
/// から直す（§4）。
class _AddDialog extends ConsumerStatefulWidget {
  const _AddDialog(this.systemId);

  final String systemId;

  @override
  ConsumerState<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends ConsumerState<_AddDialog> {
  final _query = TextEditingController();
  String _filter = '';
  String? _picked;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final systemId = widget.systemId;
    final name = ref.watch(libraryProvider(systemId))?.name ?? systemId;
    final preferred = ref.watch(preferredBranchProvider(systemId));
    final candidates = [
      for (final book in ref.watch(lendingAddCandidatesProvider(systemId)))
        if (matchesAddQuery(book, _filter)) book,
    ];
    final picked = candidates.where((book) => book.id == _picked).firstOrNull;

    return AlertDialog(
      key: const ValueKey('lending.add.dialog'),
      title: Text('$nameへ図書を追加'),
      content: SizedBox(
        width: 420,
        // **高さは上限だけを決める**（2026-09-20 の直し）。固定にすると候補が数件のときに
        // 下が空き、多いときは末尾の行が注記へ食い込む。
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('lending.add.query'),
                controller: _query,
                decoration: const InputDecoration(labelText: '書名・著者・ISBN'),
                onChanged: (value) => setState(() => _filter = value.trim()),
              ),
              const SizedBox(height: 8),
              // **受取館は読み取り専用の1行である。** 選ばせない理由は class の解説。
              Text(
                '受取館 ${preferredBranchValue(preferred)}（常用館）',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: candidates.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          _filter.isEmpty
                              ? 'この地区へ足せる書誌がありません。'
                              : '該当する書誌がありません。',
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey('lending.add.list'),
                        shrinkWrap: true,
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final book = candidates[index];
                          return ListTile(
                            key: ValueKey('lending.add.book.${book.id}'),
                            selected: book.id == _picked,
                            leading: BookCoverView(
                              width: 28,
                              colorSeed: book.id,
                              title: book.title,
                              isbn13: book.isbn13,
                            ),
                            title: Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                book.authors.join(' '),
                                book.isbn13 ?? '',
                              ].where((part) => part.isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => setState(() => _picked = book.id),
                          );
                        },
                      ),
              ),
              // **一覧と注記の間に線を引く。** 候補が上限まで並ぶと、スクロールで切れた行が
              // 注記のすぐ上に来て、どこまでが一覧かが読めない。
              const Divider(height: 9),
              // **新しい書誌の入口はここではない**（`lending.md` §5・§6）。
              Text('ここに無い本は［カーリルで予約］から登録します。', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
        FilledButton(
          key: const ValueKey('lending.add.commit'),
          onPressed: picked == null
              ? null
              : () {
                  ref
                      .read(lendingProvider.notifier)
                      .addBook(systemId: systemId, book: picked);
                  Navigator.of(context).pop();
                },
          child: const Text('予約中で追加'),
        ),
      ],
    );
  }
}
