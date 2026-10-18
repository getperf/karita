/// 取り込んだ ISBN-13 が `Books.adopt` の採番と同じ値になることを固定する。
///
/// **ここがずれると静かに壊れる。** 取り込み経路の正規化が手入力経路と1桁でも違えば、同じ本が
/// 別 `entityId` になる。重複は競合として立たず、両方が正常に適用される — 異常として観測できる
/// 箇所が無い。
///
/// 入力はデモ fixture の実在30 ISBN を流用する。**新しいデータを作らない** — fixture の書誌は
/// 2026-09-15 に OpenBD で確認した実在の値で、`karita_app` の検査が同じ ISBN から
/// `deterministicId(entityBook, isbn13)` を作っている。
///
/// **ISBN-10 の形で入れて、13桁の採番に一致することを見る。** 13桁をそのまま入れても正規化が
/// 素通りするだけで、10→13 の変換が正しいことの証明にならない。
library;

import 'dart:convert';
import 'dart:io';

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:test/test.dart';

void main() {
  test('fixture の30冊が、ISBN-10 経路でも同じ bookId になる', () {
    final books = _fixtureBooks();
    expect(books, hasLength(30), reason: 'fixture の書籍が読めていない');

    var checked = 0;
    for (final isbn13 in books) {
      final isbn10 = _toIsbn10(isbn13);
      // 979 で始まるものには ISBN-10 が無い。fixture は今のところ全て 978 である。
      if (isbn10 == null) continue;
      checked++;

      final result = parseHandoff('https://calil.jp/book/$isbn10');
      expect(result, isA<HandoffBook>(), reason: isbn10);
      final adopted = (result as HandoffBook).isbn13;

      expect(adopted, isbn13, reason: '$isbn10 → $isbn13');
      expect(deterministicId(entityBook, adopted),
          deterministicId(entityBook, isbn13),
          reason: isbn13);
    }
    expect(checked, greaterThanOrEqualTo(30), reason: '10桁経路を1件も通っていない');
  });

  test('13桁をそのまま入れても同じ bookId になる', () {
    for (final isbn13 in _fixtureBooks()) {
      final result = parseHandoff('https://calil.jp/book/$isbn13');
      expect(result, isA<HandoffBook>(), reason: isbn13);
      expect(deterministicId(entityBook, (result as HandoffBook).isbn13),
          deterministicId(entityBook, isbn13));
    }
  });
}

/// デモ fixture の ISBN を読む。**見つからなければ落とす** — 読めていないのに緑になると、
/// この試験は何も測らなくなる。
List<String> _fixtureBooks() {
  const relative = 'assets/demo/standard.json';
  final candidates = [
    File('../karita_app/$relative'),
    File('packages/karita_app/$relative'),
  ];
  final file = candidates.firstWhere(
    (candidate) => candidate.existsSync(),
    orElse: () => throw StateError(
        'デモ fixture が見つからない: ${candidates.map((c) => c.path).join(', ')}'),
  );
  final catalog = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final book in catalog['books'] as List) book['isbn13'] as String,
  ];
}

/// ISBN-13（`978` 始まり）から ISBN-10 を作る。**試験の入力を作るためだけの逆変換である。**
String? _toIsbn10(String isbn13) {
  if (!isbn13.startsWith('978') || isbn13.length != 13) return null;
  final body = isbn13.substring(3, 12);
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += int.parse(body[i]) * (10 - i);
  }
  final check = (11 - sum % 11) % 11;
  return '$body${check == 10 ? 'X' : check}';
}
