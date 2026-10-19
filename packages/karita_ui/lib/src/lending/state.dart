/// 貸出し（棚卸）画面の状態。**一覧を自分で抱える、この段だけの形である。**
///
/// ## [ledgerRevisionProvider] を見るのは初期画面だけ
///
/// 図書館管理は台帳が変わるたびに読み直す（`libraries/state.dart`）。**詳細は逆にする**
/// （2026-09-19 決定。`非公開資料:p5-production-app.md` 段階3）。棚卸は館サイトを片手に
/// 手元を合わせていく作業で、1件直すたびに一覧が組み直されると、**どこまで直したかを
/// 見失う。** 同期が他端末の変更を持ってきたときも同じである。
///
/// **初期画面は台帳の変更で読み直す**（2026-10-20）。初期画面は読み取り専用のサマリで、
/// 位置を見失う作業が無い。手動の `↻ 更新` はこの端末の表示を揃えるだけで他の端末を
/// 揃えないので、初期画面からは外した。周期は同期（`RefreshLoop`）が刻み、画面は
/// 「同期が台帳を変えた」通知だけを見る — 画面側にタイマーを持たない。
///
/// 読み直す契機は次の4つである。
///
/// - タブ入場
/// - 詳細から初期画面へ戻ったとき — 棚卸の結果を初期画面へ持ち帰る区切りである
/// - 初期画面を見ている間の台帳の変更（[_followLedger]）
/// - 詳細の `↻ 更新`
///
/// 書込みが通ったら**該当行だけを差し替える。** 枠（受取・返却／予約中）と並びは
/// [LendingState.order] と [LendingState.section] が握っていて、読み直しでしか作り直さない。
///
/// **終端にした行を消す処理は書かない。** 合成層の読み口が返さなくなるので、次の読み直しで
/// 自然に落ちる（`lending.md` §3「終端状態になった行は `↻ 更新` まで現在位置に残し、
/// 更新時に WIP 一覧から外す」）。
///
/// ## 重複・並行・期限の判定を書き直さない
///
/// `effective`／`duplicateOf`（重複の畳み）、`parallelSystemIds`（別システムの並行予約）、
/// `configured`（削除済み館）、`urgency`（期限切れ・期限間近）は `LoanReportItem` が既に
/// 持っている。**ここで作り直すと、同じ問いに二つの答えが出る。**
///
/// ここが足すのは表示条件だけである — 3つのフィルタ、`systemid` 単位の束ね方、表示順、そして
/// 「受取と返却間近」の上限日。**どれも純関数**なので、widget を立てずに固定できる。
library;

import 'dart:async';

import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../composition.dart';
import '../shell/navigation.dart';
import '../libraries/state.dart';
import 'wording.dart';

part 'state.g.dart';

// --- 表示条件の純関数 -------------------------------------------------------

/// 一覧のフィルタ。**3つで固定し、並びの先頭の [all] を既定にする**（2026-10-15）。
///
/// 元は「取置・貸出中」を先頭・既定に置いた4つだった。**選ばれる場面が無かったので外した** —
/// 受取と返却に動くときは [soon] で足り、手元の全体を見るときは [all] で足りる。既定が絞り込み
/// だと、開いた直後に予約中の本が見えず、予約が記録されていないように読める。
///
/// 期限切れ専用のフィルタは**置かない。** 下限の無い [LendingFilter.soon] に必ず入るので、
/// 絞り込みを増やさずに気付ける。
enum LendingFilter {
  all('全件'),

  /// 受取に行く本と、返却が間近の本。**取置中は全件、貸出中は基準日から [soonDays] 日以内**
  /// （期限切れ含む。下限を置かない）。週末に開いて、来週中の読書と受取を決めるための窓である。
  soon('受取と返却間近'),

  reserved('予約中');

  const LendingFilter(this.label);

  /// 画面に出る言葉。**`karita_ui` が文言を持つ側である。**
  final String label;
}

/// 詳細一覧の枠。**上段が受取・返却、下段が予約中**（`lending.md` §2）。
enum LendingSection {
  action('受取・返却', '取置中・貸出中'),
  reserved('予約中', '');

  const LendingSection(this.heading, this.note);

  final String heading;

  /// 見出しに添える内訳。**予約中は状態が1つなので持たない。**
  final String note;
}

/// 「間近」とみなす日数。**基準日から8日以内** — 週末に開いても翌週の同じ曜日まで覆える。
const soonDays = 8;

/// 基準日から [soonDays] 日後。**暦の週ではなく、開いた日から数える。**
///
/// [asOf] は `YYYY-MM-DD`。壊れた値はそのまま返す — 期限の比較は文字列で行うので、
/// 比較不能な値は「間近ではない」に落ちるだけで、一覧全体は落ちない。
String soonLimitOn(String asOf) {
  final date = DateTime.tryParse(asOf);
  if (date == null || asOf.length != 10) return asOf;
  final limit = DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).add(const Duration(days: soonDays));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${limit.year.toString().padLeft(4, '0')}-'
      '${two(limit.month)}-${two(limit.day)}';
}

