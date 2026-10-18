/// 書込み意図。**この層は SQLite も転送も知らない。**
///
/// **この層は SQLite も転送も知らない。** 封筒とローカルの現在版だけを受け取り、何を書くかを
/// データとして返す。実際に書くのは `store.dart` である。分けておくと、適用の規則を DB も
/// ファイルも用意せずに単体で検査できる。
///
/// 書込み意図を作る入口は3つある。どれを通ったかで版の検査が変わる。
///
/// | 入口 | 使う場面 | `baseVersion` の検査 | outbox |
/// |---|---|---|---|
/// | [localEmit] | ローカル発行（業務操作・fixture seed） | **現在版と一致すること** | 追記する |
/// | [remoteApply] | 受信イベントの適用 | しない（`decide` が済ませている） | 追記しない |
/// | [localResolve] | 競合の解決 | **しない** | 追記する |
///
/// [localResolve] が等値検査を持たないのは、解決イベントの `baseVersion` が
/// max(ローカル版, リモートの `resultVersion`) であり、**ローカル現在版と一致しないのが正常**
/// だからである。[localEmit] の検査を緩めて流用すると、ステップ取り違えの検出まで一緒に失われる。
///
/// 移送元: book-sync-model の `src/bsync_core/plan.py`。
library;

import 'package:karita_contract/karita_contract.dart';

class AggregateWrite {
  /// 集約行の置き換え。payload はスナップショットなので、行全体を置き換える。
  final String entityType;
  final String entityId;
  final int version;
  final String updatedAtUtc;
  final String updatedByDeviceId;
  final Map<String, Object?> columns;
  final bool isDeleted;

  const AggregateWrite({
    required this.entityType,
    required this.entityId,
    required this.version,
    required this.updatedAtUtc,
    required this.updatedByDeviceId,
    required this.columns,
    required this.isDeleted,
  });
}

class AppliedWrite {
  /// applied_events への追記。`event_id` の一意制約が冪等を担保する。
  final String eventId;
  final String entityType;
  final String entityId;
  final int resultVersion;
  final String payloadHash;
  final String origin;
  final String appliedAtUtc;

  const AppliedWrite({
    required this.eventId,
    required this.entityType,
    required this.entityId,
    required this.resultVersion,
    required this.payloadHash,
    required this.origin,
    required this.appliedAtUtc,
  });
}

class OutboxWrite {
  final Envelope envelope;
  final String state;

  const OutboxWrite(this.envelope, this.state);
}

/// 一トランザクションで確定させる書込みの一式。
class WritePlan {
  final AggregateWrite? aggregate;
  final AppliedWrite? applied;
  final OutboxWrite? outbox;

  const WritePlan({this.aggregate, this.applied, this.outbox});
}

class Planner {
  final Mapping mapping;

  const Planner(this.mapping);

  /// tombstone として扱ってよいかを検査する。3つの入口が共有する。
  bool _tombstoneOf(Envelope event) {
    if (event.operation != operationTombstone) return false;

    final spec = mapping.specFor(event.entityType);
    if (!tombstoneEntityTypes.contains(event.entityType)) {
      throw SyncDataError(
        '${event.entityType} は tombstone を許しません（許すのは '
        '${tombstoneEntityTypes.join('、')}）。'
        'Loan から参照される Book の tombstone は適用しますが、Loan は残します。',
        code: 'tombstone-not-allowed',
      );
    }
    if (!spec.hasIsDeleted) {
      throw SyncDataError('${spec.table} に削除列がありません。', code: 'tombstone-not-allowed');
    }
    return true;
  }

  AggregateWrite _aggregateWrite(Envelope event, {required bool tombstone}) =>
      AggregateWrite(
        entityType: event.entityType,
        entityId: event.entityId,
        version: event.resultVersion,
        updatedAtUtc: event.createdAtUtc,
        updatedByDeviceId: event.deviceId,
        columns: mapping.payloadToRow(event.entityType, event.payload,
            tombstone: tombstone),
        isDeleted: tombstone,
      );

  AppliedWrite _appliedWrite(Envelope event,
          {required String origin, required String appliedAtUtc}) =>
      AppliedWrite(
        eventId: event.eventId,
        entityType: event.entityType,
        entityId: event.entityId,
        resultVersion: event.resultVersion,
        payloadHash: event.payloadHash,
        origin: origin,
        appliedAtUtc: appliedAtUtc,
      );

  /// ローカルで確定した更新の書込み意図。集約更新・`applied_events`・`outbox_events` の3つを返す。
  ///
  /// 自端末が発行したイベントを `applied_events` にも記録するのは、転送先から自分のイベントを
  /// 引き戻したときに再適用しないためである。判定表2行目がこの記録に依存する。
  ///
  /// **等値検査をここから外さない。** 解決イベントは版が一致しないのが正常だが、それは
  /// [localResolve] の仕事である。ここを緩めるとステップ取り違えが通る。
  WritePlan localEmit(Envelope event, {required int currentVersion}) {
    if (event.baseVersion != currentVersion) {
      throw SyncDataError(
        '${event.entityType} ${event.entityId} の現在版は $currentVersion ですが、'
        'baseVersion は ${event.baseVersion} です。ローカル発行は現在版の上に積みます。',
        code: 'base-version-mismatch',
      );
    }
    final tombstone = _tombstoneOf(event);
    return WritePlan(
      aggregate: _aggregateWrite(event, tombstone: tombstone),
      applied: _appliedWrite(event,
          origin: originLocal, appliedAtUtc: event.createdAtUtc),
      outbox: OutboxWrite(event, outboxPending),
    );
  }

  /// 受信イベントを適用する書込み意図。
  ///
  /// **版の検査をここでしない。** 適用してよいかは `decide` が判定表に従って決めており、ここで
  /// 再度 `baseVersion` を見ると、判定表3行目（`resolvesEventIds` による迂回）で正しく通した
  /// イベントを弾いてしまう。判定の権限を二箇所に置かない。
  ///
  /// outbox には追記しない。受信したイベントを送り返すと、二端末の間でイベントが増え続ける。
  WritePlan remoteApply(Envelope event, {required String appliedAtUtc}) {
    final tombstone = _tombstoneOf(event);
    return WritePlan(
      aggregate: _aggregateWrite(event, tombstone: tombstone),
      applied:
          _appliedWrite(event, origin: originRemote, appliedAtUtc: appliedAtUtc),
    );
  }

  /// 競合の解決イベントの書込み意図。
  ///
  /// [localEmit] と違い**等値検査を持たない**。解決イベントの `baseVersion` は
  /// max(ローカル版, リモートの `resultVersion`) であり、ローカル現在版と一致しないのが正常で
  /// ある。版を決めるのは呼び出し側であり、ここは書込みの形だけを持つ。
  ///
  /// 「ローカルを採用」でもイベントを出す。出さなければ相手端末は自分の更新が退けられたことを
  /// 知れず、同じイベントを送り続ける。
  WritePlan localResolve(Envelope event) {
    final tombstone = _tombstoneOf(event);
    return WritePlan(
      aggregate: _aggregateWrite(event, tombstone: tombstone),
      applied: _appliedWrite(event,
          origin: originLocal, appliedAtUtc: event.createdAtUtc),
      outbox: OutboxWrite(event, outboxPending),
    );
  }
}
