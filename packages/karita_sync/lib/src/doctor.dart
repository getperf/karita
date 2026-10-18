/// 自己診断。**台帳が同期を続けられる状態かを、名前のついた検査で答える。**
///
/// **`SyncFacts` と重ならない。** スキーマ版とチェックサム（`dbSchemaAhead` /
/// `dbSchemaBehind` / `checksumMismatch`）、失効した lease（`expiredLeases`）、滞留
/// （`gapPending` / `stalledGaps`）は導出がすでに DB から読んでいる。ここが見るのは、
/// **導出が見ていない不変条件**である。
///
/// 移送元: book-sync-model の `bsync admin doctor`（`非公開資料:bsync-command-reference.md`）。
/// あちらの12項目のうち、`config.toml` の構文と `profile.toml` の `device_id` 一致は
/// **karita-core に対象が無い** — 設定ファイルを持たず、本番に profile も無いためである。
///
/// **環境の検査はここに無い。** HOME の書き込み可否・資格情報・認可は OS で形が違い
/// （Android には資格情報のファイルも保存トークンも無い）、`karita_platform` と
/// `karita_platform_flutter` が分けて持つ。**型と `failed` の決め方だけをここに置き**、
/// 合成層が2つを [DoctorReport.merge] でまとめる。
///
/// **`failed` の決め方を UI 側に置かない。** 7状態の導出をエンジンに置いたのと同じ理由で、
/// 置くと本番 GUI と harness が別々の規則を書く。合成層が持つのは「いつ走らせるか」と、
/// **自分にしか見えないもの**（端末設定が読めたか）だけである。[DoctorCheck] は3層ぶんの
/// 語彙を持ち、実装はそれぞれの層にある。
library;

import 'package:karita_contract/karita_contract.dart';

/// 検査の識別子。**画面へ出るのはこの名前そのものである。**
enum DoctorCheck {
  // --- 台帳（[ledgerDoctor]） ---

  /// `device_id` が無い、または `<platform>-<何か>` の形でない。
  deviceId,

  /// `journal_mode` が `wal` でない。
  journalMode,

  /// 同期テーブルへ越権で書かれた行がある。
  tableOwnership,

  /// `outbox_events` にあるが `applied_events` に対応が無い。
  orphanedOutbox,

  /// `applied_events` にあるが、集約の行が無い。
  appliedWithoutEntity,

  /// 版が飛んでいる。1..max のうち欠けている版がある。
  versionGap,

  // --- 環境（`karita_platform` と `karita_platform_flutter`） ---

  /// データ領域へ書けない。
  homeWritable,

  /// 資格情報が読めない。**Windows だけの検査である。**
  credentials,

  /// 認可が無い。
  authorization,

  // --- 合成（`karita_app`） ---

  /// 端末設定（`config/device.json`）が読めなかった、または版が新しい。
  ///
  /// **既定で起動したうえでの所見である。** 設定が読めないことを起動の失敗にしない — 起動
  /// しなければ設定画面へ到達できず、利用者が直す経路そのものが無くなる。**値が範囲外だった
  /// だけのものはここへ来ない**（ログにだけ出す）。
  deviceConfig,

  /// 業務の参照が切れている（常用館が分館一覧に無い）。
  ///
  /// **② は業務集約を知らないので、ここは合成層が `karita_domain` へ問い合わせて足す。**
  /// 台帳の検査（[ledgerDoctor]）に置くと、業務側の集約定義の変更が同期の側へ漏れる。
  ///
  /// **「まだ届いていない」と「分館が消えた」を区別しない。** どちらも「参照先が今は無い」で
  /// あり、行を消さずに人へ上げるという扱いは同じである。同期で届いた集約行は登録経路の検査を
  /// 通らないので、参照の切れた設定は正常に適用されうる — それを拾うのがこの検査である
  /// （`非公開資料:libraries-in-sqlite.md` 2c）。
  danglingReference,
}

/// 検査1件の結果。**件数と生値だけを持ち、文言を持たない。**
class DoctorFinding {
  final DoctorCheck check;

  /// 引っかかった件数。**0 の finding は作らない** — 作ると「異常が無い」と「検査していない」が
  /// 混ざる。
  final int count;

  /// 生値。テーブル名、読めなかったパス、実際の `journal_mode` など。**説明文ではない。**
  final String detail;

  const DoctorFinding(this.check, this.count, this.detail);

  Map<String, Object?> toMap() => {
        'check': check.name,
        'count': count,
        'detail': detail,
      };

  @override
  String toString() => '${check.name}(count: $count, detail: $detail)';
}

/// 走らせた検査の一覧と、引っかかったもの。
class DoctorReport {
  /// **実際に走らせた検査。** 引っかかったかどうかとは別に持つ — 環境の検査は端末によって
  /// 走らないものがあり（Android に `credentials` は無い）、**「走っていない」と「異常が無い」を
  /// 混ぜないため**である。
  final Set<DoctorCheck> checked;

  final List<DoctorFinding> findings;

  const DoctorReport({required this.checked, this.findings = const []});

  /// **1件でも引っかかれば失敗である。** 重みづけをしない — 「軽い異常」を作ると、それを
  /// どこまで無視してよいかの判断が UI 側へ漏れる。
  bool get failed => findings.isNotEmpty;

  /// 走らせていない検査。**harness の観測面が並べる。**
  Set<DoctorCheck> get notChecked =>
      DoctorCheck.values.toSet().difference(checked);

  /// 台帳の分と環境の分を1つにする。**ここが合成規則である。**
  static DoctorReport merge(Iterable<DoctorReport> reports) => DoctorReport(
        checked: {for (final report in reports) ...report.checked},
        findings: [for (final report in reports) ...report.findings],
      );

