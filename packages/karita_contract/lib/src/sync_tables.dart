/// 同期テーブルへの唯一の書込み経路。
///
/// DB を共有すると、業務側から `conflicts` へ SQL で書くことが物理的に可能になる。ここを通った
/// 書込みだけが `written_by_app` を押印し、所有検査（業務モデルの移送と同時に入れる）が
/// 押印の無い行と越権の行を報告する。
///
/// | テーブル | 書いてよいもの |
/// |---|---|
/// | `outbox_events` | ②（状態遷移、解決イベント）と業務（業務トランザクション内の pending 追記のみ） |
/// | `applied_events` | ② と、業務の**自端末発行分（`origin='local'`）のみ** |
/// | `pending_events`、`conflicts`、`sync_runs`、`sync_event_attempts` | ② のみ |
///
/// 業務が呼ぶのは [appendLocalEmission] だけである。
///
/// 移送元: book-sync-model の `src/contracts/sync_tables.py`。
library;

import 'canonical.dart' as canonical;
import 'constants.dart';
import 'db.dart';
import 'envelope.dart';
import 'ids.dart';
import 'json_reader.dart';

const List<String> syncTables = [
  'outbox_events',
  'applied_events',
  'pending_events',
  'conflicts',
  'sync_runs',
  'sync_event_attempts',
];

/// ② だけが書けるテーブル。`outbox_events` と `applied_events` は業務にも一部を開けているため、
/// この表ではなく個別の検査に掛ける。
const List<String> bsyncOnlyTables = [
  'pending_events',
  'conflicts',
  'sync_runs',
  'sync_event_attempts',
];

// --- outbox -----------------------------------------------------------------

/// outbox へ SyncEvent を追記する。呼び出し側のトランザクションの中で使う。
///
/// 業務はこれを業務トランザクション内で呼ぶ。「業務更新と outbox 追加は同一 SQLite
/// トランザクションで確定する」という不変条件を満たす唯一の置き場所である。
void appendOutbox(
  Db db,
  Envelope event, {
  String state = outboxPending,
  required String updatedAtUtc,
  required String app,
}) {
  db.execute(
    'INSERT INTO outbox_events ('
    '  event_id, device_id, created_at_utc, entity_type, entity_id, operation,'
    '  base_version, result_version, payload_hash, resolves_event_ids, payload,'
    '  domain_event_type, state, updated_at_utc, written_by_app'
    ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      event.eventId,
      event.deviceId,
      event.createdAtUtc,
      event.entityType,
      event.entityId,
      event.operation,
      event.baseVersion,
      event.resultVersion,
      event.payloadHash,
      canonical.dumpsText(List<String>.from(event.resolvesEventIds)),
      canonical.dumpsText(event.payload),
      // 版2の任意項目。**送信前に落とさない。** ここで捨てると、封筒に載せたつもりの値が
      // 発行と送信の間で静かに消える。同期層は解釈せず運ぶだけである。
      event.domainEventType,
      state,
      updatedAtUtc,
      app,
    ],
  );
}

/// 自端末が発行したイベントを `outbox_events` と `applied_events` へ**同時に**追記する。
///
/// 業務側の入口はこれ一つである。呼び出し側のトランザクションの中で使う。
///
/// **二つで一組であり、片方だけを書いてはならない。** `applied_events` を落とすと、転送先へ
/// 上げた自分の封筒を次の `pull` で引き戻したときに判定表2行目（冪等）が効かず、`baseVersion` が
/// 現在版より小さい行として**自分の更新が自分との競合になる**。二端末とも同じことが起きるため、
/// 競合が増え続けて収束しない。
void appendLocalEmission(
  Db db,
  Envelope event, {
  required String updatedAtUtc,
  required String app,
}) {
  appendOutbox(db, event, updatedAtUtc: updatedAtUtc, app: app);
  recordApplied(
    db,
    eventId: event.eventId,
    entityType: event.entityType,
    entityId: event.entityId,
    resultVersion: event.resultVersion,
    payloadHash: event.payloadHash,
    origin: originLocal,
    appliedAtUtc: event.createdAtUtc,
    app: app,
  );
}

