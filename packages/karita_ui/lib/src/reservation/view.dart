library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import '../book_cover.dart';
import '../browser_link/state.dart';
import '../browser_link/view.dart';
import '../composition.dart';
import '../density.dart';
import '../libraries/state.dart';
import '../shell/navigation.dart';
import 'state.dart';

class ReservationView extends ConsumerStatefulWidget {
  const ReservationView({super.key, this.contentMaxWidth = 520});
  final double contentMaxWidth;
  @override
  ConsumerState<ReservationView> createState() => _ReservationViewState();
}

class _ReservationViewState extends ConsumerState<ReservationView> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _isbn = TextEditingController();
  String? _operation;
  @override
  void dispose() {
    for (final c in [_url, _title, _author, _isbn]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reservationProvider);
    final actions = ref.read(reservationProvider.notifier);
    final draft = state.draft;
    if (_operation != draft?.operationId) {
      _operation = draft?.operationId;
      _title.text = draft?.title ?? '';
      _author.text = draft?.author ?? '';
      _isbn.text = draft?.isbn ?? '';
    } else if (draft != null &&
        !draft.manual &&
        !draft.edited &&
        _title.text != draft.title) {
      // 届いた本の欄は、利用者が触るまで取得結果に追従する（再取得で書名が取れた場合）。
      _title.text = draft.title;
      _author.text = draft.author;
    }
    Map<String, LibrarySystem> libraries = const {};
    String? libraryError;
    if (state.formVisible) {
      try {
        libraries = ref.watch(librariesProvider);
      } catch (error) {
        final issue = appIssueOf(error);
        libraryError = '${issue.code}: ${issue.message}';
      }
    }
    // 選んだ館のうち、常用館が決まっていないもの。**保存の前に止める** — 保存しても
    // `preferred-branch` で弾かれるだけである（貸出しの［追加］と同じ判断）。
    final unresolved = <LibrarySystem>[
      for (final id in draft?.systems ?? const <String>{})
        if (libraries[id] case final system?)
          if (_preferredState(id) != PreferredBranchState.resolved) system,
    ];
    final touch = ref.watch(densityProvider).pointer == PointerKind.touch;
    final link = ref.watch(browserLinkProvider);
    final canSave =
        draft != null &&
        !state.saving &&
        !draft.invalidIsbn &&
        normalizeTitle(draft.title).isNotEmpty &&
        (draft.manual || draft.isbn != null);
    void edit(String _) => draft?.manual == true
        ? actions.edit(_title.text, _author.text, _isbn.text)
        : actions.editShared(_title.text, _author.text);
    Future<void> pasteTitle() async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = normalizeTitle(data?.text ?? '');
      if (!mounted || text.isEmpty) return;
      _title.text = text;
      edit(text);
    }

    final titleField = TextField(
      controller: _title,
      onChanged: edit,
      enabled: !state.saving,
      decoration: InputDecoration(
        labelText: 'タイトル（必須）',
        suffixIcon: IconButton(
          tooltip: '書名を貼り付け',
          icon: const Icon(Icons.content_paste),
          onPressed: state.saving ? null : pasteTitle,
        ),
      ),
    );
    final authorField = TextField(
      controller: _author,
      onChanged: edit,
      enabled: !state.saving,
      decoration: const InputDecoration(labelText: '著者（任意）'),
    );
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.contentMaxWidth),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '図書予約',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          if (state.waiting.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Material(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        color: colors.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '受信待ち ${state.waiting.length}冊',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: colors.onSecondaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              '編集中の本とは別です',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.onSecondaryContainer,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _showWaiting(context),
                        child: const Text('一覧を見る'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                FilledButton.icon(
                  onPressed: state.saving ? null : actions.openCalil,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('カーリルで探す'),
                ),
                if (draft?.manual != true)
                  ExpansionTile(
                    title: const Text('カーリルで検索・予約して戻る'),
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'カーリルで本を検索し、図書館サイトで予約してください。\n'
                        '予約後は${touch ? 'カーリルの書籍ページに戻り、共有からkaritaを選んで' : '図書館のタブでツールバーのkaritaボタンを押し、元のカーリル書籍を選んで'}送ってください。\n'
                        '予約しない場合も、本を送って「読みたい」に登録できます。',
                      ),
                      // **ツールバーに karita ボタンが無い利用者を、つなぐ段へ戻す**（2026-10-15）。
                      if (link.applicable) ...[
                        const SizedBox(height: 8),
                        if (!link.linked)
                          Text(
                            'この端末ではブラウザープラグインをまだ確かめていません。',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        TextButton.icon(
                          key: const ValueKey('reservation-browser-link'),
                          onPressed: () => openBrowserLinkScreen(context),
                          icon: const Icon(Icons.link),
                          label: Text(
                            link.linked
                                ? 'ブラウザープラグインを確かめる'
                                : 'ブラウザープラグインをインストール',
                          ),
                        ),
                      ],
                    ],
                  ),
                ExpansionTile(
                  title: const Text('送れないときはURLを貼り付け'),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _url,
                            decoration: const InputDecoration(
                              labelText: 'カーリルの書籍ページURL',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            actions.paste(_url.text);
                            _url.clear();
                          },
                          child: const Text('取込'),
                        ),
                      ],
                    ),
                  ],
                ),
                if (draft == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: actions.manual,
                      child: const Text('手動で入力'),
                    ),
                  ),
                if (state.formVisible) ...[
                  const SizedBox(height: 16),
                  if (draft != null && !draft.manual)
                    const Text('本が届きました。内容と予約した館を確認してください。'),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReservationCoverView(draft: draft),
                      const SizedBox(width: 12),
                      Expanded(
                        child: draft?.manual == true
                            ? Column(
                                children: [
                                  titleField,
                                  authorField,
                                  TextField(
                                    controller: _isbn,
                                    onChanged: edit,
                                    enabled: !state.saving,
                                    decoration: const InputDecoration(
                                      labelText: 'ISBN（任意）',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed:
                                        draft!.isbn == null ||
                                            draft.invalidIsbn ||
                                            draft.loading ||
                                            state.saving
                                        ? null
                                        : () => _lookupManual(),
                                    child: const Text('ISBNから取得'),
                                  ),
                                ],
                              )
                            : draft?.titleEditable == true
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  titleField,
                                  authorField,
                                  const SizedBox(height: 8),
                                  Text(draft!.isbn ?? 'ISBN'),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    draft == null
                                        ? 'タイトル'
                                        : draft.title.isEmpty
                                        ? 'タイトル未取得'
                                        : draft.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(draft?.author ?? '著者'),
                                  const SizedBox(height: 8),
                                  Text(draft?.isbn ?? 'ISBN'),
                                ],
                              ),
                      ),
                    ],
                  ),
                  if (draft?.loading == true)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('書誌を取得中…'),
                    ),
                  if (draft?.lookupNotice != null) Text(draft!.lookupNotice!),
                  if (draft?.lookupNotice != null && draft?.manual == false)
                    TextButton(
                      onPressed: state.saving || draft!.loading
                          ? null
                          : actions.retryLookup,
                      child: const Text('書誌を再取得'),
                    ),
                  const SizedBox(height: 16),
                  const Text('受取システム館'),
                  if (libraryError != null) Text(libraryError),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final system in libraries.values)
                        FilterChip(
                          label: Text(system.name),
                          selected: draft?.systems.contains(system.id) ?? false,
                          onSelected: draft == null || state.saving
                              ? null
                              : (_) => actions.select(system.id),
                        ),
                    ],
                  ),
                  if (libraries.isNotEmpty)
                    Text(
                      draft?.systems.isNotEmpty == true
                          ? '${draft!.systems.length}館に予約中として登録します。受取分館は常用館を使います。'
                          : '予約した館を選んでください。読みたいへの登録は館の選択不要です。',
                    ),
                  // **予約を登録できない理由は、直す画面への入口と一緒に強く出す**（2026-10-15）。
                  // 保存してから文言で知らせるだけだと、利用者はどこで直すかを探すことになる。
                  if (draft != null &&
                      libraryError == null &&
                      libraries.isEmpty)
                    ReservationGate(
                      key: const ValueKey('reservation-gate-no-library'),
                      title: '図書館が登録されていません',
                      body:
                          '予約を記録するには、予約した図書館の登録と、受け取る常用館の設定が'
                          '必要です。「読みたい」への登録はこのままできます。',
                      actions: [
                        (
                          '図書館を登録する',
                          const ValueKey('reservation-gate-add-library'),
                          () => _openLibraries(
                            (route) =>
                                route.openAdd(returnTo: ShellTab.reserve),
                          ),
                        ),
                      ],
                    ),
                  if (unresolved.isNotEmpty)
                    ReservationGate(
                      key: const ValueKey('reservation-gate-preferred'),
                      title: '常用館が選ばれていません',
                      body:
                          '${unresolved.map((s) => s.name).join('・')}の常用館が決まって'
                          'いないため、予約を登録できません。常用館は、予約した本を受け取る館です。',
                      actions: [
                        for (final system in unresolved)
                          (
                            unresolved.length == 1
                                ? '常用館を選ぶ'
                                : '${system.name}の常用館を選ぶ',
                            ValueKey('reservation-gate-preferred:${system.id}'),
                            () => _openLibraries(
                              (route) => route.openPreferredBranch(
                                system.id,
                                returnTo: ShellTab.reserve,
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: canSave
                              ? () => actions.save(wanted: true)
                              : null,
                          child: const Text('読みたい'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed:
                              canSave &&
                                  draft.systems.isNotEmpty &&
                                  unresolved.isEmpty
                              ? () => actions.save(wanted: false)
                              : null,
                          child: const Text('予約した'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (draft != null)
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            onPressed: state.saving
                                ? null
                                : () async {
                                    final operation = draft.operationId;
                                    final dirty =
                                        draft.edited ||
                                        draft.systems.isNotEmpty;
                                    final discard =
                                        !dirty ||
                                        await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('入力を破棄しますか？'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          false,
                                                        ),
                                                    child: const Text('続ける'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    child: const Text('破棄する'),
                                                  ),
                                                ],
                                              ),
                                            ) ==
                                            true;
                                    if (mounted &&
                                        discard &&
                                        ref
                                                .read(reservationProvider)
                                                .draft
                                                ?.operationId ==
                                            operation) {
                                      actions.discard();
                                    }
                                  },
                            child: const Text('キャンセル'),
                          ),
                        ),
                    ],
                  ),
                ],
                if (state.message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(state.message),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 常用館の状態。**読めなければ未設定として扱う** — 選ぶ画面が読めないことを出す。
  PreferredBranchState _preferredState(String systemId) {
    try {
      return ref.watch(preferredBranchProvider(systemId)).state;
    } catch (_) {
      return PreferredBranchState.unset;
    }
  }

  /// 図書館管理の1画面を借りる。**閉じたら予約へ帰る**（`returnTo`）。入力中の予約は
  /// `reservationProvider` が保つ。
  void _openLibraries(void Function(LibrariesRoute route) open) {
    open(ref.read(librariesRouteProvider.notifier));
    ref.read(currentTabProvider.notifier).select(ShellTab.settings);
  }

  Future<void> _showWaiting(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final waiting = ref.watch(reservationProvider).waiting;
        return AlertDialog(
          title: Text('受信待ち ${waiting.length}冊'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final item in waiting)
                  ListTile(
                    title: Text('ISBN ${item.book.isbn13}'),
                    trailing: IconButton(
                      tooltip: '受信待ちから削除',
                      icon: const Icon(Icons.close),
                      onPressed: () => ref
                          .read(reservationProvider.notifier)
                          .removeWaiting(item.id),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _lookupManual() async {
    final before = ref.read(reservationProvider).draft!;
    final actions = ref.read(reservationProvider.notifier);
    final result = await actions.manualLookup();
    if (!mounted || result?.record == null) return;
    final record = result!.record!;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取得した書誌を入力欄へ反映しますか？'),
        content: Text(
          '${record.title}\n${record.authorLine ?? ''}\n\n現在のタイトル・著者を置き換えます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('反映する'),
          ),
        ],
      ),
    );
    if (!mounted ||
        accept != true ||
        ref.read(reservationProvider).draft?.operationId !=
            before.operationId) {
      return;
    }
    actions.applyManualLookup(result);
    final current = ref.read(reservationProvider).draft!;
    _title.text = current.title;
    _author.text = current.author;
  }
}

/// 予約画面の書影。**枠と代替ラベルは `../book_cover.dart` が持つ**（2026-09-20）。
///
/// **バイトの取り方だけがここに残る。** 予約は下書きが `coverUrl` を既に持っている
/// （`reservationLookupProvider` が引いた書誌から来る）ので、ISBN から2段で取りに行く
/// [bookCoverProvider] は通さない — 通すと同じ書誌を2回引き、試験の差し替えも効かなくなる。
class ReservationCoverView extends ConsumerWidget {
  const ReservationCoverView({super.key, required this.draft});
  final ReservationDraft? draft;

  /// 予約の書影の幅。**76×108。** 段階2 で決めた値をそのまま持ち越す。
  static const double _width = 76;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = draft;
    // **下書きが無い間は色の種も書名も無い。** 代替ラベルを作れないので、素の記号を置く。
    if (d == null) {
      return Semantics(
        label: '書影',
        child: const SizedBox(
          width: _width,
          height: 108,
          child: Icon(Icons.book_outlined),
        ),
      );
    }
    final bytes = d.coverUrl == null
        ? null
        : ref
              .watch(reservationCoverProvider(d.coverUrl.toString()))
              .asData
              ?.value
              .bytes;
    return BookCoverView.bytes(
      width: _width,
      colorSeed: d.bookId,
      title: d.title,
      bytes: bytes,
    );
  }
}

/// 予約を登録できない理由と、直す画面への入口。**かなり強めに出す**（2026-10-15）。
///
/// 異常の帯（`KaritaNotice`）より強くする — 枠線・見出し・塗りのボタンを持つ。帯は「読めない・
/// 送れない」の知らせで、こちらは**先へ進むために今ここで直すもの**だからである。
class ReservationGate extends StatelessWidget {
  const ReservationGate({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<(String label, Key key, VoidCallback onPressed)> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          border: Border.all(color: scheme.error, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actions)
                  FilledButton.icon(
                    key: action.$2,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    ),
                    onPressed: action.$3,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(action.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
