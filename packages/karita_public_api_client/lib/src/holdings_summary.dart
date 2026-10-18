/// 蔵書の観測から、画面が出す1つの状態を導く。
///
/// **畳んでよい区別と、畳んではいけない区別がある。** `Running`・`Error`・応答に現れない館・
/// 未照会を「蔵書なし」へ寄せると、画面が「この館には無い」と言い切ってしまう — 利用者は
/// それを見て予約をやめる。だから「蔵書なし」を名乗れるのは**頼んだ館が全部答え終えて、
/// どこにも無かった回だけ**である。
///
/// **応答に現れない組は実際に出る。** 2026-09-16 の実測で `complete=true` なのに 24組のうち
/// 22組しか返らない回があった（`非公開資料:2026-09-16-public-api-live-decisions.md`）。
/// 理論上の話ではないので、頼んだ館の数と返った館の数を突き合わせて数える。
///
/// **この層は語を持たない。** 出す言葉は UI が持つ。
library;

import 'calil_check.dart';
import 'failures.dart';

/// 画面が出す状態。**正本の表の行と1対1である。**
enum HoldingsState {
  /// まだ照会していない。**蔵書が無いことではない。**
  notRequested,

  /// 初回要求・継続取得中。まだどこにも見つかっていない。
  checking,

  /// 貸出可能を確認した。**借りに行ける。**
  available,

  /// 所蔵はあるが、いま借りられている。
  borrowed,

  /// 所蔵はあるが、取り置き・整理の途中である（`予約中` / `準備中`）。**待てば借りられる。**
  preparing,

  /// 所蔵はあるが借りられない（`館内のみ` / `休館中` / `不明`）。
  ///
  /// **知らない値もここへ入れる。** 借りられる側へ寄せると、行った先で借りられない。
  /// 寄せる先を選ぶなら、**過度に期待させない側**である（実際は借りられるかもしれないので、
  /// カーリルへのリンクは残す）。
  restricted,

  /// 対象館すべてが正常完了し、どこにも所蔵が無かった。
  absent,

  /// 通信失敗・館の `Error`・期限到達。**取得済みの部分結果は残る。**
  failed,

  /// 呼びすぎた。**時間を置けば直るので [failed] と分ける。**
  rateLimited,

  /// ISBN が無い・不正。**ISBN を補えば照会できる。**
  noIsbn,

  /// 登録済みの図書館が無い。
  noLibrary,

  /// appkey が無い端末。**蔵書が無いことではない。**
  keyMissing,
}

/// 1冊ぶんの蔵書サマリ。
class HoldingsSummary {
  final HoldingsState state;

  /// 成功した観測の時刻。**古い観測を今の確定結果に見せないために出す。**
  ///
  /// 観測が無ければ `null`。
  final DateTime? observedAt;

  /// 答え終えた館の数（`OK` / `Cache`）。
  final int settled;

  /// まだ答えていない館の数。**`Running`・知らない status・応答に現れない館の合計である。**
  ///
  /// 0 でなければ、見つかっていても「全館確認済み」ではない。
  final int pending;

  /// `Error` を返した館の数。
  final int errored;

  /// 取得そのものの失敗。**部分結果が在っても残す。**
  final ApiFailure? failure;

  const HoldingsSummary({
    required this.state,
    this.observedAt,
    this.settled = 0,
    this.pending = 0,
    this.errored = 0,
    this.failure,
  });

  /// まだ照会していない。
  static const HoldingsSummary notRequested =
      HoldingsSummary(state: HoldingsState.notRequested);

  /// ISBN が無い・不正。**呼ぶ前に分かる。**
  static const HoldingsSummary noIsbn =
      HoldingsSummary(state: HoldingsState.noIsbn);

  /// 登録館が無い。**呼ぶ前に分かる。**
  static const HoldingsSummary noLibrary =
      HoldingsSummary(state: HoldingsState.noLibrary);

