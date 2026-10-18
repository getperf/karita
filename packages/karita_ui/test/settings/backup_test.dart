/// 設定の［バックアップ］［復元］の2行と、復元の2枚。
///
/// **確認の前に何も変えないこと**と、**止まった端末でだけ「合わせる」が先頭に出ること**を測る
/// （`非公開資料:production-wiring-auth-backup-sync.md`「止まった端末は［復元］の
/// 選択から戻る」）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition composition;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-backup-');
    composition = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.temp),
    );
  });
  tearDown(() {
    composition.close();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  const readable = AppBackup(
    backupId: 'b-1',
    createdAtUtc: '2026-09-20T01:30:00Z',
    createdOn: 'windows',
    books: 524,
    loans: 182,
  );
  const tooNew = AppBackup(
    backupId: 'b-2',
    createdAtUtc: '2026-09-21T01:30:00Z',
    createdOn: 'android',
    readable: false,
  );

  /// [facts] を渡さなければ、**デモの合成がそのまま答える**（差し込まない）。
  Future<void> pumpRows(WidgetTester tester, {AppBackupFacts? facts}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compositionProvider.overrideWithValue(composition),
          if (facts != null) backupFactsProvider.overrideWithValue(facts),
          restoreCandidatesProvider.overrideWith(
            (ref) async =>
                const AppBackupListing(items: [readable, tooNew], skipped: 1),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  KaritaBackupRow(),
                  KaritaRestoreRow(),
                  KaritaResetRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, '復元'));
    await tester.pumpAndSettle();
  }

  FilledButton proceed(WidgetTester tester) =>
      tester.widget(find.byKey(const ValueKey('restore-proceed')));

  testWidgets('デモでは押せるものを置かない（合成層がそう言う）', (tester) async {
    await pumpRows(tester);

    expect(find.text('デモモードでは利用できません'), findsNWidgets(3));
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('未作成・未実行と、記録があればその時点を出す', (tester) async {
    await pumpRows(tester, facts: const AppBackupFacts());
    expect(find.text('未作成'), findsOneWidget);
    expect(find.text('未実行'), findsOneWidget);

    await pumpRows(
      tester,
      facts: const AppBackupFacts(
        lastBackupAt: '2026-09-24T01:00:00Z',
        lastRestoreAt: '2026-09-24T02:00:00Z',
        lastRestoreCreatedAt: '2026-09-20T01:30:00Z',
        lastRestorePlatform: 'android',
      ),
    );
    expect(find.text(backupMoment('2026-09-24T01:00:00Z')), findsOneWidget);
    // **最終復元は、戻した先の時点と作成端末である。** 復元した時刻ではない。
    expect(
      find.text('${backupMoment('2026-09-20T01:30:00Z')}・Android'),
      findsOneWidget,
    );
  });

  testWidgets('選択 → 影響確認。宣言では他の端末が止まると言う', (tester) async {
    final token = composition.ledgerSessionToken;
    await pumpRows(tester, facts: const AppBackupFacts(unsent: 3));
    await openDialog(tester);

    expect(find.text('復元するデータを選択'), findsOneWidget);
    // **止まっていない端末には「合わせる」を出さない。**
    expect(find.byKey(const ValueKey('restore-rejoin')), findsNothing);
    expect(find.textContaining('本 524冊・貸出記録 182件'), findsOneWidget);
    expect(find.textContaining('アプリの更新が必要'), findsOneWidget);
    expect(find.textContaining('読み取れないバックアップが 1 件'), findsOneWidget);
    // 選ぶまで進めない。版の合わないものは選べない。
    expect(proceed(tester).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('restore-b-2')));
    await tester.pump();
    expect(proceed(tester).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('restore-b-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore-proceed')));
    await tester.pump();

    expect(find.text('完全復元'), findsOneWidget);
    expect(find.textContaining('PC・スマホの新しい正本にします'), findsOneWidget);
    expect(find.textContaining('他の端末は同期を停止します'), findsOneWidget);
    expect(find.textContaining('変更 3件は失われます'), findsOneWidget);
    // **同じ端末の復元でサインインし直しは要らない。**
    expect(find.textContaining('サインイン'), findsNothing);
    // **ここまで台帳は替わっていない。**
    expect(identical(token, composition.ledgerSessionToken), isTrue);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.text('完全復元'), findsNothing);
    expect(identical(token, composition.ledgerSessionToken), isTrue);
  });

  testWidgets('初期化は復元とは別行で、選択なしの確認1枚だけを出す', (tester) async {
    final token = composition.ledgerSessionToken;
    await pumpRows(tester, facts: const AppBackupFacts(unsent: 3));

    // **復元の選択肢には並ばない。** 別の行のボタンから開く。
    await openDialog(tester);
    expect(find.byKey(const ValueKey('restore-empty')), findsNothing);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '初期化'));
    await tester.pumpAndSettle();

    // **選択画面が無い。** 開いた時点で既に確認の文言が出ている。
    expect(find.textContaining('PC・スマホの新しい正本にします'), findsOneWidget);
    expect(find.textContaining('他の端末は同期を停止します'), findsOneWidget);
    expect(find.textContaining('変更 3件は失われます'), findsOneWidget);
    expect(find.byKey(const ValueKey('reset-proceed')), findsOneWidget);
    // **ここまで台帳は替わっていない。**
    expect(identical(token, composition.ledgerSessionToken), isTrue);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reset-proceed')), findsNothing);
    expect(identical(token, composition.ledgerSessionToken), isTrue);
  });

  testWidgets('止まった端末では先頭に「合わせる」。これは他の端末を止めない', (tester) async {
    await pumpRows(
      tester,
      facts: const AppBackupFacts(generationChanged: true),
    );
    expect(
      find.textContaining('「別の端末で復元されたデータに合わせる」を選ぶと再開します'),
      findsOneWidget,
    );
    await openDialog(tester);

    final rejoin = find.byKey(const ValueKey('restore-rejoin'));
    expect(rejoin, findsOneWidget);
    // **先頭である。** バックアップより上に出る。
    expect(
      tester.getTopLeft(rejoin).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('restore-b-1'))).dy),
    );

    await tester.tap(rejoin);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore-proceed')));
    await tester.pump();

    expect(find.text('選択: 別の端末で復元されたデータ'), findsOneWidget);
    expect(find.textContaining('他の端末には影響しません'), findsOneWidget);
    expect(find.textContaining('同期を停止'), findsNothing);
  });

  test('台帳の接続が替わると、画面の保持を捨てる', () async {
    final container = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(composition)],
    );
    addTearDown(container.dispose);
    container.listen(lendingRouteProvider, (_, _) {});
    container.read(lendingRouteProvider.notifier).openArea('Tokyo_Koto');
    expect(container.read(lendingRouteProvider).systemId, 'Tokyo_Koto');

    // **通常の更新では捨てない。**
    await composition.syncAfterDomainWrite();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(lendingRouteProvider).systemId, 'Tokyo_Koto');

    // 復元と同じく接続を入れ替える。**`Composition` は同じものである。**
    composition.session.reopen();
    await composition.syncAfterDomainWrite();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(lendingRouteProvider).screen, LendingScreen.overview);
  });
}
