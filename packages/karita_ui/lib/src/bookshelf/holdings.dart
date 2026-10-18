/// 本棚の蔵書照会。**走りの状態と、行に出す語を持つ。**
///
/// 分割・保持・期限・中止は合成層（`HoldingsLookup`）が持ち、集約規則は
/// `karita_public_api_client` が持つ。**ここが持つのは画面の都合だけ**である — いつ始めるか、
/// いつ止めるか、どの語を出すか。
///
/// ## 始まるのは押されたときだけである
///
/// タブ入場でも描画でも同期でも始めない。カーリルの枠は **キー単位で 1,000書籍リクエスト/時**
/// で、同梱キー1つを配る以上それは**インストール台数全体の合計**である。入場のたびに
/// 読みたて全件を照会すると、利用者が意図しないところで枠が溶ける
/// （`非公開資料:bookshelf-ui.md` §11）。
///
/// ## 止めるのは2箇所である
///
/// 本棚タブを離れたとき（ここが `ref.listen` で見る）と、背面へ回ったとき（合成層の
/// `_onLifecycle` が `cancel()` を呼ぶ）。**タブの Widget は `IndexedStack` で捨てられない**
/// ので、`autoDispose` では止まらない。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';

import '../composition.dart';
import '../libraries/state.dart';
import '../shell/navigation.dart';

/// 抱えている観測を読む口。**行のバッジはここから引く。**
///
/// 既定は合成層の口で、appkey が無い端末では `null` である。**1本通してあるのは試験のため**
/// で、差し替えれば偽の応答で一覧の塗り替えまで通せる（`compose()` の外まで持ち出さない）。
///
/// **照会そのものはここを通さない**（`Composition.checkHoldings`）。読むのと走らせるのを
/// 分けてあるのは、走らせる側に記録が要るからである。
final holdingsLookupProvider = Provider<HoldingsLookup?>(
  (ref) => ref.watch(compositionProvider).holdings,
);

/// 走りの状態。**一覧の「蔵書を確認」1つが持つ。**
class ShelfHoldingsRun {
  /// いま走っているか。**ボタンを無効にするために見る。**
  final bool running;

  /// 観測が更新された回数。**行の再描画の合図である。**
  ///
  /// 観測そのものは `HoldingsLookup` が持っているので、ここには入れない。**入れると同じ
  /// ものを2箇所で持つことになり、期限で消えた側とずれる。**
  final int revision;

  /// 一度でも照会したか。**未照会の行に語を出さないための旗である。**
  ///
  /// 押す前の棚に「未照会」を100行並べても読む人の役に立たない。**未照会はボタンの存在が
  /// 表している。**
  final bool checked;

  /// 直近の走りの結末。**押した結果の案内を出し分けるために持つ。**
  final HoldingsRunOutcome? outcome;

  const ShelfHoldingsRun({
    this.running = false,
    this.revision = 0,
    this.checked = false,
    this.outcome,
  });

  /// [clearOutcome] は**前の走りの案内を消すためである。**
  ///
  /// `outcome: null` では消せない（`??` が前の値を残す）。消せないと、上限で止まった次の回に
  /// 「上限に達しました」を出したまま照会が走る。
  ShelfHoldingsRun copyWith({
    bool? running,
    int? revision,
    bool? checked,
    HoldingsRunOutcome? outcome,
    bool clearOutcome = false,
  }) => ShelfHoldingsRun(
    running: running ?? this.running,
    revision: revision ?? this.revision,
    checked: checked ?? this.checked,
    outcome: clearOutcome ? null : (outcome ?? this.outcome),
  );
}

/// 蔵書照会の走り。
///
/// **`keepAlive` である。** タブを移っても、持っている観測と「一度照会した」旗を落とさない。
/// 戻ってきたときに同じ結果を同じ確認時刻で出す（取り直さない）。
final shelfHoldingsProvider =
    NotifierProvider<ShelfHoldings, ShelfHoldingsRun>(ShelfHoldings.new);

