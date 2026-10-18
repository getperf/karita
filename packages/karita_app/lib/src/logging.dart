/// ログの sink と行の書式。**接ぐのはここだけである。**
///
/// ②③ と業務は `Logger` を作るだけで sink も書式も知らない。転送・保管先を port にしたのと
/// 同じ線である。正本は `非公開資料:logging-and-diagnostics.md`。
///
/// **ファイルは1本である。** 背面同期を持たないので、書き手の isolate は1つしかない。
/// **isolate を足したら、その入口でも [installLogging] を呼ぶ** — `Logger.root` は isolate
/// ごとに別なので、呼ばなければその isolate のログは1行も出ない。
///
/// **項目を組む場所は1つで、書式で分かれるのは最後の1行だけである。** 組む場所を2つにすると、
/// 片方にだけ足した鍵が生まれ、「どちらの書式も同じ項目を持つ」が崩れる。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:karita_platform/karita_platform.dart';
import 'package:logging/logging.dart';

/// 行の書式。**既定は [text]** — 既定の読み手は人である（`tools/logtail.ps1` で目視する）。
enum LogFormat { text, jsonl }

/// ビルド時の既定。**`device.json` にあればそちらを採る**（決定 H）。
const String defineLogLevel = String.fromEnvironment('LOG_LEVEL');
const String defineLogFormat = String.fromEnvironment('LOG_FORMAT');

/// 水準と書式が決まった結果。
///
/// **落とした値を持ち歩く。** 黙って既定にすると、水準を上げたつもりの実機で「出ていない」と
/// 「その値で動いていない」を区別できない。呼ぶ側が最初の1行（`log.setting.ignored`）に出す。
class LoggingChoice {
  final Level level;
  final LogFormat format;

  /// 読めなかった値。`{'key': 'log.level', 'value': 'LOUD', 'source': 'device.json'}`。
  final List<Map<String, Object?>> ignored;

  const LoggingChoice(this.level, this.format, {this.ignored = const []});
}

/// 水準と書式を決める。**`device.json` ＞ `--dart-define` ＞ 既定**の一方向である。
///
/// 強弱を1方向に固定しないと、実機で「どちらの値で動いているか」が読めない。
LoggingChoice resolveLogging({
  String? configLevel,
  String? configFormat,
  String defineLevel = defineLogLevel,
  String defineFormat = defineLogFormat,
}) {
  final ignored = <Map<String, Object?>>[];

  Level? level;
  for (final (source, raw) in [
    ('device.json', configLevel),
    ('--dart-define', defineLevel),
  ]) {
    if (raw == null || raw.trim().isEmpty) continue;
    final parsed = parseLevel(raw);
    if (parsed == null) {
      ignored.add({'key': 'log.level', 'value': raw, 'source': source});
      continue;
    }
    level = parsed;
    break;
  }

  LogFormat? format;
  for (final (source, raw) in [
    ('device.json', configFormat),
    ('--dart-define', defineFormat),
  ]) {
    if (raw == null || raw.trim().isEmpty) continue;
    final parsed = parseFormat(raw);
    if (parsed == null) {
      ignored.add({'key': 'log.format', 'value': raw, 'source': source});
      continue;
    }
    format = parsed;
    break;
  }

  return LoggingChoice(level ?? Level.INFO, format ?? LogFormat.text,
      ignored: ignored);
}

/// `package:logging` の水準名を引く。**大文字小文字は問わない。**
Level? parseLevel(String name) {
  final wanted = name.trim().toUpperCase();
  for (final level in Level.LEVELS) {
    if (level.name == wanted) return level;
  }
  return null;
}

LogFormat? parseFormat(String name) => switch (name.trim().toLowerCase()) {
      'text' => LogFormat.text,
      'jsonl' => LogFormat.jsonl,
      _ => null,
    };

StreamSubscription<LogRecord>? _installed;

/// sink を据える。**合成より先に立てる** — `compose()` が落ちたときにも記録が要る。
///
/// 二度呼べば前の sink を外す。**外さずに重ねると、同じ行が2回書かれる。**
void installLogging({
  required String logDir,
  String file = AppLayout.logFile,
  required Level level,
  required LogFormat format,
}) {
  uninstallLogging();
  Logger.root.level = level;
  final sink = File(AppLayout.under(logDir, file));
  Directory(logDir).createSync(recursive: true);

  _installed = Logger.root.onRecord.listen((record) {
    final line = formatLine(logFields(record), format);
    try {
      // **同期で書く。** `onRecord` は同期コールバックである。`Future` を作ると
      // `discarded_futures` に掛かり、順序も崩れる（決定 F）。
      sink.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } on FileSystemException {
      // **アプリを止めない。** ディスク満杯・権限で書けないことはある。これを `doctor` の
      // 所見にするかは未決である（`非公開資料:logging-and-diagnostics.md`）。
    }
  });
}

