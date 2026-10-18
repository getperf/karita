/// SQLite 接続の**最小の口**と、トランザクションの境界。
///
/// **ここに `package:sqlite3` を持ち込まない。** `karita_contract` は `dart:io` も `dart:ffi` も
/// 持たない層である（正本の schema を生成定数にしたのと同じ理由で、ファイルシステムへの依存を
/// この層から外してある）。必要なのは「SQL を実行する」「行を読む」の二つだけなので、それを
/// [Db] として宣言し、実装は `karita_sync` の `SqliteDb` が持つ。
///
/// 業務（`karita_domain`）と同期（`karita_sync`）の**両方がここに依存する。** 接合点は outbox の
/// 一点であり、その追記ヘルパ（[appendLocalEmission]）は `sync_tables.dart` にある。
///
/// PRAGMA の方針（実装側が守る）:
///
/// - `journal_mode=WAL`   永続設定。二プロファイルの並行実行と、書込み中の読み取りのため。
/// - `foreign_keys=OFF`   集約間参照に外部キー制約を張らない。イベントが順不同で到着する間、
///                        参照先が一時的に存在しないのは異常ではなく正常な途中状態である。
/// - `busy_timeout`       並行実行時のロック待ち。
///
/// 暗黙のコミットに委ねず、トランザクションは呼び出し側が [transaction] で明示する。
/// 適用の原子性（S1）はその境界にある。
///
/// 移送元: book-sync-model の `src/contracts/db.py`。
library;

const int busyTimeoutMs = 5000;

const String stateDeviceId = 'device_id';
const String stateProfileName = 'profile_name';
const String stateCreatedAtUtc = 'created_at_utc';

/// 最後にバックアップを保管した時刻。**端末ごとの事実であり、バックアップへは入れない。**
const String stateLastBackupAt = 'last_backup_at';

/// 最後に復元した時刻と、その対象（作成時刻・作成端末）。**これも端末ごとの事実である。**
///
/// 対象を `backup_id` で持たない。一覧を引き直さないと日時へ戻せず、消されていれば戻せない。
/// 起点（baseline）への参加でも同じ manifest が読めるので、2つの経路で形が変わらない。
const String stateLastRestoreAt = 'last_restore_at';
const String stateLastRestoreCreatedAt = 'last_restore_created_at';
const String stateLastRestorePlatform = 'last_restore_platform';

/// いまこの端末が乗っている同期世代。**`.blib` には入れない**（P1b）。
const String stateGenerationId = 'generation_id';
const String stateGenerationSeq = 'generation_seq';

/// 接続している Google アカウントの安定 ID（`about.get` の `permissionId`）。
///
/// **端末ごとの事実であり、`.blib` には入れない**（P5 単位 E）。バックアップへ入れると、
/// 復元先が作成元端末の接続先を名乗ることになる。
const String stateDriveAccountId = 'drive_account_id';

/// SQLite への最小の口。実装は `karita_sync` の `SqliteDb`。
abstract interface class Db {
  /// 1文を実行する。パラメータは `?` で束縛する。
  void execute(String sql, [List<Object?> params = const []]);

  /// 複数文の SQL をまとめて実行する。**マイグレーションの本体がこれを通る。**
  ///
  /// 文の分割を自前でやらない。SQL の文字列リテラルやコメントに現れるセミコロンで割らない
  /// ためには結局 SQLite の字句解析が要り、素朴な `split(';')` は壊れる。閉じていない SQL は
  /// SQLite 自身が `incomplete input` で落とす。
  void executeScript(String sql);

  /// 行を読む。列名 → 値。INTEGER は int、TEXT は String、NULL は null。
  List<Map<String, Object?>> select(
    String sql, [
    List<Object?> params = const [],
  ]);
}

/// 明示トランザクション。例外時は必ずロールバックする。
///
/// `BEGIN IMMEDIATE` にするのは、書込みロックを最初に取って昇格時のデッドロックを避けるため
/// である（Python 側と同じ）。
T transaction<T>(Db db, T Function() body) {
  db.execute('BEGIN IMMEDIATE');
  T result;
  try {
    result = body();
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
  db.execute('COMMIT');
  return result;
}

bool tableExists(Db db, String name) => db.select(
  "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
  [name],
).isNotEmpty;

void setState(Db db, String key, String value) {
  db.execute(
    'INSERT INTO sync_state (key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value],
  );
}

String? getState(Db db, String key) {
  if (!tableExists(db, 'sync_state')) return null;
  final rows = db.select('SELECT value FROM sync_state WHERE key = ?', [key]);
  return rows.isEmpty ? null : rows.first['value'] as String;
}
