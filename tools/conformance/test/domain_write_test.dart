/// 業務の書込み。**実 DB に対して測る。モック集約ではない。**
///
/// 業務が書くたびに、集約行・`outbox_events`・`applied_events`・`domain_events` が**同一
/// トランザクションで**確定していること、`written_by_app` に `bops` が押印されていること、
/// `entityId` が業務キーから決定的に導かれていることを見る。
///
/// **これは業務の規則の試験である。** 同期の側（判定表・LWW・世代）は別の試験が持つ。ここが
/// 答えるのは「業務が正しい形の封筒を、正しい版で、正しい id に対して積むか」だけである。
library;

import 'package:conformance/src/harness.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:test/test.dart';

const String t0 = '2026-08-04T09:00:00Z';
const String t1 = '2026-08-05T09:00:00Z';
const String t2 = '2026-08-06T09:00:00Z';

const String isbn = '9784274226298';

/// 正本の `contracts.ids.deterministic_id('book', '9784274226298')` が返す値。
const String bookIdForIsbn = 'e963a313-5ec4-510e-8811-0eb06ed5690a';

LibrarySystem minato({List<Branch>? branches}) => LibrarySystem(
      id: 'Tokyo_Minato',
      pref: '東京都',
      city: '港区',
      name: '港区立図書館',
      branches: branches ??
          const [
            Branch(id: 'minato-main', calilLibkey: '港区中央', name: '中央館'),
            Branch(id: 'minato-mita', calilLibkey: '港区三田', name: '三田館'),
          ],
    );

