/// 図書館管理の入口。**一覧・詳細・常用館・追加2段・マイページ URL の6枚である。**
///
/// 入口は設定の［図書館設定］行の［設定］で、専用の Navbar タブを持たない
/// （`karita-ui-probe/docs/screens/libraries.md`「基本設定の『図書館設定』行にある［設定］から
/// 一覧へ入る」）。外殻は共通ヘッダーを持たないので、**ヘッダーはこの画面の持ち物である。**
///
/// **利用者向けの表示名は「図書館」。** 内部用語「図書館システム」を画面に出さない（同）。
///
/// **色は必ず `ColorScheme` から採る。** 寸法だけを変えるときも `copyWith` にする
/// （2026-09-16 に白地に白を踏んだ）。
///
/// ## 画面ごとに別のファイルへ割った（2026-09-22）
///
/// 1本で 1404 行あり、この package で最も長かった。**画面の境目がそのまま切れ目である** —
/// `lending/` を 2026-09-20、`bookshelf/` を 2026-09-21 に割ったときと同じ形にしてある。
///
/// - `list.dart` — 一覧と、その1行
/// - `detail.dart` — 詳細（常用館・マイページ・削除の3枚のカード）
/// - `preferred_branch.dart` — 常用館の選択
/// - `add.dart` — 追加の2段（都道府県・検索）
/// - `mypage_url.dart` — マイページ URL の編集
/// - `shared.dart` — 5枚が使う枠。**`karita_ui.dart` からは export しない。**
///
/// **層（`providers/`・`views/`）では切っていない**（`karita_ui.dart` の「中の並べ方」）。
/// ここに残すのはヘッダーと行き先の分岐、そして［図書館追加］だけである。
/// **セッションの状態は Riverpod へ移していない** — 常用館・追加検索・マイページ URL の
/// 3枚は `TextEditingController` と Draft を State に持ち、移すと持ち主が2つに割れる。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../density.dart';
import '../shell/navigation.dart';
import 'add.dart';
import 'detail.dart';
import 'list.dart';
import 'mypage_url.dart';
import 'preferred_branch.dart';
import 'state.dart';

/// 図書館管理の器。**設定タブの本文を置き換える形で出る。**
class LibrariesView extends ConsumerStatefulWidget {
  const LibrariesView({super.key, required this.contentMaxWidth});

  final double contentMaxWidth;

  @override
  ConsumerState<LibrariesView> createState() => _LibrariesViewState();
}

class _LibrariesViewState extends ConsumerState<LibrariesView> {
  /// 画面が変わったら見出しへ移す。**フォーカスは Widget が持つ**（§5）。
  ///
  /// probe のモックが遷移のたびに `title.focus()` しているのと同じ意図である。画面全体が
  /// 入れ替わるのに読み上げ位置が前の画面のままだと、何が起きたか分からない。
  final FocusNode _titleFocus = FocusNode(debugLabel: 'libraries-title');

  LibrariesScreen? _lastScreen;

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = ref.watch(librariesRouteProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_lastScreen != route.screen) {
      _lastScreen = route.screen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && route.isOpen) _titleFocus.requestFocus();
      });
    }

    // **非表示のタブでも PopScope は生きている。** 外殻は `IndexedStack` で4タブ全部を
    // 生かすので、`canPop: false` をそのまま置くと、本棚タブに居るときの戻る操作まで
    // ここが飲んでしまう。**いま設定タブに居るときだけ効かせる。**
    final onSettingsTab = ref.watch(currentTabProvider) == ShellTab.settings;

    return PopScope(
      canPop: !onSettingsTab || !route.isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ref.read(librariesRouteProvider.notifier).back();
      },
      child: Material(
        color: scheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              // **詳細は館の名前を出す**（probe のモックと同じ）。本文で繰り返さない。
              title: switch (route.screen) {
                LibrariesScreen.preferredBranch => '常用館',
                LibrariesScreen.mypageUrl => 'マイページ URL 登録',
                LibrariesScreen.detail => _nameOf(ref, route.systemId!),
                LibrariesScreen.addPrefecture => '都道府県',
                // 探している県を出す。**詳細が館の名前を出すのと同じ扱いである。**
                LibrariesScreen.addSearch => route.pref!,
                _ => '図書館',
              },
              titleFocus: _titleFocus,
              // **［図書館追加］は一覧のヘッダーだけに出る**（probe のモック）。
              // 都道府県 → `/library` を1回 → キーワードは端末側で絞る。
              trailing: route.screen == LibrariesScreen.list
                  ? const _AddButton()
                  : null,
              onBack: () => ref.read(librariesRouteProvider.notifier).back(),
            ),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: ConstrainedBox(
                  key: const ValueKey('libraries-content'),
                  constraints: BoxConstraints(maxWidth: widget.contentMaxWidth),
                  // **鍵を対象で付ける。** 常用館の画面は選択中の分館を State に持つので、
                  // 別の館へ移ったときに前の Draft が居残らないようにする。
                  child: switch (route.screen) {
                    LibrariesScreen.preferredBranch => PreferredBranchScreen(
                      key: ValueKey('branch:${route.systemId}'),
                      systemId: route.systemId!,
                    ),
                    LibrariesScreen.detail => LibraryDetailScreen(
                      key: ValueKey('detail:${route.systemId}'),
                      systemId: route.systemId!,
                    ),
                    LibrariesScreen.mypageUrl => MypageUrlScreen(
                      key: ValueKey('mypage:${route.systemId}'),
                      systemId: route.systemId!,
                    ),
                    LibrariesScreen.addPrefecture =>
                      const AddPrefectureScreen(),
                    LibrariesScreen.addSearch => AddSearchScreen(
                      key: ValueKey('add:${route.pref}'),
                      pref: route.pref!,
                    ),
                    _ => const LibrariesListScreen(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ヘッダーに出す館の名前。**読めなくても、対象が無くてもヘッダーは出す。**
///
/// 本文の側が理由（読込失敗か対象なしか）を出すので、ヘッダーは画面名へ落ちるだけでよい。
String _nameOf(WidgetRef ref, String systemId) {
  try {
    return ref.watch(libraryProvider(systemId))?.name ?? '図書館';
  } catch (_) {
    return '図書館';
  }
}

/// 固定ヘッダー。**設定画面と同じ形である** — ペイン全幅、本文だけを最大幅で止める。
///
/// **高さを固定しない。** 文字拡大と長い画面名に必要な高さを確保する（設定の段の決定）。
class _Header extends ConsumerWidget {
  const _Header({
    required this.title,
    required this.titleFocus,
    required this.onBack,
    this.trailing,
  });

  final String title;
  final FocusNode titleFocus;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final density = ref.watch(densityProvider);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: density.control,
                minHeight: density.control,
              ),
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: '戻る',
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Focus(
                focusNode: titleFocus,
                child: Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// ［図書館追加］。**都道府県を選ぶところから始まる。**
///
/// モックはキーワード検索だけの追加画面を描いているが、**2026-09-16 の実測で都道府県を先に
/// 選ぶ2段階に決まっている**（同梱47件 → `/library?pref=X` を1回 → 端末側で絞込み）。
/// モックはその決定より前のもので、写すと決定と違うものが入る。
class _AddButton extends ConsumerWidget {
  const _AddButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
    onPressed: () => ref.read(librariesRouteProvider.notifier).openAdd(),
    child: const Text('図書館追加'),
  );
}
