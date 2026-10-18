/// 常用館の選択。**独立した1枚である**（probe のモックと同じ）。
///
/// **ダイアログにしない。** 狭い Window ではダイアログがほぼ全画面になり、画面遷移と見分けが
/// つかない（`karita-ui-probe/docs/desktop-browser-workflow.md` §4）。
///
/// **選択中の分館を State に持つ画面である。** 別の館へ移ったときに前の Draft が居残らない
/// よう、鍵は呼び出し側（`view.dart`）が対象で付けている。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';

import '../composition.dart';
import '../density.dart';
import '../notice.dart';
import 'shared.dart';
import 'state.dart';
import 'wording.dart';

class PreferredBranchScreen extends ConsumerStatefulWidget {
  const PreferredBranchScreen({
    super.key,
    required this.systemId,
    this.onClose,
  });

  final String systemId;

  /// 閉じたとき（保存・キャンセル・一覧へ戻る）の行き先。**`null` なら図書館管理の経路で戻る。**
  ///
  /// 登録の直後に続けて選ばせる段（`add.dart`）は、経路の状態を使わずにここで受ける —
  /// 起動時の登録を促す段は `LibrariesRoute` を使わないためである（`AddPrefectureScreen.onPick`
  /// と同じ形）。
  final VoidCallback? onClose;

  @override
  ConsumerState<PreferredBranchScreen> createState() =>
      _PreferredBranchScreenState();
}

