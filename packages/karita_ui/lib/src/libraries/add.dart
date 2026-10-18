/// 図書館の追加。**都道府県を選ぶ1段目と、選んだ県で1回だけ引く2段目である。**
///
/// **2段で1つの流れなので1本にしてある** — 間で渡るのは `route.pref` だけで、共有する部品は
/// 無い。2段に分かれている理由は [AddPrefectureScreen] の宣言に書いてある。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';

import '../composition.dart';
import '../density.dart';
import '../notice.dart';
import 'preferred_branch.dart';
import 'shared.dart';
import 'state.dart';
import 'wording.dart';

/// 追加の1段目。**都道府県を選ぶ。通信しない。**
///
/// `/library` は自由語検索を持たず、受けるのは `pref`・`city`・`systemid`・`geocode` だけで
/// ある。**先に県を選ばせるのは API の制約であって、UI の好みではない**
/// （`非公開資料:external-data-access.md` の 2026-09-15 決定）。
///
/// **選ぶと進む。** 常用館の選択リストと違って保存する値ではないので、ラジオにしない。
class AddPrefectureScreen extends ConsumerWidget {
  const AddPrefectureScreen({super.key, this.onPick});

  /// 県を選んだときの行き先。**`null` なら図書館管理の経路へ進む。** 起動時の登録を促す段
  /// （`shell/library_setup.dart`）は、経路の状態を使わないのでここで受ける。
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final density = ref.watch(densityProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        const LibraryParagraph('図書館を探す都道府県を選んでください。'),
        for (final pref in prefectures)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onPick != null
                  ? onPick!(pref)
                  : ref
                        .read(librariesRouteProvider.notifier)
                        .openAddSearch(pref),
              child: Container(
                constraints: BoxConstraints(minHeight: density.control),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(pref)),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 追加の2段目。**選んだ県で1回だけ引き、絞込みは端末側である。**
class AddSearchScreen extends ConsumerStatefulWidget {
  const AddSearchScreen({super.key, required this.pref});

  final String pref;

  @override
  ConsumerState<AddSearchScreen> createState() => _AddSearchScreenState();
}

class _AddSearchScreenState extends ConsumerState<AddSearchScreen> {
  /// **`TextEditingController` は Widget が持つ**（§5）。県を移ると鍵が変わって作り直る。
  final TextEditingController _keyword = TextEditingController();

  /// 常用館を選んでいる図書館。**登録の直後にここへ入る**（2026-10-15）。
  ///
  /// 登録だけでは予約できない — 予約は保存の直前に常用館を引き、未設定なら止める
  /// （`非公開資料:reservation-ui.md`）。登録と常用館は別の集約なので一つの書込みには
  /// しない（`libraries-in-sqlite.md` 2c）。**画面の流れで続けて選ばせる。** 選ばずに戻れば、
  /// 行に［常用館を選ぶ］が残る。
  ///
  /// **Widget が持つ。** 起動時の登録を促す段は経路の状態を使わないので、両方の入口で効く
  /// 置き場はここである。絞込みの入力も保ったまま一覧へ戻れる。
  String? _choosingFor;

  void _choose(String systemId) => setState(() => _choosingFor = systemId);

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final choosing = _choosingFor;
    if (choosing != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: LibraryParagraph(
              '登録しました。続けて、予約した本を受け取る常用館を選んでください。'
              '常用館が決まるまで、この図書館では予約を登録できません。',
            ),
          ),
          Expanded(
            child: PreferredBranchScreen(
              key: ValueKey('add-preferred:$choosing'),
              systemId: choosing,
              onClose: () => setState(() => _choosingFor = null),
            ),
          ),
        ],
      );
    }
    final candidates = ref.watch(libraryCandidatesProvider(widget.pref));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: TextField(
            controller: _keyword,
            // **通信はもう済んでいる。** 絞込みは端末側なので、実行ボタンを置かず即時に絞る。
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: '図書館を絞り込む',
              helperText: '市区町村・図書館名・住所で絞り込めます。',
              border: const OutlineInputBorder(),
              suffixIcon: _keyword.text.isEmpty
                  ? const Icon(Icons.search)
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '絞り込みを解除',
                      onPressed: () => setState(_keyword.clear),
                    ),
            ),
          ),
        ),
        Expanded(
          child: candidates.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) {
              final issue = appIssueOf(error);
              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                children: [
                  KaritaNotice(
                    // **キーが空と通信失敗を、候補0件と同一視しない**（2026-09-14 の仕様）。
                    issue.code == 'calil-key-missing'
                        ? '図書館を探せません。この端末では図書館の検索を利用できません。'
                        : '図書館を探せません。通信できるようになってから、もう一度開いてください。',
                    issue: issue,
                    retry: () =>
                        ref.invalidate(libraryCandidatesProvider(widget.pref)),
                  ),
                ],
              );
            },
            data: (value) => _Results(
              pref: widget.pref,
              candidates: value,
              keyword: _keyword.text,
              onClear: () => setState(_keyword.clear),
              onChoose: _choose,
              outlineVariant: scheme.outlineVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    required this.pref,
    required this.candidates,
    required this.keyword,
    required this.onClear,
    required this.onChoose,
    required this.outlineVariant,
  });

  final String pref;
  final LibraryCandidates candidates;
  final String keyword;
  final VoidCallback onClear;

  /// 常用館の選択へ入る。登録の直後と、行の［常用館を選ぶ］から呼ぶ。
  final ValueChanged<String> onChoose;
  final Color outlineVariant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **絞込みと順位付けはクライアントが持つ**（§3.1）。画面でやり直さない。
    final hits = filterSystems(candidates.systems, keyword);
    final registered = ref.watch(librariesProvider);
    final action = ref.watch(libraryRegisterProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        if (candidates.truncated)
          // **黙って欠けさせない。** 「無い」と「載っていない」を利用者が区別できるように。
          const KaritaNotice('図書館が多すぎて、一部しか取得できませんでした。'),
        LibraryParagraph(
          candidateCount(
            pref: pref,
            hits: hits.length,
            total: candidates.systems.length,
          ),
        ),
        if (hits.isEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: onClear, child: const Text('絞り込みを解除')),
          ),
        for (final candidate in hits)
          _CandidateRow(
            candidate: candidate,
            registered: registered.containsKey(candidate.systemId),
            action: action,
            onChoose: onChoose,
            outlineVariant: outlineVariant,
          ),
      ],
    );
  }
}

