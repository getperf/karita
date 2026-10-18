/// 正準化 — 言語をまたいで同じバイト列を作る。
///
/// `payloadHash` と、アップロード再送時のハッシュ照合は、Python と Dart が同じバイト列を作ることを
/// 前提にする。規則の正本は 非公開資料:sqlite-drive-sync-protocol.md である。
///
/// - UTF-8 で出力し、非ASCII文字をエスケープしない
/// - オブジェクトのキーはコードポイント昇順に並べる。**キーはASCIIに限る**
/// - 区切りは `,` と `:` とし、空白を入れない
/// - 浮動小数を payload に含めない。整数、文字列、真偽、null、配列、オブジェクトだけを使う
/// - 整数は 2^53-1 を超えない
/// - `payloadHash` は正準化後のバイト列の SHA-256 とし、`sha256:` を前置した小文字hexで書く
///
/// Dart の `jsonEncode` は区切りに空白を入れず非ASCIIもエスケープしないため2つは既定で合うが、
/// **キーを並べ替えない。** そこで自前の直列化を持つ。ASCII キーに限る限り Dart の
/// `String.compareTo`（UTF-16 コード単位順）はコードポイント順と一致する。
///
/// 移送元: book-sync-model の `src/contracts/canonical.py`。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'errors.dart';

const String hashPrefix = 'sha256:';

/// 2^53-1。Dart の int は 64bit だが Web では double であり、これを超えると値が変わる。
const int maxSafeInt = 9007199254740991;

bool _isAsciiKey(String key) {
  for (final unit in key.codeUnits) {
    if (unit > 0x7F) return false;
  }
  return true;
}

/// 浮動小数・非ASCIIキー・範囲外整数・非対応型を拒否する。書き込む前に止める。
void rejectUnsupported(Object? value, [String path = 'payload']) {
  if (value is bool) return;
  if (value is double) {
    throw SyncDataError(
      '$path に浮動小数を含められません: $value。'
      '整数、文字列、真偽、null、配列、オブジェクトだけを使ってください。',
      code: 'canonical-float',
    );
  }
  if (value is Map) {
    value.forEach((key, item) {
      if (key is! String) {
        throw SyncDataError('$path のキーは文字列である必要があります: $key', code: 'canonical-key');
      }
      if (!_isAsciiKey(key)) {
        throw SyncDataError(
          '$path のキーはASCIIである必要があります: "$key"。'
          'Python のコードポイント順と Dart の UTF-16 順が食い違い、'
          'payloadHash が言語間で一致しなくなります。',
          code: 'canonical-key-non-ascii',
        );
      }
      rejectUnsupported(item, '$path.$key');
    });
    return;
  }
  if (value is List) {
    for (var i = 0; i < value.length; i++) {
      rejectUnsupported(value[i], '$path[$i]');
    }
    return;
  }
  if (value is BigInt) {
    if (value < BigInt.from(-maxSafeInt) || value > BigInt.from(maxSafeInt)) {
      throw SyncDataError(
        '$path の整数が範囲外です: $value（±$maxSafeInt まで）。'
        'Dart の int は Web では double であり、2^53 を超えると値が変わります。',
        code: 'canonical-int-range',
      );
    }
    return;
  }
  if (value is int) {
    if (value < -maxSafeInt || value > maxSafeInt) {
      throw SyncDataError(
        '$path の整数が範囲外です: $value（±$maxSafeInt まで）。'
        'Dart の int は Web では double であり、2^53 を超えると値が変わります。',
        code: 'canonical-int-range',
      );
    }
    return;
  }
  if (value == null || value is String) return;
  throw SyncDataError('$path に載せられない型です: ${value.runtimeType}', code: 'canonical-type');
}

/// 正準化したバイト列を返す。
List<int> dumps(Object? value) {
  rejectUnsupported(value);
  final sb = StringBuffer();
  _write(value, sb);
  return utf8.encode(sb.toString());
}

/// 正準化した文字列（バイト列と同じ内容）。
String dumpsText(Object? value) => utf8.decode(dumps(value));

String payloadHash(Object? payload) {
  return hashPrefix + sha256.convert(dumps(payload)).toString();
}

/// 生のバイト列の SHA-256 を小文字hexで返す（`sha256:` の前置は付けない）。
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

void _write(Object? value, StringBuffer sb) {
  if (value == null) {
    sb.write('null');
    return;
  }
  if (value is bool) {
    sb.write(value ? 'true' : 'false');
    return;
  }
  if (value is int) {
    sb.write(value.toString());
    return;
  }
  if (value is BigInt) {
    sb.write(value.toString());
    return;
  }
  if (value is String) {
    _writeString(value, sb);
    return;
  }
  if (value is List) {
    sb.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) sb.write(',');
      _write(value[i], sb);
    }
    sb.write(']');
    return;
  }
  if (value is Map) {
    final keys = value.keys.map((k) => k as String).toList()..sort();
    sb.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) sb.write(',');
      _writeString(keys[i], sb);
      sb.write(':');
      _write(value[keys[i]], sb);
    }
    sb.write('}');
    return;
  }
  // double はここへ来ない（rejectUnsupported が先に落とす）。
  throw SyncDataError('載せられない型です: ${value.runtimeType}', code: 'canonical-type');
}

/// Python の `json.dumps(ensure_ascii=False)` と同じ規則で文字列を書く。
/// 短縮形（`\"` `\\` `\b` `\f` `\n` `\r` `\t`）と、その他の制御文字（<0x20）の小文字 `\u00xx`。
/// それ以外は非ASCIIを含めて生の文字として書き、末尾で UTF-8 にエンコードする。
void _writeString(String value, StringBuffer sb) {
  sb.writeCharCode(0x22);
  for (final unit in value.runes) {
    switch (unit) {
      case 0x22:
        sb.write(r'\"');
        break;
      case 0x5C:
        sb.write(r'\\');
        break;
      case 0x08:
        sb.write(r'\b');
        break;
      case 0x0C:
        sb.write(r'\f');
        break;
      case 0x0A:
        sb.write(r'\n');
        break;
      case 0x0D:
        sb.write(r'\r');
        break;
      case 0x09:
        sb.write(r'\t');
        break;
      default:
        if (unit < 0x20) {
          sb.write(r'\u');
          sb.write(unit.toRadixString(16).padLeft(4, '0'));
        } else {
          sb.writeCharCode(unit);
        }
    }
  }
  sb.writeCharCode(0x22);
}
