/// Windows実行ファイルでboot→業務変更→resetを通し、別プロセスのSQLiteで観測する。
/// 検証専用entrypoint。本番・通常harnessから自動実行しない。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:karita_app/karita_app.dart';

const _marker = 'demo-sql-probe-added';
const _markerId = 'd36f92ec-fadc-4bca-8000-000000000100';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // 一度描画してWindows runnerの起動を完了させる。製品画面の受入ではない。
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Text('demo_sql_probe'),
    ),
  );
  Composition? current;
  final output = Platform.environment['KARITA_DEMO_PROBE_DIR'];
  if (output == null ||
      args.length != 1 ||
      !['normal', 'crash', 'verify', 'hold'].contains(args.single) ||
      AppMode.resolve().demo != DemoMode.temp) {
    stderr.writeln(
      'Requires temp mode, probe directory and normal/crash/verify/hold',
    );
    exit(2);
  }
  final phase = args.single;
  final observations = <Map<String, Object?>>[];
  try {
    current = await boot();
    final c = current;
    final start = await _observe(c);
    _require((start['summary'] as Map)['loans'] == 19, 'initial loans');
    _require((start['summary'] as Map)['marker_count'] == 0, 'initial marker');
    c.verifyDemoFixture();
    observations.add({'step': 'startup', ...start});
    if (phase == 'hold') {
      // SQLを手で照会するための起動。明示停止まで接続を保持する。
      File(
        '$output/hold.json',
      ).writeAsStringSync(jsonEncode(start), flush: true);
      return;
    }
    if (phase == 'normal') {
      await _mutate(c);
      final edited = await _observe(c);
      _require((edited['summary'] as Map)['loans'] == 20, 'edited loans');
      _require(
        (edited['summary'] as Map)['marker_count'] == 2,
        'edited markers',
      );
      observations.add({'step': 'edited', ...edited});
      // 同じ接続で何度読んでも再投入されない。
      observations.add({'step': 'same_session', ...await _observe(c)});
      final oldPath = c.session.path!;
      current = await c.resetDemo();
      final reset = await _observe(current);
      _require(current.deviceId != c.deviceId, 'reset session');
      _require(!File(oldPath).existsSync(), 'old temp removed');
      _require((reset['summary'] as Map)['loans'] == 19, 'reset loans');
      _require((reset['summary'] as Map)['marker_count'] == 0, 'reset markers');
      current.verifyDemoFixture();
      observations.add({'step': 'reset', ...reset});
    }
    if (phase != 'verify') {
      await _mutate(current);
      observations.add({'step': 'before_exit', ...await _observe(current)});
    }
    final report = {
      'phase': phase,
      'pid': pid,
      'passed': true,
      'observations': observations,
    };
    File('$output/$phase.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    if (phase == 'crash') {
      // 外部のStop-Processで強制終了する。正常closeとは別に検証する。
      File('$output/crash.ready').writeAsStringSync('$pid', flush: true);
      return;
    }
    current.close();
    exit(0);
  } catch (error, stack) {
    File(
      '$output/$phase.error.txt',
    ).writeAsStringSync('$error\n$stack', flush: true);
    current?.close();
    exit(1);
  }
}

Future<void> _mutate(Composition c) async {
  final row = c.db
      .select("SELECT * FROM loans WHERE status = 'borrowed' ORDER BY id")
      .first;
  c.loans.update(
    loanId: row['id'] as String,
    action: 'renew',
    dueOn: '2099-01-01',
    note: _marker,
    now: nowUtc(),
  );
  c.loans.start(
    loanId: _markerId,
    bookId: row['book_id'] as String,
    systemId: row['system_id'] as String,
    pickupLibraryId: row['pickup_library_id'] as String,
    status: 'reserved',
    note: _marker,
    now: nowUtc(),
  );
  await c.syncAfterDomainWrite();
}

Future<Map<String, Object?>> _observe(Composition c) async {
  Future<List<dynamic>> sql(String query) async {
    final result = await Process.run(
      'sqlite3.exe',
      ['-readonly', '-json', c.session.path!, query],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return jsonDecode(result.stdout as String) as List<dynamic>;
  }

  final integrity = await sql('PRAGMA integrity_check');
  _require(
    integrity.length == 1 && (integrity.single as Map).values.single == 'ok',
    'SQLite integrity',
  );
  return {
    'session_id': c.deviceId,
    'db_path': c.session.path,
    'fixture': c.fixtureReport!.toJson(),
    'summary': (await sql('''SELECT
      (SELECT count(*) FROM books) AS books,
      (SELECT count(*) FROM library_systems) AS systems,
      (SELECT count(*) FROM library_memberships) AS memberships,
      (SELECT count(*) FROM loans) AS loans,
      (SELECT count(*) FROM loans WHERE note = 'demo-sql-probe-added') AS marker_count,
      (SELECT count(*) FROM loans WHERE due_on = '2099-01-01') AS changed_due_count,
      (SELECT count(*) FROM outbox_events) AS outbox,
      (SELECT count(*) FROM applied_events) AS applied,
      (SELECT count(*) FROM domain_events) AS events''')).single,
    'by_system': await sql(
      'SELECT system_id, status, count(*) AS n '
      'FROM loans GROUP BY system_id, status ORDER BY system_id, status',
    ),
    'integrity': integrity,
    'books': await sql('SELECT isbn13, title FROM books ORDER BY isbn13'),
  };
}

void _require(bool condition, String label) {
  if (!condition) throw StateError('SQL probe failed: $label');
}
