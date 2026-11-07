/// 区の詳細の1行の**見た目だけ**。操作は呼び出し側がつなぐ（2026-10-31 に切り出し）。
///
/// 貸出しの詳細（`area.dart`）と、予約画面で区を選ぶときの確認画面
/// （`../reservation/preview.dart`）が同じ行を出す。**確認画面は貸出しと同じ表示にする**
/// （`../karita-ui-probe/docs/screens/reservation-preview.md` §3）ので、行の形を2か所に
/// 書かない。書き換えの処理・ダイアログは `area.dart` に残す。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_domain/karita_domain.dart';

import '../book_cover.dart';
import '../density.dart';
import 'shared.dart';
import 'state.dart';
import 'wording.dart';

/// 4つのボタン。**並びは `lending.md` の状態の並びどおりである。**
const List<(String, String, String)> loanStatusButtons = [
  ('予約中', 'reserve', 'reserved'),
  ('取置中', 'ready-for-pickup', 'ready_for_pickup'),
  ('貸出中', 'borrow', 'borrowed'),
  ('返却済', 'return', 'returned'),
];

/// 日付のセルに出す値。**予約中は期限の代わりに予約日を出す。**
///
/// 予約日は館サイトの並び（予約日順）と照らして直すためにある。期限と取り違えないよう、
/// セルは淡い色で出す（[LoanDateButton.muted]）。
String? loanRowDate(LoanReportItem item) =>
    item.status == 'reserved' ? item.reservedOn : deadlineOf(item);

class LoanRowView extends ConsumerWidget {
  const LoanRowView({
    super.key,
    required this.item,
    required this.status,
    this.keyPrefix = 'lending',
    this.danger = false,
    this.leaving = false,
    this.inert = false,
    this.mark,
    this.onOpenRecord,
    this.onPickBranch,
    this.onStatus,
    this.onPickDate,
    this.showReview = false,
    this.onReview,
    this.trailing,
  });

  final LoanReportItem item;

  /// 画面上の状態。終端へ書いた直後は台帳の行と違うことがある（`LendingState.statusOf`）。
  final String status;

  /// 部品の `ValueKey` の頭。**同じ行を出す画面ごとに分ける。**
  final String keyPrefix;
  final bool danger;
  final bool leaving;

  /// **読むだけの行。** ボタンは押せないが、押せる行と同じ色で出す。淡くすると
  /// 「今の状態」が読み取れなくなる — 確認画面が見せたいのはそれである。
  final bool inert;

  /// 書名の前に置く短い印（確認画面の「同じ本」）。
  final String? mark;

  /// 書影と書名から本の記録へ渡す。`null` ならリンクにしない（下線も引かない）。
  final VoidCallback? onOpenRecord;

  /// 受取館を選び直す。`null` で押せない。[inert] では文字だけにする。
  final VoidCallback? onPickBranch;
  final void Function(String action)? onStatus;
  final VoidCallback? onPickDate;

  /// 返却済みにした行の［レビュー］。
  final bool showReview;
  final VoidCallback? onReview;

  /// 行の右端（取消の選択のチェックボックス）。
  final Widget? trailing;

  /// 書影の幅。**48×68**（2026-09-20）。右の中身は 24＋8＋44 でおよそ 76px なので、
  /// 書影が行の高さを決めることはない。
  static const double coverWidth = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final density = ref.watch(densityProvider);
    final dateWidth = density.pointer == PointerKind.touch ? 76.0 : 66.0;
    final linked = onOpenRecord != null;
    Widget recordLink(Widget child) => !linked
        ? child
        : InkWell(
            key: ValueKey('$keyPrefix.record.${item.bookId}'),
            onTap: onOpenRecord,
            // **書影の角に合わせる。** 押した跡が四角く出ると、書影から浮く。
            borderRadius: BorderRadius.circular(6),
            child: child,
          );
    final controls = _controls(context, density, dateWidth);

