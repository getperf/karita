/// マイページ URL を**保存してよいか**の検査。
///
/// 共有で受けた URL の検証（[parseHandoff] の分類）と、設定に保存する URL の検証は別物である。
/// 分類は「どの画面へ渡すか」を決め、こちらは「台帳へ書いてよいか」を決める。
///
/// **入口に集める理由は ISBN と同じである。** `Books.adopt` が length と数字だけを見て
/// チェック桁を見ないのと同様に、`LibrarySetting` 側の不変条件は最低限に留め、セッション ID の
/// ような**入力経路の検査はここへ集める。** 集約側へ持たせると、同期で届いた行に同じ検査を
/// 課すことになり、適用経路が止まる。
///
/// 規則の正本は `../karita-ui-probe/docs/library-site-url.md` §5 である。
library;

/// 検査で見つかったもの。**拒否と警告が混ざっている。**
enum UrlSaveIssue {
  /// http(s) ではない。**拒否。**
  notWeb,

  /// userinfo が付いている。**拒否。**
  hasUserInfo,

  /// セッション ID とみなす鍵を含む。**拒否。**
  sessionKey,

  /// 旧版のホスト比較警告。互換のため残すが、保存検査では生成しない。
  hostMismatch,

  /// 旧版の比較先欠損警告。互換のため残すが、保存検査では生成しない。
  noComparison,
}

/// 検査の結果。
class UrlSaveCheck {
  final Set<UrlSaveIssue> issues;

  const UrlSaveCheck(this.issues);

  /// 保存してよいか。**警告は保存を止めない。**
  bool get saveable => !issues.any(_rejects.contains);

  @override
  String toString() =>
      'UrlSaveCheck(saveable: $saveable, ${issues.map((i) => i.name).join(',')})';

  static const Set<UrlSaveIssue> _rejects = {
    UrlSaveIssue.notWeb,
    UrlSaveIssue.hasUserInfo,
    UrlSaveIssue.sessionKey,
  };
}

/// 保存用の検査。[compareTo] は呼び出し互換のため残すが、判定に使わない。
/// 公式サイトとOPACのホストは正常な導線でも異なるため、ホストの対応は検査しない。
///
/// **クエリがあること自体では拒否しない。** 実採取値に `?DB=LIB` と `?smtFlg=0` があり、
/// どちらもセッションではない。**拒否は鍵の名前で判定する。** 鍵を削って「安全な URL」へ
/// 加工もしない — 加工した値が安定したログイン入口である保証が無い。
UrlSaveCheck checkSaveableUrl(Uri url, {Uri? compareTo}) {
  final issues = <UrlSaveIssue>{};
  if (url.scheme != 'http' && url.scheme != 'https') {
    issues.add(UrlSaveIssue.notWeb);
  }
  if (url.userInfo.isNotEmpty) issues.add(UrlSaveIssue.hasUserInfo);
  if (_hasSessionKey(url)) issues.add(UrlSaveIssue.sessionKey);
  return UrlSaveCheck(issues);
}

/// **path も見る。** Java 系（Wicket・TOSHOW）はセッションを `;jsessionid=…` として path に
/// 付ける。葛飾区と墨田区のトップのログインリンクが実際にこの形で、`/idcheck` を安定入口と
/// した理由そのものである。クエリだけを見ると素通りする。
bool _hasSessionKey(Uri url) {
  final path = url.path.toLowerCase();
  for (final key in sessionKeys) {
    if (path.contains(';$key=')) return true;
  }
  for (final name in url.queryParametersAll.keys) {
    if (sessionKeys.contains(name.toLowerCase())) return true;
  }
  return false;
}

/// セッション ID とみなす鍵。**名前の完全一致で見る。**
const Set<String> sessionKeys = {
  'jsessionid',
  'phpsessid',
  'sessionid',
  'token',
  'uid',
};
