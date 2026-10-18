/// 完全バックアップ（`.blib`）の**形式と名前の契約**。
///
/// **これは通常同期ではない。** 通常時は不変イベントを往復させる。ここが受け持つのは初期
/// セットアップ、データ障害、明示的な巻き戻しであり、選択したバックアップを**新しい正本**に
/// する操作である。
///
/// バックアップは「利用者データを再構築できる現在状態」である。端末のバイト単位の複製でも、
/// イベント履歴のアーカイブでもない。だから次を持ち込まない。
///
/// - 同期の作業状態（outbox、applied、pending、conflict、run、attempt）
/// - 端末固有の識別（`device_id`、プロファイル名）と `last_backup_at`、世代のキー、
///   接続している Google アカウントの安定 ID（`drive_account_id`）
/// - 再生成できるもの（`domain_events`）
///
/// ## 形式
///
/// `.blib` は zip である。中身は `manifest.json` と `library.db` の2つだけとする。zip にする
/// 理由は、manifest を DB の外に置いて**開かずに読める**ようにするためである。復元先は形式と
/// 版を先に見て、読めないバックアップのために SQLite を開かなくてよい。
///
/// ## 名前
///
/// 保管先での名前は `backup-<backup-id>.blib` である。`backup_id` は manifest にも入れる。
/// **名前と中身が食い違えば、名前だけを頼りにした一覧・重複判定・削除がすべて嘘になる。**
///
/// upload 中のものは `incoming-<backup-id>.blib` という別の前置で置き、検証を通してから改名
/// する。一覧は `backup-` だけを見るので、途中で落ちた upload は**選べる一覧に出ない。**
///
/// `event-` 前置には当たらないので、転送の一覧規則（`transport.dart` の `isEventName`）は
/// 変更しなくてよい。`baseline-<seq>-<generation-id>.blib` も同じ理由で当たらない。
///
/// **ここに zip もファイル入出力も置かない。** `karita_contract` は `dart:io` を持たない層で
/// ある。書庫の読み書きは `karita_sync` の `backup_archive.dart` が行う。
///
/// 移送元: book-sync-model の `src/contracts/backup.py`。
library;

import 'db.dart';
import 'errors.dart';

/// 形式の版。DB の schema version とは別に数える。**同じ数字で兼ねない** — 形式を変えずに
/// schema だけ上げることも、その逆もあるためである。
///
/// 2 で `backup_id` を必須にした。**版 1 の `.blib` は読めない。**
const int backupVersion = 2;

const String manifestName = 'manifest.json';
const String dbName = 'library.db';

const String backupPrefix = 'backup-';
const String incomingPrefix = 'incoming-';
const String baselinePrefix = 'baseline-';
const String backupSuffix = '.blib';

/// baseline の `seq` はゼロ埋め10進で書く。**文字列の昇順が数値の昇順と一致する**ように
/// するためである。桁が揃っていないと `baseline-10-...` が `baseline-2-...` より前に並ぶ。
const int seqWidth = 4;
const int maxSeq = 9999;
const int firstSeq = 1;

/// `backup_id` は UUID とする。前置だけで絞ると、別形式の名前まで拾ってしまう。
final RegExp _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// バックアップへ入れない表。作成時に空にする。
const List<String> excludedTables = [
  'outbox_events',
  'applied_events',
  'pending_events',
  'conflicts',
  'sync_runs',
  'sync_event_attempts',
  'domain_events',
];

/// 復元先で作り直す端末固有の状態。作成時に落とす。
///
/// `last_backup_at` を入れるのは、**それが端末ごとの事実だから**である。落とさないと、復元先の
/// 「最終バックアップ」が作成元端末の日時に見える。値が嘘になるだけで失敗はしないため気づけない。
///
/// 世代のキーを入れるのは、**世代は転送先の baseline 列が決めるもの**であって、バックアップの
/// 中身ではないからである。復元は「選んだバックアップを起点に新しい世代を始める」操作なので、
/// 作成元の世代を引き継ぐと**始めたはずの新世代に旧世代の名前で書く**ことになる。
///
/// 最終復元の3つも同じ理由で入れる（2026-09-24）。落とさないと、復元先の「最終復元」が
/// 作成元端末が過去に行った復元に見える。
const List<String> deviceStateKeys = [
  stateDeviceId,
  stateProfileName,
  stateLastBackupAt,
  stateLastRestoreAt,
  stateLastRestoreCreatedAt,
  stateLastRestorePlatform,
  stateGenerationId,
  stateGenerationSeq,
  stateDriveAccountId,
];

/// 復元後に無ければ復元を成立させない表。数え上げの対象でもある。
const List<String> requiredTables = [
  'books',
  'loans',
  'library_memberships',
  'library_systems',
];

class BackupError extends SyncDataError {
  // super パラメータへは畳めない（明示の super 呼び出しで既定の code を変えるため）。
  // ignore: use_super_parameters
  const BackupError(String message, {String code = 'backup'})
    : super(message, code: code);
}

String backupName(String backupId) => '$backupPrefix$backupId$backupSuffix';

/// upload 中の名前。**検証を通るまで `backup-` を名乗らせない。**
String incomingName(String backupId) => '$incomingPrefix$backupId$backupSuffix';

String _pad(int seq) => seq.toString().padLeft(seqWidth, '0');

