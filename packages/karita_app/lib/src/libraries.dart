/// 図書館管理の画面へ公開する値と操作。**業務の型をそのまま配る箇所と、写す箇所を分ける。**
///
/// `LibrarySystem` と `MypageUrl` は `karita_domain` の型のまま渡す。画面はもともと
/// `karita_domain` を import してよい側で（`karita_ui` の pubspec）、写しを作ると
/// **同じものが2つの名前を持つ。** 写すのは**この層でしか組めないもの**だけである —
/// 常用館の解決（設定 ＋ カタログの2集約をまたぐ）と、削除で残るものの勘定がそれにあたる。
///
/// **`LibrarySettings` と `LibrarySystems` を画面へ渡さない。** 渡すと画面が集約の境界と
/// トランザクションの単位を知ることになり、`非公開資料:ui-state-model.md` §3.1 の
/// 「合成層は必要な値と操作だけを公開する」が崩れる。
///
/// **例外は `AppIssue` に写す。** 生の例外を配らないのは設定の段で決めた前例である
/// （`settings_adapter.dart`）。SQLite の例外は SQL 文とファイルパスを含みうるので、
/// **`toString()` を配らず型名だけにする。**
library;

import 'package:karita_domain/karita_domain.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';

import 'handoff.dart';
import 'settings.dart';

/// 画面が要る分だけを通す。**`karita_ui` の pubspec を増やさない。**
///
/// 候補の型は合成層の口（`Composition.libraryCandidates`）の戻り値に出るので、画面はどのみち
/// 知ることになる。**面を数え上げて通すほうが、依存を1つ足すより狭い。**
///
/// [filterSystems] を画面が呼ぶのは正しい — **絞込みと順位付けは応答の読み方であって画面の
/// 都合ではなく、だからクライアントに在る**（`非公開資料:ui-state-model.md` §3.1）。
/// 画面がやり直すと、規則が2つになる。
export 'package:karita_handoff/karita_handoff.dart'
    show UrlSaveCheck, UrlSaveIssue;
export 'package:karita_public_api_client/karita_public_api_client.dart'
    show BranchCandidate, LibrarySystemCandidate, filterSystems, prefectures;

/// 1つの都道府県で取れた候補。**切り詰めを一緒に運ぶ。**
///
/// **黙って欠けさせない。** 欠けたまま出すと、探している館が「無い」のか「載っていない」のか
/// 区別できない（`非公開資料:external-data-access.md`）。
class LibraryCandidates {
  final List<LibrarySystemCandidate> systems;

  /// `limit` に当たった。**利用者に見せる。**
  final bool truncated;

  const LibraryCandidates({required this.systems, this.truncated = false});
}

/// 常用館がどうなっているか。**3つある。**
enum PreferredBranchState {
  /// 設定していない。**既定値表が無いので、これが初期状態である**
  /// （`非公開資料:settings-and-parameters.md` の一覧）。
  unset,

  /// 設定してあり、分館一覧にも在る。
  resolved,

  /// 設定してあるが、分館一覧に無い。**「まだ届いていない」と「分館が消えた」を区別しない**
  /// （`LibrarySettings.danglingPreferredBranches` と同じ判断）。
  dangling,
}

/// 解決した常用館1件。
///
/// **`LibrarySettings.danglingPreferredBranches()` を `systemId` で絞る口はこれが兼ねる**
/// （`非公開資料:ui-state-model.md` §4 段階1 で決めた口）。全件を返す `doctor` 向けの
/// ものとは用途が違い、画面が要るのは「いま見ている1件がどの状態か」である。
class PreferredBranch {
  final PreferredBranchState state;

  /// 保存してある分館 id。**未設定のときだけ `null`。**
  ///
  /// `calilLibkey` ではない。`loans.pickup_library_id` と同じ識別子空間である。
  final String? branchId;

  /// 分館の名前。**[PreferredBranchState.resolved] のときだけ在る** — 参照が切れていれば
  /// 引く先が無い。
  final String? branchName;

  const PreferredBranch.unset()
    : state = PreferredBranchState.unset,
      branchId = null,
      branchName = null;

  const PreferredBranch.resolved(String this.branchId, String this.branchName)
    : state = PreferredBranchState.resolved;

  const PreferredBranch.dangling(String this.branchId)
    : state = PreferredBranchState.dangling,
      branchName = null;

  @override
  bool operator ==(Object other) =>
      other is PreferredBranch &&
      other.state == state &&
      other.branchId == branchId &&
      other.branchName == branchName;

  @override
  int get hashCode => Object.hash(state, branchId, branchName);

  @override
  String toString() => 'PreferredBranch(${state.name}, $branchId)';
}

/// 図書館システムを消したときに残るもの。**削除確認に出す数字だけである。**
///
/// **残骸は許容すると決めてある**（`非公開資料:ui-state-model.md`「削除で残るもの」）。
/// 台帳は既に耐えており（`loan_reporting.dart` の `configured`）、整理すべきは「何が残り、
/// それを利用者へどう見せるか」だけである。
class LibraryRemovalImpact {
  /// その館を参照する棚卸記録の件数。**削除しても消えない**（`Memberships.remove` が無い）。
  final int memberships;