/// sink を外す。**試験と、isolate を畳むときのためにある。**
void uninstallLogging() {
  final installed = _installed;
  _installed = null;
  // `cancel()` は同期に解けるが `Future` を返す。**待たない** — 外した時点で `onRecord` は
  // もう届かない。
  if (installed != null) unawaited(installed.cancel());
}

/// 1件ぶんの項目。**両方の書式がこれを共有する。**
///
/// **付随値をどこから読むか。** `_log.info('sync.run.begin', {'pending': 3})` と書くと、
/// `package:logging` は第2引数を `LogRecord.error` に入れる（`object` ではない）。**②③ が書く
/// 形はこれである**ので、`error` が `Map` なら付随値として読む。`Map` でなければ例外として
/// 末尾の `error` に置く。
Map<String, Object?> logFields(LogRecord record) {
  final object = record.object;
  final raw = record.error;
  final attached = object is Map
      ? object
      : raw is Map
          ? raw
          : null;
  final error = raw is Map ? null : raw;

  return <String, Object?>{
    'at': utcMillis(record.time),
    'level': record.level.name,
    'logger': record.loggerName,
    'event': record.message,
    if (attached != null)
      for (final entry in attached.entries)
        // **`null` は項目ごと落とす。** 「渡していない」と「`null` を渡した」を行から
        // 区別しない。
        if (entry.value != null) '${entry.key}': entry.value,
    if (error != null) 'error': '$error',
  };
}

/// UTC の ISO 8601。**ミリ秒まで、末尾 `Z`。**
String utcMillis(DateTime at) {
  final text = at.toUtc().toIso8601String();
  final dot = text.indexOf('.');
  if (dot < 0) return '${text.substring(0, text.length - 1)}.000Z';
  return '${text.substring(0, dot + 4)}Z';
}

/// 組んだ項目を1行にする。**書式で分かれるのはここだけである。**
String formatLine(Map<String, Object?> fields, LogFormat format) =>
    switch (format) {
      LogFormat.text => formatTextLine(fields),
      LogFormat.jsonl => formatJsonLine(fields),
    };

/// 位置で出す項目。**残りは `鍵=値` で続く。**
const List<String> _positional = ['at', 'level', 'logger', 'event'];

/// `2026-09-13T04:05:06.123Z INFO    karita.sync.engine sync.run.begin pending=3`
String formatTextLine(Map<String, Object?> fields) {
  final buffer = StringBuffer()
    // 水準は7桁へ左詰めで揃える（`WARNING` が最長）。
    ..write('${fields['at']} ')
    ..write('${fields['level']}'.padRight(7))
    ..write(' ${fields['logger']} ')
    ..write(_escaped('${fields['event']}'));
  for (final entry in fields.entries) {
    if (_positional.contains(entry.key)) continue;
    if (entry.value == null) continue;
    buffer.write(' ${entry.key}=${_escaped('${entry.value}')}');
  }
  return buffer.toString();
}

/// `{"at":"…","level":"INFO","logger":"…","event":"…","pending":3}`
///
/// **付随値は平らに置く。** 入れ子にしない — `jq` も `grep` も浅いほうが短く書ける。
String formatJsonLine(Map<String, Object?> fields) => jsonEncode(
      {
        for (final entry in fields.entries)
          if (entry.value != null) entry.key: entry.value,
      },
      // **書けない値でも行を落とさない。** 文字列にしてでも記録を残す。
      toEncodable: (value) => '$value',
    );

/// 値に空白・`=`・`"`・改行が含まれるときは `"` で囲む。
///
/// **改行は `\n` へ畳む。** 1行1件を書式が壊さない。`"` と `\` は `\` で逃がしてから畳むので、
/// 囲みの中の `\n` は実際の改行のことだと読める。
String _escaped(String raw) {
  final quote = raw.contains(' ') ||
      raw.contains('=') ||
      raw.contains('"') ||
      raw.contains('\n') ||
      raw.contains('\r');
  var value = raw;
  if (quote) value = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  value = value
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\n');
  return quote ? '"$value"' : value;
}