class ShelfHoldings extends Notifier<ShelfHoldingsRun> {
  @override
  ShelfHoldingsRun build() {
    // **本棚から離れたら止める。** `IndexedStack` は Widget を捨てないので、画面側の
    // dispose では止まらない。
    ref.listen(currentTabProvider, (previous, next) {
      if (next != ShellTab.bookshelf) stop();
    });
    return const ShelfHoldingsRun();
  }

  /// 照会する。**渡された行だけを対象にする。**
  ///
  /// 対象は呼ぶ側（一覧）が決める — いま絞込みに出ている読みたての行である。**全読みたてで
  /// はない。** 絞ってから押せば、100件の棚でも刻んで確かめられる。
  Future<void> run(List<ShelfBook> books) async {
    final lookup = ref.read(holdingsLookupProvider);
    if (lookup == null || state.running) return;
    final systems = ref.read(librariesProvider).keys.toList();
    // **正規化できない ISBN は外す。** 1冊の不正が塊10冊ぶんを道連れにする
    // （`CalilCheckClient` は形が違えば投げる）。外した行は「照会不可」で出る。
    final isbn13s = <String>{
      for (final book in books)
        if (book.isbn13 != null)
          if (normalizeIsbn13(book.isbn13!) case final String normalized)
            normalized,
    }.toList();
    if (isbn13s.isEmpty || systems.isEmpty) {
      state = state.copyWith(
        checked: true,
        outcome: HoldingsRunOutcome.nothingToDo,
      );
      return;
    }
    state = state.copyWith(running: true, checked: true, clearOutcome: true);
    // **合成層の口を通す。** 押した事実と結末が記録に残る（`holdings.check.*`）。
    // `lookup.check` を直に呼ぶと、外へ出た分の `api.fetch` しか残らない。
    var result = const HoldingsRunResult(outcome: HoldingsRunOutcome.failed);
    try {
      result = await ref
          .read(compositionProvider)
          .checkHoldings(
            // **読む口をそのまま渡す。** 行のバッジが引くのと同じ入れ物へ書き込む。
            lookup: lookup,
            isbn13s: isbn13s,
            systemIds: systems,
            // **届いた分から行を塗り替える。** 塊ごとではなく、館ごとの答えが届くたびに来る。
            onProgress: () =>
                state = state.copyWith(revision: state.revision + 1),
          );
    } finally {
      // **何があっても「確認中」を解く。** 押す口は `unawaited` なので、ここで解かないと
      // 投げた例外は誰にも届かず、ボタンが押せないまま残る。
      state = state.copyWith(
        running: false,
        revision: state.revision + 1,
        outcome: result.outcome,
      );
    }
  }

  /// 止める。**画面を離れたときに呼ぶ。持っている観測は捨てない。**
  void stop() {
    ref.read(holdingsLookupProvider)?.cancel();
    if (state.running) state = state.copyWith(running: false);
  }
}

/// 1冊ぶんのサマリを引く。**通信しない。**
///
/// `family` を作らない。**読みたてが100件あれば Provider が100個になる**が、ここは Map を
/// 1回引くだけの同期処理で、`ListView.builder` が見える行しか組まない前提と噛み合わない。
/// 走りの版（[ShelfHoldingsRun.revision]）を見ているので、届いたときに行は塗り替わる。
HoldingsSummary shelfHoldings(WidgetRef ref, ShelfBook book) {
  final lookup = ref.watch(holdingsLookupProvider);
  if (lookup == null) return HoldingsSummary.keyMissing;
  // 版を見る。**観測はここでは持たない。**
  ref.watch(shelfHoldingsProvider.select((run) => run.revision));
  final systems = ref.watch(librariesProvider).keys.toList();
  final isbn13 = book.isbn13 == null ? null : normalizeIsbn13(book.isbn13!);
  return lookup.summaryFor(isbn13: isbn13, systemIds: systems);
}

