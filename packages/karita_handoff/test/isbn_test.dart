import 'package:karita_handoff/karita_handoff.dart';
import 'package:test/test.dart';

void main() {
  test('ISBN-10 は 978 を前置してチェック桁を作り直す', () {
    expect(normalizeIsbn13('427421933X'), '9784274219337');
    expect(normalizeIsbn13('427421933x'), '9784274219337');
    expect(normalizeIsbn13('4-274-21933-X'), '9784274219337');
    expect(normalizeIsbn13('  427421933X  '), '9784274219337');
  });

  test('ISBN-13 はチェック桁を検証してそのまま返す', () {
    expect(normalizeIsbn13('9784274219337'), '9784274219337');
    expect(normalizeIsbn13('978-4-274-21933-7'), '9784274219337');
    // 979 は13桁でだけ受理する。ISBN-10 には対応する形が無い。
    expect(normalizeIsbn13('9791234567896'), '9791234567896');
  });

  test('チェック桁が合わなければ受理しない', () {
    expect(normalizeIsbn13('4274219330'), isNull);
    expect(normalizeIsbn13('9784274219330'), isNull);
  });

  test('ISBN ではない EAN と、形が違うものは受理しない', () {
    // 1234567890128 はチェック桁として正しいが 978/979 で始まらない。
    expect(normalizeIsbn13('1234567890128'), isNull);
    expect(normalizeIsbn13(''), isNull);
    expect(normalizeIsbn13('427421933'), isNull);
    expect(normalizeIsbn13('X274219337'), isNull);
    expect(normalizeIsbn13('97842742193370'), isNull);
  });

  test('X は末尾にだけ現れる', () {
    expect(normalizeIsbn13('42742193XX'), isNull);
    expect(normalizeIsbn13('X27421933X'), isNull);
  });
}
