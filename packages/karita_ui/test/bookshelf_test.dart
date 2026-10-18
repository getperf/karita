import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;
  late String id;
  late List<Uri> opened;
  setUp(() async {
    opened = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    home = Directory.systemTemp.createTempSync('karita-shelf-ui-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
      // 実ブラウザーを起こさない。
      openBrowser: (url) async => opened.add(url),
    );
    id = app.reservationBookId(null);
    app.saveReservation(
      book: ReservationBook(id: id, title: 'ＡＢＣ ｶﾞｲﾄﾞの本', authors: ['著者']),
      operationId: app.newReservationId(),
      systems: [],
      wanted: true,
    );
  });
  tearDown(() {
    app.close();
    home.deleteSync(recursive: true);
  });
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Size size = const Size(480, 1000),
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(app)],
    );
    addTearDown(c.dispose);
    c.read(currentTabProvider.notifier).select(ShellTab.bookshelf);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: ThemeData.dark(),
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

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  test('search uses NFKC; valid 978 only generates ISBN10 links', () {
    final b = app.loadBookshelf(bookId: id).single;
    expect(shelfMatches(b, 'abc ガイド'), isTrue);
    expect(shelfMatches(b, '著者'), isTrue);
    const withIsbn = ShelfBook(
      id: 'x',
      title: '吾輩は猫である',
      authors: ['夏目,漱石,1867-1916'],
      isbn13: '9784101010014',
      state: 'read',
      changedAt: '',
      reason: '手動登録',
      histories: [],
      activeStatuses: [],
      rating: null,
      review: '',
      reviewRevision: '',
    );
    expect(shelfMatches(withIsbn, '夏目'), isTrue);
    expect(shelfMatches(withIsbn, '978-4-10-101001-4'), isTrue);
    // 全角で入れたISBNもNFKCで一致する。
    expect(shelfMatches(withIsbn, '９７８４１０１０１０　'), isTrue);
    expect(shelfMatches(withIsbn, '森鴎外'), isFalse);
    expect(shelfCalilUrl('9784274224546')?.path, '/book/4274224546');
    expect(shelfCalilUrl('9784274224547'), isNull);
    expect(shelfCalilUrl(null), isNull);
    expect(shelfCalilUrl('9791234567896'), isNull);
    // Amazon は 978 を商品ページ、979 を ISBN13 の検索にする。ISBN が無ければ作らない。
    expect(
      shelfAmazonUrl('9784274224546').toString(),
      'https://www.amazon.co.jp/dp/4274224546',
    );
    expect(
      shelfAmazonUrl('9784000000086')?.path,
      '/dp/400000008X',
      reason: 'チェック桁10はXになる',
    );
    expect(
      shelfAmazonUrl('9791234567896').toString(),
      'https://www.amazon.co.jp/s?k=9791234567896',
    );
    expect(shelfAmazonUrl('9784274224547'), isNull);
    expect(shelfAmazonUrl(null), isNull);
  });

  testWidgets('［Amazonで見る］は ISBN のある本だけに出て、一覧と記録から開く', (tester) async {
    final withIsbn = app.reservationBookId('9784274224546');
    app.saveReservation(
      book: ReservationBook(
        id: withIsbn,
        title: 'ISBNのある本',
        isbn13: '9784274224546',
      ),
      operationId: app.newReservationId(),
      systems: [],
      wanted: true,
    );
    await pump(tester, size: const Size(367, 1000));
    // `ListView` は見える行しか組まない。2冊だけに絞る。
    await tester.enterText(find.byKey(const ValueKey('shelf.search')), '本');
    await tester.pumpAndSettle();

    // ISBN の無い本には出さない。**書影・書名は押せないまま。**
    expect(find.byKey(ValueKey('shelf.amazon.$id')), findsNothing);
    final inList = find.byKey(ValueKey('shelf.amazon.$withIsbn'));
    expect(inList, findsOneWidget);
    await tap(tester, inList);
    expect(opened.map((u) => u.toString()), [
      'https://www.amazon.co.jp/dp/4274224546',
    ]);
    // 開く前に元の画面を記録する。一覧から出たので本は持たない。
    expect(app.handoff.launch?.purpose, LaunchPurpose.bookshelf);
    expect(app.handoff.launch?.host, 'www.amazon.co.jp');
    expect(app.handoff.launch?.bookId, isNull);

    await tap(tester, find.byKey(ValueKey('shelf.open.$withIsbn')));
    expect(find.text('本の記録'), findsOneWidget);
    final inRecord = find.byKey(ValueKey('shelf.amazon.$withIsbn'));
    // 詳細は横幅いっぱいの形。
    expect(tester.getSize(inRecord).width, greaterThan(300));
    await tap(tester, inRecord);
    expect(opened, hasLength(2));
    expect(app.handoff.launch?.bookId, withIsbn);
    expect(tester.takeException(), isNull);
  });

  testWidgets('組まれる前に置かれた「この本を開く」も拾う（冷えた起動）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(app)],
    );
    addTearDown(c.dispose);
    // 判定が本棚の画面より先に合図を置く。
    c.read(shelfOpenRequestProvider.notifier).open(id);
    c.read(currentTabProvider.notifier).select(ShellTab.bookshelf);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: BookshelfView())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本の記録'), findsOneWidget);
    expect(c.read(shelfOpenRequestProvider), isNull);
  });

  testWidgets('narrow list search, state change and rating-only save', (
    tester,
  ) async {
    await pump(tester, size: const Size(360, 1000), scale: 1.3);
    await tester.enterText(
      find.byKey(const ValueKey('shelf.search')),
      'abc ガイド',
    );
    await tester.pumpAndSettle();
    expect(find.text('1冊'), findsOneWidget);
    await tap(tester, find.byKey(ValueKey('shelf.open.$id')));
    expect(find.text('本の記録'), findsOneWidget);
    await tap(tester, find.text('読んだにする'));
    await tap(tester, find.byTooltip('4点'));
    await tap(tester, find.byKey(const ValueKey('shelf.save')));
    expect(app.loadBookshelf(bookId: id).single.rating, 4);
    // 保存は本棚へ戻し、結果は notice で出す。一覧は右端に評価を出す。
    expect(find.text('1冊'), findsOneWidget);
    expect(find.widgetWithText(SnackBar, 'レビューを保存しました。'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('shelf.rating.$id')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversion commits reach the filter; composing does not', (
    tester,
  ) async {
    await pump(tester);
    final before =
        (find.textContaining('冊').evaluate().single.widget as Text).data!;
    await tester.tap(find.byKey(const ValueKey('shelf.search')));
    await tester.pump();
    // 著者を変換中の間は一覧を作り直さない。
    Future<void> type(String text, {bool committed = false}) async {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: committed
              ? TextRange.empty
              : TextRange(start: 0, end: text.length),
        ),
      );
      await tester.pumpAndSettle();
    }

    // **書名で一意になる語を使う。** fixture の本は 0〜14 がすべて夏目漱石なので、
    // 著者で絞ると件数が本の並びに依存してしまう（2026-09-21。進行中の本を読みたいへ
    // 入れたときに気付いた）。見たいのは変換の確定で絞込みが動くことである。
    await type('吾輩');
    expect(find.text(before), findsOneWidget);
    // 変換の確定は本文を変えないので onChanged は来ない。確定後の本文で絞り込む。
    await type('吾輩', committed: true);
    expect(find.text('1冊'), findsOneWidget);
    expect(find.text('吾輩は猫である'), findsOneWidget);
    // 全角で入れたISBNも確定後に一致する。
    await type('９７８４１０１０１００１４');
    await type('９７８４１０１０１００１４', committed: true);
    expect(find.text('1冊'), findsOneWidget);
    expect(find.text('吾輩は猫である'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('**外から頼まれた本の記録を開く**（貸出しの行からの導線）', (tester) async {
    final c = await pump(tester);
    expect(find.text('本の記録'), findsNothing);

    // 貸出しの行が押されたときと同じ合図を送る。**タブの切替えは `openShelfRecord` が
    // 行うので、ここでは合図だけを置く**（あちらは貸出しの試験が実際のタップで通る）。
    c.read(shelfOpenRequestProvider.notifier).open(id);
    await tester.pumpAndSettle();

    expect(find.text('本の記録'), findsOneWidget);
    // **合図は1回きりである。** 残すと本棚へ戻るたびに同じ本が開く。
    expect(c.read(shelfOpenRequestProvider), isNull);
  });

  testWidgets('貸出しから借りた本の記録は、戻ると貸出しへ帰る', (tester) async {
    final c = await pump(tester);
    c.read(shelfReturnProvider.notifier).set(ShellTab.lending);
    c.read(shelfOpenRequestProvider.notifier).open(id);
    await tester.pumpAndSettle();
    expect(find.text('本の記録'), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('shelf.back')));
    expect(find.text('本の記録'), findsNothing);
    expect(c.read(currentTabProvider), equals(ShellTab.lending));
    expect(c.read(shelfReturnProvider), isNull);
  });

  testWidgets('帰り先が無ければ、戻っても本棚に留まる。別のタブへ移ると帰り先は消える', (tester) async {
    final c = await pump(tester);
    c.read(shelfOpenRequestProvider.notifier).open(id);
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('shelf.back')));
    expect(c.read(currentTabProvider), equals(ShellTab.bookshelf));

    c.read(shelfReturnProvider.notifier).set(ShellTab.lending);
    c.read(currentTabProvider.notifier).select(ShellTab.settings);
    await tester.pumpAndSettle();
    expect(c.read(shelfReturnProvider), isNull);
  });

  testWidgets('removing from the shelf returns to the list with a notice', (
    tester,
  ) async {
    app.setShelfState(id, 'read');
    await pump(tester);
    // **先に絞り込む。** fixture の進行中の本が読みたいに並ぶので（2026-09-21）、
    // 読んだのこの本は `ListView` の見えない位置に居て、行が組まれていない。
    await tester.enterText(
      find.byKey(const ValueKey('shelf.search')),
      'abc ガイド',
    );
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(ValueKey('shelf.open.$id')));
    await tap(tester, find.text('本棚から外す'));
    await tap(tester, find.text('続ける'));
    expect(
      app.loadBookshelf(bookId: id, includeHidden: true).single.state,
      'removed',
    );
    expect(find.text('本の記録'), findsNothing);
    expect(find.byKey(ValueKey('shelf.row.$id')), findsNothing);
    expect(find.widgetWithText(SnackBar, '本棚から外しました。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('一覧の［外す］は確認してから外し、一覧に留まる', (tester) async {
    await pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('shelf.search')),
      'abc ガイド',
    );
    await tester.pumpAndSettle();
    final remove = find.byKey(ValueKey('shelf.remove.$id'));

    // **やめれば何も変えない。**
    await tap(tester, remove);
    await tap(tester, find.text('やめる'));
    expect(app.loadBookshelf(bookId: id).single.state, 'wanted');
    expect(find.byKey(ValueKey('shelf.row.$id')), findsOneWidget);

    await tap(tester, remove);
    expect(find.text('本棚から外しますか？レビューと履歴は保持します。'), findsOneWidget);
    await tap(tester, find.text('続ける'));
    expect(
      app.loadBookshelf(bookId: id, includeHidden: true).single.state,
      'removed',
    );
    // 記録は開かず、一覧のまま行だけが落ちる。
    expect(find.text('本の記録'), findsNothing);
    expect(find.byKey(ValueKey('shelf.row.$id')), findsNothing);
    expect(find.widgetWithText(SnackBar, '本棚から外しました。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('狭い幅では Amazon を書名の右に、下段の3列を1段に並べる', (tester) async {
    final withIsbn = app.reservationBookId('9784274224546');
    app.saveReservation(
      book: ReservationBook(
        id: withIsbn,
        title: 'とても長い書名がここに入って二行目まで折り返す本のタイトル',
        isbn13: '9784274224546',
      ),
      operationId: app.newReservationId(),
      systems: [],
      wanted: true,
    );
    // Android 実機の幅（行の本文は約280）。
    await pump(tester, size: const Size(360, 1000));
    await tester.enterText(find.byKey(const ValueKey('shelf.search')), '書名');
    await tester.pumpAndSettle();

    final amazon = tester.getRect(
      find.byKey(ValueKey('shelf.amazon.$withIsbn')),
    );
    final open = tester.getRect(find.byKey(ValueKey('shelf.open.$withIsbn')));
    final remove = tester.getRect(
      find.byKey(ValueKey('shelf.remove.$withIsbn')),
    );
    final holdings = find.byKey(ValueKey('shelf.holdings.$withIsbn'));
    // Amazon は書名の段にあり、下段より上に居る。
    expect(amazon.bottom, lessThanOrEqualTo(open.top));
    // 開く・外すは同じ段で、この順に並ぶ。
    expect(remove.top, open.top);
    expect(remove.left, greaterThan(open.right));
    if (holdings.evaluate().isNotEmpty) {
      expect(tester.getRect(holdings).top, open.top);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('reserved books stay wanted and show the loan status', (
    tester,
  ) async {
    final reserved = ReservationBook(
      id: app.reservationBookId('9784274219337'),
      isbn13: '9784274219337',
      title: '予約した本',
      authors: const ['著者'],
    );
    app.saveReservation(
      book: reserved,
      operationId: app.newReservationId(),
      systems: ['Tokyo_Koto'],
      wanted: false,
    );
    await pump(tester);
    // fixture の進行中の本も読みたいに並ぶので、この1冊まで絞ってから見る。
    await tester.enterText(find.byKey(const ValueKey('shelf.search')), '予約した本');
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('shelf.row.${reserved.id}'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('読みたい ›')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('予約中')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dirty review survives remote update; leaving requires confirmation',
    (tester) async {
      app.setShelfState(id, 'read');
      await pump(tester, size: const Size(640, 1600));
      await tester.enterText(find.byKey(const ValueKey('shelf.search')), 'abc');
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(ValueKey('shelf.open.$id')));
      await tester.enterText(
        find.byKey(const ValueKey('shelf.review')),
        '未保存の入力',
      );
      app.saveBookReview(id, rating: 2, review: '同期内容', expectedRevision: '');
      await tester.pumpAndSettle();
      expect(find.text('未保存の入力'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('shelf.save')));
      expect(app.loadBookshelf(bookId: id).single.review, '同期内容');
      expect(find.textContaining('別の端末でレビューが変更'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('shelf.back')));
      expect(find.text('保存していないレビューを破棄しますか？'), findsOneWidget);
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(find.text('未保存の入力'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('add uses reservation and returns only after successful save', (
    tester,
  ) async {
    final c = await pump(tester);
    await tap(tester, find.byKey(const ValueKey('shelf.add')));
    expect(c.read(currentTabProvider), ShellTab.reserve);
    final reservation = c.read(reservationProvider.notifier);
    reservation.manual();
    // Title entry is covered by the existing reservation tests; a blank save stays there.
    await reservation.save(wanted: true);
    expect(c.read(currentTabProvider), ShellTab.reserve);
  });
  test('successful registration returns to bookshelf', () async {
    final c = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(app)],
    );
    addTearDown(c.dispose);
    final reservation = c.read(reservationProvider.notifier);
    reservation.openFromBookshelf();
    reservation.manual();
    reservation.edit('追加した本', '', '');
    await reservation.save(wanted: true);
    expect(c.read(currentTabProvider), ShellTab.bookshelf);
  });

  testWidgets('render bookshelf screens when requested', (tester) async {
    final output = Platform.environment['KARITA_TEST_RENDER'];
    if (output == null) return;
    await (FontLoader('sans-serif')..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/meiryo.ttc').readAsBytesSync(),
            ),
          ),
        ))
        .load();
    await (FontLoader('ShelfRender')..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/meiryo.ttc').readAsBytesSync(),
            ),
          ),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();
    final c = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(app)],
    );
    addTearDown(c.dispose);
    c.read(currentTabProvider.notifier).select(ShellTab.bookshelf);
    app.setShelfState(id, 'read');
    app.saveBookReview(
      id,
      rating: 4,
      review: 'あとで読み返したい箇所を記録。',
      expectedRevision: '',
    );
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    Future<void> shoot(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File(
          '$output/bookshelf-$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await shoot('list-480');
    await tap(tester, find.byKey(ValueKey('shelf.open.$id')));
    await shoot('record-480');
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    await tester.pumpAndSettle();
    await shoot('record-360');
    expect(tester.takeException(), isNull);
  });
}
