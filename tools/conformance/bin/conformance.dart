/// 引数解析、--repo-root、サブコマンド振り分け、終了コード。
///
/// ```
/// dart run bin/conformance.dart canonical      # D1
/// dart run bin/conformance.dart envelope       # D2
/// dart run bin/conformance.dart sync           # D3
/// dart run bin/conformance.dart all            # 全部
///
/// dart run bin/conformance.dart update-goldens           # 差分を出すだけ
/// dart run bin/conformance.dart update-goldens --write   # 書き換える
/// ```
///
/// `--repo-root <path>` でリポジトリルートを渡せる。既定はパッケージの親であり、実行時の
/// カレントに依存しない。終了コードは全一致で 0、1件でも不一致・エラーがあれば 1。
///
/// **`update-goldens` は規則を意図的に変えたときだけ使う。** 既定は書かずに差分を出すだけで、
/// そのとき「変わる」は赤である — 変わらないことが正常だからである。
library;

import 'dart:io';

import 'package:conformance/conformance.dart';

Future<void> main(List<String> args) async {
  String? repoRoot;
  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--repo-root') {
      if (i + 1 >= args.length) {
        stderr.writeln('--repo-root に値がありません');
        exit(2);
      }
      repoRoot = args[++i];
    } else if (a.startsWith('--repo-root=')) {
      repoRoot = a.substring('--repo-root='.length);
    } else {
      positional.add(a);
    }
  }

  final command = positional.isEmpty ? 'all' : positional.first;
  final repo = repoRoot != null
      ? Repo(Directory(repoRoot))
      : Repo.fromDefault(Platform.script);

  final reports = <Report>[];
  try {
    switch (command) {
      case 'canonical':
        reports.add(runCanonical(repo));
        break;
      case 'envelope':
        reports.add(runEnvelope(repo));
        break;
      case 'sync':
        reports.add(await runSync(repo));
        break;
      case 'all':
        reports.add(runCanonical(repo));
        reports.add(runEnvelope(repo));
        reports.add(await runSync(repo));
        break;
      // **凍結の門1。** 規則を意図的に変えたときだけ使う。既定は差分を出すだけで、
      // 書くのは --write を明示したときである。壊れた実装で再生成すると、golden が
      // 「いまの実装が出すもの」になり、検査が自分自身との照合になって意味を失う。
      case 'update-goldens':
        reports.add(updateGoldens(repo, write: positional.contains('--write') ||
            args.contains('--write')));
        break;
      default:
        stderr.writeln(
            '未知のサブコマンド: $command（canonical|envelope|sync|all|update-goldens）');
        exit(2);
    }
  } on FileSystemException catch (e) {
    stderr.writeln('共有ファイルを読めません: ${e.path}');
    stderr.writeln('--repo-root が data/ を指しているか確認してください。');
    exit(2);
  }

  var failed = 0;
  for (final report in reports) {
    stdout.write(report.render());
    failed += report.failed;
  }
  exit(failed == 0 ? 0 : 1);
}
