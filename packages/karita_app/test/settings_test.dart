import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_app/src/settings_adapter.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;
  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-settings-');
    final paths = WindowsAppPaths.at(home.path)..ensure();
    File('${paths.configDir}/device.json').writeAsStringSync(
      '{"schemaVersion":1,"ui":{"theme":"system","lastTab":"bookshelf"},'
      '"calil":{"appkey":"private-key"},"unknown":{"keep":7}}',
    );
    app = await compose(
      paths: paths,
      settings: DeviceSettings.read(paths.configDir),
      mode: const AppMode(DemoMode.memory),
    );
  });
  tearDown(() {
    app.close();
    home.deleteSync(recursive: true);
  });

  test('テーマの保存・通知・再読込。秘密と未知の鍵、直近タブを保つ', () async {
    final values = <String>[];
    final sub = app.settingsChanges.listen(values.add);
    app.saveTheme('dark');
    app.saveTheme('light');
    await Future<void>.delayed(Duration.zero);
    expect(values, ['dark', 'light']);
    final saved = DeviceSettings.read(app.paths.configDir);
    expect(saved.theme, 'light');
    expect(saved.lastTab, 'bookshelf');
    expect(saved.calilAppkey, 'private-key');
    expect(
      File('${app.paths.configDir}/device.json').readAsStringSync(),
      contains('"keep": 7'),
    );
    expect(app.settings.theme, 'light');
    await sub.cancel();
    app = await app.resetDemo();
    expect(app.theme, 'light');
  });

  test('保存できないときは有効設定を動かさず、秘密やパスを例外へ載せない', () {
    final target = File('${app.paths.configDir}/device.json');
    target.deleteSync();
    Directory(target.path).createSync();
    expect(
      () => app.saveTheme('dark'),
      throwsA(
        isA<AppIssue>()
            .having((e) => e.code, 'code', 'settings-write')
            .having(
              (e) => e.message.contains(home.path),
              'path hidden',
              isFalse,
            )
            .having(
              (e) => e.message.contains('private-key'),
              'key hidden',
              isFalse,
            ),
      ),
    );
    expect(app.theme, 'system');
  });

  test('不正なテーマはファイルを書かずに拒否', () {
    final before = File(
      '${app.paths.configDir}/device.json',
    ).readAsStringSync();
    expect(() => app.saveTheme('secret-invalid'), throwsA(isA<AppIssue>()));
    expect(
      File('${app.paths.configDir}/device.json').readAsStringSync(),
      before,
    );
  });

  test('7状態は判定し直さず写す。詳細はコードと原因のメッセージだけ', () {
    for (final state in SyncState.values) {
      final value = appSyncStatus(
        SyncStatus(
          state: state,
          lastSuccessAt: '2026-09-17T00:00:00Z',
          autoResolved: 2,
          facts: const SyncFacts(openConflicts: 3, checksumMismatch: true),
        ),
      );
      expect(value.state.name, state.name);
      expect(value.lastSuccessAt, '2026-09-17T00:00:00Z');
      expect(value.autoResolved, 2);
      if (state == SyncState.needsAttention) {
        expect(value.issue!.message, contains('openConflicts=3'));
        expect(value.issue!.message, contains('checksumMismatch=true'));
      }
    }
  });

  test('業務更新後はデモでも状態変更を通知する', () async {
    final changed = app.statusChanges.first;
    await app.syncAfterDomainWrite();
    await changed;
    expect(app.syncStatus.state, AppSyncState.unsent);
  });

  test('台帳の通知には同期の状態の通知が必ず伴う（2026-10-08）', () async {
    // 設定の同期行は `syncStatusChanges` だけを見る。台帳が変わったのに状態が古いまま、を作らない。
    final ledger = app.statusChanges.first;
    final sync = app.syncStatusChanges.first;
    await app.syncAfterDomainWrite();
    await ledger;
    await sync;
  });

  test('バックアップの写しは索引から件数と「読めるか」を採る', () {
    BackupRef ref(Map<String, String> summary) =>
        BackupRef(backupId: 'b', remoteId: 'r', summary: summary);

    final ok = appBackup(
      ref({
        'backupVersion': '$backupVersion',
        'schemaVersion': '${latestVersion()}',
        'createdAtUtc': '2026-09-20T01:30:00Z',
        'sourcePlatform': 'windows',
        'counts': 'books=524 library_memberships=5 loans=182',
      }),
    );
    expect(ok.books, 524);
    expect(ok.loans, 182);
    expect(ok.createdOn, 'windows');
    expect(ok.readable, isTrue);

    // **新しい端末で作ったものは一覧で選べなくする**（受入ケース8）。
    expect(
      appBackup(ref({'schemaVersion': '${latestVersion() + 1}'})).readable,
      isFalse,
    );
    expect(
      appBackup(ref({'backupVersion': '${backupVersion + 1}'})).readable,
      isFalse,
    );
    // **索引に版が無いものは弾かない。** 読めるかは取得後に決まる。件数は出さない。
    final bare = appBackup(ref(const {}));
    expect(bare.readable, isTrue);
    expect(bare.books, isNull);
  });
}
