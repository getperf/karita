/// D1: 正準化（`dumps`、`payloadHash`）と golden manifest の突合。受入ケース12。
///
/// 同じ入力から Python と Dart が同じバイト列を作ることを確かめる。`jsonEncode` の出力を目で見て
/// 「同じに見える」で通さない。キー順と非ASCIIの差はバイト列でしか出ないため、ゴールデンの
/// 生バイト列と突き合わせ、`sha256` まで一致させる。
library;

import 'dart:convert';

import 'package:karita_contract/canonical.dart' as canonical;
import 'package:karita_contract/errors.dart';
import 'package:karita_contract/json_reader.dart';
import 'repo.dart';
import 'report.dart';

const String _dir = 'contracts/goldens/canonical';

Report runCanonical(Repo repo) {
  final report = Report('D1 正準化（ケース12）');
  final manifest = jsonDecode(repo.readString('$_dir/manifest.json')) as Map<String, Object?>;
  final cases = (manifest['cases'] as List).cast<Map<String, Object?>>();

  for (final c in cases) {
    final id = c['id'] as String;
    try {
      final inputText = repo.readString('$_dir/${c['input']}');
      final expected = repo.readBytes('$_dir/${c['canonical']}');
      // ゴールデンの入力も、整数/浮動小数の読み分けと重複キー検出を持つ読み取りを通す。
      final value = loadsJson(inputText);

      final actual = canonical.dumps(value);
      final diff = firstDiff(actual, expected);
      if (diff != -1) {
        report.fail(
          id,
          'バイト列が一致しません（位置 $diff）\n'
          '  expected: ${showBytes(expected)}\n'
          '  actual:   ${showBytes(actual)}',
        );
        continue;
      }

      final expectedHash = c['sha256'] as String;
      final actualHash = '${canonical.hashPrefix}${canonical.sha256Hex(actual)}';
      if (actualHash != expectedHash) {
        report.fail(id, 'sha256 が一致しません\n  expected: $expectedHash\n  actual:   $actualHash');
        continue;
      }

      report.pass(id);
    } on SyncDataError catch (e) {
      report.fail(id, '正準化で拒否されました: $e');
    }
  }

  if (report.results.isEmpty) {
    report.fail('(manifest)', 'ケースを1件も読み込めませんでした。--repo-root を確認してください。');
  }
  return report;
}