List<Map<String, Object?>> listOutbox(Db db, {String? state}) {
  if (state == null) {
    return db.select('SELECT * FROM outbox_events ORDER BY created_at_utc, event_id');
  }
  return db.select(
    'SELECT * FROM outbox_events WHERE state = ? ORDER BY created_at_utc, event_id',
    [state],
  );
}

int countOutbox(Db db, String state) =>
    db.select('SELECT COUNT(*) AS n FROM outbox_events WHERE state = ?', [state])
        .first['n'] as int;

/// outbox の状態を進める。
///
/// `clearLease` は lease を外す。**送信結果が不明なまま状態を進めるときは外さない** —
/// 他のプロセスが直ちに再送して重複イベントを作る余地が生まれる。
///
/// `lastError` は書かれた値をそのまま入れる。`attempts` はここでは触らない。増やすのは lease を
/// 取る [claimOutbox] だけである。
void setOutboxState(
  Db db,
  String eventId,
  String state, {
  required String updatedAtUtc,
  String? remoteFileId,
  String? lastError,
  bool clearLease = false,
  String app = appBsync,
}) {
  final lease = clearLease ? ', lease_owner = NULL, lease_expires_at_utc = NULL' : '';
  db.execute(
    'UPDATE outbox_events SET state = ?, updated_at_utc = ?, written_by_app = ?, '
    '  remote_file_id = COALESCE(?, remote_file_id), last_error = ?$lease '
    'WHERE event_id = ?',
    [state, updatedAtUtc, app, remoteFileId, lastError, eventId],
  );
}

/// 送信対象を1件押さえる。取れるものが無ければ null。
///
/// **「`pending` の行」と「`uploading` かつ lease が失効した行」を一つの条件で拾う。**
/// 二つの経路に分けると、失効行を拾う側を呼び忘れた瞬間にその行は送信から永久に漏れる。
///
/// lease の保持者は端末ではなく run である。同一端末の別プロセスから守るのが目的なので、
/// `device_id` では自分自身と区別がつかない。
///
/// `attempts` はここで増やす。**上限は置かない** — 回数で送信を打ち切ると、outbox を失わない
/// という原則に回数という別の消失経路を作ることになる。
Map<String, Object?>? claimOutbox(
  Db db, {
  required String runId,
  required String now,
  int lease = leaseSeconds,
  String app = appBsync,
}) {
  final rows = db.select(
    'SELECT event_id FROM outbox_events '
    'WHERE state = ? '
    '   OR (state = ? AND (lease_expires_at_utc IS NULL OR lease_expires_at_utc <= ?)) '
    'ORDER BY created_at_utc, event_id LIMIT 1',
    [outboxPending, outboxUploading, now],
  );
  if (rows.isEmpty) return null;

  final eventId = rows.first['event_id'] as String;
  db.execute(
    'UPDATE outbox_events SET state = ?, attempts = attempts + 1, lease_owner = ?, '
    '  lease_expires_at_utc = ?, updated_at_utc = ?, written_by_app = ? '
    'WHERE event_id = ?',
    [outboxUploading, runId, shiftSeconds(now, lease), now, app, eventId],
  );
  return getOutbox(db, eventId);
}

/// lease が失効したまま `uploading` に残っている行。
///
/// 比較が文字列で成立するのは、時刻を RFC3339 秒精度・Z終端に固定しているためである。
List<Map<String, Object?>> expiredLeases(Db db, {required String now}) => db.select(
      'SELECT * FROM outbox_events '
      'WHERE state = ? AND lease_expires_at_utc IS NOT NULL AND lease_expires_at_utc <= ? '
      'ORDER BY created_at_utc, event_id',
      [outboxUploading, now],
    );

/// 失効した lease を外し、`pending` へ戻す。戻した eventId を返す。
///
/// `attempts` は減らさない。何回試したかは診断の情報であり、回復で消してはならない。
/// `lastError` も残す — なぜ止まったのかは回復した後も要る。
List<String> unlockExpired(Db db, {required String now, String app = appBsync}) {
  final rows = expiredLeases(db, now: now);
  for (final row in rows) {
    setOutboxState(
      db,
      row['event_id'] as String,
      outboxPending,
      updatedAtUtc: now,
      lastError: row['last_error'] as String?,
      clearLease: true,
      app: app,
    );
  }
  return [for (final row in rows) row['event_id'] as String];
}

