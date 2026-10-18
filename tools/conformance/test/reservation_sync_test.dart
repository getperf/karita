import 'package:conformance/src/harness.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

void main() {
  test(
    'wanted preference travels through sync, clear, backup and restore',
    () async {
      final harness = Harness.create(
        Contracts.load(),
        prefix: 'reservation-sync-',
      );
      addTearDown(harness.dispose);
      const now = '2026-09-18T00:00:00Z';
      const later = '2026-09-18T00:01:00Z';
      final a = harness.device('windows-a', now: now);
      final b = harness.device('android-b', now: now);
      final book = ReservationBook(
        id: deterministicId(entityBook, '9784274219337'),
        isbn13: '9784274219337',
        title: '同期確認',
      );
      Reservations(a.domain).save(
        book: book,
        operationId: a.domain.uuid(),
        systems: [],
        wanted: true,
        reservedOn: '2026-09-18',
        now: now,
      );
      await a.engine.run(modeRun, now: now);
      await b.engine.restoreFromBaseline(now: now);
      expect(
        b.db
            .select('SELECT want_to_read FROM book_preferences')
            .single['want_to_read'],
        1,
      );
      const system = LibrarySystem(
        id: 'Tokyo_Koto',
        pref: '東京都',
        city: '江東区',
        name: '江東',
        branches: [Branch(id: 'main', calilLibkey: 'main', name: '中央')],
      );
      b.librarySystems.register(system: system, now: now);
      b.librarySettings.setPreferredBranch(
        systemId: system.id,
        branchId: 'main',
        now: now,
      );
      Reservations(b.domain).save(
        book: book,
        operationId: b.domain.uuid(),
        systems: [system.id],
        wanted: false,
        reservedOn: '2026-09-18',
        now: later,
      );
      final sent = await b.engine.run(modeRun, now: later);
      expect(sent.stopped, isEmpty);
      final received = await a.engine.run(modeRun, now: later);
      expect(received.report.invalid, 0, reason: '${received.report.events}');
      expect(received.report.pending, 0, reason: '${received.report.events}');
      expect(received.pullError, isNull);
      expect(
        a.db
            .select('SELECT want_to_read FROM book_preferences')
            .single['want_to_read'],
        0,
        reason:
            'sent=${sent.pushed}; events=${received.report.events}; '
            'b=${b.db.select("SELECT * FROM book_preferences")}; '
            'conflicts=${a.db.select("SELECT * FROM conflicts")}',
      );
      final path = '${harness.root.path}/reservation.blib';
      await a.engine.exportBackup(now: now, outPath: path);
      final c = harness.device('windows-c', now: now);
      await c.engine.restoreFromBackup(now: now, path: path);
      expect(
        c.db
            .select('SELECT want_to_read FROM book_preferences')
            .single['want_to_read'],
        0,
      );
      expect(c.db.select('SELECT * FROM loans'), hasLength(1));
    },
  );
}
