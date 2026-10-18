import 'dart:convert';

import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:test/test.dart';

import 'fake_public_api_server.dart';

/// 実 `/library` が返す形。**館(`libid`)単位の行が並ぶ。**
Map<String, Object?> _row({
  required String libid,
  required String systemid,
  required String systemname,
  required String formal,
  required String libkey,
  String city = '江東区',
  String address = '東京都江東区豊洲2-2-18',
  String urlPc = 'https://www.koto-lib.tokyo.jp/',
}) => {
  'libid': libid,
  'formal': formal,
  'short': libkey,
  'systemid': systemid,
  'systemname': systemname,
  'libkey': libkey,
  'pref': '東京都',
  'city': city,
  'address': address,
  'url_pc': urlPc,
};

final List<Map<String, Object?>> _tokyoRows = [
  _row(
    libid: '106491',
    systemid: 'Tokyo_Koto',
    systemname: '江東区',
    formal: '江東区立豊洲図書館',
    libkey: '豊洲',
  ),
  _row(
    libid: '106492',
    systemid: 'Tokyo_Koto',
    systemname: '江東区',
    formal: '江東区立東雲図書館',
    libkey: '東雲',
    address: '東京都江東区東雲2-7-5',
  ),
  _row(
    libid: '106001',
    systemid: 'Tokyo_Minato',
    systemname: '港区',
    formal: '港区立三田図書館',
    libkey: '三田',
    city: '港区',
    address: '東京都港区芝5-28-4',
    urlPc: 'https://www.lib.city.minato.tokyo.jp/',
  ),
];

