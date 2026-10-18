/// イベント封筒。組み立てと、受信した封筒の固定順の検証。
///
/// 形の検査はスキーマ（`schema.dart`）が持つ。ここが持つのは、封筒検証の**固定順のパイプライン**と、
/// JSON Schema で表現できない不変条件（`resultVersion > baseVersion`、`payloadHash` と payload の
/// 一致）、そして正準化制約である。
///
/// **この層の本体はスキーマ検証ではなく順序である。**`loads → readSchemaVersion → validateEnvelope →
/// validatePayload → build` は順に走り、**どの層が最初に捕まえるかでエラーコードが決まる。**
/// この順序そのものが言語間契約であり、`fixtures/invalid/manifest.json` の19件はこれに依存する。
///
/// 移送元: book-sync-model の `src/contracts/envelope.py`（validate.py と合わせて）。
library;

import 'canonical.dart' as canonical;
import 'errors.dart';
import 'json_reader.dart';
import 'schema.dart';

final RegExp _uuidRe =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
final RegExp _utcRe = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$');

const int _deviceIdMax = 64;

class Envelope {
  final String eventId;
  final String deviceId;
  final String createdAtUtc;
  final String entityType;
  final String entityId;
  final String operation;
  final int baseVersion;
  final int resultVersion;
  final String payloadHash;
  final Map<String, Object?> payload;
  final List<String> resolvesEventIds;
  final int schemaVersion;

  /// 版2の任意項目。受信側でも同じ DomainEvent を書けるようにするための語彙で、**同期層は
  /// 解釈しない**。運ぶだけである。
  final String? domainEventType;

  Envelope({
    required this.eventId,
    required this.deviceId,
    required this.createdAtUtc,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.baseVersion,
    required this.resultVersion,
    required this.payloadHash,
    required this.payload,
    required this.resolvesEventIds,
    required this.schemaVersion,
    this.domainEventType,
  });

  /// 封筒スキーマの項目名（camelCase）で出す。`resolvesEventIds` は空でも省略せず [] を書く。
  /// `domainEventType` は逆で、**値が無いときはキーを出さない** — 空値に意味が無く、null を書くか
  /// 省くかで正準化のバイト列が変わるため、規則を「値があるときだけ」の一本にする。
  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'eventId': eventId,
        'deviceId': deviceId,
        'createdAtUtc': createdAtUtc,
        'entityType': entityType,
        'entityId': entityId,
        'operation': operation,
        'baseVersion': baseVersion,
        'resultVersion': resultVersion,
        'payloadHash': payloadHash,
        'resolvesEventIds': List<String>.from(resolvesEventIds),
        'payload': Map<String, Object?>.from(payload),
        if (domainEventType != null) 'domainEventType': domainEventType,
      };

  List<int> canonicalBytes() => canonical.dumps(toJson());

  String canonicalText() => canonical.dumpsText(toJson());
}

class EnvelopeCodec {
  final Contracts contracts;

  EnvelopeCodec(this.contracts);

  String _requireUuid(Object? value, String label) {
    if (value is! String || !_uuidRe.hasMatch(value)) {
      throw SyncDataError('$label は小文字hexのUUIDである必要があります: $value', code: 'uuid');
    }
    return value;
  }

  String _requireUtc(Object? value, String label) {
    if (value is! String || !_utcRe.hasMatch(value)) {
      throw SyncDataError('$label は RFC3339秒精度・Z終端である必要があります: $value', code: 'timestamp');
    }
    return value;
  }

  int _requireInt(Object? value, String label, {required int minimum}) {
    if (value is bool || value is! int) {
      throw SyncDataError('$label は整数である必要があります: $value', code: 'version');
    }
    if (value < minimum) {
      throw SyncDataError('$label は $minimum 以上である必要があります: $value', code: 'version');
    }
    return value;
  }

