/// カーリルの `/library` から、図書館システムの候補と分館を取る。
///
/// **自由語の検索は無い。** 受けるのは `pref` / `city` / `systemid` / `geocode` だけで、
/// 全国を一度に引く経路も無い。だから画面は先に都道府県を選ばせ、**キーワードの絞込みは
/// 端末側で行う**（[filterSystems]）。これは UI の好みではなく API の制約である。
///
/// **館(`libid`)単位の行が返る。** 同じ図書館システムの行が何本も並ぶので、`systemid` で
/// 束ねて分館にする。台帳へ入る分館の id は `calil:<libid>` で、`libkey` は蔵書照会に要る
/// 外部キーとしてだけ持つ — 館名の表記ゆれで動きうるものを台帳の外部キーにしない。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'defaults.dart';
import 'failures.dart';
import 'fetch.dart';

/// 分館1件の候補。
class BranchCandidate {
  /// 台帳へ入る id。`calil:<libid>` である。
  final String id;

  /// 蔵書照会で館を名指すキー。**台帳の外部キーにしない。**
  final String libkey;

  /// 正式名称。
  final String name;

  /// 住所。**端末側の絞込みに使う** — 台帳へは持って行かない。
  final String? address;

  const BranchCandidate({
    required this.id,
    required this.libkey,
    required this.name,
    this.address,
  });
}

/// 図書館システム1件の候補。**まだ台帳の集約ではない。**
class LibrarySystemCandidate {
  final String systemId;
  final String systemName;
  final String pref;
  final String city;
  final List<BranchCandidate> branches;

  /// 公式サイト。**行ごとに違うことがあるので、最初に見つけたものを候補として持つ。**
  /// 再登録のたびに洗い替える値であり、利用者が手で直せる。
  final String? homepageUrl;

  /// このシステムの館に付いていた分類。**館ごとの値なので集合である。**
  ///
  /// **1システムの中で割れる**（2026-09-17 実測。東京都の310システム中40件が割れており、
  /// 足立区は `{MEDIUM, SMALL, SPECIAL}`）。だから「このシステムは何か」は1行では決まらない。
  ///
  /// **台帳へは持って行かない。** 並べ替えにしか使わない値で、集約の payload に入れると
  /// 洗い替えの対象が増える。
  final Set<String> categories;

  const LibrarySystemCandidate({
    required this.systemId,
    required this.systemName,
    required this.pref,
    required this.city,
    required this.branches,
    this.homepageUrl,
    this.categories = const {},
  });

  /// 公共図書館か。**大学（`UNIV`）と専門（`SPECIAL`）だけで出来ていなければ公共である。**
  ///
  /// **導出をここに置くのは、応答の読み方だからである**（`非公開資料:ui-state-model.md`
  /// §3.1）。画面の都合ではない。
  ///
  /// **2026-09-17 の実測で、この規則が接頭辞より正しいことが確かめられた。** 東京都で
  /// 公共59 / 大学・専門251 に分かれ、`Tokyo_` 接頭辞なのに大学・専門へ落ちたのは
  /// `Tokyo_Niye`（国立青少年教育振興機構）と `Tokyo_Tenji`（日本点字図書館）の2件で、
  /// **どちらも実際に専門図書館である。** 逆に公共で接頭辞が違うものは0件だった。
  /// **`systemid` の接頭辞は命名規約であって契約ではない**ので、応答が名乗る分類で決める。
  ///
  /// **分類が1つも付いていなければ公共として扱う。** 落とすより出すほうが安全である。
  bool get isPublicLibrary =>
      categories.isEmpty ||
      !categories.every((c) => c == 'UNIV' || c == 'SPECIAL');
}

class LibraryLookupResult {
  final List<LibrarySystemCandidate> systems;

  /// `limit` に当たった。**切り詰めたことを利用者へ見せる** — 黙って欠けると、探している館が
  /// 「無い」のか「載っていない」のか区別できない。
  final bool truncated;

  /// `systemid` に `/` が入っていて落とした行。
  ///
  /// **落とすのは、利用者設定の行の同一性が `<systemid>/<key>` で決まるからである**
  /// （`library_setting`）。`/` が混じると別の設定を指す id が作れてしまう。起きない想定だが、
  /// 起きたときに黙って混ぜない。
  final List<String> rejectedSystemIds;

