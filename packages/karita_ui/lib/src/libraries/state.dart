/// 図書館の基本ステートと、図書館管理の画面状態。
///
/// 読む先は合成層（`karita_app`）の窓口だけで、台帳の接続も同期 Engine も触らない
/// （`非公開資料:ui-state-model.md` §3）。**`LibrarySettings` も `LibrarySystems` も
/// ここでは組まない** — 合成層が公開した口だけを使う（§3.1）。
///
/// **全件読んで ID を鍵にした不変の Map を共有し、詳細はそこから1件を取り出す**（§2）。
/// 全体で1つの「現在の図書館」を持たない — 別画面の選択で詳細が切り替わる。詳細の参照先は
/// ルート／操作単位が `systemId` で持つ。
///
/// **台帳を読む Provider は全部 [ledgerRevisionProvider] を見る。** 購読を1本に束ねるので、
/// 1回の通知で一覧・詳細・常用館・マイページが**同じ読込単位として**揃う（§2「同じ読込単位の
/// 結果をまとめて公開する」）。
library;

import 'dart:async';

import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../composition.dart';
import '../shell/navigation.dart';

part 'state.g.dart';

/// 台帳が変わったかもしれない回数。**購読はこの1本だけである。**
///
/// 発火するのは合成層の `statusChanges` — 業務を書いた直後（`syncAfterDomainWrite`）、同期 run
/// が業務データを書いたとき（適用・競合・自動解決）と失敗時、前面復帰、診断の完了である
/// （§2「更新の共通契約」）。**同期が失敗しても、それまでのコミットは残る**ので、失敗の通知でも
/// 読み直す。**何も無い同期 run では打たない**（2026-10-08。同期の状態だけが変わった通知は
/// `syncStatusChanges` に分けた）。
///
/// **`void` の Stream を watch する形にしない。** `AsyncData<void>(null)` は前回と等しく、
/// **依存側が再計算されない。** 単調増加の `int` なら必ず違う値になる。
///
/// **`keepAlive` にする。** 誰も見ていない一瞬に捨てると購読が切れ、その間の変更を落とす。
@Riverpod(keepAlive: true)
class LedgerRevision extends _$LedgerRevision {
  @override
  int build() {
    final composition = ref.watch(compositionProvider);
    final subscription = composition.statusChanges.listen(
      (_) => state = state + 1,
    );
    ref.onDispose(() => unawaited(subscription.cancel()));
    return 0;
  }
}

/// 台帳の接続。**復元で `Db` が入れ替わったときだけ別の値になる。**
///
/// 画面の保持（貸出しの詳細・予約の下書き・図書館管理の位置・本棚の編集中入力）を捨てる
/// 契機である。**`compositionProvider` を見るだけでは足りない** — 復元では `Composition` が
/// 替わらない（`非公開資料:production-wiring-auth-backup-sync.md`「復元後の再接続」）。
///
/// [ledgerRevisionProvider] の通知ごとに読み直すが、**値は同じ token なので依存側は
/// 再計算されない。** 替わるのは接続が替わったときだけである。
@Riverpod(keepAlive: true)
Object ledgerSession(Ref ref) {
  ref.watch(ledgerRevisionProvider);
  return ref.watch(compositionProvider).ledgerSessionToken;
}

/// 登録済みの図書館システム。**`systemId` を鍵にした挿入順の Map。**
///
/// 並びは台帳の `ORDER BY system_id, id` のままである。**表示の並び順・絞り込みはここで
/// 決めない** — 別の表示条件として扱う（§2）。一覧が使うのは [libraryListProvider] である。
///
/// 一覧は `.values`、詳細は `[systemId]`。**削除済み（tombstone）は入らない。**
///
/// **読込失敗は `AppIssue` として投げる。** 空の Map（未登録）へ潰さない（§2）。包むのは
/// 合成層で、生の例外は配らない。
///
/// **自動破棄しない**（§3）。基本コレクションはタブより上の共通スコープで共有し、利用開始後は
/// セッション内で保持する。タブを移るたびに捨てると、戻るたびに全件読み直すことになる。
@Riverpod(keepAlive: true)
Map<String, LibrarySystem> libraries(Ref ref) {
  ref.watch(ledgerRevisionProvider);
  final systems = ref.watch(compositionProvider).loadLibraries();
  return Map.unmodifiable({for (final system in systems) system.id: system});
}

