/// 1プロファイルぶんの同期エンジン。`bsync sync push / pull / run` に対応する。
///
/// `run` は push → pull → apply → 自動解決 → 解決イベントの push の順で回す。**最初の push を
/// 先にする。** 適用の途中で何が起きても、自端末で確定済みの更新は相手へ届く。自分のイベントは
/// pull で戻ってくるが、判定表2行目が冪等に無視する。
///
/// **末尾の push は自動解決したときだけ走る。** 一回の同期操作の中で往復を閉じるためであり、
/// pull へは戻らない。反復すると一回の操作の終わりが決まらなくなる。
///
/// **`sync_runs` は観測用であって原子性の単位ではない。** 個々の書込みはそれぞれ独立した
/// トランザクションで確定しており、途中で落ちてもそこまでは残る。
///
/// **転送を要る操作は非同期で、互いに重ならない**（[SyncEngine.run] ほか）。待ち点が入る以上、
/// 二つの操作が同じ台帳の上で交互に進みうる — lease はプロセス跨ぎの道具であって、同じ
/// エンジンの中の重なりは守らない。並びは呼ばれた順に固定する（`_exclusive`）。
library;

import 'dart:async';
import 'dart:io';

import 'package:karita_contract/karita_contract.dart';

import 'apply.dart';
import 'backup_archive.dart';
import 'backup_store.dart';
import 'db_session.dart';
import 'doctor.dart';
import 'generation.dart';
import 'plan.dart';
import 'push.dart';
import 'sqlite_db.dart';
import 'status.dart';
import 'transport.dart';

const String modePush = 'push';
const String modePull = 'pull';
const String modeRun = 'run';

/// 競合の自動解決の方針。**製品の既定は `lww` に固定し、利用者設定にしない。**
///
/// 「LWW を利用者設定にしない」は画面の話ではなくエンジンの既定の話である。設定で切り替え
/// られると、同じ競合が端末ごとに違う結末になり、二端末の収束が利用者の設定に依存する。
///
/// [manual] は**検証専用**である。受入ケース03・04 は人手の解決を測るため、自動解決が働くと
/// 競合がそもそも残らない。それを再現するためだけに要る。**製品の組み立てでこれを選んでは
/// ならない。**
enum AutoResolvePolicy {
  /// 決定的 LWW で自動的に解く。**製品の既定。**
  lww,

  /// 競合を開いたまま残し、人手の解決を待つ。**検証専用。**
  manual,
}

/// 検証 CLI の `config set` が使うキー。**製品の設定面には出さない。**
const String settingAutoResolve = 'conflict.auto_resolve';
const String autoResolveLww = 'lww';
const String autoResolveManual = 'manual';

class RunResult {
  final String runId;

  /// この run が乗った世代。`bootstrap` なら起点をこの run が置いている。
  final GenerationResolution generation;
  final String mode;
  final List<Map<String, Object?>> pushed;
  final List<Map<String, Object?>> stopped;
  final ApplyReport report;
  final AutoResolveReport auto;
  final List<Map<String, Object?>> resolutionsPushed;
  final List<Map<String, Object?>> resolutionsStopped;
  final String? pullError;
  final Map<String, int> counts;

  const RunResult({
    required this.runId,
    required this.generation,
    required this.mode,
    required this.pushed,
    required this.stopped,
    required this.report,
    required this.auto,
    required this.resolutionsPushed,
    required this.resolutionsStopped,
    required this.pullError,
    required this.counts,
  });

  /// 台帳の業務データを書いたか。**画面に一覧を読み直させるかどうかの判定である**
  /// （`非公開資料:ui-state-model.md` §2「更新の共通契約」）。
  ///
  /// 送信だけの run は業務データを変えない（outbox の状態だけが動く）。
  bool get ledgerChanged =>
      report.applied > 0 ||
      report.conflicted > 0 ||
      auto.resolved.isNotEmpty ||
      resolutionsPushed.isNotEmpty;

  /// 何も起きなかった run か。送信・受信・適用・停止のどれも 0 件である。
  bool get idle => counts.values.every((value) => value == 0);
}

class SyncEngine {
  final DbSession session;
  final String profile;
  final String deviceId;
  final Applier applier;
  final String Function() uuid;

  /// 有効世代の転送。**世代を引数で受ける。** 既定値を持たせない — 世代を渡し忘れた呼び出しが
  /// 「別の名前空間へ静かに書く」ことになり、その封筒はどの端末の一覧にも出ない。
  final TransportPort Function(String generationId) transportFor;