  final ApiFailure? failure;

  /// Some rows could not be interpreted; unsafe for replacing saved branches.
  final bool incomplete;

  const LibraryLookupResult({
    this.systems = const [],
    this.truncated = false,
    this.rejectedSystemIds = const [],
    this.failure,
    this.incomplete = false,
  });
}

final Logger _log = Logger('karita.api.calil');

class CalilLibraryClient {
  final http.Client _httpClient;
  final Uri apiBase;
  final String appkey;
  final Duration timeout;
  final int maxBytes;

  CalilLibraryClient({
    required this.appkey,
    http.Client? httpClient,
    Uri? apiBase,
    this.timeout = defaultCalilTimeout,
    this.maxBytes = defaultMaxCalilResponseBytes,
  }) : _httpClient = httpClient ?? http.Client(),
       apiBase = apiBase ?? calilApiBase {
    if (appkey.isEmpty) {
      throw ArgumentError.value(appkey, 'appkey', 'キーなしでは照会しない');
    }
  }

  void close() => _httpClient.close();

  /// 都道府県（と、あれば市区町村）で引く。
  ///
  /// **`callback` を空にすると素の JSON が返る。** 既定は JSONP なので、指定を落とすと
  /// `callback(...)` に包まれた本文を JSON として読もうとして必ず落ちる。
  Future<LibraryLookupResult> listByPref(
    String pref, {
    String? city,
    int limit = defaultLibraryLimit,
  }) async {
    final uri = apiBase.replace(
      path: '${apiBase.path}/library',
      queryParameters: {
        'appkey': appkey,
        'pref': pref,
        if (city != null && city.isNotEmpty) 'city': city,
        'limit': '$limit',
        'format': 'json',
        'callback': '',
      },
    );
    try {
      final response = await fetchBytes(
        _httpClient,
        uri,
        maxBytes: maxBytes,
        timeout: timeout,
        provider: 'calil',
        operation: 'library',
      );
      throwForStatus(response.statusCode);
      final result = _readRows(response.bodyBytes, limit);
      // **件数だけを出す。** 都道府県も市区町村も利用者が選んだ値なので渡さない
      // （`非公開資料:logging-and-diagnostics.md`「書かないもの」）。
      _log.fine('calil.library.listed', {
        'systems': result.systems.length,
        'branches': [
          for (final system in result.systems) system.branches.length,
        ].fold<int>(0, (sum, n) => sum + n),
        'truncated': result.truncated,
        'rejected': result.rejectedSystemIds.length,
      });
      return result;
    } on ApiFailureException catch (error) {
      _log.warning('calil.library.failed', {'outcome': error.failure.name});
      return LibraryLookupResult(failure: error.failure);
    }
  }

