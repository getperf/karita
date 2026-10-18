/// 線画のアイコン。**形が在ること・単色であること・[IconTheme] に従うことを測る。**
///
/// **画像 golden を置かない。** 線の見た目は人が見て決める段のもので、機械が守るのは
/// 「描かれないこと」「色を持たないこと」に落ちないことだけである。
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_ui/karita_ui.dart';

void main() {
  group('形', () {
    test('4つとも中身がある', () {
      for (final glyph in KaritaGlyph.values) {
        final bounds = glyphPath(glyph).getBounds();
        expect(bounds.isEmpty, isFalse, reason: glyph.name);
        // **24×24 の座標系に収まっていること。** はみ出すと `canvas.scale` で切れる。
        expect(bounds.left, greaterThanOrEqualTo(0), reason: glyph.name);
        expect(bounds.top, greaterThanOrEqualTo(0), reason: glyph.name);
        expect(bounds.right, lessThanOrEqualTo(24), reason: glyph.name);
        expect(bounds.bottom, lessThanOrEqualTo(24), reason: glyph.name);
      }
    });

    test('4つとも違う形である', () {
      // **同じ path を2つの行き先へ貼っていないこと。** 境界だけでも取り違えは出る。
      final bounds = {
        for (final glyph in KaritaGlyph.values) glyph: glyphPath(glyph).getBounds(),
      };
      expect(bounds.values.toSet(), hasLength(KaritaGlyph.values.length));
    });

    test('塗らない前提の形である（閉じた輪郭を数えない）', () {
      // 栞だけが閉じている。**残り3つは線の集まりで、塗ると意味が変わる。**
      expect(glyphPath(KaritaGlyph.reserve).contains(const Offset(12, 10)), isTrue);
      expect(glyphPath(KaritaGlyph.bookshelf).contains(const Offset(12, 12)), isFalse);
    });
  });

  group('IconTheme に従う', () {
    Future<void> pump(
      WidgetTester tester, {
      required double size,
      required Color color,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            home: IconTheme(
              data: IconThemeData(size: size, color: color),
              child: const Center(child: KaritaIcon(KaritaGlyph.reserve)),
            ),
          ),
        );

    testWidgets('大きさを受け取る', (tester) async {
      await pump(tester, size: 18, color: const Color(0xFF112233));
      expect(
        tester.getSize(find.byType(KaritaIcon)),
        const Size(18, 18),
      );

      await pump(tester, size: 24, color: const Color(0xFF112233));
      expect(
        tester.getSize(find.byType(KaritaIcon)),
        const Size(24, 24),
      );
    });

    testWidgets('色が変われば描き直す', (tester) async {
      CustomPainter painterOf() => tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(KaritaIcon),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;

      await pump(tester, size: 18, color: const Color(0xFF215A57));
      final first = painterOf();
      await pump(tester, size: 18, color: const Color(0xFF68C7BD));
      // **色が painter まで届いていること。** 届いていなければ2つは等しく、描き直さない。
      expect(painterOf().shouldRepaint(first), isTrue);
    });

    testWidgets('渡した色で実際に画素が塗られる', (tester) async {
      // **ここが「白地に白」の再発点である。** widget の属性ではなく**描いた結果**を見る —
      // 2026-09-16 の欠陥は「色が `null` のまま既定に落ちる」形だったので、属性だけ見ても
      // 同種の次の1件を捕まえられるとは限らない。
      const wanted = Color(0xFF68C7BD);
      const boundary = ValueKey('boundary');
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: Color(0xFFFFFFFF),
                child: IconTheme(
                  data: IconThemeData(size: 48, color: wanted),
                  child: KaritaIcon(KaritaGlyph.bookshelf),
                ),
              ),
            ),
          ),
        ),
      );

      final pixels = await tester.runAsync(() async {
        final render = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundary),
        );
        final image = await render.toImage();
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      });

      var painted = 0;
      for (var i = 0; i + 3 < pixels!.length; i += 4) {
        // **線の芯だけを数える。** 縁は白と混ざるので、近い画素は勘定に入れない。
        if ((pixels[i] - (wanted.r * 255)).abs() <= 2 &&
            (pixels[i + 1] - (wanted.g * 255)).abs() <= 2 &&
            (pixels[i + 2] - (wanted.b * 255)).abs() <= 2 &&
            pixels[i + 3] == 255) {
          painted++;
        }
      }
      expect(painted, greaterThan(0), reason: '渡した色で1画素も塗られていない');
    });
  });

  group('外殻が渡す形', () {
    test('行き先ごとにアイコンは1つである（線画か Material か）', () {
      for (final tab in ShellTab.values) {
        expect(
          (tab.glyph == null) != (tab.materialIcon == null),
          isTrue,
          reason: tab.name,
        );
      }
    });

    test('本に関わる3つが線画で、設定だけが Material である', () {
      // 2026-09-17。**probe は設定画面のアイコンを1つも定義していない。** 出典の無い1つを
      // 自分で描くより、誰でも歯車と分かるものを借りる。
      expect(ShellTab.reserve.glyph, KaritaGlyph.reserve);
      // 貸出しは **probe の暦ではない** — probe は `rect` ＋ 3本の線を描いている。
      expect(ShellTab.lending.glyph, KaritaGlyph.lending);
      expect(ShellTab.bookshelf.glyph, KaritaGlyph.bookshelf);
      expect(ShellTab.settings.glyph, isNull);
      expect(ShellTab.settings.materialIcon, isNotNull);
    });

    test('線画は3つとも別の行き先に割り当ててある', () {
      expect(
        {for (final tab in ShellTab.values) tab.glyph}..remove(null),
        KaritaGlyph.values.toSet(),
      );
    });

    testWidgets('どちらのアイコンも IconTheme の大きさに従う', (tester) async {
      for (final tab in ShellTab.values) {
        // **同じ instance を測る。** `tab.icon` は呼ぶたびに新しい Widget を作るので、
        // `find.byWidget` へ2度目の呼び出しを渡すと一致しない。
        final icon = tab.icon;
        await tester.pumpWidget(
          MaterialApp(
            home: IconTheme(
              data: const IconThemeData(size: 18, color: Color(0xFF215A57)),
              child: Center(child: icon),
            ),
          ),
        );
        // **レールが 18px を渡したとき、Material の標準だけ 24px にならないこと。**
        expect(tester.getSize(find.byWidget(icon)).width, 18, reason: tab.name);
      }
    });
  });
}
