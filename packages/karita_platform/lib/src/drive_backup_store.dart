/// `appDataFolder` をバックアップの保管先にする `BackupStorePort` の実装。
///
/// 封筒と同じ場所に同居する。棲み分けは名前で行い、一覧は `backup-<uuid>.blib` だけを見る。
/// 整列・重複の畳み込み・有効世代の決定は `karita_sync` の共有実装を通す — 置き場ごとに違うと、
/// 端末ごとに違う世代を有効と判断し、両方が「相手が旧世代だ」と結論する。
///
/// 移送元: book-sync-model の `src/bsync_core/drive.py`（`DriveBackupStore`）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';

import 'drive_client.dart';

class DriveBackupStore implements BackupStorePort {
  final DriveClient client;

  DriveBackupStore(this.client);

  @override
  String get kind => transportDrive;

  /// `incoming-` で載せ、検算を通してから `backup-` へ改名する。
  ///
  /// **置き換えが無いことが二段名の理由である。** `create` は常に新しいファイルを作り、既存を
  /// 上書きしない。最初から `backup-` を名乗らせると、upload が途中で落ちた実体が正しい名前の
  /// まま一覧に出て、利用者が選べてしまう。hash 検査は取得の後なので、そのときには「選んだ
  /// ものが壊れていた」という形でしか分からない。
  @override
  Future<String> put(String backupId, String path) => _publish(
        path,
        incomingName(backupId),
        backupName(backupId),
        properties: _backupProperties(path, backupId: backupId),
        label: backupId,
      );

  /// 世代の起点を公開する。**`backup-` と同じ二段名を通る。**
  ///
  /// 改名が最後の1手であることは、ここではバックアップ以上に効く。`baseline-` は**有効世代の
  /// 決定に使われる**ので、途中で落ちた upload がその名前を名乗ると、全端末が実体の無い世代を
  /// 有効と判断する。
  @override
  Future<String> putBaseline(int seq, String generationId, String path) => _publish(
        path,
        incomingBaselineName(seq, generationId),
        baselineName(seq, generationId),
        properties: _backupProperties(path),
        label: 'baseline $seq',
      );

  /// `incoming-` で載せ、検算を通してから公開の名前へ改名する。
  ///
  /// **検算は必ず1つは走る。** md5 は保管先が返さないことがあり、それだけを見ると「一致した」
  /// のか「返ってこなかった」のか区別が付かないまま公開が成功する。二値ファイルの大きさは必ず
  /// 返るので、大きさの照合を無条件のガードにし、md5 は返ってきたときだけ効く上乗せにする。
  ///
  /// **どちらも得られなければ公開しない。** 検算できなかったものを `backup-` や `baseline-` の
  /// 名前で置くと、二段名を用意した意味が無くなる。障害復帰でそれを選ぶ利用者にとっては、
  /// 「バックアップが無い」より「壊れたバックアップがある」方が悪い。
  Future<String> _publish(
    String path,
    String stagedName,
    String finalName, {
    required Map<String, String> properties,
    required String label,
  }) async {
    final localSize = File(path).lengthSync();
    final uploaded = await client.createBinary(stagedName, properties, path);

    var checked = false;
    if (uploaded.sizeBytes != 0) {
      checked = true;
      if (uploaded.sizeBytes != localSize) {
        await _discard(uploaded.fileId, label,
            '大きさが違います（$localSize → ${uploaded.sizeBytes}）');
      }
    }
    if (uploaded.md5.isNotEmpty) {
      checked = true;
      if (uploaded.md5 != _md5Of(path)) {
        await _discard(uploaded.fileId, label, '内容が違います');
      }
    }
    if (!checked) {
      await _discard(uploaded.fileId, label, '保管先が大きさも md5 も返しませんでした');
    }

    await client.rename(uploaded.fileId, finalName);
    return uploaded.fileId;
  }

  /// 載せたものを**公開の名前を名乗らせないまま**捨てる。
  Future<Never> _discard(String fileId, String label, String reason) async {
    await client.delete(fileId);
    throw BackupError('アップロードした .blib を検算できませんでした（$reason）: $label',
        code: 'backup-store-upload');
  }

  /// `baseline-` を名前だけで集める。**中身は取らない。**
  ///
  /// 有効世代の判定に要るのは `seq` と `generationId` で、どちらも名前にある。世代を決めるため
  /// に `.blib` を開くと、通常同期のたびに全 baseline を取得することになる。
  @override
  Future<List<BaselineRef>> listBaselines() async {
    final found = <BaselineRef>[];
    // **名前で絞る。** 通常同期のたびに走るので、`appDataFolder` の全ファイル（封筒を含む）を
    // 読まない。名前の判定（`parseBaselineName`）は省かない。
    for (final ref in await _allFiles(namePrefixQuery(baselinePrefix))) {
      final parsed = parseBaselineName(ref.name);
      if (parsed == null) continue;
      found.add(BaselineRef(
        seq: parsed.seq,
        generationId: parsed.generationId,
        remoteId: ref.fileId,
        sizeBytes: ref.sizeBytes,
      ));
    }
    found.sort(compareBaseline);
    return found;
  }

