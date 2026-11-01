/// 1管理区分の詳細。**書き換えが起きるのはこの1枚だけである**（`lending.md` §2）。
///
/// ## 行の形（2026-09-19 の差し替え）
///
/// モック（`../karita-ui-probe/mock/index.html`）に合わせた。**4つの状態ボタンと期限を
/// 1行に均等で並べ、どれも常に押せる。** 前の版は遷移表に合わせてボタンを出し分けていたが、
/// **その規則ごと業務層から落とした**（`karita_domain` の `loanActions`）。館サイトがそう
/// 見せているならそう記録できる、が棚卸の作法である。
///
/// ## 書影を左へ（2026-09-20）
///
/// **行を「書影｜中身」の1ブロックにする。** 書名＋受取館の行と、状態＋期限の行は積んだまま
/// 書影の右へ入る。**状態ボタンを書名と同じ行へ寄せない** — 4つを均等に並べる幅が要り、
/// 440dp 未満の窓では1〜2文字まで潰れて狙いが読めなくなる。寸法は 48×68
/// （`../book_cover.dart` が比を持つ）。
///
/// **スクロール位置を保つ**（`lending.md` §4）。ブラウザーへ往復しても、戻ったときに同じ
/// 場所に居る。[PageStorageKey] が区ごとの位置を覚える。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_domain/karita_domain.dart';

import '../bookshelf/state.dart';
import '../density.dart';
import '../libraries/state.dart';
import '../libraries/wording.dart';
import '../shell/navigation.dart';
import 'action_bar.dart';
import 'row.dart';
import 'shared.dart';
import 'state.dart';

class LendingAreaDetail extends ConsumerWidget {
  const LendingAreaDetail(this.systemId, {super.key});

  final String systemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lendingProvider);
    final actions = ref.read(lendingProvider.notifier);
    final theme = Theme.of(context);
    final system = ref.watch(libraryProvider(systemId));
    final preferred = system == null
        ? null
        : ref.watch(preferredBranchProvider(systemId));
    final name =
        system?.name ??
        state.rows.values
            .firstWhere(
              (row) => row.systemId == systemId,
              orElse: () => throw StateError(systemId),
            )
            .systemName;

    final sections = [
      for (final section in LendingSection.values)
        (section, state.sectionOf(systemId, section)),
    ];
    final total = sections.fold<int>(0, (n, entry) => n + entry.$2.length);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(lendingRouteProvider.notifier).back();
      },
      child: Column(
        children: [
          Expanded(
            child: ListView(
              // **区ごとに位置を覚える。** ブラウザーから戻っても同じ場所に居る。
              key: PageStorageKey('lending.area.$systemId'),
              padding: const EdgeInsets.all(14),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      key: const ValueKey('lending.back'),
                      onPressed: ref.read(lendingRouteProvider.notifier).back,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: '管理地区へ戻る',
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: theme.textTheme.titleLarge),
                          // **［変更］は常用館のすぐ隣に置く**（2026-09-19）。押す先は図書館管理で、
                          // 編集はあちらに集約してある（`lending.md` §4）。行の受取館とは別物で、
                          // 隣り合っていないと「どちらを変えるのか」が読み取れない。
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                system == null
                                    ? '図書 $total件・この図書館システムは登録されていません'
                                    : '図書 $total件・常用館 ${preferredBranchValue(preferred!)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              TextButton(
                                key: const ValueKey('lending.preferred.change'),
                                style: lendingLinkStyle(context),
                                onPressed: () => openLibrariesFrom(
                                  ref,
                                  (notifier) => notifier.openPreferredBranch(
                                    systemId,
                                    // **直したら元の区へ帰す**（2026-09-19）。図書館管理の一覧に
                                    // 放り出されると、棚卸の続きまでが遠い。
                                    returnTo: ShellTab.lending,
                                  ),
                                ),
                                child: const Text('変更'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const LendingRefreshButton(),
                    const _SelectionButton(),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => actions.openSite(systemId),
                    icon: const Icon(Icons.open_in_new),
                    label: Text('$nameの図書館サイトを開く'),
                  ),
                ),
                _MypageUrlPanel(systemId),
                for (final (section, ids) in sections) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          section.heading,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        section.note.isEmpty
                            ? '${ids.length}冊'
                            : '${section.note} ${ids.length}冊',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (ids.isEmpty)
                    Text('${section.heading}の図書はありません')
                  else
                    for (final loanId in ids)
                      _Row(
                        key: ValueKey('lending.row.$loanId'),
                        loanId: loanId,
                      ),
                ],
              ],
            ),
          ),
          LendingActionBar(systemId),
        ],
      ),
    );
  }
}

