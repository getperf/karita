/// `.blib` の読み書き。zip とファイル入出力を要る部分。
///
/// 形式と名前の契約は `karita_contract` の `backup.dart` にある。ここが持つのは**手順**だけで
/// ある — 複製の作り方、検証の順序、置換を最後の1手にまとめること。
///
/// **正常な一時 DB が完成する前に現 DB を触らない。** 取得の中断、hash 不一致、未対応 schema、
/// migration 失敗のいずれでも現 DB は元のまま残る。置換だけが不可逆な一歩であり、それを最後の
/// 1手にまとめている。
///
/// 移送元: book-sync-model の `src/contracts/backup.py`（zip とファイル入出力の部分）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:karita_contract/karita_contract.dart';

import 'sqlite_db.dart';

class BackupOutcome {
  final Map<String, Object?> manifest;
  final Map<String, int> counts;

  const BackupOutcome(this.manifest, this.counts);
}

String _hashBytes(List<int> data) => sha256.convert(data).toString();

/// 出来上がった `.blib` 全体の hash。**保管先へ載せたものが同じか**を見るために使う。
///
/// manifest の `content_hash` は中の DB だけを覆う。zip の切り詰めは中身を取り出す前に分かった
/// 方がよく、保管先が返すチェックサムとも突き合わせられる。
String fileHash(String path) => _hashBytes(File(path).readAsBytesSync());

/// `sourceDbPath` の完全バックアップを `outPath` へ書く。manifest を返す。
///
/// 複製は `VACUUM INTO` で作る。**稼働中の DB ファイル、WAL、SHM を個別にコピーしない。**
/// 3つのファイルを別々に読むと、読んだ時点がずれて整合しない組み合わせになる。
///
/// **Python は Backup API（`source.backup(dest)`）を使うが、Dart では採れない。**
/// `package:sqlite3` の `Database.backup()` は進捗を流す `Stream` を返す非同期 API であり、
/// ここを非同期にすると `SyncEngine.run` まで伝播する。`VACUUM INTO` は同期で、1接続の一貫した
/// 読みから新しいファイルを書き出すので、**同じ性質（整合したスナップショット）を同期で得られる。**
/// 出来上がる DB の内容は同じであり、相互運用は台帳と表の一致で確かめている。
///
/// 書き出しは一時ファイルへ行い、最後に置換する。途中で落ちたとき、壊れた `.blib` が正常な
/// バックアップの名前で残らないようにするためである。
Map<String, Object?> createBackup(
  String sourceDbPath,
  String outPath, {
  required String now,
  required String backupId,
  required String sourceDeviceId,
  required String sourceProfile,
  required String sourcePlatform,
}) {
  if (!File(sourceDbPath).existsSync()) {
    throw BackupError('DB がありません: $sourceDbPath', code: 'backup-no-db');
  }
  File(outPath).parent.createSync(recursive: true);

  final work = Directory.systemTemp.createTempSync('blib-export-');
  try {
    final staged = '${work.path}${Platform.pathSeparator}$dbName';

    final source = SqliteDb.open(sourceDbPath);
    final int schemaVersion;
    try {
      schemaVersion = currentVersion(source);
      // `VACUUM INTO` は書き出し先が存在しないことを要求する。一時ディレクトリなので空である。
      source.execute('VACUUM INTO ?', [staged]);
    } finally {
      source.close();
    }

    final Map<String, int> counts;
    final copy = SqliteDb.open(staged);
    try {
      transaction(copy, () => stripForBackup(copy));
      // 落とした表の領域を返す。バックアップの大きさが「消したはずのイベント数」に比例した
      // ままでは、入れない判断が容量に反映されない。
      copy.execute('VACUUM');
      counts = aggregateCounts(copy);
    } finally {
      copy.close();
    }
    // WAL を本体へ畳んでから読む。閉じた後の残骸を取り込まない。
    for (final suffix in ['-wal', '-shm']) {
      final residue = File('$staged$suffix');
      if (residue.existsSync()) residue.deleteSync();
    }

    final payload = File(staged).readAsBytesSync();
    final manifest = <String, Object?>{
      'backup_id': backupId,
      'backup_version': backupVersion,
      'schema_version': schemaVersion,
      'created_at_utc': now,
      'source_device_id': sourceDeviceId,
      'source_profile': sourceProfile,
      'source_platform': sourcePlatform,
      'content_hash': _hashBytes(payload),
      'counts': counts,
    };

    final tempOut = '$outPath.part';
    _writeArchive(tempOut, manifest, payload);
    final temp = File(tempOut);
    final out = File(outPath);
    if (out.existsSync()) out.deleteSync();
    temp.renameSync(outPath);
    return manifest;
  } finally {
    work.deleteSync(recursive: true);
  }
}