  /// 一覧。**索引は `appProperties` から読み、実体は取らない。**
  ///
  /// 名前で落とせないものを取得で落とすと、一覧のたびに全ファイルを download することになる。
  /// 索引が無い、あるいは名前と食い違うものは**選ばせないが数は残す** — 黙って消すと、索引を
  /// 書けていない不具合が「バックアップが1つも無い」という形でしか現れない。
  @override
  Future<BackupListing> list() async {
    final found = <BackupRef>[];
    var skipped = 0;
    for (final ref in await _allFiles()) {
      final backupId = parseBackupName(ref.name);
      if (backupId == null) continue;
      final index = parseSummary(ref.appProperties);
      if (index == null || index['backupId'] != backupId) {
        skipped++;
        continue;
      }
      found.add(BackupRef(
        backupId: backupId,
        remoteId: ref.fileId,
        sizeBytes: ref.sizeBytes,
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
    await client.download(ref.remoteId, destPath);
    return destPath;
  }

  /// 世代の起点そのものを取る。**一覧の索引を通さない。**
  ///
  /// 有効世代は名前だけで決まっている（[listBaselines]）。ここで `appProperties` を要求すると、
  /// 索引を書けていない起点が「有効世代なのに復元できない」状態になる。内容の正しさは取得後の
  /// manifest と hash が見る。
  @override
  Future<String> getBaseline(BaselineRef ref, String destPath) async {
    File(destPath).parent.createSync(recursive: true);
    await client.download(ref.remoteId, destPath);
    return destPath;
  }

  /// 名指しされた `backupId` の実体をすべて消す。消した数を返す。
  ///
  /// **`appDataFolder` の削除はゴミ箱を経由せず恒久である。** 確認を求めるのは呼び出し側の
  /// 責務で、ここは名指しされたものだけを消す。重複があるとき片方を残すと、利用者から見れば
  /// 「消したのに消えていない」になる。
  @override
  Future<int> delete(String backupId) async {
    final ref = resolveBackup(await list(), backupId);
    var removed = 0;
    for (final remoteId in [ref.remoteId, ...ref.duplicateRemoteIds]) {
      await client.delete(remoteId);
      removed++;
    }
    return removed;
  }

  /// `pageToken` のループ。**同じ file id が二度返るページ境界を畳む。**
  Future<List<FileRef>> _allFiles([String? query]) async {
    final found = <FileRef>[];
    final seen = <String>{};
    String? pageToken;
    while (true) {
      final page = await client.listPage(pageToken: pageToken, query: query);
      for (final ref in page.files) {
        if (seen.add(ref.fileId)) found.add(ref);
      }
      pageToken = page.nextPageToken;
      if (pageToken == null) break;
    }
    return found;
  }
}

/// `appProperties` に載せる索引。
///
/// 載せるのは一覧と復元確認の表示に要るものだけで、**正しさは常に manifest から読む**（封筒の
/// [indexProperties] と同じ規約）。読めない `.blib` でも upload は止めない — 索引を作れない
/// ことは保管しない理由にならない。
///
/// `backupId` は `backup-` を公開するときだけ渡す。**名前と索引を必ず一致させる**ためで、
/// 一致しないものは一覧が選ばせない。baseline は名前が `seq` と `generationId` を持つので、
/// 索引には manifest の内容だけを載せる。
Map<String, String> _backupProperties(String path, {String? backupId}) {
  Map<String, String> index;
  try {
    index = Map.of(summaryOf(readManifest(path)));
  } on SyncDataError {
    index = Map.of(summaryOf(const {}));
  }
  if (backupId != null) index['backupId'] = backupId;
  return index;
}

/// 保管先が返す値と突き合わせるためだけの md5。
///
/// **内容の正しさを md5 で判定しない。** これが見るのは「載せたバイト列が途中で切れていないか」
/// だけで、中身の正しさは manifest の内容 hash（sha256）が復元時に見る。
///
/// 分割して読む。`.blib` は MB 級になりうるので、検算のためだけに全体をメモリへ載せない。
String _md5Of(String path) {
  late Digest digest;
  final sink = md5.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((digests) => digest = digests.single));
  final handle = File(path).openSync();
  try {
    final buffer = Uint8List(1024 * 1024);
    while (true) {
      final read = handle.readIntoSync(buffer);
      if (read <= 0) break;
      sink.add(Uint8List.sublistView(buffer, 0, read));
    }
  } finally {
    handle.closeSync();
  }
  sink.close();
  return '$digest';
}
