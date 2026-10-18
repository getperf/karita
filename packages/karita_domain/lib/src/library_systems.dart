/// 図書館システム（[LibrarySystem]）の登録・更新・削除と読み出し。
///
/// [Memberships] と同じ形をしている — 集約行の更新と outbox への発行が同一トランザクションで
/// 確定し、`entityId` は `uuid5(namespace, systemId)` で決定的に導く。二端末が同じ図書館
/// システムを独立に登録しても同じ id を指すため競合として立ち、LWW が一件へ収束させる。
///
/// **分館は集約を分けない。** payload の `branches` 配列として1集約に入る。別集約にすると、
/// システムと分館が別々に競合して別々に LWW され、設定全体の洗い替えという粒度が変わる。
///
/// 移送元: book-sync-model の `src/bops_application/library_systems.py`。
library;

import 'package:karita_contract/karita_contract.dart';

import 'context.dart';
import 'errors.dart';
import 'library_areas.dart';

const String librarySystemRegisteredEventType = 'LibrarySystemRegistered';
const String librarySystemRemovedEventType = 'LibrarySystemRemoved';

/// payload の必須4項目。**スキーマは `required` を持てない**（tombstone の payload は最小限で
/// よい）ため、「読める行かどうか」の判定はここが持つ。
const List<String> librarySystemRequiredKeys = [
  'system_id',
  'pref',
  'city',
  'name',
];

class LibrarySystems {
  final DomainContext context;

  const LibrarySystems(this.context);

  String entityIdFor(String systemId) =>
      deterministicId(entityLibrarySystem, systemId);

  /// [LibrarySystem] を payload へ写す。
  ///
  /// **空の項目は落とす。** `rowToPayload` が NULL 列と空の配列を落とすため、ここで落として
  /// おかないと、発行した payload と集約行から読み直した payload が食い違う。LWW の第3キーは
  /// `payloadHash` であり、食い違えば同じ内容が別物として競合する。
  Map<String, Object?> toPayload(LibrarySystem system) {
    final payload = <String, Object?>{
      'system_id': system.id,
      'pref': system.pref,
      'city': system.city,
      'name': system.name,
    };
    final template = system.opacSearchUrlTemplate;
    if (template != null && template.isNotEmpty) {
      payload['opac_search_url_template'] = template;
    }
    final homepage = system.homepageUrl;
    if (homepage != null && homepage.isNotEmpty) {
      payload['homepage_url'] = homepage;
    }
    if (system.branches.isNotEmpty) {
      payload['branches'] = [
        for (final branch in system.branches)
          {
            'id': branch.id,
            'calil_libkey': branch.calilLibkey,
            'name': branch.name,
          },
      ];
    }
    return payload;
  }

  LibrarySystem fromPayload(Map<String, Object?> payload) => LibrarySystem(
        id: '${payload['system_id']}',
        pref: '${payload['pref']}',
        city: '${payload['city']}',
        name: '${payload['name']}',
        branches: [
          for (final item
              in (payload['branches'] as List<Object?>? ?? const []))
            if (item is Map)
              Branch(
                id: '${item['id']}',
                calilLibkey: '${item['calil_libkey']}',
                name: '${item['name']}',
              ),
        ],
        opacSearchUrlTemplate: payload['opac_search_url_template'] as String?,
        homepageUrl: payload['homepage_url'] as String?,
      );

  /// 集約行を [LibrarySystem] へ戻す。**読めない行は null を返す。**
  ///
  /// payload 由来の列に NOT NULL を置けないため（tombstone の payload は最小限でよい）、必須
  /// 項目を欠いた行が理屈の上では存在しうる。**その1行で業務のコマンド全体を止めない。**
  /// 落ちたことを報告するのは所有・整合の検査（`doctor`）の側の仕事である。
  LibrarySystem? _rowToSystem(Map<String, Object?> row) {
    final payload = context.mapping.rowToPayload(entityLibrarySystem, row);
    for (final key in librarySystemRequiredKeys) {
      if (!payload.containsKey(key)) return null;
    }
    return fromPayload(payload);
  }

  /// 登録済みの図書館システムを読む。tombstone は含めない。
  ///
  /// **`validate()` を呼ばない。** 名前空間のずれた実装から同じ `systemId` の別 id が届くと
  /// 重複が立ちうるが、そこで例外にすると業務のコマンドが全部止まる。報告するのは `doctor`
  /// である。
  LibrariesConfig load() {
    final systems = <LibrarySystem>[];
    for (final row in context.db.select(
        'SELECT * FROM library_systems WHERE is_deleted = 0 '
        'ORDER BY system_id, id')) {
      final system = _rowToSystem(row);
      if (system != null) systems.add(system);
    }
    return LibrariesConfig(systems);
  }

