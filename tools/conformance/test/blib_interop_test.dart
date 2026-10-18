/// **P1b の受入 — 相互運用。** Python が作った `.blib` を Dart が復元する。
///
/// `.blib` が zip + SQLite で言語中立である以上、これは実現可能である。成立すれば **B5a で実
/// Drive を通した資産が、そのまま Dart 側の正しさの根拠になる** — 形式の解釈違いを実機を
/// 待たずに捕まえられる。
///
/// 通るのは**両側とも製品の経路**である。Python は `bsync export`、Dart は
/// `restoreFromBackup` で、片方だけの裏口を作らない。
///
/// ## 往復は終わった（2026-09-13）
///
/// **`Dart が作った .blib を Python が復元できる` は消した。原理的に成立しなくなったためである。**
///
/// 契約の正本は 2026-09-02 に karita-core へ移り、`../book-sync-model` は凍結した（編集しない・
/// 実行はする）。**karita-core がマイグレーションを1本足した時点で、台帳の版が Python より
/// 前へ出る。** `.blib` の manifest は `schema_version` を運び、復元側は
/// `schemaVersion > latest` を `backup-schema` で止める（`backup_archive.dart`）。これは正しい
/// 防御である — migration は前へしか進めないので、止めなければ「読めたが表が足りない」状態に
/// なる。凍結側は永久に 9 のままなので、**Dart → Python は今後どの版でも通らない。**
///
/// 実測（0010 を足した直後）:
///
/// ```text
/// bsync --profile android-b import from-dart.blib --yes --json
/// {"ok": false, "error": {"code": "backup-schema",
///  "message": "新しい schema のバックアップです（この版が扱えるのは 9、ファイルは 10）。"}}
/// ```
///
/// **逆向きは残る。** 古い `.blib` は製品の経路で通る（復元後に migration が前へ進める）ので、
/// **Python(9) → Dart(現在) は成立し続ける。** これは版が離れるほど価値が上がる検査である —
/// 「凍結時点の形を今も読めるか」を測っている。
///
/// **したがって版の一致はもう受入ではない。** `schema_version` は「Dart 以下であること」だけを
/// 見る。一致を要求すると、karita-core が DDL を1本足すたびにこの試験が赤くなり、**測りたい
/// 後方互換ではなく版の差を報告する**ことになる。
///
/// **代償を承知の上である。** README「凍結後に残る危険」が言うとおり、契約のずれを検出する
/// ものはこれと `drive_interop_test` しか無く、そのうち Dart 側の変更を捕まえる方向がこれで
/// 半分になった。→ P5 の分館管理の追従（非公開資料）
///
/// 正本（`../book-sync-model`）と `uv` が無ければ**この試験だけを飛ばす。** karita-core の
/// 単体試験がモデル repo の存在を要求するようになると、自己検査の「モデル repo を要さない」が
/// 崩れる。飛ばしたことは理由付きで見えるようにする。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conformance/src/harness.dart';
import 'package:conformance/src/repo.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String t0 = '2026-08-04T09:00:00Z';
const String t1 = '2026-08-05T09:00:00Z';
const String t2 = '2026-08-06T09:00:00Z';

const String sep = '/';

/// 凍結した参照実装の場所。**karita-core の隣にある前提である。**
Directory get modelRoot =>
    Directory('${Repo.coreRoot().parent.path}${Platform.pathSeparator}book-sync-model');

String? skipReason() {
  if (!modelRoot.existsSync()) {
    return '正本 (${modelRoot.path}) がありません。相互運用は測れません。';
  }
  final probe = Process.runSync('uv', ['--version'], runInShell: true);
  if (probe.exitCode != 0) {
    return 'uv を実行できません。Python 側の CLI を呼べません。';
  }
  return null;
}

