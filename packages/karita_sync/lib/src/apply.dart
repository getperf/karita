/// 受信と適用。
///
/// 転送先の封筒を読み、適用判定表に従って一件ずつ処理する。判定そのものは
/// `karita_contract` の `decide`（純関数層）が持ち、ここは SQLite と転送を繋ぐだけである。
///
/// 守る規則が3つある。
///
/// 1. **1受信イベント = 1トランザクション。** run 全体を一つのトランザクションにすると、
///    途中でプロセスが落ちたときに全部が消える。受入ケース11 の「再生途中のプロセス終了からの
///    再開」が成立しない。`sync_runs` は観測用であって原子性の単位ではない。
/// 2. **`pending_events` の再走査は不動点ループ。** 1回では足りない。v5、v4、v3 の順に届くと、
///    1パスで解ける gap は v3 の1件だけである。
/// 3. **壊れた封筒1件で run を止めない。** その1件を `invalid` として記録し、既存データと
///    outbox は不変のまま次へ進む。取り込めないイベントを転送先から消しはしないので、直せば
///    次の run で取り込める。
///
/// 移送元: book-sync-model の `src/bsync_core/sync.py`。
library;

import 'package:karita_contract/canonical.dart' as canonical;
import 'package:karita_contract/decide.dart' as decide;
import 'package:karita_contract/karita_contract.dart';

import 'plan.dart';
import 'store.dart';
import 'transport.dart';

/// 不動点ループの上限。滞留1件につき最低1回は進むため、これを超えるのは実装の誤りである。
const int maxRescanPasses = 100;

/// 同一集約の自動解決の上限。純関数ポリシーの下で往復は起きないが、`device_id` の重複や壊れた
/// 時計への保険。**設定にしない**（ドメイン定数）。上限を超えたら自動を止め、競合を開いたまま残す。
const int autoResolveGuardMax = 10;

/// 上限を数える窓。**累計で数えない。** 製品では自動解決を常時有効にするため、累計だと長く使う
/// 集約が正常な利用のまま上限へ達し、以後その集約だけ永久に自動解決されなくなる。往復は同一 run
/// か連続する run の中で起きるので、1日の窓で十分に捕まえられる。
const int autoResolveGuardWindowSeconds = 24 * 60 * 60;

const Map<String, String> outcomeByAction = {
  decide.apply: 'applied',
  decide.applyResolution: 'applied',
  decide.ignore: 'ignored',
  decide.pendingGap: 'pending_gap',
  decide.pendingSchema: 'pending_schema',
  decide.conflict: 'conflict',
};

class ApplyReport {
  int fetched = 0;
  int applied = 0;
  int ignored = 0;
  int pending = 0;
  int conflicted = 0;
  int invalid = 0;

  /// 転送先で重複排除された件数。**DB へは持たせない**（`sync_runs` は観測用であって原子性の
  /// 単位ではない）。
  int duplicate = 0;
  int duplicateMismatch = 0;

  /// eventId ごとの最終結果。再走査で gap → applied と動くため、後の結果で上書きする。
  final Map<String, Map<String, Object?>> seen = {};

  List<Map<String, Object?>> get events {
    final list = seen.values.toList();
    list.sort((a, b) => '${a['event_id']}'.compareTo('${b['event_id']}'));
    return list;
  }

  void note(Map<String, Object?> entry) {
    seen['${entry['event_id']}'] = Map<String, Object?>.from(entry);
  }

  Map<String, int> counts() => {
        'fetched': fetched,
        'applied': applied,
        'ignored': ignored,
        'pending': pending,
        'conflicted': conflicted,
        'invalid': invalid,
        'duplicate': duplicate,
        'duplicate_mismatch': duplicateMismatch,
      };
}

/// 判定の入口に立てた1件。**まだスキーマ検証は通っていない。**
class Incoming {
  final String eventId;
  final String text;
  final int schemaVersion;
  final String? entityType;
  final String? entityId;
  final int? baseVersion;
  final List<String> resolves;

