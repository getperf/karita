import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_platform/karita_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = File('assets/demo/standard.json').readAsStringSync();
  final date = DateTime(2026, 9, 15);
  final fixture = DemoFixture(catalog, date);
  late Directory home;
  late AppPaths paths;
  setUp(() {
    home = Directory.systemTemp.createTempSync('karita-fixture-test-');
    paths = WindowsAppPaths.at(home.path)..ensure();
  });
  tearDown(() => home.deleteSync(recursive: true));

  Future<Composition> start(DemoMode mode, {DateTime? at, String? source}) =>
      compose(
        paths: paths,
        settings: const DeviceSettings(),
        mode: AppMode(mode),
        demoCatalog: source ?? catalog,
        demoDate: at ?? date,
      );

  for (final mode in [DemoMode.memory, DemoMode.temp]) {
    test('$mode: 新規・保持・リセット・再起動と本番DBの分離', () async {
      File(paths.dbPath).writeAsStringSync('production sentinel');
      final setting = File('${paths.configDir}/device.json')
        ..writeAsStringSync('{"log.level":"INFO"}');
      var c = await start(mode);
      addTearDown(() => c.close());
      expect(c.verifyDemoFixture().counts['loans'], 19);
      expect(getState(c.db, stateGenerationId), isNull);
      final oldContext = c.domain;
      final oldId = c.deviceId;
      final oldPath = c.session.path;
      c.loans.update(
        loanId: fixture.loanId(6),
        action: 'renew',
        dueOn: '2099-01-01',
        note: 'reset-marker',
        now: nowUtc(),
      );
      c.loans.start(
        loanId: fixture.loanId(99),
        bookId: fixture.bookId(0),
        systemId: 'Tokyo_Koto',
        pickupLibraryId: fixture.systems
            .singleWhere((s) => s.id == 'Tokyo_Koto')
            .branches
            .first
            .id,
        status: 'reserved',
        now: nowUtc(),
      );
      await c.syncAfterDomainWrite();
      expect(c.db.select("SELECT count(*) n FROM loans").single['n'], 20);
      expect(c.verifyDemoFixture, throwsStateError);
      c = await c.resetDemo(date: date);
      expect(c.deviceId, isNot(oldId));
      expect(c.verifyDemoFixture().counts['outbox_events'], 88);
      expect(
        c.db.select('SELECT * FROM loans WHERE id = ?', [fixture.loanId(99)]),
        isEmpty,
      );
      expect(() => oldContext.db.select('SELECT 1'), throwsA(anything));
      if (oldPath != null) {
        expect(File(oldPath).existsSync(), isFalse);
        expect(c.session.path, isNot(oldPath));
      }
      c.close();
      c = await start(mode);
      expect(c.verifyDemoFixture().counts['books'], 30);
      expect(File(paths.dbPath).readAsStringSync(), 'production sentinel');
      expect(setting.readAsStringSync(), '{"log.level":"INFO"}');
    });
  }

  test('曜日境界: 月曜日から日曜日、月末・年末でも期限を検査', () async {
    for (final at in [
      for (var day = 14; day <= 20; day++) DateTime(2026, 9, day),
      DateTime(2026, 12, 31),
    ]) {
      final c = await start(DemoMode.memory, at: at);
      try {
        final report = c.verifyDemoFixture();
        expect(report.counts['due_this_week'], at.weekday == 7 ? 4 : 5);
        expect(report.counts['due_overdue'], 1);
      } finally {
        c.close();
      }
    }
  });

  test('不正カタログ・未知シナリオはDB公開前に失敗', () async {
    final malformed = jsonDecode(catalog) as Map<String, dynamic>;
    malformed['books'][0]['isbn13'] = '9780000000000';
    await expectLater(
      start(DemoMode.temp, source: jsonEncode(malformed)),
      throwsFormatException,
    );
    await expectLater(
      compose(
        paths: paths,
        settings: const DeviceSettings(),
        mode: const AppMode(DemoMode.temp),
        demoScenario: 'missing',
        demoCatalog: catalog,
      ),
      throwsFormatException,
    );
    expect(File(paths.dbPath).existsSync(), isFalse);
  });

  test('件数を変えずに参照を壊しても検出', () async {
    final c = await start(DemoMode.memory);
    addTearDown(c.close);
    // 破損注入だけ直接SQL。デモ生成・利用者の編集では使わない。
    c.db.execute('UPDATE loans SET pickup_library_id = ? WHERE id = ?', [
      'missing-branch',
      fixture.loanId(0),
    ]);
    expect(c.verifyDemoFixture, throwsStateError);
  });
}
