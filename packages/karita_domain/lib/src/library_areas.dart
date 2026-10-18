/// 管理区設定の純粋なモデルと不変条件。
///
/// 移送元: book-sync-model の `src/bops_domain/library_areas.py`。
library;

import 'errors.dart';

class Branch {
  final String id;
  final String calilLibkey;
  final String name;

  const Branch({
    required this.id,
    required this.calilLibkey,
    required this.name,
  });

  @override
  bool operator ==(Object other) =>
      other is Branch &&
      other.id == id &&
      other.calilLibkey == calilLibkey &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, calilLibkey, name);

  @override
  String toString() => 'Branch($id, $name)';
}

/// 図書館システム1件。**これが同期集約の単位である。**
///
/// `entityId` は `uuid5(namespace, id)` で導き、分館は payload の `branches` 配列として同じ
/// 集約に入る。**別集約にしない** — システムと分館が別々に競合して別々に LWW され、設定全体の
/// 洗い替えという粒度が変わる。
///
/// **版・更新時刻・更新端末を持たない。** それらは封筒と `library_systems` の集約行が持つ。
class LibrarySystem {
  final String id;
  final String pref;
  final String city;
  final String name;
  final List<Branch> branches;
  final String? opacSearchUrlTemplate;

  /// 巡回時に開く図書館システムの公式サイト。手入力で上書きできる。
  final String? homepageUrl;

  /// **常用館とマイページ URL はここに無い**（`0011`）。カタログはカーリル由来で再登録のたびに
  /// 洗い替えるが、利用者値は洗い替えの対象ではない。同じ集約に置くと、二端末が別々に変えた
  /// ときに LWW が payload 全体を差し替えて片方が消える。`LibrarySetting` の行として持つ
  /// （`非公開資料:libraries-in-sqlite.md` 2c）。
  const LibrarySystem({
    required this.id,
    required this.pref,
    required this.city,
    required this.name,
    required this.branches,
    this.opacSearchUrlTemplate,
    this.homepageUrl,
  });

  LibrarySystem copyWith({
    String? pref,
    String? city,
    String? name,
    List<Branch>? branches,
    String? opacSearchUrlTemplate,
    String? homepageUrl,
  }) =>
      LibrarySystem(
        id: id,
        pref: pref ?? this.pref,
        city: city ?? this.city,
        name: name ?? this.name,
        branches: branches ?? this.branches,
        opacSearchUrlTemplate:
            opacSearchUrlTemplate ?? this.opacSearchUrlTemplate,
        homepageUrl: homepageUrl ?? this.homepageUrl,
      );

  /// 分館が在るか。**常用館の設定経路が使う。**
  bool hasBranch(String branchId) =>
      branches.any((branch) => branch.id == branchId);

  /// 1集約分の不変条件。
  ///
  /// **同期層はこれを見ない。** payload スキーマは `required` を持てず、集約表も payload 由来の
  /// 列に NOT NULL を置けない — tombstone の payload は最小限でよいためである。したがって
  /// 「必ず埋まっている」を担保するのは**登録経路**であり、その担保がここにある。
  void validate() {
    if (id.isEmpty || pref.isEmpty || city.isEmpty || name.isEmpty) {
      throw DomainError('図書館システムにはID、都道府県、市区町村、名称が必要です。',
          code: 'library-system');
    }
    if (branches.isEmpty) {
      throw DomainError('図書館システム $id には少なくとも一つの分館が必要です。',
          code: 'library-system');
    }
    if ({for (final branch in branches) branch.id}.length != branches.length) {
      throw DomainError('図書館システム $id に分館IDの重複があります。',
          code: 'library-system');
    }
    // **常用館の検査はここに無い**（`0011`）。値が別集約へ出たので、「指定されたら分館に
    // 在ること」を見るのは設定の登録経路（`LibrarySettings.setPreferredBranch`）である。
    //
    // **これが効くのは登録経路だけである**のは変わらない。同期で届いた集約行はどちらの検査も
    // 通らない。分館を1件消した端末と常用館を設定した端末が独立に書けば、参照の切れた常用館は
    // 正常に適用されうる。報告するのは `doctor` の側である。
  }

  /// **値として比べる。** [Branch] も [LibrarySetting] も持っているのに、これだけが無かった。
  ///
  /// 効くのは UI の再読込である。台帳の変更通知（同期の開始・終了、前面復帰、診断の完了）の
  /// たびに `load()` がやり直されるので、**等価性が無いと中身が同じでも必ず別インスタンスに
  /// なり、一覧と詳細が毎回描き直される。** 「他端末で変わったか」も判定できない。
  ///
  /// `branches` は並びまで含めて比べる。カーリルの応答順をそのまま保っている値なので、
  /// **並びが変わったことは変更である。**
  @override
  bool operator ==(Object other) =>
      other is LibrarySystem &&
      other.id == id &&
      other.pref == pref &&
      other.city == city &&
      other.name == name &&
      other.opacSearchUrlTemplate == opacSearchUrlTemplate &&
      other.homepageUrl == homepageUrl &&
      _sameBranches(other.branches, branches);

  @override
  int get hashCode => Object.hash(
        id,
        pref,
        city,
        name,
        opacSearchUrlTemplate,
        homepageUrl,
        // **要素を畳んでから混ぜる。** List の hashCode は同一性なので使えない。
        Object.hashAll(branches),
      );

  @override
  String toString() => 'LibrarySystem($id, $name)';
}

/// 分館の並びまで含めた一致。**`package:collection` を入れずに済ませる。**
///
/// `karita_domain` の依存は `karita_contract` 1つだけで、この1関数のために増やさない。
bool _sameBranches(List<Branch> a, List<Branch> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 登録済みの図書館システムの一覧。
///
/// `library_systems` の集約行から組み立てる読取モデルであり、**設定ファイルの写しではない**
/// （表示・所蔵照会・レポートが「今どの図書館システムを管理しているか」を一括で知るための
/// 入れ物である）。
///
/// **一覧全体としての版は存在しない。** 洗い替えの単位が1図書館システムになったためで、版・
/// 更新時刻・更新端末は集約行の側に、集約ごとに別々にある。
class LibrariesConfig {
  final List<LibrarySystem> librarySystems;

  const LibrariesConfig(this.librarySystems);

  const LibrariesConfig.empty() : librarySystems = const [];

  void validate() {
    final ids = {for (final system in librarySystems) system.id};
    if (ids.length != librarySystems.length) {
      throw DomainError('図書館システムIDが重複しています。', code: 'library-system');
    }
    for (final system in librarySystems) {
      system.validate();
    }
  }
}