/// manifest はキー整列・2字下げで書く。Python 側と同じ形にしておくと、`.blib` を開いて
/// 目で比べたときに差分が中身の差分だけになる。
void _writeArchive(String path, Map<String, Object?> manifest, List<int> payload) {
  final text = const JsonEncoder.withIndent('  ').convert(_sortKeys(manifest));
  final manifestBytes = utf8.encode(text);
  final archive = Archive()
    ..addFile(ArchiveFile(manifestName, manifestBytes.length, manifestBytes))
    ..addFile(ArchiveFile(dbName, payload.length, payload));
  final encoded = ZipEncoder().encode(archive);
  File(path).writeAsBytesSync(encoded, flush: true);
}

Object? _sortKeys(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return {for (final key in keys) key: _sortKeys(value[key])};
  }
  return value;
}

/// `.blib` の manifest だけを読む。一覧表示と、復元前の可否判定に使う。
Map<String, Object?> readManifest(String backupPath) {
  final file = File(backupPath);
  if (!file.existsSync()) {
    throw BackupError('バックアップがありません: $backupPath', code: 'backup-missing');
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
  } catch (_) {
    throw BackupError('バックアップの形式が不正です: ${_name(backupPath)}',
        code: 'backup-format');
  }
  final entry = _find(archive, manifestName);
  if (entry == null) {
    throw BackupError('バックアップの形式が不正です: ${_name(backupPath)}',
        code: 'backup-format');
  }
  final Object? manifest;
  try {
    manifest = jsonDecode(utf8.decode(entry.content as List<int>));
  } catch (_) {
    throw BackupError('manifest を読めません: ${_name(backupPath)}',
        code: 'backup-manifest');
  }
  if (manifest is! Map<String, Object?>) {
    throw BackupError('manifest の形が不正です: ${_name(backupPath)}',
        code: 'backup-manifest');
  }
  return manifest;
}

void _checkVersion(Map<String, Object?> manifest, String backupPath) {
  final backupId = manifest['backup_id'];
  if (backupId == null || '$backupId'.isEmpty) {
    // 版 2 で必須にした。名前だけが `backup-<uuid>.blib` で中身に id が無いものは、一覧・
    // 重複判定・削除がすべて名前頼りになる。読める形に見えるので明示的に弾く。
    throw BackupError('manifest に backup_id がありません: ${_name(backupPath)}',
        code: 'backup-manifest');
  }
  final version = manifest['backup_version'];
  if (version != backupVersion) {
    throw BackupError(
      '未対応のバックアップ形式です（この版が読めるのは $backupVersion、ファイルは $version）。'
      'アプリを更新してください: ${_name(backupPath)}',
      code: 'backup-version',
    );
  }
  final schemaVersion = _asInt(manifest['schema_version']);
  final latest = latestVersion();
  if (schemaVersion > latest) {
    // 新しい端末で作ったバックアップを古い端末が読もうとしている。migration は前へしか
    // 進めないので、ここで止めなければ「読めたが表が足りない」状態になる。
    throw BackupError(
      '新しい schema のバックアップです（この版が扱えるのは $latest、ファイルは $schemaVersion）。'
      'アプリを更新してください: ${_name(backupPath)}',
      code: 'backup-schema',
    );
  }
}

String _extract(String backupPath, Map<String, Object?> manifest, Directory into) {
  final archive = ZipDecoder().decodeBytes(File(backupPath).readAsBytesSync());
  final entry = _find(archive, dbName);
  if (entry == null) {
    throw BackupError('バックアップに $dbName がありません: ${_name(backupPath)}',
        code: 'backup-format');
  }
  final payload = entry.content as List<int>;
  if (_hashBytes(payload) != manifest['content_hash']) {
    throw BackupError('バックアップの内容 hash が一致しません: ${_name(backupPath)}',
        code: 'backup-hash');
  }
  final staged = '${into.path}${Platform.pathSeparator}$dbName';
  File(staged).writeAsBytesSync(payload, flush: true);
  return staged;
}

Map<String, int> _verify(String staged, {required String now}) {
  final db = SqliteDb.open(staged);
  try {
    final verdict = '${db.select('PRAGMA integrity_check').first.values.first}';
    if (verdict != 'ok') {
      throw BackupError('SQLite の整合性検査に失敗しました: $verdict', code: 'backup-corrupt');
    }
    migrate(db, now: now);
    final missing = [
      ...missingRequiredTables(db),
      for (final table in ['book_preferences', 'book_reviews'])
        if (!tableExists(db, table)) table,
    ];
    if (missing.isNotEmpty) {
      throw BackupError('バックアップに必要な表がありません: ${missing.join('、')}',
          code: 'backup-tables');
    }
    // 送り側が古い版でも、復元先の除外規則を必ず満たす状態にしてから置換する。
    transaction(db, () => stripForBackup(db));
    return aggregateCounts(db);
  } finally {
    db.close();
  }
}