/// その行の期限。**予約中は期限を持たない** — 欄そのものを出さない（`lending.md` §2）。
String? deadlineOf(LoanReportItem item) => switch (item.status) {
  'ready_for_pickup' => item.pickupDueOn,
  'borrowed' => item.dueOn,
  _ => null,
};

/// 受取と返却間近か。**取置中は常に入る。貸出中は期限が [limit] 以前のとき入る。**
/// 下限は無く、期限を過ぎたものも必ず入る。
bool isPickupOrDueSoon(LoanReportItem item, String limit) {
  if (item.status == 'ready_for_pickup') return true;
  final deadline = deadlineOf(item);
  return item.status == 'borrowed' &&
      deadline != null &&
      deadline.isNotEmpty &&
      deadline.compareTo(limit) <= 0;
}

/// 期限を過ぎているか。**判定は台帳側の `urgency` をそのまま使う。**
///
/// 基準日は読み直したときのもので、行ごとに引き直さない。
bool isOverdue(LoanReportItem item) => item.urgency == 'overdue';

/// フィルタに当たるか。**4つを1箇所で決める。**
bool matchesFilter(LoanReportItem item, LendingFilter filter, String limit) =>
    switch (filter) {
      LendingFilter.soon => isPickupOrDueSoon(item, limit),
      LendingFilter.reserved => item.status == 'reserved',
      LendingFilter.all => true,
    };

/// 行の表示順。**台帳の `ORDER BY updated_at_utc` を使わない。**
///
/// あれは同期の都合で決まる並びで、棚卸の見え方とは関係が無い。出す順は
/// **取置中 → 貸出中 → 予約中、それぞれ期限の早い順**とする — 受け取りに行くものが先、
/// 返しに行くものが次、まだ動きの無いものが最後という巡回の順序である。
///
/// 期限を持たない予約中は予約日で並べ、最後は `loanId` まで見て必ず決めきる。同じ台帳が
/// 読むたびに違う並びになると、「連続操作で行が動かない」が成り立たない。
int compareLoanItems(LoanReportItem a, LoanReportItem b) {
  const rank = {'ready_for_pickup': 0, 'borrowed': 1, 'reserved': 2};
  String key(LoanReportItem item) =>
      deadlineOf(item) ?? item.reservedOn ?? '9999-12-31';
  final byStatus = (rank[a.status] ?? 9).compareTo(rank[b.status] ?? 9);
  if (byStatus != 0) return byStatus;
  final byDate = key(a).compareTo(key(b));
  if (byDate != 0) return byDate;
  final byTitle = a.title.compareTo(b.title);
  return byTitle != 0 ? byTitle : a.loanId.compareTo(b.loanId);
}

/// 館の優先度に使う、行の対応度。**小さいほど先に対応する。**
///
/// 0 期限切れ → 1 取置中 → 2 返却が [limit] 以内の貸出中 → 3 余裕のある貸出中 → 4 予約中。
/// 行の並び（[compareLoanItems]）とは別物で、**館を並べるためだけに使う。**
int loanPriority(LoanReportItem item, String limit) {
  if (isOverdue(item)) return 0;
  return switch (item.status) {
    'ready_for_pickup' => 1,
    'borrowed' => isPickupOrDueSoon(item, limit) ? 2 : 3,
    'reserved' => 4,
    _ => 5,
  };
}

/// 出す行が無い館の優先度。**どの行の対応度よりも後ろである。**
const noLoanPriority = 9;

/// 管理区分の並び。**対応度の高い館が先、出す行が無い館は最後。**
///
/// 登録済みが先、台帳から消えたシステムが後ろ。登録済みの中は 館の対応度（出す行の最小値）
/// → 最も早い期限 → 都道府県 → 名称 → id。**受取・返却が残る館を上げ、全部終わった館と
/// 対象 0 件の館を下げる。** 並べ直すのは初期画面を組むときだけで、詳細の中の並びは別である。
int compareLendingAreas(LendingArea a, LendingArea b) {
  if (a.configured != b.configured) return a.configured ? -1 : 1;
  final rank = a.rank.compareTo(b.rank);
  if (rank != 0) return rank;
  final earliest = a.earliest.compareTo(b.earliest);
  if (earliest != 0) return earliest;
  final pref = a.pref.compareTo(b.pref);
  if (pref != 0) return pref;
  final name = a.name.compareTo(b.name);
  return name != 0 ? name : a.systemId.compareTo(b.systemId);
}