  const Incoming({
    required this.eventId,
    required this.text,
    required this.schemaVersion,
    required this.entityType,
    required this.entityId,
    required this.baseVersion,
    required this.resolves,
  });
}

class AutoResolveReport {
  final List<Map<String, Object?>> resolved = [];

  /// 反復ガードに掛かり、自動では解かず開いたまま残した競合（要対応）。
  final List<Map<String, Object?>> guarded = [];
}

/// 適用の本体。プロファイル1つぶんの DB に対して働く。
class Applier {
  final Contracts contracts;
  final EnvelopeCodec codec;
  final Mapping mapping;
  final Aggregates aggregates;
  final Store store;
  final Planner planner;

  Applier._(this.contracts, this.codec, this.mapping, this.aggregates, this.store,
      this.planner);

  factory Applier(Contracts contracts) {
    final mapping = Mapping(contracts);
    final aggregates = Aggregates(mapping);
    return Applier._(contracts, EnvelopeCodec(contracts), mapping, aggregates,
        Store(aggregates), Planner(mapping));
  }

  /// 判定に要るローカルの状態を写す。
  ///
  /// `entityType` が読めない（未対応版など）場合、集約の版は問わない。判定表1行目で先に落ちる
  /// ため 0 を渡してよい。
  ///
  /// **② が扱わない `entityType` も 0 を返す。** 版を引きに行くと `specFor` が
  /// `entity-type-unsupported` を投げ、**判定より先に run 全体が止まる。** ここは判定の材料を
  /// 集めるだけの場所であり、受理するかどうかを決める場所ではない。受理しない封筒は
  /// `_handle` が1件だけ `invalid` として弾く。
  ///
  /// **弾くのを判定の後に置くのは、判定表1行目を守るためである。** 未対応の `schemaVersion` は
  /// `entityType` を見ずに `pending(reason='schema')` へ行く。ここで先に落とすと、まだ知らない
  /// 版で宣言された種別が `invalid` へ回り、アプリを更新しても取り込めなくなる。
  decide.LocalState _localState(Db db, String? entityType, String? entityId) {
    var current = 0;
    if (entityType != null && entityId != null && mapping.handles(entityType)) {
      current = aggregates.currentVersion(db, entityType, entityId);
    }
    return decide.LocalState(
      currentVersion: current,
      appliedEventIds: appliedEventIds(db),
      openConflictRemoteEventIds: openConflictRemoteEventIds(db),
      localEventIds: localEventIds(db),
    );
  }

  /// 判定に要る最小限を読む。**スキーマ検証はしない。**
  ///
  /// `schemaVersion` は封筒全体の検証より先に読む。未対応の版では封筒の形自体が変わりうるため、
  /// スキーマ検証の失敗として扱ってはならない。`eventId` が読めなければ保持すらできない。
  Incoming? parseIncoming(String text) {
    Object? obj;
    try {
      obj = loadsJson(text, label: '封筒');
    } on SyncDataError {
      return null;
    }
    if (obj is! Map<String, Object?>) return null;

    final int schemaVersion;
    try {
      schemaVersion = codec.readSchemaVersion(obj);
    } on SyncDataError {
      return null;
    }
    final eventId = obj['eventId'];
    if (eventId is! String || eventId.isEmpty) return null;

    final rawBase = obj['baseVersion'];
    final entityType = obj['entityType'];
    final entityId = obj['entityId'];
    final rawResolves = obj['resolvesEventIds'];

    return Incoming(
      eventId: eventId,
      text: text,
      schemaVersion: schemaVersion,
      entityType: entityType is String ? entityType : null,
      entityId: entityId is String ? entityId : null,
      baseVersion: (rawBase is int && rawBase is! bool) ? rawBase : null,
      resolves: rawResolves is List
          ? [for (final item in rawResolves) if (item is String) item]
          : const [],
    );
  }

