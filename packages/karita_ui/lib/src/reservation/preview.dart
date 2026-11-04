/// 予約先の区の確認画面（2026-10-31。`../karita-ui-probe/docs/screens/reservation-preview.md`）。
///
/// 予約画面で受取システム館を選ぶと開く、**読むだけの画面**である。予約を記録する前に、
/// その区の貸出し状況と、同じ本の記録が既にないかを見せる。記録は予約画面の［予約した］が
/// 行い、ここでは何も書かない。館サイトは貸出しと同じ［図書館サイトを開く］で開ける。
///
/// **「予約前の確認」の帯は置かない**（2026-10-31。実機で冗長だった）。予約予定の行の
/// ラベルと文が、記録していないことを言う。
///
/// **表示は区の貸出し画面と同じにする**（§3）。行は `../lending/row.dart` を共用し、
/// 状態と期限は押せないが同じ色で出す。予約予定の行は予約中の1行目に置いて目立たせる。
/// 確定後の行は貸出しでは末尾に付く（`lending.md` §5）が、**位置を揃えない**（§6）。
///
/// **予約画面の中の画面である。** 外殻のタブは `予約` のままで、貸出しタブへは移らない。
/// 戻る操作は区の貸出し画面に揃える — 左上の ← と、Android の OS の戻る（§6）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../bookshelf/holdings.dart';
import '../composition.dart';
import '../lending/row.dart';
import '../lending/state.dart';
import '../libraries/state.dart';
import '../libraries/wording.dart';
import '../shell/navigation.dart';
import 'book_link.dart';
import 'state.dart';
import 'view.dart';

part 'preview.g.dart';

/// 確認画面に出す、その区の記録済みの行。
///
/// **貸出しの `lendingProvider` は借りない。** あちらは貸出しタブに入ったときに読む作りで、
/// 予約から読むと読まれていないことがあり、貸出しの選択・並びも巻き込む。台帳から直接、
/// 同じ読み口と同じ並び（[compareLoanItems]）で読む。
@riverpod
List<LoanReportItem> reservationPreviewLoans(Ref ref, String systemId) {
  ref.watch(ledgerSessionProvider);
  ref.watch(ledgerRevisionProvider);
  final items = [
    for (final item in ref.watch(compositionProvider).loadActiveLoans())
      if (item.systemId == systemId) item,
  ]..sort(compareLoanItems);
  return List.unmodifiable(items);
}

class ReservationPreview extends ConsumerWidget {
  const ReservationPreview({super.key, required this.systemId});

  final String systemId;

  /// 予約予定の枠が左右の余白へはみ出す幅。**枠線2px＋内側の余白4px** と同じにする。
  static const double _bleed = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actions = ref.read(reservationProvider.notifier);
    final state = ref.watch(reservationProvider);
    final draft = state.draft;
    if (draft == null) return const SizedBox.shrink();
    final message = state.message;
    final system = ref.watch(libraryProvider(systemId));
    final name = system?.name ?? systemId;
    PreferredBranch? preferred;
    try {
      preferred = ref.watch(preferredBranchProvider(systemId));
    } catch (_) {
      // 読めなければ未設定として扱う（予約画面の `_preferredState` と同じ）。
    }
    final resolved = preferred?.state == PreferredBranchState.resolved;

    List<LoanReportItem> loans = const [];
    String? loadError;
    if (resolved) {
      try {
        loans = ref.watch(reservationPreviewLoansProvider(systemId));
      } catch (error) {
        final issue = appIssueOf(error);
        loadError = '${issue.code}: ${issue.message}';
      }
    }
    bool sameBook(LoanReportItem item) =>
        item.bookId == draft.bookId ||
        (draft.isbn != null && item.isbn13 == draft.isbn);
    final title = draft.title.isEmpty ? 'タイトル未取得' : draft.title;
    final actionRows = [
      for (final item in loans)
        if (item.status != 'reserved') item,
    ];
    final reservedRows = [
      for (final item in loans)
        if (item.status == 'reserved') item,
    ];
    final duplicate = loans.any(sameBook);

