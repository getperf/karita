/// 通常画面が示す状態を1つに決める。**規則はエンジンにあり、画面には無い。**
///
/// 内部状態（未送信の件数、lease、認可の喪失、受理集合の外の封筒、自己診断の失敗、回線）から
/// どの状態になるかを画面側で決めると、本番 GUI と別のクライアントが**別々の規則を書く**。同じ
/// DB を見た二つの画面が違う答えを出せる形にしない。自動解決の既定をエンジンに固定したのと同じ
/// 理屈である。画面が持つのは表示名・アイコン・色と、内部用語を避けた言い換えだけである。
///
/// **転送も保管先も見ない。** 状態は端末が持っている記録だけから決まる。読みに行くと、認可の
/// 切れた端末で件数すら見られなくなる。同期世代の変更はここに入らない — それは `run` が
/// `GenerationChangedError` で通常同期を止める話で、保管先を読まなければ分からない。
///
/// **回線と自己診断の一部だけを外から受ける。** 「いま繋がるか」は転送とプラットフォーム（③）が
/// 観測するもので、DB は「最後に試したとき何が起きたか」しか持たない。古い失敗から回線を
/// 推測すると、一度失敗して以後放置された端末が延々とオフラインを名乗り、未送信があることを
/// 隠す。設定・認可・所有の検査も同じ理由でここには無い（P2・P3 で入る）。
library;

import 'package:karita_contract/karita_contract.dart';

/// 通常画面が示す7つの状態。
///
/// **宣言順が優先順である。** 上にあるものほど先に出す。組合せは日常的に起こるので、どれを
/// 見せるかを決めない実装は「端末ごとに違う答え」を作る。
///
/// | 状態 | 次の操作 |
/// |---|---|
/// | [appUpdateRequired] | アプリを更新する |
/// | [signInRequired] | 再ログインする |
/// | [needsAttention] | 完全復元、または台帳を手で直す |
/// | [syncing] | 待つ |
/// | [offline] | 回線を回復する |
/// | [unsent] | 同期する（自動でも進む） |
/// | [synced] | 無し |
///
/// 並びの理由は3つである。
///
/// 1. **アプリ更新が最初。** 受理集合の外にある封筒は、再ログインでも完全復元でも解けない。
///    相手は新しい版で送り続けるので、他の操作を先に案内すると、済ませた後で同じ場所へ戻る
/// 2. **再ログインが要対応より先。** 認可を失っている間は取り込みが動かない。安い1操作で前提を
///    回復してからでなければ、完全復元や手修正を案内する根拠が揃わない
/// 3. **要対応は回線より先。** 要対応の3つはどれも DB に記録された事実で、回線が戻っても消え
///    ない。オフラインを先に出すと、利用者は「繋がれば直る」と読む。これは嘘になる
///
/// [syncing] だけが要対応より後で回線より先にある。走行中の run は**いま起きていること**で
/// あり、回線の観測は結果ではなく前提にすぎない。run が終われば結果のほうが状態に出る。
enum SyncState {
  /// アプリ更新が必要。受理集合の外の封筒があるか、DB が同梱のマイグレーションより新しい。
  appUpdateRequired,

  /// ログインが必要。認可を失って止まった outbox がある。
  signInRequired,

  /// データを確認できません。自動で決められないものが残っている。
  needsAttention,

  /// 同期中。走行中の run がある。
  syncing,

  /// オフライン。転送先へ届かない。
  offline,

  /// 未送信あり。送るものが残っているが、止まってはいない。
  unsent,

  /// 同期済み。
  synced,
}

/// 恒久 gap とみなすまでの猶予。**設定にしない。**
///
/// gap は先行イベントがまだ届いていないだけの正常な途中状態であり、短くすると通常の往復が
/// 要対応になる。長くすると、二度と来ない先行を待ち続ける端末が「同期済み」を名乗る。
const int stalledGapAfterSeconds = 86400;

