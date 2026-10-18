import 'package:karita_cover/karita_cover.dart';
import 'package:test/test.dart';

/// SVG の `<text>` の中身。**試験だけがこれを見る** — 本番は SVG をそのまま描く。
String? _text(String? svg) {
  final match = RegExp(r'<text[^>]*>(.*?)</text>', dotAll: true)
      .firstMatch(svg ?? '');
  return match?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
}

void main() {
  group('代替ラベル', () {
    test('書名から頭文字を作る。**取り出しは DiceBear の規則である**', () {
      expect(_text(coverLabel(colorSeed: 'b', title: '宇宙エレベーター').svg), '宇宙');
      expect(_text(coverLabel(colorSeed: 'b', title: '達人プログラマー').svg), '達人');
      expect(_text(coverLabel(colorSeed: 'b', title: 'AIという鏡').svg), 'AI');
      // 英字は語の頭から取る。**先頭2文字ではない。**
      expect(_text(coverLabel(colorSeed: 'b', title: 'Real World HTTP').svg), 'RH');
    });

    test('文字を作れない書名は本アイコンへ退避する', () {
      const noLetters = ['123', '2026', '---', '!!!', '', '   ', '9784873119038'];
      for (final title in noLetters) {
        final label = coverLabel(colorSeed: 'b', title: title);
        expect(label.kind, CoverArt.bookIcon, reason: '「$title」');
        expect(label.svg, isNull, reason: '「$title」');
      }
    });

    test('記号が混じっていても、文字が在れば頭文字になる', () {
      final label = coverLabel(colorSeed: 'b', title: '#1 ベストセラー');
      expect(label.kind, CoverArt.initials);
      expect(_text(label.svg), isNotEmpty);
    });

    test('**本アイコンでも色は在る。** 枠はどちらでも塗る', () {
      final label = coverLabel(colorSeed: 'book-1', title: '123');
      expect(label.kind, CoverArt.bookIcon);
      expect(label.colorHex, coverColorHex('book-1'));
    });

    test('同じ入力なら同じ SVG になる。**呼ぶたびに変わらない**', () {
      final first = coverLabel(colorSeed: 'b', title: '達人プログラマー').svg;
      final second = coverLabel(colorSeed: 'b', title: '達人プログラマー').svg;
      expect(first, second);
    });

    test('色は種で決まり、書名を直しても変わらない', () {
      final before = coverLabel(colorSeed: 'book-4', title: '我ら、プログラマ');
      final after = coverLabel(colorSeed: 'book-4', title: 'われらプログラマー');
      expect(after.colorHex, before.colorHex);
      expect(after.svg, isNot(before.svg));
    });

    test('背景色が SVG に入る。**枠と同じ色である**', () {
      final label = coverLabel(colorSeed: 'book-7', title: '宇宙エレベーター');
      expect(label.colorHex, '244d63');
      expect(label.svg, contains('#244d63'));
    });
  });
}
