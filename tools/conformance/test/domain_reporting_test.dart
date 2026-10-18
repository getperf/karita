/// Loan の参照レポート。**実 DB に対して測る。**
///
/// ここが答えるのは「重複と並行をどう見せるか」である。**データは両方そのまま残す** — 同じ本を
/// 同じ図書館システムで本当に二件予約したのか、一件の予約を二端末で記録しただけなのかは、館の
/// 予約番号を持たないアプリには判定できない。統合すれば、前者のとき実在の予約を一件消す。
library;

import 'package:conformance/src/harness.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:test/test.dart';

const String t0 = '2026-08-04T09:00:00Z';
const String t1 = '2026-08-05T09:00:00Z';
const String t2 = '2026-08-06T09:00:00Z';

const String isbnA = '9784274226298';

const LibrarySystem minato = LibrarySystem(
  id: 'Tokyo_Minato',
  pref: '東京都',
  city: '港区',
  name: '港区立図書館',
  branches: [Branch(id: 'minato-main', calilLibkey: '港区中央', name: '中央館')],
);

const LibrarySystem chuo = LibrarySystem(
  id: 'Tokyo_Chuo',
  pref: '東京都',
  city: '中央区',
  name: '中央区立図書館',
  branches: [Branch(id: 'chuo-main', calilLibkey: '中央区中央', name: '中央館')],
);

