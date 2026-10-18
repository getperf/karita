/// 時刻の書式。同期エンジンが要る分だけを置く。
///
/// RFC3339 秒精度・Z終端に固定するのは、**文字列の昇順が時刻の昇順と一致する**ためである。
/// lease の失効判定と自動解決の窓は SQL の文字列比較で行うので、この性質が崩れると期限が
/// 効かなくなる。
///
/// 移送元: book-sync-model の `src/contracts/ids.py`（同期が要る分だけ）。
library;

import 'errors.dart';

final RegExp rfc3339ZRe =
    RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$');

String parseNow(String value) {
  if (!rfc3339ZRe.hasMatch(value)) {
    throw SyncDataError(
      'now は RFC3339 秒精度・Z終端で指定してください（例 2026-08-04T09:00:00Z）: $value',
      code: 'timestamp',
    );
  }
  return value;
}

/// 時刻を動かす。lease の期限と、自動解決の反復ガードの窓を作るために要る。
String shiftSeconds(String value, int seconds) {
  final moment = DateTime.parse(parseNow(value)).toUtc();
  return formatUtc(moment.add(Duration(seconds: seconds)));
}

String formatUtc(DateTime moment) {
  final utc = moment.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}'
      'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}