  /// 1件を処理する。適用が進んだら true。
  ///
  /// **判定を全て済ませてから書く。** `applied_events` の主キー衝突を例外で拾う作りにすると、
  /// 同一トランザクションで先に集約を書いた後に落ちる経路ができる。
  ///
  /// 保留から出た件（`ignore` と `conflict` に落ちたもの）は `pending_events` から消す。
  /// 残すと、再走査のたびに同じ conflict 行が増える。
  bool handle(
    Db db,
    Incoming item, {
    required String now,
    required String runId,
    required ApplyReport report,
    required String Function() conflictIdFactory,
  }) {
    final state = _localState(db, item.entityType, item.entityId);
    final protected =
        item.entityType == entityBookPreference || item.entityType == entityLoan
        ? aggregates.read(db, item.entityType!, item.entityId ?? '')
        : null;
    final legacyWrite =
        protected != null &&
        ((item.schemaVersion < 3 &&
                (protected['shelf_token'] != null ||
                    protected['first_return_at_utc'] != null)) ||
            (item.schemaVersion < 4 &&
                item.entityType == entityBookPreference &&
                (protected['wanted_registered_at_utc'] != null ||
                    protected['read_registered_at_utc'] != null))) &&
        !state.appliedEventIds.contains(item.eventId);
    // 旧スナップショットは新しい本棚の因果情報を消してしまう。未適用のまま保持する。
    final decision = legacyWrite
        ? const decide.Decision(
            decide.pendingSchema,
            '本棚導入後の集約へ旧版からの書込みがあります。全端末を更新し、旧端末の操作を確認してください。',
            1,
          )
        : decide.decide(
            schemaVersion: item.schemaVersion,
            eventId: item.eventId,
            // 1行目（未対応版）で落ちる場合、baseVersion は読めていなくてよい。
            baseVersion: item.baseVersion ?? 0,
            supportedSchemaVersions: contracts.supportedSchemaVersions,
            resolvesEventIds: item.resolves,
            state: state,
          );

    final entry = <String, Object?>{
      'event_id': item.eventId,
      'entity_type': item.entityType,
      'entity_id': item.entityId,
      'action': decision.action,
      'row': decision.row,
      'reason': decision.reason,
    };

    bool markInvalid(SyncDataError exc) {
      transaction(db, () {
        recordAttempt(db,
            runId: runId,
            eventId: item.eventId,
            direction: 'pull',
            outcome: 'invalid',
            detail: '[${exc.code}] ${exc.message}',
            atUtc: now);
      });
      report.invalid++;
      report.note({...entry, 'action': 'invalid', 'reason': exc.message});
      return false;
    }

    if (decision.action == decide.ignore) {
      transaction(db, () {
        deletePending(db, item.eventId);
        recordAttempt(db,
            runId: runId,
            eventId: item.eventId,
            direction: 'pull',
            outcome: 'ignored',
            detail: decision.reason,
            atUtc: now);
      });
      report.ignored++;
      report.note(entry);
      return false;
    }

    final pendingReason = decision.pendingReason;
    if (pendingReason != null) {
      transaction(db, () {
        recordPending(db,
            eventId: item.eventId,
            reason: pendingReason,
            entityType: item.entityType,
            entityId: item.entityId,
            baseVersion: item.baseVersion,
            envelope: item.text,
            receivedAtUtc: now);
        recordAttempt(db,
            runId: runId,
            eventId: item.eventId,
            direction: 'pull',
            outcome: outcomeByAction[decision.action]!,
            detail: decision.reason,
            atUtc: now);
      });
      report.note(entry);
      return false;
    }

    // ここから先は封筒を全て検証する。形が壊れていればこの1件だけを弾き、run は止めない。
    //
    // **`specFor` を同じ try に入れる。** 封筒の `entityType` enum は ② が扱う集約より広く
    // （宣言はあるが実装が無い種別がある）、落とした種別の封筒も転送先に残る。どちらも集約行を
    // 触れないという同じ事実であり、ここで1件だけ弾いて run は続ける。**この後の
    // `aggregates.read` と `remoteApply` はどちらも表を要求するため、この検査より後に置く。**
    final Envelope envelope;
    try {
      envelope = codec.loads(item.text);
      mapping.specFor(envelope.entityType);
    } on SyncDataError catch (exc) {
      return markInvalid(exc);
    }

    if (decision.action == decide.conflict) {
      // 競合したイベントは applied_events に入らないため、run のたびに6行目へ落ちる。既に行が
      // あるものを数え直さないと、同じリモートイベントの conflict 行が run ごとに増え続ける。
      // 解決済みも含めて見る — 決着したものを再び持ち出さない。
      if (conflictedRemoteEventIds(db).contains(envelope.eventId)) {
        transaction(db, () {
          deletePending(db, item.eventId);
          recordAttempt(db,
              runId: runId,
              eventId: item.eventId,
              direction: 'pull',
              outcome: 'conflict',
              detail: '既に conflict 行がある',
              atUtc: now);
        });
        report.note({...entry, 'reason': '既に conflict 行がある'});
        return false;
      }

      final localRow = aggregates.read(db, envelope.entityType, envelope.entityId);
      final localHash = localRow == null
          ? null
          : canonical.payloadHash(mapping.rowToPayload(envelope.entityType, localRow));
      final localEventId = eventIdForVersion(
          db, envelope.entityType, envelope.entityId, state.currentVersion);
      transaction(db, () {
        deletePending(db, item.eventId);
        recordConflict(db,
            conflictId: conflictIdFactory(),
            entityType: envelope.entityType,
            entityId: envelope.entityId,
            localVersion: state.currentVersion,
            localPayloadHash: localHash,
            localEventId: localEventId,
            remoteEventId: envelope.eventId,
            remoteBaseVersion: envelope.baseVersion,
            remoteResultVersion: envelope.resultVersion,
            remoteEnvelope: item.text,
            detectedAtUtc: now);
        recordAttempt(db,
            runId: runId,
            eventId: item.eventId,
            direction: 'pull',
            outcome: 'conflict',
            detail: decision.reason,
            atUtc: now);
      });
      report.conflicted++;
      report.note(entry);
      return false;
    }

    // apply / apply_resolution。
    final WritePlan writePlan;
    try {
      writePlan = planner.remoteApply(envelope, appliedAtUtc: now);
    } on SyncDataError catch (exc) {
      return markInvalid(exc);
    }

    transaction(db, () {
      store.write(db, writePlan);
      deletePending(db, item.eventId);
      if (decision.action == decide.applyResolution) {
        closeResolvedConflicts(db, envelope, now);
      }
      recordAttempt(db,
          runId: runId,
          eventId: item.eventId,
          direction: 'pull',
          outcome: 'applied',
          detail: decision.reason,
          atUtc: now);
    });
    report.applied++;
    report.note(entry);
    return true;
  }