    Widget row(LoanReportItem item) => LoanRowView(
      key: ValueKey('reservation.preview.row.${item.loanId}'),
      item: item,
      status: item.status,
      keyPrefix: 'reservation.preview',
      danger: isOverdue(item),
      inert: true,
      mark: sameBook(item) ? '同じ本' : null,
    );

    Widget heading(LendingSection section, String count) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(section.heading, style: theme.textTheme.titleMedium),
          ),
          Text(count, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    // **予約予定の枠だけを左右の余白へはみ出させる。** 枠の内側の行を他の行と同じ幅に
    // 保つためで、枠の分だけ狭いと状態ボタンの文字がこの行だけ先に潰れた（2026-10-31）。
    // 他の部品は [inset] で貸出しの詳細と同じ 14px の余白へ戻す。
    Widget inset(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: _bleed),
      child: child,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) actions.closePreview();
      },
      child: ListView(
        key: const ValueKey('reservation.preview'),
        padding: const EdgeInsets.symmetric(
          horizontal: 14 - _bleed,
          vertical: 14,
        ),
        children: [
          inset(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  key: const ValueKey('reservation.preview.back'),
                  onPressed: actions.closePreview,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '予約へ戻る',
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.titleLarge),
                      Text(
                        resolved
                            ? '図書 ${loans.length}件・常用館 ${preferredBranchValue(preferred!)}'
                            : '常用館 未設定',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // **その本の館サイトのページを先に置く**（2026-11-04。`book_link.dart`）。予約は
          // ここから館サイトで行い、戻って［予約した］で記録する。ISBN が無い本は行き先を
          // 引けないので出さない。
          if (draft.isbn case final String isbn)
            inset(_BookLink(systemId: systemId, isbn: isbn, name: name)),
          // **館サイトを開ける**（2026-10-31）。予約の前に館サイトで区の状況を確かめたい
          // ときのため。貸出しの詳細と同じ文言にする。本のページを出すときは、主役を譲って
          // 枠線のボタンにする。
          inset(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: draft.isbn == null
                    ? FilledButton.icon(
                        key: const ValueKey('reservation.preview.site'),
                        onPressed: () => actions.openSite(systemId),
                        icon: const Icon(Icons.open_in_new),
                        label: Text('$nameの図書館サイトを開く'),
                      )
                    : OutlinedButton.icon(
                        key: const ValueKey('reservation.preview.site'),
                        onPressed: () => actions.openSite(systemId),
                        icon: const Icon(Icons.open_in_new),
                        label: Text('$nameの図書館サイトを開く'),
                      ),
              ),
            ),
          ),
          if (message.isNotEmpty)
            inset(
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(liveRegion: true, child: Text(message)),
              ),
            ),
          if (!resolved)
            // **常用館が決まっていない区では止める**（§5）。選んでも保存で弾かれるので、
            // チェックは付けていない。設定から戻ったら区を押し直す。
            inset(
              ReservationGate(
                key: const ValueKey('reservation.preview.gate'),
                title: '常用館が選ばれていません',
                body:
                    '$nameの常用館が決まっていないため、この区へ予約を記録できません。'
                    '戻っても館は選ばれません。常用館は、予約した本を受け取る館です。',
                actions: [
                  (
                    '常用館を選ぶ',
                    const ValueKey('reservation.preview.gate.preferred'),
                    () {
                      actions.closePreview();
                      ref
                          .read(librariesRouteProvider.notifier)
                          .openPreferredBranch(
                            systemId,
                            returnTo: ShellTab.reserve,
                          );
                      ref
                          .read(currentTabProvider.notifier)
                          .select(ShellTab.settings);
                    },
                  ),
                ],
              ),
            )
          else ...[
            // **次の一手を言う**（2026-10-31。実機で、確認の後にどこへ進むかが分かりづらかった）。
            // 記録はこの画面ではなく予約画面の［予約した］が行う。
            inset(
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '図書館サイトで予約したら、左上の ← で予約へ戻り、［予約した］で登録してください。',
                  key: const ValueKey('reservation.preview.next'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (loadError != null) inset(Text(loadError)),
            inset(
              heading(
                LendingSection.action,
                '${LendingSection.action.note} ${actionRows.length}冊',
              ),
            ),
            if (actionRows.isEmpty)
              inset(Text('${LendingSection.action.heading}の図書はありません'))
            else
              for (final item in actionRows) inset(row(item)),
            inset(
              heading(
                LendingSection.reserved,
                '${reservedRows.length}冊 ＋ 予約予定1冊',
              ),
            ),
            // **予約予定は予約中の1行目に置く**（§3）。末尾では予約中が多い区で
            // スクロールしないと見えず、この画面の主役を探させることになる。
            _Pending(
              item: LoanReportItem(
                loanId: 'pending',
                bookId: draft.bookId,
                systemId: systemId,
                systemName: name,
                pref: '',
                city: '',
                status: 'reserved',
                title: title,
                bookAvailable: true,
                authors: const [],
                configured: true,
                isbn13: draft.isbn,
                pickupLibraryName: preferred!.branchName,
              ),
              duplicate: duplicate,
            ),
            for (final item in reservedRows) inset(row(item)),
          ],
        ],
      ),
    );
  }
}

