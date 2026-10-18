/// 共有スキーマを読み、keyword 単位で検査して code を返す薄い検査器。
///
/// スキーマファイルは共有で読むが、**keyword→code の分類はこの検査器が持つ。** 汎用の Dart スキーマ実装は「どの keyword で落ちたか」を
/// 同じ粒度で出すとは限らないため、これらのスキーマが使う keyword だけを検査する薄い実装にする。
///
/// `anyOf`（`nullableLocalDate`）は、失敗の中から1件を選ぶ規則を正本に合わせ、子の失敗のうち `type` 以外
/// （`pattern`）を優先して `payload-format` を返す。全体の失敗が複数あるときも、より深いパスの
/// 失敗を優先する。単一の欠陥しか持たない `contracts/fixtures/invalid/` の各件では、これで
/// Python と同じ1件が選ばれる。
library;

import 'dart:convert';

import 'errors.dart';
import 'generated/schema.g.dart';

/// 正本（book-sync-model）での位置。`schemaSources` のキーはここからの相対である。
const String schemaDir = 'src/contracts/schema';
const String payloadSchemaPrefix = 'payload/';

/// 封筒の版の宣言。**スキーマではない**ため `.schema.json` で終わらない。
const String envelopeVersionsName = 'envelope-versions.json';

/// 生成された schema を引く。**ファイルシステムを見ない** — `karita_contract` は
/// `dart:io` を持たない。AOT では `package:` URI をパスへ解決できないため、実行時 schema は
/// Dart ソースとして持つしかない（凍結までは tools/contract_sync が生成していた）。
String _source(String name) {
  final text = schemaSources[name];
  if (text == null) {
    throw SyncDataError('スキーマがありません: $name', code: 'schema-file');
  }
  return text;
}

/// jsonschema の keyword を、既存のエラーコードの接尾辞へ写す。
String _suffixForKeyword(String keyword) {
  switch (keyword) {
    case 'additionalProperties':
    case 'unevaluatedProperties':
      return 'unknown-key';
    case 'required':
      return 'missing-key';
    case 'enum':
    case 'const':
      return 'enum';
    case 'pattern':
    case 'format':
      return 'format';
    default:
      return 'value';
  }
}

class _Err {
  final String path;
  final String keyword;
  _Err(this.path, this.keyword);
  int get depth => '/'.allMatches(path).length;
}

class Contracts {
  /// 封筒スキーマをファイル名で引く。版ごとに1ファイルである。
  final Map<String, Map<String, Object?>> _envelopeDocs;
  final Map<int, String> _envelopeFileByVersion;
  final Set<int> _supportedSchemaVersions;
  final int _emitSchemaVersion;
  final Map<String, Map<String, Object?>> _payloadDocs;
  final List<String> _payloadEntityTypes;

  Contracts._(
    this._envelopeDocs,
    this._envelopeFileByVersion,
    this._supportedSchemaVersions,
    this._emitSchemaVersion,
    this._payloadDocs,
    this._payloadEntityTypes,
  );

  factory Contracts.load() {
    // 受理する版と発行する版は宣言が持つ。**Python と同じ内容を読む。**
    final versions =
        jsonDecode(_source(envelopeVersionsName)) as Map<String, Object?>;
    final supported = (versions['supported'] as List).cast<int>().toSet();
    final emit = versions['emit'] as int;
    final fileByVersion = <int, String>{};
    (versions['schemaByVersion'] as Map<String, Object?>).forEach((key, value) {
      fileByVersion[int.parse(key)] = value as String;
    });

    final envelopeDocs = <String, Map<String, Object?>>{};
    for (final version in supported) {
      final name = fileByVersion[version];
      if (name == null) {
        throw SyncDataError('受理する版 $version に封筒スキーマの割り当てがありません。',
            code: 'schema-file');
      }
      envelopeDocs[name] = jsonDecode(_source(name)) as Map<String, Object?>;
    }

    final payloadDocs = <String, Map<String, Object?>>{};
    final types = <String>[];
    for (final key in schemaSources.keys) {
      if (!key.startsWith(payloadSchemaPrefix)) continue;
      if (!key.endsWith('.schema.json')) continue;
      final name = key.substring(payloadSchemaPrefix.length);
      final entityType = name.substring(0, name.length - '.schema.json'.length);
      payloadDocs[entityType] = jsonDecode(_source(key)) as Map<String, Object?>;
      types.add(entityType);
    }
    types.sort();
    return Contracts._(
        envelopeDocs, fileByVersion, supported, emit, payloadDocs, types);
  }

  List<String> get payloadEntityTypes => _payloadEntityTypes;