class _PreferredBranchScreenState extends ConsumerState<PreferredBranchScreen> {
  /// 選択中の分館。**Draft は Widget が持つ**（§5）。
  ///
  /// **取消で共有データを変えない。** 戻る・キャンセルで捨てられる。
  String? _selected;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    LibrarySystem? system;
    AppIssue? loadFailure;
    try {
      system = ref.watch(libraryProvider(widget.systemId));
    } catch (error) {
      loadFailure = appIssueOf(error);
    }
    if (loadFailure != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          KaritaNotice(
            '図書館を読み込めません。',
            issue: loadFailure,
            retry: () => ref.invalidate(librariesProvider),
          ),
        ],
      );
    }
    if (system == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          const LibraryParagraph('この図書館は登録されていません。ほかの端末で削除された可能性があります。'),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => widget.onClose != null
                  ? widget.onClose!()
                  : ref.read(librariesRouteProvider.notifier).backToList(),
              child: const Text('一覧へ戻る'),
            ),
          ),
        ],
      );
    }

    // **常用館が読めなくても選び直しはできる。** 現在値の行だけが「未設定」に見える形を
    // 避けるため、読めなかったことは下の帯で出す。
    PreferredBranch current = const PreferredBranch.unset();
    AppIssue? currentFailure;
    try {
      current = ref.watch(preferredBranchProvider(widget.systemId));
    } catch (error) {
      currentFailure = appIssueOf(error);
    }
    if (!_initialized) {
      _initialized = true;
      _selected = current.branchId;
    }

    final ids = {for (final branch in system.branches) branch.id};
    // **編集中の変更を黙って入力へ上書きしない**（§4 段階1 の注意点）。選んでいた分館が
    // 同期で消えたら、そのことを出して選び直させる。参照の切れた常用館から入った場合も同じ。
    // **「未設定」は参照切れではない。** センチネル（[_unset]）は分館 id の集合に入っていない
    // ので、素直に書くと未設定を選んだ瞬間に参照切れ扱いになって保存が止まる。
    final stale =
        _selected != null && _selected != _unset && !ids.contains(_selected);
    final save = ref.watch(preferredBranchSaveProvider);
    final refresh = ref.watch(branchRefreshProvider(widget.systemId));
    final branches = [...system.branches]
      ..sort((a, b) {
        final name = a.name.compareTo(b.name);
        return name != 0 ? name : a.id.compareTo(b.id);
      });
    final running = save.running;
    final failure = save.systemId == widget.systemId ? save.error : null;

    final density = ref.watch(densityProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: refresh.isLoading || running
                        ? null
                        : () => ref.invalidate(
                            branchRefreshProvider(widget.systemId),
                          ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('リストを更新'),
                  ),
                  if (refresh.isLoading) const Text('分館リストを確認中…'),
                  if (refresh.hasValue &&
                      !refresh.isLoading &&
                      !refresh.hasError)
                    Text(refresh.value == 0 ? '変更はありません' : '分館リストを更新しました'),
                ],
              ),
              if (refresh.hasError)
                KaritaNotice(
                  '分館リストを更新できませんでした。保存済みの一覧を表示しています。',
                  issue: appIssueOf(refresh.error!),
                  retry: () =>
                      ref.invalidate(branchRefreshProvider(widget.systemId)),
                ),
              LibraryCard(
                title: system.name,
                description: '個別に指定した受取館は変わりません。',
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (currentFailure == null)
                      Text('現在：${preferredBranchValue(current)}')
                    else
                      KaritaNotice('常用館を読み込めません。', issue: currentFailure),
                    if (stale)
                      const KaritaNotice('選択していた分館がなくなりました。選び直してください。'),
                    if (failure != null)
                      KaritaNotice('常用館を保存できませんでした。前の設定のままです。', issue: failure),
                  ],
                ),
              ),
              // **選択リストを縦に並べる。** この画面はもともと専用画面なので、選択肢を
              // メニューの中に畳む理由が無い。**実測で自治体の分館は中央値7・最大21**
              // （2026-09-17）で、21件を1つのメニューに入れる形ではない。
              //
              // **`RadioGroup` を親に置く。** `RadioListTile` の `groupValue` /
              // `onChanged` は 3.32 で deprecated になっている。
              // **保存中は触らせない。** `RadioGroup.onChanged` は `null` を受けないので、
              // 無効化は入力の側で行う。
              IgnorePointer(
                ignoring: running,
                child: RadioGroup<String>(
                  groupValue: stale ? _unset : (_selected ?? _unset),
                  onChanged: (value) {
                    if (value != null) setState(() => _selected = value);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final option in [
                        (_unset, '未設定'),
                        for (final branch in branches) (branch.id, branch.name),
                      ])
                        RadioListTile<String>(
                          value: option.$1,
                          // **タッチは Material の既定のまま、指さない側だけ詰める**
                          // （`density.dart` の2軸）。
                          visualDensity: density.pointer == PointerKind.touch
                              ? VisualDensity.standard
                              : VisualDensity.compact,
                          // **長い分館名は折り返す。** 省略記号にしない。
                          title: Text(option.$2),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (running) const LinearProgressIndicator(),
        // **画面固有の下部操作は下端に置く**（`ui-plan.md` §2。外殻の Navbar の直上に来る）。
        // 21件を並べると保存が画面の外へ出るので、本文と一緒に流さない。
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: running ? null : _close,
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: running || stale ? null : _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final saved = await ref
        .read(preferredBranchSaveProvider.notifier)
        // **空は解除である。** 合成層の口は保存と解除の2本に分かれたままで、ここが
        // 選択リストの値を振り分ける（`PreferredBranchSave.save` の宣言）。
        .save(widget.systemId, _selected == _unset ? null : _selected);
    if (saved && mounted) _close();
  }

  void _close() => widget.onClose != null
      ? widget.onClose!()
      : ref.read(librariesRouteProvider.notifier).back();
}

/// 「未設定」を表す選択肢の値。**`null` を選択肢の値にしない。**
///
/// `RadioGroup<String?>` にすると「未設定を選んだ」と「何も選んでいない」が同じ `null` に
/// なり、参照切れで選び直させたい場面（[_PreferredBranchScreenState] の `stale`）で
/// 区別できなくなる。**分館 id は `calil:<libid>` なので、空文字と衝突しない。**
const String _unset = '';
