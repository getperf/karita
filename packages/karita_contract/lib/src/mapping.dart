/// payload と集約行の相互変換。
///
/// payload は部分更新ではなく**更新後の集約スナップショット**である。したがって payload に無い
/// 項目は「変更なし」ではなく「空」を意味する。行全体を置き換える形で書く。
///
/// **項目の定義はここに書かない。** `schema/payload/*.json` を正本とし、列・必須・JSON 列は
/// そこから導出する。列名を直書きすると、Dart が読む定義と Python が使う定義が二本になり、
/// ずれても両方のテストが自分の正本に対して緑になる。
///
/// ここに残るのは**格納の都合**だけである — テーブル名、tombstone 列の有無、JSON 列を正準化
/// 文字列にする変換、欠けた列の埋め方。
///
/// 列を持つのは ② が扱う集約だけである（`constants.syncedEntityTypes`）。
///
/// 移送元: book-sync-model の `src/contracts/mapping.py`。
library;

import 'canonical.dart' as canonical;
import 'constants.dart';
import 'errors.dart';
import 'json_reader.dart';
import 'schema.dart';

class AggregateSpec {
  final String entityType;
  final String table;
  final List<String> columns;
  final List<String> required;
  final List<String> jsonColumns;
  final bool hasIsDeleted;

  const AggregateSpec({
    required this.entityType,
    required this.table,
    required this.columns,
    required this.required,
    required this.jsonColumns,
    required this.hasIsDeleted,
  });
}

/// 版列。集約の同一性は version だけでは決まらない — (version, updated_by_device_id) である。
const List<String> versionColumns = [
  'version',
  'updated_at_utc',
  'updated_by_device_id',
];

class Mapping {
  final Contracts contracts;
  final Map<String, AggregateSpec> specs;

  Mapping(this.contracts)
    : specs = {
        for (final spec in [
          _spec(contracts, entityBook, table: 'books', hasIsDeleted: true),
          _spec(
            contracts,
            entityBookPreference,
            table: 'book_preferences',
            hasIsDeleted: true,
          ),
          _spec(
            contracts,
            entityBookReview,
            table: 'book_reviews',
            hasIsDeleted: false,
          ),
          _spec(contracts, entityLoan, table: 'loans', hasIsDeleted: false),
          _spec(
            contracts,
            entityLibraryMembership,
            table: 'library_memberships',
            hasIsDeleted: false,
          ),
          // 設定の解除は tombstone である。**行を消さない** — 消すと、相手端末から届いた
          // 解除と「まだ届いていない」を区別できなくなる。
          _spec(
            contracts,
            entityLibrarySetting,
            table: 'library_settings',
            hasIsDeleted: true,
          ),
          // 図書館システムの削除は利用者の業務操作であり、相手端末へ伝わるのが期待した
          // 動作である。分館は独立集約にせず payload の配列で持つ。
          _spec(
            contracts,
            entityLibrarySystem,
            table: 'library_systems',
            hasIsDeleted: true,
          ),
        ])
          spec.entityType: spec,
      };

  /// テーブル名と削除列の有無だけがここの持ち物である。列はスキーマから導出する。
  static AggregateSpec _spec(
    Contracts contracts,
    String entityType, {
    required String table,
    required bool hasIsDeleted,
  }) {
    final doc = contracts.payloadDoc(entityType);
    if (doc == null) {
      throw SyncDataError(
        'payload スキーマがありません: $entityType',
        code: 'payload-schema-missing',
      );
    }
    final properties = (doc['properties'] as Map<String, Object?>?) ?? const {};
    final columns = properties.keys.toList();
    final required = ((doc['required'] as List?) ?? const [])
        .cast<String>()
        .toList();
    final jsonColumns = [
      for (final entry in properties.entries)
        if ((entry.value as Map<String, Object?>)['type'] == 'array') entry.key,
    ];
    return AggregateSpec(
      entityType: entityType,
      table: table,
      columns: columns,
      required: required,
      jsonColumns: jsonColumns,
      hasIsDeleted: hasIsDeleted,
    );
  }

  bool handles(String entityType) => specs.containsKey(entityType);

  /// ② が扱う集約に絞る。
  AggregateSpec specFor(String entityType) {
    final spec = specs[entityType];
    if (spec == null) {
      throw SyncDataError(
        '同期が扱うのは ${specs.keys.join('、')} だけです: $entityType',
        code: 'entity-type-unsupported',
      );
    }
    return spec;
  }

  /// payload に無い項目の値。JSON 列は NOT NULL なので空配列にする。
  Object? _absent(AggregateSpec spec, String column) =>
      spec.jsonColumns.contains(column) ? '[]' : null;

  /// payload を集約行の列へ写す。返るのは版列と id を除いた全列である。
  ///
  /// 未知のキー・欠けた必須項目・型・enum・日付書式の検査はスキーマが行う。ここでは格納の形へ
  /// 直すだけである。
  Map<String, Object?> payloadToRow(
    String entityType,
    Map<String, Object?> payload, {
    bool tombstone = false,
  }) {
    final spec = specFor(entityType);
    contracts.validatePayload(entityType, payload, tombstone: tombstone);

    final row = <String, Object?>{};
    for (final column in spec.columns) {
      if (!payload.containsKey(column)) {
        row[column] = _absent(spec, column);
        continue;
      }
      final value = payload[column];
      if (spec.jsonColumns.contains(column)) {
        row[column] = canonical.dumpsText(value);
      } else if (value == null) {
        row[column] = _absent(spec, column);
      } else if (value is bool) {
        row[column] = value ? 1 : 0;
      } else {
        row[column] = value;
      }
    }
    return row;
  }

  /// 集約行を payload へ戻す。空の項目は落とす。
  Map<String, Object?> rowToPayload(
    String entityType,
    Map<String, Object?> row,
  ) {
    final spec = specFor(entityType);
    final payload = <String, Object?>{};
    for (final column in spec.columns) {
      final value = row.containsKey(column) ? row[column] : null;
      if (value == null) continue;
      if (spec.jsonColumns.contains(column)) {
        final decoded = loadsJson(value as String, label: '$column 列');
        if (decoded is List && decoded.isEmpty) continue;
        if (decoded is Map && decoded.isEmpty) continue;
        payload[column] = decoded;
        continue;
      }
      payload[column] =
          entityType == entityBookPreference && column == 'want_to_read'
          ? value == 1
          : value;
    }
    return payload;
  }
}