/// 管理区分1つぶんの枠。**`systemid` を越えてグループ化しない**（`lending.md` §2）。
///
/// 管理地区と図書館システムは同じ単位である。`AreaLoanReport` は pref・city 単位なので
/// 流用しない — 同じ市に2つの図書館システムがあると1枠に混ざる。
class LendingArea {
  final String systemId;
  final String pref;
  final String name;

  /// 台帳に登録が在るか。**`false` は削除済み・未登録のシステムである。**
  ///
  /// Loan は消えないので枠だけが残る（`ui-state-model.md`「削除で残るもの」）。
  final bool configured;

  /// この枠に出す行。**フィルタ適用済み・表示順。**
  final List<LoanReportItem> items;

  /// [items] の最小の対応度（[loanPriority]）。**空なら [noLoanPriority]。**
  final int rank;

  /// [items] の最も早い期限（予約中は予約日）。**空なら空文字。**
  final String earliest;

  const LendingArea({
    required this.systemId,
    required this.pref,
    required this.name,
    required this.configured,
    required this.items,
    this.rank = noLoanPriority,
    this.earliest = '',
  });

  /// 行から [rank] と [earliest] を数えて作る。**[limit] は「間近」の上限日。**
  factory LendingArea.ofItems({
    required String systemId,
    required String pref,
    required String name,
    required bool configured,
    required List<LoanReportItem> items,
    required String limit,
  }) {
    var rank = noLoanPriority;
    String? earliest;
    for (final item in items) {
      final each = loanPriority(item, limit);
      if (each < rank) rank = each;
      final due = deadlineOf(item) ?? item.reservedOn;
      if (due != null && due.isNotEmpty) {
        if (earliest == null || due.compareTo(earliest) < 0) earliest = due;
      }
    }
    return LendingArea(
      systemId: systemId,
      pref: pref,
      name: name,
      configured: configured,
      items: items,
      rank: rank,
      // 期限を持たない行だけの館は、期限のある館の後ろへ回す。
      earliest: items.isEmpty ? '' : earliest ?? '9999-12-31',
    );
  }
}

// --- 画面の状態 -------------------------------------------------------------

/// 貸出し画面のどこに居るか。
enum LendingScreen {
  /// 管理区分の一覧。**読み取り専用のサマリである。**
  overview,

  /// 1つの管理区分の編集可能な詳細一覧。
  area,
}

/// 行き先1つ。**運ぶのは `systemId` だけである。**
class LendingRouteState {
  final LendingScreen screen;

  /// 見ている図書館システム。**[LendingScreen.overview] では `null`。**
  final String? systemId;

  const LendingRouteState.overview()
    : screen = LendingScreen.overview,
      systemId = null;

  const LendingRouteState.area(String this.systemId)
    : screen = LendingScreen.area;

  @override
  bool operator ==(Object other) =>
      other is LendingRouteState &&
      other.screen == screen &&
      other.systemId == systemId;

  @override
  int get hashCode => Object.hash(screen, systemId);

  @override
  String toString() => 'LendingRouteState(${screen.name}, $systemId)';
}

/// 一覧の中身。**枠と並びは更新でだけ作り直す。**
///
/// [order] と [section] が「いつ組み直すか」を握り、[rows] が「いま何が書いてあるか」を
/// 持つ。書込みは [rows] の1件を差し替えるだけなので、**行は動かない。**
class LendingState {
  /// 表示順の `loanId`。**読み直し（ライブラリ冒頭の4つの契機）でだけ作り直す。**
  final List<String> order;

  /// `loanId` → いまの行。**書込みのたびに差し替わる。**
  final Map<String, LoanReportItem> rows;

  /// `loanId` → 出す枠。**状態を変えても更新まで動かない**（`lending.md` §2）。
  final Map<String, LendingSection> section;

  /// 次の更新で一覧から外れる行。`loanId` → いまの状態。
  ///
  /// 読み口（`loadActiveLoans`）が返さなくなった行がここへ入る。**行そのものは位置に残り、
  /// 操作もできる** — 状態は自由に書き直せるので、返却済みにした行をその場で貸出中へ戻せる
  /// （戻すとここから抜ける）。**消す処理は書かない。** 次の更新で [order] から落ちる。
  final Map<String, String> leaving;

  final LendingFilter filter;

  /// 期限判定の基準日。**読み直したときのものを使い続ける。**
  final String asOf;

  final bool loading;

  /// 書込み中の行。**連打をその行だけで止める。**
  final String? busyLoanId;

  /// 一覧そのものが読めなかった。**空の結果と区別する**（`ui-state-model.md` §2）。
  final AppIssue? loadError;

  /// 直近の操作の結果。**短い notice として出して消える**（2026-09-19）。
  ///
  /// 本文にも見出しにも置かない — 棚卸は何件も続けて直す作業で、行の上に文が増えると押す
  /// 位置がそのたびにずれる。
  final String message;

