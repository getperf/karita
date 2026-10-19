/// 貸出しの2画面が両方使う部品。**どちらの持ち物でもないものだけを置く。**
///
/// 初期画面（`overview.dart`）と詳細（`area.dart`）を別のライブラリへ割ったので、
/// `_` の付いた名前は共有できない。**公開するのはここに集めた4つだけ**で、`karita_ui.dart`
/// からは export しない — package の外から触れる必要は無い。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../libraries/state.dart';
import '../shell/navigation.dart';
import 'state.dart';
import 'wording.dart';

/// モックのリンク。**下線を引く**（`.book-branch` / `.link-button` の
/// `text-decoration: underline`）。
///
/// **色だけでリンクを示さない。** 単色の淡い配色では地の文との差が小さく、暗いテーマでは
/// さらに縮む。下線は配色に依存しない手がかりである。
ButtonStyle lendingLinkStyle(BuildContext context) {
  final theme = Theme.of(context);
  return TextButton.styleFrom(
    foregroundColor: theme.colorScheme.primary,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(0, 32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    // **配色の書体から作る。** 素の [TextStyle] を渡すと `fontFamily` ごと置き換わり、
    // 書体を差し替えたテーマでここだけ既定の書体に落ちる（外殻で同じ罠を踏んでいる
    // — `shell.dart` の「色は必ず配色から採る」）。
    textStyle: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      decoration: TextDecoration.underline,
      decorationThickness: 1,
    ),
  );
}

/// 詳細の一覧を読み直す操作。**詳細は台帳の変更で読み直さない**（段階3 の決定）。
///
/// 初期画面には置かない（2026-10-20）。初期画面は同期が台帳を変えたら読み直す。
class LendingRefreshButton extends ConsumerWidget {
  const LendingRefreshButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lendingProvider);
    final dropped = state.leavingCount;
    return TextButton(
      key: const ValueKey('lending.refresh'),
      // **選択中は押せない**（2026-09-20。モックの `refresh-list` の `disabled`）。一括取消
      // の選択は表示順に紐づいているので、並びを組み直す操作は選択ごと意味を失う
      // （probe `findings.md` 2026-08-23「選択状態を失う更新操作を無効にする」）。
      onPressed:
          state.loading ||
              state.busyLoanId != null ||
              ref.watch(lendingSelectionProvider).active
          ? null
          : ref.read(lendingProvider.notifier).refresh,
      child: Text(dropped > 0 ? '↻ 更新 ($dropped)' : '↻ 更新'),
    );
  }
}

/// 読めなかったときの1画面。**コードを言葉にして、やり直す口を添える。**
class LendingFailure extends ConsumerWidget {
  const LendingFailure(this.code, {super.key});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(lendingIssueMessage(code)),
        const SizedBox(height: 8),
        // **初期画面にも出るので `↻ 更新` ではなく再試行にする**（2026-10-20）。
        TextButton(
          key: const ValueKey('lending.retry'),
          onPressed: ref.read(lendingProvider.notifier).refresh,
          child: const Text('再試行'),
        ),
      ],
    ),
  );
}

/// 図書館管理へ渡す。**編集はあちらが持つ**（`lending.md` §4。2026-09-13 に集約した）。
void openLibrariesFrom(WidgetRef ref, void Function(LibrariesRoute) open) {
  open(ref.read(librariesRouteProvider.notifier));
  ref.read(currentTabProvider.notifier).select(ShellTab.settings);
}