Map<String, Object?>? getOutbox(Db db, String eventId) {
  final rows =
      db.select('SELECT * FROM outbox_events WHERE event_id = ?', [eventId]);
  return rows.isEmpty ? null : rows.first;
}

/// 止まった行を `pending` へ戻す。`lastError` は消す — 利用者が明示的に再送を指示した以上、
/// 前回の失敗は了解済みである。自動の回復（[unlockExpired]）が残すのと対になっている。
void retryOutbox(Db db, String eventId, {required String now, String app = appBsync}) {
  setOutboxState(db, eventId, outboxPending,
      updatedAtUtc: now, lastError: null, clearLease: true, app: app);
}


/// outbox 行を封筒へ戻す。
///
/// `payload` 列は正準化済みの文字列なので、読み直しても同じ `payloadHash` になる。`build` が
/// 宣言ハッシュと再計算値の一致を検査するため、格納中に壊れていれば送信前に落ちる。
///
/// **`schemaVersion` の列は持たない。** outbox に入るのは自端末が発行した封筒だけであり、
/// 発行版は常に一つである。
Envelope envelopeFromOutboxRow(EnvelopeCodec codec, Map<String, Object?> row) {
  return codec.build(
    eventId: row['event_id'],
    deviceId: row['device_id'],
    createdAtUtc: row['created_at_utc'],
    entityType: row['entity_type'],
    entityId: row['entity_id'],
    operation: row['operation'],
    baseVersion: row['base_version'],
    resultVersion: row['result_version'],
    payload: loadsJson(row['payload'] as String, label: 'outbox の payload'),
    resolvesEventIds: loadsJson(row['resolves_event_ids'] as String,
        label: 'outbox の resolvesEventIds'),
    payloadHash: row['payload_hash'],
    domainEventType: row['domain_event_type'],
  );
}

// --- applied ----------------------------------------------------------------

/// applied_events へ追記する。主キー衝突は冪等の担保であって異常ではない。
void recordApplied(
  Db db, {
  required String eventId,
  required String entityType,
  required String entityId,
  required int resultVersion,
  required String payloadHash,
  required String origin,
  required String appliedAtUtc,
  String app = appBsync,
}) {
  db.execute(
    'INSERT INTO applied_events ('
    '  event_id, entity_type, entity_id, result_version, payload_hash, origin,'
    '  applied_at_utc, written_by_app'
    ') VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [eventId, entityType, entityId, resultVersion, payloadHash, origin, appliedAtUtc, app],
  );
}

/// 判定表2行目（冪等）が使う。
Set<String> appliedEventIds(Db db) => {
      for (final row in db.select('SELECT event_id FROM applied_events'))
        row['event_id'] as String,
    };

/// 自端末が発行したイベント。判定表3行目の迂回条件が使う。
Set<String> localEventIds(Db db) => {
      for (final row in db
          .select('SELECT event_id FROM applied_events WHERE origin = ?', [originLocal]))
        row['event_id'] as String,
    };

int countApplied(Db db) =>
    db.select('SELECT COUNT(*) AS n FROM applied_events').first['n'] as int;

/// いまのローカル版を作ったイベント。解決イベントの `resolvesEventIds` に要る。
///
/// 版だけでは実体を識別できないが、`applied_events` はこの端末が実際に適用したものしか
/// 持たないため、同じ集約・同じ `result_version` の行はこの端末では一つである。
String? eventIdForVersion(Db db, String entityType, String entityId, int version) {
  final rows = db.select(
    'SELECT event_id FROM applied_events '
    'WHERE entity_type = ? AND entity_id = ? AND result_version = ? '
    'ORDER BY applied_at_utc DESC, event_id DESC LIMIT 1',
    [entityType, entityId, version],
  );
  return rows.isEmpty ? null : rows.first['event_id'] as String;
}

// --- pending ----------------------------------------------------------------