/// 走行中の run を走行中と読み続ける上限。**lease と同じ長さにする。**
///
/// `outcome='running'` の行は、プロセスが落ちればそのまま残る。上限を置かないと、一度落ちた
/// 端末が永久に「同期中」を名乗り、未送信も要対応も隠れる。lease の長さを使うのは、その run が
/// 押さえていた outbox の行がそこで解放されるためである。**run が何も押さえられなくなった後に、
/// その run を進行中と呼ばない。**
const int runStaleAfterSeconds = leaseSeconds;

/// 状態の導出に使う事実の一枚。**ここに無いものは判定に入らない。**
///
/// 読み取り（[readSyncFacts]）と判定（[deriveState]）を分けてある。判定が純粋な関数になるので、
/// 組合せの試験がこの型を直に組み立てられ、DB を作らずに全ての枝を通せる。
class SyncFacts {
  /// 送っていない outbox の総数。`uploaded` でない行すべてで、[blockedAuth] を含む。
  ///
  /// **利用者に見せる「未送信 N件」はこれである。** 止まっている行を数から外すと、「未送信
  /// 0件」と「ログインが必要」が同時に出て、送るものが消えたように見える。
  final int unsent;

  /// 認可を失って止まった outbox の数。
  ///
  /// **転送先が認可の誤りを返したときにだけ立つ。** 届かなかっただけの行はここへ来ない
  /// （`TransportTimeout` は状態を進めない）。だから回線の有無と独立に読んでよい。
  final int blockedAuth;

  /// 失効した lease を持ったまま `uploading` に残っている行の数。
  ///
  /// **これ自体は状態を変えない。** 送信中にプロセスが落ちれば正常に起こる状態であり、次の
  /// `claimOutbox` が「`pending` の行」と一つの条件で拾い直す。要対応にすると、正常な回復の
  /// 途中が毎回赤くなる。行は [unsent] に数えられているので、利用者には未送信として見える。
  final int expiredLeases;

  /// 受理集合の外にあって保留した封筒の数（`pending_events` の `reason='schema'`）。
  final int schemaPending;

  /// 先行が未着で保留している封筒の数（`reason='gap'`）。
  final int gapPending;

  /// [gapPending] のうち恒久とみなしたもの。
  ///
  /// **「受信から [stalledGapAfterSeconds] を超えた」だけでは足りない。** 取り込みに成功した
  /// run を1回またいでもなお残っていることを要る。オフラインや認可切れで一度も取り込めていない
  /// 端末の gap は、先行が来ないのではなく**まだ取りに行けていない**だけである。
  final int stalledGaps;

  /// 開いたままの競合の数。
  ///
  /// **製品では自動解決が既定なので、開いたまま残るのは反復ガードが止めたものである。** 自動で
  /// 解決済みのものは数えない — 成功として扱い、事後通知で件数だけ知らせる。
  final int openConflicts;

  /// DB のマイグレーション版が、このアプリが同梱する最新より**新しい**。
  ///
  /// 新しいアプリが書いた DB をこのアプリが開いている。知らない列や表が既にある。
  final bool dbSchemaAhead;

  /// DB のマイグレーション版が同梱の最新より**古い**。起動時の適用が通っていない。
  final bool dbSchemaBehind;

  /// 適用済みマイグレーションのチェックサムが同梱の SQL と食い違う。
  final bool checksumMismatch;

  /// 走行中の run がある。
  final bool running;

  /// 最後に取り込みまで成功した時刻。無ければ null。
  final String? lastSuccessAt;

  /// 直近の run が自動解決した件数。事後通知「更新差を自動調整しました N件」の N である。
  final int autoResolved;

  /// 転送先へ届かない。**③ が観測して渡す。**
  final bool offline;

  /// 自己診断が失敗した。**呼び出し側が渡す分**であり、DB から読める分（[dbSchemaAhead]・
  /// [dbSchemaBehind]・[checksumMismatch]）はここに含めない。設定・認可・所有の検査は P2・P3 で
  /// 入る。
  final bool doctorFailed;