class _CandidateRow extends ConsumerWidget {
  const _CandidateRow({
    required this.candidate,
    required this.registered,
    required this.action,
    required this.onChoose,
    required this.outlineVariant,
  });

  final LibrarySystemCandidate candidate;
  final bool registered;
  final LibraryActionState action;
  final ValueChanged<String> onChoose;
  final Color outlineVariant;

  /// 登録済みの行の常用館。**読めなければ未設定と同じく選ばせる** — 選択の画面が読めない
  /// ことを出す。
  PreferredBranch? _preferred(WidgetRef ref) {
    if (!registered) return null;
    try {
      return ref.watch(preferredBranchProvider(candidate.systemId));
    } catch (_) {
      return const PreferredBranch.unset();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mine = action.systemId == candidate.systemId;
    final running = action.running && mine;
    final preferred = _preferred(ref);
    final needsPreferred =
        preferred != null && preferred.state != PreferredBranchState.resolved;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.systemName,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${candidate.city}・${candidate.branches.length} 館',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (running)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // **二重追加しない。** 登録済みは無効化して、そう見せる（probe のモック）。
                    FilledButton(
                      onPressed: registered || action.running
                          ? null
                          : () async {
                              final done = await ref
                                  .read(libraryRegisterProvider.notifier)
                                  .register(candidate);
                              if (done) onChoose(candidate.systemId);
                            },
                      child: Text(registered ? '登録済み' : '登録'),
                    ),
                    // **常用館が決まるまでは、登録は済んでいない扱いで見せる。**
                    if (needsPreferred)
                      FilledButton(
                        key: ValueKey('add-choose:${candidate.systemId}'),
                        onPressed: action.running
                            ? null
                            : () => onChoose(candidate.systemId),
                        child: const Text('常用館を選ぶ'),
                      ),
                  ],
                ),
            ],
          ),
          if (preferred != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '常用館：${preferredBranchValue(preferred)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: needsPreferred
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (mine && action.error != null)
            KaritaNotice('図書館を登録できませんでした。', issue: action.error),
        ],
      ),
    );
  }
}
