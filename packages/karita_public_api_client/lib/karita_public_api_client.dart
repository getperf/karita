/// OpenBD とカーリルへ端末から直接つなぐ分。
///
/// **持たないもののほうが大事である。** キーの保管も、キャッシュも、進行中の要求の共有も、
/// 再試行の方針も、ここには無い。それらは端末の事情であり、合成層（`karita_app`）が決める。
/// ここが持つのは「1回の取得」と「その失敗の区別」だけで、**そう切っておくと固定応答に対する
/// 試験が無印の `dart test` で回る** — 実 API の可用性が CI の条件にならない。
///
/// 業務の型も返さない。返すのは候補であって、台帳に載るものではない。採るかどうかを決めるのは
/// 利用者で、変換するのは合成層である。
library;

export 'src/calil_check.dart';
export 'src/calil_library.dart';
export 'src/defaults.dart';
export 'src/failures.dart';
export 'src/holdings_summary.dart';
export 'src/openbd.dart';
export 'src/prefectures.dart';