/// その本の館サイトのページへのボタンと、その区での蔵書の1行（2026-11-04）。
///
/// 行き先が分かれば館のページ、分からなければカーリルの書籍ページを開く。**照会中も
/// ボタンの位置を空けない** — 押せない同じボタンを置き、届いたら押せるようにする。
class _BookLink extends ConsumerWidget {
  const _BookLink({
    required this.systemId,
    required this.isbn,
    required this.name,
  });
  final String systemId;
  final String isbn;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actions = ref.read(reservationProvider.notifier);
    final link = ref.watch(reservationBookLinkProvider((isbn, systemId)));
    final value = link.isLoading ? null : link.value;
    final url = value?.url;
    final summary = value?.summary;
    final note = switch (summary?.state) {
      null when link.isLoading => '$nameの蔵書を確認しています…',
      HoldingsState.keyMissing => '',
      HoldingsState.absent => '$nameにこの本の蔵書は見つかりませんでした（カーリル）。',
      final HoldingsState _ when summary!.found =>
        url == null
            ? '$name：${shelfHoldingsBadge(summary)}。本のページは分からないため、カーリルから開きます。'
            : '$name：${shelfHoldingsBadge(summary)}',
      _ => '$nameの蔵書を確認できませんでした。カーリルから探せます。',
    };
    final Widget button;
    if (url != null || link.isLoading) {
      button = FilledButton.icon(
        key: const ValueKey('reservation.preview.book'),
        onPressed: url == null
            ? null
            : () => actions.openBookPage(systemId, url),
        icon: const Icon(Icons.menu_book),
        label: Text('この本を$nameの図書館で開く'),
      );
    } else {
      button = FilledButton.tonalIcon(
        key: const ValueKey('reservation.preview.calil'),
        onPressed: actions.openCalil,
        icon: const Icon(Icons.search),
        label: const Text('カーリルでこの本を見る'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: double.infinity, child: button),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  note,
                  key: const ValueKey('reservation.preview.book.note'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 予約予定の行。**太枠・地色・ラベル・文で示し、色だけに頼らない。**
class _Pending extends StatelessWidget {
  const _Pending({required this.item, required this.duplicate});
  final LoanReportItem item;
  final bool duplicate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('reservation.preview.pending'),
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      // 横の余白は枠線と合わせて [ReservationPreview._bleed] になる。
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        border: Border.all(color: scheme.primary, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '予約予定',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                'まだ記録していません。［予約した］で予約中になります',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          LoanRowView(
            item: item,
            status: 'reserved',
            keyPrefix: 'reservation.preview.pending',
            inert: true,
          ),
          if (duplicate)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'この区で既に記録があります（「同じ本」の印の行）。',
                key: const ValueKey('reservation.preview.duplicate'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