/// 図書館システム1件。**コレクションから取り出すだけである。**
///
/// **未登録と読込失敗を分ける必要がある**（§4 段階1）。ここが返す `null` は「その
/// `systemId` は登録されていない」であって、失敗ではない — 台帳が読めなければ
/// [libraries] が投げる。
///
/// **利用停止・削除した館も、既存 Loan の表示では参照できる必要がある。** 台帳から
/// 消えた館はここでは `null` になるので、Loan 側の表示はその `null` に耐える
/// （`loan_reporting.dart` の `configured` と同じ扱い）。
///
/// **詳細は自動破棄する**（§3）。`family` の鍵は `systemId` — 文字列なので等価比較は安定して
/// いる。誰も見ていない館の分を抱え続けない。
///
/// **関数名が `library` なのは意図である。** 生成される Provider の名前は関数名で決まり、
/// 設計が呼んでいるのは `libraryProvider` である。`library` は予約語ではなく組み込み識別子で、
/// 関数名には使える（型名には使えない）。
@riverpod
LibrarySystem? library(Ref ref, String systemId) =>
    ref.watch(librariesProvider)[systemId];

/// 一覧に出す並び。**都道府県 → 名称 → id。**
///
/// **台帳の `system_id` 順を使わない。** あれはカーリルの識別子のローマ字順
/// （`Tokyo_Edogawa`, `Tokyo_Katsushika`, …）で、利用者が見ている名前と関係が無い。
///
/// **絞込みは持たない**（2026-09-17 決定）。登録数は利用者の生活圏ぶんで、検索欄を置いても
/// 効果を測れず、次の単位の追加画面が持つ検索と操作が二重になる。
///
/// `id` まで見るのは、同名の図書館システムが2件あったときに並びを決めきるためである。
@riverpod
List<LibrarySystem> libraryList(Ref ref) {
  final systems = ref.watch(librariesProvider).values.toList()
    ..sort(compareLibrarySystems);
  return List.unmodifiable(systems);
}

/// 一覧の並び順。**純関数なので画面を立てずに固定できる。**
int compareLibrarySystems(LibrarySystem a, LibrarySystem b) {
  final pref = a.pref.compareTo(b.pref);
  if (pref != 0) return pref;
  final name = a.name.compareTo(b.name);
  if (name != 0) return name;
  return a.id.compareTo(b.id);
}

/// 常用館1件。**未設定・解決済み・参照切れの3つに分かれる。**
///
/// **`LibrarySystem` には入っていない。** 常用館は `LibrarySetting` の別集約で（`0011`）、
/// [libraries] を読み直しても拾えない。だからこちらも [ledgerRevisionProvider] を見る。
@riverpod
PreferredBranch preferredBranch(Ref ref, String systemId) {
  ref.watch(ledgerRevisionProvider);
  return ref.watch(compositionProvider).preferredBranchFor(systemId);
}

/// 出典つきで解決したマイページ URL。**順序を画面で書き直さない**（§3.1）。
///
/// `取り込み値` → `既定値` → `公式サイト` → `未設定` の順は `karita_domain` の純関数が持つ。
@riverpod
MypageUrl mypageUrl(Ref ref, String systemId) {
  ref.watch(ledgerRevisionProvider);
  return ref.watch(compositionProvider).mypageUrlFor(systemId);
}

/// 削除で残るものの勘定。**確認ダイアログを開くときだけ読む。**
@riverpod
LibraryRemovalImpact libraryRemovalImpact(Ref ref, String systemId) {
  ref.watch(ledgerRevisionProvider);
  return ref.watch(compositionProvider).removalImpactFor(systemId);
}

/// 図書館管理のどこに居るか。
enum LibrariesScreen {
  /// 閉じている。**設定画面が出る。**
  closed,

  list,
  detail,
  preferredBranch,

  /// 追加の1段目。**都道府県を選ぶ。通信しない**（同梱47件）。
  addPrefecture,

  /// 追加の2段目。**選んだ県で1回だけ引き、絞込みは端末側である。**
  addSearch,

  /// マイページ URL の編集。**主導線は［karita に送る］で、貼り付けは補助である。**
  mypageUrl,
}

