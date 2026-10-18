/// 本棚の入口。**一覧と本の記録の2枚である**（`screens/bookshelf.md`）。
///
/// ここが持つのは**セッションの状態と行き先の分岐**だけである — 検索欄・絞込み・いま開いて
/// いる本。どちらの画面を出すかは `selected` が決める。
///
/// ## 2枚を別のファイルへ割った（2026-09-21）
///
/// 1本で 891 行あり、蔵書のバッジを足してさらに伸びた。**画面の境目がそのまま切れ目である**
/// — `lending/` を 2026-09-20 に割ったときと同じ形にしてある。
///
/// - `row.dart` — 一覧の1行と、ヘッダーの「蔵書を確認」
/// - `record.dart` — 本の記録
/// - `shared.dart` — 両方が使う2つ。**`karita_ui.dart` からは export しない。**
/// - `holdings.dart` — 蔵書照会の走りと、語・リンクの規則
/// - `state.dart` — 台帳の読み口と検索の照合
///
/// **層（`providers/`・`views/`）では切っていない**（`karita_ui.dart` の「中の並べ方」）。
/// **セッションの状態は Riverpod へ移していない** — `TextEditingController` と変換確定の
/// 購読は StatefulWidget に居る必要があり、移すと持ち主が2つに割れる。画面が3枚目に増えた
/// ときに考える。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_domain/karita_domain.dart';

import '../libraries/state.dart';
import '../reservation/state.dart';
import '../shell/navigation.dart';
import 'record.dart';
import 'row.dart';
import 'shared.dart';
import 'state.dart';

class BookshelfView extends ConsumerWidget {
  const BookshelfView({super.key, this.contentMaxWidth = 640});
  final double contentMaxWidth;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerRevisionProvider);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: contentMaxWidth),
      child: _ShelfSession(
        key: ObjectKey(ref.watch(ledgerSessionProvider)),
      ),
    );
  }
}

class _ShelfSession extends ConsumerStatefulWidget {
  const _ShelfSession({super.key});
  @override
  ConsumerState<_ShelfSession> createState() => _ShelfSessionState();
}

