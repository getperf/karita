/// 本番 GUI の画面と状態。**文言を持つのはここである。**
///
/// 持つのは3つである。
///
/// - 基本データを購読する Provider と、ID 指定の詳細（`非公開資料:ui-state-model.md` §2）
/// - 画面の入力状態・表示条件
/// - 画面に出る言葉
///
/// **`karita_sync` と `karita_platform` を直接 import しない。** 生の DB 接続や同期 Engine を
/// 操作する代わりに、合成層（`karita_app`）の窓口を使う。**宣言では滲むので機械で見る** —
/// `test/boundary_test.dart` が `lib/` を歩く。
///
/// ## 中の並べ方
///
/// **`lib/src/` の直下は継ぎ目と全 feature が使うものだけで、画面は feature ごとの
/// ディレクトリに入る**（2026-09-16）。段階4 まで進むと 30〜40 本になり、他の package と
/// 同じ平置きでは読めなくなる。深さは1段で止め、feature の中は役割をファイル名で分ける。
///
/// **層（`providers/`・`views/`）では切らない。** §4 は段階1〜4 を UI 単位で切り、§5 の
/// 設計メモ6項目も1 UI につき1枚である。層で切ると1つの設計メモが2ディレクトリに散る。
library;

export 'src/account/state.dart';
export 'src/account/view.dart';
export 'src/backup/generation_notice.dart';
export 'src/backup/state.dart';
export 'src/backup/view.dart';
export 'src/book_cover.dart';
export 'src/browser_link/state.dart';
export 'src/browser_link/view.dart';
export 'src/composition.dart';
export 'src/first_run/state.dart';
export 'src/first_run/view.dart';
export 'src/density.dart';
export 'src/icons.dart';
export 'src/libraries/state.dart';
export 'src/libraries/view.dart';
export 'src/notice.dart';
export 'src/setting_row.dart';
export 'src/shell/boot_gate.dart';
export 'src/shell/handoff_triage.dart';
export 'src/shell/library_setup.dart';
export 'src/shell/navigation.dart';
export 'src/shell/shell.dart';
export 'src/settings/state.dart';
export 'src/settings/view.dart';
export 'src/theme.dart';
export 'src/reservation/state.dart';
export 'src/lending/state.dart';
export 'src/lending/view.dart';
export 'src/lending/wording.dart';
export 'src/reservation/view.dart';

export 'src/bookshelf/holdings.dart';
export 'src/bookshelf/state.dart';
export 'src/bookshelf/view.dart';