/// 復元先の端末としての素性と、始める世代を入れる。
///
/// **作成元の `device_id` を復元しない。** 二台が同じ `device_id` を使うと LWW の全順序が
/// 壊れ、どちらの更新が新しいか決まらなくなる。診断も端末を区別できなくなる。
///
/// 世代は呼び出し側が**先に baseline を公開してから**渡す。復元は「選んだ時点を新しい正本に
/// する」操作であり、新しい世代を始めることと不可分である。旧世代の名前のまま復元すると、
/// 転送先に残った復元前のイベントを次の pull が拾い、**巻き戻したはずの更新が戻る。**
///
/// **最終復元もここで書く**（2026-09-24）。置換の前の複製に入れるので、置換と同じ一歩で
/// 現れる — 置換の後に書くと、その間に落ちた端末は「復元したのに記録が無い」状態で起きる。
/// 対象は manifest から採る。起点への参加でも起点は同じ `.blib` の形なので、経路で分けない。
void _adopt(
  String staged, {
  required Map<String, Object?> manifest,
  required String deviceId,
  required String profile,
  required String now,
  required String generationId,
  required int generationSeq,
}) {
  final db = SqliteDb.open(staged);
  try {
    transaction(db, () {
      setState(db, stateDeviceId, deviceId);
      setState(db, stateProfileName, profile);
      setState(db, stateGenerationId, generationId);
      setState(db, stateGenerationSeq, '$generationSeq');
      setState(db, stateLastRestoreAt, now);
      setState(db, stateLastRestoreCreatedAt,
          '${manifest['created_at_utc'] ?? ''}');
      setState(db, stateLastRestorePlatform,
          '${manifest['source_platform'] ?? ''}');
      if (getState(db, stateCreatedAtUtc) == null) {
        setState(db, stateCreatedAtUtc, now);
      }
    });
  } finally {
    db.close();
  }
}

/// 復元できるかどうかだけを先に判定する。現 DB にも保管先にも触らない。
///
/// **新しい世代を公開する前にこれを通す。** 復元の手順は「検証 → baseline を公開 → 現 DB を
/// 置換」であり、順を崩すと**読めないバックアップを指す baseline が有効世代になる。** 現 DB が
/// 無事でも、他の全端末がその壊れた起点からの完全復元を求められる。
///
/// [restoreBackup] が同じ検証をもう一度行う。二度走るのは無駄に見えるが、**置換の直前に見た
/// 結果だけが置換の根拠になる**。ここでの合格は「公開してよい」という判断にとどめる。
BackupOutcome precheckBackup(String backupPath, {required String now}) {
  final manifest = readManifest(backupPath);
  _checkVersion(manifest, backupPath);
  final work = Directory.systemTemp.createTempSync('blib-precheck-');
  try {
    return BackupOutcome(manifest, _verify(_extract(backupPath, manifest, work), now: now));
  } finally {
    work.deleteSync(recursive: true);
  }
}

/// `backupPath` を `targetDbPath` の新しい正本にする。manifest と件数を返す。
///
/// 置換の後に WAL と SHM を消す。古い WAL が新しい本体の隣に残ると、SQLite はそれを本体の
/// 続きとして読もうとする。**これは復元の失敗より静かで、後から原因が分からない。**
BackupOutcome restoreBackup(
  String backupPath,
  String targetDbPath, {
  required String now,
  required String deviceId,
  required String profile,
  required String generationId,
  required int generationSeq,
}) {
  final manifest = readManifest(backupPath);
  _checkVersion(manifest, backupPath);

  final work = Directory.systemTemp.createTempSync('blib-import-');
  final Map<String, int> counts;
  try {
    final staged = _extract(backupPath, manifest, work);
    counts = _verify(staged, now: now);
    _adopt(staged,
        manifest: manifest,
        deviceId: deviceId,
        profile: profile,
        now: now,
        generationId: generationId,
        generationSeq: generationSeq);

    final target = File(targetDbPath);
    target.parent.createSync(recursive: true);
    // 同一ボリュームとは限らないため、置換の直前に隣へ寄せる。rename は跨ぐと失敗する。
    final landing = File('$targetDbPath.incoming');
    File(staged).copySync(landing.path);
    if (target.existsSync()) target.deleteSync();
    landing.renameSync(targetDbPath);
  } finally {
    work.deleteSync(recursive: true);
  }

  for (final suffix in ['-wal', '-shm']) {
    final residue = File('$targetDbPath$suffix');
    if (residue.existsSync()) residue.deleteSync();
  }
  return BackupOutcome(manifest, counts);
}

ArchiveFile? _find(Archive archive, String name) {
  for (final file in archive.files) {
    if (file.name == name) return file;
  }
  return null;
}

String _name(String path) => path.split(RegExp(r'[\/]')).last;

int _asInt(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;
