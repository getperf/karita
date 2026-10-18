/// ログの行。**両方の書式が同じ項目を同じ順で持つことを固定する。**
///
/// 受入の正本は `非公開資料:logging-and-diagnostics.md`「受入条件」。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:logging/logging.dart';

LogRecord _record(
  String event, {
  Object? attached,
  Level level = Level.INFO,
  String logger = 'karita.sync.engine',
}) =>
    LogRecord(level, event, logger, attached);

/// **`LogRecord` は時刻を受け取らない**（`DateTime.now()` を自分で入れる）。行の見た目を
/// 固定したいので、組んだ項目の `at` だけを置き換える。順序は鍵の挿入順なので動かない。
Map<String, Object?> _fieldsAt(LogRecord record) =>
    logFields(record)..['at'] = '2026-09-13T04:05:06.123Z';

void main() {
  group('水準と書式の決め方', () {
    test('既定は INFO と text', () {
      final choice = resolveLogging(defineLevel: '', defineFormat: '');
      expect(choice.level, Level.INFO);
      expect(choice.format, LogFormat.text);
      expect(choice.ignored, isEmpty);
    });

    test('--dart-define が既定を上書きする', () {
      final choice =
          resolveLogging(defineLevel: 'WARNING', defineFormat: 'jsonl');
      expect(choice.level, Level.WARNING);
      expect(choice.format, LogFormat.jsonl);
    });

    test('device.json が --dart-define を上書きする', () {
      final choice = resolveLogging(
        configLevel: 'FINE',
        configFormat: 'text',
        defineLevel: 'WARNING',
        defineFormat: 'jsonl',
      );
      expect(choice.level, Level.FINE);
      expect(choice.format, LogFormat.text);
    });

    test('読めない値は既定へ落とし、落としたことを持ち歩く', () {
      final choice = resolveLogging(
        configLevel: 'LOUD',
        configFormat: 'yaml',
        defineLevel: '',
        defineFormat: '',
      );
      expect(choice.level, Level.INFO);
      expect(choice.format, LogFormat.text);
      expect(choice.ignored.map((i) => i['key']),
          containsAll(['log.level', 'log.format']));
      expect(choice.ignored.first['source'], 'device.json');
    });

    test('device.json が読めなければ --dart-define まで降りる', () {
      final choice = resolveLogging(configLevel: 'LOUD', defineLevel: 'SHOUT');
      expect(choice.level, Level.SHOUT);
      expect(choice.ignored.single['key'], 'log.level');
    });
  });

  group('行の書式', () {
    test('text は位置4つのあとに 鍵=値 が続く', () {
      final line = formatTextLine(_fieldsAt(
          _record('sync.run.begin', attached: {'generation': 'g-0007', 'pending': 3})));
      expect(
        line,
        '2026-09-13T04:05:06.123Z INFO    karita.sync.engine sync.run.begin '
        'generation=g-0007 pending=3',
      );
    });

    test('水準は7桁へ左詰めで揃う', () {
      final line = formatTextLine(
          logFields(_record('x', level: Level.WARNING)));
      expect(line, contains(' WARNING karita.sync.engine x'));
    });

    test('jsonl は同じ項目を同じ順で持つ', () {
      final fields = _fieldsAt(
          _record('sync.run.begin', attached: {'generation': 'g-0007', 'pending': 3}));
      final json = jsonDecode(formatJsonLine(fields)) as Map<String, Object?>;
      expect(json.keys.toList(),
          ['at', 'level', 'logger', 'event', 'generation', 'pending']);
      expect(json['at'], '2026-09-13T04:05:06.123Z');
      expect(json['pending'], 3);
    });

    test('付随値は第2引数から読む', () {
      // `_log.info('event', {...})` と書くと、package:logging は第2引数を
      // `LogRecord.error` に入れる。**②③ が書く形はこれである。**
      final fields = logFields(_record('e', attached: {'a': 1}));
      expect(fields['a'], 1);
      expect(fields.containsKey('error'), isFalse);
    });

    test('例外は末尾の error に置く', () {
      final fields =
          logFields(_record('sync.run.failed', attached: StateError('boom')));
      expect(fields.keys.last, 'error');
      expect('${fields['error']}', contains('boom'));
    });

    test('null は項目ごと落とす', () {
      final fields = logFields(_record('e', attached: {'a': null, 'b': 1}));
      expect(fields.containsKey('a'), isFalse);
      expect(formatTextLine(fields), endsWith('b=1'));
      expect(jsonDecode(formatJsonLine(fields)), isNot(contains('a')));
    });

    test('空白・=・" を含む値は囲んで逃がす', () {
      final line = formatTextLine(logFields(
          _record('e', attached: {'m': r'a b=c "d" \e'})));
      expect(line, endsWith(r'm="a b=c \"d\" \\e"'));
    });

    test('改行は \\n へ畳む', () {
      final line =
          formatTextLine(logFields(_record('e', attached: {'m': 'a\nb'})));
      expect(line, endsWith(r'm="a\nb"'));
      expect(line.contains('\n'), isFalse);
    });

    test('書けない値でも行を落とさない', () {
      final line = formatJsonLine(
          logFields(_record('e', attached: {'m': Object()})));
      expect(jsonDecode(line), isA<Map<String, Object?>>());
    });

    test('ミリ秒まで、末尾 Z', () {
      expect(utcMillis(DateTime.utc(2026, 1, 2, 3, 4, 5)), '2026-01-02T03:04:05.000Z');
      expect(utcMillis(DateTime.utc(2026, 1, 2, 3, 4, 5, 7, 89)),
          '2026-01-02T03:04:05.007Z');
    });
  });

  group('sink', () {
    late Directory home;

    setUp(() => home = Directory.systemTemp.createTempSync('karita-log-'));
    tearDown(() {
      uninstallLogging();
      Logger.root.level = Level.INFO;
      if (home.existsSync()) home.deleteSync(recursive: true);
    });

    String read() =>
        File(AppLayout.under(home.path, AppLayout.logFile)).readAsStringSync();

    test('1行1件でファイルへ追記する', () {
      installLogging(
          logDir: home.path, level: Level.INFO, format: LogFormat.text);
      Logger('karita.test').info('a.b', {'n': 1});
      Logger('karita.test').info('c.d');
      final lines = read().trim().split('\n');
      expect(lines, hasLength(2));
      expect(lines.first, endsWith('karita.test a.b n=1'));
    });

    test('水準より下は出ない', () {
      installLogging(
          logDir: home.path, level: Level.WARNING, format: LogFormat.text);
      Logger('karita.test').fine('debug.line');
      Logger('karita.test').warning('warn.line');
      expect(read(), isNot(contains('debug.line')));
      expect(read(), contains('warn.line'));
    });

    test('二度立てても同じ行を2回書かない', () {
      installLogging(
          logDir: home.path, level: Level.INFO, format: LogFormat.text);
      installLogging(
          logDir: home.path, level: Level.INFO, format: LogFormat.text);
      Logger('karita.test').info('once');
      expect(read().trim().split('\n'), hasLength(1));
    });

    test('書式を切り替えても拡張子は .log のままで、1本に混ざる', () {
      installLogging(
          logDir: home.path, level: Level.INFO, format: LogFormat.text);
      Logger('karita.test').info('text.line');
      installLogging(
          logDir: home.path, level: Level.INFO, format: LogFormat.jsonl);
      Logger('karita.test').info('jsonl.line');
      final lines = read().trim().split('\n');
      expect(lines.first.startsWith('{'), isFalse);
      expect(lines.last.startsWith('{'), isTrue);
    });

    test('ログの場所が無ければ作る', () {
      final logDir = AppLayout.under(home.path, AppLayout.logDirName);
      installLogging(
          logDir: logDir, level: Level.INFO, format: LogFormat.text);
      Logger('karita.test').info('made');
      expect(Directory(logDir).existsSync(), isTrue);
    });
  });
}
