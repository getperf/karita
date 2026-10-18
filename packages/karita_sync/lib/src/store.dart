/// SQLite アダプタ。書込み意図を単一トランザクションで確定する。
///
/// 純粋な適用層（`plan.dart`）が作った書込み意図を、**単一トランザクション**で確定する。
/// **この層の完了条件はここにある** — 集約更新、`applied_events` 追記、解決イベントの outbox
/// 追記が同時に確定し、途中で例外が起きれば全てロールバックされること。
///
/// 同期テーブルへ直接 SQL を書かず `karita_contract` の `sync_tables` を通すのは、
/// `written_by_app` の押印を一箇所に閉じるためである。
///
/// 移送元: book-sync-model の `src/bsync_core/store.py`。
library;

import 'package:karita_contract/karita_contract.dart';

import 'plan.dart';

class Store {
  final Aggregates aggregates;

  const Store(this.aggregates);

  /// 一つの書込み意図を確定する。**既に開いているトランザクションの中で使う。**
  void write(Db db, WritePlan plan, {String app = appBsync}) {
    final aggregate = plan.aggregate;
    if (aggregate != null) {
      aggregates.upsert(
        db,
        entityType: aggregate.entityType,
        entityId: aggregate.entityId,
        version: aggregate.version,
        updatedAtUtc: aggregate.updatedAtUtc,
        updatedByDeviceId: aggregate.updatedByDeviceId,
        columns: aggregate.columns,
        isDeleted: aggregate.isDeleted,
      );
    }
    final applied = plan.applied;
    if (applied != null) {
      recordApplied(
        db,
        eventId: applied.eventId,
        entityType: applied.entityType,
        entityId: applied.entityId,
        resultVersion: applied.resultVersion,
        payloadHash: applied.payloadHash,
        origin: applied.origin,
        appliedAtUtc: applied.appliedAtUtc,
        app: app,
      );
    }
    final outbox = plan.outbox;
    if (outbox != null) {
      appendOutbox(
        db,
        outbox.envelope,
        state: outbox.state,
        updatedAtUtc: outbox.envelope.createdAtUtc,
        app: app,
      );
    }
  }

  /// 複数の書込み意図を**一トランザクション**で確定する。
  ///
  /// 1入力イベント = 1トランザクション = 1 SyncEvent が原則だが、fixture の1ステップが複数の
  /// イベントを持つ場合、そのステップ全体を一つの原子単位として確定する。途中の例外で
  /// ステップ全体がロールバックされる。
  void commit(Db db, List<WritePlan> plans, {String app = appBsync}) {
    transaction(db, () {
      for (final plan in plans) {
        write(db, plan, app: app);
      }
    });
  }
}