  LibraryLookupResult _readRows(List<int> bodyBytes, int limit) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes));
    } catch (error) {
      throw ApiFailureException(ApiFailure.invalidData, '$error');
    }
    if (decoded is! List) {
      throw const ApiFailureException(ApiFailure.invalidData, '配列ではない');
    }

    // 並び順は応答のままにする。**先に出てきたシステムが先に出る。**
    final grouped = <String, List<Map<Object?, Object?>>>{};
    final rejected = <String>[];
    var incomplete = false;
    final branchIds = <String>{};
    for (final row in decoded) {
      if (row is! Map) {
        incomplete = true;
        continue;
      }
      final systemId = _text(row['systemid']);
      if (systemId == null) {
        incomplete = true;
        continue;
      }
      if (_text(row['libid']) == null ||
          _text(row['libkey']) == null ||
          (_text(row['formal']) == null && _text(row['short']) == null)) {
        incomplete = true;
      }
      final libid = _text(row['libid']);
      if (libid != null && !branchIds.add('$systemId/$libid')) {
        incomplete = true;
      }
      if (systemId.contains('/')) {
        if (!rejected.contains(systemId)) rejected.add(systemId);
        continue;
      }
      grouped.putIfAbsent(systemId, () => []).add(row);
    }

    final systems = <LibrarySystemCandidate>[];
    for (final entry in grouped.entries) {
      final rows = entry.value;
      systems.add(
        LibrarySystemCandidate(
          systemId: entry.key,
          systemName: _firstOf(rows, 'systemname') ?? entry.key,
          pref: _firstOf(rows, 'pref') ?? '',
          city: _firstOf(rows, 'city') ?? '',
          homepageUrl: _firstOf(rows, 'url_pc'),
          categories: {
            for (final row in rows)
              if (_text(row['category']) case final category?) category,
          },
          branches: [
            for (final row in rows)
              if (_text(row['libid']) case final libid?)
                BranchCandidate(
                  id: 'calil:$libid',
                  libkey: _text(row['libkey']) ?? '',
                  name: _text(row['formal']) ?? _text(row['short']) ?? '',
                  address: _text(row['address']),
                ),
          ],
        ),
      );
    }

    return LibraryLookupResult(
      systems: systems,
      truncated: decoded.length >= limit,
      rejectedSystemIds: rejected,
      incomplete: incomplete,
    );
  }

  static String? _firstOf(List<Map<Object?, Object?>> rows, String key) {
    for (final row in rows) {
      final value = _text(row[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// 取ってきた候補を、利用者の入れた語で絞る。**通信しない。**
///
/// 当てるのは systemid・システム名・都道府県・市区町村と、分館の名前・libkey・住所である。
/// **表記ゆれは推測しない** — 揃えるのは英字の大小と空白だけで、`図書館` と `圖書館` を
/// 同じものにはしない。推測で当てると、選んだつもりのない館が候補に混じる。
///
/// 語が空なら全部返す。**「絞り込めない」を「1件も無い」にしない。**
///
/// **並べ替えて返す**（2026-09-17）。順位は次の3つで、上から順に効く。
///
/// 1. **公共が先、大学・専門が後**（[LibrarySystemCandidate.isPublicLibrary]）。東京都の
///    310システムのうち **251件が大学・専門**で、利用者が登録するのは公共である
/// 2. **本体（`systemname`・`city`）に当たったものが先**、分館の名前・住所にだけ当たった
///    ものが後（2026-09-16 決定）
/// 3. **応答の並び。** 決めきれないところで揺らさない — `List.sort` は安定ではないので、
///    元の位置を最後の鍵にする
///
/// **1 は「分類で分けない」の差し戻しではない**（2026-09-16 決定）。あちらが退けたのは
/// 大学と美術館を分けることで、その理由（探し方が変わらない）はいまも効いている。ここで
/// 分けるのは**公共かそれ以外かの2つだけ**で、しかも**並びであって絞込みではない** —
/// 大学・専門も全部出る。
List<LibrarySystemCandidate> filterSystems(
  List<LibrarySystemCandidate> systems,
  String keyword,
) {
  final needle = _fold(keyword);
  final hits = <({LibrarySystemCandidate system, int index, bool inBody})>[];
  for (var index = 0; index < systems.length; index++) {
    final system = systems[index];
    if (needle.isEmpty) {
      hits.add((system: system, index: index, inBody: true));
      continue;
    }
    if (!_haystack(system).contains(needle)) continue;
    hits.add((
      system: system,
      index: index,
      inBody: _matchedInBody(system, needle),
    ));
  }
  hits.sort((a, b) {
    final public =
        (b.system.isPublicLibrary ? 1 : 0) - (a.system.isPublicLibrary ? 1 : 0);
    if (public != 0) return public;
    final body = (b.inBody ? 1 : 0) - (a.inBody ? 1 : 0);
    if (body != 0) return body;
    return a.index - b.index;
  });
  return [for (final hit in hits) hit.system];
}

/// 語が本体（`systemid`・システム名・都道府県・市区町村）に当たったか。
///
/// **当たらなければ分館の名前・住所にだけ当たったということである** — [filterSystems] は
/// 当たったものしか渡さない。
bool _matchedInBody(LibrarySystemCandidate system, String foldedNeedle) =>
    _fold(
      [system.systemId, system.systemName, system.pref, system.city].join(' '),
    ).contains(foldedNeedle);

String _haystack(LibrarySystemCandidate system) => _fold(
  [
    system.systemId,
    system.systemName,
    system.pref,
    system.city,
    for (final branch in system.branches) ...[
      branch.name,
      branch.libkey,
      branch.address ?? '',
    ],
  ].join(' '),
);

String _fold(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
