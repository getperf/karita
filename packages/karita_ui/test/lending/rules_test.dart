/// 貸出しの表示条件。**純関数なので widget を立てずに固定する。**
///
/// 間近の窓・フィルタ・並びは `lending.md` §2 が文章で決めているものである。文章のまま実装へ
/// 写すと、`<=` か `<` かといった境目が試験に残らない。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_ui/karita_ui.dart';

LoanReportItem item({
  String loanId = 'l1',
  String systemId = 'Tokyo_Koto',
  String status = 'borrowed',
  String title = 'a',
  String? dueOn,
  String? pickupDueOn,
  String? reservedOn,
  String? urgency,
  String? updatedAtUtc,
}) => LoanReportItem(
  loanId: loanId,
  bookId: 'b',
  systemId: systemId,
  systemName: '江東',
  pref: '東京都',
  city: '江東区',
  status: status,
  title: title,
  bookAvailable: true,
  authors: const [],
  configured: true,
  dueOn: dueOn,
  pickupDueOn: pickupDueOn,
  reservedOn: reservedOn,
  urgency: urgency,
  updatedAtUtc: updatedAtUtc,
);

void main() {
  group('間近の上限日', () {
    test('基準日の8日後を返す。曜日に関わらず開いた日から数える', () {
      expect(soonLimitOn('2026-09-19'), equals('2026-09-27')); // 土
      expect(soonLimitOn('2026-09-20'), equals('2026-09-28')); // 日
      expect(soonLimitOn('2026-09-14'), equals('2026-09-22'));
    });

    test('月・年をまたぐ', () {
      expect(soonLimitOn('2026-09-28'), equals('2026-10-06'));
      expect(soonLimitOn('2026-12-28'), equals('2027-01-05'));
    });

    test('壊れた基準日はそのまま返す。一覧を落とさない', () {
      expect(soonLimitOn(''), equals(''));
      expect(soonLimitOn('2026-09'), equals('2026-09'));
    });
  });

  group('受取と返却間近の判定', () {
    const limit = '2026-09-27';

    test('貸出中は上限日ちょうどは入り、翌日は入らない', () {
      expect(isPickupOrDueSoon(item(dueOn: limit), limit), isTrue);
      expect(isPickupOrDueSoon(item(dueOn: '2026-09-28'), limit), isFalse);
    });

    test('下限は無い。何年前の期限でも必ず入る', () {
      expect(isPickupOrDueSoon(item(dueOn: '2020-01-01'), limit), isTrue);
    });

    test('取置中は取置期限が遠くても、期限が無くても入る', () {
      expect(
        isPickupOrDueSoon(
          item(status: 'ready_for_pickup', pickupDueOn: '2026-12-28'),
          limit,
        ),
        isTrue,
      );
      expect(
        isPickupOrDueSoon(item(status: 'ready_for_pickup'), limit),
        isTrue,
      );
    });

    test('予約中は入らない', () {
      expect(
        isPickupOrDueSoon(
          item(status: 'reserved', reservedOn: '2020-01-01'),
          limit,
        ),
        isFalse,
      );
      expect(deadlineOf(item(status: 'reserved')), isNull);
    });
  });

  group('フィルタ3種', () {
    const limit = '2026-09-27';
    final reserved = item(status: 'reserved', reservedOn: '2026-09-01');
    final ready = item(status: 'ready_for_pickup', pickupDueOn: '2026-09-18');
    final borrowedSoon = item(dueOn: '2026-09-26');
    final readyFar = item(
      status: 'ready_for_pickup',
      pickupDueOn: '2026-12-01',
    );
    final borrowedLater = item(dueOn: '2026-10-30');

    test('受取と返却間近は、取置中の全件と期限の近い貸出中。予約中は入らない', () {
      expect(matchesFilter(readyFar, LendingFilter.soon, limit), isTrue);
      expect(matchesFilter(borrowedSoon, LendingFilter.soon, limit), isTrue);
      expect(matchesFilter(borrowedLater, LendingFilter.soon, limit), isFalse);
      expect(matchesFilter(reserved, LendingFilter.soon, limit), isFalse);
    });

    test('予約中は予約中だけ', () {
      expect(matchesFilter(reserved, LendingFilter.reserved, limit), isTrue);
      expect(matchesFilter(ready, LendingFilter.reserved, limit), isFalse);
    });

    test('全件は3状態すべてを通す', () {
      for (final each in [reserved, ready, borrowedLater]) {
        expect(matchesFilter(each, LendingFilter.all, limit), isTrue);
      }
    });
  });

  group('期限切れ', () {
    test('判定は台帳側の urgency をそのまま使う', () {
      expect(isOverdue(item(urgency: 'overdue')), isTrue);
      expect(isOverdue(item(urgency: 'due_soon')), isFalse);
      expect(isOverdue(item()), isFalse);
    });

    test('専用のフィルタは無い。受取と返却間近に必ず含まれる', () {
      final overdue = item(dueOn: '2026-01-01', urgency: 'overdue');
      expect(isPickupOrDueSoon(overdue, '2026-09-27'), isTrue);
      expect(LendingFilter.values, hasLength(3));
    });
  });

  group('行の並び', () {
    test('取置中 → 貸出中 → 予約中 の順である', () {
      final rows = [
        item(loanId: 'c', status: 'reserved', reservedOn: '2026-01-01'),
        item(loanId: 'b', dueOn: '2026-09-30'),
        item(
          loanId: 'a',
          status: 'ready_for_pickup',
          pickupDueOn: '2026-12-31',
        ),
      ]..sort(compareLoanItems);
      expect(rows.map((i) => i.loanId), equals(['a', 'b', 'c']));
    });

    test('同じ状態では期限の早い順である', () {
      final rows = [
        item(loanId: 'late', dueOn: '2026-10-01'),
        item(loanId: 'early', dueOn: '2026-09-01'),
      ]..sort(compareLoanItems);
      expect(rows.map((i) => i.loanId), equals(['early', 'late']));
    });

    test('期限も題も同じなら loanId で決めきる', () {
      final rows = [
        item(loanId: 'z', dueOn: '2026-09-01'),
        item(loanId: 'a', dueOn: '2026-09-01'),
      ]..sort(compareLoanItems);
      expect(rows.map((i) => i.loanId), equals(['a', 'z']));
    });

    test('期限の無い予約中は予約日で並ぶ', () {
      final rows = [
        item(loanId: 'new', status: 'reserved', reservedOn: '2026-09-10'),
        item(loanId: 'old', status: 'reserved', reservedOn: '2026-08-10'),
      ]..sort(compareLoanItems);
      expect(rows.map((i) => i.loanId), equals(['old', 'new']));
    });

    /// 館サイトは予約日の中を予約した順に出す。館サイトの並びの順に予約日を直せば、直した
    /// 時刻がその順を写す。**題の順ではない。**
    test('同じ予約日の予約中は書いた時刻の早い順である', () {
      final rows = [
        item(
          loanId: 'a',
          status: 'reserved',
          title: 'a',
          reservedOn: '2026-10-19',
          updatedAtUtc: '2026-10-20T01:00:03Z',
        ),
        item(
          loanId: 'b',
          status: 'reserved',
          title: 'b',
          reservedOn: '2026-10-19',
          updatedAtUtc: '2026-10-20T01:00:01Z',
        ),
        item(
          loanId: 'c',
          status: 'reserved',
          title: 'c',
          reservedOn: '2026-10-19',
          updatedAtUtc: '2026-10-20T01:00:02Z',
        ),
      ]..sort(compareLoanItems);
      expect(rows.map((i) => i.loanId), equals(['b', 'c', 'a']));
    });

    test('期限で並ぶ状態は書いた時刻を見ない。題で決める', () {
      final rows = [
        item(
          loanId: 'a',
          title: 'a',
          dueOn: '2026-10-28',
          updatedAtUtc: '2026-10-20T02:00:00Z',
        ),
        item(
          loanId: 'b',
          title: 'b',
          dueOn: '2026-10-28',
          updatedAtUtc: '2026-10-20T01:00:00Z',
        ),
      ]..sort(compareLoanItems);
      expect(rows.map((i) => i.loanId), equals(['a', 'b']));
    });
  });

  group('管理区分の並び', () {
    const limit = '2026-09-27';

    LendingArea area(
      String id,
      String pref,
      String name, {
      bool ok = true,
      List<LoanReportItem> items = const [],
    }) => LendingArea.ofItems(
      systemId: id,
      pref: pref,
      name: name,
      configured: ok,
      items: items,
      limit: limit,
    );

    List<String> order(List<LendingArea> areas) =>
        ([...areas]..sort(compareLendingAreas)).map((a) => a.systemId).toList();

    /// **`compareLibrarySystems`（図書館一覧）と同じ比較である。** 対応度が同じ館の最後の
    /// 決め手で、素の `String.compareTo`（符号位置順）。読みの順ではない。
    test('同じ対応度・期限なら 都道府県 → 名称 → id', () {
      final due = [item(dueOn: '2026-09-20')];
      expect(
        order([
          area('Tokyo_Koto', '東京都', '江東区立図書館', items: due),
          area('Chiba_Ichikawa', '千葉県', '市川市立図書館', items: due),
          area('Tokyo_Adachi', '東京都', '足立区立図書館', items: due),
        ]),
        equals(['Chiba_Ichikawa', 'Tokyo_Koto', 'Tokyo_Adachi']),
      );
    });

    test('台帳から消えたシステムは後ろへ回る', () {
      expect(
        order([
          area(
            'Gone',
            '',
            '削除済み',
            ok: false,
            items: [item(status: 'ready_for_pickup')],
          ),
          area('Tokyo_Koto', '東京都', '江東区立図書館'),
        ]).first,
        equals('Tokyo_Koto'),
      );
    });

    test('対象が0件の館は最後である', () {
      expect(
        order([
          area('Empty', '東京都', 'あ'),
          area('Busy', '東京都', 'ん', items: [item(dueOn: '2026-09-26')]),
        ]),
        equals(['Busy', 'Empty']),
      );
    });

    test('対応度の高い館が先: 期限切れ → 取置中 → 返却間近 → 余裕 → 予約中', () {
      expect(
        order([
          area(
            'reserved',
            '東京都',
            'a',
            items: [item(status: 'reserved', reservedOn: '2026-01-01')],
          ),
          area('later', '東京都', 'b', items: [item(dueOn: '2026-10-30')]),
          area('soon', '東京都', 'c', items: [item(dueOn: '2026-09-26')]),
          area(
            'ready',
            '東京都',
            'd',
            items: [
              item(status: 'ready_for_pickup', pickupDueOn: '2026-12-01'),
            ],
          ),
          area(
            'overdue',
            '東京都',
            'e',
            items: [item(dueOn: '2026-09-01', urgency: 'overdue')],
          ),
        ]),
        equals(['overdue', 'ready', 'soon', 'later', 'reserved']),
      );
    });

    test('館の対応度は出す行の最小値である', () {
      expect(
        order([
          area(
            'mixed',
            '東京都',
            'b',
            items: [
              item(dueOn: '2026-10-30'),
              item(status: 'ready_for_pickup', pickupDueOn: '2026-12-01'),
            ],
          ),
          area('soon', '東京都', 'a', items: [item(dueOn: '2026-09-26')]),
        ]),
        equals(['mixed', 'soon']),
      );
    });

    test('対応度が同じなら最も早い期限の館が先', () {
      expect(
        order([
          area('b', '東京都', 'a', items: [item(dueOn: '2026-09-25')]),
          area('a', '東京都', 'b', items: [item(dueOn: '2026-09-21')]),
        ]),
        equals(['a', 'b']),
      );
    });
  });
}