  /// 一件を引く。**id で引く。**
  LibrarySystem? read(String systemId) {
    final row = context.aggregates
        .read(context.db, entityLibrarySystem, entityIdFor(systemId));
    if (row == null || (row['is_deleted'] as int? ?? 0) != 0) return null;
    return _rowToSystem(row);
  }

  /// 集約の現在版。まだ無ければ 0。
  ///
  /// **tombstone された集約も 0 を返さない。** 「この集約に触れたことがあるか」を問う入口で
  /// あり、[read] の「今どうなっているか」とは別である。削除済みの図書館システムを黙って
  /// 復活させないために要る。
  int aggregateVersion(String systemId) => context.aggregates
      .currentVersion(context.db, entityLibrarySystem, entityIdFor(systemId));

  /// 図書館システムを1件登録・更新する。集約更新と発行の記録が同時に確定する。
  ///
  /// payload は**スナップショット**である。分館を1件消した登録は「分館の削除イベント」では
  /// なく、残った分館だけを持つ新しいスナップショットとして伝わる。
  Envelope register({required LibrarySystem system, required String now}) {
    system.validate();
    final entityId = entityIdFor(system.id);
    final payload = toPayload(system);
    return transaction(
      context.db,
      () => context.emit(
        entityType: entityLibrarySystem,
        entityId: entityId,
        payload: payload,
        domainEventType: librarySystemRegisteredEventType,
        aggregateType: 'library_system',
        now: now,
      ),
    );
  }

  /// 図書館システムを削除する。**tombstone の発行元はここだけである。**
  ///
  /// 図書館システムの削除は利用者の業務操作であり、相手端末へ伝わるのは事故ではなく期待した
  /// 動作である。
  ///
  /// **参照する `library_memberships` の行は消さない。** 参照整合性を同期層で強制しない —
  /// 片方の端末で削除、もう片方で棚卸完了、という並行更新は正常に起こりうる。参照先が消えた
  /// ことは `doctor` が報告する。
  ///
  /// payload はスナップショットではなく `system_id` だけにする。tombstone は「この実体は
  /// 消えた」という表明であり、**消えたものの中身を運ぶ意味がない。** 受信側が「どのシステムが
  /// 消えたか」を知るのに要るのは `system_id` だけである（`entityId` は uuid であり逆算
  /// できない）。
  Envelope remove({required String systemId, required String now}) {
    final entityId = entityIdFor(systemId);
    return transaction(context.db, () {
      final base = context.aggregates
          .currentVersion(context.db, entityLibrarySystem, entityId);
      if (base == 0) {
        throw LibrarySystemError('図書館システムが見つかりません: $systemId',
            code: 'library-system-missing');
      }
      return context.emit(
        entityType: entityLibrarySystem,
        entityId: entityId,
        payload: <String, Object?>{'system_id': systemId},
        domainEventType: librarySystemRemovedEventType,
        aggregateType: 'library_system',
        operation: operationTombstone,
        isDeleted: true,
        now: now,
      );
    });
  }

  /// 削除しようとしている図書館システムを参照する棚卸記録の件数。**消さずに数えるだけ**である。
  int referencingMemberships(String systemId) => context.db.select(
        'SELECT COUNT(*) AS n FROM library_memberships WHERE system_id = ?',
        [systemId],
      ).first['n'] as int;

  /// 同じく、その図書館システムで始めた Loan の件数。**履歴も数える。**
  ///
  /// 削除の確認に出す2つ目の数字である（`非公開資料:ui-state-model.md` §4
  /// 「削除で残るもの」）。**残るものを数えているので、終了した Loan も対象である** —
  /// 返却済みの記録から館名が引けなくなることも、利用者に告げる内容に含まれる。
  ///
  /// `loan_reporting.dart` が `configured: system != null` で館の不在に耐えているとおり、
  /// **消えても一覧は落ちない。** ここが数えるのは「落ちないが館名が出なくなる件数」である。
  int referencingLoans(String systemId) => context.db.select(
        'SELECT COUNT(*) AS n FROM loans WHERE system_id = ?',
        [systemId],
      ).first['n'] as int;
}