  /// 解決イベントを適用したとき、決着した conflict を閉じる。
  ///
  /// `resolvesEventIds` が名指しした行に加え、同じ集約に残る未解決の行のうち
  /// `remote_result_version` が新しいローカル版以下のものも閉じる。再評価しないと、既に決着した
  /// 内容の行が利用者に残り続ける。
  void closeResolvedConflicts(Db db, Envelope envelope, String now) {
    final named = envelope.resolvesEventIds.toSet();
    for (final row in openConflictsFor(db, envelope.entityType, envelope.entityId)) {
      final superseded =
          (row['remote_result_version'] as int) <= envelope.resultVersion;
      if (named.contains(row['remote_event_id'] as String) || superseded) {
        resolveConflict(db, row['conflict_id'] as String,
            resolvedAtUtc: now, resolutionEventId: envelope.eventId);
      }
    }
  }

  /// 受信した封筒を適用し、`pending_events` を不動点まで再走査する。
  ApplyReport applyIncoming(
    Db db,
    List<RemoteEvent> incoming, {
    required String now,
    required String runId,
    required String Function() conflictIdFactory,
    ApplyReport? report,
  }) {
    final result = report ?? ApplyReport();

    for (final item in incoming) {
      result.fetched++;
      // 転送先で落とした複製を数える。fetched は**ファイル数ではなく相異なる eventId 数**で
      // あり、重複は適用の対象ではない。それでも落とした事実は見えなければならない。
      if (item.duplicateRemoteIds.isNotEmpty) {
        result.duplicate += item.duplicateRemoteIds.length;
        if (item.duplicateMismatch) result.duplicateMismatch++;
      }
      final parsed = parseIncoming(item.text);
      if (parsed == null) {
        // eventId も読めないため pending にも置けない。転送先には残るので、直せば次に入る。
        result.invalid++;
        result.note({
          'event_id': item.eventId ?? item.remoteId,
          'action': 'invalid',
          'reason': '封筒として読めません（${item.remoteId}）',
        });
        continue;
      }
      handle(db, parsed,
          now: now,
          runId: runId,
          report: result,
          conflictIdFactory: conflictIdFactory);
    }

    rescan(db,
        now: now, runId: runId, report: result, conflictIdFactory: conflictIdFactory);
    result.pending = listPending(db).length;
    return result;
  }