  /// バックアップと baseline の保管先。**転送先と同じ場所である。**
  final BackupStorePort store;

  /// **既定は [AutoResolvePolicy.lww] である。** 検証ハーネスだけが
  /// [AutoResolvePolicy.manual] を選ぶ。
  AutoResolvePolicy autoResolve;

  /// 直前に受け付けた排他操作の末尾。`null` なら誰も走っていない。
  Future<void>? _tail;

  /// 状態を読み直す契機だけを通知する。購読や画面状態は持たない。
  final void Function()? onStatusChanged;

  /// 転送を要る操作が今どの一手を進めているかだけを通知する。**ログの語彙は持たない** —
  /// [onStatusChanged] と同じく、事実を渡すだけで、記録するかどうかと文言は呼び出し側が決める。
  ///
  /// Drive との通信（`transport.list`・`pushOutbox`・`store.putBaseline` など）は明示の
  /// タイムアウトを持たない。通信が詰まると `await` が返らないまま待ち続け、**呼び出し側には
  /// 「今どの一手で止まっているか」を知る手段が無かった。** ここが無いままだと、待ちが長引いた
  /// ときの原因の切り分けが「どこにも記録が無い」状態から始まることになる。
  final void Function(String step)? onProgress;

  SyncEngine({
    required this.session,
    required this.profile,
    required this.deviceId,
    required this.transportFor,
    required this.store,
    required Contracts contracts,
    required this.uuid,
    this.autoResolve = AutoResolvePolicy.lww,
    this.onStatusChanged,
    this.onProgress,
  }) : applier = Applier(contracts);

  Db get db => session.db;

  EnvelopeCodec get codec => applier.codec;
  Planner get planner => applier.planner;

  bool get autoResolveEnabled => autoResolve == AutoResolvePolicy.lww;

  /// ローカル発行。業務トランザクション（P3）と `admin fixture seed` が通る経路である。
  ///
  /// 1ステップを一つの原子単位として、集約更新・`applied_events` 追記・`outbox_events` 追記を
  /// 同一トランザクションで確定する。同一ステップ内で同じ実体を続けて更新する場合、2件目は
  /// 1件目の版の上に積む。DB はまだコミット前なので、版はここで持ち回る。
  List<Envelope> emitLocal(List<Envelope> events) {
    final versions = <String, int>{};
    final plans = <WritePlan>[];
    for (final event in events) {
      final key = '${event.entityType}/${event.entityId}';
      final current = versions[key] ??
          applier.aggregates.currentVersion(db, event.entityType, event.entityId);
      plans.add(planner.localEmit(event, currentVersion: current));
      versions[key] = event.resultVersion;
    }
    applier.store.commit(db, plans);
    return events;
  }

  /// 競合を1件解決する。`take` は `local` / `remote` / `auto`。
  Envelope resolveConflictById(String conflictId,
      {required String take, required String now}) {
    final row = getConflict(db, conflictId);
    if (row == null) {
      throw SyncDataError('conflict $conflictId がありません。', code: 'conflict-not-found');
    }
    if (row['state'] != conflictOpen) {
      throw SyncDataError(
          'conflict $conflictId は既に解決済みです（${row['resolved_at_utc']}）。',
          code: 'conflict-resolved');
    }
    return applier.resolveOne(db, row,
        take: take, deviceId: deviceId, eventId: uuid(), now: now);
  }

  /// 最初に開いている競合。手動解決の対象を選ぶ既定の規則である。
  String? firstOpenConflictId() {
    final rows = listConflicts(db, state: conflictOpen);
    return rows.isEmpty ? null : rows.first['conflict_id'] as String;
  }

  /// 転送を要る操作を、**呼ばれた順に一つずつ**通す。
  ///
  /// 同期だったころは、この保証を型が持っていた — `run` の中に待ち点が無いので、二つの run が
  /// 交互に進みようがなかった。非同期にした以上、保証はどこかに書かねばならない。
  ///
  /// **lease では足りない。** lease が守るのはプロセス跨ぎの重複送信で、同じエンジンの中で
  /// 重なった二つの run は同じ lease の持ち主として振る舞う。守られない。
  ///
  /// **最も悪いのは run と復元の重なりである。** 復元は DB ファイルを丸ごと置換するために接続を
  /// 手放して開き直す（`_restore`）。転送を待っている run がその間に再開すると、置き換わった
  /// 台帳に対して古い判断の続きを書く。
  ///
  /// **落とさずに待たせる。** 例外にすると、定期同期と利用者の操作がたまたま重なっただけで
  /// 失敗が見える。待たせても失われるものは無い — 転送を要る操作はどれも冪等か、状態機械が
  /// 途中経過を持っている。
  ///
  /// **入れ子にしない。** ここは再入を許さないので、包むのは外から呼ばれる入口だけにし、
  /// 内側は包まない実装（`_run` など）を呼ぶ。入口が入口を呼ぶと止まる。
  /// 待ち行列が空か。**試験のためだけにある。**
  ///
  /// 鎖を切り忘れても普段の緑は変わらない — 余分に待つだけで、結果は同じである。切れている
  /// ことを直接見る口が無いと、その取りこぼしを機械で縛れない。
  bool get debugIdle => _tail == null;

