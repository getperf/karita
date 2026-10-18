/// 合成層への口。**画面側でここだけが `Composition` を知る。**
///
/// **値を持たない。** `ProviderScope` の `overrides` で外から差し込む — runner（`apps/karita`）
/// は `boot()` の戻り値を、試験は `compose()` のデモをここへ入れる。
///
/// ```dart
/// ProviderScope(
///   overrides: [compositionProvider.overrideWithValue(composition)],
///   child: ...,
/// )
/// ```
///
/// **合成を画面が作らない。** 作れる口をここへ置くと合成が2つに割れ、`karita_app` が
/// 「合成は1つだけである」で守っているものがそのまま崩れる
/// （`非公開資料:production-app-composition.md` 決定 B）。
///
/// **コード生成を使わない1本である。** 生成した Provider は「計算する関数」を要求するが、
/// これは計算せず差し込まれるだけの継ぎ目である。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';

// **`Composition` の操作は機能ごとの拡張に分かれている**（2026-10-16）。拡張は import した
// ところでしか見えないので、この継ぎ目を通る画面にも届くよう出し直す。
export 'package:karita_app/karita_app.dart'
    show
        CompositionAccount,
        CompositionBackup,
        CompositionDiagnostics,
        CompositionHandoff,
        CompositionLibraries,
        CompositionLibrarySettings,
        CompositionRecords,
        CompositionSettings,
        CompositionSync;

/// 組み上がった1端末。**差し込まれていなければ落ちる。**
///
/// 黙って空の合成を返さない — 差し込み忘れた画面が「図書館が0件の端末」に見える。
final Provider<Composition> compositionProvider = Provider<Composition>(
  (ref) => throw UnimplementedError(
    'compositionProvider is not overridden. '
    'Wrap the app in ProviderScope(overrides: ['
    'compositionProvider.overrideWithValue(composition)]).',
  ),
);

/// 合成層の失敗を画面が受け取る形。**Riverpod が包んでいるので、型では受けられない。**
///
/// Riverpod 3 は Provider が投げた例外を `ProviderException` で包み、**依存を1段またぐたびに
/// もう1枚重ねる**（2026-09-17 実測。直接読んでも1枚は掛かる）。そしてその型は
/// `@publicInMisc` で、`flutter_riverpod` からも `riverpod` からも export されていない。
///
/// したがって `on ProviderException` とは書けず、**`on AppIssue` は一度も当たらない。**
/// 画面が `catch (_)` で全部飲むと、コードとメッセージを出すという設定の段の決定が消える。
///
/// **名前で受けずに中身を掘る。** `exception` は公開の getter なので、持っていれば取れる。
/// 持っていなければそこで止め、型名だけの1件にする — **生の例外を画面へ配らない**のは
/// 変わらない（`非公開資料:ui-state-model.md`「設定でこの段に決めたこと」）。
AppIssue appIssueOf(Object error) {
  Object current = error;
  for (var depth = 0; depth < 8; depth++) {
    if (current is AppIssue) return current;
    Object? nested;
    try {
      // ignore: avoid_dynamic_calls
      nested = (current as dynamic).exception as Object?;
    } catch (_) {
      break;
    }
    if (nested == null || identical(nested, current)) break;
    current = nested;
  }
  // **一番奥の型名を出す。** 包みの型（ProviderException）を出しても原因が分からない。
  return AppIssue('unexpected', 'Unexpected failure (${current.runtimeType}).');
}