/// 取り込めないイベントを保持する。**破棄しない。**
///
/// `reason='schema'` では封筒の形自体が未知でありうるため、解析済みの列は NULL 可とし、
/// 受信した生の文字列を正本にする。
void recordPending(
  Db db, {
  required String eventId,
  required String reason,
  String? entityType,
  String? entityId,
  int? baseVersion,
  required String envelope,
  required String receivedAtUtc,
  String app = appBsync,
}) {
  db.execute(
    'INSERT INTO pending_events ('
    '  event_id, reason, entity_type, entity_id, base_version, envelope,'
    '  received_at_utc, written_by_app'
    ') VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
    'ON CONFLICT(event_id) DO UPDATE SET reason = excluded.reason',
    [eventId, reason, entityType, entityId, baseVersion, envelope, receivedAtUtc, app],
  );
}

void deletePending(Db db, String eventId) {
  db.execute('DELETE FROM pending_events WHERE event_id = ?', [eventId]);
}

/// 再走査の順序を固定する。走査順が実行ごとに変わるとゴールデンが安定しない。
List<Map<String, Object?>> listPending(Db db, {String? reason}) {
  if (reason == null) {
    return db.select('SELECT * FROM pending_events ORDER BY base_version, event_id');
  }
  return db.select(
    'SELECT * FROM pending_events WHERE reason = ? ORDER BY base_version, event_id',
    [reason],
  );
}

Map<String, int> pendingCountsByReason(Db db) {
  final counts = <String, int>{};
  for (final row
      in db.select('SELECT reason, COUNT(*) AS n FROM pending_events GROUP BY reason')) {
    counts[row['reason'] as String] = row['n'] as int;
  }
  return counts;
}

// --- conflicts --------------------------------------------------------------

/// 1リモートイベントにつき1行を作る。後から届いた競合で先の行を上書きしない。
void recordConflict(
  Db db, {
  required String conflictId,
  required String entityType,
  required String entityId,
  required int localVersion,
  String? localPayloadHash,
  String? localEventId,
  required String remoteEventId,
  required int remoteBaseVersion,
  required int remoteResultVersion,
  required String remoteEnvelope,
  required String detectedAtUtc,
  String app = appBsync,
}) {
  db.execute(
    'INSERT INTO conflicts ('
    '  conflict_id, entity_type, entity_id, local_version, local_payload_hash,'
    '  local_event_id, remote_event_id, remote_base_version, remote_result_version,'
    '  remote_envelope, state, detected_at_utc, written_by_app'
    ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      conflictId,
      entityType,
      entityId,
      localVersion,
      localPayloadHash,
      localEventId,
      remoteEventId,
      remoteBaseVersion,
      remoteResultVersion,
      remoteEnvelope,
      conflictOpen,
      detectedAtUtc,
      app,
    ],
  );
}

List<Map<String, Object?>> listConflicts(Db db, {String? state}) {
  if (state == null) {
    return db.select('SELECT * FROM conflicts ORDER BY detected_at_utc, conflict_id');
  }
  return db.select(
    'SELECT * FROM conflicts WHERE state = ? ORDER BY detected_at_utc, conflict_id',
    [state],
  );
}

int countOpenConflicts(Db db) => db
    .select('SELECT COUNT(*) AS n FROM conflicts WHERE state = ?', [conflictOpen])
    .first['n'] as int;

Map<String, Object?>? getConflict(Db db, String conflictId) {
  final rows = db.select('SELECT * FROM conflicts WHERE conflict_id = ?', [conflictId]);
  return rows.isEmpty ? null : rows.first;
}

List<Map<String, Object?>> openConflictsFor(Db db, String entityType, String entityId) =>
    db.select(
      'SELECT * FROM conflicts WHERE state = ? AND entity_type = ? AND entity_id = ? '
      'ORDER BY detected_at_utc, conflict_id',
      [conflictOpen, entityType, entityId],
    );

/// 判定表3行目の迂回条件が使う。**未解決のものだけ**である。
///
/// 解決済みを含めると、同じ競合を決着させた古いイベントが届くたびに版判定を飛ばして
/// 適用され続ける。
Set<String> openConflictRemoteEventIds(Db db) => {
      for (final row in db
          .select('SELECT remote_event_id FROM conflicts WHERE state = ?', [conflictOpen]))
        row['remote_event_id'] as String,
    };

/// 既に conflict 行を持つリモートイベント。**解決済みも含める。**
///
/// 競合したイベントは `applied_events` に入らないため、sync run のたびに判定表6行目へ落ちる。
/// ここで数えないと、同じリモートイベントに対する conflict 行が run ごとに増え続ける。
Set<String> conflictedRemoteEventIds(Db db) => {
      for (final row in db.select('SELECT remote_event_id FROM conflicts'))
        row['remote_event_id'] as String,
    };