void main() {
  final skip = skipReason();
  late Directory work;
  late Directory pyHome;
  late Directory drop;

  String path(Directory base, String name) =>
      '${base.path}${Platform.pathSeparator}$name';

  /// Python 側の CLI。**製品の経路をそのまま呼ぶ。**
  ///
  /// 入出力を UTF-8 に固定する。Windows の既定コードページ（cp932）のままだと、CLI が返す
  /// 日本語の JSON が化けて読めなくなる。**これは形式の問題ではなく、この試験が子プロセスの
  /// 出力をどう読むかの問題である。**
  /// Python 側の CLI。**製品の経路をそのまま呼ぶ。**
  ///
  /// [allowFailure] は「落ちること自体を測る」ときだけ真にする。既定で落ちたら試験を止めるのは、
  /// 失敗を黙って通すと後続の `expect` が別の理由で緑になりうるためである。
  ProcessResult bsync(List<String> args, {bool allowFailure = false}) {
    final result = Process.runSync(
      'uv',
      ['run', 'bsync', ...args],
      workingDirectory: modelRoot.path,
      environment: {'BLIB_HOME': pyHome.path, 'PYTHONIOENCODING': 'utf-8'},
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (!allowFailure) {
      expect(result.exitCode, equals(0),
          reason: 'bsync ${args.join(' ')} が失敗しました:\n'
              '${result.stderr}\n${result.stdout}');
    }
    return result;
  }

  Map<String, Object?> bsyncJson(List<String> args) =>
      jsonDecode(bsync(args).stdout as String) as Map<String, Object?>;

  int pyRows(String profile, String table) {
    final db = '${pyHome.path}${Platform.pathSeparator}profiles'
        '${Platform.pathSeparator}$profile${Platform.pathSeparator}library.db';
    final probe = SqliteDb.open(db);
    try {
      return probe.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;
    } finally {
      probe.close();
    }
  }

  setUp(() {
    if (skip != null) return;
    work = Directory.systemTemp.createTempSync('karita-interop-');
    pyHome = Directory(path(work, 'pyhome'))..createSync(recursive: true);
    drop = Directory(path(work, 'drop'))..createSync(recursive: true);
  });
  tearDown(() {
    if (skip != null) return;
    try {
      work.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows では WAL のハンドルが残って消せないことがある。判定には関わらない。
    }
  });

  test('Python が作った .blib を Dart が復元できる', () async {
    final fixture = [
      modelRoot.path, 'contracts', 'fixtures', 'sync', '03-concurrent-loan.json',
    ].join(Platform.pathSeparator);

    bsync(['init', 'db', '--profile', 'windows-a', '--now', t0]);
    bsync(['--profile', 'windows-a', 'config', 'set', 'transport.dir', drop.path,
      '--now', t0]);
    bsync(['--profile', 'windows-a', 'admin', 'fixture', 'seed', '--case', fixture,
      '--step', '0', '--now', t0, '--json']);

    final blib = path(work, 'from-python.blib');
    final exported = bsyncJson(['--profile', 'windows-a', 'export', '--out', blib,
      '--now', t1, '--json']);
    final manifest = exported['manifest'] as Map<String, Object?>;
    final expected = (manifest['counts'] as Map).cast<String, Object?>();

    expect(File(blib).existsSync(), isTrue);
    expect(manifest['backup_version'], equals(backupVersion),
        reason: '形式の版が両実装で一致しない');
    // **一致は要求しない**（2026-09-13）。凍結側は台帳の版が前へ進まないので、karita-core が
    // DDL を足すたびに差が開く。ここで測りたいのは**古い `.blib` を今も読めること**であって、
    // 版が揃っていることではない。上を越えていたら復元側が `backup-schema` で止めるので、
    // 「Dart 以下であること」だけを見る。
    expect(manifest['schema_version'], lessThanOrEqualTo(latestVersion()),
        reason: '凍結側の台帳の版が Dart を追い越した。'
            '`.blib` の復元は backup-schema で止まる');

    // Dart 側で復元する。**製品の経路**（宣言としての復元）を通す。
    final harness = Harness.create(Contracts.load(), prefix: 'karita-interop-dart-');
    try {
      final device = harness.device('android-b');
      final outcome = await device.engine.restoreFromBackup(now: t2, path: blib);

      expect(outcome.counts.map((k, v) => MapEntry(k, v as Object?)), equals(expected),
          reason: 'Python が数えた件数と Dart が数えた件数が違う');
      expect(outcome.manifest['source_profile'], equals('windows-a'));
      // 作成元の素性を名乗らない。
      expect(getState(device.db, stateDeviceId), equals(device.deviceId));
      expect(getState(device.db, stateProfileName), equals('android-b'));
      // 復元は宣言なので、Dart 側の保管先に起点が1つ立つ。
      expect(outcome.declared, isTrue);
      expect(outcome.seq, equals(firstSeq));
    } finally {
      harness.dispose();
    }
  }, skip: skip);

  test('Dart が作った .blib を Python は復元できない — 往復は終わった', () async {
    // **これは「壊れたこと」ではなく「防御が効いていること」を測る試験である。**
    //
    // 2026-09-13 に台帳の版が Dart 10 / Python 9 になり、逆向きは原理的に成立しなくなった。
    // 黙って消すと、後で誰かが「なぜ往復を測っていないのか」を調べ直すことになる。**代わりに、
    // 止まることを受入にする。**
    //
    // **仕掛けでもある。** 凍結側に migration を入れて版が揃えば、この試験は赤くなる。そのとき
    // 往復を戻すかどうかを改めて決めることになる — 静かに戻ってしまうより良い。
    final harness = Harness.create(Contracts.load(), prefix: 'karita-interop-dart-');
    final blib = path(work, 'from-dart.blib');
    try {
      final device = harness.device('windows-a');
      final codec = EnvelopeCodec(harness.contracts);
      device.engine.emitLocal([
        codec.build(
          eventId: harness.uuid(),
          deviceId: device.deviceId,
          createdAtUtc: t0,
          entityType: 'book',
          entityId: 'aaaaaaaa-0101-4000-8000-000000000001',
          operation: 'upsert',
          baseVersion: 0,
          resultVersion: 1,
          payload: {'title': 'リファクタリング', 'authors': ['Martin Fowler']},
        ),
      ]);
      await device.engine.exportBackup(now: t1, outPath: blib);
    } finally {
      harness.dispose();
    }

    bsync(['init', 'db', '--profile', 'android-b', '--now', t0]);
    bsync(['--profile', 'android-b', 'config', 'set', 'transport.dir', drop.path,
      '--now', t0]);
    expect(pyRows('android-b', 'books'), equals(0));

    final result = bsync(['--profile', 'android-b', 'import', blib, '--yes',
      '--now', t2, '--json'], allowFailure: true);
    expect(result.exitCode, isNot(equals(0)),
        reason: '凍結側が Dart の .blib を受け入れた。台帳の版が揃ったのなら往復を戻すか決め直す');

    // **落ちたときの JSON は stderr に出る。** 標準出力だけを見ると空になる。
    final reportedText = '${result.stdout}'.trim().isEmpty
        ? '${result.stderr}'.trim()
        : '${result.stdout}'.trim();
    final reported = jsonDecode(reportedText) as Map<String, Object?>;
    final error = (reported['error'] as Map).cast<String, Object?>();
    expect(error['code'], equals('backup-schema'),
        reason: '止まったが理由が版ではない。別の非互換が入った可能性がある: $reportedText');

    // **業務データは1行も入っていない。** 途中まで書いて止まる形ではない。
    expect(pyRows('android-b', 'books'), equals(0),
        reason: '弾いたはずの .blib から行が入った');
  }, skip: skip);
}