void main() {
  late FakePublicApiServer server;
  late CalilLibraryClient client;

  setUp(() async {
    server = await FakePublicApiServer.start();
    client = CalilLibraryClient(appkey: 'test-key', apiBase: server.calilBase);
  });

  tearDown(() async {
    client.close();
    await server.close();
  });

  group('図書館の候補', () {
    test('不正な行と重複IDは部分応答として判別できる', () async {
      for (final bad in [
        null,
        {'systemid': 'Tokyo_Koto'},
        _tokyoRows.first,
      ]) {
        server.libraryBody = jsonEncode([_tokyoRows.first, bad]);
        expect((await client.listByPref('東京都')).incomplete, isTrue);
      }
      server.libraryBody = jsonEncode(_tokyoRows);
      expect((await client.listByPref('東京都')).incomplete, isFalse);
    });
    test('**館の行を systemid で束ねる。** 区と共同システムを混ぜない', () async {
      server.libraryBody = jsonEncode(_tokyoRows);
      final result = await client.listByPref('東京都');

      expect(result.systems.map((s) => s.systemId), [
        'Tokyo_Koto',
        'Tokyo_Minato',
      ]);
      final koto = result.systems.first;
      expect(koto.systemName, '江東区');
      expect(koto.pref, '東京都');
      expect(koto.city, '江東区');
      expect(koto.homepageUrl, 'https://www.koto-lib.tokyo.jp/');
      expect(koto.branches.length, 2);
    });

    test('**台帳へ入る分館の id は `calil:<libid>`。** libkey は外部キーとしてだけ持つ', () async {
      server.libraryBody = jsonEncode(_tokyoRows);
      final result = await client.listByPref('東京都');
      final branch = result.systems.first.branches.first;

      expect(branch.id, 'calil:106491');
      expect(branch.libkey, '豊洲');
      expect(branch.name, '江東区立豊洲図書館');
      expect(branch.address, '東京都江東区豊洲2-2-18');
    });

    test('appkey と JSON の指定が要求に載る。**callback を空にしないと JSONP で返る**', () async {
      server.libraryBody = '[]';
      await client.listByPref('東京都', city: '江東区');

      final query = server.requests.single.queryParameters;
      expect(query['appkey'], 'test-key');
      expect(query['pref'], '東京都');
      expect(query['city'], '江東区');
      expect(query['format'], 'json');
      expect(query['callback'], '');
    });

    test('`limit` に当たったら、切り詰めたことを伝える', () async {
      server.libraryBody = jsonEncode(_tokyoRows);
      final result = await client.listByPref('東京都', limit: 3);

      expect(result.truncated, isTrue);
      expect((await client.listByPref('東京都', limit: 500)).truncated, isFalse);
    });

    test('**`systemid` に `/` が混じる行は落とす。** 設定の行 id が壊れる', () async {
      server.libraryBody = jsonEncode([
        ..._tokyoRows,
        _row(
          libid: '999',
          systemid: 'Tokyo/Broken',
          systemname: 'こわれ',
          formal: 'こわれ図書館',
          libkey: 'こわれ',
        ),
      ]);
      final result = await client.listByPref('東京都');

      expect(result.rejectedSystemIds, ['Tokyo/Broken']);
      expect(result.systems.map((s) => s.systemId), [
        'Tokyo_Koto',
        'Tokyo_Minato',
      ]);
    });

    test('読めない応答は失敗にする', () async {
      for (final body in ['{}', 'JSONではない']) {
        server.libraryBody = body;
        final result = await client.listByPref('東京都');
        expect(result.failure, ApiFailure.invalidData, reason: body);
        expect(result.systems, isEmpty, reason: body);
      }
    });

    test('キー無しでは作らせない', () {
      expect(() => CalilLibraryClient(appkey: ''), throwsArgumentError);
    });
  });

  group('端末側の絞込み', () {
    late List<LibrarySystemCandidate> systems;

    setUp(() async {
      server.libraryBody = jsonEncode(_tokyoRows);
      systems = (await client.listByPref('東京都')).systems;
    });

    test('システム名・市区町村・館名・住所のどれでも当たる', () {
      expect(filterSystems(systems, '江東').map((s) => s.systemId), [
        'Tokyo_Koto',
      ]);
      expect(filterSystems(systems, '東雲').map((s) => s.systemId), [
        'Tokyo_Koto',
      ]);
      expect(filterSystems(systems, '芝5').map((s) => s.systemId), [
        'Tokyo_Minato',
      ]);
      expect(filterSystems(systems, 'Tokyo_Minato').map((s) => s.systemId), [
        'Tokyo_Minato',
      ]);
    });

    test('英字の大小と空白は揃える。**表記ゆれは推測しない**', () {
      expect(filterSystems(systems, 'tokyo_koto').length, 1);
      expect(filterSystems(systems, ' 東 雲 ').length, 1);
      // `圖書館` は `図書館` と同じにしない。当てると、選んだつもりのない館が混じる。
      expect(filterSystems(systems, '圖書館'), isEmpty);
    });

    test('**語が空なら全部返す。** 「絞り込めない」は「1件も無い」ではない', () {
      expect(filterSystems(systems, '').length, systems.length);
      expect(filterSystems(systems, '   ').length, systems.length);
    });

    test('当たらなければ空を返す', () {
      expect(filterSystems(systems, '北海道'), isEmpty);
    });
  });

  rankingTests();
}

/// 並べ替えと分類。**2026-09-17 の実測で決まった規則を固定する。**
///
/// 候補は手書きで組む — 並べ替えの規則を見るのに応答の形は要らない。
LibrarySystemCandidate _candidate(
  String systemId, {
  String systemName = 'システム',
  String city = '江東区',
  Set<String> categories = const {'SMALL'},
  List<BranchCandidate> branches = const [],
}) => LibrarySystemCandidate(
  systemId: systemId,
  systemName: systemName,
  pref: '東京都',
  city: city,
  categories: categories,
  branches: branches,
);