/// 受信の一覧で**本文を取らずに済む**イベント（2026-10-08）。
///
/// 適用済み（自端末の発行分を含む）・保留中・競合として記録済みの3つである。保留中は
/// `pending_events` に封筒ごと持っていて、再走査は表から行う。競合済みは判定表6行目へ落ちても
/// 「既に conflict 行がある」で終わる。**どれも本文を取り直して得るものが無い。**
///
/// `invalid` になった封筒はどの表にも残らないので含まれない（毎回取り直す）
/// （`非公開資料:sqlite-drive-sync-protocol.md`「受信は差分で取る」）。
Set<String> knownIncomingEventIds(Db db) => {
      ...appliedEventIds(db),
      for (final row in db.select('SELECT event_id FROM pending_events'))
        row['event_id'] as String,
      ...conflictedRemoteEventIds(db),
    };

/// ある集約で解決済みになった競合の件数。自動解決の反復ガードが使う。
///
/// **`sinceUtc` で窓を切る。** 累計で数えると、自動解決を常時有効にした後、長く使う集約が
/// 正常な利用のまま上限へ達し、以後その集約だけ二度と自動解決されなくなる。ガードは頻度の
/// 保険であって、集約ごとの恒久的な停止装置ではない。
int resolvedConflictCount(
  Db db,
  String entityType,
  String entityId, {
  String? sinceUtc,
}) {
  var sql = 'SELECT COUNT(*) AS n FROM conflicts '
      'WHERE state = ? AND entity_type = ? AND entity_id = ?';
  final params = <Object?>[conflictResolved, entityType, entityId];
  if (sinceUtc != null) {
    sql += ' AND resolved_at_utc >= ?';
    params.add(sinceUtc);
  }
  return db.select(sql, params).first['n'] as int;
}

void resolveConflict(
  Db db,
  String conflictId, {
  required String resolvedAtUtc,
  String? resolutionEventId,
  String app = appBsync,
}) {
  db.execute(
    'UPDATE conflicts SET state = ?, resolved_at_utc = ?, resolution_event_id = ?, '
    '  written_by_app = ? WHERE conflict_id = ?',
    [conflictResolved, resolvedAtUtc, resolutionEventId, app, conflictId],
  );
}

// --- runs -------------------------------------------------------------------

const List<String> runCounters = [
  'pushed',
  'fetched',
  'applied',
  'ignored',
  'pending',
  'conflicted',
  'invalid',
];

void startRun(
  Db db, {
  required String runId,
  required String startedAtUtc,
  required String transport,
  required String mode,
  String app = appBsync,
}) {
  db.execute(
    'INSERT INTO sync_runs (run_id, started_at_utc, transport, mode, written_by_app) '
    'VALUES (?, ?, ?, ?, ?)',
    [runId, startedAtUtc, transport, mode, app],
  );
}

void finishRun(
  Db db,
  String runId, {
  required String finishedAtUtc,
  required Map<String, int> counts,
  String outcome = 'ok',
}) {
  final assignments = [for (final name in runCounters) '$name = ?'].join(', ');
  db.execute(
    'UPDATE sync_runs SET finished_at_utc = ?, outcome = ?, $assignments WHERE run_id = ?',
    [
      finishedAtUtc,
      outcome,
      for (final name in runCounters) counts[name] ?? 0,
      runId,
    ],
  );
}

/// 何も無かった run の行を、[keepRunId] を除いて消す（2026-10-08）。
///
/// 前面の周期は 30 秒で、何も無い回ごとに1行を足すと `sync_runs` が使っている間ずっと伸びる。
/// **最終同期の時刻は残す** — 消すのは [keepRunId] より前の同種の行だけで、[keepRunId] 自身が
/// 最新の成功として残る（`lastSuccessAt` は `MAX(finished_at_utc)`）。
///
/// 何も無い = `ok` で全カウンタが 0、かつ `sync_event_attempts` に1行も持たない。
void pruneIdleRuns(Db db, {required String keepRunId}) {
  final zero = [for (final name in runCounters) '$name = 0'].join(' AND ');
  db.execute(
    "DELETE FROM sync_runs WHERE run_id <> ? AND outcome = 'ok' "
    'AND finished_at_utc IS NOT NULL AND $zero '
    'AND NOT EXISTS (SELECT 1 FROM sync_event_attempts a WHERE a.run_id = sync_runs.run_id)',
    [keepRunId],
  );
}