  const SyncFacts({
    this.unsent = 0,
    this.blockedAuth = 0,
    this.expiredLeases = 0,
    this.schemaPending = 0,
    this.gapPending = 0,
    this.stalledGaps = 0,
    this.openConflicts = 0,
    this.dbSchemaAhead = false,
    this.dbSchemaBehind = false,
    this.checksumMismatch = false,
    this.running = false,
    this.lastSuccessAt,
    this.autoResolved = 0,
    this.offline = false,
    this.doctorFailed = false,
  });

  /// アプリが古い。**この端末で解ける操作が他に無い。**
  bool get appTooOld => schemaPending > 0 || dbSchemaAhead;

  /// 自動では決められないものが残っている。
  bool get attention =>
      openConflicts > 0 ||
      stalledGaps > 0 ||
      dbSchemaBehind ||
      checksumMismatch ||
      doctorFailed;

  /// ハーネスの観測面が並べる内訳。**文言を持たず、件数と生値だけを出す。**
  Map<String, Object?> toMap() => {
        'unsent': unsent,
        'blocked_auth': blockedAuth,
        'expired_leases': expiredLeases,
        'schema_pending': schemaPending,
        'gap_pending': gapPending,
        'stalled_gaps': stalledGaps,
        'open_conflicts': openConflicts,
        'db_schema_ahead': dbSchemaAhead,
        'db_schema_behind': dbSchemaBehind,
        'checksum_mismatch': checksumMismatch,
        'running': running,
        'last_success_at': lastSuccessAt,
        'auto_resolved': autoResolved,
        'offline': offline,
        'doctor_failed': doctorFailed,
      };
}

/// 画面へ返す一枚。
class SyncStatus {
  final SyncState state;

  /// 最後に取り込みまで成功した時刻。画面の「最終同期」である。
  final String? lastSuccessAt;

  /// 直近の run が自動解決した件数。事後通知の N である。
  final int autoResolved;

  /// 内訳。**ハーネスの観測面が並べるためのもので、製品の画面は状態と上の2つしか使わない。**
  final SyncFacts facts;

  const SyncStatus({
    required this.state,
    required this.lastSuccessAt,
    required this.autoResolved,
    required this.facts,
  });

  Map<String, Object?> toMap() => {
        'state': state.name,
        'last_success_at': lastSuccessAt,
        'auto_resolved': autoResolved,
        'facts': facts.toMap(),
      };
}

/// 事実から状態を1つ決める。**[SyncState] の宣言順に見て、最初に当たったものを返す。**
///
/// 判定を宣言順の走査そのものにしてある。条件を並べ替えても優先順が変わらない形にすると、表と
/// 実装がずれる。
SyncState deriveState(SyncFacts facts) {
  for (final state in SyncState.values) {
    if (holdsFor(state, facts)) return state;
  }
  // [SyncState.synced] が常に当たるのでここへは来ない。網羅を型で示すために置いてある。
  return SyncState.synced;
}

/// その状態の条件が成り立つか。**[deriveState] の走査が使う。**
bool holdsFor(SyncState state, SyncFacts f) => switch (state) {
      SyncState.appUpdateRequired => f.appTooOld,
      SyncState.signInRequired => f.blockedAuth > 0,
      SyncState.needsAttention => f.attention,
      SyncState.syncing => f.running,
      SyncState.offline => f.offline,
      SyncState.unsent => f.unsent > 0,
      SyncState.synced => true,
    };