  /// `pending_events` を不動点まで再走査する。
  ///
  /// **1回では足りない。** v5、v4、v3 の順に届いた場合、1パスで解ける gap は v3 の1件だけで、
  /// 残りは次の run まで滞留する。適用が1件でも進む限り繰り返す。
  ///
  /// `gap` は先行イベントの到着で解け、`schema` はアプリを更新した後の再走査で解ける。
  int rescan(
    Db db, {
    required String now,
    required String runId,
    required ApplyReport report,
    required String Function() conflictIdFactory,
    String? reason,
  }) {
    var total = 0;
    for (var pass = 0; pass < maxRescanPasses; pass++) {
      var progressed = 0;
      for (final row in listPending(db, reason: reason)) {
        final parsed = parseIncoming(row['envelope'] as String);
        if (parsed == null) continue; // 保持時に読めているはず。
        if (handle(db, parsed,
            now: now,
            runId: runId,
            report: report,
            conflictIdFactory: conflictIdFactory)) {
          progressed++;
        }
      }
      total += progressed;
      if (progressed == 0) return total;
    }
    throw SyncDataError(
        'pending_events の再走査が $maxRescanPasses 回で収束しませんでした。',
        code: 'rescan-not-converging');
  }

  // --- 解決（手動と自動）-----------------------------------------------------