  /// 封筒を組み立てる。`payloadHash` は与えなければ正準化から計算する。
  /// `resultVersion > baseVersion` と payloadHash の一致は JSON Schema で表現できないため、ここで検査する。
  Envelope build({
    required Object? eventId,
    required Object? deviceId,
    required Object? createdAtUtc,
    required Object? entityType,
    required Object? entityId,
    required Object? operation,
    required Object? baseVersion,
    required Object? resultVersion,
    required Object? payload,
    Object? resolvesEventIds,
    Object? payloadHash,
    int? schemaVersion,
    Object? domainEventType,
  }) {
    // **enum の照合はその封筒の版で行う。** 発行版に固定すると、受理集合を広げただけの実装で
    // 版2の封筒が落ち、保持されるべきものが `invalid` として破棄の側へ回る。
    final version = schemaVersion ?? contracts.schemaVersion;
    if (!contracts.supportedSchemaVersions.contains(version)) {
      throw SyncDataError('未対応の schemaVersion です: $version',
          code: 'schema-version-unsupported');
    }

    final eid = _requireUuid(eventId, 'eventId');
    final entId = _requireUuid(entityId, 'entityId');
    final created = _requireUtc(createdAtUtc, 'createdAtUtc');

    if (deviceId is! String || deviceId.isEmpty || deviceId.length > _deviceIdMax) {
      throw SyncDataError('deviceId が不正です: $deviceId', code: 'device-id');
    }
    if (!contracts.operations(version: version).contains(operation)) {
      throw SyncDataError('operation が不正です: $operation', code: 'operation');
    }
    if (!contracts.entityTypes(version: version).contains(entityType)) {
      throw SyncDataError('未知の entityType です: $entityType', code: 'entity-type');
    }
    if (payload is! Map) {
      throw SyncDataError('payload はオブジェクトである必要があります。', code: 'payload');
    }
    if (domainEventType != null && domainEventType is! String) {
      throw SyncDataError('domainEventType は文字列である必要があります: $domainEventType',
          code: 'domain-event-type');
    }

    final base = _requireInt(baseVersion, 'baseVersion', minimum: 0);
    final result = _requireInt(resultVersion, 'resultVersion', minimum: 1);
    if (result <= base) {
      throw SyncDataError(
        'resultVersion ($result) は baseVersion ($base) より大きい必要があります。',
        code: 'version-order',
      );
    }

    final resolvesRaw = (resolvesEventIds as List?) ?? const [];
    final resolves = [for (final item in resolvesRaw) _requireUuid(item, 'resolvesEventIds')];
    if (resolves.toSet().length != resolves.length) {
      throw SyncDataError('resolvesEventIds に重複があります。', code: 'resolves-duplicate');
    }

    final payloadMap = Map<String, Object?>.from(payload);
    // payloadHash の計算がここで正準化制約（float・非ASCIIキー・整数上限）を発火させる。
    final computed = canonical.payloadHash(payloadMap);
    if (payloadHash != null && payloadHash != computed) {
      throw SyncDataError(
        'payloadHash が payload と一致しません（宣言 $payloadHash / 実際 $computed）。',
        code: 'payload-hash',
      );
    }

    return Envelope(
      eventId: eid,
      deviceId: deviceId,
      createdAtUtc: created,
      entityType: entityType as String,
      entityId: entId,
      operation: operation as String,
      baseVersion: base,
      resultVersion: result,
      payloadHash: computed,
      payload: payloadMap,
      resolvesEventIds: resolves,
      schemaVersion: version,
      domainEventType: domainEventType as String?,
    );
  }

  /// schemaVersion は封筒全体の検証より先に読む。未対応の版では封筒の形自体が変わりうる。
  int readSchemaVersion(Map<String, Object?> obj) {
    final value = obj['schemaVersion'];
    if (value is bool || value is! int) {
      throw SyncDataError('schemaVersion が整数ではありません: $value', code: 'schema-version');
    }
    return value;
  }

  /// 受信した封筒をスキーマで検証する。順序を守る。
  void validateJson(Map<String, Object?> obj) {
    final version = readSchemaVersion(obj);
    if (!contracts.supportedSchemaVersions.contains(version)) {
      final accepted = (contracts.supportedSchemaVersions.toList()..sort()).join('・');
      throw SyncDataError(
        '未対応の schemaVersion です: $version（この実装が受理するのは $accepted）。'
        'pending_events(reason=\'schema\') に保持してください。',
        code: 'schema-version-unsupported',
      );
    }
    // 受理する版が複数あるとき、形を検査するのは**その封筒の版**のスキーマである。
    contracts.validateEnvelope(obj, version: version);

    final entityType = obj['entityType'] as String;
    if (contracts.payloadEntityTypes.contains(entityType)) {
      contracts.validatePayload(
        entityType,
        obj['payload'],
        tombstone: obj['operation'] == 'tombstone',
      );
    }
  }

  Envelope fromJson(Map<String, Object?> obj) {
    validateJson(obj);
    return build(
      eventId: obj['eventId'],
      deviceId: obj['deviceId'],
      createdAtUtc: obj['createdAtUtc'],
      entityType: obj['entityType'],
      entityId: obj['entityId'],
      operation: obj['operation'],
      baseVersion: obj['baseVersion'],
      resultVersion: obj['resultVersion'],
      payload: obj['payload'] ?? <String, Object?>{},
      resolvesEventIds: obj['resolvesEventIds'] ?? const [],
      payloadHash: obj['payloadHash'],
      schemaVersion: readSchemaVersion(obj),
      domainEventType: obj['domainEventType'],
    );
  }

  /// 受信した封筒のバイト列を読む。重複キーを拒否する読み取りを通す。
  Envelope loads(String text, {String label = '封筒'}) {
    final obj = loadsJson(text, label: label);
    if (obj is! Map<String, Object?>) {
      throw SyncDataError('$label はオブジェクトである必要があります。', code: 'envelope-value');
    }
    return fromJson(obj);
  }
}
