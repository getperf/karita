/// 保管先をローカルディレクトリに見立てる `BackupStorePort` の実装。
///
/// **試験側が持つ。** `DirTransport` と同じ理由でここにある — 実 Drive の実装は
/// `karita_platform` が P2 で持ち、`karita_sync` は port の定義しか持たない。
///
/// **`dir` は利便のためではない。** 受入ケースの大半はネットワークを要さない。これが無ければ、
/// 一覧の除外規則・重複・途中 upload の扱いを実 Drive でしか試せなくなる。
///
/// 保管先は転送先と同じ場所を使う。名前で棲み分ける — 封筒は `event-`、バックアップは
/// `backup-`、upload 中は `incoming-`、世代の起点は `baseline-` である。
library;

import 'dart:io';

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';

class DirBackupStore implements BackupStorePort {
  final Directory root;

  DirBackupStore(this.root);

  @override
  String get kind => transportDir;

  File _file(String name) =>
      File('${root.path}${Platform.pathSeparator}$name');

  /// `incoming-` へ書いてから `backup-` へ改名する。
  ///
  /// `dir` では改名が原子的なので二段にする必要は無い。**それでも同じ形にする** — 一覧の除外
  /// 規則を実 Drive と同じ経路で試せるようにするためであり、片方にしか無い前処理を作ると、
  /// 実 Drive で起きた不具合を `dir` で再現できなくなる。
  @override
  Future<String> put(String backupId, String path) async =>
      _publish(path, incomingName(backupId), backupName(backupId));

  @override
  Future<String> putBaseline(int seq, String generationId, String path) async =>
      _publish(
      path, incomingBaselineName(seq, generationId), baselineName(seq, generationId));

  String _publish(String path, String stagedName, String finalName) {
    root.createSync(recursive: true);
    final staged = _file(stagedName);
    File(path).copySync(staged.path);
    final published = _file(finalName);
    if (published.existsSync()) published.deleteSync();
    staged.renameSync(published.path);
    return finalName;
  }

  /// `baseline-<seq>-<generation-id>.blib` を集める。
  ///
  /// **中身は読まない。** 有効世代の判定に要るのは名前だけであり、世代を決めるために毎回
  /// `.blib` を開くと、通常同期のたびに全 baseline を読むことになる。
  @override
  Future<List<BaselineRef>> listBaselines() async {
    if (!root.existsSync()) return const [];
    final found = <BaselineRef>[];
    for (final entry in _entries()) {
      final name = _nameOf(entry);
      final parsed = parseBaselineName(name);
      if (parsed == null) continue;
      found.add(BaselineRef(
        seq: parsed.seq,
        generationId: parsed.generationId,
        remoteId: name,
        sizeBytes: entry.lengthSync(),
      ));
    }
    found.sort(compareBaseline);
    return found;
  }

  @override
  Future<BackupListing> list() async {
    if (!root.existsSync()) return const BackupListing();
    final found = <BackupRef>[];
    var skipped = 0;
    for (final entry in _entries()) {
      final name = _nameOf(entry);
      final backupId = parseBackupName(name);
      if (backupId == null) continue;
      final Map<String, String>? index;
      try {
        index = parseSummary(summaryOf(readManifest(entry.path)));
      } on SyncDataError {
        // 読めない `.blib` が名前だけ正しく置かれている。選ばせない。
        skipped++;
        continue;
      }
      if (index == null || index['backupId'] != backupId) {
        // 名前と中身の `backup_id` が食い違う。名前を信じると削除が別物に当たる。
        skipped++;
        continue;
      }
      found.add(BackupRef(
        backupId: backupId,
        remoteId: name,
        sizeBytes: entry.lengthSync(),
        summary: index,
      ));
    }
    found.sort(compareBackup);
    return BackupListing(refs: collapseBackups(found), skipped: skipped);
  }

  @override
  Future<String> get(String backupId, String destPath) async {
    final ref = resolveBackup(await list(), backupId);
    File(destPath).parent.createSync(recursive: true);
    _file(ref.remoteId).copySync(destPath);
    return destPath;
  }

  /// 世代の起点そのものを取る。**一覧の索引を通さない。**
  ///
  /// `backup-` は名前と索引の一致を一覧で見てから選ばせるが、baseline は名前が `seq` と
  /// `generationId` を持ち、有効世代の判定がその名前で済んでいる。ここで索引を要求すると、
  /// 索引を書けていない起点が「有効世代なのに復元できない」状態になる。
  @override
  Future<String> getBaseline(BaselineRef ref, String destPath) async {
    File(destPath).parent.createSync(recursive: true);
    _file(ref.remoteId).copySync(destPath);
    return destPath;
  }

  /// 名指しされた `backupId` の実体をすべて消す。消した数を返す。
  ///
  /// 重複があるとき片方だけ残すと、次の一覧に同じ id がまた出る。利用者から見れば
  /// 「消したのに消えていない」である。
  @override
  Future<int> delete(String backupId) async {
    final ref = resolveBackup(await list(), backupId);
    var removed = 0;
    for (final name in [ref.remoteId, ...ref.duplicateRemoteIds]) {
      final file = _file(name);
      if (file.existsSync()) {
        file.deleteSync();
        removed++;
      }
    }
    return removed;
  }

  List<File> _entries() {
    final files = root.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static String _nameOf(File file) => file.uri.pathSegments.last;
}
