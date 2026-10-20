/// 合成層。**利用側（harness・本番 GUI）はここだけを見る。**
///
/// 持つのは4つである。
///
/// - どの実装を使うかの分岐（Windows / Android / デモ）と、`SyncEngine` と `DomainContext` の
///   組み立て
/// - ログ sink の設置（`非公開資料:logging-and-diagnostics.md`）
/// - 前面の周期リフレッシュの配線と、**背面の口**（実装は持たない）
/// - デモの差し替え（`非公開資料:demo-mode.md`）
///
/// **利用側は合成を作らない。** [boot] を呼ぶだけである。合成が2つに割れると、gateway の
/// 決定 A（port を implement するのは合成層だけ）が守る対象そのものが分裂する。
///
/// **受け渡しの排出と一時保持はここにある**（[HandoffQueue]）。受理規則そのものは
/// `karita_handoff`（純 Dart）が持ち、ここは「どこまで処理したか」「いつブラウザーを開いたか」
/// という**状態**だけを持つ。
library;

export 'src/api_cache.dart';
export 'src/api_defaults.dart';
export 'src/background.dart';
export 'src/book_lookup.dart';
export 'src/composition.dart';
export 'src/demo.dart';
export 'src/demo_fixture.dart';
export 'src/handoff.dart';
export 'src/holdings_lookup.dart';
export 'src/libraries.dart';
export 'src/logging.dart';
export 'src/mypage_defaults.dart';
export 'src/public_api.dart';
export 'src/refresh.dart';
export 'src/settings.dart';

export 'src/bookshelf_export/models.dart';