/// マイページ URL の現在値。**［URL変更］で開く**（モックの `url-edit-accordion`）。
///
/// **小さく出す**（2026-09-19）。主役は上の［図書館サイトを開く］で、これはその補助である。
/// Card と既定の [ExpansionTile] では、開く操作と同じ重さに見えてしまっていた。枠を外し、
/// 高さを詰め、文字も小さくする。
///
/// **ここでは編集しない。** 出典つきの現在値を見せ、［変更］から図書館管理の編集画面へ渡す
/// （`mypage-url-editing.md`）。取り込み・検証・保存の規則をこの画面が二重に持たない。
class _MypageUrlPanel extends ConsumerWidget {
  const _MypageUrlPanel(this.systemId);

  final String systemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final url = ref.watch(mypageUrlProvider(systemId));
    return Theme(
      // **[ExpansionTile] の仕切り線を消す。** 枠が無いので、開閉で線だけが現れると浮く。
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // **`PageStorageKey` でなければならない**（2026-09-19 の障害）。[ExpansionTile] は
        // 開閉を `PageStorage` へ預ける（`expansible.dart`）。格納先は「自分から上へ辿って
        // 集めた [PageStorageKey] の並び」で決まるので、素の `ValueKey` だと識別子が祖先の
        // [ListView] の `PageStorageKey('lending.area.…')` **だけ**になり、スクロール位置
        // （`double`）と同じ棚を共有する。次に開いたとき `readState(context) as bool?` が
        // `double` を受けて落ちる。**自分の鍵を持てば棚が分かれる。**
        key: const PageStorageKey('lending.url.panel'),
        title: Text(
          'URL変更',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
        ),
        dense: true,
        visualDensity: VisualDensity.compact,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  url.value?.isNotEmpty == true ? url.value! : '未設定',
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                key: const ValueKey('lending.url.change'),
                style: lendingLinkStyle(context),
                onPressed: () => openLibrariesFrom(
                  ref,
                  (notifier) => notifier.openMypageUrl(
                    systemId,
                    returnTo: ShellTab.lending,
                  ),
                ),
                child: const Text('変更'),
              ),
            ],
          ),
          // **出典は必ず出す**（`library-site-url.md` §3）。既定値は作者が確認した時点の値で、
          // 館サイトの更新で切れる。切れたことをアプリは検知できない。
          Text(
            '出典: ${mypageSourceLabel(url.source)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 一括取消へ入る。**ヘッダーの `↻ 更新` の隣に置く**（`lending.md` §2）。
///
/// **選択中は押せない。** 出口は下部バーの［解除］1本で、入口と出口が同じ場所に並ぶと
/// どちらを押したのかが読み取れない（モックの `toggle-selection` も `disabled` にする）。
class _SelectionButton extends ConsumerWidget {
  const _SelectionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
    key: const ValueKey('lending.cancel.begin'),
    onPressed: ref.watch(lendingSelectionProvider).active
        ? null
        : ref.read(lendingSelectionProvider.notifier).begin,
    child: const Text('取消'),
  );
}

