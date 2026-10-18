/// 状態から選ぶ文言。**固定の項目名・説明は view に置く**（2026-09-17 の決定）。
///
/// 全画面共通の文言台帳は作らない。ここに在るのは「値によって言葉が変わるもの」だけである。
library;

import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';

import 'state.dart';

/// 常用館の現在値。**3状態それぞれに別の言葉を出す。**
///
/// 参照切れの文言は仕様で決めたものをそのまま採る（「参照先が見つからないときは『登録していた館が見つかりません』と再選択を促す」）。
String preferredBranchValue(PreferredBranch branch) => switch (branch.state) {
  PreferredBranchState.unset => '未設定',
  PreferredBranchState.resolved => branch.branchName!,
  PreferredBranchState.dangling => '登録していた館が見つかりません',
};

/// マイページ URL の出典。**必ず出す**（`library-site-url.md` §3）。
///
/// 既定値はアプリ作者が確認した時点の値で、館サイトの更新で切れる。切れたことをアプリは
/// 検知できないので、**古さを伝える手段は表示しかない。**
String mypageSourceLabel(MypageUrlSource source) => switch (source) {
  MypageUrlSource.imported => '取り込み値',
  MypageUrlSource.bundled => '既定値',
  MypageUrlSource.official => '公式サイト',
  MypageUrlSource.unset => '未設定',
};

/// 確認日つきの出典。**確認日は出典によって意味が変わる** — 既定値なら作者の採取日、
/// 取り込み値なら利用者の取り込み日である。公式サイトと未設定では無い。
String mypageSourceLine(MypageUrl url) {
  final label = mypageSourceLabel(url.source);
  final checkedOn = url.checkedOn;
  return checkedOn == null || checkedOn.isEmpty
      ? label
      : '$label・$checkedOn 確認';
}

/// 削除で残るもの。**数字は消えない件数である。**
///
/// **「消える」と書かない。** 棚卸記録も Loan も消さず、館名が出なくなるだけである
/// （`非公開資料:ui-state-model.md`「削除で残るもの」）。
List<String> removalConsequences(LibraryRemovalImpact impact) => [
  if (impact.loans > 0) 'この図書館で借りた記録 ${impact.loans} 件は残りますが、図書館名は表示されなくなります。',
  if (impact.memberships > 0) '棚卸の記録 ${impact.memberships} 件は残ります。',
  if (impact.hasPreferredBranch || impact.hasMypageUrl)
    '${[if (impact.hasPreferredBranch) '常用館', if (impact.hasMypageUrl) 'マイページ URL'].join('と')}の設定は参照先を失います。',
  '削除はほかの端末にも伝わります。',
];

/// 候補の件数。**絞り込んでいるかどうかで言い方が変わる。**
///
/// 絞り込んでいないときに「N 件 / N 件」と出しても読む値が無い。絞り込んでいるときは、
/// **母数を一緒に出す** — 「0件」が「無い」なのか「絞りすぎ」なのかを利用者が決められる。
String candidateCount({
  required String pref,
  required int hits,
  required int total,
}) => hits == total ? '$prefの図書館：$hits件' : '$hits件 / $prefの$total件';

/// 保存を止める理由。**拒否と警告を混ぜない。**
///
/// **キーを削って「安全な URL」へ
/// 加工しない** — 加工した値が安定したログイン入口である保証が無いので、利用者に送り直して
/// もらう。
String? urlRejection(Set<UrlSaveIssue> issues) {
  if (issues.contains(UrlSaveIssue.sessionKey)) {
    // **導線の文言と揃える**（2026-09-18）。モックの「ログイン画面の URL を送ってください」は、
    // 画面が「マイページへ移動してから送る」と案内するようになったので使えない。**言うべき
    // ことは変わっていない** — セッション ID を含む URL は次回つながらない。
    return 'この URL にはセッション ID が含まれています。次に開いたときにはつながりません。'
        'ログインしなくても同じままの URL を送ってください。';
  }
  if (issues.contains(UrlSaveIssue.notWeb) ||
      issues.contains(UrlSaveIssue.hasUserInfo)) {
    return '認証情報を含まない http(s) の URL が必要です。';
  }
  return null;
}

/// 候補の出どころ。**古さを出すのは受信のときだけである。**
String candidateSource(MypageDraftSource source) => switch (source) {
  MypageDraftSource.none => '',
  MypageDraftSource.received => '［karita に送る］で受け取りました。',
  MypageDraftSource.typed => '',
};

/// 候補の古さ。**一時保持に期限を置かないと決めた代償である**（2026-09-12）。
///
/// 数値の根拠がないので期限を決めず、**古さを伝える手段を表示だけにした。** 分単位より細かく
/// しない — 秒を出しても利用者の判断は変わらない。
String candidateAge(Duration age) {
  if (age.inMinutes < 1) return 'たった今、ブラウザーを開きました。';
  if (age.inHours < 1) return '${age.inMinutes}分前にブラウザーを開きました。';
  if (age.inDays < 1) return '${age.inHours}時間前にブラウザーを開きました。';
  return '${age.inDays}日前にブラウザーを開きました。古い候補かもしれません。';
}
