/// 密度トークン。**ポインタで切る。幅では切らない。**
///
/// 形（下部 Navbar かレールか）は**幅**で決まり、密度（操作要素をどこまで詰めるか）は
/// **ポインタ**で決まる。**2軸である**（`非公開資料:ui-state-model.md` §4
/// 「幅で切り替え、密度はポインタで切る」）。
///
/// 混ぜると Android タブレットで破綻する — 幅 800dp はレール側だが、**指で触るので操作要素は
/// 44px のままである必要がある。** 44px を 28〜38px へ下げた理由は「マウス操作に 44px の根拠が
/// ない」であって幅ではない（`karita-ui-probe` の `desktop-browser-workflow.md` §3）。
///
/// **閾値 440dp はここに無い。** 幅の話は外殻（`shell/shell.dart`）が持つ。
///
/// **本文の最大幅もここに無い。** 予約 520px・貸出し・本棚 640px は行き先ごとに違う値なので、
/// 行き先の定義（`shell/navigation.dart` の `ShellTab`）が持つ。ポインタでは変わらない。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 触るか、指さないか。**端末の種類ではない。**
///
/// Android タブレットも折りたたみの展開も [touch] である。
enum PointerKind {
  /// 指。**操作要素は 44px。**
  touch,

  /// マウス・トラックパッド・ペン。**28〜38px まで詰められる。**
  precise,
}

/// 操作要素の寸法。**決まっているのは [control] だけである。**
@immutable
class Density {
  final PointerKind pointer;

  const Density(this.pointer);

  /// 操作要素の最小の当たり判定。**44 / 32。**
  ///
  /// 44 は 2026-09-09 の Android のタップ精度の観察による。32 は probe の 28〜38px の中で
  /// 採った値である。**キーボード操作の可視性は輪郭で保つ**ので、詰めても失われない。
  double get control => pointer == PointerKind.touch ? 44 : 32;

  /// レールの幅。**アイコン18px ＋ 2〜3文字のラベル。**
  ///
  /// 44 は probe `desktop-browser-workflow.md` §3 の値で、**precise の実測である。**
  /// touch でも同じ値で始める — **仮であり、実機（タブレット・折りたたみ）で1回測る。**
  ///
  /// **この幅に Material の選択インジケータ（56px の丸枠）は入らない。** 外殻はレールの
  /// `useIndicator` を落とし、現在地を選択アイコンと色で示す。
  double get railWidth => 44;

  /// レールのアイコン。**18px**（probe §3）。Material の既定 24 では 44px に収まらない。
  double get railIconSize => 18;

  /// レールのラベル。**11px。** 「貸出し」の3文字が 44px に収まる大きさである。
  double get railLabelSize => 11;

  /// 下部 Navbar の高さ。**touch は Material の既定のままである。**
  ///
  /// **probe は下部 Navbar の高さを持たない** — Windows のモックにはレールしかなく、
  /// モバイルのモック（`mock/navbar-mobile.html`）はまだ測っていない。**値が無いところへ
  /// 独自の数字を置かない**ので、touch は Material の 80 をそのまま採る。
  ///
  /// precise の 64 は**仮である。** そもそもここへ来るのは Window を 440dp 未満へ縮めた
  /// ときだけで、probe の最小 Window 幅は 460px（予約）である。
  double get navigationBarHeight => pointer == PointerKind.touch ? 80 : 64;

  @override
  bool operator ==(Object other) =>
      other is Density && other.pointer == pointer;

  @override
  int get hashCode => pointer.hashCode;

  @override
  String toString() => 'Density(${pointer.name})';
}

/// OS からポインタを決める。**純関数である。**
///
/// 分岐を [Density] の中へ入れずに切り出してあるのは、**画面を立てずに全枝を固定できる**
/// ようにするためである。`TargetPlatform` は Flutter の列挙で、`karita_platform` とは無関係。
///
/// **`TargetPlatform.fuchsia` は触る側へ入れる。** 迷ったら 44px の方が安全で、**大きすぎて
/// 押せない操作要素は無い。**
Density densityFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => const Density(PointerKind.touch),
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => const Density(PointerKind.precise),
};

/// この端末の密度。**OS から1回決まる。**
///
/// **`Theme.of(context).platform` ではなく Provider にしてある。** 表示条件は `karita_ui`
/// （Riverpod）の持ち物であり（`非公開資料:ui-state-model.md` §3.1）、**試験は
/// `overrideWithValue` で触る側と指さない側の両方を測る。**
///
/// **`keepAlive` にする。** 幅で外殻が入れ替わる間に捨てても得るものが無い。
final Provider<Density> densityProvider = Provider<Density>(
  (ref) => densityFor(defaultTargetPlatform),
);
