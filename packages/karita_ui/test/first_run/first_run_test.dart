/// 初回起動の画面。**先頭はサインインであること**と、2択の出方を測る。
///
/// 足場は `karita_app` のデモ（`DemoMode.memory`）で、**ゲートは閉じた状態に差し替える** —
/// デモのゲートは常に開くので、そのままではこの画面が出ない。
///
/// **3状態は差し込む。** ここが見るのは「どの状態でどの段を出すか」であって、3状態の
/// 組み立てではない。それは合成層の試験（`karita_app/test/composition_test.dart`）が見る。
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
    home = Directory.systemTemp.createTempSync('karita-first-run-');
    composition = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
  });
  tearDown(() {
    composition.close();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  Future<void> pumpFirstRun(
    WidgetTester tester, {
    required AppAuthState state,
    AppBackupListing? backups,
    bool shared = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compositionProvider.overrideWithValue(composition),
          bootReadyProvider.overrideWithValue(false),
          authStatusProvider.overrideWith(
            (ref) async => AppAuthStatus(state: state, kind: 'test'),
          ),
          if (backups != null)
            firstRunBackupsProvider.overrideWith((ref) async => backups),
          firstRunSharedRecordsProvider.overrideWith((ref) async => shared),
        ],
        child: const MaterialApp(home: KaritaShell()),
      ),
    );
    // **`pumpAndSettle` にしない。** 読込中の `LinearProgressIndicator` が回り続ける。
    await tester.pump();
    // 記録の有無とバックアップ一覧の Future を待つ。
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  const oneBackup = AppBackupListing(
    items: [
      AppBackup(
        backupId: 'b-1',
        createdAtUtc: '2026-09-20T01:02:03Z',
        createdOn: 'windows',
        sizeBytes: 2 * 1024 * 1024,
      ),
    ],
  );

  Future<void> openBackupList(WidgetTester tester) async {
    await tester.tap(find.text('バックアップから復旧する'));
    await tester.pump();
    // **もう1回 pump する。** 一覧は押してから引きに行く（Future が1つ挟まる）。
    await tester.pump();
  }

  testWidgets('未サインインでは2択を出さない。**先頭はサインインである**', (tester) async {
    await pumpFirstRun(tester, state: AppAuthState.signedOut);

    expect(find.text('サインイン'), findsOneWidget);
    expect(find.text('新しく始める'), findsNothing);
    expect(find.text('今の記録に合流する（おすすめ）'), findsNothing);
  });

  testWidgets('接続が切れているときは、切れたことを言う', (tester) async {
    await pumpFirstRun(tester, state: AppAuthState.reauthRequired);

    expect(
      find.textContaining('接続が切れています'),
      findsOneWidget,
      reason: 'まだ繋いでいない端末と同じ文言にしない',
    );
    expect(find.text('サインイン'), findsOneWidget);
  });

  testWidgets('記録が無ければ新規開始を主操作にし、復旧はリンクにする', (tester) async {
    await pumpFirstRun(
      tester,
      state: AppAuthState.signedIn,
      backups: oneBackup,
    );

    expect(find.text('新しく始める'), findsWidgets);
    expect(find.text('バックアップから復旧する'), findsOneWidget);
    expect(find.text('今の記録に合流する（おすすめ）'), findsNothing);
    // **一覧は押すまで引かない。**
    expect(find.text('復旧する時点のバックアップを選びます。'), findsNothing);
  });

  testWidgets('記録があれば、合流を先に出し、戻す方は主ボタンにしない', (tester) async {
    await pumpFirstRun(
      tester,
      state: AppAuthState.signedIn,
      shared: true,
      backups: oneBackup,
    );

    expect(find.text('今の記録に合流する（おすすめ）'), findsOneWidget);
    expect(find.text('バックアップから復旧する'), findsOneWidget);
    expect(find.text('新しく始める'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, '合流する'),
      findsOneWidget,
      reason: '新しい端末を足す操作を主ボタンにする',
    );
    expect(
      find.widgetWithText(TextButton, 'バックアップから復旧する'),
      findsOneWidget,
      reason: '他の端末を止める方を主ボタンにしない',
    );
  });

  testWidgets('記録があるとき、バックアップを選ぶと影響を確かめる。［戻る］なら何も始めない', (tester) async {
    await pumpFirstRun(
      tester,
      state: AppAuthState.signedIn,
      backups: oneBackup,
      shared: true,
    );
    await openBackupList(tester);
    expect(find.text('復旧する時点のバックアップを選びます。'), findsOneWidget);

    await tester.tap(find.text('このバックアップで復旧する'));
    await tester.pump();

    expect(find.text('ほかの端末の同期が止まります'), findsOneWidget);
    expect(find.textContaining('この時点より後にほかの端末で加えた変更は失われます'), findsOneWidget);
    expect(find.textContaining('［合わせる］の操作が必要'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '戻る').last);
    await tester.pump();

    expect(find.text('ほかの端末の同期が止まります'), findsNothing);
    expect(
      find.byType(LinearProgressIndicator),
      findsNothing,
      reason: '確認で戻ったら setup を始めない',
    );
  });

  testWidgets('記録が無いときは、確認を挟まない（止まる端末が無い）', (tester) async {
    await pumpFirstRun(
      tester,
      state: AppAuthState.signedIn,
      backups: oneBackup,
    );
    await openBackupList(tester);

    await tester.tap(find.text('このバックアップで復旧する'));
    await tester.pump();

    expect(find.text('ほかの端末の同期が止まります'), findsNothing);
  });

  testWidgets('［バックアップを選ぶ］で一覧が出る。日時と作成端末を出す', (tester) async {
    await pumpFirstRun(
      tester,
      state: AppAuthState.signedIn,
      backups: const AppBackupListing(
        items: [
          AppBackup(
            backupId: 'b-1',
            createdAtUtc: '2026-09-20T01:02:03Z',
            createdOn: 'windows',
            sizeBytes: 2 * 1024 * 1024,
          ),
        ],
        skipped: 2,
      ),
    );

    await openBackupList(tester);

    expect(find.text('復旧する時点のバックアップを選びます。'), findsOneWidget);
    expect(find.textContaining('Windows'), findsOneWidget);
    // **読めなかったものは数だけ出す。** 黙って落とすと不具合が見えない。
    expect(find.textContaining('読み取れないバックアップが 2 件'), findsOneWidget);
    expect(find.text('このバックアップで復旧する'), findsOneWidget);
  });

  testWidgets('バックアップが無ければ復旧リンクを出さない', (tester) async {
    await pumpFirstRun(
      tester,
      state: AppAuthState.signedIn,
      backups: const AppBackupListing(),
    );
    expect(find.text('バックアップから復旧する'), findsNothing);
    expect(find.widgetWithText(FilledButton, '新しく始める'), findsOneWidget);
  });

  group('表示の作り方', () {
    test('作成時刻は分まで。読めない値は取り繕わない', () {
      expect(backupMoment(''), '作成日時が不明');
      expect(backupMoment('まだ書いていない'), 'まだ書いていない');
      final local = DateTime.utc(2026, 9, 20, 1, 2, 3).toLocal();
      expect(
        backupMoment('2026-09-20T01:02:03Z'),
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}',
      );
    });

    test('作成端末と大きさ。分からないものは分からないと出す', () {
      expect(
        backupOrigin(const AppBackup(backupId: 'b', createdAtUtc: '')),
        '作成端末が不明',
      );
      expect(
        backupOrigin(
          const AppBackup(
            backupId: 'b',
            createdAtUtc: '',
            createdOn: 'android',
            sizeBytes: 512 * 1024,
          ),
        ),
        'Android・512 KB',
      );
    });
  });
}
