/// 線画のアイコン。**単色・塗り無し・線だけである。**
///
/// 描き方は `karita-ui-probe` のレールに合わせてある（`mock/desktop-search.html` の
/// `.rail-item svg`）。
///
/// | | |
/// |---|---|
/// | 座標系 | 24×24（probe の `viewBox="0 0 24 24"`） |
/// | 塗り | **無し**（`fill: none`） |
/// | 線の太さ | **1.6 の座標系換算。** SVG の `stroke-width` は viewBox の単位なので、18px で描けば実寸 1.2px になる。ここも同じに揃える |
/// | 端・継ぎ目 | 丸（`stroke-linecap: round` / `stroke-linejoin: round`） |
///
/// **色と大きさは [IconTheme] から採る。** 自分では1色も持たない — 外殻が
/// `shell.dart` で配色から色を渡し、テーマ（明暗）に追従する。**素の色を既定にすると、
/// 2026-09-16 の「白地に白」がこちらでも再発する。**
///
/// **出典が分かれる。**
///
/// - [KaritaGlyph.reserve] と [KaritaGlyph.bookshelf] は **probe の path をそのまま写した**
/// - [KaritaGlyph.lending] は **probe とは違う。** probe は暦（`rect` ＋ 3本の線）だが、
///   **本と分かる形にする**と決めた（2026-09-17）。harness に出ていた開いた本を、この線画の
///   描き方で引き直したものである
///
/// **［設定］はここに無い。** probe に出典が無く（`settings.html` はレールも下部 Navbar も
/// 持たず、アイコンを1つも定義していない）、**Material の標準を使うと決めた**（2026-09-17）。
/// 出典の無い1つを自分で描くより、誰でも歯車と分かるものを借りるほうが安い。
/// **ここに在るのは本に関わる3つだけである。**
///
/// **probe 自身が「暫定の線画。正式な意匠はこの repo では決めない」と書いている。** 写している
/// のは暫定を暫定のまま写すことであって、意匠を確定させる行為ではない。**正式な意匠が来たら
/// 差し替えるのはこの1ファイルだけである。**
library;

import 'package:flutter/widgets.dart';

/// 描く形。**行き先の役割で名を付けてある**（何に見えるか、ではない）。
enum KaritaGlyph {
  /// 栞。probe の `M7 4h10v16l-5-4-5 4z`。
  reserve,

  /// 開いた本。**probe の暦ではない**（2026-09-17 の差し替え）。
  lending,

  /// 棚に立つ本と、傾いた1冊。probe の `M5 4v16M10 4v16M15 5l4 15M3 20h18`。
  bookshelf,
}

/// probe の座標系。**path はこの大きさで書いてある。**
const double _viewBox = 24;

/// probe の `stroke-width`。**座標系の単位である** — 実寸は大きさに比例して細くなる。
const double _strokeWidth = 1.6;

/// 線画を1つ描く。**[Icon] と同じ場所へ置ける。**
///
/// 大きさと色は [IconTheme] から採るので、`NavigationRail` の `selectedIconTheme` も
/// `NavigationBar` の既定の状態別の色も、そのまま効く。
class KaritaIcon extends StatelessWidget {
  const KaritaIcon(this.glyph, {super.key});

  final KaritaGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    // **`Icon` と同じ既定に揃える。** `IconTheme` は `WidgetsApp` が必ず1枚敷くので、
    // ここへ落ちるのは素の `WidgetsApp` すら無い場だけである。
    final size = theme.size ?? 24;
    final opacity = theme.opacity ?? 1;
    final color = (theme.color ?? const Color(0xFF000000)).withValues(
      alpha: (theme.color?.a ?? 1) * opacity,
    );
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlyphPainter(glyph: glyph, color: color),
        // **意味は外側が持つ。** `NavigationDestination` がラベルを付けるので、ここで
        // 読み上げの文言を重ねると2回読まれる。
        isComplex: false,
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({required this.glyph, required this.color});

  final KaritaGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _viewBox;
    canvas.save();
    canvas.scale(scale);
    canvas.drawPath(
      glyphPath(glyph),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        // **座標系の中で太さを決める。** `canvas.scale` が掛かるので、18px で描けば
        // 実寸 1.2px になる — SVG の `stroke-width` と同じふるまいである。
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

/// 24×24 の座標系で描いた形。**塗らない。**
///
/// 公開してあるのは**試験が形を測れるようにするため**である（境界が空でないこと、
/// 3つとも別の形であること）。
Path glyphPath(KaritaGlyph glyph) => switch (glyph) {
  // probe をそのまま：`M7 4h10v16l-5-4-5 4z`
  KaritaGlyph.reserve =>
    Path()
      ..moveTo(7, 4)
      ..lineTo(17, 4)
      ..lineTo(17, 20)
      ..lineTo(12, 16)
      ..lineTo(7, 20)
      ..close(),

  // 開いた本。背を1本、左右のページを対称に置く。
  KaritaGlyph.lending =>
    Path()
      ..moveTo(12, 7)
      ..lineTo(12, 20)
      ..moveTo(12, 7)
      ..cubicTo(9.5, 5.2, 6.5, 5, 4, 5)
      ..lineTo(4, 18)
      ..cubicTo(6.5, 18, 9.5, 18.2, 12, 20)
      ..moveTo(12, 7)
      ..cubicTo(14.5, 5.2, 17.5, 5, 20, 5)
      ..lineTo(20, 18)
      ..cubicTo(17.5, 18, 14.5, 18.2, 12, 20),

  // probe をそのまま：`M5 4v16M10 4v16M15 5l4 15M3 20h18`
  KaritaGlyph.bookshelf =>
    Path()
      ..moveTo(5, 4)
      ..lineTo(5, 20)
      ..moveTo(10, 4)
      ..lineTo(10, 20)
      ..moveTo(15, 5)
      ..lineTo(19, 20)
      ..moveTo(3, 20)
      ..lineTo(21, 20),
};