/// 画面状態1つ。**選択 ID は `LibrarySystem.id`（カーリルの `systemid`）である。**
///
/// **分館 id（`Branch.id`）と混同しない。** 画面をまたいで運ぶのは systemId だけで、分館は
/// 詳細と常用館画面の中でしか出てこない。
class LibrariesRouteState {
  final LibrariesScreen screen;

  /// 見ている図書館システム。**[LibrariesScreen.closed] と [LibrariesScreen.list] では
  /// `null` である。**
  final String? systemId;

  /// 探している都道府県。**[LibrariesScreen.addSearch] のときだけ在る。**
  ///
  /// **`systemId` と混ぜない。** 片方は集約の識別子、片方はカーリルへ渡す要求のパラメータで、
  /// 寿命も意味も違う。
  final String? pref;

  /// cold start の triage 画面から直接渡す受信 URL。**[LibrariesScreen.mypageUrl] のときだけ
  /// 在りうる。**
  ///
  /// 通常経路（`mypageCandidatesProvider`）はストリームで拾うが、triage 画面で確定した候補は
  /// 既に `.where` で捨てられた後のイベントなのでストリーム再購読では拾えない
  /// （`shell/handoff_triage.dart`）。そのための直接受け渡し経路である。
  final String? prefillUrl;

  const LibrariesRouteState.closed()
    : screen = LibrariesScreen.closed,
      systemId = null,
      pref = null,
      prefillUrl = null;

  const LibrariesRouteState.list()
    : screen = LibrariesScreen.list,
      systemId = null,
      pref = null,
      prefillUrl = null;

  const LibrariesRouteState.detail(String this.systemId)
    : screen = LibrariesScreen.detail,
      pref = null,
      prefillUrl = null;

  const LibrariesRouteState.preferredBranch(String this.systemId)
    : screen = LibrariesScreen.preferredBranch,
      pref = null,
      prefillUrl = null;

  const LibrariesRouteState.mypageUrl(String this.systemId, {this.prefillUrl})
    : screen = LibrariesScreen.mypageUrl,
      pref = null;

  const LibrariesRouteState.addPrefecture()
    : screen = LibrariesScreen.addPrefecture,
      systemId = null,
      pref = null,
      prefillUrl = null;

  const LibrariesRouteState.addSearch(String this.pref)
    : screen = LibrariesScreen.addSearch,
      systemId = null,
      prefillUrl = null;

  bool get isOpen => screen != LibrariesScreen.closed;

  @override
  bool operator ==(Object other) =>
      other is LibrariesRouteState &&
      other.screen == screen &&
      other.systemId == systemId &&
      other.pref == pref &&
      other.prefillUrl == prefillUrl;

  @override
  int get hashCode => Object.hash(screen, systemId, pref, prefillUrl);

  @override
  String toString() =>
      'LibrariesRouteState(${screen.name}, ${systemId ?? pref})';
}

/// 一覧・詳細・常用館の行き来。**Navigator ではなく状態で持つ**（2026-09-17 決定）。
///
/// §5 の3・4 が要求する共有範囲と保持・破棄条件を、そのまま Provider の宣言として書ける。
/// widget 試験からも直接読める。
///
/// **共有範囲はアプリである。** `keepAlive` にするのは、幅で外殻が入れ替わる一瞬に捨てられると
/// 詳細を見ていた利用者が設定画面へ戻されるためである。**タブ切替でも保つ** — 外殻の
/// `IndexedStack` が本文を生かしたままにしているので、設定タブへ戻ると同じ画面が出る。
///
/// **再起動では捨てる。** `device.json` へ書かない（`ui.lastTab` を持たないのと同じ判断）。
/// **セッション交換でも捨てる** — [build] が `compositionProvider` を watch しているので、
/// デモのリセットで先頭（閉じた状態）へ戻る。
@Riverpod(keepAlive: true)
class LibrariesRoute extends _$LibrariesRoute {
  /// 閉じたら戻る先。**別の feature から1画面だけ借りられたときに入る**（2026-09-19）。
  ///
  /// 貸出しの詳細から常用館・マイページ URL を直しに来た利用者は、**図書館管理の一覧では
  /// なく元の区へ帰りたい。** 保存でも取消でも出口は [back] の1本なので、行き先の記憶も
  /// ここ1箇所で足りる。
  ///
  /// **状態（[LibrariesRouteState]）には入れない。** 画面がどこかは行き先の話で、どこから
  /// 来たかは経路の話である。混ぜると、同じ画面が由来ごとに別の状態値を持つことになる。
  ShellTab? _returnTo;

