/// 受信の最終判定の型。**判定そのものは `Composition.triageOf` が持つ。**
library;

import 'package:karita_handoff/karita_handoff.dart';

import '../handoff.dart';

/// 受信1件を、用途ヒント・一時保持・ホスト逆引きで最終判定した結果。
///
/// **cold start（karita 未起動時に届いた配送）専用の判定である。** 一時保持が信頼できる
/// 通常のケース（`mypageCandidateOf`/`lendingCandidateOf` が候補を返すケース）は、この型を
/// 経由せず既存の候補ストリームがそのまま扱う。
sealed class HandoffTriage {
  const HandoffTriage();
}

/// 用途ヒントとホスト逆引きで、貸出しの対象地区が一意に決まった。
final class LendingTriageCandidate extends HandoffTriage {
  final String systemId;
  final DateTime startedAt;
  const LendingTriageCandidate(this.systemId, this.startedAt);
}

/// 用途ヒントとホスト逆引きで、マイページ URL 設定の対象地区が一意に決まった。
final class MypageTriageCandidate extends HandoffTriage {
  final String systemId;
  final Uri url;
  final DateTime startedAt;
  const MypageTriageCandidate(this.systemId, this.url, this.startedAt);
}

/// 用途は決まったが対象地区が一意でない。**0件（該当なし）も複数件も同じ形。**
final class DistrictChoiceNeeded extends HandoffTriage {
  final LaunchPurpose purpose;
  final Uri url;
  final List<String> systemIdChoices;
  const DistrictChoiceNeeded(this.purpose, this.url, this.systemIdChoices);
}

/// 用途も地区も決まらない。**Android 標準共有・旧拡張・ヒント無しの従来経路。**
final class PurposeChoiceNeeded extends HandoffTriage {
  final Uri url;
  const PurposeChoiceNeeded(this.url);
}

// --- Amazon の受信（`非公開資料:amazon-share-handoff.md` §3） ----------
//
// **4つとも利用者の選択を待たない。** 図書館の2用途と違い、行き先が1つに決まる。

/// 本棚の［Amazonで見る］の記録があった。**届いた URL の中身は見ない** — 別の本へ移って
/// 送っても元の画面へ戻す（誤った本を開くことはない）。記録は配った側が消す。
final class ShelfReturnCandidate extends HandoffTriage {
  /// 記録から開いていればその本。一覧から開いていれば `null`。
  final String? bookId;
  final DateTime startedAt;
  const ShelfReturnCandidate(this.bookId, this.startedAt);
}

/// 記録は無いが、ISBN で本棚の本が1冊に決まった。
final class ShelfBookFound extends HandoffTriage {
  final String bookId;
  const ShelfBookFound(this.bookId);
}

/// ISBN は取れたが本棚に無い（または同じ ISBN が複数ある）。**予約画面の下書きへ渡す。**
/// 自動では追加しない。
final class ShelfBookDraft extends HandoffTriage {
  /// `source` はホストだけの URL である。**URL 全文を下書きへ持ち込まない。**
  final HandoffBook book;
  const ShelfBookDraft(this.book);
}

/// Amazon だが ISBN が取れない（電子版・検索語・その他のページ）。
final class AmazonNoIsbn extends HandoffTriage {
  final AmazonShape shape;
  const AmazonNoIsbn(this.shape);
}
