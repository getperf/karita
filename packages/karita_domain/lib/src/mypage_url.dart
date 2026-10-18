/// マイページ URL の解決順序。**純関数だけを置く。**
///
/// 出典は四つあり、`取り込み値` → `既定値` → `公式サイト` → `未設定` の順に引く
/// （`../karita-ui-probe/docs/library-site-url.md` §3）。
///
/// **出典そのものを保存しない。** 「保存値があるか」だけで決まるので、`既定値に戻す` は保存値の
/// 削除で済む。既定値を焼き込むと、既定値の修正がアプリ更新でしか届かず、利用者の値とも区別が
/// つかなくなる。
///
/// **値が妥当かはここで見ない。** 決めるのは順序だけである。保存してよいかの検査は入力経路
/// （`karita_handoff` の `checkSaveableUrl`）が持ち、壊れた既定値の逃げ道は仕様側で未決である。
library;

/// どこから来た値か。**画面に必ず出す** — 既定値はアプリ作者が確認した時点の値で、館サイトの
/// 更新で切れる。切れたことをアプリは検知できないので、古さを伝える手段は表示しかない。
enum MypageUrlSource {
  /// 利用者が取り込んで保存した値。
  imported,

  /// 同梱の既定値表（5区）。
  bundled,

  /// カーリル `url_pc` 由来の公式サイト。**マイページではない** — 館サイトのトップなので、
  /// 利用者がログイン入口を探すことになる。
  official,

  /// いずれも無い。
  unset,
}

/// 解決した1件。
class MypageUrl {
  final String? value;
  final MypageUrlSource source;

  /// 確認した日。**出典によって意味が変わる** — 既定値なら作者の採取日、取り込み値なら利用者の
  /// 取り込み日である。公式サイトと未設定では無い。
  final String? checkedOn;

  const MypageUrl(this.source, {this.value, this.checkedOn});

  bool get isSet => value != null && value!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is MypageUrl &&
      other.value == value &&
      other.source == source &&
      other.checkedOn == checkedOn;

  @override
  int get hashCode => Object.hash(value, source, checkedOn);

  @override
  String toString() => 'MypageUrl(${source.name}, $value)';
}

/// 順に引く。**空文字は「無い」と同じに扱う。**
MypageUrl resolveMypageUrl({
  String? imported,
  String? importedCheckedOn,
  String? bundled,
  String? bundledCheckedOn,
  String? homepageUrl,
}) {
  if (imported != null && imported.isNotEmpty) {
    return MypageUrl(MypageUrlSource.imported,
        value: imported, checkedOn: importedCheckedOn);
  }
  if (bundled != null && bundled.isNotEmpty) {
    return MypageUrl(MypageUrlSource.bundled,
        value: bundled, checkedOn: bundledCheckedOn);
  }
  if (homepageUrl != null && homepageUrl.isNotEmpty) {
    return MypageUrl(MypageUrlSource.official, value: homepageUrl);
  }
  return const MypageUrl(MypageUrlSource.unset);
}