  @override
  LibrariesRouteState build() {
    ref.watch(compositionProvider);
    ref.watch(ledgerSessionProvider);
    return const LibrariesRouteState.closed();
  }

  /// マイページの候補が届いた。**呼ぶのは `PendingHandoffTriage`（`shell/handoff_triage.dart`）
  /// だけである。** ここ自身が `handoffTriage` を購読しないのは、`ledgerSessionProvider` も
  /// 見ているため起動直後の同期状態変化だけで何度も作り直され、購読を張り直す一瞬に
  /// broadcast stream のイベントを取りこぼす実害があったため（2026-09-29 実機で確認）。
  /// 公開しているのは試験のためでもある
  /// （`reservation_test.dart` の `actions.receive(delivery)` と同じ扱い）。
  ///
  /// [url] を `prefillUrl` として直接渡す。**`mypageCandidatesProvider` の再購読に頼らない** —
  /// `handoffTriage` は `MypageUrlScreen` が無い状態からでも届くので、画面が開く前に値を渡す。
  void onMypageCandidate(String systemId, Uri url) {
    openMypageUrl(
      systemId,
      returnTo: ref.read(currentTabProvider),
      prefillUrl: url.toString(),
    );
  }

  void openList() {
    _returnTo = null;
    state = const LibrariesRouteState.list();
  }

  void openDetail(String systemId) {
    _returnTo = null;
    state = LibrariesRouteState.detail(systemId);
  }

  /// [returnTo] を渡すと、この画面を閉じたときにそのタブへ帰る。
  void openPreferredBranch(String systemId, {ShellTab? returnTo}) {
    _returnTo = returnTo;
    state = LibrariesRouteState.preferredBranch(systemId);
  }

  /// [prefillUrl] は cold start の triage 画面が確定した候補を直接渡すためのものである
  /// （`MypageUrlScreen` が initState で読む、通常のストリーム経由の候補とは別経路）。
  void openMypageUrl(
    String systemId, {
    ShellTab? returnTo,
    String? prefillUrl,
  }) {
    _returnTo = returnTo;
    ref.read(currentTabProvider.notifier).select(ShellTab.settings);
    state = LibrariesRouteState.mypageUrl(systemId, prefillUrl: prefillUrl);
  }

  /// [openMypageUrl] の `prefillUrl` を使い終わったら消す。**次にこの画面へ来たとき、古い
  /// 値を再適用しない。**
  void clearPrefillUrl() {
    final current = state;
    if (current.screen == LibrariesScreen.mypageUrl &&
        current.prefillUrl != null) {
      state = LibrariesRouteState.mypageUrl(current.systemId!);
    }
  }

  /// [returnTo] を渡すと、追加を閉じたときにそのタブへ帰る。**予約画面で図書館が1件も無い
  /// ときの導線である**（2026-10-15）— 登録が済んだら、届いた本の予約へ戻りたい。
  void openAdd({ShellTab? returnTo}) {
    _returnTo = returnTo;
    state = const LibrariesRouteState.addPrefecture();
  }

  void openAddSearch(String pref) =>
      state = LibrariesRouteState.addSearch(pref);