void main() {
  late Harness harness;
  late Device device;

  setUp(() {
    harness = Harness.create(Contracts.load(), prefix: 'karita-domain-');
    device = harness.device('windows-a', now: t0);
  });
  tearDown(() => harness.dispose());

  int rows(String table) =>
      device.db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;

  Map<String, Object?> outboxRow(String eventId) =>
      device.db.select('SELECT * FROM outbox_events WHERE event_id = ?',
          [eventId]).first;

  group('Book の採用', () {
    test('集約・outbox・applied・業務記録が同時に立つ', () {
      final event = device.books.adopt(
        title: '達人プログラマー',
        authors: const ['David Thomas', 'Andrew Hunt'],
        isbn13: isbn,
        publisher: 'オーム社',
        sourceUrl: 'https://books.example.invalid/item/$isbn',
        provider: 'rakuten',
        now: t0,
      );

      expect(event.entityType, equals(entityBook));
      expect(event.baseVersion, equals(0));
      expect(event.resultVersion, equals(1));
      expect(rows('books'), equals(1));
      expect(rows('outbox_events'), equals(1));
      expect(rows('applied_events'), equals(1),
          reason: 'outbox と applied は二つで一組である');
      expect(rows('domain_events'), equals(1));

      final book = device.domain.aggregates
          .read(device.db, entityBook, event.entityId)!;
      expect(book['title'], equals('達人プログラマー'));
      expect(book['isbn13'], equals(isbn));
      expect(book['version'], equals(1));
      expect(book['updated_by_device_id'], equals(device.deviceId));
    });

    test('bookId は ISBN から決定的に導く', () {
      // **二端末が同じ ISBN を独立に採用しても同じ id になる。** そうして初めて二重登録が
      // 競合として立ち、LWW が一件へ収束させる。
      final event = device.books.adopt(
        title: '達人プログラマー',
        authors: const [],
        isbn13: isbn,
        provider: 'rakuten',
        now: t0,
      );
      expect(event.entityId, equals(bookIdForIsbn));
      expect(event.entityId, equals(deterministicId(entityBook, isbn)));
    });

    test('written_by_app に bops が押される', () {
      final event = device.books.adopt(
        title: 'a', authors: const [], isbn13: isbn,
        provider: 'rakuten', now: t0);
      expect(outboxRow(event.eventId)['written_by_app'], equals(appBops));
      expect(outboxRow(event.eventId)['state'], equals(outboxPending),
          reason: '業務が積むのは pending だけである');
      expect(ownershipViolations(device.db), isEmpty);
    });

    test('同じ ISBN の二度目は落ちる', () {
      device.books.adopt(
          title: 'a', authors: const [], isbn13: isbn,
          provider: 'rakuten', now: t0);
      expect(
          () => device.books.adopt(
              title: 'b', authors: const [], isbn13: isbn,
              provider: 'rakuten', now: t1),
          throwsA(isA<BookError>()
              .having((e) => e.code, 'code', 'book-exists')));
      expect(rows('books'), equals(1));
    });

    test('検証が先で採番が後である', () {
      // 形の崩れた ISBN から id を導くと、同じ本が表記ゆれの数だけ別の実体になる。
      for (final bad in ['', '123', '97842742262X8']) {
        expect(
            () => device.books.adopt(
                title: 'a', authors: const [], isbn13: bad,
                provider: 'rakuten', now: t0),
            throwsA(isA<BookError>()
                .having((e) => e.code, 'code', 'candidate')));
      }
      expect(
          () => device.books.adopt(
              title: '   ', authors: const [], isbn13: isbn,
              provider: 'rakuten', now: t0),
          throwsA(isA<BookError>()));
      expect(rows('outbox_events'), equals(0), reason: '落ちたら何も残らない');
    });

    test('出所は book_references に残る', () {
      final event = device.books.adopt(
        title: 'a', authors: const [], isbn13: isbn,
        sourceUrl: 'https://example.invalid/x', provider: 'rakuten', now: t0);
      final references = event.payload['book_references'] as List;
      expect(references.single,
          equals({'provider': 'rakuten', 'source_url': 'https://example.invalid/x'}));
    });
  });

  group('Loan の開始', () {
    String adoptBook() => device.books
        .adopt(
            title: 'a', authors: const [], isbn13: isbn,
            provider: 'rakuten', now: t0)
        .entityId;

    test('予約は受取館と予約日を持つ', () {
      final bookId = adoptBook();
      final event = device.loans.start(
        loanId: harness.uuid(),
        bookId: bookId,
        status: 'reserved',
        systemId: 'Tokyo_Minato',
        pickupLibraryId: 'minato-main',
        now: t0,
      );
      expect(event.payload['status'], equals('reserved'));
      expect(event.payload['pickup_library_id'], equals('minato-main'));
      expect(event.payload['reserved_on'], equals('2026-08-04'),
          reason: '操作日を省いたら now の日付を当てる');
    });

    test('借出は既定で14日後を返却期限にする', () {
      final bookId = adoptBook();
      final event = device.loans.start(
        loanId: harness.uuid(),
        bookId: bookId,
        status: 'borrowed',
        systemId: 'Tokyo_Minato',
        pickupLibraryId: 'minato-main',
        now: t0,
      );
      expect(event.payload['borrowed_on'], equals('2026-08-04'));
      expect(event.payload['due_on'], equals('2026-08-18'));
      // **貸出館は書かない。** 館は受取館の1つだけである（受取も返却も同じ窓口で行う）。
      // 列は読み取り互換のために残るが、新規書込みの経路はもう無い。
      expect(event.payload.containsKey('loan_library_id'), isFalse);
      expect(event.payload['pickup_library_id'], equals('minato-main'));
    });

    test('開始できるのは reserved と borrowed だけである', () {
      final bookId = adoptBook();
      for (final status in ['ready_for_pickup', 'returned', 'cancelled']) {
        expect(
            () => device.loans.start(
                loanId: harness.uuid(), bookId: bookId, status: status,
                systemId: 'Tokyo_Minato', pickupLibraryId: 'x', now: t0),
            throwsA(isA<LoanError>()
                .having((e) => e.code, 'code', 'start-status')));
      }
    });

    test('館の指定を欠くと落ちる', () {
      final bookId = adoptBook();
      expect(
          () => device.loans.start(
              loanId: harness.uuid(), bookId: bookId, status: 'reserved',
              systemId: 'Tokyo_Minato', now: t0),
          throwsA(isA<LoanError>()
              .having((e) => e.code, 'code', 'pickup-library')));
      // **借出開始も受取館を要る。** `貸出中` は受取館と返却期限を持つ。予約を経ずに直接
      // 借りた場合も、受け取った窓口は必ずある。
      expect(
          () => device.loans.start(
              loanId: harness.uuid(), bookId: bookId, status: 'borrowed',
              systemId: 'Tokyo_Minato', now: t0),
          throwsA(isA<LoanError>()
              .having((e) => e.code, 'code', 'pickup-library')));
    });

    test('借出は貸出館を要求しない', () {
      // 2026-09-10 に貸出館を廃止した（UI 仕様 screens/lending.md）。受取館さえあれば通る。
      final bookId = adoptBook();
      expect(
          () => device.loans.start(
              loanId: harness.uuid(), bookId: bookId, status: 'borrowed',
              systemId: 'Tokyo_Minato', pickupLibraryId: 'minato-main',
              now: t0),
          returnsNormally);
    });

    test('崩れた日付は落ちる', () {
      final bookId = adoptBook();
      for (final bad in ['2026-02-30', '2026-13-01', '20260804', '2026-8-4']) {
        expect(
            () => device.loans.start(
                loanId: harness.uuid(), bookId: bookId, status: 'reserved',
                systemId: 'Tokyo_Minato', pickupLibraryId: 'x',
                reservedOn: bad, now: t0),
            throwsA(isA<LoanError>().having((e) => e.code, 'code', 'date')),
            reason: '$bad が通ってしまう');
      }
    });
  });

  group('候補からの開始', () {
    test('採用と開始が一つのトランザクションで確定する', () {
      final loanId = harness.uuid();
      final event = device.loans.startFromCandidate(
        loanId: loanId,
        candidate: const BookCandidateInput(
          title: '達人プログラマー',
          authors: ['David Thomas'],
          isbn13: isbn,
          provider: 'rakuten',
        ),
        status: 'reserved',
        systemId: 'Tokyo_Minato',
        pickupLibraryId: 'minato-main',
        now: t0,
      );
      expect(rows('books'), equals(1));
      expect(rows('loans'), equals(1));
      expect(rows('outbox_events'), equals(2), reason: '採用と開始で2件');
      expect(event.payload['book_id'], equals(bookIdForIsbn),
          reason: 'bookId は Books が ISBN から導く。入口ごとに採番しない');
    });

    test('採用が落ちれば Loan も残らない', () {
      // **原子性の要である。** 採用だけが残ると、次の開始が「本はあるが Loan が無い」から
      // 始まり、二端末の同一性が入口によって変わる。
      device.books.adopt(
          title: 'a', authors: const [], isbn13: isbn,
          provider: 'rakuten', now: t0);
      expect(
          () => device.loans.startFromCandidate(
                loanId: harness.uuid(),
                candidate: const BookCandidateInput(
                    title: 'b', authors: [], isbn13: isbn, provider: 'rakuten'),
                status: 'reserved',
                systemId: 'Tokyo_Minato',
                pickupLibraryId: 'x',
                now: t1,
              ),
          throwsA(isA<BookError>()));
      expect(rows('loans'), equals(0));
      expect(rows('outbox_events'), equals(1), reason: '最初の採用の1件だけ');
    });

    test('Loan の側で落ちても採用が残らない', () {
      expect(
          () => device.loans.startFromCandidate(
                loanId: harness.uuid(),
                candidate: const BookCandidateInput(
                    title: 'a', authors: [], isbn13: isbn, provider: 'rakuten'),
                // 受取館を欠く予約。Loan の検証で落ちる。
                status: 'reserved',
                systemId: 'Tokyo_Minato',
                now: t0,
              ),
          throwsA(isA<LoanError>()));
      expect(rows('books'), equals(0), reason: '採用も巻き戻る');
      expect(rows('outbox_events'), equals(0));
    });
  });

  group('Loan の遷移', () {
    late String loanId;

    setUp(() {
      loanId = harness.uuid();
      device.books.adopt(
          title: 'a', authors: const [], isbn13: isbn,
          provider: 'rakuten', now: t0);
      device.loans.start(
        loanId: loanId,
        bookId: bookIdForIsbn,
        status: 'reserved',
        systemId: 'Tokyo_Minato',
        pickupLibraryId: 'minato-main',
        now: t0,
      );
    });

    test('予約 → 取置 → 借出 → 返却が通り、版が1つずつ上がる', () {
      final ready =
          device.loans.update(loanId: loanId, action: 'ready-for-pickup', now: t1);
      expect(ready.payload['status'], equals('ready_for_pickup'));
      expect(ready.baseVersion, equals(1));
      expect(ready.resultVersion, equals(2));
      expect(ready.payload['pickup_due_on'], equals('2026-08-12'),
          reason: '取置は既定で7日');

      // **貸出館を渡さない。** 受取館は予約のときに入っており、行から引き継がれる。
      final borrowed =
          device.loans.update(loanId: loanId, action: 'borrow', now: t2);
      expect(borrowed.payload['status'], equals('borrowed'));
      expect(borrowed.payload['pickup_library_id'], equals('minato-main'));
      expect(borrowed.resultVersion, equals(3));
      expect(borrowed.payload['due_on'], equals('2026-08-20'));

      final returned =
          device.loans.update(loanId: loanId, action: 'return', now: t2);
      expect(returned.payload['status'], equals('returned'));
      expect(returned.resultVersion, equals(4));
      expect(returned.payload['returned_on'], equals('2026-08-06'));
    });

    /// **前状態は問わない**（2026-09-19 改定）。許された遷移という概念を業務層から落とした。
    /// 書くのは利用者が館サイトで確認した事実であって、アプリの側に「その順でしか起こらない
    /// はず」と言える根拠が無い。
    test('どの状態からどの状態へでも書ける', () {
      // 予約中へいきなり返却済みを当てる。以前は invalid-transition で落ちていた。
      final returned =
          device.loans.update(loanId: loanId, action: 'return', now: t1);
      expect(returned.payload['status'], equals('returned'));
      expect(returned.payload['returned_on'], equals('2026-08-05'));

      // 返却済みから貸出中へ戻す。
      final back =
          device.loans.update(loanId: loanId, action: 'borrow', now: t2);
      expect(back.payload['status'], equals('borrowed'));

      // 貸出中から予約中へ戻す。**`reserve` はこの改定で足した操作である。**
      final again =
          device.loans.update(loanId: loanId, action: 'reserve', now: t2);
      expect(again.payload['status'], equals('reserved'));
      expect(again.payload['reserved_on'], equals('2026-08-04'),
          reason: '開始時の予約日を動かさない');
    });

    test('取消済みからも書き直せる', () {
      device.loans.update(loanId: loanId, action: 'cancel', now: t1);
      expect(
          device.loans
              .update(loanId: loanId, action: 'ready-for-pickup', now: t2)
              .payload['status'],
          equals('ready_for_pickup'));
    });

    test('未知の操作は落ちる', () {
      expect(
          () => device.loans.update(loanId: loanId, action: 'teleport', now: t1),
          throwsA(isA<LoanError>()
              .having((e) => e.code, 'code', 'loan-action')));
    });

    test('無い Loan は落ちる', () {
      expect(
          () => device.loans
              .update(loanId: harness.uuid(), action: 'return', now: t1),
          throwsA(isA<LoanError>()
              .having((e) => e.code, 'code', 'loan-not-found')));
    });

    test('取消は予約からも取置からも通る', () {
      final cancelled =
          device.loans.update(loanId: loanId, action: 'cancel', now: t1);
      expect(cancelled.payload['status'], equals('cancelled'));
      expect(cancelled.payload['cancelled_on'], equals('2026-08-05'));
    });


    test('取置期限の訂正は状態も取置開始日も動かさない', () {
      device.loans.update(
          loanId: loanId,
          action: 'ready-for-pickup',
          operationOn: '2026-08-05',
          now: t1);
      final fixed = device.loans.update(
          loanId: loanId,
          action: 'correct-pickup-due-date',
          pickupDueOn: '2026-08-15',
          now: t2);
      expect(fixed.payload['status'], equals('ready_for_pickup'));
      expect(fixed.payload['pickup_due_on'], equals('2026-08-15'));
      expect(fixed.payload['pickup_available_on'], equals('2026-08-05'),
          reason: '起点は動かさない');
    });

    test('取置期限の訂正の既定は取置開始から7日である。操作日ではない', () {
      device.loans.update(
          loanId: loanId,
          action: 'ready-for-pickup',
          operationOn: '2026-08-05',
          now: t1);
      final fixed = device.loans
          .update(loanId: loanId, action: 'correct-pickup-due-date', now: t2);
      expect(fixed.payload['pickup_due_on'], equals('2026-08-12'));
    });

    /// 取置期限の訂正は**行き先が `ready_for_pickup` である。** 前状態を見ないので、貸出中の
    /// 行に当てれば取置中へ戻る。区別は操作の名前だけが持つ。
    test('取置期限の訂正は行き先を取置中にする', () {
      device.loans.update(loanId: loanId, action: 'borrow', now: t1);
      final fixed = device.loans.update(
          loanId: loanId,
          action: 'correct-pickup-due-date',
          pickupDueOn: '2026-08-20',
          now: t2);
      expect(fixed.payload['status'], equals('ready_for_pickup'));
      expect(fixed.payload['pickup_due_on'], equals('2026-08-20'));
    });
    test('遷移の業務記録が残る', () {
      device.loans.update(loanId: loanId, action: 'ready-for-pickup', now: t1);
      final kinds = device.db
          .select('SELECT event_type FROM domain_events ORDER BY occurred_at_utc')
          .map((row) => row['event_type'])
          .toList();
      expect(kinds,
          equals([adoptionEventType, 'LoanReserved', 'LoanReadyForPickup']));
    });
  });

  group('受取館の訂正', () {
    late String loanId;

    setUp(() {
      loanId = harness.uuid();
      device.books.adopt(
          title: 'a', authors: const [], isbn13: isbn,
          provider: 'rakuten', now: t0);
      device.loans.start(
        loanId: loanId,
        bookId: bookIdForIsbn,
        status: 'reserved',
        systemId: 'Tokyo_Minato',
        pickupLibraryId: 'minato-main',
        now: t0,
      );
    });

    test('状態も日付も動かさず、館だけが変わる', () {
      final moved = device.loans.correctPickupLibrary(
          loanId: loanId, pickupLibraryId: 'minato-mita', now: t1);
      expect(moved.payload['pickup_library_id'], equals('minato-mita'));
      expect(moved.payload['status'], equals('reserved'),
          reason: '訂正は遷移ではない');
      expect(moved.payload['reserved_on'], equals('2026-08-04'),
          reason: '予約日は操作日で上書きしない');
      expect(moved.baseVersion, equals(1));
      expect(moved.resultVersion, equals(2));
    });

    test('取置中・貸出中でも通る', () {
      device.loans.update(loanId: loanId, action: 'ready-for-pickup', now: t1);
      expect(
          device.loans
              .correctPickupLibrary(
                  loanId: loanId, pickupLibraryId: 'minato-mita', now: t1)
              .payload['status'],
          equals('ready_for_pickup'));
      device.loans.update(loanId: loanId, action: 'borrow', now: t2);
      final borrowed = device.loans.correctPickupLibrary(
          loanId: loanId, pickupLibraryId: 'minato-main', now: t2);
      expect(borrowed.payload['status'], equals('borrowed'));
      expect(borrowed.payload['pickup_library_id'], equals('minato-main'));
      expect(borrowed.payload['due_on'], equals('2026-08-20'),
          reason: '返却期限は訂正で動かない');
    });

    /// **状態を見ない**（2026-09-19 改定）。状態そのものを自由に書き直せる以上、受取館だけを
    /// 縛る理由が無い。返却済みの行の館名が違っていれば直せる。
    test('終端の Loan でも直せる', () {
      device.loans.update(loanId: loanId, action: 'return', now: t1);
      final moved = device.loans.correctPickupLibrary(
          loanId: loanId, pickupLibraryId: 'minato-mita', now: t2);
      expect(moved.payload['pickup_library_id'], equals('minato-mita'));
      expect(moved.payload['status'], equals('returned'), reason: '状態は動かない');
    });

    test('空の受取館は落ちる', () {
      expect(
          () => device.loans.correctPickupLibrary(
              loanId: loanId, pickupLibraryId: '', now: t1),
          throwsA(isA<LoanError>()
              .having((e) => e.code, 'code', 'pickup-library')));
      expect(rows('outbox_events'), equals(2), reason: '採用と開始の2件のまま');
    });

    test('無い Loan は落ちる', () {
      expect(
          () => device.loans.correctPickupLibrary(
              loanId: harness.uuid(), pickupLibraryId: 'minato-mita', now: t1),
          throwsA(isA<LoanError>()
              .having((e) => e.code, 'code', 'loan-not-found')));
    });

    test('分館がそのシステムに在るかはここでは見ない。突き合わせは合成層である', () {
      final moved = device.loans.correctPickupLibrary(
          loanId: loanId, pickupLibraryId: 'chuo-main', now: t1);
      expect(moved.payload['pickup_library_id'], equals('chuo-main'));
    });

    test('業務記録は LoanPickupLibraryCorrected である', () {
      device.loans.correctPickupLibrary(
          loanId: loanId, pickupLibraryId: 'minato-mita', now: t1);
      final kinds = device.db
          .select('SELECT event_type FROM domain_events ORDER BY occurred_at_utc')
          .map((row) => row['event_type'])
          .toList();
      expect(kinds,
          equals([adoptionEventType, 'LoanReserved', 'LoanPickupLibraryCorrected']));
    });
  });

  group('棚卸完了', () {
    test('entityId は system_id から決定的に導く', () {
      // **端末ごとの事実ではない。** 二端末が別々に棚卸を完了しても同じ id を指す。
      final event =
          device.memberships.completePatrol(systemId: 'Tokyo_Minato', now: t0);
      expect(event.entityId,
          equals(deterministicId(entityLibraryMembership, 'Tokyo_Minato')));
      expect(device.memberships.lastReconciledAtUtc('Tokyo_Minato'), equals(t0));
    });

    test('二度目は版を上げて上書きする', () {
      device.memberships.completePatrol(systemId: 'Tokyo_Minato', now: t0);
      final second =
          device.memberships.completePatrol(systemId: 'Tokyo_Minato', now: t1);
      expect(second.baseVersion, equals(1));
      expect(second.resultVersion, equals(2));
      expect(device.memberships.lastReconciledAtUtc('Tokyo_Minato'), equals(t1),
          reason: '後から棚卸した側が勝つ');
      expect(rows('library_memberships'), equals(1));
    });

    test('記録の無いシステムは null', () {
      expect(device.memberships.lastReconciledAtUtc('Tokyo_Chuo'), isNull);
    });
  });

  group('図書館システム', () {
    test('登録すると分館が payload の配列に入る', () {
      final event = device.librarySystems.register(system: minato(), now: t0);
      expect(event.entityId,
          equals(deterministicId(entityLibrarySystem, 'Tokyo_Minato')));
      final branches = event.payload['branches'] as List;
      expect(branches, hasLength(2), reason: '分館は独立集約にしない');

      final loaded = device.librarySystems.read('Tokyo_Minato')!;
      expect(loaded.name, equals('港区立図書館'));
      expect(loaded.branches.map((b) => b.id),
          equals(['minato-main', 'minato-mita']));
    });

    test('発行した payload と読み直した payload が一致する', () {
      // **LWW の第3キーは payloadHash である。** 食い違えば同じ内容が別物として競合する。
      final event = device.librarySystems.register(system: minato(), now: t0);
      final row = device.domain.aggregates
          .read(device.db, entityLibrarySystem, event.entityId)!;
      final readBack =
          device.domain.mapping.rowToPayload(entityLibrarySystem, row);
      expect(canonicalHash(readBack), equals(event.payloadHash));
    });

    test('洗い替えである。消した分館は残らない', () {
      device.librarySystems.register(system: minato(), now: t0);
      device.librarySystems.register(
          system: minato(branches: const [
            Branch(id: 'minato-main', calilLibkey: '港区中央', name: '中央館'),
          ]),
          now: t1);
      expect(device.librarySystems.read('Tokyo_Minato')!.branches, hasLength(1));
    });

    test('不変条件を満たさない登録は落ちる', () {
      expect(
          () => device.librarySystems.register(
              system: minato(branches: const []), now: t0),
          throwsA(isA<DomainError>()));
      expect(rows('outbox_events'), equals(0));
    });

    test('削除は tombstone を発行し、payload は system_id だけになる', () {
      device.librarySystems.register(system: minato(), now: t0);
      final removed =
          device.librarySystems.remove(systemId: 'Tokyo_Minato', now: t1);

      expect(removed.operation, equals(operationTombstone));
      expect(removed.payload, equals({'system_id': 'Tokyo_Minato'}),
          reason: '消えたものの中身を運ぶ意味がない');
      expect(device.librarySystems.read('Tokyo_Minato'), isNull);
      expect(device.librarySystems.load().librarySystems, isEmpty);
    });

    test('削除しても「触れたことがある」は 0 に戻らない', () {
      // 削除済みの図書館システムを黙って復活させないために要る。
      device.librarySystems.register(system: minato(), now: t0);
      device.librarySystems.remove(systemId: 'Tokyo_Minato', now: t1);
      expect(device.librarySystems.aggregateVersion('Tokyo_Minato'), equals(2));
    });

    test('無いものは削除できない', () {
      expect(
          () => device.librarySystems.remove(systemId: 'Tokyo_Chuo', now: t0),
          throwsA(isA<LibrarySystemError>()
              .having((e) => e.code, 'code', 'library-system-missing')));
    });

    test('参照する棚卸記録は数えるだけで消さない', () {
      // 参照整合性を同期層で強制しない — 片方で削除、もう片方で棚卸完了は正常に起こりうる。
      device.librarySystems.register(system: minato(), now: t0);
      device.memberships.completePatrol(systemId: 'Tokyo_Minato', now: t0);
      expect(device.librarySystems.referencingMemberships('Tokyo_Minato'),
          equals(1));
      device.librarySystems.remove(systemId: 'Tokyo_Minato', now: t1);
      expect(rows('library_memberships'), equals(1));
    });

    test('load は tombstone を含めず、system_id 順に並ぶ', () {
      device.librarySystems.register(system: minato(), now: t0);
      device.librarySystems.register(
          system: LibrarySystem(
            id: 'Tokyo_Chuo',
            pref: '東京都',
            city: '中央区',
            name: '中央区立図書館',
            branches: const [
              Branch(id: 'chuo-main', calilLibkey: '中央区中央', name: '中央館'),
            ],
          ),
          now: t0);
      expect(device.librarySystems.load().librarySystems.map((s) => s.id),
          equals(['Tokyo_Chuo', 'Tokyo_Minato']));
    });
  });

  group('図書館の設定', () {
    test('entityId は system_id と鍵から決定的に導く', () {
      // **鍵ごとに別の集約である。** 同じ集約に入れると、二端末が別々の鍵を変えたときに
      // LWW が payload 全体を差し替えて片方が消える。
      device.librarySystems.register(system: minato(), now: t0);
      final preferred = device.librarySettings.setPreferredBranch(
          systemId: 'Tokyo_Minato', branchId: 'minato-main', now: t0);
      final mypage = device.librarySettings.setMypageUrl(
          systemId: 'Tokyo_Minato',
          url: 'https://example.invalid/login',
          checkedOn: '2026-09-15',
          now: t0);

      expect(
          preferred.entityId,
          equals(deterministicId(
              entityLibrarySetting, 'Tokyo_Minato/preferred_branch')));
      expect(
          mypage.entityId,
          equals(deterministicId(
              entityLibrarySetting, 'Tokyo_Minato/mypage_url')));
      expect(preferred.entityId, isNot(equals(mypage.entityId)));
    });

    test('片方を変えても、もう片方は版も値も動かない', () {
      // **これが 0011 を入れた理由そのものである。**
      device.librarySystems.register(system: minato(), now: t0);
      device.librarySettings.setPreferredBranch(
          systemId: 'Tokyo_Minato', branchId: 'minato-main', now: t0);
      final mypage = device.librarySettings.setMypageUrl(
          systemId: 'Tokyo_Minato',
          url: 'https://example.invalid/login',
          checkedOn: '2026-09-15',
          now: t0);
      final before = device.domain.aggregates
          .read(device.db, entityLibrarySetting, mypage.entityId)!;

      device.librarySettings.setPreferredBranch(
          systemId: 'Tokyo_Minato', branchId: 'minato-mita', now: t1);

      final after = device.domain.aggregates
          .read(device.db, entityLibrarySetting, mypage.entityId)!;
      expect(after['version'], equals(before['version']));
      expect(after['value'], equals('https://example.invalid/login'));
      expect(
          device.librarySettings.valueOf('Tokyo_Minato', settingPreferredBranch),
          equals('minato-mita'));
    });

    test('発行した payload と読み直した payload が一致する', () {
      device.librarySystems.register(system: minato(), now: t0);
      final event = device.librarySettings.setMypageUrl(
          systemId: 'Tokyo_Minato',
          url: 'https://example.invalid/login',
          checkedOn: '2026-09-15',
          now: t0);
      final row = device.domain.aggregates
          .read(device.db, entityLibrarySetting, event.entityId)!;
      final readBack =
          device.domain.mapping.rowToPayload(entityLibrarySetting, row);
      expect(canonicalHash(readBack), equals(event.payloadHash));
    });

    test('常用館は分館に在ることを要求する。カタログ側は見ない', () {
      device.librarySystems.register(system: minato(), now: t0);
      expect(
          () => device.librarySettings.setPreferredBranch(
              systemId: 'Tokyo_Minato', branchId: '港区中央', now: t0),
          throwsA(isA<DomainError>()),
          reason: 'calil_libkey を入れたらここで落ちる');
      expect(
          () => device.librarySettings.setPreferredBranch(
              systemId: 'Tokyo_Edogawa', branchId: 'x', now: t0),
          throwsA(isA<DomainError>()),
          reason: '未登録のシステムには設定できない');
    });

    test('解除は tombstone で、payload は system_id と鍵だけになる', () {
      device.librarySystems.register(system: minato(), now: t0);
      device.librarySettings.setPreferredBranch(
          systemId: 'Tokyo_Minato', branchId: 'minato-main', now: t0);

      final removed = device.librarySettings
          .clearPreferredBranch(systemId: 'Tokyo_Minato', now: t1);

      expect(removed.operation, equals(operationTombstone));
      expect(removed.payload,
          equals({'system_id': 'Tokyo_Minato', 'key': 'preferred_branch'}));
      expect(device.librarySettings.read('Tokyo_Minato', settingPreferredBranch),
          isNull);
      // **行は消さない。** 消すと「解除が届いた」と「まだ届いていない」を区別できない。
      expect(
          device.db.select(
              'SELECT is_deleted FROM library_settings').single['is_deleted'],
          equals(1));
    });

    test('load は tombstone を含めず、system_id と鍵の順に並ぶ', () {
      device.librarySystems.register(system: minato(), now: t0);
      device.librarySystems.register(
          system: LibrarySystem(
            id: 'Tokyo_Koto',
            pref: '東京都',
            city: '江東区',
            name: '江東区立図書館',
            branches: const [
              Branch(id: 'koto-main', calilLibkey: '江東中央', name: '中央館'),
            ],
          ),
          now: t0);
      device.librarySettings.setPreferredBranch(
          systemId: 'Tokyo_Minato', branchId: 'minato-main', now: t0);
      device.librarySettings.setMypageUrl(
          systemId: 'Tokyo_Koto',
          url: 'https://example.invalid/koto',
          checkedOn: '2026-09-15',
          now: t0);
      device.librarySettings.setPreferredBranch(
          systemId: 'Tokyo_Koto', branchId: 'koto-main', now: t0);
      device.librarySettings
          .clearPreferredBranch(systemId: 'Tokyo_Minato', now: t1);

      expect(
          device.librarySettings.load().map((s) => '${s.systemId}/${s.key}'),
          equals(['Tokyo_Koto/mypage_url', 'Tokyo_Koto/preferred_branch']));
    });

    test('分館が消えた常用館は残る。拾うのは doctor の側である', () {
      // **同期で届いた行は登録経路の検査を通らない。** 分館を消した端末と常用館を設定した
      // 端末が独立に書けば、参照の切れた設定は正常に適用されうる。
      device.librarySystems.register(system: minato(), now: t0);
      device.librarySettings.setPreferredBranch(
          systemId: 'Tokyo_Minato', branchId: 'minato-mita', now: t0);
      device.librarySystems.register(
          system: minato(branches: const [
            Branch(id: 'minato-main', calilLibkey: '港区中央', name: '中央館'),
          ]),
          now: t1);

      expect(
          device.librarySettings.valueOf('Tokyo_Minato', settingPreferredBranch),
          equals('minato-mita'),
          reason: 'カタログの洗い替えは利用者値に触れない');
      expect(
          device.librarySettings
              .danglingPreferredBranches()
              .map((s) => s.systemId),
          equals(['Tokyo_Minato']));
    });

    test('マイページURLは確認日を持つ。常用館は持たない', () {
      device.librarySystems.register(system: minato(), now: t0);
      device.librarySettings.setMypageUrl(
          systemId: 'Tokyo_Minato',
          url: 'https://example.invalid/login',
          checkedOn: '2026-09-15',
          now: t0);
      device.librarySettings.setPreferredBranch(
          systemId: 'Tokyo_Minato', branchId: 'minato-main', now: t0);

      expect(
          device.librarySettings
              .read('Tokyo_Minato', settingMypageUrl)!
              .checkedOn,
          equals('2026-09-15'));
      expect(
          device.librarySettings
              .read('Tokyo_Minato', settingPreferredBranch)!
              .checkedOn,
          isNull);
    });
  });

  group('所有', () {
    test('業務が普通に書いただけでは違反にならない', () {
      device.books.adopt(
          title: 'a', authors: const [], isbn13: isbn,
          provider: 'rakuten', now: t0);
      device.librarySystems.register(system: minato(), now: t0);
      device.memberships.completePatrol(systemId: 'Tokyo_Minato', now: t0);
      expect(ownershipViolations(device.db), isEmpty);
    });

    test('生 SQL で同期テーブルへ書くと違反として出る', () {
      // **DB を共有すると、業務から同期テーブルへ SQL で書くことが物理的に可能になる。**
      // import の静的検査では捕まらない。押印の無い行がここに出る。
      device.db.execute(
        'INSERT INTO conflicts (conflict_id, entity_type, entity_id, '
        '  local_version, remote_event_id, remote_base_version, '
        '  remote_result_version, remote_envelope, state, detected_at_utc) '
        "VALUES ('c1', 'book', 'b1', 1, 'e1', 0, 1, '{}', 'open', ?)",
        [t0],
      );
      final violations = ownershipViolations(device.db);
      expect(violations.map((v) => v.table), contains('conflicts'));
      expect(violations.single.count, equals(1));
    });

    test('業務が pending 以外の outbox を書くと違反になる', () {
      // 業務に開けているのは pending の追記だけ。状態を動かすのは送信の責務である。
      final event = device.books.adopt(
          title: 'a', authors: const [], isbn13: isbn,
          provider: 'rakuten', now: t0);
      device.db.execute(
        'UPDATE outbox_events SET state = ? WHERE event_id = ?',
        [outboxUploaded, event.eventId],
      );
      expect(ownershipViolations(device.db).map((v) => v.table),
          contains('outbox_events'));
    });

    test('業務が origin=remote の適用を書くと違反になる', () {
      // 受信イベントの適用は同期の責務であり、業務が書いた時点で適用経路が二本になっている。
      device.db.execute(
        'INSERT INTO applied_events (event_id, entity_type, entity_id, '
        '  result_version, payload_hash, origin, applied_at_utc, written_by_app) '
        "VALUES ('e1', 'book', 'b1', 1, 'x', 'remote', ?, ?)",
        [t0, appBops],
      );
      expect(ownershipViolations(device.db).map((v) => v.table),
          contains('applied_events'));
    });
  });
}

/// payload の正準ハッシュ。封筒が持つものと同じ取り方でなければ意味がない。
String canonicalHash(Map<String, Object?> payload) => payloadHash(payload);
