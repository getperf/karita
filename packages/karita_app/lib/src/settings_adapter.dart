/// 型の写しと公開可能な診断情報。7状態の判定は SyncEngine に残す。
library;

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'settings.dart';

AppSyncStatus appSyncStatus(
  SyncStatus status, {
  AppIssue? generationChanged,
  AppIssue? accountMismatch,
}) {
  final facts = status.facts;
  final state = switch (status.state) {
    SyncState.appUpdateRequired => AppSyncState.appUpdateRequired,
    SyncState.signInRequired => AppSyncState.signInRequired,
    SyncState.needsAttention => AppSyncState.needsAttention,
    SyncState.syncing => AppSyncState.syncing,
    SyncState.offline => AppSyncState.offline,
    SyncState.unsent => AppSyncState.unsent,
    SyncState.synced => AppSyncState.synced,
  };
  // 生の例外、HTTP 応答、設定の所見は秘密を含み得るため渡さない。
  // コードと、型の決まった事実から作るメッセージだけを公開する。
  final issue = switch (state) {
    AppSyncState.appUpdateRequired => AppIssue(
      'sync-schema',
      'schemaPending=${facts.schemaPending}, dbSchemaAhead=${facts.dbSchemaAhead}',
    ),
    AppSyncState.signInRequired => AppIssue(
      'sync-auth',
      'blockedAuth=${facts.blockedAuth}',
    ),
    AppSyncState.needsAttention => AppIssue(
      'sync-attention',
      'openConflicts=${facts.openConflicts}, stalledGaps=${facts.stalledGaps}, '
          'dbSchemaBehind=${facts.dbSchemaBehind}, checksumMismatch=${facts.checksumMismatch}, '
          'doctorFailed=${facts.doctorFailed}',
    ),
    _ => null,
  };
  return AppSyncStatus(
    state: state,
    lastSuccessAt: status.lastSuccessAt,
    autoResolved: status.autoResolved,
    issue: issue,
    generationChanged: generationChanged,
    accountMismatch: accountMismatch,
  );
}

/// バックアップ1件を索引から写す。**件数と「読めるか」は索引の値で、正しさの根拠ではない**
/// （復元は取得後の manifest と内容 hash で判定する）。
AppBackup appBackup(BackupRef ref) {
  final counts = <String, int>{};
  for (final pair in (ref.summary['counts'] ?? '').split(' ')) {
    final at = pair.indexOf('=');
    if (at <= 0) continue;
    final value = int.tryParse(pair.substring(at + 1));
    if (value != null) counts[pair.substring(0, at)] = value;
  }
  // 版の判定はエンジンの `_checkVersion` と同じ2点である。**索引に版が無いものは弾かない**
  // — 読めるかどうかは取得後に決まり、ここで弾くと選ぶ手段が消える。
  final version = int.tryParse(ref.summary['backupVersion'] ?? '');
  final schema = int.tryParse(ref.summary['schemaVersion'] ?? '');
  final readable =
      (version == null || version == backupVersion) &&
      (schema == null || schema <= latestVersion());
  return AppBackup(
    backupId: ref.backupId,
    createdAtUtc: ref.createdAtUtc,
    createdOn: ref.summary['sourcePlatform'] ?? '',
    sizeBytes: ref.sizeBytes,
    books: counts['books'],
    loans: counts['loans'],
    readable: readable,
  );
}