  /// 1つ戻る。**戻れたら `true`。**
  ///
  /// `false` を返すのは既に閉じているときだけで、そのとき戻る操作は外殻より外（OS）へ渡る。
  bool back() {
    final current = state;
    if (current.screen == LibrariesScreen.closed) return false;
    // **追加は2段で借りられる。** 候補から戻るのは県の段であって、まだ借り手へは返さない。
    if (current.screen == LibrariesScreen.addSearch && _returnTo != null) {
      state = const LibrariesRouteState.addPrefecture();
      return true;
    }
    // **借りられた1画面は、閉じたら借り手へ返す。** 保存で戻るのも取消で戻るのもここを
    // 通るので、呼び手ごとに後始末を書かなくてよい。
    final origin = _returnTo;
    if (origin != null) {
      _returnTo = null;
      state = const LibrariesRouteState.closed();
      ref.read(currentTabProvider.notifier).select(origin);
      return true;
    }
    state = switch (current.screen) {
      LibrariesScreen.closed => current,
      LibrariesScreen.list => const LibrariesRouteState.closed(),
      LibrariesScreen.detail => const LibrariesRouteState.list(),
      LibrariesScreen.preferredBranch => LibrariesRouteState.detail(
        current.systemId!,
      ),
      LibrariesScreen.addPrefecture => const LibrariesRouteState.list(),
      LibrariesScreen.addSearch => const LibrariesRouteState.addPrefecture(),
      LibrariesScreen.mypageUrl => LibrariesRouteState.detail(
        current.systemId!,
      ),
    };
    return true;
  }

  /// 対象を失った画面から一覧へ落ちる。**他端末の削除を受けたときの明示操作である。**
  void backToList() => state = const LibrariesRouteState.list();
}

/// 進行中の業務操作1つ。**保存中・対象・失敗だけを持つ。**
///
/// 確定したデータは基本コレクションの側にあり、ここには入らない（§2「保存中・保存エラーは
/// 確定済みコレクションとは別に持つ」）。
class LibraryActionState {
  final bool running;

  /// 何に対する操作か。**失敗を出す行を決めるのに要る。**
  final String? systemId;

  final AppIssue? error;

  const LibraryActionState({this.running = false, this.systemId, this.error});

  @override
  bool operator ==(Object other) =>
      other is LibraryActionState &&
      other.running == running &&
      other.systemId == systemId &&
      other.error == error;

  @override
  int get hashCode => Object.hash(running, systemId, error);
}

/// 常用館の保存と解除。**`ThemeSave` と同じ形である**（設定の段の前例）。
///
/// **連打は保存中に止める。** **セッションが交換されたら古い操作結果を捨てる。**
@Riverpod(keepAlive: true)
class PreferredBranchSave extends _$PreferredBranchSave {
  @override
  LibraryActionState build() {
    ref.watch(compositionProvider);
    return const LibraryActionState();
  }

  /// `branchId` が `null` なら解除する。
  ///
  /// **設定と解除は合成層でも別の口である。** `null` を渡して解除する形にすると「変更なし」と
  /// 「外す」が同じ値で表される（`LibrarySettings` の宣言）。ここが分けているのは画面から
  /// 選択リストの値をそのまま渡せるようにするためで、**下の口は2本のままである。**
  Future<bool> save(String systemId, String? branchId) =>
      _run(systemId, (composition) async {
        if (branchId == null || branchId.isEmpty) {
          await composition.clearPreferredBranch(systemId);
        } else {
          await composition.savePreferredBranch(systemId, branchId);
        }
      });

  Future<bool> _run(
    String systemId,
    Future<void> Function(Composition composition) body,
  ) async {
    if (state.running) return false;
    final composition = ref.read(compositionProvider);
    state = LibraryActionState(running: true, systemId: systemId);
    AppIssue? error;
    try {
      await body(composition);
    } on AppIssue catch (issue) {
      error = issue;
    } catch (_) {
      error = const AppIssue('library-write', 'The change could not be saved.');
    }
    // **交換された後のセッションへ古い結果を書かない。**
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return false;
    }
    state = LibraryActionState(systemId: systemId, error: error);
    return error == null;
  }
}

/// 図書館システムの削除。**確認の後にだけ呼ばれる。**
@Riverpod(keepAlive: true)
class LibraryRemove extends _$LibraryRemove {
  @override
  LibraryActionState build() {
    ref.watch(compositionProvider);
    return const LibraryActionState();
  }

  Future<bool> remove(String systemId) async {
    if (state.running) return false;
    final composition = ref.read(compositionProvider);
    state = LibraryActionState(running: true, systemId: systemId);
    AppIssue? error;
    try {
      await composition.removeLibrarySystem(systemId);
    } on AppIssue catch (issue) {
      error = issue;
    } catch (_) {
      error = const AppIssue('library-write', 'The change could not be saved.');
    }
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return false;
    }
    state = LibraryActionState(systemId: systemId, error: error);
    return error == null;
  }
}

