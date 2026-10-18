import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:karita_ui/karita_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;
  late ProviderContainer container;
  late Reservation actions;
  late Map<String, Completer<OpenBdResult>> requests;
  late List<Uri> opened;
  const a = '9784274219337';
  const b = '9784048930659';
  const c = '9784788514348';
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    opened = [];
    home = Directory.systemTemp.createTempSync('karita-reservation-ui-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
      // 実ブラウザーを起こさない。
      openBrowser: (url) async => opened.add(url),
    );
    requests = {};
    container = ProviderContainer(
      overrides: [
        compositionProvider.overrideWithValue(app),
        reservationLookupProvider.overrideWith(
          (ref, isbn) => (requests[isbn] ??= Completer<OpenBdResult>()).future,
        ),
      ],
    );
    container.read(reservationProvider);
    actions = container.read(reservationProvider.notifier);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() {
    container.dispose();
    app.close();
    home.deleteSync(recursive: true);
  });
  BookDelivery delivery(int id, String isbn) => BookDelivery(
    id,
    HandoffBook(isbn, Uri.parse('https://calil.jp/book/427421933X')),
  );
  // **書名は必須である**（2026-10-08）。保存を試す前に書誌を返しておく。
  Future<void> found(String isbn, [String title = '書名']) async {
    requests[isbn]!.complete(
      OpenBdResult.found(BookRecord(isbn13: isbn, title: title)),
    );
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'FIFO keeps current selection; duplicate ISBN takes no slot; no prefetch',
    () async {
      actions.receive(delivery(1, a));
      actions.select('Tokyo_Koto');
      actions.receive(delivery(2, b));
      actions.receive(delivery(3, c));
      actions.receive(delivery(4, b));
      expect(
        container.read(reservationProvider).waiting.map((d) => d.book.isbn13),
        [b, c],
      );
      expect(container.read(reservationProvider).draft!.systems, {
        'Tokyo_Koto',
      });
      expect(requests.keys, [a]);
      await found(a, '最初の書名');
      await actions.save(wanted: false);
      expect(container.read(reservationProvider).draft!.isbn, b);
      expect(container.read(reservationProvider).draft!.systems, isEmpty);
      expect(container.read(reservationProvider).draft!.title, isEmpty);
      expect(app.findReservationBook(a)!.title, '最初の書名');
    },
  );
  group('カーリルで探す', () {
    test('届いた本が無ければトップを開く', () async {
      await actions.openCalil();
      expect(opened, [Uri.parse('https://calil.jp/')]);
    });

    test('設定で選んだブラウザーで開く（OS の既定へ直接行かない、2026-10-16）', () async {
      final chosen = <(String, Uri)>[];
      final chromeApp = await compose(
        paths: WindowsAppPaths.at(home.path),
        settings: const DeviceSettings(browserApp: 'chrome'),
        mode: const AppMode(DemoMode.memory),
        openBrowser: (url) async => opened.add(url),
        browsers: _RecordingLauncher(chosen),
      );
      final scoped = ProviderContainer(
        overrides: [compositionProvider.overrideWithValue(chromeApp)],
      );
      addTearDown(() {
        scoped.dispose();
        chromeApp.close();
      });
      scoped.read(reservationProvider);
      await scoped.read(reservationProvider.notifier).openCalil();
      expect(chosen, [('chrome', Uri.parse('https://calil.jp/'))]);
      expect(opened, isEmpty);
    });

    test('届いた本があれば13桁の書籍ページを開き、送り返した同じ本で下書きは変わらない', () async {
      actions.receive(delivery(1, a));
      actions.select('Tokyo_Koto');
      await actions.openCalil();
      expect(opened, [Uri.parse('https://calil.jp/book/$a')]);
      actions.receive(delivery(2, a));
      final state = container.read(reservationProvider);
      expect(state.draft!.isbn, a);
      expect(state.draft!.systems, {'Tokyo_Koto'});
      expect(state.waiting, isEmpty);
    });

    test('貸出し一覧からは下書きが残っていてもトップを開く', () async {
      actions.receive(delivery(1, a));
      await actions.startFromLending('Tokyo_Koto');
      expect(opened, [Uri.parse('https://calil.jp/')]);
    });
  });
  group('貸出し一覧から始めた予約', () {
    test('届いた最初の1冊だけ区が初期選択になり、予約したら貸出し一覧へ戻る', () async {
      await actions.startFromLending('Tokyo_Koto');
      expect(opened, [Uri.parse('https://calil.jp/')]);
      actions.receive(delivery(1, a));
      expect(container.read(reservationProvider).draft!.systems, {
        'Tokyo_Koto',
      });
      // 強制ではなく初期選択である。
      actions.select('Tokyo_Sumida');
      expect(container.read(reservationProvider).draft!.systems, hasLength(2));
      actions.receive(delivery(2, b));
      // 受信待ちへ回った本に区は付かない。
      actions.discard();
      expect(container.read(reservationProvider).draft!.isbn, b);
      expect(container.read(reservationProvider).draft!.systems, isEmpty);
    });

    test('読みたいで保存したら本棚へ戻る', () async {
      await actions.startFromLending('Tokyo_Koto');
      actions.receive(delivery(1, a));
      await found(a);
      await actions.save(wanted: true);
      expect(container.read(currentTabProvider), ShellTab.bookshelf);
    });

    test('予約で保存したら貸出し一覧へ戻る', () async {
      await actions.startFromLending('Tokyo_Koto');
      actions.receive(delivery(1, a));
      await found(a);
      await actions.save(wanted: false);
      final message = container.read(reservationProvider).message;
      if (!message.contains('登録できません') && !message.contains('常用館')) {
        expect(container.read(currentTabProvider), ShellTab.lending);
      }
    });

    test('破棄すると文脈は消え、後から届いた本に区は付かない', () async {
      await actions.startFromLending('Tokyo_Koto');
      actions.receive(delivery(1, a));
      actions.discard();
      actions.receive(delivery(2, b));
      expect(container.read(reservationProvider).draft!.systems, isEmpty);
    });

    test('届かないまま次に届いた本で使い切る（2冊目には付かない）', () async {
      await actions.startFromLending('Tokyo_Koto');
      actions.receive(delivery(1, a));
      actions.discard();
      await actions.startFromLending('Tokyo_Sumida');
      actions.receive(delivery(2, b));
      expect(container.read(reservationProvider).draft!.systems, {
        'Tokyo_Sumida',
      });
    });
  });
  test('20 waiting books cap is explicit and keeps older candidates', () {
    actions.receive(delivery(1, a));
    for (var i = 0; i < 21; i++) {
      actions.receive(delivery(i + 2, 'test-$i'));
    }
    expect(container.read(reservationProvider).waiting, hasLength(20));
    expect(container.read(reservationProvider).message, contains('20冊'));
    expect(
      container.read(reservationProvider).waiting.first.book.isbn13,
      'test-0',
    );
  });
  test('invalid ISBN cannot be saved and the manual draft survives', () async {
    actions.manual();
    actions.edit('手入力', '著者', 'invalid');
    await actions.save(wanted: true);
    expect(container.read(reservationProvider).draft!.title, '手入力');
    expect(app.loadReservationBooks().where((b) => b.title == '手入力'), isEmpty);
  });
  test('a delivery cancels the manual draft instead of queueing', () async {
    actions.manual();
    actions.edit('手入力', '著者', '');
    actions.receive(delivery(1, a));
    final state = container.read(reservationProvider);
    expect(state.waiting, isEmpty);
    expect(state.draft!.isbn, a);
    expect(state.draft!.manual, isFalse);
    expect(state.draft!.title, isNot('手入力'));
    expect(state.message, contains('取り消して'));
    // **受信した本を編集中のときは従来どおり待たせる。**
    actions.receive(delivery(2, b));
    expect(
      container.read(reservationProvider).waiting.map((d) => d.book.isbn13),
      [b],
    );
  });
  test(
    'save failure retains draft and queue; repeated tap only saves once',
    () async {
      actions.receive(delivery(1, a));
      await found(a);
      actions.select('Tokyo_Sumida');
      actions.receive(delivery(2, b));
      await actions.save(wanted: false);
      expect(container.read(reservationProvider).draft!.isbn, a);
      expect(container.read(reservationProvider).waiting, hasLength(1));
      actions.select('Tokyo_Sumida');
      actions.select('Tokyo_Koto');
      await Future.wait([
        actions.save(wanted: false),
        actions.save(wanted: false),
      ]);
      expect(
        app.db.select('SELECT * FROM loans WHERE book_id = ?', [
          app.reservationBookId(a),
        ]),
        hasLength(1),
      );
      expect(container.read(reservationProvider).draft!.isbn, b);
    },
  );
  group('書名は必須（2026-10-08）', () {
    test('書誌の取得中は保存しない', () async {
      actions.receive(delivery(1, a));
      await actions.save(wanted: true);
      expect(container.read(reservationProvider).draft!.isbn, a);
      expect(container.read(reservationProvider).message, contains('タイトル'));
      expect(app.findReservationBook(a), isNull);
    });

    test('openBD に無い本は書名を入れて登録する。出典は手動になる', () async {
      actions.receive(delivery(1, a));
      requests[a]!.complete(const OpenBdResult.notListed());
      await Future<void>.delayed(Duration.zero);
      final draft = container.read(reservationProvider).draft!;
      expect(draft.titleEditable, isTrue);
      expect(draft.lookupNotice, contains('書名'));
      actions.editShared('  図書館で\n見た書名 ', '著者');
      await actions.save(wanted: true);
      final book = app.findReservationBook(a)!;
      expect(book.title, '図書館で 見た書名');
      expect(book.authors, ['著者']);
      final refs =
          app.db.select('SELECT book_references FROM books WHERE id = ?', [
                book.id,
              ]).single['book_references']!
              as String;
      expect(refs, contains('"manual"'));
      expect(refs, contains('calil.jp'));
    });

    test('書名が空の保存済み Book は、取れた書誌で埋めて保存する', () async {
      final id = app.reservationBookId(a);
      app.db.execute(
        "INSERT INTO books (id, title, authors, isbn13, version, updated_at_utc, "
        "updated_by_device_id) VALUES (?, NULL, '[]', ?, 1, "
        "'2026-10-01T00:00:00Z', 'x')",
        [id, a],
      );
      actions.receive(delivery(1, a));
      expect(container.read(reservationProvider).draft!.titleEditable, isTrue);
      await found(a, 'あとから載った書名');
      expect(container.read(reservationProvider).draft!.title, 'あとから載った書名');
      await actions.save(wanted: true);
      expect(app.findReservationBook(a)!.title, 'あとから載った書名');
    });

    test('書名を貼り付けると1行に詰める', () {
      expect(normalizeTitle('　書名\r\n副題  第2版 '), '書名 副題 第2版');
    });
  });

  testWidgets('manual form records wanted and returns to initial screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ReservationView())),
      ),
    );
    await tester.tap(find.text('手動で入力'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'タイトル（必須）'),
      '手動登録テスト',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('読みたい'));
    await tester.tap(find.text('読みたい'));
    await tester.pumpAndSettle();
    expect(find.text('本棚の「読みたい」に登録しました。'), findsOneWidget);
    expect(
      app.loadReservationBooks().where((b) => b.title == '手動登録テスト'),
      hasLength(1),
    );
  });

  group('予約を登録できないときの案内（2026-10-15）', () {
    // **`found` を使わない。** あれは `Future.delayed` を待つので、時計の進まない
    // `testWidgets` の中では返らない。完了だけさせ、続く `pump` で流す。
    void complete(String isbn) => requests[isbn]!.complete(
      OpenBdResult.found(BookRecord(isbn13: isbn, title: '書名')),
    );

    // **Riverpod が後片付けに置く0秒のタイマーを流す。** 残ると試験の終わりで落ちる。
    Future<void> settle(WidgetTester tester) =>
        tester.pump(const Duration(milliseconds: 1));

    Future<void> pumpView(
      WidgetTester tester, {
      Map<String, LibrarySystem>? libraries,
    }) async {
      tester.view.physicalSize = const Size(520, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final view = MaterialApp(home: Scaffold(body: ReservationView()));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: libraries == null
              ? view
              // 図書館が無い台帳を作る代わりに、一覧だけを差し替える。
              : ProviderScope(
                  overrides: [librariesProvider.overrideWithValue(libraries)],
                  child: view,
                ),
        ),
      );
      await tester.pump();
    }

    testWidgets('常用館が決まっていない館を選ぶと、予約したを止めて選ぶ画面へ渡す', (tester) async {
      actions.receive(delivery(1, a));
      complete(a);
      actions.select('Tokyo_Sumida');
      await pumpView(tester);

      expect(find.text('常用館が選ばれていません'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '予約した'))
            .onPressed,
        isNull,
        reason: '保存しても preferred-branch で弾かれるだけである',
      );

      await tester.tap(
        find.byKey(const ValueKey('reservation-gate-preferred:Tokyo_Sumida')),
      );
      await tester.pump();
      final route = container.read(librariesRouteProvider);
      expect(route.screen, LibrariesScreen.preferredBranch);
      expect(route.systemId, 'Tokyo_Sumida');
      expect(container.read(currentTabProvider), ShellTab.settings);

      // **閉じたら予約へ帰る。** 入力中の予約は残っている。
      container.read(librariesRouteProvider.notifier).back();
      expect(container.read(currentTabProvider), ShellTab.reserve);
      expect(container.read(reservationProvider).draft!.systems, {
        'Tokyo_Sumida',
      });
      await settle(tester);
    });

    testWidgets('常用館が決まっている館だけなら、案内は出ない', (tester) async {
      actions.receive(delivery(1, a));
      complete(a);
      actions.select('Tokyo_Koto');
      await pumpView(tester);

      expect(find.text('常用館が選ばれていません'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '予約した'))
            .onPressed,
        isNotNull,
      );
      await settle(tester);
    });

    testWidgets('図書館が1件も無ければ、登録の画面へ渡す。戻ると予約へ帰る', (tester) async {
      actions.receive(delivery(1, a));
      complete(a);
      await pumpView(tester, libraries: const <String, LibrarySystem>{});

      expect(find.text('図書館が登録されていません'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('reservation-gate-add-library')),
      );
      await tester.pump();
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.addPrefecture,
      );
      expect(container.read(currentTabProvider), ShellTab.settings);

      // 県 → 候補と進んでも、戻ると県の段を経て予約へ帰る。
      final route = container.read(librariesRouteProvider.notifier);
      route.openAddSearch('東京都');
      route.back();
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.addPrefecture,
      );
      route.back();
      expect(container.read(currentTabProvider), ShellTab.reserve);
      await settle(tester);
    });
  });

  testWidgets(
    'received form fits narrow light and dark screens; optional rendering',
    (tester) async {
      final output = Platform.environment['KARITA_TEST_RENDER'];
      if (output != null) {
        await tester.runAsync(() async {
          final font = FontLoader('ReservationRender')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File('C:/Windows/Fonts/meiryo.ttc').readAsBytesSync(),
                ),
              ),
            );
          await font.load();
          final svgFont = FontLoader('sans-serif')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File('C:/Windows/Fonts/meiryo.ttc').readAsBytesSync(),
                ),
              ),
            );
          await svgFont.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File(
                    'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                  ).readAsBytesSync(),
                ),
              ),
            );
          await icons.load();
        });
      }
      actions.receive(delivery(1, a));
      actions.receive(delivery(2, b));
      requests[a]!.complete(
        const OpenBdResult.found(
          BookRecord(isbn13: a, title: 'ソフトウェア設計の考え方と実践', authorLine: '山田 太郎'),
        ),
      );
      await tester.pump();
      actions.select('Tokyo_Koto');
      final key = GlobalKey();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final brightness in Brightness.values) {
        tester.view.physicalSize = const Size(390, 940);
        final base = karitaTheme(brightness);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: output == null
                  ? base
                  : base.copyWith(
                      textTheme: base.textTheme.apply(
                        fontFamily: 'ReservationRender',
                      ),
                    ),
              home: RepaintBoundary(
                key: key,
                child: const Scaffold(body: ReservationView()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('受信待ち 1冊'), findsOneWidget);
        expect(find.text('編集中の本とは別です'), findsOneWidget);
        expect(find.text('一覧を見る'), findsOneWidget);
        if (output != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(key),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            Directory(output).createSync(recursive: true);
            await File(
              '$output/reservation-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(find.text('受信待ち 1冊'), findsOneWidget);
        await tester.tap(find.text('一覧を見る'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('受信待ち 1冊'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('閉じる'));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, 500));
        await tester.pumpAndSettle();
      }
    },
  );
}

class _RecordingLauncher implements BrowserLauncher {
  _RecordingLauncher(this.opened);
  final List<(String, Uri)> opened;

  @override
  Future<Set<String>> installed() async => {'chrome'};

  @override
  Future<void> open(String choice, Uri url) async => opened.add((choice, url));
}