  /// 集約の payload スキーマ。**列の導出元である**（`mapping.dart`）。
  ///
  /// 列名を Dart 側に直書きしないための口である。直書きすると、Dart が読める定義と実際に
  /// 使う定義が二本になり、ずれても両方のテストが自分の正本に対して緑になる。
  Map<String, Object?>? payloadDoc(String entityType) => _payloadDocs[entityType];

  /// 受理する版の集合。単一値との比較にしない — 版を上げた瞬間に転送先へ残る旧版の封筒が
  /// すべて `pending(schema)` へ落ちて恒久滞留する。
  Set<int> get supportedSchemaVersions => _supportedSchemaVersions;

  /// 発行する版。**常に一つ**であり、受理集合の max とは限らない。
  int get schemaVersion => _emitSchemaVersion;

  /// この端末が組み立てる封筒の形。定数はスキーマから読み、runner に写さない。
  Map<String, Object?> get _emitDoc => _docFor(_emitSchemaVersion);

  Map<String, Object?> _docFor(int version) {
    final name = _envelopeFileByVersion[version];
    final doc = name == null ? null : _envelopeDocs[name];
    if (doc == null) {
      throw SyncDataError('schemaVersion $version の封筒スキーマがありません。',
          code: 'schema-file');
    }
    return doc;
  }

  /// **版を省略したときに読むのは発行版である。** 組み立てる封筒の形はそれ一つだからである。
  /// 受信した封筒を読み直すときは、その封筒自身の版を渡さなければならない。渡さないと、受理集合を
  /// 広げただけの実装（`supported={1,2}` / `emit=1`）に版2でしか宣言されていない `entityType` が
  /// 届いたとき、スキーマ検証を通った封筒がここで落ちて `invalid` になる。
  List<String> entityTypes({int? version}) =>
      _enumAt(version == null ? _emitDoc : _docFor(version), 'entityType');

  List<String> operations({int? version}) =>
      _enumAt(version == null ? _emitDoc : _docFor(version), 'operation');

  List<String> _enumAt(Map<String, Object?> doc, String property) {
    final props = doc['properties'] as Map<String, Object?>;
    final prop = props[property] as Map<String, Object?>;
    return (prop['enum'] as List).cast<String>();
  }

  /// 封筒の形を、**その封筒の版**のスキーマで検証する。payload の中身は見ない。
  ///
  /// 版を引数で受けるのは、受理集合が複数版を含むとき、どのスキーマで検査するかが封筒ごとに
  /// 変わるためである。呼び出し側は先に版を読み、受理集合に入っていることを確かめておく。
  void validateEnvelope(Object? instance, {required int version}) {
    final doc = _docFor(version);
    final errors = <_Err>[];
    _evaluate(doc, instance, r'$', doc, errors);
    _raiseBest(errors, 'envelope', '封筒');
  }

  /// 集約の payload を検証する。tombstone は必須項目だけを外し、書いてある項目の形は保つ。
  void validatePayload(String entityType, Object? instance, {bool tombstone = false}) {
    final doc = _payloadDocs[entityType];
    if (doc == null) {
      throw SyncDataError('payload スキーマがありません: $entityType', code: 'payload-schema-missing');
    }
    var schema = doc;
    if (tombstone) {
      schema = Map<String, Object?>.from(doc)..remove('required');
    }
    final errors = <_Err>[];
    _evaluate(schema, instance, r'$', _emitDoc, errors);
    _raiseBest(errors, 'payload', '$entityType payload');
  }

  void _raiseBest(List<_Err> errors, String prefix, String label) {
    final best = _bestMatch(errors);
    if (best == null) return;
    final code = '$prefix-${_suffixForKeyword(best.keyword)}';
    throw SyncDataError('$label がスキーマに合いません（${best.keyword} @ ${best.path}）', code: code);
  }

  _Err? _bestMatch(List<_Err> errors) {
    if (errors.isEmpty) return null;
    _Err best = errors.first;
    for (final e in errors.skip(1)) {
      if (e.depth > best.depth) {
        best = e;
      } else if (e.depth == best.depth &&
          best.keyword == 'type' &&
          e.keyword != 'type') {
        // 同じ深さなら type 以外（pattern など）を優先する。nullableLocalDate が
        // payload-format を返す挙動に合わせる。
        best = e;
      }
    }
    return best;
  }

  // --- 評価 -----------------------------------------------------------------

