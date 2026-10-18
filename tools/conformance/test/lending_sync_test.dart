/// 貸出し画面の書込みが**端末をまたいで届く**こと。
///
/// 段階3 の書込みは2種類ある — [Loans.update] による遷移と、[Loans.correctPickupLibrary] に
/// よる受取館の訂正である。後者はこの段で足した操作で、**`domainEventType` を1つ増やしただけ**
/// であり封筒の版は上げていない。受信側がそれを素通しで適用できることは、増やした語彙を
/// 配る前に測っておく必要がある。
///
/// 見るのは3つ。遷移が届くこと、受取館の訂正が届くこと、そして**終端の Loan が
/// `readActiveLoans` から落ちる**こと（一覧の「終端行は次の更新で消える」の裏側）。
library;

import 'package:conformance/src/harness.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const LibrarySystem koto = LibrarySystem(
  id: 'Tokyo_Koto',
  pref: '東京都',
  city: '江東区',
  name: '江東区立図書館',
  branches: [
    Branch(id: 'koto-main', calilLibkey: '江東中央', name: '中央館'),
    Branch(id: 'koto-east', calilLibkey: '江東東陽', name: '東陽館'),
  ],
);

void main() {
  test('Loan の遷移と受取館の訂正が同期で往復する', () async {
    final harness = Harness.create(Contracts.load(), prefix: 'lending-sync-');
    addTearDown(harness.dispose);
    const now = '2026-09-19T00:00:00Z';
    const later = '2026-09-19T00:01:00Z';
    const latest = '2026-09-19T00:02:00Z';

    final a = harness.device('windows-a', now: now);
    final b = harness.device('android-b', now: now);

    a.librarySystems.register(system: koto, now: now);
    a.books.adopt(
      title: '棚卸の本',
      authors: const ['著者'],
      isbn13: '9784274219337',
      provider: 'rakuten',
      now: now,
    );
    final loanId = harness.uuid();
    a.loans.start(
      loanId: loanId,
      bookId: deterministicId(entityBook, '9784274219337'),
      status: 'reserved',
      systemId: koto.id,
      pickupLibraryId: 'koto-main',
      now: now,
    );
    await a.engine.run(modeRun, now: now);
    await b.engine.restoreFromBaseline(now: now);

    // **受け側で棚卸を続ける。** 館サイトを見ているのが手元の端末とは限らない。
    b.loans.update(loanId: loanId, action: 'ready-for-pickup', now: later);
    b.loans.correctPickupLibrary(
      loanId: loanId,
      pickupLibraryId: 'koto-east',
      now: later,
    );
    final sent = await b.engine.run(modeRun, now: later);
    expect(sent.stopped, isEmpty);

    final received = await a.engine.run(modeRun, now: later);
    expect(received.report.invalid, 0, reason: '${received.report.events}');
    expect(received.report.pending, 0, reason: '${received.report.events}');
    expect(received.pullError, isNull);

    final item = a.reporting
        .readActiveLoans(LibrariesConfig([koto]), asOf: '2026-09-19')
        .single;
    expect(item.loanId, equals(loanId));
    expect(item.status, equals('ready_for_pickup'));
    expect(item.pickupLibraryId, equals('koto-east'));
    expect(item.pickupLibraryName, equals('東陽館'), reason: '館名は受け側のカタログから引く');
    expect(item.pickupDueOn, equals('2026-09-26'), reason: '取置は既定で7日');

    // **終端にすると一覧から落ちる。** 画面が行を消すのではなく、読み口が返さなくなる。
    a.loans.update(loanId: loanId, action: 'cancel', now: latest);
    expect(
      a.reporting.readActiveLoans(LibrariesConfig([koto]), asOf: '2026-09-19'),
      isEmpty,
    );

    final back = await a.engine.run(modeRun, now: latest);
    expect(back.stopped, isEmpty);
    final applied = await b.engine.run(modeRun, now: latest);
    expect(applied.report.invalid, 0, reason: '${applied.report.events}');
    expect(
      b.db.select('SELECT status FROM loans').single['status'],
      equals('cancelled'),
    );
  });
}
