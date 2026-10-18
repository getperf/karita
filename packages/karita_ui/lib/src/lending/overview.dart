/// 貸出しの初期画面。**読み取り専用のサマリである。**
///
/// どの区へ行くかを決めるためにあり、**書き換えはここで起きない**（`lending.md` §2）。
/// 区の枠を押すと編集できる詳細（`area.dart`）へ入る。
///
/// ## 行の形（2026-09-20 の差し替え）
///
/// `吾輩は猫である  取置中  期限 2026-09-20` を **`▤ 吾輩は猫である [取] 09-20`** へ詰めた。
///
/// - 状態は**1文字のバッジ**にする（`loanStatusBadge`）。ここは押す場所ではないので、
///   3文字を読ませる必要が無い。
/// - 期限は `期限` の2文字と年を落として `MM-DD` だけにする。**年は区別に効かない** —
///   棚卸で見るのは常に目前の数週間である。
/// - バッジと期限を**固定幅の列**に入れる。期限を持たない `予約中` の行が来ても桁が動かず、
///   縦に目で追える。
/// - 左に**小さい書影**（28×40）を置く。区に何冊あっても、書名を読む前に「あの本だ」が
///   先に来る。取れないときは Initials が出る（`../book_cover.dart`）。
///
/// 元は「期限を持たない予約中は期限欄そのものを出さない」だったが、**欄は出してダッシュを
/// 置く**に改めた。欄ごと消すと右端が行ごとに動き、揃えるという目的と衝突する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_domain/karita_domain.dart';

import '../book_cover.dart';
import '../libraries/state.dart';
import 'shared.dart';
import 'state.dart';
import 'wording.dart';

class LendingOverview extends ConsumerWidget {
  const LendingOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lendingProvider);
    final theme = Theme.of(context);

    if (state.loadError != null) return LendingFailure(state.loadError!.code);
    List<LibrarySystem> systems = const [];
    String? librariesError;
    try {
      systems = ref.watch(libraryListProvider);
    } catch (error) {
      librariesError = lendingIssueCode(error);
    }
    if (librariesError != null) return LendingFailure(librariesError);

    final areas = state.areasFor(systems);
    return ListView(
      key: const PageStorageKey('lending.overview'),
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(child: Text('貸出し', style: theme.textTheme.titleLarge)),
            const LendingRefreshButton(),
          ],
        ),
        const SizedBox(height: 8),
        const _Filters(),
        if (state.unread && state.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (areas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('図書館がまだ登録されていません。設定の図書館管理から追加してください。'),
          )
        else
          for (final area in areas) _AreaCard(area),
      ],
    );
  }
}

/// フィルタ3種。**押す前に何件出るかを併記する**（`lending.md` §2）。
///
/// **同じ数字を並べる集計行を別に置かない。** 件数はここにしか出ない。
class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lendingProvider);
    final actions = ref.read(lendingProvider.notifier);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in LendingFilter.values)
          ChoiceChip(
            key: ValueKey('lending.filter.${filter.name}'),
            label: Text('${filter.label} ${state.countFor(filter)}'),
            selected: state.filter == filter,
            onSelected: (_) => actions.select(filter),
          ),
      ],
    );
  }
}

/// 管理区分1つの枠。**枠内全体がリンク領域である**（`lending.md` §2）。
class _AreaCard extends ConsumerWidget {
  const _AreaCard(this.area);

  final LendingArea area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: InkWell(
        key: ValueKey('lending.area.${area.systemId}'),
        onTap: () =>
            ref.read(lendingRouteProvider.notifier).openArea(area.systemId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(area.name, style: theme.textTheme.titleMedium),
                  ),
                  Text('${area.items.length}件 ›'),
                ],
              ),
              // **常用館は出さない**（2026-10-05）。全体一覧は区を選ぶ場で、常用館は
              // 区の詳細にある。未登録の警告だけは残す。
              if (!area.configured)
                Text(
                  'この図書館システムは登録されていません',
                  style: theme.textTheme.bodySmall,
                ),
              // **0件の枠には何も足さない**（2026-09-20）。`この条件に該当する図書は
              // ありません` は右肩の `0件 ›` と同じことを、本文の大きさでもう一度言って
              // いた。**枠そのものが残っていること**が「この区には無い」の答えであり
              // （`lending.md` §2「0 件の管理区分も非表示にしない」）、1行ぶんの高さを
              // 使ってまで言い直す内容ではない。区が5つあれば5行になる。
              if (area.items.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final item in area.items) _Summary(item),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 1行のサマリ。**書影・書名・状態のバッジ・期限を一行で出す。**
class _Summary extends StatelessWidget {
  const _Summary(this.item);

  final LoanReportItem item;

  /// 書影の幅。**28×40。** 1件あたり 44px 前後に収まり、区の枠に10件並べても読める。
  static const double _coverWidth = 28;

  /// 期限は文字拡大時にも末尾を欠かさず、予約中のダッシュも同じ列に揃える。
  static const double _deadlineWidth = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = isOverdue(item);
    // **期限切れは行ごと強調する。** 専用のフィルタも件数も設けない（`lending.md` §2）。
    final style = overdue
        ? TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w700)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          BookCoverView(
            width: _coverWidth,
            colorSeed: item.bookId,
            title: item.title,
            isbn13: item.isbn13,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.title,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _StatusBadge(status: item.status, overdue: overdue),
          const SizedBox(width: 8),
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(_deadlineWidth),
            child: Text(
              deadlineBadgeValue(deadlineOf(item)),
              style: style,
              textAlign: TextAlign.end,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// 状態の1文字。**色の付いた角丸へ入れる**（2026-09-20）。
///
/// **色だけで状態を示さない。** 中の1文字が正本で、地色は「同じ状態の行を縦に拾う」ための
/// 補助である。配色を落としても読める。
///
/// **地色は必ず `colorScheme` から採る**（`shell.dart` の「色は必ず配色から採る」）。
/// 3つを役割の違う container 色へ割り当てるので、明暗のどちらでも対比が保たれる。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.overdue});

  final String status;

  /// 期限を過ぎているか。**バッジごと `error` に寄せる。**
  final bool overdue;

  /// バッジの1辺。**書影の幅の 3/4 で、本文の行の高さに収まる。**
  static const double _size = 22;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = overdue
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : switch (status) {
            'ready_for_pickup' => (
              scheme.tertiaryContainer,
              scheme.onTertiaryContainer,
            ),
            'borrowed' => (scheme.primaryContainer, scheme.onPrimaryContainer),
            'reserved' => (
              scheme.surfaceContainerHighest,
              scheme.onSurfaceVariant,
            ),
            // 終端（返却済み・取消済み）は `↻ 更新` まで残る行である。**地に沈める。**
            _ => (scheme.surfaceContainerLow, scheme.outline),
          };
    return Tooltip(
      message: loanStatusLabel(status),
      child: Container(
        key: ValueKey('lending.badge.$status'),
        width: _size,
        height: _size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          loanStatusBadge(status),
          style: theme.textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