  /// [message] を出した回数。**同じ文言が続いても notice を出すための種である。**
  ///
  /// 文字列そのものを購読すると、受取館を2件続けて同じ館へ変えたときに2回目が出ない。
  final int messageId;

  const LendingState({
    this.order = const [],
    this.rows = const {},
    this.section = const {},
    this.leaving = const {},
    this.filter = LendingFilter.all,
    this.asOf = '',
    this.loading = false,
    this.busyLoanId,
    this.loadError,
    this.message = '',
    this.messageId = 0,
  });

  /// まだ一度も読んでいない。**0件の正常な結果と区別する。**
  bool get unread => asOf.isEmpty;

  /// 「間近」の上限日（基準日の [soonDays] 日後）。
  String get soonLimit => soonLimitOn(asOf);

  /// 更新すると一覧から外れる行の数。**`↻ 更新` の隣に出す。**
  int get leavingCount => leaving.length;

  /// 行1つのいまの状態。**一覧から外れた行は [leaving] が持つ。**
  ///
  /// 読み口が返さなくなっても、利用者から見れば行はそこに在って状態が変わっただけである。
  /// 4つのボタンはこの値で選択中を決める。
  String statusOf(String loanId) =>
      leaving[loanId] ?? rows[loanId]?.status ?? '';

  /// 一覧から外れる行を除いた、いま生きている行。**件数と初期画面はこれを数える。**
  Iterable<LoanReportItem> get active sync* {
    for (final loanId in order) {
      if (leaving.containsKey(loanId)) continue;
      final row = rows[loanId];
      if (row != null) yield row;
    }
  }

  /// フィルタごとの合計件数。**全管理区分ぶんである**（`lending.md` §2）。
  ///
  /// 押す前に何件出るかが分かる。**同じ数字を並べる集計行を別に置かない。**
  int countFor(LendingFilter filter) {
    final end = soonLimit;
    return active.where((item) => matchesFilter(item, filter, end)).length;
  }

  /// 初期画面に出す枠。**フィルタ結果が0件の管理区分も落とさない**（`lending.md` §2）。
  ///
  /// 該当が無いことを枠内に出すので、[LendingArea.items] が空の枠も返す。[systems] は
  /// 登録済みの図書館システムで、**Loan だけが残っているシステムも枠として出す。**
  List<LendingArea> areasFor(List<LibrarySystem> systems) {
    final end = soonLimit;
    final grouped = <String, List<LoanReportItem>>{
      for (final system in systems) system.id: [],
    };
    // 登録が無いシステムの表示名を借りる先。`LoanReportItem` が既に組み立てている。
    final fallbackName = <String, String>{};
    for (final item in active) {
      final bucket = grouped.putIfAbsent(item.systemId, () => []);
      fallbackName.putIfAbsent(item.systemId, () => item.systemName);
      if (matchesFilter(item, filter, end)) bucket.add(item);
    }
    final known = {for (final system in systems) system.id: system};
    final areas = [
      for (final entry in grouped.entries)
        LendingArea.ofItems(
          systemId: entry.key,
          pref: known[entry.key]?.pref ?? '',
          // 登録が無ければ `LoanReportItem` が作った表示名を借りる。**id を裸で出さない。**
          name: known[entry.key]?.name ?? fallbackName[entry.key] ?? entry.key,
          configured: known.containsKey(entry.key),
          items: List.unmodifiable(entry.value..sort(compareLoanItems)),
          limit: end,
        ),
    ]..sort(compareLendingAreas);
    return List.unmodifiable(areas);
  }

  /// 詳細一覧の1枠ぶん。**フィルタは掛からない。**
  ///
  /// 初期画面の絞り込みは「どの区へ行くか」を決めるためのもので、区に入った後は**その区の
  /// 全部**を相手にする。終端にした行も位置に残す。
  List<String> sectionOf(String systemId, LendingSection section) => [
    for (final loanId in order)
      if (rows[loanId]?.systemId == systemId && this.section[loanId] == section)
        loanId,
  ];

  LendingState copy({
    List<String>? order,
    Map<String, LoanReportItem>? rows,
    Map<String, LendingSection>? section,
    Map<String, String>? leaving,
    LendingFilter? filter,
    String? asOf,
    bool? loading,
    String? busyLoanId,
    AppIssue? loadError,
    String? message,
    bool clearBusy = false,
    bool clearError = false,
  }) => LendingState(
    order: order ?? this.order,
    rows: rows ?? this.rows,
    section: section ?? this.section,
    leaving: leaving ?? this.leaving,
    filter: filter ?? this.filter,
    asOf: asOf ?? this.asOf,
    loading: loading ?? this.loading,
    busyLoanId: clearBusy ? null : busyLoanId ?? this.busyLoanId,
    loadError: clearError ? null : loadError ?? this.loadError,
    message: message ?? this.message,
    // **文言を渡すたびに数える。** 同じ文に続けてなっても notice は出る。
    messageId: message != null && message.isNotEmpty
        ? messageId + 1
        : messageId,
  );
}