/// バッジに出す語。**正本の表の語をそのまま使い、短いものだけを入れる。**
///
/// **丸バッジに収まる長さで切る。** 確認時刻と未確認館の数はここへ入れない
/// （[shelfHoldingsDetail]）— 入れるとバッジが行の主役である書名より幅を取る。
///
/// 未照会・登録館なし・キーなしは空文字を返す。**行ではなくボタンの位置で伝える**ものである。
/// 「蔵書なし」と混ぜないために、空にするだけで済ませている。
String shelfHoldingsBadge(HoldingsSummary summary) => switch (summary.state) {
  HoldingsState.available => '蔵書あり',
  HoldingsState.borrowed => '貸出し中',
  HoldingsState.preparing => '準備中',
  HoldingsState.restricted => '貸出し不可',
  HoldingsState.absent => '蔵書なし',
  HoldingsState.checking => '確認中',
  HoldingsState.failed => '確認できません',
  // **上限も「確認できません」である。** 時間をおく案内はボタンの位置に1つ出るので、
  // 行ごとに繰り返さない。
  HoldingsState.rateLimited => '確認できません',
  HoldingsState.noIsbn => '照会不可',
  // **押す前・館なし・キーなしは「蔵書未確認」である。** 空欄にしない — バッジが常に在れば、
  // 「まだ聞いていない」と「聞いて無かった」が同じ位置で読み分けられる。
  HoldingsState.notRequested ||
  HoldingsState.noLibrary ||
  HoldingsState.keyMissing => '蔵書未確認',
};

/// バッジからカーリルを開けるか。**押せるものと押せないものを1箇所で決める。**
///
/// **`蔵書未確認` 以外は全部開ける**（2026-09-21 改定）。はじめは「観測になっていないものは
/// 押せない」にしていたが、**確認中・確認できませんこそ実サイトで見たい場面である** —
/// こちらが答えを持っていないときに、利用者の手を止める理由が無い。
///
/// 開けないのは2つだけ。**まだ何も聞いていない** `蔵書未確認`（押す前・館なし・キーなし）と、
/// **リンクを作れない** `照会不可`（ISBNなし）である。後者は押せないのではなく、
/// 行き先が存在しない。
bool shelfHoldingsLinked(HoldingsSummary summary) => !const {
  HoldingsState.notRequested,
  HoldingsState.noLibrary,
  HoldingsState.keyMissing,
  HoldingsState.noIsbn,
}.contains(summary.state);

/// バッジに添える細かい分。**無ければ空文字。**
///
/// **確認時刻は出さない**（2026-09-21 の実機確認）。出していたのは「古い観測を今の確定結果に
/// 見せない」ためだが、それは観測の保持が5分（`holdingsTtl`）で切れることが担保している —
/// 期限が過ぎた行は `蔵書未確認` へ戻るので、**出ているものは必ず5分以内である。**
/// 時刻は行ごとに1つ増える文字の割に、読む人が使い道を持たない。
String shelfHoldingsDetail(HoldingsSummary summary) {
  if (summary.state == HoldingsState.noIsbn) return 'ISBNなし';
  // **見つかっていても、未確認の館が在れば併記する。** 全館確認済みと区別する。
  final unconfirmed = summary.pending + summary.errored;
  if (summary.found && unconfirmed > 0) return '$unconfirmed館未確認';
  return '';
}

/// 押した結果の案内。**行ではなくボタンの位置に出す。**
///
/// 上限は行ごとに出さない。**枠はキー単位で尽きる**ので、原因は1冊の事情ではない。
String shelfHoldingsNotice(ShelfHoldingsRun run, {required bool canCheck}) {
  if (!canCheck) return '';
  return switch (run.outcome) {
    HoldingsRunOutcome.rateLimited => '照会の上限に達しました。時間をおいてください。',
    HoldingsRunOutcome.deadline => '時間内に確認しきれませんでした。もう一度押すと続けられます。',
    HoldingsRunOutcome.nothingToDo => 'ISBNのある本がありません。',
    HoldingsRunOutcome.failed => '蔵書を確認できませんでした。',
    // 中止（画面を離れた）と完了は案内を出さない。**結果は行が語る。**
    _ => '',
  };
}
