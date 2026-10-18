/// 状態から選ぶ文言。**固定の項目名・説明は view に置く**（2026-09-17 の決定）。
///
/// **失敗のコードはここで日本語になる。** コードそのものは言語間で共有する契約なので
/// （`karita_domain` の `DomainError` の宣言）、**画面側で enum へ写さない** — 写すとずれ、
/// ずれても両方の試験が自分の正本に対して緑になる。
library;

import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';

/// 状態の表示名。**`WIP` という語は製品 UI に出さない**（`lending.md` §1）。
String loanStatusLabel(String status) => switch (status) {
  'reserved' => '予約中',
  'ready_for_pickup' => '取置中',
  'borrowed' => '貸出中',
  'returned' => '返却済み',
  'cancelled' => '取消済み',
  'expired' => '期限切れ',
  _ => status,
};

/// 受取館の表示。**削除済み・参照切れでも行を落とさない。**
///
/// 台帳から館が消えても Loan は残る（`ui-state-model.md`「削除で残るもの」）。記録した
/// 受取館の id は残っているが、名前を引く先が無い。
String pickupLibraryLabel(LoanReportItem item) =>
    item.pickupLibraryName ??
    (item.pickupLibraryId == null ? '受取館なし' : '登録していた館が見つかりません');

/// 失敗のコード。**業務の `DomainError` と合成層の `AppIssue` の両方から採る。**
///
/// Riverpod が例外を包むことがあるので（`composition.dart` の `appIssueOf` と同じ事情）、
/// **名前で受けずに中身を掘る。** 掘り当てられなければ `unexpected` にする — 生の例外を
/// 画面へ配らないのは変わらない。
String lendingIssueCode(Object error) {
  Object current = error;
  for (var depth = 0; depth < 8; depth++) {
    if (current is DomainError) return current.code;
    if (current is AppIssue) return current.code;
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
  return 'unexpected';
}

/// 失敗の言葉。**コードごとに何をすればよいかまで書く。**
///
/// **`invalid-transition` はもう出ない**（2026-09-19）。遷移の検査を業務層から落としたので、
/// 「その状態にはその操作を当てられない」という失敗そのものが無くなった。残っているのは
/// 記録できない値（受取館・日付）と、対象が見つからない場合だけである。
String lendingIssueMessage(String code) => switch (code) {
  'pickup-library' => 'この記録には受取館がありません。受取館を選んでから操作してください。',
  'pickup-library-unknown' => 'その館はこの図書館システムにありません。図書館管理で分館を取り直してください。',
  'loan-not-found' => 'この記録が見つかりません。［↻ 更新］で読み直してください。',
  'loan-action' => 'この操作はこの画面では扱えません。',
  'date' => '日付は正しい暦の日付を選んでください。',
  'missing-date' => '日付を入力してください。',
  'loans-load' => '一覧を読み込めませんでした。［↻ 更新］でやり直してください。',
  'libraries-load' => '図書館の一覧を読み込めませんでした。',
  'mypage-url-unset' => 'この地区の図書館サイトのURLがありません。図書館管理で設定してください。',
  'mypage-url-broken' => '保存されているURLが使えません。図書館管理で設定し直してください。',
  'browser-open' => 'ブラウザーを開けませんでした。',
  _ => '操作できませんでした（$code）。',
};

/// 成功したときの1行。**何が起きたかを状態の言葉で言う。**
String lendingAppliedMessage(String title, String status) =>
    '$title を${loanStatusLabel(status)}にしました。';

/// 別の図書館システムで同じ本を待っていることの注記。**畳まずに出す。**
///
/// 早く来た方を取るのは正当な運用で、片方が受取可能になったらもう片方を取り消す、という
/// 判断に直接効く（`loan_reporting.dart` の `parallelSystemIds`）。
String? parallelNote(LoanReportItem item) => item.parallelLabels.isEmpty
    ? null
    : '${item.parallelLabels.join('・')}でも同じ本を待っています';

/// 同じ図書館システムに同じ本の記録が二重にあることの注記。
///
/// **どちらも自動で取り消さない**（`loan-lifecycle.md`）。実在の二件だった場合に実在の予約を
/// 一件消すことになるため、決めるのは利用者である。
String duplicateNote() => '同じ本の記録がこの地区にもう1件あります';

/// 状態の1文字。**初期画面のサマリで使う**（2026-09-20）。
///
/// サマリは「どの区へ行くかを決める」ための読み取り専用の一覧で、`取置中` の3文字を並べても
/// **区ごとの内訳が読み取れるだけ隙間が空かない。** 1文字にして固定幅の列へ入れると、
/// 期限を持たない `予約中` の行とも桁が揃う（`lending.md` §2「一行でコンパクトに表示する」）。
///
/// **詳細の状態ボタンは3文字のままである。** あちらは押す対象で、1文字では狙いが読めない。
String loanStatusBadge(String status) => switch (status) {
  'reserved' => '予',
  'ready_for_pickup' => '取',
  'borrowed' => '貸',
  'returned' => '返',
  'cancelled' => '消',
  'expired' => '切',
  _ => '?',
};

/// サマリの期限。**`MM-DD`。持たない状態では全角ダッシュ1つ。**
///
/// **`期限` の見出しを付けない。** 列の位置そのものが何の数字かを示していて、毎行に同じ
/// 2文字を刷ると書名を押し出す。
String deadlineBadgeValue(String? deadline) =>
    deadline != null && deadline.length == 10
    ? '${deadline.substring(5, 7)}-${deadline.substring(8, 10)}'
    : '–';

/// 一括取消の確定ボタン。**選んでいない間も出す**（モックの `対象を選択`）。
///
/// **件数がそのまま確認である。** 押す前に何件が終端になるかが読めるので、取消だけに
/// 確認ダイアログを置かない — 返却との扱いが理由なく割れる。
String lendingCancelCommitLabel(int count) =>
    count > 0 ? '取消済み $count件にする' : '対象を選択';

/// 一括取消の結果。**件数で言う。**
///
/// **失敗した件数も出す。** 1件ずつの操作と違い、押した後に個々の行を目で追わないので、
/// 通らなかったものが黙って消えると気付けない。
String lendingCancelledMessage(int done, int failed) {
  if (done == 0) return '取消せませんでした。［↻ 更新］で読み直してください。';
  final head = '$done件を取消済みにしました。';
  return failed == 0 ? head : '$head$failed件は取消せませんでした。［↻ 更新］で読み直してください。';
}

/// 追加できたとき。**入ったのは予約中である**（`lending.md` §5）。
String lendingAddedMessage(String title) => '$title を予約中として追加しました。';

/// 追加できなかったとき。**`saveReservation` が投げる code をこの画面の言葉にする。**
///
/// **[lendingIssueMessage] と混ぜない。** あちらは1行の更新が投げる code の表で、ここは
/// 予約の記録が投げる `ReservationIssue` の表である。同じ地区を相手にしていても、直しに行く
/// 先（図書館管理）を添えるかどうかが違う。
String lendingAddIssueMessage(String code) => switch (code) {
  'active-wip' => 'この本はこの地区で予約中・取置中・貸出中です。追加していません。',
  'preferred-branch' => 'この地区の常用館が設定されていません。図書館管理で選んでから追加してください。',
  'no-system' => '追加する地区がありません。',
  'book-deleted' => 'この書誌は削除されています。',
  'book-identity-conflict' => 'この書誌のISBNが記録と食い違います。',
  'ambiguous-book' => '同じISBNの本が複数あります。書誌の重複を確認してください。',
  'isbn-invalid' => 'この書誌のISBNが正しくありません。',
  'reservation-date' => '予約日を記録できませんでした。',
  _ => '追加できませんでした（$code）。',
};
