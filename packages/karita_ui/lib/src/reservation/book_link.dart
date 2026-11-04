/// 区の確認画面から、その本の館サイトのページを開く（2026-11-04）。
///
/// 予約の手順を **確認画面 → 館サイトで予約 → karita へ戻る →［予約した］** にするための口。
/// それまでは カーリル → 館サイト → カーリルへ戻る → ブラウザーから共有、と往復していた。
///
/// ## 行き先はカーリルの `reserveurl` である
///
/// `/check` が館ごとに返す、館の書誌ページの URL（江戸川区なら `WwShousaiKen.aspx?FCode=…`）。
/// **所蔵が無い館は空で返す**（2026-11-04 の実測）ので、無ければカーリルの書籍ページへ戻る。
/// 館ごとに OPAC の URL の型を持つ案は採らない — 館の数だけ保守が要る。
///
/// ## 確認画面を開いたときに照会する
///
/// 本棚は「押されたときだけ照会する」（`../bookshelf/holdings.dart`）。あちらは読みたて全件
/// × 全館で枠を食うからである。**ここは利用者が区を選んだ1冊 × 1館で、1リクエストである。**
/// 押してから聞くと `Running` の聞き直しで数秒待たせるので、開いた時点で先に聞く。
///
/// **観測は `HoldingsLookup` の5分の保持に乗せる。** 同じ区を開き直しても取り直さない。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';

import '../bookshelf/holdings.dart';
import '../composition.dart';

/// 1冊 × 1館の照会結果。
class ReservationBookLink {
  /// その館での蔵書の状態。**語は本棚のバッジと同じものを出す。**
  final HoldingsSummary summary;

  /// 館の書誌ページ。**相手が返したときだけ在る。**
  final Uri? url;

  const ReservationBookLink(this.summary, [this.url]);
}

/// 確認画面の本の行き先。鍵は `(ISBN-13, systemId)`。
///
/// **`autoDispose` である。** 確認画面を閉じたら照会の待ちも捨てる。観測そのものは
/// `HoldingsLookup` が持っているので、開き直せば通信せずに同じ答えが出る。
final reservationBookLinkProvider = FutureProvider.autoDispose
    .family<ReservationBookLink, (String, String)>((ref, key) async {
      final (isbn, systemId) = key;
      final lookup = ref.watch(holdingsLookupProvider);
      if (lookup == null) {
        return const ReservationBookLink(HoldingsSummary.keyMissing);
      }
      final isbn13 = normalizeIsbn13(isbn);
      if (isbn13 == null) {
        return const ReservationBookLink(HoldingsSummary.noIsbn);
      }
      final systems = [systemId];
      ReservationBookLink read() => ReservationBookLink(
        lookup.summaryFor(isbn13: isbn13, systemIds: systems),
        lookup
            .holdingFor(isbn13: isbn13, systemIds: systems, systemId: systemId)
            ?.reserveUrl,
      );
      final cached = read();
      // **答えを持っていれば聞かない。** 失敗・上限も期限つきで持っている（60秒・10分）ので、
      // その間に開き直しても外へ出さない。
      if (!const {
        HoldingsState.notRequested,
        HoldingsState.checking,
      }.contains(cached.summary.state)) {
        return cached;
      }
      // **合成層の口を通す。** 押した事実と結末が記録に残る（`holdings.check.*`）。
      await ref
          .read(compositionProvider)
          .checkHoldings(lookup: lookup, isbn13s: [isbn13], systemIds: systems);
      return read();
    });