  Future<T> _exclusive<T>(Future<T> Function() body) async {
    // ここまでは同期に走る。**並びは呼ばれた順で決まる。**
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    if (previous != null) await previous;
    try {
      return await body();
    } finally {
      gate.complete();
      // 自分が最後尾なら鎖を切る。残すと、次の呼び出しが完了済みの Future を1つ余計に待つ。
      if (identical(_tail, gate.future)) _tail = null;
    }
  }

  /// push / pull / run の本体。転送と適用を1つの run にまとめる。
  ///
  /// 走行中の操作があれば、その終わりまで待ってから始まる（`_exclusive`）。
  Future<RunResult> run(String mode, {required String now}) =>
      _exclusive(() async {
        try {
          return await _run(mode, now: now);
        } finally {
          onStatusChanged?.call();
        }
      });

  Future<RunResult> _run(String mode, {required String now}) async {
    // **世代を決めるのが先である。** 転送を組む前に決めないと、世代が変わっているときに旧世代の
    // 名前で1件でも書いてしまう。その封筒はどの端末の一覧にも出ない（静かな消失）。
    // 世代が変わっていれば [GenerationChangedError] がここから出て、通常同期は止まる。
    onProgress?.call('run.generation.resolving');
    final resolution = await useGeneration(establish: true, now: now);
    // **世代を確かめられないまま送受信しない**（2026-10-08）。端末の世代のまま送ると、世代が
    // 変わっていた場合に旧世代の名前で書く（2026-10-04 に Windows で 20 件、どの端末にも
    // 届かなかった）。**認可切れだけは先へ進める** — 書き込みも認可で落ちるので何も書かれず、
    // outbox が `blocked_auth` になって再サインインの状態へ届く（`resolveGeneration` の注記）。
    final unreadable = resolution.unreadable;
    if (resolution.state == generationUnknown &&
        unreadable != null &&
        unreadable is! TransportAuthError) {
      onProgress?.call('run.generation.unreadable');
      throw unreadable;
    }
    onProgress?.call('run.generation.resolved');
    final transport = transportFor(resolution.generationId);

    final runId = uuid();
    transaction(db, () {
      startRun(db,
          runId: runId,
          startedAtUtc: now,
          transport: transport.kind,
          mode: mode);
    });
    onStatusChanged?.call();

    var sent = const <Map<String, Object?>>[];
    var stopped = const <Map<String, Object?>>[];
    if (mode == modePush || mode == modeRun) {
      onProgress?.call('run.push.begin');
      final result = await pushOutbox(db, codec, transport, now: now, runId: runId);
      sent = result.sent;
      stopped = result.stopped;
      onProgress?.call('run.push.done');
    }

    var report = ApplyReport();
    var auto = AutoResolveReport();
    var resolutionsSent = const <Map<String, Object?>>[];
    var resolutionsStopped = const <Map<String, Object?>>[];
    String? pullError;

    if (mode == modePull || mode == modeRun) {
      var incoming = const <RemoteEvent>[];
      onProgress?.call('run.pull.list.begin');
      // **知っている封筒は本文を取らない**（2026-10-08。`sqlite-drive-sync-protocol.md`
      // 「受信は差分で取る」）。一覧の前に1回だけ集める — 一覧の途中で表は変わらない。
      final known = knownIncomingEventIds(db);
      try {
        incoming = await transport.list(known: known.contains);
      } on TransportAuthError catch (exc) {
        // 受信できないだけであり、outbox には触らない。取り込めるものが無いのと
        // 「取り込んだ結果が空」は別である。run の結果に残す。
        pullError = exc.message;
      }
      onProgress?.call('run.pull.list.done');
      report = applier.applyIncoming(db, incoming,
          now: now, runId: runId, conflictIdFactory: uuid);
      onProgress?.call('run.pull.apply.done');

      // 適用フェーズの末尾で自動解決する。off のケースはここを素通りする。
      if (autoResolveEnabled) {
        auto = applier.autoResolveOpenConflicts(db,
            deviceId: deviceId, now: now, uuidFactory: uuid);
      }
      if (mode == modeRun && auto.resolved.isNotEmpty) {
        // 自動解決で生まれた解決イベントを、同じ run のうちに送る。**利用者の一回の操作で
        // 往復を閉じるためである。** 次回の push に任せると、自動解決した端末だけが新しい版を
        // 持ち、相手はまだ競合前の版のままになる。追加の push は一度だけで、pull へは戻らない。
        onProgress?.call('run.push_resolutions.begin');
        final again = await pushOutbox(db, codec, transport, now: now, runId: runId);
        resolutionsSent = again.sent;
        resolutionsStopped = again.stopped;
        onProgress?.call('run.push_resolutions.done');
      }
    }

    final counts = <String, int>{
      ...report.counts(),
      'pushed': sent.length,
      'stopped': stopped.length + resolutionsStopped.length,
      'auto_resolved': auto.resolved.length,
      'resolutions_pushed': resolutionsSent.length,
    };
    transaction(db, () {
      finishRun(db, runId,
          finishedAtUtc: now,
          counts: counts,
          outcome: (stopped.isNotEmpty ||
                  resolutionsStopped.isNotEmpty ||
                  pullError != null)
              ? 'error'
              : 'ok');
    });

    final result = RunResult(
      runId: runId,
      generation: resolution,
      mode: mode,
      pushed: sent,
      stopped: stopped,
      report: report,
      auto: auto,
      resolutionsPushed: resolutionsSent,
      resolutionsStopped: resolutionsStopped,
      pullError: pullError,
      counts: counts,
    );
    // **何も無い run の行を溜めない**（2026-10-08）。前面の周期は 30 秒で、残すと使っている
    // 間ずっと伸びる。この run の行は最終同期として残る。
    if (result.idle && pullError == null) {
      transaction(db, () => pruneIdleRuns(db, keepRunId: runId));
    }
    return result;
  }