/// 1イベントを1回扱った記録。判定表のどの行に落ちたかを残す。
///
/// gap と conflict は入力の形が同じで結果が逆であるため、どちらに落ちたかを後から追えないと
/// 切り分けができない。再走査で同じ run 内に二度現れうるので、後の結果で上書きする。
void recordAttempt(
  Db db, {
  required String runId,
  required String eventId,
  required String direction,
  required String outcome,
  String? detail,
  required String atUtc,
  String app = appBsync,
}) {
  db.execute(
    'INSERT INTO sync_event_attempts ('
    '  run_id, event_id, direction, outcome, detail, at_utc, written_by_app'
    ') VALUES (?, ?, ?, ?, ?, ?, ?) '
    'ON CONFLICT(run_id, event_id, direction) DO UPDATE SET '
    '  outcome = excluded.outcome, detail = excluded.detail, at_utc = excluded.at_utc',
    [runId, eventId, direction, outcome, detail, atUtc, app],
  );
}

// --- 所有検査 ---------------------------------------------------------------

/// 所有違反1件。どのテーブルに、何件、なぜ。
class OwnershipViolation {
  final String table;
  final int count;
  final String detail;

  const OwnershipViolation(this.table, this.count, this.detail);
}

/// 同期テーブルへ越権で書かれた行を数える。
///
/// **DB を共有すると、業務から同期テーブルへ SQL で書くことが物理的に可能になる。** import の
/// 静的検査では捕まらない — 依存の向きは正しいまま、実行時に別のテーブルへ手が伸びる。そこで
/// `karita_contract` の書込みヘルパだけが `written_by_app` を押印し、ここがその押印を見る。
///
/// **生 SQL で直接書かれた行は押印が既定の空文字のままになる**ので、同じ検査に掛かる。
/// 「押印が無い」と「他人の押印がある」を分けて数えない — どちらも「ここを通っていない」で
/// あり、対処は同じである。
///
/// 移送元: book-sync-model の `src/contracts/sync_tables.py`（`ownership_violations`）。
List<OwnershipViolation> ownershipViolations(Db db) {
  final violations = <OwnershipViolation>[];

  for (final table in bsyncOnlyTables) {
    final n = db.select(
      'SELECT COUNT(*) AS n FROM $table WHERE written_by_app <> ?',
      [appBsync],
    ).first['n'] as int;
    if (n > 0) {
      violations.add(OwnershipViolation(
          table, n, '$table へ ② 以外が書いた行が $n 件あります'));
    }
  }

  // 業務に開けているのは **`pending` の追記だけ**である。状態を動かすのは送信の責務で、
  // 業務が動かした時点で lease と再送の管理が二本になる。
  final outbox = db.select(
    'SELECT COUNT(*) AS n FROM outbox_events '
    'WHERE written_by_app NOT IN (?, ?) OR (written_by_app = ? AND state <> ?)',
    [appBsync, appBops, appBops, outboxPending],
  ).first['n'] as int;
  if (outbox > 0) {
    violations.add(OwnershipViolation('outbox_events', outbox,
        'outbox_events に越権の行が $outbox 件あります'
        '（業務に許すのは state=$outboxPending の追記だけです）'));
  }

  // 業務に許すのは**自端末発行分の記録だけ**である。受信イベントの適用（origin='remote'）は
  // 同期の責務であり、業務が書いた時点で適用経路が二本になっている。
  final applied = db.select(
    'SELECT COUNT(*) AS n FROM applied_events '
    'WHERE written_by_app NOT IN (?, ?) OR (written_by_app = ? AND origin <> ?)',
    [appBsync, appBops, appBops, originLocal],
  ).first['n'] as int;
  if (applied > 0) {
    violations.add(OwnershipViolation('applied_events', applied,
        'applied_events に越権の行が $applied 件あります'
        '（業務に許すのは origin=$originLocal の追記だけです）'));
  }

  return violations;
}