  /// 競合の解決イベントを組む。版は max(ローカル版, リモートの `resultVersion`) + 1。
  ///
  /// 手動解決と自動解決の両方がこれを使う。版の規則を二箇所に置くと、片方だけ直して相手端末が
  /// 再び競合と判定し、往復が終わらなくなる。
  Envelope resolutionEnvelope(
    Db db,
    Map<String, Object?> conflictRow, {
    required Map<String, Object?> payload,
    required Map<String, Object?> remoteObj,
    required String take,
    required String deviceId,
    required String eventId,
    required String now,
  }) {
    final entityType = conflictRow['entity_type'] as String;
    final entityId = conflictRow['entity_id'] as String;
    final localVersion = aggregates.currentVersion(db, entityType, entityId);
    final remoteResult = conflictRow['remote_result_version'] as int;
    final baseVersion = localVersion > remoteResult ? localVersion : remoteResult;
    final resolves = <String>[conflictRow['remote_event_id'] as String];
    final localEventId = conflictRow['local_event_id'];
    if (localEventId is String && !resolves.contains(localEventId)) {
      resolves.add(localEventId);
    }
    return codec.build(
      eventId: eventId,
      deviceId: deviceId,
      createdAtUtc: now,
      entityType: entityType,
      entityId: entityId,
      // **操作は「採った側」から決める。** payload と operation の出所が食い違うと、解決が
      // 内容と削除状態を別々のところから取ってくることになる。
      //
      // - `remote` を採ったなら、リモートの封筒の操作をそのまま使う。
      // - `local` を採ったなら、**ローカルの集約行が削除済みかどうか**で決める。
      //
      // **どちらも実害が出ていた。** リモートの操作を常に使っていたため、(1) ローカルが勝った
      // のにリモートが tombstone だと行が消え、(2) ローカルが削除済みなのにリモートが upsert
      // だと、直前に適用した tombstone が「値の無い、消えていない行」として復活していた。
      // (2) は復元直後に踏みやすい — 起点の封筒を引き戻すため、全集約に競合が1件立つ
      // （`非公開資料:sqlite-drive-sync-protocol.md`）。
      operation: take == decide.autoRemote
          ? (remoteObj['operation'] ?? operationUpsert)
          : (_locallyDeleted(db, entityType, entityId)
              ? operationTombstone
              : operationUpsert),
      baseVersion: baseVersion,
      resultVersion: baseVersion + 1,
      payload: payload,
      resolvesEventIds: resolves,
    );
  }

  /// ローカルの集約行が tombstone 済みか。**削除列を持たない集約は常に `false`。**
  bool _locallyDeleted(Db db, String entityType, String entityId) {
    if (!mapping.specFor(entityType).hasIsDeleted) return false;
    final row = aggregates.read(db, entityType, entityId);
    return (row?['is_deleted'] as int? ?? 0) != 0;
  }

  /// 競合を LWW で解く側を決める。`take` は `local` か `remote`。
  ///
  /// 判定そのものは純関数 `decide.autoTake` が持ち、ここは決定キーを SQLite とリモート封筒から
  /// 写すだけである。ローカル側の業務時刻・端末は集約の版列から、リモート側は封筒の
  /// `createdAtUtc` / `deviceId` から取る。
  ///
  /// **第3キーは両側とも payloadHash である。** ローカル側は現在の集約スナップショットから
  /// 計算し、リモート側は封筒が持つ値をそのまま使う。payload は更新後の全体スナップショット
  /// なので、この二つは同じ更新に対して必ず同値になる。3要素すべてを同じ出所から取ることで、
  /// 二端末が同じ勝者を選ぶ。
  String autoSide(Db db, Map<String, Object?> conflictRow, Map<String, Object?> remoteObj) {
    final entityType = conflictRow['entity_type'] as String;
    final entityId = conflictRow['entity_id'] as String;
    final localRow = aggregates.read(db, entityType, entityId);
    if (localRow == null) {
      // 競合が立つとき集約は現在版を持つはずだが、無ければ採れるのは remote だけである。
      return decide.autoRemote;
    }
    return decide.autoTake(
      local: decide.Side(
        localRow['updated_at_utc'] as String,
        localRow['updated_by_device_id'] as String,
        canonical.payloadHash(mapping.rowToPayload(entityType, localRow)),
      ),
      remote: decide.Side(
        remoteObj['createdAtUtc'] as String,
        remoteObj['deviceId'] as String,
        remoteObj['payloadHash'] as String,
      ),
    );
  }

  /// take が採る側の payload。payload は全体スナップショットなのでフィールド合成しない。
  Map<String, Object?> resolutionPayload(
    Db db,
    Map<String, Object?> conflictRow, {
    required String take,
    required Map<String, Object?> remoteObj,
  }) {
    if (take == decide.autoRemote) {
      return Map<String, Object?>.from(
          (remoteObj['payload'] as Map?) ?? const <String, Object?>{});
    }
    final entityType = conflictRow['entity_type'] as String;
    final entityId = conflictRow['entity_id'] as String;
    final localRow = aggregates.read(db, entityType, entityId);
    if (localRow == null) {
      throw SyncDataError(
        '$entityType $entityId がローカルにありません。local を採れません。',
        code: 'conflict-no-local',
      );
    }
    return mapping.rowToPayload(entityType, localRow);
  }