  // --- 状態 -----------------------------------------------------------------

  /// いまの状態を1つに決めて返す。**画面はこの値を引くだけである。**
  ///
  /// 導出の規則は `status.dart` にある。ここが持つのは「転送を起こさずに DB だけを読む」という
  /// 一点で、[activeTransport] を通さないのはそのためである。**読みに行くと、認可の切れた端末で
  /// 件数すら見られなくなる。**
  ///
  /// [offline] と [doctorFailed] は端末の記録から読めない事実で、呼び出し側が観測して渡す
  /// （回線は ③、設定・認可・所有の検査は P2・P3）。渡さなければ false であり、その分の状態には
  /// ならない。**推測で埋めない** — 古い失敗から回線を決めると、一度失敗して放置された端末が
  /// 延々とオフラインを名乗り、未送信があることを隠す。
  SyncStatus status({
    required String now,
    bool offline = false,
    bool doctorFailed = false,
  }) {
    final facts =
        readSyncFacts(db, now: now, offline: offline, doctorFailed: doctorFailed);
    return SyncStatus(
      state: deriveState(facts),
      lastSuccessAt: facts.lastSuccessAt,
      autoResolved: facts.autoResolved,
      facts: facts,
    );
  }

  /// 台帳の自己診断。**[status] の `doctorFailed` へ渡す値を作る側である。**
  ///
  /// **[status] がこれを自分で呼ばない。** `doctorFailed` は `offline` と同じ「呼び出し側が
  /// 渡す分」であり、推測で埋めない。加えてこちらは全表を走るので、状態を読むたびに走らせる
  /// ものではない。**何を健全とするかがエンジンの規則、いつ走らせるかが合成層の判断**である。
  ///
  /// **環境の分（データ領域・資格情報・認可）は入らない。** OS で形が違うので
  /// `karita_platform` と `karita_platform_flutter` が持ち、合成層が
  /// [DoctorReport.merge] でまとめる。
  DoctorReport doctor() => ledgerDoctor(db, applier.mapping);

  /// 認可を失って止まった outbox（`blocked_auth`）を、すべて送信待ちへ戻す。戻した件数を返す。
  ///
  /// **再サインインの直後に呼ぶ。** `claimOutbox` は `blocked_auth` を拾わないので、戻さないと
  /// 認可を取り戻しても行は止まったままで、状態は [SyncState.signInRequired] から抜けない。
  /// 自動では戻さない（`admin outbox retry` の注記）— 戻す契機は利用者のサインインである。
  ///
  /// **走行中の run の後に並ぶ。** 古い認可で走っている run が後から `blocked_auth` を
  /// 書き戻すと、戻した行がまた止まる。
  Future<int> retryBlockedAuth({required String now}) => _exclusive(() async {
        final rows = listOutbox(db, state: outboxBlockedAuth);
        if (rows.isEmpty) return 0;
        transaction(db, () {
          for (final row in rows) {
            retryOutbox(db, row['event_id'] as String, now: now);
          }
        });
        onStatusChanged?.call();
        return rows.length;
      });

