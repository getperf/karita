/// 管理区設定の不変条件と、登録の合成。**DB を要さない部分だけをここで測る。**
///
/// 集約を書く経路（`register` / `adopt` / `start`）は実 DB を要るので `tools/conformance` に
/// ある。`karita_domain` は `dart:ffi` を持たないので、この層の試験も SQLite を要求しない。
library;

import 'package:karita_domain/karita_domain.dart';
import 'package:test/test.dart';

LibrarySystem system(
  String id, {
  String pref = '東京都',
  String city = '港区',
  String name = '港区立図書館',
  List<Branch>? branches,
  String? template,
  String? homepage,
}) =>
    LibrarySystem(
      id: id,
      pref: pref,
      city: city,
      name: name,
      branches: branches ??
          [const Branch(id: 'minato-main', calilLibkey: '港区中央', name: '中央館')],
      opacSearchUrlTemplate: template,
      homepageUrl: homepage,

    );

void main() {
  group('LibrarySystem.validate', () {
    test('必須4項目が揃っていれば通る', () {
      expect(() => system('Tokyo_Minato').validate(), returnsNormally);
    });

    test('必須項目が欠けていれば落ちる', () {
      // **同期層はこれを見ない。** payload スキーマは required を持てず、集約表も payload 由来の
      // 列に NOT NULL を置けない。「必ず埋まっている」を担保するのは登録経路である。
      for (final broken in [
        system(''),
        system('x', pref: ''),
        system('x', city: ''),
        system('x', name: ''),
      ]) {
        expect(broken.validate, throwsA(isA<DomainError>()));
      }
    });

    test('分館が一つも無ければ落ちる', () {
      expect(system('x', branches: const []).validate,
          throwsA(isA<DomainError>()));
    });

    test('分館IDの重複は落ちる', () {
      expect(
          system('x', branches: const [
            Branch(id: 'a', calilLibkey: 'k1', name: '中央館'),
            Branch(id: 'a', calilLibkey: 'k2', name: '分館'),
          ]).validate,
          throwsA(isA<DomainError>()));
    });

    test('常用館の検査はここに無い（0011 で別集約へ出た）', () {
      // **`LibrarySystem` は常用館を持たない。** 「指定されたら分館に在ること」を見るのは
      // `LibrarySettings.setPreferredBranch` である。カタログ側に残すと、寿命の違うものを
      // 同じ集約で検査することになる。
      expect(() => system('x').validate(), returnsNormally);
    });
  });

  group('LibrariesConfig.validate', () {
    test('システムIDの重複は落ちる', () {
      expect(LibrariesConfig([system('x'), system('x')]).validate,
          throwsA(isA<DomainError>()));
    });

    test('空は通る', () {
      expect(const LibrariesConfig.empty().validate, returnsNormally);
    });
  });

  group('prepareRegistration', () {
    test('id 順に並べ、都道府県と市区町村を揃える', () {
      final prepared = prepareRegistration(
        const LibrariesConfig.empty(),
        pref: ' 東京都 ',
        city: ' 港区 ',
        selectedSystems: [system('B'), system('A')],
      );
      expect(prepared.map((s) => s.id), equals(['A', 'B']));
      expect(prepared.every((s) => s.pref == '東京都' && s.city == '港区'), isTrue);
    });

    test('登録済みの外部リンクをカタログの値で上書きしない', () {
      // 利用者が設定した OPAC のテンプレートは、再登録でカタログの値に戻ってはならない。
      final current = LibrariesConfig([system('A', template: '利用者の設定')]);
      final prepared = prepareRegistration(
        current,
        pref: '東京都',
        city: '港区',
        selectedSystems: [system('A', template: 'カタログの値')],
      );
      expect(prepared.single.opacSearchUrlTemplate, equals('利用者の設定'));
    });

    test('登録済みでリンクが空ならカタログの値も採らない（テンプレート）', () {
      // **`copyWith` の「null は変更なし」に落ちない**ことを測る。登録済みの側が空であることは
      // 「決まっていない」ではなく「空に決まっている」である。
      final current = LibrariesConfig([system('A')]);
      final prepared = prepareRegistration(
        current,
        pref: '東京都',
        city: '港区',
        selectedSystems: [system('A', template: 'カタログの値')],
      );
      expect(prepared.single.opacSearchUrlTemplate, isNull);
    });

    test('homepage だけは登録済みが空ならカタログの値を採る', () {
      // 巡回で開く先は「あるなら出したい」ので、テンプレートとは規則が違う。
      final current = LibrariesConfig([system('A')]);
      final prepared = prepareRegistration(
        current,
        pref: '東京都',
        city: '港区',
        selectedSystems: [system('A', homepage: 'https://example.invalid/')],
      );
      expect(prepared.single.homepageUrl, equals('https://example.invalid/'));
    });

    test('常用館を運ばない。カタログの洗い替えは利用者値に触れない', () {
      // **`0011` で常用館が `LibrarySetting` の行へ出た。** 以前はここが利用者の値を手で
      // 引き継ぎ、新しい分館一覧に無ければ外していた。**寿命の違うものを同じ集約へ押し込んだ
      // 結果の逃げだったので、出したことで消えた。** 分館が消えて参照の切れた設定は
      // `LibrarySettings.danglingPreferredBranches` が拾い、`doctor` が報告する。
      final current = LibrariesConfig([system('A')]);
      final prepared = prepareRegistration(
        current,
        pref: '東京都',
        city: '港区',
        selectedSystems: [
          system('A', branches: const [
            Branch(id: 'minato-mita', calilLibkey: '港区三田', name: '三田館'),
          ]),
        ],
      );
      expect(prepared.single.branches.single.id, equals('minato-mita'));
    });

    test('未登録のシステムはカタログの値をそのまま使う', () {
      final prepared = prepareRegistration(
        const LibrariesConfig.empty(),
        pref: '東京都',
        city: '港区',
        selectedSystems: [system('A', template: 'カタログの値')],
      );
      expect(prepared.single.opacSearchUrlTemplate, equals('カタログの値'));
    });

    test('選択が空、または区が空なら落ちる', () {
      expect(
          () => prepareRegistration(const LibrariesConfig.empty(),
              pref: '東京都', city: '港区', selectedSystems: const []),
          throwsA(isA<DomainError>()));
      expect(
          () => prepareRegistration(const LibrariesConfig.empty(),
              pref: ' ', city: '港区', selectedSystems: [system('A')]),
          throwsA(isA<DomainError>()));
    });

    test('不変条件を満たさないものは合成の時点で落ちる', () {
      expect(
          () => prepareRegistration(const LibrariesConfig.empty(),
              pref: '東京都',
              city: '港区',
              selectedSystems: [system('A', branches: const [])]),
          throwsA(isA<DomainError>()));
    });
  });

  equalityTests();
}