/// 1つの都道府県の候補。**通信はここ1回だけである。**
///
/// **`family` の鍵は都道府県名。** 同じ県を10箇所が購読しても外へ出る要求は1本である
/// （`非公開資料:ui-state-model.md` §3.1「相乗りを自前で持たない」）。
///
/// **`keepAlive` にする。** 登録作業の途中で県を行き来しても取り直さない — それが
/// `libraryCatalogTtl` の24時間が効く唯一の場面であり、**セッション内で足りる**（§3.1 の
/// 差し戻し）。**DB は作らない。**
///
/// **`maxLibraryPrefectures`（3県）は強制していない。** 打ち切る仕組みが要るうえ、1回の
/// 登録で行き来するのはせいぜい隣接する2〜3県で、セッションも長くない。**段階2 で保持の
/// 置き場を決めるときに一緒に扱う。**
@Riverpod(keepAlive: true)
Future<LibraryCandidates> libraryCandidates(Ref ref, String pref) =>
    ref.watch(compositionProvider).libraryCandidates(pref);

/// Session-local refresh result. Explicit retry invalidates this cache.
@Riverpod(keepAlive: true)
Future<int> branchRefresh(Ref ref, String systemId) {
  ref.watch(ledgerSessionProvider);
  return ref.watch(compositionProvider).refreshLibraryBranches(systemId);
}

/// 図書館の登録。**`PreferredBranchSave` と同じ形である。**
@Riverpod(keepAlive: true)
class LibraryRegister extends _$LibraryRegister {
  @override
  LibraryActionState build() {
    ref.watch(compositionProvider);
    return const LibraryActionState();
  }

  Future<bool> register(LibrarySystemCandidate candidate) async {
    if (state.running) return false;
    final composition = ref.read(compositionProvider);
    state = LibraryActionState(running: true, systemId: candidate.systemId);
    AppIssue? error;
    try {
      await composition.registerLibrary(candidate);
    } on AppIssue catch (issue) {
      error = issue;
    } catch (_) {
      error = const AppIssue('library-write', 'The change could not be saved.');
    }
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return false;
    }
    state = LibraryActionState(systemId: candidate.systemId, error: error);
    return error == null;
  }
}

/// 受信したマイページ URL の候補。**用途で絞った後のものが流れてくる。**
///
/// **合成層が用途を決める**（`handoff.dart` の宣言）。画面は「どの館の候補か」を受け取り、
/// 対象と値を確認して確定する。**共有だけでは保存しない。**
///
/// **`keepAlive` にする。** 画面が立つ前に届いた1件を落とさない — 共有から起動された直後は
/// 受信のほうが早い。
@Riverpod(keepAlive: true)
Stream<MypageCandidate> mypageCandidates(Ref ref) =>
    ref.watch(compositionProvider).mypageCandidates;

/// 編集中のマイページ URL。**欄の文字列から導いたものだけを持つ。**
///
/// **候補の置き場は欄そのものである**（2026-09-18 に改めた）。受信した値も欄へ入るので、
/// 「受け取った値」と「これから保存する値」が2つに分かれない。**取り込み・解除・破棄の
/// ボタンを置かない** — 欄を編集して［保存］か［キャンセル］だけである。
class MypageDraft {
  /// 読めた URL。**空・読めない文字列では `null`。**
  final Uri? url;

  /// 検査の結果。[url] があるときだけ在る。
  final MypageUrlCheck? check;

  /// 欄が空である。**取り込み値があれば、保存で解除になる。**
  final bool empty;

  /// 空ではないが、URL として読めない。
  final bool broken;

  /// 候補の出どころ。**受信のときだけ古さを出す。**
  final MypageDraftSource source;

  /// ブラウザーを開いた時刻。**受信の候補にだけ在る。**
  ///
  /// 一時保持に**期限は置かないと決めてある**（2026-09-12）。代償として、古さを伝える手段は
  /// 表示しかない。
  final DateTime? startedAt;

  final bool saving;
  final AppIssue? error;

  const MypageDraft({
    this.url,
    this.check,
    this.empty = true,
    this.broken = false,
    this.source = MypageDraftSource.none,
    this.startedAt,
    this.saving = false,
    this.error,
  });