  // --- 初回起動 --------------------------------------------------------------

  /// この端末が使い始めているか。**初回起動の2択を出すかどうかの唯一の判定である。**
  ///
  /// 世代を持っているか、適用したイベントか送るイベントが1件でもあれば、使い始めている。世代
  /// だけを見ると、世代の解決に失敗したまま業務操作を受けた端末が「未セットアップ」に見え、
  /// [setupFromBackup] がその台帳を置換できてしまう。
  bool get isSetUp =>
      localGeneration(db) != null ||
      _hasRows('applied_events') ||
      _hasRows('outbox_events');

  /// 初回起動の「新しく始める」。**この端末を有効世代へ乗せるだけで、復元しない。**
  ///
  /// 保管先に起点が無ければ現状態を `baseline-0001-` として置き（`bootstrap`）、あれば有効世代に
  /// 乗る（`adopt`）。乗った端末は通常同期でその世代の全イベントを再生する — 「新しく始める」は
  /// そういう意味であり、再生を避けたい利用者は [setupFromBackup] を選ぶ。
  ///
  /// **保管先を読めなければ完了しない。** 世代を確かめないまま始めたことにすると、この端末は
  /// 後から現れた本当の有効世代に気づかず、自分の世代のまま送り続ける。サインインは ③ の仕事で、
  /// 失敗はここに `TransportAuthError` として現れる。
  Future<GenerationResolution> setupFresh({required String now}) =>
      _exclusive(() => _setupFresh(now: now));

  Future<GenerationResolution> _setupFresh({required String now}) async {
    _requireNotSetUp();
    final resolution = await useGeneration(establish: true, now: now);
    if (resolution.state == generationUnknown) {
      throw SyncDataError(
        '保管先を読めないため初回セットアップを完了できません。'
        'サインインと接続を確かめてからやり直してください。',
        code: 'setup-store-unreadable',
      );
    }
    return resolution;
  }

  /// 初回起動の「バックアップから開始」。**順序をここで閉じる。**
  ///
  /// 「サインイン → 一覧 → 選択 → 検証 → 起点を公開 → 置換」のうち、一覧から後ろをこの1関数が
  /// 通す。画面が持つのは2択の提示と、一覧から1件を選ばせることだけである。**順序を画面へ出すと、
  /// 順序事故が画面ごとに起こる。**
  ///
  /// 選べるのは一覧に出るものだけである。索引を読めなかった `.blib`（`BackupListing.skipped`）を
  /// id 指定で通すと、画面に出していないものが正本になる。
  ///
  /// 選んだ時点を新しい正本にする**宣言**であり、新しい世代を始める。他の端末は世代変更を検出
  /// して通常同期を止め、同じ起点へ戻ってくる。
  Future<RestoreOutcome> setupFromBackup(String backupId, {required String now}) =>
      _exclusive(() => _setupFromBackup(backupId, now: now));

  Future<RestoreOutcome> _setupFromBackup(String backupId,
      {required String now}) async {
    _requireNotSetUp();
    resolveBackup(await listBackups(), backupId);
    return _restoreFromBackup(now: now, backupId: backupId);
  }

  /// 初回起動の操作を、使い始めた端末に対して実行させない。
  ///
  /// 2択はアプリの最初の1回だけの問いである。二度目に押せると、[setupFromBackup] が未送信を
  /// 抱えた台帳を置換する。使い始めた後の復元はデータ管理の [restoreFromBackup] を通る — 同じ
  /// 置換でも、そちらは不可逆であることを確認した上での操作である。
  void _requireNotSetUp() {
    if (!isSetUp) return;
    throw SyncDataError(
      'この端末は既に使い始めています。初回起動の操作は一度きりです。'
      '復元はデータ管理の完全復元を使ってください。',
      code: 'setup-already-done',
    );
  }

  bool _hasRows(String table) => db.select('SELECT 1 FROM $table LIMIT 1').isNotEmpty;

  // --- 世代 -----------------------------------------------------------------