/// DB から読める事実を集める。**転送も保管先も読まない。**
SyncFacts readSyncFacts(
  Db db, {
  required String now,
  bool offline = false,
  bool doctorFailed = false,
}) {
  final pending = pendingCountsByReason(db);
  final dbVersion = currentVersion(db);
  final appVersion = latestVersion();

  return SyncFacts(
    unsent: _count(db, 'SELECT COUNT(*) AS n FROM outbox_events WHERE state != ?',
        [outboxUploaded]),
    blockedAuth: countOutbox(db, outboxBlockedAuth),
    expiredLeases: expiredLeases(db, now: now).length,
    schemaPending: pending['schema'] ?? 0,
    gapPending: pending['gap'] ?? 0,
    stalledGaps: _stalledGaps(db, now: now),
    openConflicts: countOpenConflicts(db),
    dbSchemaAhead: dbVersion > appVersion,
    dbSchemaBehind: dbVersion < appVersion,
    checksumMismatch: checksumMismatches(db).isNotEmpty,
    running: _running(db, now: now),
    lastSuccessAt: lastSuccessAt(db),
    autoResolved: _autoResolvedInLastRun(db),
    offline: offline,
    doctorFailed: doctorFailed,
  );
}

/// 最後に取り込みまで成功した run の終了時刻。
///
/// **`push` だけの run は数えない。** 送っただけで相手の更新を取り込んでいないため、「この時刻の
/// 内容で最新」とは言えない。画面の「最終同期」はその意味で読まれる。
///
/// 文字列の比較で最大を採れるのは、時刻を RFC3339 秒精度・Z終端に固定しているためである
/// （`expiredLeases` が同じ前提に乗っている）。
String? lastSuccessAt(Db db) {
  final rows = db.select(
    "SELECT MAX(finished_at_utc) AS at FROM sync_runs "
    "WHERE outcome = 'ok' AND mode IN ('pull', 'run') AND finished_at_utc IS NOT NULL",
  );
  if (rows.isEmpty) return null;
  final value = rows.first['at'];
  return value is String && value.isNotEmpty ? value : null;
}

int _count(Db db, String sql, [List<Object?> params = const []]) {
  final rows = db.select(sql, params);
  return rows.isEmpty ? 0 : (rows.first['n'] as int);
}

/// 走行中の run があるか。**古すぎる `running` は走行中と読まない。**
bool _running(Db db, {required String now}) =>
    _count(
      db,
      "SELECT COUNT(*) AS n FROM sync_runs "
      "WHERE outcome = 'running' AND started_at_utc > ?",
      [shiftSeconds(now, -runStaleAfterSeconds)],
    ) >
    0;

/// 恒久とみなす gap の数。
///
/// 猶予を過ぎたことと、**受信より後に取り込みへ成功した run があること**の両方を要る。片方だけ
/// では、取りに行けていない端末の gap を「来ない先行」と読み違える。
int _stalledGaps(Db db, {required String now}) => _count(
      db,
      "SELECT COUNT(*) AS n FROM pending_events p "
      "WHERE p.reason = 'gap' AND p.received_at_utc <= ? "
      "  AND EXISTS ("
      "    SELECT 1 FROM sync_runs r "
      "    WHERE r.outcome = 'ok' AND r.mode IN ('pull', 'run') "
      "      AND r.finished_at_utc > p.received_at_utc"
      "  )",
      [shiftSeconds(now, -stalledGapAfterSeconds)],
    );

/// 直近の run が閉じた競合の数。事後通知の N である。
///
/// **run の記録ではなく `conflicts` の解決時刻から数える。** `sync_runs` の計数列は判定表の行に
/// 対応するもので（`runCounters`）、自動解決はそこに無い。列を足すのは DDL の変更であり、契約の
/// 正本を先に動かす話になる。解決時刻は既にあるので、それで足りる。
///
/// 手動解決（検証専用）もここに入る。製品では自動解決が既定で手動の口が無いため、区別しても
/// 画面の値は変わらない。
int _autoResolvedInLastRun(Db db) {
  final runs = db.select(
    'SELECT started_at_utc FROM sync_runs ORDER BY started_at_utc DESC, run_id DESC LIMIT 1',
  );
  if (runs.isEmpty) return 0;
  return _count(
    db,
    "SELECT COUNT(*) AS n FROM conflicts "
    "WHERE state = 'resolved' AND resolved_at_utc >= ?",
    [runs.first['started_at_utc']],
  );
}
