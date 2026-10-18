/// マイページ URL の登録。**読み順は 今の値 → 変える手段 → 確定 である。**
///
/// ボタンを先頭に置くと、**まだ見ていない値を変える操作から目に入る**。
///
/// **候補の置き場は欄そのものである**（2026-09-18）。受信した値も欄へ入り、取り込み・解除・
/// 破棄のボタンを置かない。**Android と Windows で同じ画面である** — 貼り付けは OS の
/// 機能（長押し・`Ctrl+V`）が受け持つ。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';

import '../composition.dart';
import '../notice.dart';
import 'shared.dart';
import 'state.dart';
import 'wording.dart';

class MypageUrlScreen extends ConsumerStatefulWidget {
  const MypageUrlScreen({super.key, required this.systemId});

  final String systemId;

  @override
  ConsumerState<MypageUrlScreen> createState() => _MypageUrlScreenState();
}

class _MypageUrlScreenState extends ConsumerState<MypageUrlScreen> {
  /// 欄。**`TextEditingController` は Widget が持つ**（§5）。
  final TextEditingController _url = TextEditingController();

  @override
  void initState() {
    super.initState();
    // **画面が立つ前に届いていた1件を拾う。** `ref.listen` は変化しか流さず、widget 版に
    // `fireImmediately` が無い。受信のほうが早いのが普通なので、ここで1回読む。
    //
    // **フレームの後に置く。** 組み立ての最中に Provider を書き換えない。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // **cold start の triage 画面が確定した候補を先に取り込む。** ストリーム経由の候補
      // （下）は `.where` で捨てられた後のイベントを再購読できないので、triage 画面は
      // `LibrariesRoute.prefillUrl` で直接渡す（`shell/handoff_triage.dart`）。
      final prefillUrl = ref.read(librariesRouteProvider).prefillUrl;
      if (prefillUrl != null) {
        _url.text = prefillUrl;
        ref
            .read(mypageEditProvider(widget.systemId).notifier)
            .setText(prefillUrl, MypageDraftSource.received,
                startedAt: DateTime.now());
        ref.read(librariesRouteProvider.notifier).clearPrefillUrl();
        return;
      }
      final current = ref.read(mypageCandidatesProvider);
      if (current is AsyncData<MypageCandidate>) _take(current.value);
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// 受信した候補を欄へ入れる。**欄が候補の置き場である。**
  void _take(MypageCandidate candidate) {
    if (candidate.systemId != widget.systemId) return;
    _url.text = candidate.url.toString();
    ref
        .read(mypageEditProvider(widget.systemId).notifier)
        .setText(
          _url.text,
          MypageDraftSource.received,
          startedAt: candidate.startedAt,
        );
  }

  void _listenForCandidates() {
    ref.listen(mypageCandidatesProvider, (_, next) {
      if (next is AsyncData<MypageCandidate> && mounted) _take(next.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    _listenForCandidates();
    final system = ref.watch(libraryProvider(widget.systemId));
    if (system == null) {
      return _MissingSystem(
        onBack: () => ref.read(librariesRouteProvider.notifier).backToList(),
      );
    }

    final MypageUrl current;
    try {
      current = ref.watch(mypageUrlProvider(widget.systemId));
    } catch (error) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          KaritaNotice(
            'マイページを読み込めません。',
            issue: appIssueOf(error),
            retry: () => ref.invalidate(mypageUrlProvider(widget.systemId)),
          ),
        ],
      );
    }

    final draft = ref.watch(mypageEditProvider(widget.systemId));
    final edit = ref.read(mypageEditProvider(widget.systemId).notifier);
    final opening = ref.watch(librarySiteOpenProvider);
    final scheme = Theme.of(context).colorScheme;

    // **空で保存すると解除である**（2026-09-18）。解除できるのは取り込み値を持つときだけで、
    // 既定値・公式サイトは台帳の行ではないので消せない。
    final clearing = draft.empty && current.source == MypageUrlSource.imported;
    final confirmable = !draft.saving && (draft.savable || clearing);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            children: [
              LibraryCard(
                title: system.name,
                description: '図書館サイトのマイページ（利用状況）の URL です。',
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('現在：${mypageSourceLine(current)}'),
                    if (current.isSet)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SelectableText(current.value!),
                      ),
                  ],
                ),
              ),
              LibraryCard(
                title: 'ブラウザーから登録',
                // **開いた事実でも、戻った事実でも状態を変えない。** 送られてくるまで何もしない。
                description: 'ログイン画面からマイページ（利用状況）へ移動して、［karita に送る］を押してください。',
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (opening.running)
                      const LinearProgressIndicator()
                    else
                      // **横幅いっぱいの主導線である**（2026-09-18）。probe のモバイル版が
                      // 「全幅のカーリルリンク」を主導線にしているのと同じ扱いで、
                      // ここから先は利用者がブラウザーで作業する。
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: current.isSet
                              ? () => ref
                                    .read(librarySiteOpenProvider.notifier)
                                    .open(widget.systemId)
                              : null,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('図書館サイトを開く'),
                        ),
                      ),
                    if (!current.isSet)
                      const LibraryParagraph('開く先がありません。図書館を登録し直すと公式サイトが入ります。'),
                    if (opening.systemId == widget.systemId &&
                        opening.error != null)
                      KaritaNotice('ブラウザーを開けませんでした。', issue: opening.error),
                  ],
                ),
              ),
              _MypageFieldCard(
                controller: _url,
                draft: draft,
                clearing: clearing,
                onChanged: (value) =>
                    edit.setText(value, MypageDraftSource.typed),
              ),
            ],
          ),
        ),
        if (draft.saving) const LinearProgressIndicator(),
        // **下端に固定する。** 候補と検証の帯が伸びたときに確定が流れない。
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
                  onPressed: draft.saving
                      ? null
                      : () => ref.read(librariesRouteProvider.notifier).back(),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: confirmable
                      ? () async {
                          if (await edit.confirm() && mounted) {
                            ref.read(librariesRouteProvider.notifier).back();
                          }
                        }
                      : null,
                  child: Text(clearing ? '解除して保存' : '保存'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 欄と検証結果。**取り込み・解除・破棄のボタンを置かない。**
///
/// 貼り付けは OS の機能で行う — Windows は `Ctrl+V`、Android は長押しである。**アプリ側に
/// 取り込みボタンを置かないので、クリップボードを読む経路も持たない。**
class _MypageFieldCard extends StatelessWidget {
  const _MypageFieldCard({
    required this.controller,
    required this.draft,
    required this.clearing,
    required this.onChanged,
  });

  final TextEditingController controller;
  final MypageDraft draft;
  final bool clearing;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final issues = draft.check?.issues ?? const <UrlSaveIssue>{};
    final rejection = urlRejection(issues);
    return LibraryCard(
      title: '新しい URL',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            // **長い URL を折り返して全部見せる。** 確認してから保存する値である。
            maxLines: null,
            minLines: 2,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          if (draft.broken)
            const KaritaNotice('URL として読み取れません。')
          else if (rejection != null)
            KaritaNotice(rejection),
          if (clearing)
            const LibraryParagraph('空のまま保存すると、取り込んだ値を解除して既定値に戻します。'),
          if (draft.source == MypageDraftSource.received) ...[
            LibraryParagraph(candidateSource(draft.source)),
            if (draft.startedAt != null)
              LibraryParagraph(
                candidateAge(DateTime.now().difference(draft.startedAt!)),
              ),
          ],
          if (draft.error != null)
            KaritaNotice('保存できませんでした。前の値のままです。', issue: draft.error),
        ],
      ),
    );
  }
}

/// 対象を失った画面。**自動で一覧へ戻さない。**
class _MissingSystem extends StatelessWidget {
  const _MissingSystem({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
    children: [
      const LibraryParagraph('この図書館は登録されていません。ほかの端末で削除された可能性があります。'),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(onPressed: onBack, child: const Text('一覧へ戻る')),
      ),
    ],
  );
}