  /// 世代を決め、`establish` なら起点を置いて端末に記録する。
  ///
  /// **`establish` は転送先へ書く経路だけが立てる。** 読み取り専用の診断が世代の起点を作ると、
  /// 「見ただけで状態が変わる」道具になる。読み取りのときに世代がまだ無ければ、読めるイベントも
  /// 無い。
  Future<GenerationResolution> useGeneration(
      {required bool establish, required String now}) async {
    final resolution = await resolveGeneration(store, localGeneration(db),
        newGenerationId: uuid());
    if (!establish) return resolution;

    if (resolution.needsBaseline) {
      await publishFirstBaseline(resolution, now: now);
    }
    // **確かめられなかった世代は記録しない。** 保管先を読めていないので、書くと次回から
    // 「持っている」ことになり、本当の有効世代との突き合わせが `changed` に倒れる。
    if (resolution.state != generationUnknown) {
      final local = localGeneration(db);
      if (local == null ||
          local.id != resolution.generationId ||
          local.seq != resolution.seq) {
        setLocalGeneration(db, resolution.generationId, resolution.seq);
      }
    }
    return resolution;
  }

  /// 保管先に baseline が1つも無いときに、現状態を世代の起点として置く。
  ///
  /// **これは復元ではない。** 最初の1台が転送先へ書き始めるとき、誰かが起点を置かなければ
  /// 有効世代が決まらない。二台目以降は `adopt` でこの世代に乗る。
  ///
  /// 起点にするのは現在の DB そのものである。`export` と同じ `.blib` を作って
  /// `baseline-0001-` の名前で公開する。**バックアップ一覧には出ない** — 名前が `backup-` では
  /// ないためで、利用者が「作った覚えのないバックアップ」を見ることはない。
  Future<void> publishFirstBaseline(GenerationResolution resolution,
      {required String now}) async {
    final work = Directory.systemTemp.createTempSync('blib-baseline-');
    try {
      final staged = '${work.path}${Platform.pathSeparator}baseline$backupSuffix';
      createBackup(
        _requireDbPath(),
        staged,
        now: now,
        backupId: uuid(),
        sourceDeviceId: deviceId,
        sourceProfile: profile,
        sourcePlatform: platformOf(deviceId),
      );
      await store.putBaseline(resolution.seq, resolution.generationId, staged);
    } finally {
      work.deleteSync(recursive: true);
    }
  }

  /// 有効世代の転送。**転送を要る操作の入口はこれを使う。**
  ///
  /// 世代を渡し忘れると別の名前空間を覗くことになり、一覧が「0件」と答える。
  ///
  /// `establish` は**転送先へ書く経路だけが立てる。** 読み取り専用の診断が起点を作ると、
  /// 「見ただけで状態が変わる」道具になる。
  Future<TransportPort> activeTransport(
          {required bool establish, required String now}) async =>
      transportFor(
          (await useGeneration(establish: establish, now: now)).generationId);

  // --- バックアップ ----------------------------------------------------------

  /// 完全バックアップを作り、保管先へ入れる。`outPath` を渡したときは保管先へ入れない。
  ///
  /// 最終バックアップ日時は**保管に成功した後にだけ**進める。先に書くと、載せられなかったときに
  /// 「バックアップ済み」と表示される。この値は端末ごとの事実なので `.blib` には入らない。
  Future<ExportOutcome> exportBackup({required String now, String? outPath}) =>
      _exclusive(() => _exportBackup(now: now, outPath: outPath));

  Future<ExportOutcome> _exportBackup(
      {required String now, String? outPath}) async {
    final backupId = uuid();
    final work = Directory.systemTemp.createTempSync('blib-export-');
    try {
      onProgress?.call('backup.stage.begin');
      final staged = '${work.path}${Platform.pathSeparator}${backupName(backupId)}';
      final manifest = createBackup(
        _requireDbPath(),
        staged,
        now: now,
        backupId: backupId,
        sourceDeviceId: deviceId,
        sourceProfile: profile,
        sourcePlatform: platformOf(deviceId),
      );
      final size = File(staged).lengthSync();
      onProgress?.call('backup.stage.done');

      if (outPath != null) {
        File(outPath).parent.createSync(recursive: true);
        File(staged).copySync(outPath);
        return ExportOutcome(
            backupId: backupId,
            manifest: manifest,
            storedIn: 'local',
            location: outPath,
            bytes: size);
      }

      onProgress?.call('backup.upload.begin');
      final remoteId = await store.put(backupId, staged);
      onProgress?.call('backup.upload.done');
      transaction(db, () => setState(db, stateLastBackupAt, now));
      return ExportOutcome(
          backupId: backupId,
          manifest: manifest,
          storedIn: store.kind,
          location: remoteId,
          bytes: size);
    } finally {
      work.deleteSync(recursive: true);
    }
  }

