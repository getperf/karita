/// golden を再生成できること。**凍結の門1 がこれである。**
///
/// 凍結で正本がこちらへ移ると、**golden を書き直せる実装はここだけになる。** 「能力がある」を
/// D1 の緑で示すのでは足りない — D1 が測っているのは読み取り側で、書き出し側が壊れていても
/// 緑のままだからである。ここは**壊れた golden を実際に直せること**を測る。
///
/// 作業は写しの上で行う。**正本の `data/` を試験が書き換えない** — 書き換えると、その run 以降
/// の D1 が「試験が作った期待値」に対して緑になる。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conformance/conformance.dart';
import 'package:test/test.dart';

const String goldenDir = 'contracts/goldens/canonical';

void main() {
  late Directory work;
  late Repo copy;

  /// `data/` をまるごと写す。**元は触らない。**
  setUp(() {
    work = Directory.systemTemp.createTempSync('karita-goldens-');
    // **`Platform.script` を渡さない。** `dart test` ではランナーのスナップショットを指すので、
    // そこから上へ辿っても workspace の `pubspec.yaml` に当たらない。カレントから辿る。
    final source = Repo.dataRoot();
    for (final entry in source.listSync(recursive: true)) {
      final relative = entry.path.substring(source.path.length + 1);
      final target = '${work.path}${Platform.pathSeparator}$relative';
      if (entry is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entry is File) {
        Directory(File(target).parent.path).createSync(recursive: true);
        entry.copySync(target);
      }
    }
    copy = Repo(work);
  });
  tearDown(() {
    try {
      work.deleteSync(recursive: true);
    } on FileSystemException {
      // 消せなくても判定には関わらない。
    }
  });

  Map<String, Object?> manifest() =>
      jsonDecode(copy.readString('$goldenDir/manifest.json'))
          as Map<String, Object?>;

  Map<String, Object?> caseById(String id) =>
      (manifest()['cases'] as List)
          .cast<Map<String, Object?>>()
          .firstWhere((entry) => entry['id'] == id);

  test('正しい golden に対しては何も変わらない', () {
    // **変わらないことが正常である。** 変わるなら、実装か golden のどちらかが動いている。
    final report = updateGoldens(copy, write: false);
    expect(report.failed, equals(0));
    expect(report.results, hasLength(9));
  });

  test('--write でも、変わらないなら書かない', () {
    final before = copy.readString('$goldenDir/manifest.json');
    expect(updateGoldens(copy, write: true).failed, equals(0));
    expect(copy.readString('$goldenDir/manifest.json'), equals(before),
        reason: '変更が無いのに manifest を書き直している');
  });

  test('壊れたバイト列を検出し、書かずに差分だけ出せる', () {
    final path = '$goldenDir/${caseById('002-non-ascii')['canonical']}';
    final original = copy.readBytes(path);
    copy.file(path).writeAsStringSync('壊した');

    final report = updateGoldens(copy, write: false);
    expect(report.failed, equals(1));
    expect(copy.readBytes(path), isNot(equals(original)),
        reason: '書かない指定なのに直してしまっている');
  });

  test('--write で golden と manifest の両方を直せる', () {
    final entry = caseById('002-non-ascii');
    final path = '$goldenDir/${entry['canonical']}';
    final goodHash = entry['sha256'] as String;

    copy.file(path).writeAsStringSync('壊した');
    // manifest の側も一緒に壊す。**片方だけ直る実装を通さない。**
    final broken = manifest();
    (broken['cases'] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((c) => c['id'] == '002-non-ascii')['sha256'] =
        'sha256:0000000000000000000000000000000000000000000000000000000000000000';
    copy
        .file('$goldenDir/manifest.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(broken));

    final report = updateGoldens(copy, write: true);
    expect(report.failed, equals(1), reason: '直した件数が1件のはず');

    expect(caseById('002-non-ascii')['sha256'], equals(goodHash),
        reason: 'manifest の sha256 が元の値に戻っていない');

    // **直した後は D1 が通る。** これが「再生成できる」の意味である。
    expect(runCanonical(copy).failed, equals(0));
  });

  test('入力と description は書き換えない', () {
    // 再生成の対象はバイト列と sha256 だけである。**人が書いたものは触らない** — 触ると
    // 「何を測りたかったか」が実装の出力に置き換わる。
    final entry = caseById('002-non-ascii');
    final inputPath = '$goldenDir/${entry['input']}';
    final inputBefore = copy.readString(inputPath);
    final descriptionBefore = entry['description'];

    copy.file('$goldenDir/${entry['canonical']}').writeAsStringSync('壊した');
    updateGoldens(copy, write: true);

    expect(copy.readString(inputPath), equals(inputBefore));
    expect(caseById('002-non-ascii')['description'], equals(descriptionBefore));
  });

  test('読めない入力からは期待値を作らない', () {
    // 壊れた規則がそのまま golden になるのを防ぐ。落ちたケースは飛ばして書かない。
    final entry = caseById('002-non-ascii');
    final canonicalPath = '$goldenDir/${entry['canonical']}';
    final before = copy.readBytes(canonicalPath);
    copy.file('$goldenDir/${entry['input']}').writeAsStringSync('{ 壊れた JSON');

    final report = updateGoldens(copy, write: true);
    expect(report.failed, equals(1));
    expect(copy.readBytes(canonicalPath), equals(before),
        reason: '読めない入力から期待値を書いてしまっている');
  });
}
