/// 規則1「文言を書かない」を**機械で判定する。**
///
/// 宣言だけでは滲む。`unawaited_futures` を lint で塞いだのと同じで、人手の注意で守るものでは
/// ない。**`lib/` の Dart ソースの文字列リテラルに日本語が現れたら赤にする。**
///
/// **コメントは対象外である。** この repo はコメントに理由を日本語で書く。禁じているのは
/// *画面に出る言葉*であって、コードの中の説明ではない。だから「コメントかリテラルか」を
/// 見分ける必要があり、正規表現では足りない — 状態を持って1文字ずつ歩く。
///
/// これに引っかかったものは本番 GUI の断片である。`../karita-ui-probe` へ出すこと。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/ の文字列リテラルに日本語が無い', () {
    final offenders = <String>[];
    final root = Directory('lib');
    expect(root.existsSync(), isTrue, reason: 'lib/ を lib/ から見つけられない');

    var scanned = 0;
    for (final entry in root.listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      scanned++;
      final source = entry.readAsStringSync();
      for (final found in _japaneseStringLiterals(source)) {
        offenders.add('${entry.path}:${found.line}  ${found.text}');
      }
    }

    // **走査していないのに緑にならないこと。** 相対パスの解決が変われば 0 件で通ってしまう。
    //
    // **P5a で 6 から 5 へ下げた。** `composition.dart` が `karita_app` へ移り、harness は
    // その利用側へ降りた。**下限を下げるのは合成が出ていったときだけである** — 画面が減った
    // ときに下げると、この検査は走査漏れを見なくなる。
    expect(scanned, greaterThanOrEqualTo(5), reason: 'lib/ を走査できていない');

    expect(
      offenders,
      isEmpty,
      reason: '文字列リテラルに日本語がある。'
          '表示名・説明文は本番 GUI（../karita-ui-probe）の持ち物である。\n'
          '${offenders.join('\n')}',
    );
  });

  test('判定そのものが働くこと', () {
    // **検査が検査になっていることを検査する。** 常に空を返す実装でも上の試験は緑になる。
    expect(_japaneseStringLiterals("var a = 'あ';").length, 1);
    expect(_japaneseStringLiterals('var a = "テスト";').length, 1);
    expect(_japaneseStringLiterals('var a = "図書";').length, 1);
    // コメントは対象外。
    expect(_japaneseStringLiterals('// 日本語のコメント'), isEmpty);
    expect(_japaneseStringLiterals('/// 日本語の doc コメント'), isEmpty);
    expect(_japaneseStringLiterals('/* 日本語のブロック */'), isEmpty);
    // ASCII のリテラルは通る。
    expect(_japaneseStringLiterals("var a = 'setupFresh()';"), isEmpty);
    // コメントの中の引用符でリテラル判定が崩れないこと。
    expect(
      _japaneseStringLiterals("// don't\nvar a = 'ok';"),
      isEmpty,
    );
  });
}

class _Found {
  final int line;
  final String text;

  const _Found(this.line, this.text);
}

final RegExp _japanese = RegExp(r'[぀-ヿ㐀-䶿一-鿿]');

/// Dart ソースを1文字ずつ歩き、**文字列リテラルの中身だけ**を拾う。
///
/// 見分けるのは4つの状態 — 素のコード、行コメント、ブロックコメント、文字列リテラル。
/// 生文字列（`r'...'`）は中身をそのまま拾う。補間（`${...}`）の中は式なので、`}` まで飛ばす。
List<_Found> _japaneseStringLiterals(String source) {
  final found = <_Found>[];
  var line = 1;
  var i = 0;

  void advance(int by) {
    for (var k = 0; k < by && i + k < source.length; k++) {
      if (source[i + k] == '\n') line++;
    }
    i += by;
  }

  while (i < source.length) {
    final rest = source.length - i;

    if (rest >= 2 && source[i] == '/' && source[i + 1] == '/') {
      final end = source.indexOf('\n', i);
      advance((end == -1 ? source.length : end) - i);
      continue;
    }
    if (rest >= 2 && source[i] == '/' && source[i + 1] == '*') {
      final end = source.indexOf('*/', i + 2);
      advance((end == -1 ? source.length : end + 2) - i);
      continue;
    }

    final quote = source[i];
    if (quote != "'" && quote != '"') {
      advance(1);
      continue;
    }

    // 三重引用符かどうかで終端が変わる。
    final triple = rest >= 3 &&
        source[i + 1] == quote &&
        source[i + 2] == quote;
    final delimiter = triple ? quote * 3 : quote;
    final startLine = line;
    advance(delimiter.length);

    final buffer = StringBuffer();
    while (i < source.length) {
      if (source.startsWith(delimiter, i)) {
        advance(delimiter.length);
        break;
      }
      if (source[i] == r'\') {
        advance(2);
        continue;
      }
      // 補間の中は式である。**リテラルではないので拾わない。**
      if (source.startsWith(r'${', i)) {
        var depth = 0;
        do {
          if (source[i] == '{') depth++;
          if (source[i] == '}') depth--;
          advance(1);
        } while (i < source.length && depth > 0);
        continue;
      }
      buffer.write(source[i]);
      advance(1);
    }

    final text = buffer.toString();
    if (_japanese.hasMatch(text)) found.add(_Found(startLine, text));
  }

  return found;
}
