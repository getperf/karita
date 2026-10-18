/// ナビゲーションの状態。**行き先の定義と、いま居る場所の2つである。**
///
/// **下部 Navbar とレールは同じ状態を使う**（`非公開資料:ui-state-model.md` §4
/// 段階1）。幅で形が入れ替わっても、選択は片方から片方へ写されるのではなく、はじめから
/// 1つしかない。
///
/// **共有範囲はアプリである**（§5 の3）。タブより上の共通スコープに置き、タブごとに独立した
/// コンテナを作らない。**保持はセッション内で、再起動では先頭へ戻す**（§5 の4）。
library;

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../icons.dart';

part 'navigation.g.dart';

/// Navbar の行き先。**並びがそのまま表示順である。**
///
/// **［設定］は4つ目である**（2026-09-16）。`ui-plan.md` §2 と `ui-state-model.md` §4 は
/// 「予約・貸出し・本棚の3つ。設定は Navbar に無い」と書いていたが、**その決定を差し替えた。**
/// 図書館設定の中へ潜らせると、設定画面そのものへの入口が probe 側にも無いまま残る。
enum ShellTab {
  /// **起動時の行き先である。** probe のモバイル版が「初期表示を図書予約」と決めている
  /// （`ui-plan.md` §3）。
  reserve('予約', 520, glyph: KaritaGlyph.reserve),

  lending('貸出し', 640, glyph: KaritaGlyph.lending),

  bookshelf('本棚', 640, glyph: KaritaGlyph.bookshelf),

  /// **アイコンは Material の標準である**（2026-09-17）。probe は設定画面のアイコンを
  /// 1つも定義していないので、**出典の無い1つを自分で描くより、誰でも歯車と分かるものを
  /// 借りる。** 本に関わる3つだけが線画である。
  ///
  /// 設定仕様 screens/settings.md の 560px。外殻の仮値640を置き換えた。
  settings('設定', 560, materialIcon: Icons.settings_outlined);

  const ShellTab(
    this.label,
    this.contentMaxWidth, {
    this.glyph,
    this.materialIcon,
  }) : assert(
         (glyph == null) != (materialIcon == null),
         '行き先のアイコンは線画か Material のどちらか1つである',
       );

  /// 画面に出る言葉。**`karita_ui` が文言を持つ側である。**
  ///
  /// 下部 Navbar とレールで同じ語を使う（`ui-plan.md` §2「Windows デスクトップ版は同じ
  /// 表示名を左端のアイコンレールで使う」）。
  final String label;

  /// 線画のアイコン（`icons.dart`）。**probe に出典がある行き先だけが持つ。**
  final KaritaGlyph? glyph;

  /// Material の標準アイコン。**probe に出典が無い行き先だけが持つ。**
  final IconData? materialIcon;

  /// 画面に出すアイコン。**線画でも Material でも、[IconTheme] に従う点は同じである。**
  ///
  /// **選択中の形を別に持たない。** probe のレールは1つの SVG を `currentColor` で描き、
  /// 現在地を**色と太さ**で示す（`.rail-item[aria-current="page"]`）。Material の
  /// 「輪郭↔塗りつぶし」の切り替えは、単色の線画には無い区別である。
  Widget get icon {
    final line = glyph;
    return line != null ? KaritaIcon(line) : Icon(materialIcon);
  }

  /// 本文の最大幅。**広い Window で入力欄と一覧が間延びしないようにする。**
  ///
  /// 予約 520px、貸出し・本棚 640px（probe `desktop-browser-workflow.md` §3）。
  /// **レールとヘッダーは幅いっぱいのまま、本文だけを左寄せで止める。**
  ///
  /// **密度トークン（`density.dart`）に置かない。** ポインタでは変わらず、行き先ごとに違う。
  final double contentMaxWidth;
}

/// いま居る場所。**起動は常に先頭（予約）である。**
///
/// **`ui.lastTab` を読まない**（2026-09-16 に閉じた。§4「直近タブは復元しない」）。復元が
/// 効くのは起動時だけで、前面復帰では Riverpod にナビ状態が残っており、Android の
/// プロセス kill 後は Draft ごと消えるので足りない。
///
/// **`Notifier` である**（§3）。同期の読み取りに見えるが、[select] という操作を持つ。
///
/// **`keepAlive` にする。** 誰も見ていない一瞬（幅の切替で外殻が入れ替わる間）に捨てられると、
/// 選択が先頭へ戻る。
@Riverpod(keepAlive: true)
class CurrentTab extends _$CurrentTab {
  @override
  ShellTab build() => ShellTab.reserve;

  /// 行き先を変える。**Navbar の切替は画面内の戻る操作とは別である**（`ui-plan.md` §2）。
  void select(ShellTab tab) => state = tab;
}
