/// 図書館システムの詳細。**常用館・マイページ・削除の3枚のカードである**
/// （`karita-ui-probe/docs/screens/libraries.md` §「システム詳細」）。
///
/// ここで直接書き換わるのは削除だけで、常用館とマイページは押すとそれぞれの画面へ入る。
/// **分館の一覧は出さない**（2026-09-17）。
///
/// 館の名前はヘッダー（`view.dart`）が出しているので、本文の先頭で繰り返さない。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';

import '../composition.dart';
import '../notice.dart';
import '../setting_row.dart';
import 'shared.dart';
import 'state.dart';
import 'wording.dart';

/// 詳細。**選択 ID は `LibrarySystem.id`（カーリルの `systemid`）である。**
class LibraryDetailScreen extends ConsumerWidget {
  const LibraryDetailScreen({super.key, required this.systemId});

  final String systemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibrarySystem? system;
    try {
      system = ref.watch(libraryProvider(systemId));
    } catch (error) {
      final issue = appIssueOf(error);
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

    // **対象なしは読込失敗ではない。** 他端末で削除された場合もここへ来る。
    // **自動で一覧へ戻さない** — 見ていた画面が黙って消えると、何が起きたか分からない。
    if (system == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          const LibraryParagraph('この図書館は登録されていません。ほかの端末で削除された可能性があります。'),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () =>
                  ref.read(librariesRouteProvider.notifier).backToList(),
              child: const Text('一覧へ戻る'),
            ),
          ),
        ],
      );
    }

    final removal = ref.watch(libraryRemoveProvider);
    final save = ref.watch(preferredBranchSaveProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        // **館の名前はヘッダーが出している。** 本文の先頭で繰り返さない。
        _PreferredBranchCard(systemId: systemId, save: save),
        _MypageCard(systemId: systemId),
        // **分館の一覧は出さない。** 利用者が分館を見るのは常用館を選ぶときだけで、
        // そこには選択リストが在る。眺めるための一覧は用が無い（2026-09-17）。
        _RemovalCard(systemId: systemId, name: system.name, state: removal),
      ],
    );
  }
}

/// 常用館の行。**操作は右端である**（設定と同じトーン。2026-09-18）。
class _PreferredBranchCard extends ConsumerWidget {
  const _PreferredBranchCard({required this.systemId, required this.save});

  final String systemId;
  final LibraryActionState save;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    PreferredBranch? branch;
    AppIssue? loadFailure;
    try {
      branch = ref.watch(preferredBranchProvider(systemId));
    } catch (error) {
      loadFailure = appIssueOf(error);
    }
    final failure = save.systemId == systemId ? save.error : null;
    return KaritaSettingRow(
      name: '常用館',
      value: loadFailure == null ? preferredBranchValue(branch!) : null,
      description: '個別に指定していない受取館の既定になります。',
      control: TextButton(
        onPressed: () => ref
            .read(librariesRouteProvider.notifier)
            .openPreferredBranch(systemId),
        child: const Text('常用館登録'),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loadFailure != null)
            KaritaNotice(
              '常用館を読み込めません。',
              issue: loadFailure,
              retry: () => ref.invalidate(preferredBranchProvider(systemId)),
            ),
          if (failure != null) KaritaNotice('常用館を保存できませんでした。', issue: failure),
        ],
      ),
    );
  }
}

/// マイページの行。**出典は必ず出す**（`library-site-url.md` §3）。
class _MypageCard extends ConsumerWidget {
  const _MypageCard({required this.systemId});

  final String systemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MypageUrl url;
    try {
      url = ref.watch(mypageUrlProvider(systemId));
    } catch (error) {
      final issue = appIssueOf(error);
      return KaritaSettingRow(
        name: 'マイページ',
        description: '図書館サイトのマイページ（利用状況）の URL です。',
        trailing: KaritaNotice(
          'マイページを読み込めません。',
          issue: issue,
          retry: () => ref.invalidate(mypageUrlProvider(systemId)),
        ),
      );
    }
    final theme = Theme.of(context);
    return KaritaSettingRow(
      name: 'マイページ',
      description: '図書館サイトのマイページ（利用状況）の URL です。',
      control: TextButton(
        onPressed: () =>
            ref.read(librariesRouteProvider.notifier).openMypageUrl(systemId),
        child: const Text('マイページ登録'),
      ),
      valueWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // **既定値は作者が確認した時点の値で、館サイトの更新で切れる。** 切れたことを
          // アプリは検知できないので、確認日を出すことだけが古さを伝える手段である。
          Text(mypageSourceLine(url)),
          if (url.isSet)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(
                url.value!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 削除の行。**確認だけをダイアログにする**（設定の復元と同じ切り分け）。
class _RemovalCard extends ConsumerWidget {
  const _RemovalCard({
    required this.systemId,
    required this.name,
    required this.state,
  });

  final String systemId;
  final String name;
  final LibraryActionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final failure = state.systemId == systemId ? state.error : null;
    final running = state.running && state.systemId == systemId;
    return KaritaSettingRow(
      name: '図書館の削除',
      description: '借りた記録と棚卸の記録は残ります。削除はほかの端末にも伝わります。',
      control: running
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () => _confirm(context, ref),
              child: const Text('削除'),
            ),
      trailing: failure == null
          ? null
          : KaritaNotice('図書館を削除できませんでした。', issue: failure),
    );
  }

  /// 確認だけをダイアログにする。**編集はダイアログにしない**（設定の復元と同じ切り分け）。
  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name を削除しますか？'),
        content: SingleChildScrollView(
          child: _RemovalConsequences(systemId: systemId),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await ref
        .read(libraryRemoveProvider.notifier)
        .remove(systemId);
    // **消えた館の詳細に留まらない。** 失敗したときは詳細に残り、行内に理由が出る。
    if (removed) ref.read(librariesRouteProvider.notifier).backToList();
  }
}

/// 削除で残るもの。**数字は2つだけ**（棚卸記録と Loan）。
class _RemovalConsequences extends ConsumerWidget {
  const _RemovalConsequences({required this.systemId});

  final String systemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryRemovalImpact impact;
    try {
      impact = ref.watch(libraryRemovalImpactProvider(systemId));
    } catch (error) {
      final issue = appIssueOf(error);
      return KaritaNotice('影響を数えられません。', issue: issue);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in removalConsequences(impact))
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(line)),
      ],
    );
  }
}