    Widget layout({required bool narrow}) {
      final header = Row(
        // **書影は行の頭に付ける。** 中身の高さは注記の有無で変わるので、中央寄せにすると
        // 同じ枠の中で書影の位置が行ごとに上下する。
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          recordLink(
            BookCoverView(
              width: coverWidth,
              colorSeed: item.bookId,
              title: item.title,
              isbn13: item.isbn13,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mark != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _Mark(mark!),
                  ),
                // **書名と受取館は2行に分ける**（2026-10-05）。受取館名が長いと、同じ行では
                // 書名が1〜2文字まで潰れた（狭い Android の窓）。書名が全幅を使い、受取館は
                // 直下で省略する。受取館はリンクで、押すとその Loan だけの受取館を選び直す。
                // **常用館は動かない。**
                recordLink(
                  Text(
                    item.title,
                    // **本文の大きさで出す**（2026-09-19）。`titleSmall` では
                    // 小さすぎた。モックの `.book-title` は地の文と同じ大きさの
                    // 太字である。
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: danger ? theme.colorScheme.error : null,
                      // **色だけでリンクを示さない**（`lendingLinkStyle` と同じ
                      // 理由）。書名は色を期限超過にも使うので、下線が唯一の
                      // 配色に依存しない手がかりである。
                      decoration: linked ? TextDecoration.underline : null,
                      decorationColor: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: inert
                      // **読むだけの行の受取館は文字にする。** 押せない下線は、押せる
                      // リンクと見分けが付かない。
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Text(
                            pickupLibraryLabel(item),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : TextButton(
                          key: ValueKey('$keyPrefix.branch.${item.loanId}'),
                          style: lendingLinkStyle(context),
                          onPressed: onPickBranch,
                          child: Text(
                            pickupLibraryLabel(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                ),
                if (!item.bookAvailable) const Text('この記録の書誌が台帳にありません。'),
                if (!item.effective)
                  Text(duplicateNote(), style: theme.textTheme.bodySmall),
                if (parallelNote(item) case final note?)
                  Text(note, style: theme.textTheme.bodySmall),
                if (!narrow) ...[const SizedBox(height: 8), ...controls],
              ],
            ),
          ),
          ?trailing,
        ],
      );
      if (!narrow) return header;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, const SizedBox(height: 8), ...controls],
      );
    }

    return Container(
      // **行に余白と区切りを入れる**（2026-09-19）。モックの `.book-row` は
      // `padding: 5px` と `border-bottom` を持つ。詰めて並べると、どこまでが1冊かが
      // 読み取れない。
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      // **狭い幅では状態ボタンを書影の下へ出し、行の全幅を使う**（2026-11-06）。
      // 書影の右に並べると、iPhone 12 mini（375pt）の確認画面で1つ 42pt ほどになり、
      // 「予約中」が「予…」に潰れた。
      child: LayoutBuilder(
        builder: (context, constraints) {
          final beside =
              constraints.maxWidth -
              coverWidth -
              10 -
              (trailing == null ? 0 : 48);
          return layout(narrow: beside < minControlsWidth(dateWidth));
        },
      ),
    );
  }

  /// 状態ボタンが潰れずに並ぶ幅。**1つ 52 ＝ 3文字の地の文＋左右の余白。**
  static double minControlsWidth(double dateWidth) =>
      loanStatusButtons.length * 52 + loanStatusButtons.length * 4 + dateWidth;

  List<Widget> _controls(
    BuildContext context,
    Density density,
    double dateWidth,
  ) {
    return [
      // **4つの状態を均等に、期限だけ固定幅で並べる**（モックの `.book-controls` は
      // `repeat(4, minmax(0, 1fr)) 76px`）。
      //
      // **期限を5等分に混ぜない**（2026-09-19 の直し）。出るのは `09/20` の5文字だけ
      // なので、状態ボタンと同じ幅を与えると横に空白が広がる。
      Row(
        // **間隔は [Row] に入れさせる。** 各セルの中へ padding を置くと最後の1つだけが
        // 広くなり、4つの均等が崩れる。
        spacing: 4,
        children: [
          for (final (label, action, target) in loanStatusButtons)
            Expanded(
              child: LoanStatusButton(
                key: ValueKey('$keyPrefix.$action.${item.loanId}'),
                label: label,
                selected: status == target,
                height: density.control,
                inert: inert,
                onPressed: onStatus == null ? null : () => onStatus!(action),
              ),
            ),
          SizedBox(
            width: dateWidth,
            child: LoanDateButton(
              key: ValueKey('$keyPrefix.date.${item.loanId}'),
              deadline: leaving ? null : loanRowDate(item),
              muted: item.status == 'reserved',
              height: density.control,
              inert: inert,
              onPressed: onPickDate,
            ),
          ),
        ],
      ),
      // **返却済みにした行にだけ、下の行へレビューの入口を出す。** 状態ボタンと同じ
      // 列割りで、「返却済」の真下に置く。
      if (showReview) ...[
        const SizedBox(height: 4),
        Row(
          spacing: 4,
          children: [
            for (var i = 0; i < loanStatusButtons.length - 1; i++)
              const Expanded(child: SizedBox.shrink()),
            Expanded(
              child: LoanStatusButton(
                key: ValueKey('$keyPrefix.review.${item.loanId}'),
                label: 'レビュー',
                selected: false,
                height: density.control,
                onPressed: onReview,
              ),
            ),
            SizedBox(width: dateWidth),
          ],
        ),
      ],
    ];
  }
}

