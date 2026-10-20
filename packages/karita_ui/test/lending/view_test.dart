/// 貸出し画面を実際に描く。**状態の試験で見えないものだけをここで見る。**
///
/// 件数の併記、枠内全体がリンクであること、詳細の2段組、受取館のリンク、終端行の残り方、
/// そしてスクロール位置の保持。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    home = Directory.systemTemp.createTempSync('karita-lending-view-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
  });
  tearDown(() {
    app.close();
    home.deleteSync(recursive: true);
  });

  /// **背の高い画面で描く。** デモの5区は 600px に収まらず、[ListView] は見えていない分を
  /// 作らない。スクロールそのものを測る試験だけが狭い画面を使う。
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Size size = const Size(640, 2400),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(app)],
    );
    addTearDown(container.dispose);
    // **タブ入場が読み直しの契機である。** 画面を出す前に入場させる。
    container.read(lendingProvider);
    container.read(currentTabProvider.notifier).select(ShellTab.lending);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const Scaffold(body: LendingView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> openArea(WidgetTester tester, String systemId) async {
    final card = find.byKey(ValueKey('lending.area.$systemId'));
    await tester.scrollUntilVisible(card, 200);
    await tester.tap(card);
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(find.byKey(key), 200);
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  String loanIn(ProviderContainer c, String systemId, [String? status]) {
    final state = c.read(lendingProvider);
    return state.order.firstWhere(
      (id) =>
          state.rows[id]!.systemId == systemId &&
          (status == null || state.rows[id]!.status == status),
    );
  }

  testWidgets('初期画面はフィルタに件数を併記する', (tester) async {
    await pump(tester);
    expect(find.text('受取と返却間近 ${_soonCount(app)}'), findsOneWidget);
    expect(find.text('予約中 7'), findsOneWidget);
    expect(find.text('全件 13'), findsOneWidget);
    // **取置・貸出中は外した**（2026-10-15）。既定は全件で、先頭に立つ。
    expect(find.textContaining('取置・貸出中'), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('lending.filter.all')))
          .selected,
      isTrue,
    );
  });

  testWidgets('フィルタは全管理区分へ一括で効き、0件の枠も残る', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('lending.filter.reserved')));
    await tester.pumpAndSettle();
    // 5区すべての枠が出る。該当が無い区は枠の中で「ありません」と言う。
    for (final id in [
      'Tokyo_Koto',
      'Tokyo_Minato',
      'Tokyo_Katsushika',
      'Tokyo_Edogawa',
      'Tokyo_Sumida',
    ]) {
      expect(
        find.byKey(ValueKey('lending.area.$id')),
        findsOneWidget,
        reason: id,
      );
    }
    // **0件はそう言わずに、枠と `0件 ›` で示す**（2026-09-20）。本文へ1行足すと、
    // 該当の無い区のほうが縦に場所を取る。
    expect(find.text('この条件に該当する図書はありません'), findsNothing);
    expect(find.text('0件 ›'), findsWidgets);
  });

  /// **サマリは1文字のバッジと `MM-DD` である**（2026-09-20）。`取置中 期限 2026-09-20` は
  /// 読み取り専用の一覧には太く、区ごとの内訳が読めるだけの隙間が残らなかった。
  ///
  /// **期待する日付を暦から作る**（2026-09-22）。デモの期限は今日からの相対日で入るので
  /// （`DemoFixture` の `_LoanSeed.due`）、`09-20` と書くと書いた日にしか緑にならない。
  testWidgets('初期画面のサマリは状態を1文字、期限を MM-DD で出す', (tester) async {
    await pump(tester);
    final today = DateTime.now();
    final mmdd =
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    expect(find.text(mmdd), findsWidgets, reason: '期限 0日の行が今日の日付で出る');
    expect(
      find.textContaining('期限 ${today.year}-'),
      findsNothing,
      reason: '年と見出しは落とす',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lending.badge.ready_for_pickup')),
        matching: find.text('取'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lending.badge.borrowed')),
        matching: find.text('貸'),
      ),
      findsWidgets,
    );
  });

  testWidgets('文字を拡大しても期限列の幅を確保する', (tester) async {
    await pump(tester, textScale: 1.6);
    final today = DateTime.now();
    final mmdd =
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    expect(
      tester.getSize(find.text(mmdd).first).width,
      greaterThanOrEqualTo(89),
    );
  });

  /// **期限を持たない予約中でも欄を出す**（2026-09-20 の改定）。元は「期限欄そのものを
  /// 出さない」だったが、欄ごと消すと右端が行ごとに動き、桁を揃える目的と衝突する。
  testWidgets('予約中もバッジと期限の桁が揃い、期限はダッシュになる', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('lending.filter.reserved')));
    await tester.pumpAndSettle();

    final badges = find.byKey(const ValueKey('lending.badge.reserved'));
    expect(find.descendant(of: badges, matching: find.text('予')), findsWidgets);
    expect(find.text('–'), findsWidgets, reason: '期限を持たない行にも欄が出る');

    // **同じ区の行なら桁が動かない。** バッジの左端がすべて同じ x に来る。
    await tester.tap(find.byKey(const ValueKey('lending.filter.all')));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('lending.area.Tokyo_Koto'));
    final lefts = <double>{
      for (final element
          in find
              .descendant(of: card, matching: find.byType(Container))
              .evaluate())
        if (element.widget.key case final ValueKey<String> key
            when key.value.startsWith('lending.badge.'))
          (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dx,
    };
    expect(lefts, hasLength(1), reason: '予約中も取置中も同じ列に立つ');
  });

  testWidgets('枠を押すと詳細が開き、受取・返却と予約中に分かれる', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');

    expect(
      container.read(lendingRouteProvider),
      equals(const LendingRouteState.area('Tokyo_Koto')),
    );
    expect(find.text('取置中・貸出中 3冊'), findsOneWidget);
    expect(find.text('5冊'), findsOneWidget);
    expect(find.textContaining('の図書館サイトを開く'), findsOneWidget);
    // **初期画面の絞り込みは持ち込まない。** 区に入ったらその区の全部を相手にする。
    expect(find.byKey(const ValueKey('lending.filter.all')), findsNothing);
  });

  testWidgets('更新ボタンは詳細にだけあり、初期画面には無い（2026-10-20）', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('lending.refresh')), findsNothing);
    await openArea(tester, 'Tokyo_Koto');
    expect(find.byKey(const ValueKey('lending.refresh')), findsOneWidget);
  });

  testWidgets('返却した行は位置に残り、更新で外れる', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'borrowed');

    await tapRow(tester, ValueKey('lending.return.$target'));

    expect(find.byKey(ValueKey('lending.row.$target')), findsOneWidget);
    expect(
      container.read(lendingProvider).statusOf(target),
      equals('returned'),
    );
    expect(find.text('↻ 更新 (1)'), findsOneWidget);

    await tapRow(tester, const ValueKey('lending.refresh'));
    expect(find.byKey(ValueKey('lending.row.$target')), findsNothing);
  });

  /// **ルールを入れない**（2026-09-19 の差し替え）。4つのボタンはどの状態でも押せる。
  testWidgets('4つの状態はどれも常に押せて、選択中だけが色で分かる', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'reserved');

    // 予約中の行でも、返却済も貸出中も押せる。
    for (final action in ['reserve', 'ready-for-pickup', 'borrow', 'return']) {
      final button = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(ValueKey('lending.$action.$target')),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNotNull, reason: action);
    }

    // 予約中 → 返却済 → 予約中 と往復できる。
    await tapRow(tester, ValueKey('lending.return.$target'));
    expect(
      container.read(lendingProvider).statusOf(target),
      equals('returned'),
    );
    await tapRow(tester, ValueKey('lending.reserve.$target'));
    expect(
      container.read(lendingProvider).statusOf(target),
      equals('reserved'),
    );
    expect(
      container.read(lendingProvider).leaving.containsKey(target),
      isFalse,
      reason: '一覧へ帰ってくる',
    );
  });

  /// モックの `.book-controls` は `repeat(4, minmax(0, 1fr)) 76px`。**期限だけが固定幅**で、
  /// 4つの状態が残りを均等に分ける。5等分にすると `09/20` の5文字に状態ボタンと同じ幅が
  /// 与えられ、横に空白が広がる（2026-09-19 の直し）。
  testWidgets('4つの状態は均等、期限は固定幅で1行に並ぶ', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'borrowed');
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('lending.row.$target')),
      200,
    );
    final widths = [
      for (final key in [
        'lending.reserve.$target',
        'lending.ready-for-pickup.$target',
        'lending.borrow.$target',
        'lending.return.$target',
      ])
        tester.getSize(find.byKey(ValueKey(key))).width,
    ];
    expect(widths.toSet(), hasLength(1), reason: '4つとも同じ幅');
    final date = tester.getSize(find.byKey(ValueKey('lending.date.$target')));
    expect(date.width, lessThan(widths.first), reason: '期限は狭い固定幅');

    final tops = [
      for (final key in ['lending.reserve.$target', 'lending.date.$target'])
        tester.getTopLeft(find.byKey(ValueKey(key))).dy,
    ];
    expect(tops.first, equals(tops.last), reason: '1行に並ぶ');
  });

  /// **選択中の1つが行の主役（書名）より目立たない**（2026-09-19 の直し）。
  /// `primaryContainer` は配色によっては濃く出るので、主色の薄い被せにした。
  testWidgets('選択中の地色は主色の薄い被せで、枠は1px', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'borrowed');
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('lending.row.$target')),
      200,
    );
    final scheme = Theme.of(
      tester.element(find.byKey(ValueKey('lending.row.$target'))),
    ).colorScheme;

    final selected = tester
        .widget<OutlinedButton>(
          find.descendant(
            of: find.byKey(ValueKey('lending.borrow.$target')),
            matching: find.byType(OutlinedButton),
          ),
        )
        .style!;
    final fill = selected.backgroundColor!.resolve({})!;
    expect(fill.a, lessThan(0.2), reason: '地に近い薄さ');
    expect(
      fill,
      isNot(equals(scheme.primaryContainer)),
      reason: '濃く出る容器色は使わない',
    );
    expect(selected.side!.resolve({})!.width, equals(1.0));
  });

  testWidgets('期限は1クリックで確定する。OK は無い', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'borrowed');
    final before = container.read(lendingProvider).rows[target]!.dueOn;

    await tapRow(tester, ValueKey('lending.date.$target'));
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'OK'), findsNothing);
    // **キャンセルは在る。** 確定が1タップである以上、開いてしまったことからの出口が要る。
    expect(find.byKey(const ValueKey('lending.date.cancel')), findsOneWidget);

    // 日を1つ押しただけで閉じ、確定する。
    final day = DateTime.parse(before!).day == 15 ? '16' : '15';
    await tester.tap(find.text(day).last);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsNothing);
    final after = container.read(lendingProvider).rows[target]!.dueOn;
    expect(after, isNot(equals(before)));
    expect(after!.substring(8), equals(day.padLeft(2, '0')));
  });

  testWidgets('キャンセルでは期限が変わらない', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'borrowed');
    final before = container.read(lendingProvider).rows[target]!.dueOn;

    await tapRow(tester, ValueKey('lending.date.$target'));
    await tester.tap(find.byKey(const ValueKey('lending.date.cancel')));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(container.read(lendingProvider).rows[target]!.dueOn, equals(before));
  });

  /// **「〜にしました。」は本文へ置かない**（2026-09-19）。出したら消える notice にする。
  testWidgets('操作の結果は notice で出て、本文には残らない', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'borrowed');

    await tapRow(tester, ValueKey('lending.return.$target'));
    final text = container.read(lendingProvider).message;
    expect(text, contains('にしました'));
    expect(find.widgetWithText(SnackBar, text), findsOneWidget);
    // 本文（一覧）の側には出ていない。
    expect(
      find.descendant(of: find.byType(ListView), matching: find.text(text)),
      findsNothing,
    );
  });

  testWidgets('受取館と［変更］には下線が引かれる', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'borrowed');
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('lending.row.$target')),
      200,
    );
    for (final key in ['lending.branch.$target', 'lending.preferred.change']) {
      final style = tester
          .widget<TextButton>(find.byKey(ValueKey(key)))
          .style!
          .textStyle!
          .resolve({})!;
      expect(style.decoration, equals(TextDecoration.underline), reason: key);
    }
  });

  testWidgets('常用館のすぐ隣に［変更］があり、図書館管理へ渡す', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final label = find.textContaining('常用館');
    final change = find.byKey(const ValueKey('lending.preferred.change'));
    expect(label, findsOneWidget);
    expect(change, findsOneWidget);
    expect(
      tester.getTopLeft(change).dx,
      greaterThan(tester.getTopLeft(label).dx),
      reason: '常用館の右隣',
    );
    expect(
      tester.getTopLeft(change).dy,
      closeTo(tester.getTopLeft(label).dy, 12),
      reason: '同じ行',
    );

    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(container.read(currentTabProvider), equals(ShellTab.settings));
    expect(
      container.read(librariesRouteProvider),
      equals(const LibrariesRouteState.preferredBranch('Tokyo_Koto')),
    );
  });

  testWidgets('［URL変更］でマイページURLの現在値と出典が出る', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');

    final panel = find.byKey(const PageStorageKey('lending.url.panel'));
    expect(panel, findsOneWidget);
    expect(find.text('URL変更'), findsOneWidget);
    await tapRow(tester, const PageStorageKey('lending.url.panel'));

    final url = container.read(mypageUrlProvider('Tokyo_Koto'));
    expect(find.text(url.value!), findsOneWidget);
    expect(find.textContaining('出典:'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lending.url.change')));
    await tester.pumpAndSettle();
    expect(container.read(currentTabProvider), equals(ShellTab.settings));
    expect(
      container.read(librariesRouteProvider),
      equals(const LibrariesRouteState.mypageUrl('Tokyo_Koto')),
    );
  });

  /// **[ExpansionTile] は一覧のスクロール位置と同じ棚を使ってはいけない**（2026-09-19 の障害）。
  ///
  /// `PageStorage` の格納先は「自分から上へ辿って集めた [PageStorageKey] の並び」で決まる。
  /// URL パネルの鍵を素の `ValueKey` にしていたので、識別子が祖先の [ListView] の
  /// `PageStorageKey('lending.area.…')` だけになり、**スクロール位置（`double`）と同じ棚を
  /// 共有していた。** 次に開いたとき `readState(context) as bool?` が `double` を受けて落ちる
  /// （`expansible.dart`）。区を出入りすると必ず起きる。
  testWidgets('区を出入りしても URL パネルが落ちない', (tester) async {
    final container = await pump(tester, size: const Size(640, 700));
    final route = container.read(lendingRouteProvider.notifier);
    await openArea(tester, 'Tokyo_Koto');

    // 一覧を送る。ここでスクロール位置が PageStorage へ書かれる。
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();

    // 戻って入り直すと、URL パネルの State が作り直されて読みに行く。
    route.back();
    await tester.pumpAndSettle();
    route.openArea('Tokyo_Koto');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // 先頭へ戻せばパネルは在る（スクロール位置は保つので、入り直した直後は画面の外）。
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const PageStorageKey('lending.url.panel')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const PageStorageKey('lending.url.panel')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '開閉も通る');
  });

  /// **直したら元の区へ帰す**（2026-09-19）。出口は `LibrariesRoute.back()` の1本なので、
  /// 保存でも取消でも同じ経路を通る。
  testWidgets('常用館から戻ると貸出しの元の区へ帰る', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    await tapRow(tester, const ValueKey('lending.preferred.change'));
    expect(
      container.read(librariesRouteProvider),
      equals(const LibrariesRouteState.preferredBranch('Tokyo_Koto')),
    );

    // 図書館管理の側が閉じると、貸出しタブの元の区へ戻る。
    container.read(librariesRouteProvider.notifier).back();
    await tester.pumpAndSettle();

    expect(container.read(currentTabProvider), equals(ShellTab.lending));
    expect(container.read(librariesRouteProvider).isOpen, isFalse);
    expect(
      container.read(lendingRouteProvider),
      equals(const LendingRouteState.area('Tokyo_Koto')),
      reason: '元の区のまま',
    );
  });

  testWidgets('URL変更から戻ると貸出しの元の区へ帰る', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    await tapRow(tester, const PageStorageKey('lending.url.panel'));
    await tapRow(tester, const ValueKey('lending.url.change'));
    expect(
      container.read(librariesRouteProvider),
      equals(const LibrariesRouteState.mypageUrl('Tokyo_Koto')),
    );

    container.read(librariesRouteProvider.notifier).back();
    await tester.pumpAndSettle();

    expect(container.read(currentTabProvider), equals(ShellTab.lending));
    expect(container.read(librariesRouteProvider).isOpen, isFalse);
    expect(
      container.read(lendingRouteProvider),
      equals(const LendingRouteState.area('Tokyo_Koto')),
    );
  });

  testWidgets('図書館管理から自分で開いた常用館は、これまでどおり詳細へ戻る', (tester) async {
    final container = await pump(tester);
    container
        .read(librariesRouteProvider.notifier)
        .openPreferredBranch('Tokyo_Koto');
    await tester.pumpAndSettle();
    container.read(librariesRouteProvider.notifier).back();
    expect(
      container.read(librariesRouteProvider),
      equals(const LibrariesRouteState.detail('Tokyo_Koto')),
    );
    expect(
      container.read(currentTabProvider),
      equals(ShellTab.lending),
      reason: 'タブは動かさない',
    );
  });

  testWidgets('受取館はリンクで、押すと分館から選び直せる。常用館は変わらない', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'reserved');
    final branches = app
        .loadLibraries()
        .firstWhere((s) => s.id == 'Tokyo_Koto')
        .branches;
    final preferred = app.preferredBranchFor('Tokyo_Koto');

    await tapRow(tester, ValueKey('lending.branch.$target'));
    // **説明文は置かない**（2026-09-19）。見出しと分館の並びだけで用は足りる。
    expect(find.text('受取館を変える'), findsOneWidget);
    for (final branch in branches) {
      expect(
        find.byKey(ValueKey('lending.branch.option.${branch.id}')),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.byKey(ValueKey('lending.branch.option.${branches[1].id}')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(lendingProvider).rows[target]!.pickupLibraryName,
      equals(branches[1].name),
    );
    expect(
      app.preferredBranchFor('Tokyo_Koto'),
      equals(preferred),
      reason: '常用館は動かない',
    );
  });

  /// **予約中のセルは予約日を出し、押すと予約日を直す**（2026-10-20）。館サイトは予約日順に
  /// 並べるので、登録日が入ったままだと並びがずれる。期限と取り違えないよう淡い色で出す。
  testWidgets('予約中の行は予約日を出し、1クリックで予約日を直す', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Katsushika');
    final target = loanIn(container, 'Tokyo_Katsushika');
    final before = container.read(lendingProvider).rows[target]!;
    expect(before.status, equals('reserved'));
    final reservedOn = before.reservedOn!;
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('lending.row.$target')),
      200,
    );
    final date = find.byKey(ValueKey('lending.date.$target'));
    expect(
      find.descendant(
        of: date,
        matching: find.text(
          '${reservedOn.substring(5, 7)}/${reservedOn.substring(8, 10)}',
        ),
      ),
      findsOneWidget,
    );

    await tapRow(tester, ValueKey('lending.date.$target'));
    final day = DateTime.parse(reservedOn).day == 15 ? '16' : '15';
    await tester.tap(find.text(day).last);
    await tester.pumpAndSettle();

    final after = container.read(lendingProvider).rows[target]!;
    expect(after.status, equals('reserved'));
    expect(after.reservedOn!.substring(8), equals(day.padLeft(2, '0')));
  });

  testWidgets('スクロール位置を保つ。区へ入って戻っても先頭へ跳ねない', (tester) async {
    await pump(tester, size: const Size(640, 500));
    // 最後の区まで送ってから入る。**位置を読むのは送り終えた後である。**
    final card = find.byKey(const ValueKey('lending.area.Tokyo_Sumida'));
    await tester.scrollUntilVisible(card, 200);
    await tester.pumpAndSettle();
    final offset = tester
        .widget<Scrollable>(find.byType(Scrollable).first)
        .controller!
        .offset;
    expect(offset, greaterThan(0));

    await tester.tap(card);
    await tester.pumpAndSettle();
    await tapRow(tester, const ValueKey('lending.back'));

    expect(
      tester
          .widget<Scrollable>(find.byType(Scrollable).first)
          .controller!
          .offset,
      equals(offset),
      reason: 'PageStorageKey が初期画面の位置を覚えている',
    );
  });

  testWidgets('削除済みのシステムでも枠は出て、受取館は押せない', (tester) async {
    await app.removeLibrarySystem('Tokyo_Koto');
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');

    expect(find.textContaining('この図書館システムは登録されていません'), findsWidgets);
    final target = loanIn(container, 'Tokyo_Koto');
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('lending.row.$target')),
      200,
    );
    final link = tester.widget<TextButton>(
      find.byKey(ValueKey('lending.branch.$target')),
    );
    expect(link.onPressed, isNull, reason: '選び直す先が無い');
  });

  // --- 取消（一括）と ＋ この地区へ図書を追加（2026-09-20） -------------------
  //
  // **どちらもモックに合わせた。** 行の操作列は4つの状態と期限で埋まっているので取消は
  // 一括にし、追加は台帳に在る書誌から選ぶこの画面のダイアログにした（外への書誌検索は
  // `lending.md` §6 が扱わないものである）。

  testWidgets('ヘッダーの［取消］で選択モードへ入り、更新は押せなくなる', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');

    expect(find.byKey(const ValueKey('lending.cancel.commit')), findsNothing);
    await tapRow(tester, const ValueKey('lending.cancel.begin'));

    expect(container.read(lendingSelectionProvider).active, isTrue);
    // **選択状態を失う操作は無効にする**（probe `findings.md` 2026-08-23）。
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('lending.refresh')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('lending.cancel.begin')),
          )
          .onPressed,
      isNull,
      reason: '出口は下部バーの［解除］1本である',
    );
    // 0件でも確定ボタンは出る。押せないだけである。
    expect(find.text('対象を選択'), findsOneWidget);

    await tapRow(tester, const ValueKey('lending.cancel.dismiss'));
    expect(container.read(lendingSelectionProvider).active, isFalse);
    expect(find.byKey(const ValueKey('lending.cancel.commit')), findsNothing);
  });

  testWidgets('選んだ行をまとめて取消済みにする。行は位置に残る', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final state = container.read(lendingProvider);
    final reserved = [
      for (final id in state.order)
        if (state.rows[id]!.systemId == 'Tokyo_Koto' &&
            state.rows[id]!.status == 'reserved')
          id,
    ];
    final first = reserved[0];
    final second = reserved[1];

    await tapRow(tester, const ValueKey('lending.cancel.begin'));
    await tapRow(tester, ValueKey('lending.select.$first'));
    await tapRow(tester, ValueKey('lending.select.$second'));
    expect(find.text('取消済み 2件にする'), findsOneWidget);

    await tapRow(tester, const ValueKey('lending.cancel.commit'));

    for (final loanId in [first, second]) {
      expect(
        container.read(lendingProvider).statusOf(loanId),
        equals('cancelled'),
        reason: loanId,
      );
      // **終端にしても位置に残る**（`lending.md` §3）。返却と同じ扱いである。
      expect(find.byKey(ValueKey('lending.row.$loanId')), findsOneWidget);
    }
    expect(find.text('↻ 更新 (2)'), findsOneWidget);
    expect(
      container.read(lendingSelectionProvider).active,
      isFalse,
      reason: '確定したら選択モードから出る',
    );

    await tapRow(tester, const ValueKey('lending.refresh'));
    expect(find.byKey(ValueKey('lending.row.$first')), findsNothing);
    expect(find.byKey(ValueKey('lending.row.$second')), findsNothing);
  });

  testWidgets('終端にした行にはチェックボックスが出ない', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final done = loanIn(container, 'Tokyo_Koto', 'borrowed');
    final live = loanIn(container, 'Tokyo_Koto', 'reserved');
    await tapRow(tester, ValueKey('lending.return.$done'));

    await tapRow(tester, const ValueKey('lending.cancel.begin'));
    expect(find.byKey(ValueKey('lending.select.$done')), findsNothing);
    expect(find.byKey(ValueKey('lending.select.$live')), findsOneWidget);
  });

  testWidgets('選択中は状態と期限を押せない', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'borrowed');
    await tapRow(tester, const ValueKey('lending.cancel.begin'));

    await tester.scrollUntilVisible(
      find.byKey(ValueKey('lending.row.$target')),
      200,
    );
    for (final key in ['lending.borrow', 'lending.return', 'lending.date']) {
      expect(
        tester
            .widget<OutlinedButton>(
              find.descendant(
                of: find.byKey(ValueKey('$key.$target')),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
        reason: key,
      );
    }
  });

  /// **追加は台帳に在る書誌からである**（`lending.md` §5・§6）。江戸川は期限切れの1件だけを
  /// 持つ区で、生きた記録が無い＝一覧が空の区でも足せることを兼ねて見る。
  testWidgets('［台帳から追加］で台帳の書誌を予約中として足す', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Edogawa');
    expect(
      container
          .read(lendingProvider)
          .sectionOf('Tokyo_Edogawa', LendingSection.reserved),
      isEmpty,
    );

    await tapRow(tester, const ValueKey('lending.add.open'));
    expect(find.byKey(const ValueKey('lending.add.dialog')), findsOneWidget);
    // **受取館は選ばせない。** 常用館を読み取り専用で出すだけである（§5）。
    expect(find.textContaining('（常用館）'), findsOneWidget);

    final book = container
        .read(lendingAddCandidatesProvider('Tokyo_Edogawa'))
        .first;
    await tester.tap(find.byKey(ValueKey('lending.add.book.${book.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lending.add.commit')));
    await tester.pumpAndSettle();

    final added = container
        .read(lendingProvider)
        .sectionOf('Tokyo_Edogawa', LendingSection.reserved);
    expect(added, hasLength(1));
    final row = container.read(lendingProvider).rows[added.single]!;
    expect(row.status, equals('reserved'));
    expect(row.bookId, equals(book.id));
    expect(row.pickupLibraryId, isNotNull, reason: '受取館は常用館から決まる');
    expect(find.byKey(ValueKey('lending.row.${added.single}')), findsOneWidget);
  });

  testWidgets('追加の候補に、この地区で生きている本は出ない', (tester) async {
    final container = await pump(tester);
    final live = container
        .read(lendingProvider)
        .rows[loanIn(container, 'Tokyo_Katsushika', 'reserved')]!;
    final candidates = container.read(
      lendingAddCandidatesProvider('Tokyo_Katsushika'),
    );
    expect(candidates.map((book) => book.id), isNot(contains(live.bookId)));
    // **別の区では候補に戻る。** 除外はこの区の記録だけを見る。
    expect(
      container
          .read(lendingAddCandidatesProvider('Tokyo_Edogawa'))
          .map((book) => book.id),
      contains(live.bookId),
    );
  });

  /// `lending.md` §4「常用館が未設定のシステムでは予約を記録できない」。**保存まで進ませず、
  /// 本を選ばせる前に止める。** 墨田だけが未設定の区である（デモ fixture）。
  testWidgets('常用館が決まっていない区では、追加の前に図書館管理へ渡す', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Sumida');
    await tapRow(tester, const ValueKey('lending.add.open'));

    expect(find.byKey(const ValueKey('lending.add.dialog')), findsNothing);
    expect(find.byKey(const ValueKey('lending.add.preferred')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lending.add.preferred.open')));
    await tester.pumpAndSettle();
    expect(container.read(currentTabProvider), equals(ShellTab.settings));
    expect(
      container.read(librariesRouteProvider),
      equals(const LibrariesRouteState.preferredBranch('Tokyo_Sumida')),
    );

    // 直して閉じると、これまでどおり元の区へ帰る。
    container.read(librariesRouteProvider.notifier).back();
    await tester.pumpAndSettle();
    expect(
      container.read(lendingRouteProvider),
      equals(const LendingRouteState.area('Tokyo_Sumida')),
    );
  });

  testWidgets('**書影と書名から本棚の記録へ渡す。** 貸出しの記録は変えない', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final loanId = loanIn(container, 'Tokyo_Koto', 'borrowed');
    final bookId = container.read(lendingProvider).rows[loanId]!.bookId;
    final before = container.read(lendingProvider).statusOf(loanId);

    final link = find.byKey(ValueKey('lending.record.$bookId'));
    await tester.scrollUntilVisible(link.first, 200);
    await tester.tap(link.first);
    await tester.pumpAndSettle();

    // 本棚タブへ移り、開く本が伝わっている。閉じたらこの区へ帰る。
    expect(container.read(currentTabProvider), equals(ShellTab.bookshelf));
    expect(container.read(shelfReturnProvider), equals(ShellTab.lending));
    // **貸出しの記録は動かない。** 押しても読むだけである。
    expect(container.read(lendingProvider).statusOf(loanId), before);
  });

  testWidgets('返却済みの行にだけレビューの入口が出る。押すと本棚へ渡り、帰り先を覚える', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final loanId = loanIn(container, 'Tokyo_Koto', 'borrowed');
    final review = find.byKey(ValueKey('lending.review.$loanId'));
    expect(review, findsNothing, reason: '返却済みにするまでは出さない');

    await tapRow(tester, ValueKey('lending.return.$loanId'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(review, 200);
    await tester.tap(review);
    await tester.pumpAndSettle();

    expect(container.read(currentTabProvider), equals(ShellTab.bookshelf));
    expect(container.read(shelfReturnProvider), equals(ShellTab.lending));
  });

  testWidgets('取消を選んでいる最中は本棚へ渡さない', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final loanId = loanIn(container, 'Tokyo_Koto', 'borrowed');
    final bookId = container.read(lendingProvider).rows[loanId]!.bookId;

    container.read(lendingSelectionProvider.notifier).begin();
    await tester.pumpAndSettle();
    // **選んでいる途中で画面が変わると、選択が消える。**
    expect(find.byKey(ValueKey('lending.record.$bookId')), findsNothing);
    expect(container.read(currentTabProvider), equals(ShellTab.lending));
  });

  testWidgets('台帳から消えたシステムでは追加を出さない。取消はできる', (tester) async {
    await app.removeLibrarySystem('Tokyo_Koto');
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');

    expect(
      find.byKey(const ValueKey('lending.add.open')),
      findsNothing,
      reason: '常用館を設定しに行く先が無い',
    );
    await tapRow(tester, const ValueKey('lending.cancel.begin'));
    expect(container.read(lendingSelectionProvider).active, isTrue);
    expect(find.byKey(const ValueKey('lending.cancel.commit')), findsOneWidget);
  });

  testWidgets('区を出ると選択は消える', (tester) async {
    final container = await pump(tester);
    await openArea(tester, 'Tokyo_Koto');
    final target = loanIn(container, 'Tokyo_Koto', 'reserved');
    await tapRow(tester, const ValueKey('lending.cancel.begin'));
    await tapRow(tester, ValueKey('lending.select.$target'));
    expect(container.read(lendingSelectionProvider).count, equals(1));

    await tapRow(tester, const ValueKey('lending.back'));
    expect(container.read(lendingSelectionProvider).active, isFalse);
    expect(container.read(lendingSelectionProvider).count, isZero);
  });

  /// 実描画の確認用画像（指定時だけ保存）。**通常の試験では走らない。**
  ///
  /// 図書館管理の `view_test.dart` と同じ仕掛けである。行の詰まり具合・選択中の濃さ・
  /// 横幅の余りは、数値で測るより目で見たほうが早い。
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('実描画の確認用画像・${brightness.name}（指定時だけ保存）', (tester) async {
      final output = Platform.environment['KARITA_TEST_RENDER'];
      if (output == null) return;
      final font = FontLoader(_renderFamily)
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/meiryo.ttc').readAsBytesSync(),
            ),
          ),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                'C:/flutter/bin/cache/artifacts/material_fonts/'
                'MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();

      await tester.binding.setSurfaceSize(const Size(700, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer(
        overrides: [compositionProvider.overrideWithValue(app)],
      );
      addTearDown(container.dispose);
      container.read(lendingProvider);
      container.read(currentTabProvider.notifier).select(ShellTab.lending);
      final base = karitaTheme(brightness);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: base.copyWith(
              textTheme: base.textTheme.apply(fontFamily: _renderFamily),
            ),
            // **[RepaintBoundary] を [Navigator] より上へ置く**（2026-09-20）。`home` の
            // 中に置くとダイアログが写らない — 追加ダイアログは Navigator に積まれる。
            builder: (context, child) =>
                RepaintBoundary(key: const ValueKey('screen'), child: child),
            home: const Scaffold(body: LendingView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      /// **2枚とも出す**（2026-09-20）。初期画面のサマリはバッジと期限の桁が揃っているか、
      /// 詳細は書影と中身の釣り合いが見どころで、どちらも目で見ないと分からない。
      Future<void> shoot(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('screen')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output/lending-$name-${brightness.name}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await shoot('overview');
      container.read(lendingRouteProvider.notifier).openArea('Tokyo_Koto');
      await tester.pumpAndSettle();
      await shoot('area');

      // **下部バーの2枚も出す**（2026-09-20）。チェックボックスの列が行の右へ入った
      // ときの詰まり具合と、確定ボタンの文言の収まりは目で見ないと分からない。
      container.read(lendingSelectionProvider.notifier).begin();
      await tester.pumpAndSettle();
      await shoot('select');
      container.read(lendingSelectionProvider.notifier).end();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lending.add.open')));
      await tester.pumpAndSettle();
      await shoot('add');
    });
  }
}

/// デモの台帳に対する「受取と返却間近」の実数。**基準日は実行日である。**
int _soonCount(Composition app) {
  final end = soonLimitOn(localToday());
  return app
      .loadActiveLoans()
      .where((item) => isPickupOrDueSoon(item, end))
      .length;
}

/// 実描画に日本語と Material のアイコンを載せる名前。**通常の試験では読み込まない。**
const String _renderFamily = 'LendingRender';