  void _evaluate(
    Object? node,
    Object? instance,
    String path,
    Map<String, Object?> root,
    List<_Err> errors,
  ) {
    if (node is! Map) return;

    final ref = node[r'$ref'];
    if (ref is String) {
      final resolved = _resolveRef(ref, root);
      _evaluate(resolved.node, instance, path, resolved.root, errors);
    }

    if (node.containsKey('type')) {
      if (!_typeMatches(instance, node['type'])) {
        errors.add(_Err(path, 'type'));
      }
    }

    if (node.containsKey('enum')) {
      final options = node['enum'] as List;
      if (!options.any((o) => _jsonEquals(o, instance))) {
        errors.add(_Err(path, 'enum'));
      }
    }

    if (node.containsKey('const')) {
      if (!_jsonEquals(node['const'], instance)) {
        errors.add(_Err(path, 'const'));
      }
    }

    if (node.containsKey('pattern') && instance is String) {
      final re = RegExp(node['pattern'] as String);
      if (!re.hasMatch(instance)) {
        errors.add(_Err(path, 'pattern'));
      }
    }

    if (node.containsKey('minLength') && instance is String) {
      if (instance.length < (node['minLength'] as int)) {
        errors.add(_Err(path, 'minLength'));
      }
    }
    if (node.containsKey('maxLength') && instance is String) {
      if (instance.length > (node['maxLength'] as int)) {
        errors.add(_Err(path, 'maxLength'));
      }
    }

    if (node.containsKey('minimum') && _isNumber(instance)) {
      if (_compareNum(instance, node['minimum']) < 0) {
        errors.add(_Err(path, 'minimum'));
      }
    }
    if (node.containsKey('maximum') && _isNumber(instance)) {
      if (_compareNum(instance, node['maximum']) > 0) {
        errors.add(_Err(path, 'maximum'));
      }
    }

    if (node.containsKey('required') && instance is Map) {
      for (final key in (node['required'] as List).cast<String>()) {
        if (!instance.containsKey(key)) {
          errors.add(_Err(path, 'required'));
        }
      }
    }

    if (instance is Map) {
      final props = node['properties'] as Map<String, Object?>?;
      final additional = node['additionalProperties'];
      instance.forEach((key, value) {
        if (props != null && props.containsKey(key)) {
          _evaluate(props[key], value, '$path/$key', root, errors);
        } else if (additional == false) {
          errors.add(_Err('$path/$key', 'additionalProperties'));
        }
      });
    }

    if (node.containsKey('items') && instance is List) {
      final items = node['items'];
      for (var i = 0; i < instance.length; i++) {
        _evaluate(items, instance[i], '$path/$i', root, errors);
      }
    }

    if (node.containsKey('anyOf')) {
      final branches = node['anyOf'] as List;
      final branchErrors = <_Err>[];
      var matched = false;
      for (final branch in branches) {
        final local = <_Err>[];
        _evaluate(branch, instance, path, root, local);
        if (local.isEmpty) {
          matched = true;
          break;
        }
        branchErrors.addAll(local);
      }
      if (!matched) {
        errors.addAll(branchErrors);
      }
    }
  }

  ({Object? node, Map<String, Object?> root}) _resolveRef(
      String ref, Map<String, Object?> root) {
    var targetRoot = root;
    var pointer = ref;
    if (ref.startsWith('#')) {
      pointer = ref.substring(1);
    } else if (ref.contains('#')) {
      // "../sync-event.schema.json#/$defs/..." のような外部参照。**版ごとに1ファイルなので、
      // 参照先はファイル名で引く。** 発行版の doc へ固定すると、旧版の $defs を参照した
      // ときに黙って新版の定義で検査することになる。
      final parts = ref.split('#');
      final filename = parts[0].split('/').last;
      targetRoot = _envelopeDocs[filename] ?? _emitDoc;
      pointer = parts[1];
    }
    Object? node = targetRoot;
    for (final segment in pointer.split('/')) {
      if (segment.isEmpty) continue;
      final key = segment.replaceAll('~1', '/').replaceAll('~0', '~');
      node = (node as Map<String, Object?>)[key];
    }
    return (node: node, root: targetRoot);
  }
}

bool _isNumber(Object? v) => v is int || v is BigInt || (v is double);

int _compareNum(Object? a, Object? b) {
  final da = a is BigInt ? a.toDouble() : (a as num).toDouble();
  final db = b is BigInt ? b.toDouble() : (b as num).toDouble();
  return da.compareTo(db);
}

bool _typeMatches(Object? instance, Object? typeSpec) {
  final types = typeSpec is List ? typeSpec.cast<String>() : [typeSpec as String];
  for (final t in types) {
    switch (t) {
      case 'string':
        if (instance is String) return true;
        break;
      case 'integer':
        if (instance is int || instance is BigInt) return true;
        break;
      case 'number':
        if (instance is int || instance is BigInt || instance is double) return true;
        break;
      case 'object':
        if (instance is Map) return true;
        break;
      case 'array':
        if (instance is List) return true;
        break;
      case 'boolean':
        if (instance is bool) return true;
        break;
      case 'null':
        if (instance == null) return true;
        break;
    }
  }
  return false;
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  return a == b;
}