  Future<BackupListing> listBackups() => store.list();

  /// 保管先に有効世代があるか。**初回起動の2択を出し分けるためにある。**
  ///
  /// あれば、新しい端末の選択は「合流する」（`adopt`。誰も止まらない）と「バックアップの時点へ
  /// 戻す」（宣言。他の端末が止まる）の二つになる。**新しい端末を足す操作として後者を選ばせない**
  /// ために、画面がこの事実で言葉と確認を変える。
  Future<bool> hasActiveGeneration() async =>
      activeBaseline(await store.listBaselines()) != null;

  Future<int> deleteBackup(String backupId) => store.delete(backupId);

  /// バックアップを指しての復元。**これは宣言である。**
  ///
  /// 「この時点を新しい正本にする」という宣言であり、**新しい世代を始める。** 他の端末は世代
  /// 変更を検出して通常同期を止める。旧世代のまま復元すると、転送先に残った復元前のイベントを
  /// 次の pull が拾い、**巻き戻したはずの更新が戻る。**
  ///
  /// 順序は「**検証 → 起点を公開 → 現 DB を置換**」である。検証を先にしないと、読めない
  /// バックアップを指す起点が有効世代になり、現 DB が無事でも他の全端末がその壊れた起点からの
  /// 完全復元を求められる。公開を置換より先にするのは逆の理由で、置換に成功して公開に失敗した
  /// 端末は旧世代の名前で新しい DB の更新を送り出す。
  Future<RestoreOutcome> restoreFromBackup({
    required String now,
    String? backupId,
    String? path,
  }) =>
      _exclusive(() => _restoreFromBackup(now: now, backupId: backupId, path: path));

  Future<RestoreOutcome> _restoreFromBackup({
    required String now,
    String? backupId,
    String? path,
  }) async {
    if ((backupId == null) == (path == null)) {
      throw SyncDataError('復元元は backupId か path のどちらか一つを指定します。',
          code: 'usage');
    }
    final work = Directory.systemTemp.createTempSync('blib-import-');
    try {
      final String source;
      final String label;
      if (backupId != null) {
        source = '${work.path}${Platform.pathSeparator}${backupName(backupId)}';
        onProgress?.call('restore.download.begin');
        await store.get(backupId, source);
        onProgress?.call('restore.download.done');
        label = '${store.kind} / $backupId';
      } else {
        source = path!;
        label = path;
      }
      return await _restore(source, label: label, now: now, baseline: null);
    } finally {
      work.deleteSync(recursive: true);
    }
  }

  /// 有効世代の起点そのものへ戻る。**これは参加であり、世代を進めない。**
  ///
  /// 進めると、`changed` で止められた端末が復元するたびに世代が1つ上がって今度は相手が止まる。
  /// 二端末は交互に止まり続け、**同じ世代へ戻る経路がどこにも無くなる。** 世代を持たない端末の
  /// `adopt` を `changed` と区別しているのと同じ理由で、参加は切替ではない。
  Future<RestoreOutcome> restoreFromBaseline({required String now}) =>
      _exclusive(() => _restoreFromBaseline(now: now));

  Future<RestoreOutcome> _restoreFromBaseline({required String now}) async {
    onProgress?.call('restore.baseline.list.begin');
    final active = activeBaseline(await store.listBaselines());
    onProgress?.call('restore.baseline.list.done');
    if (active == null) {
      throw SyncDataError(
        '保管先に世代の起点がありません。起点への復元は乗る先がある端末のための操作です。',
        code: 'generation-no-baseline',
      );
    }
    final work = Directory.systemTemp.createTempSync('blib-import-');
    try {
      final source = '${work.path}${Platform.pathSeparator}'
          '${baselineName(active.seq, active.generationId)}';
      onProgress?.call('restore.download.begin');
      await store.getBaseline(active, source);
      onProgress?.call('restore.download.done');
      return await _restore(source,
          label: '${store.kind} / baseline ${_seqText(active.seq)}',
          now: now,
          baseline: active);
    } finally {
      work.deleteSync(recursive: true);
    }
  }

  /// ［復元］の「空にしてやり直す」。**これも宣言である** — 手順は [restoreFromBackup] と
  /// 同じで、渡す `.blib` が業務データを持たない空の台帳であるだけである。新しい世代を始め、
  /// 他の端末は世代変更を検出して通常同期を止める。
  ///
  /// **アカウント（token）や保管先に残る過去のバックアップ・イベントは変えない。** 消えるのは
  /// この端末が置換する `library.db` の業務データだけである。Drive 側を含めた完全な作り直しは
  /// 別アカウントでの初回セットアップ、または保管先の接続解除が要る — ここは対象にしない。
  Future<RestoreOutcome> restoreEmpty({required String now}) =>
      _exclusive(() => _restoreEmpty(now: now));

