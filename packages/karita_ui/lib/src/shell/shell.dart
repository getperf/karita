/// 外殻。**起動ゲートと、幅で入れ替わる2つの形である。**
///
/// **共通ヘッダーを持たない**（`非公開資料:ui-state-model.md` §4「共通ヘッダーは
/// 持たない」）。7状態（`SyncState`）は設定画面の持ち物で、この段では触らない。
///
/// **例外は世代変更の帯1本である**（2026-10-08）。止まったことが設定にしか出ないと、
/// 設定を開かない利用者は気づけない。設定のタブでは設定画面が自分の帯を出すので、
/// 外殻は出さない（[_WithNotices]）。
///
/// **ゲートが閉じている間は Navbar を出さない。** 行き先が無いからではなく、**行き先の
/// どれもが台帳を要る**からである。
library;

import '../bookshelf/view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backup/generation_notice.dart';
import '../browser_link/state.dart';
import '../browser_link/view.dart';
import '../density.dart';
import '../first_run/view.dart';
import '../settings/state.dart';
import '../settings/view.dart';
import '../lending/view.dart';
import '../reservation/view.dart';
import 'boot_gate.dart';
import 'handoff_triage.dart';
import 'library_setup.dart';
import 'navigation.dart';

/// レールへ切り替わる幅。**440dp。**
///
/// **Material の 600dp は使えない。** probe の
/// `desktop-browser-workflow.md` §3 が**最小 Window 幅 460px（予約）／480px（貸出し・本棚）で
/// レールを描いている**ので、600 で切ると Windows を細めた時点でモックと食い違う。
///
/// 440 は「Windows が下がれる下限 460」と「Android スマホの上限 412」の間に取った値である。
/// **実機（折りたたみ・タブレット）で1回測る前提の初期値であり、測るまで根拠はその2つ
/// しかない。**
///
/// **密度をこの値で決めない。** Android タブレットは幅 800dp でレール側に入るが、指で触るので
/// 操作要素は 44px のままである（`density.dart`）。
const double shellRailBreakpoint = 440;

/// 本番 GUI の外殻。
///
/// **`ConsumerStatefulWidget` である。** 幅で形が入れ替わっても本文を作り直さないために
/// [GlobalKey] を1つ持ち続ける必要があり、それは build をまたいで残るものである。
class KaritaShell extends ConsumerStatefulWidget {
  const KaritaShell({super.key});

  @override
  ConsumerState<KaritaShell> createState() => _KaritaShellState();
}

class _KaritaShellState extends ConsumerState<KaritaShell> {
  /// **幅で外殻が入れ替わっても、この下を作り直さない**（§4 段階1 の注意点）。
  ///
  /// 下部 Navbar の [Scaffold] とレールの [Row] では本文の親が違うので、素直に書くと
  /// Element が捨てられ、**State も Draft も初期化される。** [GlobalKey] を付けた subtree は
  /// 新しい親へ**同じ Element のまま**移る。
  ///
  /// **State に置く。** build のたびに作り直すと、鍵が変わって意味が無くなる。
  final GlobalKey _bodyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // **ゲートが先である。** 閉じている間は Navbar もレールも出さない。
    // 画面本体（サインイン → 初回起動の2択）は `first_run/view.dart` が持つ。外殻が持つのは
    // 「未了」と「準備済み」の2つだけで、読込中・失敗の表示はあちらの持ち物である（§5 の6）。
    if (!ref.watch(bootReadyProvider)) return const FirstRunScreen();

    // **始め方の次に、ブラウザープラグインのインストール**（Windows のみ、2026-10-15）。
    // 図書館の登録より先に置く — セットアップの最後がブラウザーとの往復だと、karita の中の
    // 作業（図書館の登録）を終えた後にまた外へ出ることになり、流れとして据わりが悪い
    // （`browser_link/state.dart`）。
    if (ref.watch(browserLinkEnsureProvider)) return const BrowserLinkScreen();