/// 初期画面と詳細の行き来。**Navigator ではなく状態で持つ**（図書館管理と同じ前例）。
///
/// **`keepAlive` にする。** 幅で外殻が入れ替わる一瞬に捨てられると、詳細を見ていた利用者が
/// 初期画面へ戻される。**セッション交換では捨てる** — [build] が `compositionProvider` を
/// watch している。
@Riverpod(keepAlive: true)
class LendingRoute extends _$LendingRoute {
  @override
  LendingRouteState build() {
    ref.watch(compositionProvider);
    ref.watch(ledgerSessionProvider);
    return const LendingRouteState.overview();
  }

  /// 貸出しの候補が届いた。**呼ぶのは `PendingHandoffTriage`（`shell/handoff_triage.dart`）
  /// だけである。** ここ自身が `handoffTriage` を購読しないのは、`ledgerSessionProvider` も
  /// 見ているため起動直後の同期状態変化だけで何度も作り直され、購読を張り直す一瞬に
  /// broadcast stream のイベントを取りこぼす実害があったため（2026-09-29 実機で確認）。
  /// 公開しているのは試験のためでもある
  /// （`reservation_test.dart` の `actions.receive(delivery)` と同じ扱い）。
  void onLendingCandidate(String systemId) {
    openArea(systemId);
    ref.read(currentTabProvider.notifier).select(ShellTab.lending);
  }

  void openArea(String systemId) => state = LendingRouteState.area(systemId);

  /// 1つ戻る。**戻れたら `true`。**
  bool back() {
    if (state.screen == LendingScreen.overview) return false;
    state = const LendingRouteState.overview();
    return true;
  }
}

/// 一括取消の選択。**詳細画面だけの持ち物である。**
///
/// **`LendingState` に入れない。** あちらは一覧の中身（何が書いてあるか・どこの枠に出るか）
/// で、これは選択という操作の途中経過である。混ぜると、一覧を差し替えるたびに選択の有無を
/// 引き回すことになる。
class LendingSelectionState {
  /// 選択モードに入っているか。**「0件選んでいる」と区別する。**
  ///
  /// モックの確定ボタンは選択0件でも `対象を選択` として出ており、押せないだけである。
  /// 件数だけを見ると、入った直後とモード外が同じ値になる。
  final bool active;

  final Set<String> loanIds;

  const LendingSelectionState({this.active = false, this.loanIds = const {}});

  bool contains(String loanId) => loanIds.contains(loanId);

  int get count => loanIds.length;
}

/// 一括取消の選択。**区を出ると消える。**
///
/// **取消を一括にしたのはモックに合わせたからである**（2026-09-20）。行の操作列は4つの状態と
/// 期限で埋まっていて（`.book-controls` は `repeat(4, minmax(0, 1fr)) 76px`）、5つ目を足すと
/// 440dp 未満でどれも1〜2文字まで潰れる。取消がまとまって出るのは予約中の棚卸であり、
/// 1件ずつではない。**返却は行内に残す** — モック自身がそう言っている（`renderActionBar` の
/// 「返却は行内で完結するので、バーの一括操作は取消だけを扱う」）。
///
/// **[build] が [lendingRouteProvider] を watch している。** 初期画面へ戻ると選択は空へ戻り、
/// **後始末を呼び手ごとに書かなくてよい**（`LibrariesRoute` の `_returnTo` と同じ考え方）。
@Riverpod(keepAlive: true)
class LendingSelection extends _$LendingSelection {
  @override
  LendingSelectionState build() {
    ref.watch(lendingRouteProvider);
    return const LendingSelectionState();
  }

  void begin() => state = const LendingSelectionState(active: true);

  /// 選択をやめる。**モックの `解除` と、確定した後の出口を兼ねる。**
  void end() => state = const LendingSelectionState();

  void toggle(String loanId) {
    if (!state.active) return;
    final ids = {...state.loanIds};
    if (!ids.add(loanId)) ids.remove(loanId);
    state = LendingSelectionState(active: true, loanIds: Set.unmodifiable(ids));
  }
}

