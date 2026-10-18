/// 棚卸完了（LibraryMembership）の記録。
///
/// **「その図書館システムを確認し終えた」という一つの事実であり、端末ごとの事実ではない。**
/// したがって集約IDを `uuid5(namespace, systemId)` で決定的に導く。二端末が別々に棚卸を完了
/// しても同じ id を指すため競合として立ち、LWW が解決する。決定キーは記録時刻であり、記録時刻は
/// 棚卸を完了した時刻そのものなので、結果は実質 `max()` と一致する — **後から棚卸した側が
/// 必ず勝つ。**
///
/// Loan の更新とは独立した事実なので、Loans から分けてある。巡回セッションはトランザクションを
/// 持たず、各更新が即時確定する。
///
/// 移送元: book-sync-model の `src/bops_application/memberships.py`。
library;

import 'package:karita_contract/karita_contract.dart';

import 'context.dart';

/// 巡回そのものは案内であり、記録される事実は**「一巡確認した」だけ**である。
const String patrolEventType = 'PatrolCompleted';

class Memberships {
  final DomainContext context;

  const Memberships(this.context);

  String entityIdFor(String systemId) =>
      deterministicId(entityLibraryMembership, systemId);

  /// **明示的な棚卸完了だけが巡回時刻を更新する。** 集約更新と発行の記録が同時に確定する。
  Envelope completePatrol({required String systemId, required String now}) {
    final entityId = entityIdFor(systemId);
    final payload = <String, Object?>{
      'system_id': systemId,
      'last_reconciled_at_utc': now,
    };
    return transaction(
      context.db,
      () => context.emit(
        entityType: entityLibraryMembership,
        entityId: entityId,
        payload: payload,
        domainEventType: patrolEventType,
        aggregateType: 'library_membership',
        now: now,
      ),
    );
  }

  /// 棚卸完了時刻。
  ///
  /// **id で引く。** id が正本であり、`systemId` で引くと、名前空間のずれた実装から別 id の行が
  /// 届いたときに結果が不定になる。
  String? lastReconciledAtUtc(String systemId) {
    final row = context.aggregates
        .read(context.db, entityLibraryMembership, entityIdFor(systemId));
    return row == null ? null : row['last_reconciled_at_utc'] as String?;
  }
}