  /// appkey が無い。**呼ぶ前に分かる。**
  static const HoldingsSummary keyMissing =
      HoldingsSummary(state: HoldingsState.keyMissing);

  /// 未確認の館が在るか。**肯定の結果に併記するためである。**
  bool get partial => pending > 0 || errored > 0;

  /// 所蔵がどこかで見つかっているか。**借りられるかどうかとは別である。**
  bool get found => const {
    HoldingsState.available,
    HoldingsState.borrowed,
    HoldingsState.preparing,
    HoldingsState.restricted,
  }.contains(state);
}

/// libkey の値を4つに分ける。**所蔵が在る側だけを見る。**
///
/// 相手が返すのは `貸出可` / `蔵書あり` / `館内のみ` / `貸出中` / `予約中` / `準備中` /
/// `休館中` / `不明` である。**知らない値は `不明` と同じ扱いにする** — 借りられる側へ寄せると
/// 行った先で借りられないので、寄せるなら期待させない側である。
///
/// 数が小さいほど利用者にとって良い。**同じ本を複数の館で見つけたら、いちばん良いものを出す。**
int _rank(String libkeyStatus) => switch (libkeyStatus) {
  '貸出可' => 0,
  '貸出中' => 1,
  '予約中' || '準備中' => 2,
  // `館内のみ` / `休館中` / `不明`、そして知らない値。
  _ => 3,
};

const List<HoldingsState> _byRank = [
  HoldingsState.available,
  HoldingsState.borrowed,
  HoldingsState.preparing,
  HoldingsState.restricted,
];

/// 観測から状態を導く。**純関数である。**
///
/// [holdings] が `null` なら未照会。[requestedSystemIds] は重複を除いた頼んだ館で、
/// **応答に現れなかった館を数えるために要る。**
HoldingsSummary summarizeHoldings({
  required List<String> requestedSystemIds,
  required List<SystemHolding>? holdings,
  DateTime? observedAt,
  ApiFailure? failure,
}) {
  if (requestedSystemIds.isEmpty) return HoldingsSummary.noLibrary;
  if (holdings == null) return HoldingsSummary.notRequested;

  final requested = requestedSystemIds.toSet();
  // **頼んだ館の答えだけを数える。** 頼んでいない館が応答に混ざっても勘定に入れない。
  final answered = <String, SystemHolding>{};
  for (final holding in holdings) {
    if (requested.contains(holding.systemId)) answered[holding.systemId] = holding;
  }

  var settled = 0;
  var errored = 0;
  var running = 0;
  // いちばん良い貸出状況。**見つからなければ所蔵なしである。**
  int? best;
  for (final holding in answered.values) {
    if (holding.isSettled) {
      settled++;
      for (final status in holding.libkeyStatuses.values) {
        final rank = _rank(status);
        if (best == null || rank < best) best = rank;
      }
    } else if (holding.isError) {
      errored++;
    } else {
      // `Running` と、知らない status。**決着させない。**
      running++;
    }
  }
  // **応答に現れなかった館も「まだ答えていない」に数える。** 落とすと、22/24 の回が
  // 「全館確認済み」に見える。
  final pending = running + (requested.length - answered.length);

  final HoldingsState state;
  if (best != null) {
    state = _byRank[best];
  } else if (failure == ApiFailure.rateLimited) {
    state = HoldingsState.rateLimited;
  } else if (failure != null) {
    state = HoldingsState.failed;
  } else if (pending > 0) {
    state = HoldingsState.checking;
  } else if (errored > 0) {
    // 全館が答えたが、答えたのは `Error` だけである。**蔵書なしではない。**
    state = HoldingsState.failed;
  } else {
    state = HoldingsState.absent;
  }

  return HoldingsSummary(
    state: state,
    observedAt: observedAt,
    settled: settled,
    pending: pending,
    errored: errored,
    failure: failure,
  );
}
