/// ISBN-13 への正規化。**この repo で唯一の実装である。**
///
/// ここが同一性の境目になる。`karita_domain` の `Books.adopt` は
/// `bookId = deterministicId(entityBook, isbn13)` を採番するので、取り込み経路の正規化が
/// 手入力経路と1桁でも違えば、**同じ本が別 `entityId` になる。** 重複は競合として立たず、
/// 両方が正常に適用される — **異常として観測できる箇所が無い。**
///
/// さらに `Books.adopt` の検証は `length != 13 || !digits` だけで、**チェック桁を見ていない。**
/// つまりチェック桁の関門はここしかない。手入力・貼り付け・標準共有・拡張の4経路すべてが
/// この関数を通る。
library;

/// ISBN-10 / ISBN-13 を ISBN-13 へ正規化する。**受理できなければ `null`。**
///
/// ハイフンと前後の空白を落とし、`X` は大文字に寄せる。10桁は mod 11、13桁は mod 10 で
/// チェック桁を検証する。**979 は13桁でだけ受理する** — ISBN-10 には 979 に対応する形が無く、
/// `978` 固定の変換しか定義されていない。
String? normalizeIsbn13(String raw) {
  final value = raw.trim().replaceAll('-', '').toUpperCase();

  if (_isbn10.hasMatch(value)) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += (value[i] == 'X' ? 10 : value.codeUnitAt(i) - _zero) * (10 - i);
    }
    if (sum % 11 != 0) return null;
    final body = '978${value.substring(0, 9)}';
    return '$body${_checkDigit13(body)}';
  }

  if (_isbn13.hasMatch(value)) {
    final body = value.substring(0, 12);
    return _checkDigit13(body) == value.codeUnitAt(12) - _zero ? value : null;
  }

  return null;
}

/// 12桁の本体からチェック桁を出す。**10桁からの変換と13桁の検証が同じ式を使う。**
int _checkDigit13(String body) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += (body.codeUnitAt(i) - _zero) * (i.isEven ? 1 : 3);
  }
  return (10 - sum % 10) % 10;
}

const int _zero = 0x30;
final RegExp _isbn10 = RegExp(r'^[0-9]{9}[0-9X]$');
final RegExp _isbn13 = RegExp(r'^97[89][0-9]{10}$');