int _requireSeq(int seq) {
  if (seq < firstSeq || seq > maxSeq) {
    throw BackupError(
      '世代の seq は $firstSeq〜$maxSeq です: $seq',
      code: 'baseline-seq',
    );
  }
  return seq;
}

/// 世代の起点のファイル名。**`seq` が有効世代を決める。**
///
/// 可変ファイルを置き換えていく形にしない。転送先は同名ファイルの重複作成を許すので、単一の
/// 可変ファイルを正本にすると「2つある状態」が普通に起こる。不変ファイルの列にして
/// **最大 `seq` を有効世代**とする。
String baselineName(int seq, String generationId) =>
    '$baselinePrefix${_pad(_requireSeq(seq))}-$generationId$backupSuffix';

/// 公開前の baseline。`backup-` と同じ二段名を通す。
String incomingBaselineName(int seq, String generationId) =>
    '$incomingPrefix${_pad(_requireSeq(seq))}-$generationId$backupSuffix';

/// `(seq, generationId)` を取る。当たらなければ null。
///
/// **`seq` の桁数を固定で見る。** 可変長を許すと、桁の違う2つが文字列順と数値順で食い違い、
/// **端末ごとに違う世代を有効と判断する**経路ができる。
({int seq, String generationId})? parseBaselineName(String name) {
  if (!name.startsWith(baselinePrefix) || !name.endsWith(backupSuffix))
    return null;
  final body = name.substring(
    baselinePrefix.length,
    name.length - backupSuffix.length,
  );
  final separator = body.indexOf('-');
  if (separator != seqWidth) return null;
  final seqText = body.substring(0, separator);
  final generationId = body.substring(separator + 1);
  if (!RegExp(r'^\d+$').hasMatch(seqText)) return null;
  if (!_uuidRe.hasMatch(generationId)) return null;
  final seq = int.parse(seqText);
  return seq >= firstSeq ? (seq: seq, generationId: generationId) : null;
}

/// 保管先の名前から `backup_id` を取る。当たらなければ null。
///
/// 一覧はこれを**本文を取る前に**通す。転送先は同じアプリの他のものと共有されており、封筒・
/// baseline・途中 upload・他版の残骸が同居する。名前で落とせないものを落とすために取得すると、
/// 一覧のたびに全ファイルを取ることになる。
String? parseBackupName(String name) {
  if (!name.startsWith(backupPrefix) || !name.endsWith(backupSuffix))
    return null;
  final backupId = name.substring(
    backupPrefix.length,
    name.length - backupSuffix.length,
  );
  return _uuidRe.hasMatch(backupId) ? backupId : null;
}

/// 件数を一行にする。**表示する場所が二つ以上あるので、整形は一箇所に置く。**
///
/// キーで整列する。`manifest.json` はキー整列で書かれるため、読み直した manifest の `counts`
/// も整列済みで返る。作った直後と読み直したものが同じ文字列にならないと、`export` の出力と
/// `backup list` の行が違って見える。
String formatCounts(Object? counts) {
  if (counts is! Map) return '';
  final keys = counts.keys.map((key) => '$key').toList()..sort();
  return [for (final key in keys) '$key=${counts[key]}'].join(' ');
}

/// 一覧と復元確認に出す索引。**表示とクエリのためだけに使う。**
///
/// 復元の可否や件数の正しさは、**必ず取得後の manifest と内容 hash から読む** — 索引は後から
/// 書き換えられるメタデータであり、正しさの根拠にできない。
Map<String, String> summaryOf(Object? manifest) {
  final source = manifest is Map ? manifest : const {};
  String text(String key) => '${source[key] ?? ''}';
  return {
    'backupId': text('backup_id'),
    'backupVersion': text('backup_version'),
    'schemaVersion': text('schema_version'),
    'createdAtUtc': text('created_at_utc'),
    'sourceProfile': text('source_profile'),
    'sourcePlatform': text('source_platform'),
    'counts': formatCounts(source['counts']),
  };
}

/// 索引を読む。`backupId` が無ければ「読めない」とする。
///
/// 読めないものは**選べる一覧から外す**。ただし数は残す — 黙って消すと、索引を書けていない
/// 不具合に誰も気づかない。
Map<String, String>? parseSummary(Object? properties) {
  if (properties is! Map) return null;
  final backupId = properties['backupId'];
  if (backupId == null || '$backupId'.isEmpty) return null;
  return {
    for (final key in summaryOf(const {}).keys) key: '${properties[key] ?? ''}',
  };
}

/// 復元確認画面に出す件数。「本 524冊、貸出記録 182件」の行の元になる。
Map<String, int> aggregateCounts(Db db) => {
  for (final table in requiredTables)
    table: db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int,
};

/// 複製から同期の作業状態と端末固有の識別を落とす。
///
/// **元の DB ではなく複製に対して行う。** 稼働中の DB から消すと、送信待ちの outbox を
/// バックアップ操作が破棄することになる。呼び出し側のトランザクションの中で使う。
void stripForBackup(Db db) {
  for (final table in excludedTables) {
    if (tableExists(db, table)) db.execute('DELETE FROM $table');
  }
  for (final key in deviceStateKeys) {
    db.execute('DELETE FROM sync_state WHERE key = ?', [key]);
  }
}

/// 復元先で欠けている表。空なら復元を成立させてよい。
List<String> missingRequiredTables(Db db) => [
  for (final name in requiredTables)
    if (!tableExists(db, name)) name,
];
