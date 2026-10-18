/// 設定の［アカウント］行。**3状態の出し分けと、デモで操作を置かないことを測る。**
///
/// **メールアドレスは出ない。** 接続先を名乗るには `about.get` が要り、それは段5 である。
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
    home = Directory.systemTemp.createTempSync('karita-account-');
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

  /// [state] を渡さなければ、**デモの合成がそのまま答える**（差し込まない）。
  Future<void> pumpRow(WidgetTester tester, {AppAuthState? state}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compositionProvider.overrideWithValue(composition),
          if (state != null)
            authStatusProvider.overrideWith(
              (ref) async => AppAuthStatus(state: state, kind: 'test'),
            ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: KaritaAccountRow()),
          ),
        ),
      ),
    );
    // **2回 pump する。** 3状態の読みは `Future` である（Android は Play services へ
    // 無音で訊くしかなく、同期に読めない）。
    await tester.pump();
    await tester.pump();
  }

  testWidgets('未サインインでは［サインイン］を出す', (tester) async {
    await pumpRow(tester, state: AppAuthState.signedOut);

    expect(find.text('アカウント'), findsOneWidget);
    expect(find.text('未サインイン'), findsOneWidget);
    expect(find.text('サインイン'), findsOneWidget);
    expect(find.text('サインアウト'), findsNothing);
  });

  testWidgets('サインイン済みでは［サインアウト］を出し、残る許可のことを言う', (tester) async {
    await pumpRow(tester, state: AppAuthState.signedIn);

    expect(find.text('サインイン済み'), findsOneWidget);
    expect(find.text('サインアウト'), findsOneWidget);
    // **「サインアウトした」と言い切らない。** grant は Google 側に残る。
    expect(find.textContaining('Google 側の許可は残ります'), findsOneWidget);
    // **Windows では導線を出さない。** サインインのたびにブラウザでアカウント選択が出る。
    expect(find.text('接続の解除画面を開く'), findsNothing);
  });

  testWidgets(
    'canSwitchAccount が立つ端末（Android）では［サインアウト］を置かず、常に接続の解除画面への導線を出す',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            compositionProvider.overrideWithValue(composition),
            authStatusProvider.overrideWith(
              (ref) async => const AppAuthStatus(
                state: AppAuthState.signedIn,
                kind: 'test',
                canSwitchAccount: true,
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: KaritaAccountRow()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // **サインアウトが grant を取り消さない以上、置いても何も止まらない。** 唯一
      // 実効性を持つ外部導線だけを出す。
      expect(find.text('接続の解除画面を開く'), findsOneWidget);
      expect(find.text('サインアウト'), findsNothing);
    },
  );

  testWidgets('再サインインが必要なときは、そう出して［サインイン］に戻す', (tester) async {
    await pumpRow(tester, state: AppAuthState.reauthRequired);

    expect(find.text('再サインインが必要'), findsOneWidget);
    expect(find.text('サインイン'), findsOneWidget);
  });

  testWidgets('デモでは押せるものを置かない（合成層がそう言う）', (tester) async {
    await pumpRow(tester);

    expect(find.text('デモモードでは利用できません'), findsOneWidget);
    expect(find.text('サインイン'), findsNothing);
    expect(find.text('サインアウト'), findsNothing);
  });

  test('3状態の文言は1箇所から出る', () {
    expect(authLabel(AppAuthState.signedOut), '未サインイン');
    expect(authLabel(AppAuthState.signedIn), 'サインイン済み');
    expect(authLabel(AppAuthState.reauthRequired), '再サインインが必要');
  });
}