  Map<String, Object?> toMap() => {
        'failed': failed,
        'checked': [for (final check in checked) check.name],
        'not_checked': [for (final check in notChecked) check.name],
        'findings': [for (final finding in findings) finding.toMap()],
      };
}

/// `device_id` の形。**`<platform>-<uuid>` の前半を `platformOf` が読む。**
final RegExp _deviceIdShape = RegExp(r'^[a-z0-9]+-.+$');

/// 台帳から読める不変条件を全部見る。**ネットワークも認可も要らない。**
///
/// **転送先を見ない。** 有効世代との突き合わせは `run` が `generation-changed` で答えるもので、
/// 自己診断が通信を要求すると、オフラインの端末が「異常」を名乗る。
DoctorReport ledgerDoctor(Db db, Mapping mapping) {
  final findings = <DoctorFinding>[];

  // --- device_id -----------------------------------------------------------
  final deviceId = getState(db, stateDeviceId);
  if (deviceId == null || !_deviceIdShape.hasMatch(deviceId)) {
    // **値そのものを出す。** 形が違うことが問題なので、伏せると直しようがない。
    findings.add(DoctorFinding(DoctorCheck.deviceId, 1, deviceId ?? '(none)'));
  }

  // --- journal_mode --------------------------------------------------------
  //
  // **WAL でないと、置換の途中で落ちたときの回復が変わる。** 複製は `VACUUM INTO` で作るので
  // 稼働中の WAL を個別にコピーすることは無いが、置換の後に古い WAL が残ると SQLite は
  // それを新しい本体のものとして読む。
  //
  // **ファイルの DB のときだけ見る。** `SqliteDb.memory()` は `journal_mode = memory` のままで、
  // そこには本体もジャーナルも無いので、この検査に意味が無い。**走らせずに [DoctorReport.checked]
  // から外す** — 「異常が無い」と「検査していない」を混ぜないためである。
  final fileBacked = _isFileBacked(db);
  if (fileBacked) {
    final mode = _scalar(db, 'PRAGMA journal_mode');
    if (mode?.toLowerCase() != 'wal') {
      findings.add(DoctorFinding(DoctorCheck.journalMode, 1, mode ?? '(none)'));
    }
  }

  // --- 所有 ----------------------------------------------------------------
  //
  // **P3 で入ったまま、これまで誰も呼んでいなかった。** 押印を見る側がここである。
  for (final violation in ownershipViolations(db)) {
    findings.add(DoctorFinding(
        DoctorCheck.tableOwnership, violation.count, violation.table));
  }

  // --- 孤児 outbox ---------------------------------------------------------
  //
  // ローカル発行は集約更新・`applied_events`・`outbox_events` を**同一トランザクション**で
  // 確定する。対応が無い outbox は、その原子性が崩れた跡である。
  final orphaned = _count(
    db,
    'SELECT COUNT(*) AS n FROM outbox_events o '
    'WHERE NOT EXISTS (SELECT 1 FROM applied_events a WHERE a.event_id = o.event_id)',
  );
  if (orphaned > 0) {
    findings.add(DoctorFinding(DoctorCheck.orphanedOutbox, orphaned, 'outbox_events'));
  }

  // --- 実体のない applied_events -------------------------------------------
  //
  // **entity_type ごとにテーブルが違う。** 対応表は `Mapping` が持つ。知らない entity_type は
  // ここでは見ない — 未対応版の封筒は判定表の1行目で先に落ちており、`pending_events` の話である。
  for (final entry in mapping.specs.entries) {
    final missing = _count(
      db,
      'SELECT COUNT(*) AS n FROM applied_events a '
      'WHERE a.entity_type = ? '
      'AND NOT EXISTS (SELECT 1 FROM ${entry.value.table} t WHERE t.id = a.entity_id)',
      [entry.key],
    );
    if (missing > 0) {
      findings.add(DoctorFinding(
          DoctorCheck.appliedWithoutEntity, missing, entry.value.table));
    }
  }

  // --- 版の飛び ------------------------------------------------------------
  //
  // **1..max のうち欠けている版を数える。** 版の同一性は (version, updated_by_device_id) だが、
  // 飛びを見るのに要るのは連番の方だけである。1件ずつ引かずに、実体ごとの
  // `COUNT(DISTINCT)` と `MAX` を突き合わせる。
  final gaps = _count(
    db,
    'SELECT COUNT(*) AS n FROM ('
    '  SELECT entity_type, entity_id '
    '  FROM applied_events '
    '  GROUP BY entity_type, entity_id '
    '  HAVING COUNT(DISTINCT result_version) <> MAX(result_version)'
    ')',
  );
  if (gaps > 0) {
    findings.add(DoctorFinding(DoctorCheck.versionGap, gaps, 'applied_events'));
  }

  return DoctorReport(
    checked: {
      DoctorCheck.deviceId,
      if (fileBacked) DoctorCheck.journalMode,
      DoctorCheck.tableOwnership,
      DoctorCheck.orphanedOutbox,
      DoctorCheck.appliedWithoutEntity,
      DoctorCheck.versionGap,
    },
    findings: findings,
  );
}

/// この接続がファイルの DB を開いているか。
///
/// `PRAGMA database_list` の `main` の `file` は、メモリ上の DB では空文字である。
bool _isFileBacked(Db db) {
  for (final row in db.select('PRAGMA database_list')) {
    if (row['name'] != 'main') continue;
    final file = row['file'];
    return file is String && file.isNotEmpty;
  }
  return false;
}

String? _scalar(Db db, String sql) {
  final rows = db.select(sql);
  if (rows.isEmpty) return null;
  final value = rows.first.values.first;
  return value == null ? null : '$value';
}

int _count(Db db, String sql, [List<Object?> parameters = const []]) =>
    db.select(sql, parameters).first['n'] as int;
