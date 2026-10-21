/// 本棚の蔵書表示。**押したときだけ照会し、混ぜてはいけない状態を混ぜない。**
///
/// 分割・間欠・中止の試験は `karita_app/test/holdings_lookup_test.dart`、集約規則は
/// `karita_public_api_client/test/holdings_summary_test.dart` にある。**ここで見るのは画面**で、
/// いつ出るか・どの語が出るか・使えない端末でも本棚が動くか。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:karita_ui/karita_ui.dart';

const String _isbn = '9784274219337';
final DateTime _now = DateTime(2026, 9, 21, 15, 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;
  late String wantedId;

  /// 外へ出した照会の数。**押していないのに出ていないことを見る。**
  late List<Uri> starts;
  var statusCode = 200;
  var libkey = <String, String>{'豊洲': '貸出可'};

  /// 応答に現れない館を作る。**部分結果の枝である。**
  var answerSystems = true;

  /// 進められる時計。**上限の10分を越えさせるために要る。**
  var now = _now;

  HoldingsLookup makeLookup() => HoldingsLookup(
    CalilCheckClient(
      appkey: 'test-key',
      now: () => now,
      delay: (_) async {},
      httpClient: MockClient((request) async {
        final isbn = request.url.queryParameters['isbn'];
        if (isbn == null) {
          return http.Response(
            jsonEncode({'session': 's', 'continue': 0, 'books': {}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        starts.add(request.url);
        if (statusCode != 200) return http.Response('', statusCode);
        final requested = request.url.queryParameters['systemid']!.split(',');
        return http.Response(
          jsonEncode({
            'session': 's',
            'continue': 0,
            'books': {
              for (final one in isbn.split(','))
                one: {
                  if (answerSystems)
                    for (final system in requested)
                      system: {'status': 'OK', 'libkey': libkey},
                },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
    now: () => now,
    delay: (_) async {},
  );

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    home = Directory.systemTemp.createTempSync('karita-shelf-holdings-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
    starts = [];
    statusCode = 200;
    libkey = {'豊洲': '貸出可'};
    answerSystems = true;
    now = _now;
    // 読みたての本を1冊。**ISBNが在るので照会の対象になる。**
    wantedId = app.reservationBookId(_isbn);
    app.saveReservation(
      book: ReservationBook(
        id: wantedId,
        isbn13: _isbn,
        title: '読みたい本',
        authors: const ['著者'],
      ),
      operationId: app.newReservationId(),
      systems: [],
      wanted: true,
    );
  });

  tearDown(() {
    app.close();
    home.deleteSync(recursive: true);
  });

  /// [lookup] に `null` を渡すと「照会できない端末」になる。
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    HoldingsLookup? lookup,
    bool usable = true,
    Size size = const Size(480, 1000),
    double scale = 1,
    Density? density,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final resolved = usable ? (lookup ?? makeLookup()) : null;
    if (resolved != null) addTearDown(resolved.close);
    final c = ProviderContainer(
      overrides: [
        compositionProvider.overrideWithValue(app),
        if (density != null) densityProvider.overrideWithValue(density),
        holdingsLookupProvider.overrideWithValue(resolved),
      ],
    );
    addTearDown(c.dispose);
    c.read(currentTabProvider.notifier).select(ShellTab.bookshelf);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(body: BookshelfView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  Finder line(String id) => find.byKey(ValueKey('shelf.holdings.$id'));
  Finder detail(String id) => find.byKey(ValueKey('shelf.holdings.detail.$id'));

  /// バッジの語。**行の右端の丸バッジ。**
  String? badgeText(WidgetTester tester, String id) => tester
      .widget<Text>(find.descendant(of: line(id), matching: find.byType(Text)))
      .data;

  /// バッジに添える細かい分。**無ければ `null`。**
  String? detailText(WidgetTester tester, String id) =>
      detail(id).evaluate().isEmpty
      ? null
      : tester.widget<Text>(detail(id)).data;

  /// バッジを押せるか。**押せないものはカーリルへ行かない。**
  bool badgeLinked(WidgetTester tester, String id) =>
      tester.widget<TextButton>(line(id)).onPressed != null;

  /// バッジの地の色。
  Color? badgeColor(WidgetTester tester, String id) => tester
      .widget<TextButton>(line(id))
      .style
      ?.backgroundColor
      ?.resolve(<WidgetState>{});
  final button = find.byKey(const ValueKey('shelf.holdings.check'));

  Future<void> check(WidgetTester tester) async {
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 360.0, 411.0, 900.0]) {
    testWidgets('header actions fit one row at width $width', (tester) async {
      await pump(
        tester,
        size: Size(width, 1000),
        density: const Density(PointerKind.touch),
      );
      final add = tester.getRect(find.byKey(const ValueKey('shelf.add')));
      final holdings = tester.getRect(button);
      final export = tester.getRect(find.byKey(const ValueKey('shelf.export')));
      expect(holdings.left, greaterThanOrEqualTo(add.right));
      expect(export.left, greaterThanOrEqualTo(holdings.right));
      expect(holdings.center.dy, closeTo(add.center.dy, 1));
      expect(export.center.dy, closeTo(add.center.dy, 1));
      expect(export.right, lessThanOrEqualTo(width));
      for (final rect in [add, holdings, export]) {
        expect(rect.height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
    });
  }

  group('始める契機', () {
    testWidgets('**描画では照会しない。** 押す前の行に蔵書の語は出ない', (tester) async {
      await pump(tester);
      expect(starts, isEmpty, reason: '一覧を描いただけでは外へ出ない');
      expect(button, findsOneWidget);
      // **押す前は「蔵書未確認」で、押せない。** 蔵書なしとは混ざらない。
      expect(badgeText(tester, wantedId), '蔵書未確認');
      expect(badgeLinked(tester, wantedId), isFalse);
      expect(find.text('蔵書なし'), findsNothing);
    });

    testWidgets('押すと読みたての行に語と確認時刻が出る', (tester) async {
      await pump(tester);
      await check(tester);
      expect(starts, isNotEmpty, reason: '押したら外へ出る');
      // **バッジそのものがリンクである。** 2行に分けない。
      expect(badgeText(tester, wantedId), '蔵書あり ›');
      expect(badgeLinked(tester, wantedId), isTrue);
      // **確認時刻は出さない。** 5分で期限が切れるので、出ているものは必ず新しい。
      expect(detailText(tester, wantedId), isNull);
    });

    testWidgets('**押し直しても描画では増えない。** 再描画で照会は始まらない', (tester) async {
      await pump(tester);
      await check(tester);
      final sent = starts.length;
      expect(sent, greaterThan(0));
      // 検索欄を触って一覧を組み直す。**照会は増えない。**
      await tester.enterText(find.byKey(const ValueKey('shelf.search')), '読み');
      await tester.pumpAndSettle();
      expect(starts, hasLength(sent));
    });

    testWidgets('本棚タブを離れたら止める', (tester) async {
      final c = await pump(tester);
      await check(tester);
      c.read(currentTabProvider.notifier).select(ShellTab.reserve);
      await tester.pumpAndSettle();
      expect(c.read(shelfHoldingsProvider).running, isFalse);
    });
  });

  group('並び順', () {
    testWidgets('**読みたいを先に、読んだを後に出す**', (tester) async {
      await pump(tester);
      final rows = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.key)
          .whereType<ValueKey<String>>()
          .map((k) => k.value)
          .where((v) => v.startsWith('shelf.row.'))
          .toList();
      final states = <String>[];
      for (final key in rows) {
        final id = key.substring('shelf.row.'.length);
        final open = find.byKey(ValueKey('shelf.open.$id'));
        states.add(
          tester
              .widget<Text>(
                find.descendant(of: open, matching: find.byType(Text)),
              )
              .data!,
        );
      }
      expect(states, isNotEmpty);
      final firstRead = states.indexWhere((s) => s.startsWith('読んだ'));
      final lastWanted = states.lastIndexWhere((s) => s.startsWith('読みたい'));
      if (firstRead >= 0 && lastWanted >= 0) {
        expect(lastWanted, lessThan(firstRead), reason: '読みたてが全部、読んだより前に出ること');
      }
    });
  });

  group('混ぜない', () {
    testWidgets('ISBNなしは照会不可であって蔵書なしではない', (tester) async {
      final noIsbn = app.reservationBookId(null);
      app.saveReservation(
        book: ReservationBook(id: noIsbn, title: 'ISBNなしの本', authors: const []),
        operationId: app.newReservationId(),
        systems: [],
        wanted: true,
      );
      await pump(tester);
      // **この1冊まで絞ってから見る。** 一覧の並びは本棚変更の新しい順で、秒が同じなら
      // bookId で決まる。fixture と同じ秒に入ると位置が変わり、`ListView` が行を組まない。
      await tester.enterText(
        find.byKey(const ValueKey('shelf.search')),
        'ISBNなしの本',
      );
      await tester.pumpAndSettle();
      await check(tester);
      expect(badgeText(tester, noIsbn), '照会不可');
      expect(badgeLinked(tester, noIsbn), isFalse, reason: 'リンクを作れない');
      expect(detailText(tester, noIsbn), 'ISBNなし');
      expect(find.text('蔵書なし'), findsNothing);
    });

    testWidgets('応答に現れない館が在れば、全館確認済みに見せない', (tester) async {
      answerSystems = false;
      await pump(tester);
      await check(tester);
      // 誰も答えていないので確認中。**蔵書なしにしない。**
      // **確認中でもカーリルへ行ける。** こちらが答えを持っていないときこそ見たい。
      expect(badgeText(tester, wantedId), '確認中 ›');
      expect(badgeLinked(tester, wantedId), isTrue);
      expect(find.text('蔵書なし'), findsNothing);
    });

    // **1件につき1回だけ組む。** 同じ試験で何度も組み直すと、捨てた容れ物の破棄の予約が
    // タイマーとして残り、終わりで `!timersPending` に当たる。
    for (final row in const [
      ('貸出中', '貸出し中 ›'),
      ('予約中', '準備中 ›'),
      ('準備中', '準備中 ›'),
      ('館内のみ', '貸出し不可 ›'),
      ('休館中', '貸出し不可 ›'),
      ('不明', '貸出し不可 ›'),
      // **知らない値は不明と同じに置く。** 借りられる側へ寄せない。
      ('取次中', '貸出し不可 ›'),
    ]) {
      testWidgets('libkey の ${row.$1} は「${row.$2}」になる', (tester) async {
        libkey = {'豊洲': row.$1};
        await pump(tester);
        await check(tester);
        expect(badgeText(tester, wantedId), row.$2);
        // **どれもカーリルへ行ける。** 実サイトで確かめられるようにする。
        expect(badgeLinked(tester, wantedId), isTrue);
      });
    }

    testWidgets('全館が答えて所蔵が無いときだけ蔵書なしを出す', (tester) async {
      libkey = {};
      await pump(tester);
      await check(tester);
      expect(badgeText(tester, wantedId), '蔵書なし ›');
      // **蔵書なしでもリンクを隠さない**（正本）。
      expect(badgeLinked(tester, wantedId), isTrue);
    });
  });

  group('上限に達したとき', () {
    testWidgets('案内はボタンの位置に出し、行は時間をおく語にする', (tester) async {
      statusCode = 429;
      await pump(tester);
      await check(tester);
      expect(
        find.byKey(const ValueKey('shelf.holdings.notice')),
        findsOneWidget,
      );
      expect(find.text('照会の上限に達しました。時間をおいてください。'), findsOneWidget);
      // **行では上限を繰り返さない。** 時間をおく案内はボタンの位置に1つ出る。
      expect(badgeText(tester, wantedId), '確認できません ›');
      expect(badgeLinked(tester, wantedId), isTrue);
    });

    testWidgets('**10分たって押し直したら、前の案内は消える**', (tester) async {
      statusCode = 429;
      await pump(tester);
      await check(tester);
      expect(find.text('照会の上限に達しました。時間をおいてください。'), findsOneWidget);

      // 10分待った端末。**押せるようになり、前の案内は残らない。**
      final stopped = starts.length;
      now = now.add(holdingsRateLimitedTtl);
      statusCode = 200;
      await check(tester);
      expect(find.text('照会の上限に達しました。時間をおいてください。'), findsNothing);
      expect(starts.length, greaterThan(stopped), reason: '今度は外へ出る');
      expect(badgeText(tester, wantedId), '蔵書あり ›');
    });

    testWidgets('**押し直しても外へ出さない。** 尽きた枠をさらに削らない', (tester) async {
      statusCode = 429;
      await pump(tester);
      await check(tester);
      // **上限を受けたら残りの塊をやめる。** 続けても全部落ちる。
      expect(starts, hasLength(1), reason: '1塊目で打ち切る');
      statusCode = 200;
      await check(tester);
      expect(starts, hasLength(1), reason: '10分は外へ出ない');
    });
  });

  group('読みやすさ', () {
    testWidgets('狭幅・文字拡大で横にはみ出さない', (tester) async {
      // 上限の案内がいちばん長い。**ボタンと同じ行に並ぶので、折り返せることを見る。**
      statusCode = 429;
      await pump(tester, size: const Size(360, 900), scale: 1.6);
      await check(tester);
      expect(tester.takeException(), isNull);
      for (final box in tester.renderObjectList<RenderBox>(find.byType(Text))) {
        expect(box.size.width, lessThanOrEqualTo(360));
      }
    });
  });

  group('押した結果が必ず返る', () {
    testWidgets('**想定外の失敗でも「確認中」のまま残さない**', (tester) async {
      // 閉じた口を渡す。`check` が `StateError` を投げる経路である。
      final closed = makeLookup()..close();
      final c = await pump(tester, lookup: closed);
      await check(tester);
      expect(c.read(shelfHoldingsProvider).running, isFalse);
      expect(find.text('蔵書を確認できませんでした。'), findsOneWidget);
      // 押し直せること。**壊れたボタンにしない。**
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    });
  });

  group('使えない端末', () {
    testWidgets('**本棚・検索はそのまま動く。** 理由はボタンの位置に出す', (tester) async {
      await pump(tester, usable: false);
      expect(find.text('蔵書照会を利用できません。'), findsOneWidget);
      expect(button, findsNothing);
      // 一覧と検索は生きている。
      expect(find.byKey(ValueKey('shelf.row.$wantedId')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('shelf.search')), '読み');
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('shelf.row.$wantedId')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('shelf.search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('条件に一致する本がありません。'), findsOneWidget);
      // 行に蔵書の語を出さない。**「蔵書なし」に化けない。**
      expect(find.text('蔵書なし'), findsNothing);
    });
  });

  group('語の組み立て', () {
    test('未確認の館は肯定の結果に併記する。**バッジは短い語だけ**', () {
      final summary = summarizeHoldings(
        requestedSystemIds: const ['A', 'B', 'C'],
        holdings: const [
          SystemHolding(
            systemId: 'A',
            status: 'OK',
            libkeyStatuses: {'豊洲': '貸出可'},
          ),
        ],
        observedAt: _now,
      );
      expect(shelfHoldingsBadge(summary), '蔵書あり');
      // **確認時刻は出さない。** 未確認館だけを添える。
      expect(shelfHoldingsDetail(summary), '2館未確認');
    });

    test('確認中と確認できませんに確認時刻を付けない', () {
      final running = summarizeHoldings(
        requestedSystemIds: const ['A'],
        holdings: const [SystemHolding(systemId: 'A', status: 'Running')],
        observedAt: _now,
      );
      expect(shelfHoldingsBadge(running), '確認中');
      expect(shelfHoldingsDetail(running), '');

      final failed = summarizeHoldings(
        requestedSystemIds: const ['A'],
        holdings: const [],
        observedAt: _now,
        failure: ApiFailure.network,
      );
      expect(shelfHoldingsBadge(failed), '確認できません');
      expect(shelfHoldingsDetail(failed), '');
    });

    test('**未照会・登録館なし・キーなしは「蔵書未確認」。** 押せない', () {
      for (final summary in const [
        HoldingsSummary.notRequested,
        HoldingsSummary.noLibrary,
        HoldingsSummary.keyMissing,
      ]) {
        expect(shelfHoldingsBadge(summary), '蔵書未確認');
        expect(shelfHoldingsLinked(summary), isFalse);
      }
    });

    test('**蔵書未確認と照会不可の2つだけがカーリルへ行かない**', () {
      for (final state in const [
        HoldingsState.notRequested,
        HoldingsState.noLibrary,
        HoldingsState.keyMissing,
        // こちらは押せないのではなく、行き先が作れない。
        HoldingsState.noIsbn,
      ]) {
        expect(
          shelfHoldingsLinked(HoldingsSummary(state: state)),
          isFalse,
          reason: state.name,
        );
      }
      // **残りは全部開ける。** 確認中・確認できませんも含む。
      for (final state in const [
        HoldingsState.available,
        HoldingsState.borrowed,
        HoldingsState.preparing,
        HoldingsState.restricted,
        HoldingsState.absent,
        HoldingsState.checking,
        HoldingsState.failed,
        HoldingsState.rateLimited,
      ]) {
        expect(
          shelfHoldingsLinked(HoldingsSummary(state: state)),
          isTrue,
          reason: state.name,
        );
      }
    });
  });

  group('バッジの見た目', () {
    ColorScheme schemeOf(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(BookshelfView))).colorScheme;

    testWidgets('**蔵書ありだけを主色で塗る。** 借りられる見込みで色を分ける', (tester) async {
      await pump(tester);
      await check(tester);
      expect(badgeColor(tester, wantedId), schemeOf(tester).primary);
    });

    testWidgets('貸出し中は琥珀にする', (tester) async {
      libkey = {'豊洲': '貸出中'};
      await pump(tester);
      await check(tester);
      final tone = karitaBorrowedTone(
        Theme.of(tester.element(find.byType(BookshelfView))).brightness,
      );
      expect(badgeColor(tester, wantedId), tone.background);
      expect(tone.background, isNot(schemeOf(tester).primary));
    });

    testWidgets('準備中は水色にする。**貸出し中と分ける**', (tester) async {
      libkey = {'豊洲': '準備中'};
      await pump(tester);
      await check(tester);
      final brightness = Theme.of(
        tester.element(find.byType(BookshelfView)),
      ).brightness;
      final tone = karitaPreparingTone(brightness);
      expect(badgeColor(tester, wantedId), tone.background);
      expect(tone.background, isNot(karitaBorrowedTone(brightness).background));
      expect(tone.background, isNot(schemeOf(tester).primary));
    });

    testWidgets('蔵書なし・貸出し不可・未確認は地に近い灰にする', (tester) async {
      libkey = {};
      await pump(tester);
      await check(tester);
      expect(badgeColor(tester, wantedId), schemeOf(tester).surface);
    });

    testWidgets('狭い画面でも書影を残し、状態のタップ領域を保つ', (tester) async {
      await pump(tester, size: const Size(320, 900));
      // 狭い行は2段に逃がすので、fixture の行に押し出されないよう1冊に絞る。
      await tester.enterText(
        find.byKey(const ValueKey('shelf.search')),
        '読みたい本',
      );
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey('shelf.row.$wantedId'));
      expect(
        find.descendant(of: row, matching: find.byType(BookCoverView)),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(ValueKey('shelf.open.$wantedId'))).height,
        greaterThanOrEqualTo(32),
      );
      final holdings = find.byKey(ValueKey('shelf.holdings.$wantedId'));
      expect(
        tester.getTopRight(holdings).dx,
        closeTo(tester.getTopRight(row).dx, 1),
        reason: 'Android の狭い行でも蔵書表示は右端に置く',
      );
    });

    testWidgets('広い行でも蔵書表示を右端に置く', (tester) async {
      await pump(tester, size: const Size(640, 900));
      final row = find.byKey(ValueKey('shelf.row.$wantedId'));
      final holdings = find.byKey(ValueKey('shelf.holdings.$wantedId'));
      // 書名の右に Amazon を置いて行が伸び、この行が最初の画面から外れることがある。
      await tester.scrollUntilVisible(
        holdings,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        tester.getTopRight(holdings).dx,
        closeTo(tester.getTopRight(row).dx, 1),
      );
    });

    testWidgets('ISBNのない本は押せない', (tester) async {
      final noIsbn = app.reservationBookId(null);
      app.saveReservation(
        book: ReservationBook(id: noIsbn, title: 'ISBNなしの本', authors: const []),
        operationId: app.newReservationId(),
        systems: [],
        wanted: true,
      );
      await pump(tester);
      // fixture の進行中の本も読みたいに並ぶので、この1冊まで絞ってから見る
      // （`ListView` は見える行しか組まない）。
      await tester.enterText(
        find.byKey(const ValueKey('shelf.search')),
        'ISBNなしの本',
      );
      await tester.pumpAndSettle();
      expect(badgeLinked(tester, noIsbn), isFalse);
    });
  });

  testWidgets('実描画の確認用画像（指定時だけ保存）', (tester) async {
    final output = Platform.environment['KARITA_TEST_RENDER'];
    if (output == null) return;
    for (final family in ['sans-serif', 'ShelfRender']) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                File('C:/Windows/Fonts/meiryo.ttc').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                'C:/flutter/bin/cache/artifacts/material_fonts/'
                'MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();

    // 状態を撮り分けるための本を足す。**どれも読みたてである。**
    void wanted(String? isbn, String title) {
      final id = app.reservationBookId(isbn);
      app.saveReservation(
        book: ReservationBook(
          id: id,
          isbn13: isbn,
          title: title,
          authors: const ['著者'],
        ),
        operationId: app.newReservationId(),
        systems: [],
        wanted: true,
      );
    }

    wanted(null, 'ISBNのない本');

    Future<void> shoot(String name) async {
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File(
          '$output/bookshelf-holdings-$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    // **1枚撮るごとに前の容れ物を捨てる。** 4つ抱えたまま終わると、Riverpod の破棄の予約が
    // タイマーとして残り、終わりで `!timersPending` に当たる。
    ProviderContainer? open_;
    Future<void> open({required bool usable}) async {
      await tester.binding.setSurfaceSize(const Size(480, 1000));
      open_?.dispose();
      // 予約された破棄をここで流す。
      if (open_ != null) await tester.pump();
      final resolved = usable ? makeLookup() : null;
      if (resolved != null) addTearDown(resolved.close);
      final c = ProviderContainer(
        overrides: [
          compositionProvider.overrideWithValue(app),
          holdingsLookupProvider.overrideWithValue(resolved),
        ],
      );
      open_ = c;
      c.read(currentTabProvider.notifier).select(ShellTab.bookshelf);
      final theme = karitaTheme(Brightness.dark);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'ShelfRender'),
            ),
            builder: (context, child) =>
                RepaintBoundary(key: const ValueKey('capture'), child: child),
            home: const Scaffold(body: BookshelfView()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // 1. 押す前。**行に蔵書の語が無い。**
    await open(usable: true);
    await shoot('before');

    // 2. 押した後。貸出可・蔵書なし・照会不可が並ぶ。
    await check(tester);
    await shoot('checked');

    // 2b. 読んだの札（紫）。**読みたいの緑と分かれていること。**
    await tester.tap(find.text('読んだ'));
    await shoot('read-filter');
    await tester.tap(find.text('全件'));
    await tester.pumpAndSettle();

    // 3. 貸出し中（琥珀）。
    libkey = {'豊洲': '貸出中'};
    await open(usable: true);
    await check(tester);
    await shoot('borrowed');

    // 4. 準備中（水色）。
    libkey = {'豊洲': '準備中'};
    await open(usable: true);
    await check(tester);
    await shoot('preparing');

    // 5. 貸出し不可（灰）。
    libkey = {'豊洲': '館内のみ'};
    await open(usable: true);
    await check(tester);
    await shoot('restricted');

    // 4. 上限に達したとき。案内はボタンの位置に出る。
    statusCode = 429;
    await open(usable: true);
    await check(tester);
    await shoot('rate-limited');

    // 5. 照会できない端末。**本棚はそのまま出る。**
    await open(usable: false);
    await shoot('unusable');

    open_?.dispose();
    open_ = null;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // **書影の取得の期限を過ぎさせる。** 撮るだけの試験なので書影は要らないが、`BookLookup`
    // が openBD へ出した要求の期限（10〜15秒）が残っていると、終わりで
    // `!timersPending` に当たる。
    await tester.pump(const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
  });
}