    // **図書館が1件も無ければ、先に登録を促す。** 受信した配送は保持されたまま待ち、
    // 登録が済んでから行き先の選択へ戻る（`shell/library_setup.dart`）。
    if (ref.watch(libraryEnsureProvider)) return const LibrarySetupScreen();

    // **台帳の準備より後、タブ本体より前。** 地区選択がホスト逆引き（`LibrarySystems`）を
    // 読むため、初回起動の2択より前には出さない（`shell/handoff_triage.dart`）。
    final pendingTriage = ref.watch(pendingHandoffTriageProvider);
    if (pendingTriage != null) {
      return HandoffTriageScreen(triage: pendingTriage);
    }

    final tab = ref.watch(currentTabProvider);
    final density = ref.watch(densityProvider);
    // **本文はここで1つだけ作る。** 下の分岐へ同じ instance を渡す。
    final body = _TabBodies(key: _bodyKey, tab: tab);
    void select(ShellTab next) =>
        ref.read(currentTabProvider.notifier).select(next);

    // **`MediaQuery` ではなく [LayoutBuilder] である。** 見るのは外殻に与えられた幅であって
    // 画面の幅ではない。両者が違いうる場（分割ウィンドウ）で、外殻が自分の入れ物より広い形を
    // 選ばない。
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= shellRailBreakpoint
          ? _RailShell(tab: tab, density: density, onSelect: select, body: body)
          : _BarShell(tab: tab, density: density, onSelect: select, body: body),
    );
  }
}

/// 幅の狭い側。**下部 Navbar。**
class _BarShell extends StatelessWidget {
  const _BarShell({
    required this.tab,
    required this.density,
    required this.onSelect,
    required this.body,
  });

  final ShellTab tab;
  final Density density;
  final ValueChanged<ShellTab> onSelect;
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: _WithNotices(tab: tab, body: body),
    ),
    bottomNavigationBar: NavigationBar(
      height: density.navigationBarHeight,
      // **現在地は常に出す**（`ui-plan.md` §2）。選択中だけラベルを出す既定にしない。
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      selectedIndex: tab.index,
      onDestinationSelected: (index) => onSelect(ShellTab.values[index]),
      destinations: [
        for (final each in ShellTab.values)
          // **選択中の形を別に渡さない。** 単色の線画に「輪郭↔塗りつぶし」の区別は
          // 無く、現在地は色で出る（`NavigationBar` が状態ごとに `IconTheme` を敷く）。
          NavigationDestination(icon: each.icon, label: each.label),
      ],
    ),
  );
}

/// 幅の広い側。**左のレール。**
class _RailShell extends StatelessWidget {
  const _RailShell({
    required this.tab,
    required this.density,
    required this.onSelect,
    required this.body,
  });