/// 貸出し一覧。**読み直す契機を2つに絞った Notifier である。**
///
/// **`keepAlive` にする。** 外殻の `IndexedStack` が本文を生かしたままにしているので、
/// タブを移って戻ってきても一覧は読み直されない — それがこの段の狙いそのものである。
@Riverpod(keepAlive: true)
class Lending extends _$Lending {
  @override
  LendingState build() {
    ref.watch(compositionProvider);
    // **復元で台帳が替わったら捨てる。** 合成は替わらないので、上の watch では足りない。
    ref.watch(ledgerSessionProvider);
    // **タブ入場が読み直しの契機である。** `IndexedStack` は画面を捨てないので、widget の
    // ライフサイクルでは入場を拾えない。行き先そのものを見る。
    ref.listen(currentTabProvider, (previous, next) {
      if (next == ShellTab.lending && previous != ShellTab.lending) refresh();
    });
    // **詳細から戻ったら読み直す。** 詳細で直した結果（外れた行・並び）を初期画面へ持ち帰る。
    ref.listen(lendingRouteProvider, (previous, next) {
      if (previous?.screen == LendingScreen.area &&
          next.screen == LendingScreen.overview &&
          ref.read(currentTabProvider) == ShellTab.lending) {
        refresh();
      }
    });
    ref.listen(ledgerRevisionProvider, (_, _) => _followLedger());
    // **初回は読まない。** 起動直後は先頭（予約）に居り、外殻がここも同時に build する。
    // 見ていない画面のために台帳を読むと、起動が Loan 全件ぶん遅くなる。
    scheduleMicrotask(() {
      if (ref.mounted && ref.read(currentTabProvider) == ShellTab.lending) {
        refresh();
      }
    });
    return const LendingState();
  }

  /// 台帳が変わった。**初期画面を見ているときだけ読み直す**（2026-10-20）。
  ///
  /// 通知はこの端末の書込みでも来る。詳細で1件直すたびに並びを組み直さないよう、詳細に
  /// 居る間は何もしない — 戻ったときに読み直す。見ていないタブも読まない（タブ入場で読む）。
  /// **notice は出さない** — 利用者が何もしていないのに「外しました」が出ると読めない。
  void _followLedger() {
    if (ref.read(currentTabProvider) != ShellTab.lending) return;
    if (ref.read(lendingRouteProvider).screen != LendingScreen.overview) return;
    if (state.unread || state.loading || state.busyLoanId != null) return;
    refresh(notify: false);
  }

  /// 読み直して枠と並びを作り直す。
  ///
  /// 終端にした行はここで落ちる — 合成層の読み口が返さなくなるからで、**消す処理は
  /// 書いていない。** [notify] が `false` なら外した件数の notice を出さない。
  void refresh({bool notify = true}) {
    final composition = ref.read(compositionProvider);
    final dropped = state.leavingCount;
    state = state.copy(loading: true, clearError: true);
    final List<LoanReportItem> items;
    try {
      items = composition.loadActiveLoans();
    } on Object catch (error) {
      state = state.copy(
        loading: false,
        loadError: appIssueOf(error),
        message: '',
      );
      return;
    }
    if (!ref.mounted) return;
    final sorted = [...items]..sort(compareLoanItems);
    state = LendingState(
      order: List.unmodifiable([for (final item in sorted) item.loanId]),
      rows: Map.unmodifiable({for (final item in sorted) item.loanId: item}),
      section: Map.unmodifiable({
        for (final item in sorted)
          item.loanId: item.status == 'reserved'
              ? LendingSection.reserved
              : LendingSection.action,
      }),
      filter: state.filter,
      asOf: localToday(),
      message: notify && dropped > 0 ? '一覧を更新し、$dropped件を外しました。' : '',
      messageId: notify ? state.messageId + 1 : state.messageId,
    );
  }

  void select(LendingFilter filter) =>
      state = state.copy(filter: filter, message: '');

  /// 1行の状態・日付を書く。**通ったらその行だけを差し替える。**
  ///
  /// **どの状態からどの状態へでも書ける**（`karita_domain` の `loanActions`）。館サイトが
  /// そう見せているならそう記録できる、という規則をこの画面が体現する。
  ///
  /// 読み口が返さなくなった行は [LendingState.leaving] へ記録して**位置に残す。** 書き直せば
  /// そこから戻ってくる。落ちるのは次の更新である。
  void apply({
    required String loanId,
    required String action,
    String? pickupAvailableOn,
    String? pickupDueOn,
    String? borrowedOn,
    String? dueOn,
  }) {
    if (state.busyLoanId != null) return;
    final composition = ref.read(compositionProvider);
    state = state.copy(busyLoanId: loanId, message: '');
    try {
      composition.updateLoan(
        loanId: loanId,
        action: action,
        pickupAvailableOn: pickupAvailableOn,
        pickupDueOn: pickupDueOn,
        borrowedOn: borrowedOn,
        dueOn: dueOn,
      );
    } on Object catch (error) {
      _fail(loanId, error);
      return;
    }
    _adopt(
      loanId,
      offList: loanActions[action]?.to,
      message: (fresh) => lendingAppliedMessage(
        fresh?.title ?? state.rows[loanId]?.title ?? 'この本',
        fresh?.status ?? loanActions[action]?.to ?? '',
      ),
    );
  }