void rankingTests() {
  group('公共か大学・専門か', () {
    test('全行が UNIV か SPECIAL なら大学・専門。1つでも違えば公共', () {
      expect(
        _candidate('a', categories: const {'UNIV'}).isPublicLibrary,
        isFalse,
      );
      expect(
        _candidate('a', categories: const {'SPECIAL'}).isPublicLibrary,
        isFalse,
      );
      expect(
        _candidate('a', categories: const {'UNIV', 'SPECIAL'}).isPublicLibrary,
        isFalse,
      );
      // **足立区は `{MEDIUM, SMALL, SPECIAL}` である**（実測）。専門の館を持つが公共である。
      expect(
        _candidate(
          'a',
          categories: const {'MEDIUM', 'SMALL', 'SPECIAL'},
        ).isPublicLibrary,
        isTrue,
      );
      for (final category in const ['SMALL', 'MEDIUM', 'LARGE', 'BM']) {
        expect(_candidate('a', categories: {category}).isPublicLibrary, isTrue);
      }
    });

    test('分類が付いていなければ公共として扱う。**落とすより出す**', () {
      expect(_candidate('a', categories: const {}).isPublicLibrary, isTrue);
    });
  });

  group('並べ替え', () {
    test('公共が先、大学・専門が後', () {
      final ranked = filterSystems([
        _candidate('Univ_A', categories: const {'UNIV'}),
        _candidate('Tokyo_A'),
        _candidate('Special_A', categories: const {'SPECIAL'}),
        _candidate('Tokyo_B'),
      ], '');
      expect(ranked.map((s) => s.systemId), [
        'Tokyo_A',
        'Tokyo_B',
        'Univ_A',
        'Special_A',
      ]);
    });

    test('同じ側なら、本体に当たったものが分館にだけ当たったものより先', () {
      final ranked = filterSystems([
        _candidate(
          'Tokyo_Branch',
          systemName: '港区',
          city: '港区',
          branches: const [
            BranchCandidate(
              id: 'calil:1',
              libkey: '越中島',
              name: '越中島図書館',
              address: '東京都江東区越中島2-1-6',
            ),
          ],
        ),
        _candidate('Tokyo_Body', systemName: '江東区'),
      ], '江東区');
      // **市区町村を選ばせる形だと落ちるほうが、キーワードなら残る**（2026-09-16 の実測）。
      expect(ranked.map((s) => s.systemId), ['Tokyo_Body', 'Tokyo_Branch']);
    });

    test('決めきれないところは応答の並びのまま。**揺らさない**', () {
      final ranked = filterSystems([
        _candidate('Tokyo_C'),
        _candidate('Tokyo_A'),
        _candidate('Tokyo_B'),
      ], '');
      expect(ranked.map((s) => s.systemId), ['Tokyo_C', 'Tokyo_A', 'Tokyo_B']);
    });

    test('語が空なら全部返る。**「絞り込めない」を「1件も無い」にしない**', () {
      final systems = [
        _candidate('Tokyo_A'),
        _candidate('Univ_A', categories: const {'UNIV'}),
      ];
      expect(filterSystems(systems, '').length, 2);
      expect(filterSystems(systems, '   ').length, 2);
    });

    test('大学・専門も絞込みで消えない。**並びであって絞込みではない**', () {
      final ranked = filterSystems([
        _candidate(
          'Univ_Kaiyodai',
          systemName: '東京海洋大学',
          city: '港区',
          categories: const {'UNIV'},
        ),
        _candidate('Tokyo_Koto', systemName: '江東区'),
      ], '江東区');
      expect(ranked.map((s) => s.systemId), ['Tokyo_Koto']);
      // 語を消せば大学も出る。
      expect(
        filterSystems([
          _candidate('Univ_Kaiyodai', categories: const {'UNIV'}),
          _candidate('Tokyo_Koto'),
        ], '').length,
        2,
      );
    });
  });

  group('都道府県', () {
    test('47件。重複しない', () {
      expect(prefectures, hasLength(47));
      expect(prefectures.toSet(), hasLength(47));
    });

    test('地方公共団体コード順で、端は北海道と沖縄県である', () {
      expect(prefectures.first, '北海道');
      expect(prefectures.last, '沖縄県');
      expect(prefectures[12], '東京都');
    });

    test('**カーリルへ渡す値そのものである。** 実測した応答の pref と一致する', () {
      // 2026-09-16・17 の live 観測はどれも `東京都` で引いている。
      expect(prefectures, contains('東京都'));
      expect(prefectures, contains('北海道'));
      expect(prefectures, contains('大阪府'));
      expect(prefectures, contains('京都府'));
    });
  });
}
