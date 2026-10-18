/// 集約の同一性の種。**業務キーから entityId を決定的に導く。**
///
/// `entityId` は uuid でなければならない（`sync-event.schema.json` の `$defs/uuid`）ので、
/// ISBN や `system_id` をそのまま id にはできない。uuid5 で決定的に写す。
///
/// **二端末が同じ実体を独立に登録したとき、同じ id になって初めて競合として立ち、LWW が一件へ
/// 収束させる。** namespace が実装ごとにずれると id が食い違い、重複が競合にすらならず両方が
/// 正常に適用される — **静かに壊れる。** だから Python と Dart と Flutter が同じ宣言
/// （`schema/identity.json`）を読む。ここが読むのはその生成物である。
///
/// 移送元: book-sync-model の `src/contracts/ids.py`（`deterministic_id` と `_identity`）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'generated/schema.g.dart';

/// 同一性の宣言。**スキーマではない**ため `.schema.json` で終わらない。
const String identityDeclarationName = 'identity.json';

/// 宣言の中身。`namespace` と、名前空間を分ける `kinds` である。
class Identity {
  final String namespace;
  final Set<String> kinds;

  const Identity(this.namespace, this.kinds);

  static Identity? _cached;

  /// 生成された宣言を読む。**ファイルシステムを見ない** — `karita_contract` は `dart:io` を
  /// 持たない。
  factory Identity.load() {
    final cached = _cached;
    if (cached != null) return cached;

    final text = schemaSources[identityDeclarationName];
    if (text == null) {
      throw SyncDataError('同一性の宣言がありません: $identityDeclarationName',
          code: 'identity');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw SyncDataError('$identityDeclarationName の形が不正です。', code: 'identity');
    }
    if (decoded is! Map<String, Object?>) {
      throw SyncDataError('$identityDeclarationName の形が不正です。', code: 'identity');
    }
    final namespace = decoded['namespace'];
    final kinds = decoded['kinds'];
    if (namespace is! String ||
        !_uuidRe.hasMatch(namespace) ||
        kinds is! List) {
      throw SyncDataError('$identityDeclarationName の形が不正です。', code: 'identity');
    }
    final names = {for (final value in kinds) '$value'};
    if (names.isEmpty) {
      throw SyncDataError('$identityDeclarationName に kinds がありません。',
          code: 'identity');
    }
    return _cached = Identity(namespace, names);
  }
}

final RegExp _uuidRe = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// 業務キーから entityId を決定的に導く。
///
/// **種別ごとに名前空間を分ける。** `book` の ISBN と `library_system` の `system_id` が同じ
/// 文字列になったときに同じ id を作らせないためである。宣言に無い `kind` は綴り間違いとして
/// 落とす — 黙って別の名前空間を作ると、その種別の同一性だけが端末間で成立しなくなる。
String deterministicId(String kind, String name) {
  final identity = Identity.load();
  if (!identity.kinds.contains(kind)) {
    throw SyncDataError(
        '同一性の宣言にない種別です: $kind（$identityDeclarationName）',
        code: 'identity');
  }
  if (name.isEmpty) {
    throw SyncDataError('$kind の同一性の種が空です。', code: 'identity');
  }
  return _uuid5(_uuid5(identity.namespace, kind), name);
}

/// RFC 4122 の uuid5。**Python の `uuid.uuid5` と同じ値を出す。**
///
/// 名前空間の16バイトに名前の UTF-8 バイト列を継いで SHA-1 を取り、上位16バイトの版とバリアント
/// のビットを立て直す。ここがずれると id が実装ごとに食い違い、重複が競合として立たなくなる。
String _uuid5(String namespace, String name) {
  final bytes = Uint8List(16 + utf8.encode(name).length)
    ..setRange(0, 16, _uuidBytes(namespace))
    ..setRange(16, 16 + utf8.encode(name).length, utf8.encode(name));
  final digest = Uint8List.fromList(sha1.convert(bytes).bytes.sublist(0, 16));
  // 版5。上位ニブルを 5 にする。
  digest[6] = (digest[6] & 0x0f) | 0x50;
  // RFC 4122 のバリアント。上位2ビットを 10 にする。
  digest[8] = (digest[8] & 0x3f) | 0x80;
  return _uuidText(digest);
}

Uint8List _uuidBytes(String value) {
  final hex = value.replaceAll('-', '');
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String _uuidText(Uint8List bytes) {
  final hex = [
    for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
