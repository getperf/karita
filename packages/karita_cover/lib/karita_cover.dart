/// 書影が無いときに枠へ出すものの規則。**描画は持たない。**
///
/// 出すのは色と、頭文字ラベルの SVG 文字列までである。縦長の枠へ正方形を中央寄せするのも、
/// SVG をラスタへ変えるのも `karita_ui` の側にある。**ここに Flutter を入れない** —
/// 代替ラベルは通信もしないので、実画像を取りに行く側（`karita_public_api_client`）とも
/// 別に置く。純 Dart であることで、「同じ本がいつも同じ見た目になる」を無印の `dart test` で
/// 固定できる。**画面が出来上がるより先に固定できる**のが、ここを分けた理由である。
///
/// 画像のバイトはここを通らない。復号できたかどうかは呼ぶ側が知っており、ここへは
/// 「実画像が無いときに何を出すか」だけを聞く。
library;

import 'dart:convert';

import 'package:dicebear_core/dicebear_core.dart' show Avatar, Style;
import 'package:dicebear_styles/initials.dart';

/// 生成規則の版。**上げると全書籍の見た目が変わる。**
///
/// 色の表・種の取り方・頭文字の options をまとめて指す。片方だけ変えて版を据え置くと、
/// 端末で見た目が割れたときに、どちらが古い規則なのかを区別する手掛かりが無くなる。
const int coverRuleVersion = 1;

/// 書影の枠に出すもの。
enum CoverArt {
  /// 取得して復号できた実画像。
  image,

  /// 書名から作った頭文字ラベル。
  initials,

  /// 頭文字を作れなかったときの共通アイコン。**通信の失敗ではない。**
  ///
  /// 数字と記号だけの書名がこれになる。オフラインでも書影が無くても頭文字は出るので、
  /// この退避が起きるのは「文字を作れない」ときだけである。
  bookIcon,
}

/// 代替ラベルの背景色。8色。
///
/// **本番の画面で隣り合う本を見分けるための色であり、意味を持たない。** 分類・状態・出典の
/// どれとも対応しない。増やすと取り違えは減るが、暗い背景で白文字が読めなくなる色が混じる。
const List<String> coverPalette = <String>[
  '244d63',
  '695080',
  '386653',
  '8b493b',
  '745c29',
  '485e89',
  '80516a',
  '48686c',
];

/// 代替ラベルの背景色を選ぶ。`rrggbb` の6桁を返す。
///
/// **種は書名ではなく、確定した `bookId` である。** 書名を種にすると、利用者が誤記を直した
/// だけで色が変わる — 棚に並んだ本を色で覚えている利用者にとっては、別の本に入れ替わったのと
/// 同じことが起きる。`bookId` は ISBN-13 から採番して端末をまたいで同じなので、**別の端末でも
/// 同じ色になる。**
///
/// 混ぜ方は FNV-1a の 32bit である。暗号用ではない — 要るのは「同じ種なら必ず同じ色」と
/// 「近い種が固まらない」の二つだけで、書籍数は多くても数千件である。
String coverColorHex(String colorSeed) {
  var hash = 2166136261;
  for (final byte in utf8.encode(colorSeed)) {
    hash = ((hash ^ byte) * 16777619) & 0xffffffff;
  }
  return coverPalette[hash % coverPalette.length];
}

/// 枠に出す代替ラベル1件。**実画像が無いときだけ作る。**
class CoverLabel {
  /// [CoverArt.initials] か [CoverArt.bookIcon]。**[CoverArt.image] にはならない** —
  /// 実画像を持っているかどうかは、取得した側が知っている。
  final CoverArt kind;

  /// 背景色。`rrggbb` の6桁。**本アイコンのときも色は在る** — 枠はどちらでも塗る。
  final String colorHex;

  /// 頭文字ラベルの SVG。[kind] が [CoverArt.bookIcon] なら `null`。
  final String? svg;

  const CoverLabel({required this.kind, required this.colorHex, this.svg});
}

/// 書影が無いときに枠へ出すものを決める。
///
/// **色の種と文字の種は別である。** 色は確定した `bookId`（[coverColorHex]）、文字は書名から
/// 取る。利用者が書名を直すと文字は変わるが色は変わらない — 棚の中の位置を色で覚えている利用者
/// にとって、誤記の修正で本が入れ替わって見えないほうが良い。
///
/// **文字を作れたかどうかは、書名ではなく出力を見て決める。** 頭文字の取り出しは DiceBear の
/// 規則そのままで、こちらは真似をしない — 真似をすると規則が2つになり、片方だけが版で動く。
/// 出来上がった SVG に中身のある `<text>` が無ければ、文字を作れなかったということなので
/// [CoverArt.bookIcon] へ退避する。数字と記号だけの書名がここへ来る。
CoverLabel coverLabel({required String colorSeed, required String title}) {
  final color = coverColorHex(colorSeed);
  final svg = _initialsSvg(title, color);
  return _hasVisibleText.hasMatch(svg)
      ? CoverLabel(kind: CoverArt.initials, colorHex: color, svg: svg)
      : CoverLabel(kind: CoverArt.bookIcon, colorHex: color);
}

/// 中身のある `<text>` が在るか。**空の `<text>` は「文字を作れなかった」である。**
final RegExp _hasVisibleText = RegExp(r'<text\b[^>]*>\s*[^<\s]');

/// 頭文字ラベルの options。**probe が両OSの実機で出したものと同じ値である**（2026-09-15決定）。
///
/// HTML で識別しやすさを比べたときの `fontSize` / `chars` は、この Dart 移植（10.x）に同じ名前
/// では無い。**移植側の名前へ読み替えるのではなく、probe が実際に描いた設定をそのまま採る** —
/// 読み替えた値が同じ見え方になる保証は無く、確かめたのは probe の出力のほうである。
///
/// `idRandomization` を落とすのは、SVG の中の id を毎回同じにするためである。**入れたままだと
/// 同じ本が呼ぶたびに違うバイト列になり**、出力を試験で固定できない。
String _initialsSvg(String title, String colorHex) => Avatar(_style, {
      'seed': title,
      'backgroundColor': ['#$colorHex'],
      'textColor': ['#ffffff'],
      'fontFamily': ['sans-serif'],
      'fontWeight': 700,
      'scale': 0.8,
      'initialsVariant': 'alt',
      'lettersVariant': 'double',
      'idRandomization': false,
    }).svg;

/// style の解析は1回でよい。**呼ぶたびに JSON を読み直さない。**
final Style _style = Style.parse(initials);