  /// その館で始めた Loan の件数。**履歴も含む。** 消さず、館名だけが出なくなる。
  final int loans;

  /// 常用館の設定行が在るか。**参照先を失う。**
  final bool hasPreferredBranch;

  /// マイページ URL の取り込み値が在るか。**同じく参照先を失う。**
  ///
  /// 既定値・公式サイトは台帳の行ではないので数えない — 消えるのは利用者が保存した値だけである。
  final bool hasMypageUrl;

  const LibraryRemovalImpact({
    required this.memberships,
    required this.loans,
    required this.hasPreferredBranch,
    required this.hasMypageUrl,
  });

  @override
  bool operator ==(Object other) =>
      other is LibraryRemovalImpact &&
      other.memberships == memberships &&
      other.loans == loans &&
      other.hasPreferredBranch == hasPreferredBranch &&
      other.hasMypageUrl == hasMypageUrl;

  @override
  int get hashCode =>
      Object.hash(memberships, loans, hasPreferredBranch, hasMypageUrl);

  @override
  String toString() =>
      'LibraryRemovalImpact(memberships: $memberships, loans: $loans)';
}

/// 登録済みの図書館システムを読む。**失敗は [AppIssue] になる。**
///
/// **読込失敗を「0件」に変換しない**（`非公開資料:ui-state-model.md` §2）。空の正常結果は
/// 「まだ1つも登録していない端末」であり、読めなかったこととは別である。
List<LibrarySystem> readLibrarySystems(DomainContext domain) {
  try {
    return LibrarySystems(domain).load().librarySystems;
  } catch (error) {
    // **`toString()` を配らない。** SQLite の例外は SQL 文と DB のパスを含みうる。
    throw AppIssue(
      'libraries-load',
      'Library systems could not be read (${error.runtimeType}).',
    );
  }
}

/// 常用館1件を解決する。**設定とカタログの2集約をまたぐ。**
PreferredBranch readPreferredBranch(DomainContext domain, String systemId) {
  final String? branchId;
  final LibrarySystem? system;
  try {
    branchId = LibrarySettings(
      domain,
    ).valueOf(systemId, settingPreferredBranch);
    system = LibrarySystems(domain).read(systemId);
  } catch (error) {
    throw AppIssue(
      'library-setting-load',
      'Library settings could not be read (${error.runtimeType}).',
    );
  }
  if (branchId == null || branchId.isEmpty) {
    return const PreferredBranch.unset();
  }
  for (final branch in system?.branches ?? const <Branch>[]) {
    if (branch.id == branchId) {
      return PreferredBranch.resolved(branchId, branch.name);
    }
  }
  // **システムごと消えた場合もここに入る。** 参照先が今は無い、という点で同じである。
  return PreferredBranch.dangling(branchId);
}

/// 削除で残るものを数える。**消さずに数えるだけである。**
LibraryRemovalImpact readRemovalImpact(DomainContext domain, String systemId) {
  try {
    final systems = LibrarySystems(domain);
    final settings = LibrarySettings(domain);
    return LibraryRemovalImpact(
      memberships: systems.referencingMemberships(systemId),
      loans: systems.referencingLoans(systemId),
      hasPreferredBranch:
          settings.read(systemId, settingPreferredBranch) != null,
      hasMypageUrl: settings.read(systemId, settingMypageUrl) != null,
    );
  } catch (error) {
    throw AppIssue(
      'library-impact-load',
      'Library references could not be counted (${error.runtimeType}).',
    );
  }
}

/// 業務の書込みを1本包む。**業務の失敗と、それ以外を分ける。**
///
/// [DomainError] の `code` は言語間で共有する契約の文字列で（`errors.dart`）、message は
/// 「常用館 X は図書館システム Y の分館にありません。」のように**何をすればよいかが読める。**
/// どちらも秘密を含まないのでそのまま渡す。
///
/// **それ以外は型名だけにする。** 台帳の書込みで落ちたときの例外はパスや SQL を含みうる。
T runLibraryWrite<T>(T Function() body) {
  try {
    return body();
  } on AppIssue {
    rethrow;
  } on DomainError catch (error) {
    throw AppIssue(error.code, error.message);
  } catch (error) {
    throw AppIssue(
      'library-write',
      'The change could not be saved (${error.runtimeType}).',
    );
  }
}

/// 候補1件を、台帳へ書く形の集約に直す。**純関数である。**
///
/// **`opacSearchUrlTemplate` を候補から持ってこない。** カーリルはその値を返さず、利用者が
/// 手で入れる値である（`prepareRegistration` が登録済みの側を優先して運ぶ）。
LibrarySystem librarySystemOf(LibrarySystemCandidate candidate) =>
    LibrarySystem(
      id: candidate.systemId,
      pref: candidate.pref,
      city: candidate.city,
      // **カーリルの `systemname` をそのまま採る**（2026-09-16 決定）。「東京都江東区」であって
      // 「江東区立図書館」ではない。
      name: candidate.systemName,
      branches: [
        for (final branch in candidate.branches)
          Branch(id: branch.id, calilLibkey: branch.libkey, name: branch.name),
      ],
      homepageUrl: candidate.homepageUrl,
    );

