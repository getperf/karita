/// D3: 適用判定表の突合。ケース 01,02,03,04,06,11,13,14,16。
///
/// `contracts/fixtures/sync/*.json`（入力）と隣の `*.expect.json`（期待）を Python と同じ形で
/// 読み、**`karita_sync` の driver**（実物の ②）で `script` を回して、集約・conflicts・
/// pending_events・applied_events・outbox を突き合わせる。写しは作らない。
///
/// **P1a でインメモリの模擬（旧 `apply.dart`）を置き換えた。** 模擬を残すと Dart の ② が二つに
/// なり、`dart/` を残すと ① が二つになるのと同じ形になる。ここが駆動するのは SQLite と転送を
/// 通る製品の経路であり、Python 側の横断ランナーが CLI 呼び出しへ写しているものと同じである。
///
/// ケース07〜10 は転送の状態機械（lease・認可喪失・重複リモート）を要するので P2 で閉じる。
library;

import 'dart:convert';

import 'package:karita_contract/errors.dart';
import 'package:karita_contract/json_reader.dart';
import 'package:karita_contract/schema.dart';
import 'package:karita_sync/karita_sync.dart';

import 'repo.dart';
import 'report.dart';
import 'world.dart';

const String _dir = 'contracts/fixtures/sync';

const List<String> _cases = [
  '01-duplicate-event.expect.json',
  '02-gap-fill.expect.json',
  '03-concurrent-loan.expect.json',
  '04-conflict-resolution.expect.json',
  '06-unsupported-schema.expect.json',
  // 故障注入。**転送先そのものを見ないと表明できないものが混じる**（`remote`）— 再送が重複を
  // 作ったかどうかは DB に現れない。
  '07-duplicate-remote.expect.json',
  '08-ambiguous-upload.expect.json',
  '09-expired-lease.expect.json',
  '10-auth-loss.expect.json',
  '11-bulk-replay.expect.json',
  // 同じ入力を、整列を壊した一覧で再走行する。**判定表は到着順に依存しない。**
  '11-bulk-replay-shuffled.expect.json',
  // 自動解決（LWW）。13 は `resolve --take auto` の決定的勝者、14 は `conflict.auto_resolve=lww` を
  // 立てた `sync run` の自動収束。どちらもケース03 の入力を再利用する。
  '13-deterministic-lww.expect.json',
  '14-auto-resolve-converge.expect.json',
  // 受理する版が集合であること。**版2でだけ宣言された entityType を含む。** 版番号だけを変えた
  // 封筒では、封筒を読み直す入口が発行版の enum を見ているという穴を通過してしまう。言語間で
  // 同じ穴が開いていたため、両方をこのケースで縛る。
  '16-mixed-schema-versions.expect.json',
];

Future<Report> runSync(Repo repo) async {
  final report = Report('D3 適用判定（expect 突合）');
  final contracts = Contracts.load();

  for (final file in _cases) {
    final id = file.replaceAll('.expect.json', '');
    try {
      final fails = await _runCase(repo, contracts, file);
      if (fails.isEmpty) {
        report.pass(id);
      } else {
        report.fail(id, fails.join('\n'));
      }
    } on SyncDataError catch (e) {
      report.fail(id, 'script の実行で拒否されました: $e');
    }
  }

  if (report.results.isEmpty) {
    report.fail('(cases)', 'ケースを1件も読み込めませんでした。--repo-root を確認してください。');
  }
  return report;
}

Future<List<String>> _runCase(
    Repo repo, Contracts contracts, String expectFile) async {
  final expect = jsonDecode(repo.readString('$_dir/$expectFile')) as Map<String, Object?>;
  // ケースファイルは重複キーを拒否する読み取りを通す。`jsonDecode` は後勝ちで黙って通す。
  final input = FixtureCase.parse(
    loadsJson(repo.readString('$_dir/${expect['input']}'),
        label: 'ケースファイル ${expect['input']}'),
    label: '${expect['input']}',
  );

  final world = CaseWorld.create(contracts);
  try {
    return await world.driver.runScript(input, expect['script'] as List);
  } finally {
    world.dispose();
  }
}
