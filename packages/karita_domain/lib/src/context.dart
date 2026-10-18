/// 業務の書込みが共通で要るもの。
///
/// Python の bops は自由関数に `conn` と `now` と `device_id` と `uuid` を毎回渡していた。
/// Dart では ② の `SyncEngine` と同じく**組み立てを1箇所に寄せる**が、持つものは変えない —
/// ここにあるのは契約への口と素性だけで、**業務の規則は各サービスが持つ。**
///
/// **`karita_sync` に依存しない。** 業務更新と outbox 追記は同一 SQLite トランザクションで行い、
/// その入口は `karita_contract` の [appendLocalEmission] 一点である。同期エンジンを経由すると
/// 依存の向きが反転し、業務が同期の都合で動くようになる。
library;

import 'package:karita_contract/canonical.dart' as canonical;
import 'package:karita_contract/karita_contract.dart';

/// DomainEvent は監査用の業務記録で、**同期用の outbox とは別物である。**
///
/// 相手端末へ運ばれるのは封筒の `domainEventType` であって、この表の行ではない。行そのものは
/// 端末ごとに、その端末が実際に行った操作として残る。
const String domainEventsTable = 'domain_events';

class DomainContext {
  /// **接続を値で持たない。** 完全復元は DB ファイルを置換して接続を開き直す
  /// （`DbSession.reopen`）。業務が復元前の接続を握っていると、**復元の後で業務だけが死ぬ** —
  /// 同期は開き直した接続を使い続けるので、症状は「同期は動くのに本が登録できない」になる。
  /// 毎回引き直すことでその形を作らない。
  final Db Function() _dbOf;

  final Contracts contracts;
  final EnvelopeCodec codec;
  final Mapping mapping;
  final Aggregates aggregates;
  final String deviceId;
  final String Function() uuid;

  DomainContext({
    required Db Function() db,
    required this.contracts,
    required this.deviceId,
    required this.uuid,
  })  : _dbOf = db,
        codec = EnvelopeCodec(contracts),
        mapping = Mapping(contracts),
        aggregates = Aggregates(Mapping(contracts));

  /// 差し替わらない接続を渡す口。**復元を経ない場面だけで使う。**
  DomainContext.fixed({
    required Db db,
    required Contracts contracts,
    required String deviceId,
    required String Function() uuid,
  }) : this(
          db: (() => db),
          contracts: contracts,
          deviceId: deviceId,
          uuid: uuid,
        );

  Db get db => _dbOf();

  /// 業務記録を1行残す。**呼び出し側のトランザクションの中で使う。**
  ///
  /// `written_by_app` を持たない表なので所有検査には掛からない。監査の記録であって、同期の
  /// 経路が二本になる話ではないためである。
  void recordDomainEvent({
    required String eventType,
    required String aggregateType,
    required String aggregateId,
    required String occurredAtUtc,
    required Map<String, Object?> payload,
  }) {
    db.execute(
      'INSERT INTO $domainEventsTable ('
      '  event_id, event_type, aggregate_type, aggregate_id, occurred_at_utc,'
      '  device_id, payload_json'
      ') VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        uuid(),
        eventType,
        aggregateType,
        aggregateId,
        occurredAtUtc,
        deviceId,
        canonical.dumpsText(payload),
      ],
    );
  }

  /// 集約を1つ進め、封筒を発行し、業務記録を残す。**3つで一組である。**
  ///
  /// **トランザクションを開かない。** 採用と Loan の開始を一つのトランザクションで確定する
  /// 経路があるため、ここでは開けない。単独で使う入口が `transaction` で包む。
  ///
  /// `baseVersion` は現在版から採る。呼び出し側が渡せるようにはしない — 入口ごとに版の採り方が
  /// 分かれると、同じ更新が入口によって競合したりしなかったりする。
  Envelope emit({
    required String entityType,
    required String entityId,
    required Map<String, Object?> payload,
    required String domainEventType,
    required String aggregateType,
    required String now,
    String operation = operationUpsert,
    bool isDeleted = false,
  }) {
    final base = aggregates.currentVersion(db, entityType, entityId);
    final event = codec.build(
      eventId: uuid(),
      deviceId: deviceId,
      createdAtUtc: now,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      baseVersion: base,
      resultVersion: base + 1,
      payload: payload,
    );
    aggregates.upsert(
      db,
      entityType: entityType,
      entityId: entityId,
      version: event.resultVersion,
      updatedAtUtc: now,
      updatedByDeviceId: deviceId,
      columns: mapping.payloadToRow(entityType, payload,
          tombstone: operation == operationTombstone),
      isDeleted: isDeleted,
    );
    // **業務から同期への経路はこの一点だけである。** outbox と applied_events を二つで一組で
    // 書く。片方だけだと、上げた自分の封筒を次の pull で引き戻したときに自分の更新が自分との
    // 競合になる。
    appendLocalEmission(db, event, updatedAtUtc: now, app: appBops);
    recordDomainEvent(
      eventType: domainEventType,
      aggregateType: aggregateType,
      aggregateId: entityId,
      occurredAtUtc: now,
      payload: payload,
    );
    return event;
  }
}