  /// 保存してよい値が入っているか。**警告は止めない** — 別ホストは外部 OPAC への正常な
  /// 遷移でも起こる。
  ///
  /// **解除できるかはここで決めない。** それは「いま取り込み値を持っているか」で決まり、
  /// 欄の中身の話ではない（画面が [MypageUrl.source] を見て判断する）。
  bool get savable => !saving && url != null && check!.saveable;
}

/// 候補がどこから来たか。
enum MypageDraftSource {
  none,

  /// ［karita に送る］で届いた。**主導線である。**
  received,

  /// 欄で直に編集した。**貼り付けもここに入る** — OS の貼り付けが効くので、
  /// アプリ側に取り込みボタンを置かない（2026-09-18 に改めた）。
  typed,
}

/// マイページ URL の編集。**欄の文字列を受けて、読めるかと保存してよいかを出す。**
///
/// **`autoDispose` にする。** 画面を閉じたら捨てる — 保存しなかった値を抱え続けない。
/// ただし**受信の候補は合成層の側に残る**ので、開き直せば取り直せる。
@riverpod
class MypageEdit extends _$MypageEdit {
  @override
  MypageDraft build(String systemId) {
    ref.watch(compositionProvider);
    return const MypageDraft();
  }

  /// 欄の中身が変わった。**読めない文字列は保存させない。**
  ///
  /// `checkSaveableUrl` は `Uri` を受け取る純関数で、**文字列の妥当性は入口の仕事である。**
  void setText(String text, MypageDraftSource source, {DateTime? startedAt}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      state = MypageDraft(source: source, startedAt: startedAt);
      return;
    }
    final url = Uri.tryParse(trimmed);
    if (url == null || !url.hasAuthority) {
      state = MypageDraft(
        empty: false,
        broken: true,
        source: source,
        startedAt: startedAt,
      );
      return;
    }
    state = MypageDraft(
      url: url,
      check: ref.read(compositionProvider).checkMypageUrl(systemId, url),
      empty: false,
      source: source,
      startedAt: startedAt,
    );
  }

  /// 確定する。**ここで初めて台帳が変わる。**
  ///
  /// **空で保存すると解除である**（2026-09-18）。取り込み値を消し、既定値表・公式サイトへ
  /// 戻る。専用のボタンを置かないと決めたので、**欄を空にすることが解除の意思表示になる。**
  Future<bool> confirm() async {
    final draft = state;
    if (draft.saving) return false;
    if (!draft.empty && !draft.savable) return false;
    final composition = ref.read(compositionProvider);
    state = MypageDraft(
      url: draft.url,
      check: draft.check,
      empty: draft.empty,
      broken: draft.broken,
      source: draft.source,
      startedAt: draft.startedAt,
      saving: true,
    );
    AppIssue? error;
    try {
      if (draft.empty) {
        await composition.clearMypageUrl(systemId);
      } else {
        await composition.saveMypageUrl(systemId, draft.url!);
      }
    } on AppIssue catch (issue) {
      error = issue;
    } catch (_) {
      error = const AppIssue('library-write', 'The change could not be saved.');
    }
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return false;
    }
    if (error == null) {
      state = const MypageDraft();
      return true;
    }
    state = MypageDraft(
      url: draft.url,
      check: draft.check,
      empty: draft.empty,
      broken: draft.broken,
      source: draft.source,
      startedAt: draft.startedAt,
      error: error,
    );
    return false;
  }
}

/// 図書館サイトを開く操作。**開いた事実で状態を変えない。**
@Riverpod(keepAlive: true)
class LibrarySiteOpen extends _$LibrarySiteOpen {
  @override
  LibraryActionState build() {
    ref.watch(compositionProvider);
    return const LibraryActionState();
  }

  Future<bool> open(String systemId) async {
    if (state.running) return false;
    final composition = ref.read(compositionProvider);
    state = LibraryActionState(running: true, systemId: systemId);
    AppIssue? error;
    try {
      await composition.openLibrarySite(systemId);
    } on AppIssue catch (issue) {
      error = issue;
    } catch (_) {
      error = const AppIssue('browser-open', 'The browser could not open.');
    }
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return false;
    }
    state = LibraryActionState(systemId: systemId, error: error);
    return error == null;
  }
}