void main() {
  late Harness harness;
  late Device device;

  setUp(() {
    harness = Harness.create(Contracts.load(), prefix: 'karita-report-');
    device = harness.device('windows-a', now: t0);
    device.librarySystems.register(system: minato, now: t0);
    device.librarySystems.register(system: chuo, now: t0);
    device.books.adopt(
        title: '達人プログラマー',
        authors: const ['David Thomas'],
        isbn13: isbnA,
        provider: 'rakuten',
        now: t0);
  });
  tearDown(() => harness.dispose());

  String bookId() => deterministicId(entityBook, isbnA);

  String reserve(String loanId, LibrarySystem system,
      {String? on, String now = t0}) {
    device.loans.start(
      loanId: loanId,
      bookId: bookId(),
      status: 'reserved',
      systemId: system.id,
      pickupLibraryId: system.branches.first.id,
      reservedOn: on,
      now: now,
    );
    return loanId;
  }

  LoanReport report({String asOf = '2026-08-06', String? systemId}) =>
      device.reporting.buildLoanReport(device.librarySystems.load(),
          asOf: asOf, systemId: systemId);

  test('管理区ごとに束ね、分館名を解決する', () {
    reserve('aaaaaaaa-2000-4000-8000-000000000001', minato);
    final built = report();

    expect(built.reservedCount, equals(1));
    expect(built.areas, hasLength(1));
    final area = built.areas.single;
    expect(area.city, equals('港区'));
    expect(area.systemIds, equals([minato.id]));
    expect(area.items.single.pickupLibraryName, equals('中央館'));
    expect(area.items.single.systemName, equals('港区立図書館'));
    expect(area.items.single.title, equals('達人プログラマー'));
    expect(area.items.single.configured, isTrue);
  });

  test('同じ館の同じ本の二件は、片方だけを実効にする。データは消さない', () {
    // **後から予約した方を採る。** LWW の決定キーと同じ構造の全順序で決める。
    final older = reserve('aaaaaaaa-2000-4000-8000-000000000001', minato,
        on: '2026-08-01');
    final newer = reserve('aaaaaaaa-2000-4000-8000-000000000002', minato,
        on: '2026-08-03', now: t1);

    final built = report();
    expect(built.reservedCount, equals(1), reason: '見出しは実効だけを数える');
    expect(built.duplicateCount, equals(1));

    final items = built.areas.single.items;
    expect(items, hasLength(2), reason: '重複も残す。畳むのは表示だけである');
    final effective = items.firstWhere((item) => item.effective);
    final duplicate = items.firstWhere((item) => !item.effective);
    expect(effective.loanId, equals(newer));
    expect(duplicate.loanId, equals(older));
    expect(duplicate.duplicateOf, equals(newer));

    // 台帳の側は2件のままである。
    expect(
        device.db.select('SELECT COUNT(*) AS n FROM loans').first['n'], equals(2));
  });

  test('区をまたいだ並行予約は畳まず、注記だけを出す', () {
    // 別の区で予約し、早く来た方を取るのは正当な運用である。畳むと複数の管理区を並行して
    // 使う運用が壊れる。
    reserve('aaaaaaaa-2000-4000-8000-000000000001', minato);
    reserve('aaaaaaaa-2000-4000-8000-000000000002', chuo, now: t1);

    final built = report();
    expect(built.reservedCount, equals(2), reason: '別の区なので両方が実効である');
    expect(built.duplicateCount, equals(0));
    expect(built.areas.map((a) => a.city), equals(['中央区', '港区']));

    for (final item in built.areas.expand((a) => a.items)) {
      expect(item.parallelSystemIds, hasLength(1));
      expect(item.parallelLabels.single, isIn(['港区', '中央区']));
    }
  });

  test('絞り込んでも並行の注記は消えない', () {
    // **絞った側だけを見ると、区をまたいだ並行予約は相手が視界の外にあるため一件も見えない。**
    reserve('aaaaaaaa-2000-4000-8000-000000000001', minato);
    reserve('aaaaaaaa-2000-4000-8000-000000000002', chuo, now: t1);

    final built = report(systemId: minato.id);
    expect(built.areas.single.items.single.parallelSystemIds,
        equals([chuo.id]));
  });

  test('期限が近い・過ぎているを出す', () {
    final loanId = 'aaaaaaaa-2000-4000-8000-000000000001';
    device.loans.start(
      loanId: loanId,
      bookId: bookId(),
      status: 'borrowed',
      systemId: minato.id,
      pickupLibraryId: 'minato-main',
      borrowedOn: '2026-08-04',
      dueOn: '2026-08-07',
      now: t0,
    );
    expect(report(asOf: '2026-08-06').areas.single.items.single.urgency,
        equals('due_soon'));
    expect(report(asOf: '2026-08-08').areas.single.items.single.urgency,
        equals('overdue'));
    expect(report(asOf: '2026-08-01').areas.single.items.single.urgency, isNull);
  });

  test('取置は取置期限で、借出は返却期限で測る', () {
    final loanId = reserve('aaaaaaaa-2000-4000-8000-000000000001', minato);
    device.loans.update(
        loanId: loanId,
        action: 'ready-for-pickup',
        pickupAvailableOn: '2026-08-05',
        pickupDueOn: '2026-08-07',
        now: t1);
    expect(report(asOf: '2026-08-06').areas.single.items.single.urgency,
        equals('due_soon'));
  });

  test('返却した Loan は出てこない', () {
    final loanId = 'aaaaaaaa-2000-4000-8000-000000000001';
    device.loans.start(
      loanId: loanId,
      bookId: bookId(),
      status: 'borrowed',
      systemId: minato.id,
      pickupLibraryId: 'minato-main',
      now: t0,
    );
    expect(report().borrowedCount, equals(1));
    device.loans.update(loanId: loanId, action: 'return', now: t2);
    expect(report().borrowedCount, equals(0));
    expect(report().areas, isEmpty);
  });

  test('未設定のシステムの Loan も落とさず、そうと分かる形で出す', () {
    // **1行のために業務のコマンド全体を止めない。** 設定から消えたシステムの Loan は残る。
    device.loans.start(
      loanId: 'aaaaaaaa-2000-4000-8000-000000000001',
      bookId: bookId(),
      status: 'reserved',
      systemId: 'Tokyo_Shibuya',
      pickupLibraryId: 'shibuya-main',
      now: t0,
    );
    final item = report().areas.single.items.single;
    expect(item.configured, isFalse);
    expect(item.systemName, contains('Tokyo_Shibuya'));
    expect(item.pickupLibraryName, isNull, reason: '分館名は解決できない');
  });

  test('書誌の無い Loan もそうと分かる形で出す', () {
    device.loans.start(
      loanId: 'aaaaaaaa-2000-4000-8000-000000000001',
      bookId: 'aaaaaaaa-9999-4000-8000-000000000001',
      status: 'reserved',
      systemId: minato.id,
      pickupLibraryId: 'minato-main',
      now: t0,
    );
    final item = report().areas.single.items.single;
    expect(item.bookAvailable, isFalse);
    expect(item.title, contains('書誌未登録'));
    expect(item.authors, isEmpty);
  });

  test('書名の無い Book は書誌未登録にせず、ISBN を残す', () {
    // 書誌の取れない ISBN は書名 NULL で保存される。台帳に Book は在る。
    device.db.execute('UPDATE books SET title = NULL WHERE id = ?', [bookId()]);
    reserve('aaaaaaaa-2000-4000-8000-000000000001', minato);
    final item = report().areas.single.items.single;
    expect(item.bookAvailable, isTrue);
    expect(item.title, equals('書名なし'));
    expect(item.isbn13, equals(isbnA));
  });

  test('includeEmpty は Loan の無い区も見出しに出す', () {
    expect(report().areas, isEmpty);
    final built = device.reporting.buildLoanReport(
        device.librarySystems.load(),
        asOf: '2026-08-06',
        includeEmpty: true);
    expect(built.areas.map((a) => a.city), equals(['中央区', '港区']),
        reason: '設定済みの区が先に、load() の system_id 順で並ぶ');
    expect(built.areas.every((a) => a.items.isEmpty), isTrue);
  });

  test('as_of の書式が崩れていれば落ちる', () {
    expect(() => report(asOf: '2026/08/06'), throwsA(isA<FormatException>()));
  });
}