class _ShelfSessionState extends ConsumerState<_ShelfSession> {
  final query = TextEditingController();
  String filter = 'all', reason = '', system = '', keyword = '';
  String? selected;
  List<ShelfBook>? lastBooks;
  bool opened = false;
  @override
  void initState() {
    super.initState();
    query.addListener(_keyword);
    // **組まれる前に置かれた合図も拾う。** 冷えた起動（Amazon の共有で karita が起きた）
    // では、判定が本棚の画面より先に合図を置く。`ref.listen` は以後の変化しか見ない。
    final pending = ref.read(shelfOpenRequestProvider);
    if (pending != null) {
      selected = pending;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(shelfOpenRequestProvider.notifier).taken();
      });
    }
  }

  /// **日本語変換の確定では `onChanged` が来ない。** 変換の確定は本文を変えず範囲だけを閉じるので、
  /// `onChanged` を待つと「夏目」「全角のISBN」がいつまでも絞込みに入らない。
  /// 変換中は一覧を作り直さず、確定・取消のあとの本文へ追従する。
  void _keyword() {
    if (!query.value.composing.isCollapsed || query.text == keyword) return;
    setState(() => keyword = query.text);
  }

  /// 本の記録を閉じる。**貸出しから借りた画面なら、閉じたら貸出しへ帰す。**
  /// 保存でも戻るでも、ここを通る。
  void closeRecord() {
    setState(() => selected = null);
    final origin = ref.read(shelfReturnProvider);
    if (origin == null) return;
    ref.read(shelfReturnProvider.notifier).set(null);
    ref.read(currentTabProvider.notifier).select(origin);
  }

  @override
  void dispose() {
    query.removeListener(_keyword);
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // **外から頼まれた本を開く**（貸出しの行から。2026-09-21）。
    //
    // 早い `return` より前に置く。本棚をまだ一度も開いていない端末でも、この Widget 自体は
    // `IndexedStack` の中に組まれているので、合図は受け取れる。
    ref.listen(shelfOpenRequestProvider, (_, next) {
      if (next == null) return;
      setState(() => selected = next);
      ref.read(shelfOpenRequestProvider.notifier).taken();
    });
    // **本棚から別のタブへ移ったら、貸出しへ帰る約束は捨てる。**
    ref.listen(currentTabProvider, (_, next) {
      if (next != ShellTab.bookshelf) {
        ref.read(shelfReturnProvider.notifier).set(null);
      }
    });
    opened = opened || ref.watch(currentTabProvider) == ShellTab.bookshelf;
    if (!opened) return const SizedBox.shrink();
    final data = ref.watch(bookshelfProvider);
    final books = data.value ?? lastBooks;
    if (data.hasValue) lastBooks = data.value;
    // 再照会の失敗で詳細の入力Widgetを捨てない。
    return (books == null ? data : AsyncData(books)).when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('本棚を読み込めませんでした。'),
            TextButton(
              onPressed: () => ref.invalidate(bookshelfProvider),
              child: const Text('再試行'),
            ),
          ],
        ),
      ),
      data: (all) {
        final chosen = all.where((b) => b.id == selected).firstOrNull;
        if (selected != null) {
          return chosen == null
              ? Column(
                  children: [
                    TextButton(
                      onPressed: closeRecord,
                      child: Text(
                        shelfBackLabel(ref.watch(shelfReturnProvider)),
                      ),
                    ),
                    const Text('この本は台帳にありません。'),
                  ],
                )
              : ShelfRecord(
                  key: ValueKey(selected),
                  book: chosen,
                  onBack: closeRecord,
                );
        }
        final visible = all
            .where((b) => b.state == 'wanted' || b.state == 'read')
            .toList();
        // 検索語の正規化は1回だけ。本ごとの鍵は投影1回につき1回しか作らない。
        final key = shelfSearchKey(keyword);
        final rows = visible
            .where(
              (b) =>
                  (filter == 'all' || b.state == filter) &&
                  shelfMatchesKey(b, key) &&
                  (filter != 'read' ||
                      ((reason.isEmpty || b.reason == reason) &&
                          (system.isEmpty ||
                              b.histories.any((h) => h.systemId == system)))),
            )
            .toList();
        // **読みたいを先に、読んだを後に出す**（2026-09-21）。中の順序は台帳の並び
        // （本棚変更の新しい順＋bookId）のままで、まとまりだけを足す安定な分割である。
        final ordered = [
          for (final b in rows)
            if (b.state == 'wanted') b,
          for (final b in rows)
            if (b.state != 'wanted') b,
        ];
        final systems = {
          for (final b in visible)
            for (final h in b.histories)
              if (h.systemId != null) h.systemId!,
        }.toList()..sort();
        final libraries = shelfLibraries(ref);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('本棚', style: Theme.of(context).textTheme.titleLarge),
                      const Spacer(),
                      IconButton(
                        tooltip: '本棚を更新',
                        onPressed: () => ref.invalidate(bookshelfProvider),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  TextField(
                    key: const ValueKey('shelf.search'),
                    controller: query,
                    decoration: const InputDecoration(
                      labelText: '書名・著者・ISBN',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in const {
                        'all': '全件',
                        'wanted': '読みたい',
                        'read': '読んだ',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: filter == entry.key,
                          onSelected: (_) => setState(() {
                            filter = entry.key;
                            if (filter != 'read') {
                              reason = '';
                              system = '';
                            }
                          }),
                        ),
                    ],
                  ),
                  if (filter == 'read')
                    Wrap(
                      spacing: 8,
                      children: [
                        DropdownButton<String>(
                          value: reason,
                          items: [
                            for (final r in ['', '手動登録', '返却済み'])
                              DropdownMenuItem(
                                value: r,
                                child: Text(r.isEmpty ? '登録理由：すべて' : r),
                              ),
                          ],
                          onChanged: (v) => setState(() => reason = v ?? ''),
                        ),
                        DropdownButton<String>(
                          value: systems.contains(system) ? system : '',
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('利用システム：すべて'),
                            ),
                            for (final s in systems)
                              DropdownMenuItem(
                                value: s,
                                child: Text(libraries[s]?.name ?? s),
                              ),
                          ],
                          onChanged: (v) => setState(() => system = v ?? ''),
                        ),
                      ],
                    ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('shelf.add'),
                        icon: const Icon(Icons.add),
                        label: const Text('本を追加'),
                        onPressed: () {
                          ref
                              .read(reservationProvider.notifier)
                              .openFromBookshelf();
                          ref
                              .read(currentTabProvider.notifier)
                              .select(ShellTab.reserve);
                        },
                      ),
                      // 蔵書は押されたときだけ照会する。**描画・タブ入場では始めない。**
                      CheckHoldingsButton(
                        wanted: [
                          for (final b in rows)
                            if (b.state == 'wanted') b,
                        ],
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${rows.length}冊'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        visible.isEmpty ? '本棚に本がありません。' : '条件に一致する本がありません。',
                      ),
                    )
                  : ListView.builder(
                      key: const PageStorageKey('bookshelf.list'),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: ordered.length,
                      itemBuilder: (context, index) {
                        final b = ordered[index];
                        return ShelfRow(
                          book: b,
                          onOpen: () => setState(() => selected = b.id),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