  /// 競合を1件解決し、解決イベントを outbox へ積む。手動解決（`conflict resolve`）の本体。
  ///
  /// 集約更新・`applied_events`・outbox 追記・conflict の解決を同一トランザクションで確定する。
  /// 途中で落ちて「解決済みだがイベントが無い」状態を作らない。
  Envelope resolveOne(
    Db db,
    Map<String, Object?> conflictRow, {
    required String take,
    required String deviceId,
    required String eventId,
    required String now,
  }) {
    final remoteObj = loadsJson(conflictRow['remote_envelope'] as String,
        label: 'リモートの封筒') as Map<String, Object?>;
    // `--take auto` は決定的 LWW で採る側を決める。
    final effective = take == 'auto' ? autoSide(db, conflictRow, remoteObj) : take;
    final payload =
        resolutionPayload(db, conflictRow, take: effective, remoteObj: remoteObj);
    final envelope = resolutionEnvelope(db, conflictRow,
        payload: payload,
        remoteObj: remoteObj,
        take: effective,
        deviceId: deviceId,
        eventId: eventId,
        now: now);
    transaction(db, () {
      store.write(db, planner.localResolve(envelope));
      closeResolvedConflicts(db, envelope, now);
    });
    return envelope;
  }

  /// 開いた競合を決定的 LWW で解く。`sync pull` の適用フェーズ末尾で呼ぶ。
  ///
  /// 解決イベントは outbox へ積むだけで、送信は続く push が行う（手動解決と同じ）。敗者の封筒は
  /// 転送先に不変で残り、`conflicts` の行は resolved として残る。**黙って上書きしない** —
  /// 解決イベントを残さない上書きだけを禁じているのであって、人手の介在は要らない。
  ///
  /// 同一集約の解決済み件数が窓の中で上限に達したら自動を止め、競合を開いたまま残す（要対応へ
  /// 落とす）。窓を切る理由は [autoResolveGuardWindowSeconds] にある。
  AutoResolveReport autoResolveOpenConflicts(
    Db db, {
    required String deviceId,
    required String now,
    required String Function() uuidFactory,
    int guardMax = autoResolveGuardMax,
    int guardWindowSeconds = autoResolveGuardWindowSeconds,
  }) {
    final report = AutoResolveReport();
    final since = shiftSeconds(now, -guardWindowSeconds);
    for (final row in listConflicts(db, state: conflictOpen)) {
      final conflictId = row['conflict_id'] as String;
      // 先の解決が同一集約の別の行を閉じていることがある。都度読み直す。
      final current = getConflict(db, conflictId);
      if (current == null || current['state'] != conflictOpen) continue;
      final entityType = current['entity_type'] as String;
      final entityId = current['entity_id'] as String;
      if (resolvedConflictCount(db, entityType, entityId, sinceUtc: since) >= guardMax) {
        report.guarded.add({
          'conflict_id': conflictId,
          'entity_type': entityType,
          'entity_id': entityId,
        });
        continue;
      }
      final remoteObj = loadsJson(current['remote_envelope'] as String,
          label: 'リモートの封筒') as Map<String, Object?>;
      final take = autoSide(db, current, remoteObj);
      final envelope = resolveOne(db, current,
          take: take, deviceId: deviceId, eventId: uuidFactory(), now: now);
      report.resolved.add({
        'conflict_id': conflictId,
        'entity_type': entityType,
        'entity_id': entityId,
        'take': take,
        'event_id': envelope.eventId,
        'result_version': envelope.resultVersion,
      });
    }
    return report;
  }
}
