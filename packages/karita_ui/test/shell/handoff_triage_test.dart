/// cold start / 用途未確定の triage。**widget を立てずに、通知メソッドを直接呼んで測る**
/// （`reservation_test.dart` の `actions.receive(delivery)` と同じ扱い）。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;
  late ProviderContainer container;
  late PendingHandoffTriage triage;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    home = Directory.systemTemp.createTempSync('karita-handoff-triage-ui-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
    container = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(app)],
    );
    triage = container.read(pendingHandoffTriageProvider.notifier);
  });
  tearDown(() {
    container.dispose();
    app.close();
    home.deleteSync(recursive: true);
  });

  final url = Uri.parse('https://unknown.example/login');

  test('地区未確定は保留し、選択画面が要ることを示す', () {
    triage.onTriage(DistrictChoiceNeeded(LaunchPurpose.lending, url, const []));
    expect(
      container.read(pendingHandoffTriageProvider),
      isA<DistrictChoiceNeeded>(),
    );
  });

  test('用途未確定は保留する', () {
    triage.onTriage(PurposeChoiceNeeded(url));
    expect(
      container.read(pendingHandoffTriageProvider),
      isA<PurposeChoiceNeeded>(),
    );
  });

  test('地区が一意に決まった貸出し受信は、保留せず LendingRoute へ直接配る', () {
    triage.onTriage(LendingTriageCandidate('Tokyo_Koto', DateTime.now()));

    expect(container.read(pendingHandoffTriageProvider), isNull);
    expect(
      container.read(lendingRouteProvider),
      LendingRouteState.area('Tokyo_Koto'),
    );
    expect(container.read(currentTabProvider), ShellTab.lending);
  });

  test('地区が一意に決まったマイページ受信は、保留せず LibrariesRoute へ直接配る', () {
    triage.onTriage(MypageTriageCandidate('Tokyo_Koto', url, DateTime.now()));

    expect(container.read(pendingHandoffTriageProvider), isNull);
    final state = container.read(librariesRouteProvider);
    expect(state.screen, LibrariesScreen.mypageUrl);
    expect(state.systemId, 'Tokyo_Koto');
    expect(state.prefillUrl, url.toString());
    expect(container.read(currentTabProvider), ShellTab.settings);
  });

  test('resolve で保留を解く', () {
    triage.onTriage(PurposeChoiceNeeded(url));
    expect(container.read(pendingHandoffTriageProvider), isNotNull);

    triage.resolve();
    expect(container.read(pendingHandoffTriageProvider), isNull);
  });

  // `非公開資料:amazon-share-handoff.md` §3。どれも保留せず直接配る。
  group('Amazon の受信', () {
    LaunchContext shelfLaunch(String? bookId) => LaunchContext(
      purpose: LaunchPurpose.bookshelf,
      systemId: '',
      host: 'www.amazon.co.jp',
      startedAt: DateTime.now(),
      bookId: bookId,
    );

    test('記録から戻す: その本の記録を開き、記録を消す', () {
      container.read(currentTabProvider.notifier).select(ShellTab.lending);
      container.read(shelfReturnProvider.notifier).set(ShellTab.lending);
      app.handoff.remember(shelfLaunch('book-1'));

      triage.onTriage(ShelfReturnCandidate('book-1', DateTime.now()));

      expect(container.read(pendingHandoffTriageProvider), isNull);
      expect(container.read(shelfOpenRequestProvider), 'book-1');
      expect(container.read(currentTabProvider), ShellTab.bookshelf);
      // 本棚から出た往復なので、閉じたら貸出しへ帰る約束は持たない。
      expect(container.read(shelfReturnProvider), isNull);
      expect(app.handoff.launch, isNull);
    });

    test('一覧から出た記録: 一覧へ戻す', () {
      app.handoff.remember(shelfLaunch(null));

      triage.onTriage(ShelfReturnCandidate(null, DateTime.now()));

      expect(container.read(shelfOpenRequestProvider), isNull);
      expect(container.read(currentTabProvider), ShellTab.bookshelf);
      expect(app.handoff.launch, isNull);
    });

    test('本棚にある ISBN: その本の記録', () {
      triage.onTriage(const ShelfBookFound('book-2'));

      expect(container.read(shelfOpenRequestProvider), 'book-2');
      expect(container.read(currentTabProvider), ShellTab.bookshelf);
    });

    test('本棚に無い ISBN: 予約画面の下書き。provider は amazon、source はホストだけ', () {
      triage.onTriage(
        ShelfBookDraft(
          HandoffBook('9784000000000', Uri.parse('https://www.amazon.co.jp/')),
        ),
      );

      final draft = container.read(reservationProvider).draft!;
      expect(draft.isbn, '9784000000000');
      expect(draft.provider, 'amazon');
      expect(draft.sourceUrl, 'https://www.amazon.co.jp/');
      expect(container.read(currentTabProvider), ShellTab.reserve);
      // **自動では追加しない。**
      expect(app.findReservationBook('9784000000000'), isNull);
    });

    test('ISBN なし: 予約タブで案内する。下書きは作らない', () {
      triage.onTriage(const AmazonNoIsbn(AmazonShape.asin));

      final state = container.read(reservationProvider);
      expect(state.message, amazonNoIsbnMessage);
      expect(state.draft, isNull);
      expect(container.read(currentTabProvider), ShellTab.reserve);
    });
  });
}
