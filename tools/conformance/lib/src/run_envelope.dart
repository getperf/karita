/// D2: 封筒検証と、拒否コードを返すエラー型（受入ケース05）。
///
/// manifest の19件はそれぞれ期待コードを宣言する。**拒否したという事実ではなくコードを見る。**
/// 「両方とも例外を投げた」で通すと、壊れたJSON を スキーマ違反として弾いても緑になる。そのコードが
/// 言語間の契約である。
library;

import 'dart:convert';

import 'package:karita_contract/envelope.dart';
import 'package:karita_contract/errors.dart';
import 'repo.dart';
import 'report.dart';
import 'package:karita_contract/schema.dart';

const String _dir = 'contracts/fixtures/invalid';

Report runEnvelope(Repo repo) {
  final report = Report('D2 封筒検証（ケース05）');
  final codec = EnvelopeCodec(Contracts.load());
  final manifest = jsonDecode(repo.readString('$_dir/manifest.json')) as Map<String, Object?>;
  final cases = (manifest['cases'] as List).cast<Map<String, Object?>>();

  for (final c in cases) {
    final file = c['file'] as String;
    final expected = c['code'] as String;
    final text = repo.readString('$_dir/$file');

    String? actual;
    try {
      codec.loads(text);
    } on SyncDataError catch (e) {
      actual = e.code;
    }

    if (actual == null) {
      report.fail(file, '拒否されませんでした（期待コード: $expected）');
    } else if (actual != expected) {
      report.fail(file, 'コードが違います\n  expected: $expected\n  actual:   $actual');
    } else {
      report.pass(file);
    }
  }

  if (report.results.isEmpty) {
    report.fail('(manifest)', 'ケースを1件も読み込めませんでした。--repo-root を確認してください。');
  }
  return report;
}
