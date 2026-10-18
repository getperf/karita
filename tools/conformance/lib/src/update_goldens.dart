/// golden と manifest を書き直す口。**凍結の門1。**
///
/// 移送元は book-sync-model の `pytest --update-goldens`（`tests/test_goldens.py`）。凍結で
/// 正本がこちらへ移ると、**golden を再生成できる実装がここだけになる。** 口が無いまま凍結すると、
/// 契約を意図的に変えたい日に「新しい期待値を作る手段がどこにも無い」状態になる。
///
/// ## 使ってよい場面は一つだけである
///
/// **規則を意図的に変えたときだけ使う。** 壊れた実装で再生成すれば、golden は「いまの実装が
/// 出すもの」になり、検査が自分自身との照合になって意味を失う。D1 が毎回バイト一致を測って
/// いるのは、**実装が過去の自分とずれないこと**を見るためであって、実装に合わせて期待値を
/// 動かすためではない。
///
/// だから既定では**書かずに差分だけを出す。** 書くのは `--write` を明示したときで、そのときも
/// 何を書き換えたかを列挙する。生成されたバイト列を目で確認してからコミットすること。
///
/// ## 入力は書き換えない
///
/// 書き換えるのは `*.canonical`（正準化後のバイト列）と manifest の `sha256` だけである。
/// `*.input.json` と各ケースの `description` は**人が書いたもの**で、再生成の対象ではない。
/// ここを触ると「何を測りたかったか」が実装の出力に置き換わる。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:karita_contract/canonical.dart' as canonical;
import 'package:karita_contract/karita_contract.dart';

import 'report.dart';
import 'repo.dart';

const String goldenDir = 'contracts/goldens/canonical';

/// 1件ぶんの再生成の結果。
class GoldenUpdate {
  final String id;

  /// バイト列が変わるか。
  final bool bytesChanged;

  /// manifest の sha256 が変わるか。
  final bool hashChanged;

  final String beforeHash;
  final String afterHash;

  const GoldenUpdate({
    required this.id,
    required this.bytesChanged,
    required this.hashChanged,
    required this.beforeHash,
    required this.afterHash,
  });

  bool get changed => bytesChanged || hashChanged;
}

/// golden を作り直す。`write` が false なら**読むだけ**で、何が変わるかを返す。
///
/// 戻り値の [Report] は D1 と同じ形で、`fail` は「変わる」を意味する — 既定の実行
/// （`--write` なし）では**変わることが赤**である。再生成が要らないなら全件が緑になる。
Report updateGoldens(Repo repo, {required bool write}) {
  final report = Report(write ? 'golden の再生成（書き込み）' : 'golden の再生成（差分のみ）');
  final manifestPath = '$goldenDir/manifest.json';
  final manifest =
      jsonDecode(repo.readString(manifestPath)) as Map<String, Object?>;
  final cases = (manifest['cases'] as List).cast<Map<String, Object?>>();

  final updates = <GoldenUpdate>[];
  for (final entry in cases) {
    final id = entry['id'] as String;
    try {
      final inputText = repo.readString('$goldenDir/${entry['input']}');
      // **入力は golden の読み取りと同じ経路を通す。** 整数/浮動小数の読み分けと重複キーの
      // 検出を飛ばすと、ここだけが通してしまう入力から期待値が作られる。
      final produced = canonical.dumps(loadsJson(inputText));
      final producedHash =
          '${canonical.hashPrefix}${canonical.sha256Hex(produced)}';

      final canonicalPath = '$goldenDir/${entry['canonical']}';
      final existing = repo.exists(canonicalPath)
          ? repo.readBytes(canonicalPath)
          : Uint8List(0);
      final bytesChanged = firstDiff(produced, existing) != -1;
      final beforeHash = entry['sha256'] as String;
      final hashChanged = beforeHash != producedHash;

      final update = GoldenUpdate(
        id: id,
        bytesChanged: bytesChanged,
        hashChanged: hashChanged,
        beforeHash: beforeHash,
        afterHash: producedHash,
      );
      updates.add(update);

      if (!update.changed) {
        report.pass(id);
        continue;
      }
      if (write) {
        repo.file(canonicalPath).writeAsBytesSync(produced);
        entry['sha256'] = producedHash;
      }
      report.fail(
        id,
        '${write ? '書き換えた' : '書き換わる'}'
        '${bytesChanged ? '（バイト列）' : ''}${hashChanged ? '（sha256）' : ''}\n'
        '  before: $beforeHash\n'
        '  after:  $producedHash',
      );
    } on SyncDataError catch (exc) {
      // **落ちたケースは飛ばして書かない。** 読めない入力から期待値を作ると、壊れた規則が
      // そのまま golden になる。
      report.fail(id, '正準化で拒否されました。書き換えません: $exc');
    }
  }

  if (updates.isEmpty) {
    report.fail('(manifest)',
        'ケースを1件も読み込めませんでした。--repo-root を確認してください。');
    return report;
  }

  if (write && updates.any((u) => u.changed)) {
    // **manifest は最後に一度だけ書く。** ケースごとに書くと、途中で落ちたときに
    // 「バイト列は新しいが sha256 は古い」manifest が残る。
    repo.file(manifestPath).writeAsStringSync(_renderManifest(manifest));
  }
  return report;
}

/// manifest を書き戻す。**正準化ではなく、人が読む JSON として書く。**
///
/// manifest は golden の索引であって golden そのものではない。バイト列の契約はケースの
/// `*.canonical` が持つので、ここは差分が読める形（2スペース字下げ・末尾改行）にする。
String _renderManifest(Map<String, Object?> manifest) =>
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