  Future<RestoreOutcome> _restoreEmpty({required String now}) async {
    final work = Directory.systemTemp.createTempSync('blib-reset-');
    try {
      onProgress?.call('reset.empty_db.begin');
      final emptyDbPath = '${work.path}${Platform.pathSeparator}$dbName';
      final empty = SqliteDb.open(emptyDbPath);
      try {
        migrate(empty, now: now);
      } finally {
        empty.close();
      }
      onProgress?.call('reset.empty_db.done');
      final staged = '${work.path}${Platform.pathSeparator}empty$backupSuffix';
      createBackup(
        emptyDbPath,
        staged,
        now: now,
        backupId: uuid(),
        sourceDeviceId: deviceId,
        sourceProfile: profile,
        sourcePlatform: platformOf(deviceId),
      );
      return await _restore(staged, label: 'empty', now: now, baseline: null);
    } finally {
      work.deleteSync(recursive: true);
    }
  }

  Future<RestoreOutcome> _restore(
    String source, {
    required String label,
    required String now,
    required BaselineRef? baseline,
  }) async {
    final dbPath = _requireDbPath();

    // 1. 検証。ここで落ちれば現 DB も保管先も元のままである。
    onProgress?.call('restore.precheck.begin');
    precheckBackup(source, now: now);
    onProgress?.call('restore.precheck.done');

    // 2. 起点を公開する。**参加（baseline への復元）は公開しない** — 起点は既に保管先にあり、
    //    これから乗る世代のものである。ここで新しい起点を置くと、止められた端末が復元する
    //    たびに世代が上がって今度は相手が止まる。
    final int seq;
    final String generationId;
    if (baseline != null) {
      seq = baseline.seq;
      generationId = baseline.generationId;
    } else {
      onProgress?.call('restore.generation.seq.resolving');
      seq = await nextGenerationSeq(store);
      generationId = uuid();
      onProgress?.call('restore.baseline.publish.begin');
      await store.putBaseline(seq, generationId, source);
      onProgress?.call('restore.baseline.publish.done');
    }

    // 3. 置換。**不可逆な一歩はここだけである。** 置換の前に接続を手放す。
    onProgress?.call('restore.replace.begin');
    session.detach();
    final BackupOutcome outcome;
    try {
      outcome = restoreBackup(source, dbPath,
          now: now,
          deviceId: deviceId,
          profile: profile,
          generationId: generationId,
          generationSeq: seq);
    } finally {
      session.reopen();
    }
    onProgress?.call('restore.replace.done');

    return RestoreOutcome(
      source: label,
      manifest: outcome.manifest,
      counts: outcome.counts,
      generationId: generationId,
      seq: seq,
      declared: baseline == null,
    );
  }

  String _requireDbPath() {
    final path = session.path;
    if (path == null) {
      throw SyncDataError(
        'メモリ DB ではバックアップと復元を扱えません。ファイルの DB が要ります。',
        code: 'db-memory',
      );
    }
    return path;
  }
}

/// `<platform>-<uuid4>` の前半。一覧表示と診断のためのメタデータである。
///
/// **復元可否の分岐には使わない。** PC 用と Android 用でバックアップを分けない判断がここに現れる。
String platformOf(String deviceId) {
  final head = deviceId.split('-').first;
  return head.isEmpty ? 'unknown' : head;
}

String _seqText(int seq) => seq.toString().padLeft(seqWidth, '0');

class ExportOutcome {
  final String backupId;
  final Map<String, Object?> manifest;
  final String storedIn;
  final String location;
  final int bytes;

  const ExportOutcome({
    required this.backupId,
    required this.manifest,
    required this.storedIn,
    required this.location,
    required this.bytes,
  });
}

class RestoreOutcome {
  final String source;
  final Map<String, Object?> manifest;
  final Map<String, int> counts;
  final String generationId;
  final int seq;

  /// 宣言（新しい世代を始めた）なら true、参加（有効世代の起点へ戻った）なら false。
  final bool declared;

  const RestoreOutcome({
    required this.source,
    required this.manifest,
    required this.counts,
    required this.generationId,
    required this.seq,
    required this.declared,
  });

  String? get backupId => manifest['backup_id'] as String?;
}
