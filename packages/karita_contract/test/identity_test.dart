/// 同一性の種。**Python と同じ id を出すことが全部である。**
///
/// ずれても両方の実装は自分の中では一貫して動く。ずれが出るのは二端末が同じ実体を独立に
/// 登録したときで、そのとき重複は競合として立たず、両方が正常に適用される。**静かに壊れる**
/// ので、期待値は Python が実際に出した値を焼き込む。
library;

import 'package:karita_contract/karita_contract.dart';
import 'package:test/test.dart';

void main() {
  group('deterministicId', () {
    // book-sync-model の `contracts.ids.deterministic_id` が実際に返した値。
    const expected = {
      ('book', '9784274226298'): 'e963a313-5ec4-510e-8811-0eb06ed5690a',
      ('book', '9780000000002'): '90e4d372-0aa2-59fb-87d7-d5f0cc89f68b',
      ('library_system', 'Tokyo_Minato'): '7f1c1301-a6bd-5655-8f8f-bc9cd0823608',
      ('library_membership', 'Tokyo_Minato'):
          '52b09325-8c68-5f42-bf56-4433ce07afc4',
    };

    test('Python が出した値と一致する', () {
      expected.forEach((key, value) {
        expect(deterministicId(key.$1, key.$2), equals(value),
            reason: '${key.$1} / ${key.$2} の id が Python と食い違う');
      });
    });

    test('種別ごとに名前空間が分かれている', () {
      // 同じ種文字列でも種別が違えば別の id になる。ISBN と system_id が衝突しないため。
      expect(deterministicId('library_system', 'Tokyo_Minato'),
          isNot(equals(deterministicId('library_membership', 'Tokyo_Minato'))));
    });

    test('宣言にない種別は綴り間違いとして落とす', () {
      // 黙って別の名前空間を作ると、その種別の同一性だけが端末間で成立しなくなる。
      expect(() => deterministicId('loann', 'x'),
          throwsA(isA<SyncDataError>().having((e) => e.code, 'code', 'identity')));
      expect(() => deterministicId('Book', 'x'), throwsA(isA<SyncDataError>()));
    });

    test('種が空なら落とす', () {
      expect(() => deterministicId('book', ''),
          throwsA(isA<SyncDataError>().having((e) => e.code, 'code', 'identity')));
    });

    test('同じ入力は何度でも同じ id になる', () {
      expect(deterministicId('book', '9784274226298'),
          equals(deterministicId('book', '9784274226298')));
    });
  });

  group('宣言', () {
    test('kinds は封筒の enum に含まれる種別だけである', () {
      // 宣言できるのは同期集約の種別だけ。loan は業務キーを持たないので入らない。
      for (final kind in Identity.load().kinds) {
        expect(syncedEntityTypes, contains(kind));
      }
    });

    test('namespace は宣言のものをそのまま使う', () {
      expect(Identity.load().namespace,
          equals('c036a129-14eb-400c-adfa-e836f9c7a214'));
    });
  });
}
