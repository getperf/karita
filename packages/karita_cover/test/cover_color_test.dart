import 'package:karita_cover/karita_cover.dart';
import 'package:test/test.dart';

void main() {
  group('代替ラベルの色', () {
    test('種から色が決まる。**値は別実装で出したものと突き合わせてある**', () {
      // 同じ混ぜ方（FNV-1a 32bit を UTF-8 のバイトへ、8色で剰余）を Dart の外で回して出した
      // 値である。ここがずれると、HTML で識別しやすさを確かめたときの見た目と本番が食い違う。
      expect(coverColorHex('9784873119038'), '695080');
      expect(coverColorHex('9784780802047'), '485e89');
      expect(coverColorHex('宇宙エレベーター'), '695080');
    });

    test('同じ種は必ず同じ色になる', () {
      for (final seed in ['book-0', 'book-1', '', 'あ']) {
        expect(coverColorHex(seed), coverColorHex(seed));
      }
    });

    test('8色すべてに当たる — 表の一部だけが使われることはない', () {
      const seeds = {
        'book-7': '244d63',
        'book-4': '695080',
        'book-1': '386653',
        'book-6': '8b493b',
        'book-3': '745c29',
        'book-0': '485e89',
        'book-5': '80516a',
        'book-2': '48686c',
      };
      for (final entry in seeds.entries) {
        expect(coverColorHex(entry.key), entry.value, reason: entry.key);
      }
      expect(seeds.values.toSet().length, coverPalette.length);
    });

    test('空の種でも落ちない。**種が無いことは色が無いことではない**', () {
      expect(coverPalette, contains(coverColorHex('')));
    });

    test('色は rrggbb の6桁である', () {
      for (final color in coverPalette) {
        expect(RegExp(r'^[0-9a-f]{6}$').hasMatch(color), isTrue, reason: color);
      }
    });
  });
}
