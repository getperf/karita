/// ブラウザーから来た URL の解析・分類・ISBN 正規化。**純 Dart である。**
///
/// **受理規則をここ1箇所だけに置く。** spike では ISBN の規則が Dart・JS・Kotlin の3写しに
/// なっていて、1つ直すのに3箇所と3つの試験が要った。OS 側（Kotlin・JavaScript・C++）に残すのは
/// 「URL がちょうど1件あるか」だけで、**ISBN の規則を1文字も置かない。**
///
/// **［karita に送る］は3用途の共通入口である** — 予約・貸出し（棚卸）の復帰・マイページ URL
/// 設定。ただし**用途を決めるのはここではない。** 書籍 URL だけが URL 単体で判定でき、残り2つは
/// どちらも「館サイトの一般 URL」で区別がつかない。用途の候補を組むのは合成層、確定するのは
/// 画面である。
///
/// **Flutter にも `dart:io` にも依存しない。** 受理規則の試験を無印の `dart test` で回すためで
/// ある。`karita_contract` を引くのも試験だけで、本体は依存を持たない。
///
/// 正本は `非公開資料:browser-handoff-implementation.md`。仕様は `../karita-ui-probe` が
/// 持つ。
library;

export 'src/isbn.dart';
export 'src/parse.dart';
export 'src/save_check.dart';
