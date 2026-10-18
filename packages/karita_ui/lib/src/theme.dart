import 'package:flutter/material.dart';

/// probe の仮トーン。色の数値を Widget へ散らさない。
ThemeData karitaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final primary = Color(dark ? 0xff68c7bd : 0xff215a57);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff215a57),
        brightness: brightness,
      ).copyWith(
        primary: primary,
        onPrimary: Color(dark ? 0xff172126 : 0xffffffff),
        surface: Color(dark ? 0xff172126 : 0xffffffff),
        surfaceContainerLowest: Color(dark ? 0xff101619 : 0xffeef2f3),
        surfaceContainerLow: Color(dark ? 0xff202d33 : 0xfff5f7f7),
        onSurface: Color(dark ? 0xffedf4f4 : 0xff172026),
        onSurfaceVariant: Color(dark ? 0xffa9b6ba : 0xff61707a),
        outlineVariant: Color(dark ? 0xff3a494f : 0xffd8e0e4),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
  );
}

/// 地と文字の組。**バッジと淡い操作のために持つ。**
typedef KaritaTone = ({Color background, Color foreground});

/// 「貸出し中」のバッジの色。**モックの `.holding-label.held` の琥珀。**
///
/// 所蔵は在るが、いまは借りられない。**「蔵書あり」（主色）と「貸出し不可」（灰）の間**に置く
/// — 待てば借りられるからである。
/// **明暗で同じ値である** — 淡い地に濃い文字の組は、どちらの背景の上でも読める。
KaritaTone karitaBorrowedTone(Brightness brightness) => (
  background: const Color(0xfff5ead8),
  foreground: const Color(0xff805817),
);

/// 「準備中」のバッジの色。**水色。**
///
/// 取り置き・整理の途中で、待てば借りられる。**琥珀（貸出し中）と分ける** — あちらは
/// 「誰かが借りている」で、こちらは「館の手の中に在る」である。
KaritaTone karitaPreparingTone(Brightness brightness) =>
    brightness == Brightness.dark
    ? (background: const Color(0xff1f3848), foreground: const Color(0xff91c3e5))
    : (background: const Color(0xffe3eef5), foreground: const Color(0xff426e8c));

/// 「読みたい」の札の色。**モックの `.type-badge`（`--brand-soft` / `--brand`）。**
///
/// 一覧の行の左に置く、本の記録へ入る札である。**主色の塗り（蔵書あり）と紛れないよう淡くする**
/// — 行の主役は書名であって、状態の札ではない。
KaritaTone karitaWantedTone(Brightness brightness) =>
    brightness == Brightness.dark
    ? (background: const Color(0xff183b39), foreground: const Color(0xff68c7bd))
    : (background: const Color(0xffdff0ed), foreground: const Color(0xff215a57));

/// 「読んだ」の札の色。**モックの `.type-badge.read`（`--read-soft` / `--read`）。**
///
/// 読みたいの緑と分ける。**読み終えたことは本棚の別の軸**であり、蔵書の有無とも関係が無い。
KaritaTone karitaReadTone(Brightness brightness) =>
    brightness == Brightness.dark
    ? (background: const Color(0xff342b44), foreground: const Color(0xffc4afe8))
    : (background: const Color(0xffeee9f7), foreground: const Color(0xff66518c));