  final ShellTab tab;
  final Density density;
  final ValueChanged<ShellTab> onSelect;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    // **色は必ず配色から採る。** 素の `TextStyle(fontSize: …)` / `IconThemeData(size: …)` を
    // 渡すと、**Material が持っていた色ごと上書きして消える** — 2026-09-16 に実機でそれを
    // 踏んだ（白地に白でラベルが読めなかった）。寸法だけを変えたいときも `copyWith` にする。
    //
    // **ここが明暗の追従点でもある。** `ColorScheme` は `ThemeData.brightness` で入れ替わるので、
    // 配色から採っているかぎり、テーマの選択（`device.json` の `ui.theme`）は外殻を触らずに効く。
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelBase = theme.textTheme.labelMedium ?? const TextStyle();
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              minWidth: density.railWidth,
              // **Material の選択インジケータ（56px の丸枠）は 44px に入らない。**
              // 現在地は選択アイコンと色で示す。
              useIndicator: false,
              labelType: NavigationRailLabelType.all,
              // **現在地は色と太さで示す**（インジケータを落としてあるため）。モックの
              // `--brand` / `--muted` に当たるのが `primary` / `onSurfaceVariant` である。
              selectedIconTheme: IconThemeData(
                size: density.railIconSize,
                color: scheme.primary,
              ),
              unselectedIconTheme: IconThemeData(
                size: density.railIconSize,
                color: scheme.onSurfaceVariant,
              ),
              selectedLabelTextStyle: labelBase.copyWith(
                fontSize: density.railLabelSize,
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelTextStyle: labelBase.copyWith(
                fontSize: density.railLabelSize,
                color: scheme.onSurfaceVariant,
              ),
              selectedIndex: tab.index,
              onDestinationSelected: (index) =>
                  onSelect(ShellTab.values[index]),
              destinations: [
                for (final each in ShellTab.values)
                  NavigationRailDestination(
                    // **Material の既定は左右 8px を足す。** 44px のレールでは「貸出し」の
                    // 3文字（11px × 3 ＝ 33）に 16 が乗って 49 になり、**レールが自分から
                    // 広がる。** probe が数えているのはラベルの文字数だけである。
                    padding: EdgeInsets.zero,
                    icon: each.icon,
                    label: Text(each.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: _WithNotices(tab: tab, body: body),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本文の上に、外殻が持つ帯を置く。**いまは世代変更の1本だけである。**
///
/// **帯の有無で本文の位置を変えない。** 帯は常に同じ位置の子として置き、出さないときは
/// 空にする。子の数が変わると、本文の [GlobalKey] が付いた subtree の親が入れ替わる。
class _WithNotices extends ConsumerWidget {
  const _WithNotices({required this.tab, required this.body});

  final ShellTab tab;
  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **設定では出さない。** 設定画面のヘッダーが同じ帯を出す（二重にしない）。
    final issue = tab == ShellTab.settings
        ? null
        : ref.watch(syncStatusProvider).value?.generationChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (issue == null)
          const SizedBox.shrink()
        else
          Padding(
            key: const ValueKey('shell-generation-notice'),
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: GenerationChangedNotice(issue: issue),
          ),
        Expanded(child: body),
      ],
    );
  }
}

/// 行き先ぶんの本文。**選んでいないものも生かしておく。**
///
/// [IndexedStack] なので、**タブを移っても State は捨てられない。** 段階2 の予約 Draft が
/// 「ブラウザー往復・タブ切替で維持する」と言えるのはこの形のためである。
///
/// **[KaritaShell] の [GlobalKey] はこの Widget に付く。** 幅で親が入れ替わっても、この
/// subtree ごと新しい親へ移る。
class _TabBodies extends StatelessWidget {
  const _TabBodies({super.key, required this.tab});

  final ShellTab tab;

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: tab.index,
    // **本文に外殻ぶんの大きさを渡す。** 最大幅で止めるのはその中である。
    sizing: StackFit.expand,
    children: [
      for (final each in ShellTab.values)
        Align(
          // **本文だけを左寄せで止める**（probe §3）。レールと Navbar は幅いっぱいの
          // ままである。
          alignment: AlignmentDirectional.topStart,
          child: KeyedSubtree(key: ValueKey(each), child: _TabBody(each)),
        ),
    ],
  );
}

/// 行き先1つの本文。設定だけを接続し、他の画面は後続で入れる。
///
/// 設定はヘッダーを全幅、本文だけを最大幅で止める。本棚は段階4で入れる。
///
/// **鍵はこの Widget に付く。** 外側の [Align] ではなく最大幅の内側に付けてあるので、
/// `tester.getSize` が測るのは**止まった後の幅**である。
class _TabBody extends StatelessWidget {
  const _TabBody(this.tab);

  final ShellTab tab;

  @override
  Widget build(BuildContext context) => tab == ShellTab.settings
      ? SettingsView(contentMaxWidth: tab.contentMaxWidth)
      : tab == ShellTab.reserve
      ? ReservationView(contentMaxWidth: tab.contentMaxWidth)
      : tab == ShellTab.lending
      ? LendingView(contentMaxWidth: tab.contentMaxWidth)
      : BookshelfView(contentMaxWidth: tab.contentMaxWidth);
}
