/// 図書館の一覧と、その1行。**登録済みの館を並べるだけである。**
///
/// **絞込みも並べ替えも持たない**。
/// 並びは都道府県 → 名称順で、これは読み口（`state.dart`）が決めている。
///
/// 行が出すのは名称・常用館・マイページの出典の3つで、押すと詳細へ入る。
/// **［図書館追加］はヘッダーの持ち物**なので `view.dart` の側に居る。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_domain/karita_domain.dart';

import '../composition.dart';
import '../density.dart';
import '../notice.dart';
import 'shared.dart';
import 'state.dart';
import 'wording.dart';

class LibrariesListScreen extends ConsumerWidget {
  const LibrariesListScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<LibrarySystem> systems;
    try {
      systems = ref.watch(libraryListProvider);
    } catch (error) {
      final issue = appIssueOf(error);
      // **読込失敗を「未登録」に変換しない。** 0件は正常な結果で、これは別である。
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          KaritaNotice(
            '図書館を読み込めません。',
            issue: issue,
            retry: () => ref.invalidate(librariesProvider),
          ),
        ],
      );
    }

    if (systems.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          const LibraryParagraph('登録した図書館はありません。'),
          const LibraryParagraph('ヘッダーの［図書館追加］から登録できます。'),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [for (final system in systems) _ListRow(system: system)],
    );
  }
}

/// 一覧の1行。**名称・常用館・マイページの出典を出す**（probe のモック）。
///
/// **「〇〇の図書館」にしない。** モックの館名は `江東区` という手書き fixture で、実データの
/// [LibrarySystem.name] はカーリルの `systemname` をそのまま採った `東京都江東区` である
/// （2026-09-16 の決定）。そのまま写すと「東京都江東区の図書館」になる。
class _ListRow extends ConsumerWidget {
  const _ListRow({required this.system});

  final LibrarySystem system;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final density = ref.watch(densityProvider);
    final sub = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () =>
            ref.read(librariesRouteProvider.notifier).openDetail(system.id),
        child: Container(
          constraints: BoxConstraints(minHeight: density.control),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // **省略記号にしない。** 分館名は「港区男女平等参画センター｢リーブラ｣
                    // 図書資料室」のように長く、狭い画面では折り返すほうが読める。
                    Text(system.name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 5),
                    _PreferredBranchLine(systemId: system.id, style: sub),
                    _MypageLine(systemId: system.id, style: sub),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一覧の行に出す常用館。**利用者値は `LibrarySetting` の別集約なので別に引く。**
class _PreferredBranchLine extends ConsumerWidget {
  const _PreferredBranchLine({required this.systemId, this.style});

  final String systemId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      final branch = ref.watch(preferredBranchProvider(systemId));
      return Text('常用館：${preferredBranchValue(branch)}', style: style);
    } catch (_) {
      return Text('常用館：読み込めません', style: style);
    }
  }
}

/// 一覧の行に出すマイページの出典。**確認日は詳細の側に出す。**
class _MypageLine extends ConsumerWidget {
  const _MypageLine({required this.systemId, this.style});

  final String systemId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      final url = ref.watch(mypageUrlProvider(systemId));
      return Text('マイページ：${mypageSourceLabel(url.source)}', style: style);
    } catch (_) {
      return Text('マイページ：読み込めません', style: style);
    }
  }
}