  /// 行1件の受取館を選び直す。**常用館は動かさない**（`lending.md` §4）。
  void changePickupLibrary({
    required String loanId,
    required String systemId,
    required String branchId,
  }) {
    if (state.busyLoanId != null) return;
    final composition = ref.read(compositionProvider);
    state = state.copy(busyLoanId: loanId, message: '');
    try {
      composition.changeLoanPickupLibrary(
        loanId: loanId,
        systemId: systemId,
        branchId: branchId,
      );
    } on Object catch (error) {
      _fail(loanId, error);
      return;
    }
    _adopt(
      loanId,
      message: (fresh) =>
          '受取館を${fresh == null ? '' : pickupLibraryLabel(fresh)}にしました。',
    );
  }

  /// 館サイトを開く。**開いた事実だけでは状態を変えない**（`lending.md` §4）。
  Future<void> openSite(String systemId) async {
    final composition = ref.read(compositionProvider);
    try {
      await composition.openLendingSite(systemId);
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = state.copy(message: lendingIssueMessage(lendingIssueCode(error)));
    }
  }

  /// 選んだ行をまとめて取消済みにする。**[apply] を件数ぶん繰り返さない。**
  ///
  /// [_adopt] は書込みのたびに台帳を全件読む（`effective` と `parallelSystemIds` が他の Loan
  /// を見なければ決まらないため）。20件選べば20回の全件読みになるので、**全部書いてから
  /// 1回だけ読み直す。**
  ///
  /// **触った行だけを差し替える。** 重複を1件消すと残った側の `effective` も変わるが、
  /// 読み直した結果を一覧全体へは配らない — 利用者が触っていない行が書き換わるのは、この画面
  /// が避けているもの（`↻ 更新` まで動かさない）そのものである。残りは次の更新で揃う。
  ///
  /// **確認は置かない。** 終端にした行は位置に残り、4つのボタンで押し直せる（段階3 の
  /// 差し替えで受け入れた形）。後戻りできなくなる境目は取消ではなく `↻ 更新` である。
  void cancelSelected(Set<String> loanIds) {
    // **表示順で書く。** 途中で失敗しても、どこまで進んだかが画面の並びと一致する。
    final targets = [
      for (final loanId in state.order)
        if (loanIds.contains(loanId) && !state.leaving.containsKey(loanId))
          loanId,
    ];
    if (targets.isEmpty || state.busyLoanId != null) return;
    final composition = ref.read(compositionProvider);
    final done = <String>[];
    var failed = 0;
    for (final loanId in targets) {
      try {
        composition.updateLoan(loanId: loanId, action: 'cancel');
        done.add(loanId);
      } on Object catch (_) {
        failed++;
      }
    }
    if (!ref.mounted) return;
    if (done.isEmpty) {
      state = state.copy(message: lendingCancelledMessage(0, failed));
      return;
    }
    final fresh = {
      for (final item in composition.loadActiveLoans(
        asOf: state.asOf.isEmpty ? null : state.asOf,
      ))
        item.loanId: item,
    };
    final rows = {...state.rows};
    final leaving = {...state.leaving};
    for (final loanId in done) {
      final item = fresh[loanId];
      if (item == null) {
        leaving[loanId] = 'cancelled';
      } else {
        // 読み口がまだ返すなら終端になっていない。**そのときは行を残す。**
        rows[loanId] = item;
        leaving.remove(loanId);
      }
    }
    state = state.copy(
      rows: Map.unmodifiable(rows),
      leaving: Map.unmodifiable(leaving),
      message: lendingCancelledMessage(done.length, failed),
    );
  }