/// 書名の前の短い印。**枠と文字で示し、色だけに頼らない。**
class _Mark extends StatelessWidget {
  const _Mark(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.primary),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 状態の1つ。**選択中は枠と淡い地色で示す**（モックの `.status-button.active`）。
///
/// **地色は淡くする**（2026-09-19 の直し）。`primaryContainer` は配色によっては濃く出て、
/// 4つ並んだ中の1つが**行の主役より目立つ。** 行の主役は書名である。モックの
/// `--brand-soft`（`#dff0ed`）は地に近い薄さなので、こちらも主色の薄い被せにする。
///
/// **枠は1px。** 2px は選択を強めるが、隣の3つとの太さの差が行の輪郭より強くなる。
class LoanStatusButton extends StatelessWidget {
  const LoanStatusButton({
    super.key,
    required this.label,
    required this.selected,
    required this.height,
    required this.onPressed,
    this.inert = false,
  });

  final String label;
  final bool selected;

  /// 操作要素の高さ。**ポインタで決まる**（`density.dart`。モックも触44／精30）。
  final double height;

  final VoidCallback? onPressed;

  /// 押せないが、押せるときと同じ色で出す（[LoanRowView.inert]）。
  final bool inert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = selected ? scheme.primary.withValues(alpha: 0.10) : null;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: Size(0, height),
        // **地の文と同じ大きさにする**（2026-09-19 の直し）。13px では小さすぎた。
        // **配色の書体から作る** — 素の [TextStyle] は `fontFamily` ごと置き換える。
        textStyle: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
        // 主色の薄い被せ。**明暗のどちらでも地に近い濃さになる。**
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: inert ? background : null,
        disabledForegroundColor: inert ? foreground : null,
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      // **省略せずに縮める**（2026-11-06）。「予…」「取…」では4つの見分けが付かない。
      // 全幅に出しても、文字を大きくした端末では収まらないことがある。
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
    );
  }
}

/// 期限のセル。**`MM/DD`。持たない状態では `--/--`。**
class LoanDateButton extends StatelessWidget {
  const LoanDateButton({
    super.key,
    required this.deadline,
    required this.height,
    required this.onPressed,
    this.muted = false,
    this.inert = false,
  });

  /// `YYYY-MM-DD`。無ければ `null`。
  final String? deadline;

  /// 期限ではない日付（予約日）。**淡い色で出し、期限と見分ける。**
  final bool muted;

  final double height;

  final VoidCallback? onPressed;

  /// 押せないが、押せるときと同じ色で出す（[LoanRowView.inert]）。
  final bool inert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = deadline != null && deadline!.length == 10
        ? '${deadline!.substring(5, 7)}/${deadline!.substring(8, 10)}'
        : '--/--';
    final foreground = muted ? scheme.onSurfaceVariant : scheme.onSurface;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size(0, height),
        foregroundColor: foreground,
        disabledForegroundColor: inert ? foreground : null,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Text(value, maxLines: 1),
    );
  }
}
