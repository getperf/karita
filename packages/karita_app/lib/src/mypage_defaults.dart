/// マイページ URL の既定値表（5区）。
///
/// **焼き込まず、実行時に引く。** 焼き込むと既定値の修正がアプリ更新でしか届かず、利用者の値と
/// 区別もつかなくなる。実行時に引けば、出典の判別は「保存値があるか」だけで決まり、
/// `既定値に戻す` は保存値の削除で済む（`非公開資料:settings-and-parameters.md`）。
///
/// **23区を埋めることを出荷の条件にしない。** 残る18区でも穴は空かない — カーリルの `url_pc`
/// から `公式サイト` が必ず埋まるので、一手余分にかかるだけで着地はする。
///
/// 解決順序そのものは `karita_domain` の `resolveMypageUrl` が持つ（純 Dart で試験が回る）。
/// ここが持つのは**表の読み取りだけ**である。
library;

import 'dart:convert';

/// 読み込んだ表。**版と確認日を持つ。**
class MypageDefaults {
  final int version;

  /// 作者が採取した日。**画面に必ず出す** — 館サイトの更新で切れたことをアプリは検知できず、
  /// 古さを伝える手段は表示しかない。
  final String checkedOn;

  final Map<String, String> _bySystemId;

  const MypageDefaults._(this.version, this.checkedOn, this._bySystemId);

  const MypageDefaults.empty()
      : version = 0,
        checkedOn = '',
        _bySystemId = const {};

  /// 表が無い・読めないことを起動の失敗にしない。**空の表として扱う** — 既定値が引けなければ
  /// `公式サイト` へ落ちるだけで、業務は続く。
  factory MypageDefaults.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return const MypageDefaults.empty();
    }
    if (decoded is! Map<String, Object?>) return const MypageDefaults.empty();
    final version = decoded['version'];
    final checkedOn = decoded['checked_on'];
    final rows = decoded['rows'];
    if (version is! int || checkedOn is! String || rows is! List) {
      return const MypageDefaults.empty();
    }
    final bySystemId = <String, String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final systemId = row['systemid'];
      final url = row['url'];
      if (systemId is String &&
          systemId.isNotEmpty &&
          url is String &&
          url.isNotEmpty) {
        bySystemId[systemId] = url;
      }
    }
    return MypageDefaults._(version, checkedOn, bySystemId);
  }

  String? urlFor(String systemId) => _bySystemId[systemId];

  Iterable<String> get systemIds => _bySystemId.keys;

  int get length => _bySystemId.length;
}