  /// この区へ1冊足す。**台帳に在る書誌を予約中として記録する。**
  ///
  /// **業務の口は予約画面と同じ `saveReservation` である**（`lending.md` §5 が定める形）。
  /// 受取館は常用館から決まり、**選ばせない** — §5 の「`予約` では館を選ばせない」をこの
  /// 入口でも守る。違う館へ行くなら、足した行の受取館リンクから直す（§4）。
  ///
  /// **新しい書誌はここから入らない。** 外へ問い合わせる書誌検索はこの画面が扱わないもので
  /// ある（§6）。候補は [lendingAddCandidatesProvider] が台帳から出す。
  ///
  /// **並びは組み直さない。** 足した行は予約中の枠の末尾へ付き、次の `↻ 更新` で本来の位置
  /// へ入る。
  void addBook({required String systemId, required ReservationBook book}) {
    if (state.unread) return refresh();
    final composition = ref.read(compositionProvider);
    try {
      composition.saveReservation(
        book: book,
        operationId: composition.newReservationId(),
        systems: [systemId],
        wanted: false,
      );
    } on Object catch (error) {
      state = state.copy(
        message: lendingAddIssueMessage(lendingIssueCode(error)),
      );
      return;
    }
    if (!ref.mounted) return;
    // **立った Loan の id を画面で組み立てない。** `deterministicId(entityLoan, …)` は業務層
    // の持ち物で、写すと id の作り方が2箇所になる。読み直して、この区でまだ持っていない行を
    // 拾う。
    final added = [
      for (final item in composition.loadActiveLoans(
        asOf: state.asOf.isEmpty ? null : state.asOf,
      ))
        if (item.systemId == systemId && !state.rows.containsKey(item.loanId))
          item,
    ];
    state = state.copy(
      order: List.unmodifiable([
        ...state.order,
        for (final item in added) item.loanId,
      ]),
      rows: Map.unmodifiable({
        ...state.rows,
        for (final item in added) item.loanId: item,
      }),
      section: Map.unmodifiable({
        ...state.section,
        for (final item in added) item.loanId: LendingSection.reserved,
      }),
      message: lendingAddedMessage(book.title),
    );
  }

  /// 書込みの後に、その行だけを読み直して差し替える。
  ///
  /// **並びと枠は触らない。** 読み口が返さなければ [offList] の状態を [LendingState.leaving]
  /// へ記録し、返れば逆にそこから外す — 返却済みにした行を貸出中へ戻すと一覧へ帰ってくる。
  void _adopt(
    String loanId, {
    String? offList,
    required String Function(LoanReportItem? fresh) message,
  }) {
    if (!ref.mounted) return;
    final composition = ref.read(compositionProvider);
    final fresh = composition.loadActiveLoans(
      asOf: state.asOf.isEmpty ? null : state.asOf,
      loanId: loanId,
    );
    if (fresh.isEmpty) {
      state = state.copy(
        leaving: Map.unmodifiable({
          ...state.leaving,
          loanId: offList ?? 'returned',
        }),
        clearBusy: true,
        message: message(null),
      );
      return;
    }
    state = state.copy(
      rows: Map.unmodifiable({...state.rows, loanId: fresh.single}),
      leaving: Map.unmodifiable({...state.leaving}..remove(loanId)),
      clearBusy: true,
      message: message(fresh.single),
    );
  }

  void _fail(String loanId, Object error) {
    if (!ref.mounted) return;
    state = state.copy(
      clearBusy: true,
      message: lendingIssueMessage(lendingIssueCode(error)),
    );
  }
}

/// 詳細で選び直せる分館。**その図書館システムの分だけである。**
///
/// **台帳から消えたシステムでは空になる。** そのとき受取館のリンクは押せない — 選び直す先が
/// 無く、合成層も `pickup-library-unknown` で止める。
@riverpod
List<Branch> lendingBranches(Ref ref, String systemId) => List.unmodifiable(
  ref.watch(libraryProvider(systemId))?.branches ?? const [],
);

/// 追加の候補。**台帳に在る書誌のうち、この区でまだ生きた記録を持たないもの。**
///
/// **キーワードによる書誌検索ではない**（`lending.md` §6）。外へは一切問い合わせず、既に
/// アプリが持っている書誌を出すだけである。モックの追加ダイアログが絞っているのも、
/// 同じくローカルの `catalog` から `registeredBookIds` を除いたものである。新しい書誌は
/// 予約画面から入る（§5）。
///
/// **除外は一覧が持っている行から決める。** ここで台帳へ問い直すと、この画面が「読み直す
/// 契機は2つだけ」と決めたものの外に3つ目ができる。台帳の側の判断は `saveReservation` が
/// `active-wip` で下すので、取りこぼしても二重には登録されない。
@riverpod
List<ReservationBook> lendingAddCandidates(Ref ref, String systemId) {
  final taken = {
    for (final item in ref.watch(lendingProvider).active)
      if (item.systemId == systemId) item.bookId,
  };
  return List.unmodifiable([
    for (final book in ref.watch(compositionProvider).loadReservationBooks())
      if (!taken.contains(book.id)) book,
  ]);
}

/// 候補の絞り込み。**書名・著者・ISBN を1本の文字列として見る**（モックの `book-query`）。
///
/// **全角・半角の正規化はしない。** `dart:core` に NFKC が無く、1つの入力欄のために
/// 依存を増やす理由が無い。空白で区切った語は AND で当てる。
bool matchesAddQuery(ReservationBook book, String query) {
  final haystack = [
    book.title,
    ...book.authors,
    book.isbn13 ?? '',
  ].join(' ').toLowerCase();
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((word) => word.isEmpty);
  return words.every(haystack.contains);
}
