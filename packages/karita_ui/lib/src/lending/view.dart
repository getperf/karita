/// 貸出し（棚卸）の入口。**初期画面と、1管理区分の詳細の2枚である**（`lending.md` §2）。
///
/// 初期画面は読み取り専用のサマリで、どの区へ行くかを決めるためにある。区の枠を押すと編集
/// できる詳細へ入る。**書き換えは詳細だけで起きる。**
///
/// ## 2枚を別のファイルへ割った（2026-09-20）
///
/// 1本で 819 行あり、書影を足すとさらに伸びる。**画面の境目はそのまま切れ目である** — 上の
/// 段落が言っているとおり、読み取り専用の1枚と書き換える1枚で、間に共有している状態は
/// `state.dart` にしかない。
///
/// - `overview.dart` — 初期画面（区の枠、フィルタ、1行のサマリ）
/// - `area.dart` — 詳細（区ヘッダー、URL パネル、状態を直す行）
/// - `shared.dart` — 両方が使う4つ。**`karita_ui.dart` からは export しない。**
///
/// **層（`providers/`・`views/`）では切っていない**（`karita_ui.dart` の「中の並べ方」）。
/// ここに残すのは行き先の分岐と notice だけである。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'area.dart';
import 'overview.dart';
import 'state.dart';

class LendingView extends ConsumerWidget {
  const LendingView({super.key, this.contentMaxWidth = 640});

  final double contentMaxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(lendingRouteProvider);
    return _NoticeListener(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth),
        child: route.screen == LendingScreen.overview
            ? const LendingOverview()
            : LendingAreaDetail(route.systemId!),
      ),
    );
  }
}

/// 操作の結果を短い notice で出す。**ヘッダーにも本文にも居座らせない**（2026-09-19）。
///
/// 「〜にしました。」は**済んだことの確認**であって、読み続ける情報ではない。棚卸は何件も
/// 続けて直す作業なので、行の上に文が増えると押す位置がそのたびにずれる。出したら消える
/// [SnackBar] にして、**版面を動かさない。**
///
/// **同じ文言が続いても出す。** 状態の `messageId` は文字列ではなく回数を持つので、受取館を
/// 2件続けて同じ館へ変えても2回出る。
class _NoticeListener extends ConsumerWidget {
  const _NoticeListener({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(lendingProvider.select((state) => state.messageId), (_, _) {
      final text = ref.read(lendingProvider).message;
      if (text.isEmpty) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(text),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });
    return child;
  }
}