/// 行1つ。**左に書影、右にタイトルと受取館、その下に4つの状態と期限。**
///
/// **どのボタンも常に押せる。** 出し分けの規則は業務層から落としてある
/// （`karita_domain` の `loanActions`）。連続操作でも行は動かない — 枠と位置を握っているのは
/// 状態の側である。
class _Row extends ConsumerWidget {
  const _Row({super.key, required this.loanId});

  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lendingProvider);
    final actions = ref.read(lendingProvider.notifier);
    final item = state.rows[loanId];
    if (item == null) return const SizedBox.shrink();
    final status = state.statusOf(loanId);
    final busy = state.busyLoanId == loanId;
    final leaving = state.leaving.containsKey(loanId);
    final branches = ref.watch(lendingBranchesProvider(item.systemId));
    // **選択中は状態と期限を押せなくする**（モックの
    // `.selection-mode .book-controls { pointer-events: none }`）。いま選んでいるのは
    // 「どの行を取消すか」であって、1行の状態ではない。
    final selection = ref.watch(lendingSelectionProvider);
    final selecting = selection.active;
    final density = ref.watch(densityProvider);

    return LoanRowView(
      item: item,
      status: status,
      danger: !leaving && isOverdue(item),
      leaving: leaving,
      // **書影と書名から本の記録へ渡す**（2026-09-21）。貸出しの行が指している1冊を、
      // 本棚の側で見る導線である。**選んでいる最中は渡さない** — いま選んでいるのは
      // 「どの行を取消すか」で、その途中で画面が変わると選択が消える。
      // **閉じたらこの区へ帰す**（［レビュー］と同じ）。戻る・外す・保存のどれでも。
      onOpenRecord: selecting
          ? null
          : () => openShelfRecord(ref, item.bookId, returnTo: ShellTab.lending),
      onPickBranch: busy || branches.isEmpty
          ? null
          : () => _pickBranch(context, ref, item, branches),
      onStatus: busy || selecting
          ? null
          : (action) => actions.apply(loanId: loanId, action: action),
      onPickDate: busy || selecting || leaving || _dateActionFor(status) == null
          ? null
          : () => _pickDate(context, ref, item, status),
      // 自動では移らない — 棚卸は何冊も続けて直す作業で、返すたびに画面が変わると中断する。
      // 押したときだけ本棚の記録へ渡し、閉じたらこの区へ帰る。選んでいる最中は出さない。
      showReview: status == 'returned' && !selecting,
      onReview: busy
          ? null
          : () => openShelfRecord(ref, item.bookId, returnTo: ShellTab.lending),
      // **終端にした行にはチェックボックスを出さない**（モックも同じ）。もう終わって
      // いる行を取消しても書くものが無く、選べると件数だけが増える。
      trailing: selecting && !leaving
          ? SizedBox(
              width: density.control,
              height: density.control,
              child: Checkbox(
                key: ValueKey('lending.select.$loanId'),
                // **当たり判定は密度トークンで決める**（`density.dart`）。Material の
                // 既定は 48px 固定で、触44／精32 のどちらとも合わない。
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                value: selection.contains(loanId),
                onChanged: (_) =>
                    ref.read(lendingSelectionProvider.notifier).toggle(loanId),
              ),
            )
          : null,
    );
  }

  /// 日付を直す操作。**予約中は予約日を直す**（2026-10-20）。返却済は無い。
  static String? _dateActionFor(String status) => switch (status) {
    'reserved' => 'correct-reserved-date',
    'ready_for_pickup' => 'correct-pickup-due-date',
    'borrowed' => 'correct-due-date',
    _ => null,
  };

  /// 期限を選ぶ。**日を押した時点で確定する。OK は置かない**（2026-09-19）。
  ///
  /// `showDatePicker` は OK／キャンセルを持つ。棚卸は館サイトを見ながら何件も直す作業で、
  /// 1件ごとに確定の1タップが増えるのは重い。[CalendarDatePicker] を自前のダイアログへ入れ、
  /// 日を選んだ時点で閉じて確定する。
  ///
  /// **キャンセルは置く。** 確定が1タップである以上、**開いてしまったこと自体からの出口**が
  /// 要る。押し間違えて開いたときに、外側を押す以外の逃げ道が無いと詰まる。
  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    LoanReportItem item,
    String status,
  ) async {
    final action = _dateActionFor(status);
    if (action == null) return;
    final now = DateTime.now();
    final current = DateTime.tryParse(loanRowDate(item) ?? '') ?? now;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: CalendarDatePicker(
                  initialDate: current,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 2),
                  onDateChanged: (value) => Navigator.of(context).pop(value),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: TextButton(
                    key: const ValueKey('lending.date.cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('キャンセル'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    final value = picked.toIso8601String().substring(0, 10);
    ref
        .read(lendingProvider.notifier)
        .apply(
          loanId: loanId,
          action: action,
          reservedOn: action == 'correct-reserved-date' ? value : null,
          pickupDueOn: action == 'correct-pickup-due-date' ? value : null,
          dueOn: action == 'correct-due-date' ? value : null,
        );
  }

  Future<void> _pickBranch(
    BuildContext context,
    WidgetRef ref,
    LoanReportItem item,
    List<Branch> branches,
  ) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('受取館を変える'),
        children: [
          for (final branch in branches)
            SimpleDialogOption(
              key: ValueKey('lending.branch.option.${branch.id}'),
              onPressed: () => Navigator.of(context).pop(branch.id),
              child: Text(branch.name),
            ),
        ],
      ),
    );
    if (picked == null || picked == item.pickupLibraryId) return;
    ref
        .read(lendingProvider.notifier)
        .changePickupLibrary(
          loanId: loanId,
          systemId: item.systemId,
          branchId: picked,
        );
  }
}
