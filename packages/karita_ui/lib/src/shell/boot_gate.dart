/// 起動ゲート。**Navbar より先に居る。**
///
/// ゲートが無いと図書館管理が話す台帳が無い（`非公開資料:ui-state-model.md` §4
/// 段階1「外殻は Navbar だけではない」）。
///
/// **述語は合成層が持つ。** 本番は `localGeneration(db) != null`、デモは常に開く。
/// `localGeneration` は `karita_sync` の関数で、**`karita_ui` は import しない**（§3）。
/// ここが受け取るのは `bool` だけである。
///
/// **表示は2つだけである**（§5 の6）。「ゲート未了」と「準備済み」で、読込中・失敗は
/// **起動ゲートの段**（初回起動の2択の画面本体）が持つ。この単位では作らない。
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../composition.dart';

part 'boot_gate.g.dart';

/// 起動準備が済んでいるか。**外殻はこれ1つで開く。**
///
/// **同期の読み取りなので `Provider` である**（§3）。`Composition.bootReady` は台帳の
/// 1行をその場で引くだけで、待つものが無い。
///
/// **再読込の契機は `ref.invalidate` である。** 初回起動の2択（新規／復元）が済んだ時点で
/// その画面が無効化する — **この Provider が自分で気付く手段は無い**（台帳を監視していない）。
/// **繋いだ**（2026-09-23。`first_run/state.dart` の `FirstRunSetup`）。
///
/// **`keepAlive` にする。** 外殻が幅で入れ替わる間に捨てられると、開いたゲートを開き直す。
@Riverpod(keepAlive: true)
bool bootReady(Ref ref) => ref.watch(compositionProvider).bootReady;