/// 候補を、いまの台帳に対して**書こうとしている値**へ整える。
///
/// **比べる相手はこれである。** 生の候補と台帳を比べると、`homepageUrl` を手で直した端末では
/// 毎回「違う」になる — `prepareRegistration` が登録済みの側を優先して運ぶためである
/// （`非公開資料:ui-state-model.md`「差分があるときだけ書く」）。
///
/// 整えられなければ `null`。**分館が0件・市区町村が空の候補は書けない**（集約の不変条件）。
LibrarySystem? prepareCandidate(
  LibrariesConfig current,
  LibrarySystemCandidate candidate,
) {
  try {
    return prepareRegistration(
      current,
      pref: candidate.pref,
      city: candidate.city,
      selectedSystems: [librarySystemOf(candidate)],
    ).single;
  } on DomainError {
    return null;
  }
}

/// マイページ URL の候補1件。**保存までは候補である。**
///
/// **共有元がその起動操作に対応している保証はない**ので、起動情報（[LaunchContext]）は
/// 候補を組む手がかりであって証明ではない
/// （`../karita-ui-probe/docs/browser-handoff.md` §3）。画面が対象と値を確認して確定する。
class MypageCandidate {
  /// 候補の宛先。**起動情報が指していたシステムである。**
  final String systemId;

  final Uri url;

  /// ブラウザーを開いた時刻。**候補の古さを画面に出すために運ぶ。**
  ///
  /// 一時保持に**期限は置かないと決めてある**（2026-09-12）。代償として、古さを伝える手段は
  /// 表示しかない。
  final DateTime startedAt;

  const MypageCandidate({
    required this.systemId,
    required this.url,
    required this.startedAt,
  });

  @override
  String toString() => 'MypageCandidate($systemId, ${url.host})';
}

/// 届いた1件を、マイページ URL の候補にするか決める。**純関数である。**
///
/// **用途は URL からは決まらない。** 書籍 URL だけが URL 単体で判定でき、残り2つはどちらも
/// 「館サイトの一般 URL」で区別がつかない。手がかりは起動情報だけで、**それは候補であって
/// 証明ではない**（`../karita-ui-probe/docs/browser-handoff.md` §3）。
///
/// `null` を返すのは4つ — 書籍・Notice・起動情報が無い・起動情報が貸出しの用途。
/// **どれも「この画面の候補ではない」であって、捨ててよいという意味ではない**（書籍の行き先は
/// 予約＝段階2、Notice は別タスクの Activity である）。
MypageCandidate? mypageCandidateOf(Handoff delivery, LaunchContext? launch) {
  if (delivery is! HandoffWebUrl) return null;
  if (launch == null || launch.purpose != LaunchPurpose.mypageUrl) return null;
  return MypageCandidate(
    systemId: launch.systemId,
    url: delivery.url,
    startedAt: launch.startedAt,
  );
}

/// 貸出しへ戻る候補1件。**URL は持たない** — 貸出しの往復は URL を保存しない
/// （`../karita-ui-probe/docs/browser-handoff.md` §5「対象地区の貸出しへ／URL 保存なし」）。
class LendingCandidate {
  /// 候補の宛先。**起動情報が指していたシステムである。**
  final String systemId;

  /// ブラウザーを開いた時刻。**候補の古さを画面に出すために運ぶ。**
  final DateTime startedAt;

  const LendingCandidate({required this.systemId, required this.startedAt});

  @override
  bool operator ==(Object other) =>
      other is LendingCandidate &&
      other.systemId == systemId &&
      other.startedAt == startedAt;

  @override
  int get hashCode => Object.hash(systemId, startedAt);

  @override
  String toString() => 'LendingCandidate($systemId)';
}

/// 届いた1件を、貸出しへ戻る候補にするか決める。**`mypageCandidateOf` と対称な純関数。**
LendingCandidate? lendingCandidateOf(Handoff delivery, LaunchContext? launch) {
  if (delivery is! HandoffWebUrl) return null;
  if (launch == null || launch.purpose != LaunchPurpose.lending) return null;
  return LendingCandidate(
    systemId: launch.systemId,
    startedAt: launch.startedAt,
  );
}

/// 保存してよいかの検査結果と、比べた相手。
///
/// **検査そのものは `karita_handoff` の純関数である**（`checkSaveableUrl`）。ここが足すのは
/// 「何と比べたか」だけで、画面はホスト名を並べて確認を促せる。
class MypageUrlCheck {
  final UrlSaveCheck check;

  /// 比べた相手の URL。**既定値または公式サイト。** 無ければ `null`（＝確認できない）。
  final Uri? comparedTo;

  const MypageUrlCheck(this.check, this.comparedTo);

  bool get saveable => check.saveable;
  Set<UrlSaveIssue> get issues => check.issues;
}
