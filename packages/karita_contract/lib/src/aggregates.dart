/// 業務集約行の読み書き。
///
/// 集約テーブルは業務（`karita_domain`）の所有だが、同期（`karita_sync`）も受信イベントの適用で
/// 書く。両方が書くため、SQL はここ（`karita_contract`）に置いて共有する。
///
/// payload はスナップショットなので、更新は行全体の置き換えである。payload に無い項目を
/// 「変更なし」として残すと、削除された項目が端末間で復活する。
///
/// 移送元: book-sync-model の `src/contracts/aggregates.py`。
library;

import 'db.dart';
import 'mapping.dart';

class Aggregates {
  final Mapping mapping;

  const Aggregates(this.mapping);

  /// 現在版。実体が無ければ 0（新規作成の baseVersion に対応する）。
  int currentVersion(Db db, String entityType, String entityId) {
    final spec = mapping.specFor(entityType);
    final rows =
        db.select('SELECT version FROM ${spec.table} WHERE id = ?', [entityId]);
    return rows.isEmpty ? 0 : rows.first['version'] as int;
  }

  Map<String, Object?>? read(Db db, String entityType, String entityId) {
    final spec = mapping.specFor(entityType);
    final rows =
        db.select('SELECT * FROM ${spec.table} WHERE id = ?', [entityId]);
    return rows.isEmpty ? null : rows.first;
  }

  int count(Db db, String entityType) {
    final spec = mapping.specFor(entityType);
    return db.select('SELECT COUNT(*) AS n FROM ${spec.table}').first['n'] as int;
  }

  /// 集約行を置き換える。呼び出し側のトランザクションの中で使う。
  void upsert(
    Db db, {
    required String entityType,
    required String entityId,
    required int version,
    required String updatedAtUtc,
    required String updatedByDeviceId,
    required Map<String, Object?> columns,
    bool isDeleted = false,
  }) {
    final spec = mapping.specFor(entityType);

    final names = <String>['id', ...spec.columns, ...versionColumns];
    final values = <Object?>[
      entityId,
      for (final name in spec.columns) columns[name],
      version,
      updatedAtUtc,
      updatedByDeviceId,
    ];
    if (spec.hasIsDeleted) {
      names.add('is_deleted');
      values.add(isDeleted ? 1 : 0);
    }

    final placeholders = List.filled(names.length, '?').join(', ');
    final assignments = [
      for (final name in names)
        if (name != 'id') '$name = excluded.$name',
    ].join(', ');
    db.execute(
      'INSERT INTO ${spec.table} (${names.join(', ')}) VALUES ($placeholders) '
      'ON CONFLICT(id) DO UPDATE SET $assignments',
      values,
    );
  }
}