/// 等価性。**UI の再読込がここに掛かっている。**
///
/// 台帳の変更通知（同期の開始・終了、前面復帰、診断の完了）のたびに `load()` がやり直される
/// ので、値として比べられないと**中身が同じでも必ず別インスタンス**になり、一覧と詳細が
/// 毎回描き直される。`Branch` と `LibrarySetting` は先に持っていた。
void equalityTests() {
  group('LibrarySystem の等価性', () {
    test('同じ内容なら等しく、hashCode も揃う', () {
      expect(system('A'), system('A'));
      expect(system('A').hashCode, system('A').hashCode);
      expect({system('A'), system('A')}, hasLength(1));
    });

    test('欄が1つでも違えば等しくない', () {
      expect(system('A'), isNot(system('B')));
      expect(system('A'), isNot(system('A', pref: '千葉県')));
      expect(system('A'), isNot(system('A', city: '中央区')));
      expect(system('A'), isNot(system('A', name: '別の名')));
      expect(system('A'), isNot(system('A', template: 'https://x/{isbn}')));
      expect(system('A'), isNot(system('A', homepage: 'https://x/')));
    });

    test('分館は並びまで含めて比べる', () {
      const one = Branch(id: 'b1', calilLibkey: 'k1', name: '館1');
      const two = Branch(id: 'b2', calilLibkey: 'k2', name: '館2');
      expect(
        system('A', branches: const [one, two]),
        system('A', branches: const [one, two]),
      );
      // **並びが変わったことは変更である。** カーリルの応答順を保っている値である。
      expect(
        system('A', branches: const [one, two]),
        isNot(system('A', branches: const [two, one])),
      );
      expect(
        system('A', branches: const [one, two]),
        isNot(system('A', branches: const [one])),
      );
    });
  });
}
