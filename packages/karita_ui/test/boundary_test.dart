/// 層の境界を**機械で判定する。**
///
/// 宣言だけでは滲む。`unawaited_futures` を lint で塞ぎ、規則1「文言を書かない」を
/// `example/harness/test/no_wording_test.dart` が歩いて見るのと同じ形である。
///
/// **見るのは import だけである。** 文言の規則はここへ写さない — `karita_ui` は**文言を持つ
/// 側**であり、日本語のリテラルが出ることこそが正しい。
///
/// 塞ぐのは1つ：**`karita_sync` と `karita_platform` を直接 import しないこと**
/// （`非公開資料:ui-state-model.md` §3）。生の DB 接続や同期 Engine を画面が握ると、
/// 合成層が「どの実装を使うか」を決めている意味が消える。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **`karita_platform_flutter` は別の名前である。** 接頭辞では切らない。
const List<String> _forbidden = ['karita_sync', 'karita_platform'];

void main() {
  test('lib/ が karita_sync と karita_platform を import しない', () {
    final offenders = <String>[];
    final root = Directory('lib');
    expect(root.existsSync(), isTrue, reason: 'lib/ を lib/ から見つけられない');

    var scanned = 0;
    final subdirectories = <String>{};
    for (final entry in root.listSync(recursive: true)) {
      if (entry is Directory) subdirectories.add(entry.path);
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      scanned++;
      final lines = entry.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final package in _importedPackages(lines[i])) {
          if (_forbidden.contains(package)) {
            offenders.add('${entry.path}:${i + 1}  package:$package');
          }
        }
      }
    }

    // **走査していないのに緑にならないこと。** 相対パスの解決が変われば 0 件で通ってしまう。
    // **feature ごとのディレクトリへ入れた後も歩けること**を含めて見る（`listSync` は再帰）
    // ので、下限は入れ子にした後の本数で置く。生成物を含めて 19 本ある（2026-09-17、図書館
    // 管理の画面を入れた時点）。**下限を下げるのは package が割れたときだけである。**
    expect(scanned, greaterThanOrEqualTo(19), reason: 'lib/ を走査できていない');

    // **1段以上の入れ子を実際に歩いていること。** 上の下限は平置きのままでも満たせる。
    expect(
      subdirectories,
      isNotEmpty,
      reason: 'lib/src/ の下のディレクトリを歩いていない',
    );

    expect(
      offenders,
      isEmpty,
      reason: '生の DB 接続と同期 Engine は合成層（karita_app）の持ち物である。\n'
          '${offenders.join('\n')}',
    );
  });

  test('pubspec の dependencies に入っていない', () {
    // **dev_dependencies には入っている。** 試験の足場が `compose()` へ渡す `AppPaths` と
    // `DeviceSettings` の型を名前で呼ぶためで、製品の依存ではない。
    final source = File('pubspec.yaml').readAsStringSync();
    final start = source.indexOf(RegExp(r'^dependencies:$', multiLine: true));
    final end = source.indexOf(
      RegExp(r'^dev_dependencies:$', multiLine: true),
    );
    expect(start, isNonNegative, reason: 'pubspec.yaml に dependencies が無い');
    expect(end, greaterThan(start), reason: 'pubspec.yaml に dev_dependencies が無い');

    final declared = source.substring(start, end);
    for (final package in _forbidden) {
      expect(
        declared.contains(RegExp('^  $package:', multiLine: true)),
        isFalse,
        reason: '$package が dependencies に居る',
      );
    }
  });

  test('判定そのものが働くこと', () {
    // **検査が検査になっていることを検査する。** 常に空を返す実装でも上の試験は緑になる。
    expect(_importedPackages("import 'package:karita_sync/karita_sync.dart';"),
        ['karita_sync']);
    expect(_importedPackages("export 'package:karita_platform/x.dart';"),
        ['karita_platform']);
    expect(_importedPackages('  import "package:karita_sync/a.dart" as s;'),
        ['karita_sync']);
    // **接頭辞で切らない。** `karita_platform_flutter` は別の package である。
    expect(_importedPackages("import 'package:karita_platform_flutter/a.dart';"),
        ['karita_platform_flutter']);
    // doc コメントの中の import は import ではない。
    expect(_importedPackages("/// import 'package:karita_sync/a.dart';"), isEmpty);
    expect(_importedPackages("// import 'package:karita_sync/a.dart';"), isEmpty);
    // 相対 import は package を名乗らない。
    expect(_importedPackages("import 'composition.dart';"), isEmpty);
  });
}

/// 1行から `package:` の package 名を拾う。
///
/// **`import` / `export` で始まる行だけを見る。** doc コメントは `///` で始まるので、行頭の
/// 判定だけで落ちる — `no_wording_test.dart` が状態を持って歩くのは、文字列リテラルと
/// コメントが行の途中で入れ替わるからであって、ここはそうならない。
List<String> _importedPackages(String line) {
  final code = line.trimLeft();
  if (!code.startsWith('import ') && !code.startsWith('export ')) return const [];
  return [
    for (final match in RegExp(r'''package:([a-z0-9_]+)/''').allMatches(code))
      match.group(1)!,
  ];
}
