/// 起動時の業務fixture。外部応答の代替には使わない。
library;

import 'dart:convert';

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_handoff/karita_handoff.dart';

const defineDemoScenario = String.fromEnvironment(
  'KARITA_DEMO_SCENARIO',
  defaultValue: 'standard',
);

/// 業務APIから作るデモ台帳。本棚の読みたい・手動読書・レビューも含む。
class DemoFixture {
  final Map<String, dynamic> catalog;
  final DateTime baseDate;
  DemoFixture(String json, DateTime localDate)
    : catalog = jsonDecode(json) as Map<String, dynamic>,
      baseDate = DateTime.utc(localDate.year, localDate.month, localDate.day) {
    if (catalog['scenario'] != 'standard' || catalog['version'] != 1) {
      throw const FormatException('Unsupported demo fixture');
    }
    if (bookRows.length != 30 || libraryRows.length != 5) {
      throw const FormatException('Expected 30 books and 5 library systems');
    }
    final isbns = <String>{};
    for (final book in bookRows) {
      final isbn = book['isbn13'] as String;
      // **チェック桁の規則を写さない。** 受理規則は `karita_handoff` に1箇所だけ置くと決めた
      // （browser-handoff-implementation.md の決定 A）。fixture の検査も同じ関門を通す。
      if (normalizeIsbn13(isbn) != isbn ||
          !isbns.add(isbn) ||
          book['key'] != isbn ||
          (book['title'] as String).trim().isEmpty) {
        throw const FormatException('Invalid or duplicate demo book');
      }
    }
    final config = LibrariesConfig(systems);
    config.validate();
    if (systems.map((s) => s.id).toSet().difference(_systemIds).isNotEmpty) {
      throw const FormatException('Unexpected demo library system');
    }
  }

  static const _systemIds = {
    'Tokyo_Koto',
    'Tokyo_Minato',
    'Tokyo_Katsushika',
    'Tokyo_Edogawa',
    'Tokyo_Sumida',
  };
  List<Map<String, dynamic>> get bookRows =>
      (catalog['books'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get libraryRows =>
      (catalog['libraries'] as List).cast<Map<String, dynamic>>();
  List<LibrarySystem> get systems => [
    for (final row in libraryRows)
      LibrarySystem(
        id: row['systemid'] as String,
        pref: row['pref'] as String,
        city: row['city'] as String,
        name: row['name'] as String,
        homepageUrl: row['homepage_url'] as String,
        // **利用者値はここに無い**（`0011`）。JSONはカタログであり、常用館とマイページURLは
        // 下の `_settings` が業務入口を通して入れる。
        branches: [
          for (final branch in row['branches'] as List)
            Branch(
              id: branch['id'] as String,
              calilLibkey: branch['calil_libkey'] as String,
              name: branch['name'] as String,
            ),
        ],
      ),
  ];

  String on(int days) =>
      baseDate.add(Duration(days: days)).toIso8601String().substring(0, 10);
  String get baseOn => on(0);
  int get sunday => DateTime.sunday - baseDate.weekday;
  String bookId(int index) =>
      deterministicId(entityBook, bookRows[index]['isbn13'] as String);
  // Loanは利用ごとのID。ISBNによる同一性採番の対象ではない。
  String loanId(int index) =>
      'd36f92ec-fadc-4bca-8000-${(index + 1).toString().padLeft(12, '0')}';

  List<_LoanSeed> get _loans => [
    for (var i = 0; i < 5; i++) _LoanSeed(i, 'Tokyo_Koto', 'reserved'),
    _LoanSeed(5, 'Tokyo_Koto', 'ready_for_pickup', due: sunday),
    const _LoanSeed(6, 'Tokyo_Koto', 'borrowed', due: 1),
    _LoanSeed(7, 'Tokyo_Koto', 'borrowed', due: sunday + 1, branch: 1),
    const _LoanSeed(0, 'Tokyo_Koto', 'returned', age: -60),
    const _LoanSeed(0, 'Tokyo_Koto', 'returned', age: -40, branch: 1),
    const _LoanSeed(0, 'Tokyo_Minato', 'reserved'),
    const _LoanSeed(8, 'Tokyo_Minato', 'ready_for_pickup', due: -1),
    const _LoanSeed(9, 'Tokyo_Minato', 'borrowed', due: 0),
    _LoanSeed(10, 'Tokyo_Minato', 'borrowed', due: sunday, branch: 1),
    const _LoanSeed(0, 'Tokyo_Minato', 'returned', age: -20),
    const _LoanSeed(11, 'Tokyo_Minato', 'cancelled', age: -20),
    const _LoanSeed(12, 'Tokyo_Katsushika', 'reserved'),
    const _LoanSeed(13, 'Tokyo_Katsushika', 'cancelled', age: -20),
    const _LoanSeed(14, 'Tokyo_Edogawa', 'expired', age: -20),
  ];

  /// まだ終わっていない Loan の状態。**この3つが本棚の「読みたい」にも並ぶ。**
  static const _activeStatuses = {'reserved', 'ready_for_pickup', 'borrowed'};

  /// 常用館を入れる区。**墨田だけ未設定のままにする** — 未設定時の表示と誘導を確かめられる
  /// 唯一の場所である。値は各区の `branches[0]`。
  static const _preferredSystems = {
    'Tokyo_Koto',
    'Tokyo_Minato',
    'Tokyo_Katsushika',
    'Tokyo_Edogawa',
  };

  /// **江東だけ取り込み値を1件持たせる。**
  ///
  /// 出典は「保存値があるか」だけで決まるので、5区すべてに焼くと `既定値` の表示が一度も
  /// 出ない。逆に1件も置かないと `取り込み値` と `既定値に戻す` の有効状態が出ない。1件だけ
  /// 置くと2出典が同じ画面に並ぶ（`非公開資料:demo-fixture-format.md`）。
  ///
  /// **架空の利用者値である**（Loan や会員情報と同じ）。同梱の既定値表とは別物で、既定値を
  /// 取り込み値として焼いたものではない。
  static const _importedMypageSystem = 'Tokyo_Koto';
  static const _importedMypageUrl =
      'https://www.koto-lib.tokyo.jp/opw/OPW/OPWUSERINFO.CSP?DB=LIB';

  /// 呼出側が非公開の新DBを所有する。失敗したDBは丸ごと破棄する。
  ///
  /// [generations] は撒く時点で台帳が持っている同期世代の数である。**デモは0、検証モード（種）は1**
  /// — 種は初回起動の2択（`setupFresh`）が世代を作った後に撒く（2026-09-23 に順序を移した）。
  /// 0 に固定したままだと、30冊を書き込んだ直後に検証が必ず落ち、同期の契機まで届かない
  /// （2026-09-24 に実機で踏んだ）。
  DemoFixtureReport seed(
    DomainContext context, {
    required String now,
    int generations = 0,
  }) {
    final db = context.db;
    for (final table in [
      'books',
      'loans',
      'library_systems',
      'library_memberships',
      'library_settings',
      'outbox_events',
      'applied_events',
      'domain_events',
    ]) {
      if (db.select('SELECT 1 FROM $table LIMIT 1').isNotEmpty) {
        throw StateError('Demo fixture requires an empty ledger');
      }
    }
    final libraries = LibrarySystems(context);
    final settings = LibrarySettings(context);
    for (final system in systems) {
      libraries.register(system: system, now: now);
      Memberships(context).completePatrol(systemId: system.id, now: now);
      // **設定も業務入口を通す。** 集約行への直接INSERTを避けるのと同じ理由である。
      if (_preferredSystems.contains(system.id)) {
        settings.setPreferredBranch(
          systemId: system.id,
          branchId: system.branches.first.id,
          now: now,
        );
      }
      if (system.id == _importedMypageSystem) {
        settings.setMypageUrl(
          systemId: system.id,
          url: _importedMypageUrl,
          // 取り込み値の確認日は**利用者が取り込んだ日**である（既定値の採取日ではない）。
          checkedOn: baseOn,
          now: now,
        );
      }
    }
    final books = Books(context);
    for (final book in bookRows) {
      books.adopt(
        title: book['title'] as String,
        authors: (book['authors'] as List).cast<String>(),
        isbn13: book['isbn13'] as String,
        publisher: book['publisher'] as String,
        sourceUrl: book['source'] as String,
        provider: 'openbd',
        now: now,
      );
    }
    final loans = Loans(context);
    for (var i = 0; i < _loans.length; i++) {
      final seed = _loans[i];
      final system = systems.singleWhere((s) => s.id == seed.system);
      final borrowed = seed.status == 'borrowed' || seed.status == 'returned';
      loans.start(
        loanId: loanId(i),
        bookId: bookId(seed.book),
        status: borrowed ? 'borrowed' : 'reserved',
        systemId: seed.system,
        pickupLibraryId: system.branches[seed.branch].id,
        operationOn: on(seed.age),
        dueOn: on(seed.status == 'returned' ? seed.age + 14 : seed.due),
        now: now,
      );
      if (seed.status == 'ready_for_pickup' || seed.status == 'expired') {
        loans.update(
          loanId: loanId(i),
          action: 'ready-for-pickup',
          operationOn: on(seed.age + 1),
          pickupDueOn: on(seed.status == 'expired' ? seed.age + 7 : seed.due),
          now: now,
        );
      }
      final action = switch (seed.status) {
        'returned' => 'return',
        'cancelled' => 'cancel',
        'expired' => 'expire',
        _ => null,
      };
      if (action != null) {
        loans.update(
          loanId: loanId(i),
          action: action,
          operationOn: on(seed.age + 8),
          now: now,
        );
      }
    }
    final shelf = Bookshelf(context);
    // **進行中の本は「読みたい」に入れる**（2026-09-21。設計§10「予約は読む意思を消さない」）。
    //
    // 本番では予約の保存が同じ取引で `wanted` を書くので、予約中・取置中・貸出中の本は
    // 本棚にも並ぶ。**fixture はその取引を通らずに Loan だけを作っていた**ので、デモだけが
    // 「貸出し中なのに本棚に無い」状態になっていた。
    //
    // **返却済みの本も対象である。** 明示した `wanted` は、それより前に観測された返却
    // （`first_return_basis` が古い）に負けない。予約中の本が「読んだ」に沈まない。
    for (final index
        in <int>{
          for (final seed in _loans)
            if (_activeStatuses.contains(seed.status)) seed.book,
        }.toList()..sort()) {
      shelf.setState(bookId(index), 'wanted', now: now);
    }
    shelf.setState(bookId(24), 'wanted', now: now);
    shelf.setState(bookId(25), 'read', now: now, readOn: baseOn);
    shelf.saveReview(
      bookId(25),
      rating: 4,
      review: '読み返したい箇所を記録しました。',
      expectedRevision: '',
      now: now,
    );
    return verify(db, generations: generations);
  }

  DemoFixtureReport verify(Db db, {int generations = 0}) {
    final counts = <String, int>{};
    void check(
      String key,
      int expected,
      String sql, [
      List<Object?> args = const [],
    ]) {
      final actual = db.select(sql, args).single.values.single as int;
      counts[key] = actual;
      if (actual != expected) {
        throw StateError(
          'Demo fixture $key: expected $expected, actual $actual',
        );
      }
    }

    for (final entry in {
      'books': 30,
      'library_systems': 5,
      'library_memberships': 5,
      // 常用館4件（墨田は未設定）＋ 江東の取り込み値1件。
      'library_settings': 5,
      'loans': 19,
      // 本棚指定2件（手動の読みたい・読んだ）と、進行中12冊ぶんの「読みたい」。
      'book_preferences': 14,
      'book_reviews': 1,
      // 従来73件に、本棚指定2件・レビュー1件・進行中12件を追加。
      'outbox_events': 88,
      'applied_events': 88,
      'domain_events': 88,
    }.entries) {
      check(entry.key, entry.value, 'SELECT count(*) FROM ${entry.key}');
    }
    for (final entry in {
      'reserved': 7,
      'ready_for_pickup': 2,
      'borrowed': 4,
      'returned': 3,
      'cancelled': 2,
      'expired': 1,
    }.entries) {
      check(
        entry.key,
        entry.value,
        'SELECT count(*) FROM loans WHERE status = ?',
        [entry.key],
      );
    }
    check(
      'orphan_books',
      0,
      'SELECT count(*) FROM loans l LEFT JOIN books b '
          'ON b.id = l.book_id AND b.is_deleted = 0 WHERE b.id IS NULL',
    );
    check(
      'orphan_branches',
      0,
      '''SELECT count(*) FROM loans l WHERE NOT EXISTS (
      SELECT 1 FROM library_systems s, json_each(s.branches) b
      WHERE s.system_id = l.system_id AND s.is_deleted = 0
        AND json_extract(b.value, '\$.id') = l.pickup_library_id)''',
    );
    check(
      'due_overdue',
      1,
      "SELECT count(*) FROM loans WHERE "
          "status IN ('borrowed','ready_for_pickup') AND "
          "CASE status WHEN 'borrowed' THEN due_on ELSE pickup_due_on END < ?",
      [baseOn],
    );
    // 日曜日には「明日」が翌週になる。今日と日曜は同じ日になりうる。
    check(
      'due_this_week',
      baseDate.weekday == DateTime.sunday ? 4 : 5,
      "SELECT count(*) FROM loans WHERE status IN ('borrowed','ready_for_pickup') "
          "AND CASE status WHEN 'borrowed' THEN due_on ELSE pickup_due_on END <= ?",
      [on(sunday)],
    );
    check(
      'sent_outbox',
      0,
      "SELECT count(*) FROM outbox_events WHERE state != 'pending'",
    );
    check(
      'missing_applied',
      0,
      'SELECT count(*) FROM outbox_events o '
          'LEFT JOIN applied_events a ON a.event_id = o.event_id WHERE a.event_id IS NULL',
    );
    check(
      'sync_generation',
      generations,
      "SELECT count(*) FROM sync_state WHERE key = 'generation_id'",
    );
    for (final system in systems) {
      check(
        'system:${system.id}',
        1,
        'SELECT count(*) FROM library_systems WHERE system_id = ? '
            'AND name = ? AND is_deleted = 0',
        [system.id, system.name],
      );
      check(
        'preferred:${system.id}',
        _preferredSystems.contains(system.id) ? 1 : 0,
        'SELECT count(*) FROM library_settings WHERE system_id = ? '
            "AND key = 'preferred_branch' AND value = ? AND is_deleted = 0",
        [system.id, system.branches.first.id],
      );
      check(
        'mypage:${system.id}',
        system.id == _importedMypageSystem ? 1 : 0,
        'SELECT count(*) FROM library_settings WHERE system_id = ? '
            "AND key = 'mypage_url' AND value = ? AND checked_on = ? "
            'AND is_deleted = 0',
        [system.id, _importedMypageUrl, baseOn],
      );
      check(
        'membership:${system.id}',
        1,
        'SELECT count(*) FROM library_memberships WHERE system_id = ? '
            'AND last_reconciled_at_utc IS NOT NULL',
        [system.id],
      );
      for (final branch in system.branches) {
        check(
          'branch:${branch.id}',
          1,
          '''SELECT count(*) FROM library_systems s, json_each(s.branches) b
          WHERE s.system_id = ? AND json_extract(b.value, '\$.id') = ?
            AND json_extract(b.value, '\$.calil_libkey') = ?
            AND json_extract(b.value, '\$.name') = ?''',
          [system.id, branch.id, branch.calilLibkey, branch.name],
        );
      }
    }
    // 件数が同じでも違う内容なら失敗する。
    for (final book in bookRows) {
      check(
        'book:${book['key']}',
        1,
        'SELECT count(*) FROM books WHERE id = ? AND isbn13 = ? AND title = ? AND is_deleted = 0',
        [
          deterministicId(entityBook, book['isbn13'] as String),
          book['isbn13'],
          book['title'],
        ],
      );
    }
    for (var i = 0; i < _loans.length; i++) {
      final seed = _loans[i];
      final branch = systems
          .singleWhere((s) => s.id == seed.system)
          .branches[seed.branch]
          .id;
      check(
        'loan:$i',
        1,
        'SELECT count(*) FROM loans WHERE id = ? AND book_id = ? '
            'AND system_id = ? AND status = ? AND pickup_library_id = ? AND note IS NULL',
        [loanId(i), bookId(seed.book), seed.system, seed.status, branch],
      );
      final borrowed = seed.status == 'borrowed' || seed.status == 'returned';
      final ready =
          seed.status == 'ready_for_pickup' || seed.status == 'expired';
      check(
        'loan_dates:$i',
        1,
        'SELECT count(*) FROM loans WHERE id = ? AND reserved_on IS ? '
            'AND borrowed_on IS ? AND due_on IS ? AND pickup_available_on IS ? '
            'AND pickup_due_on IS ? AND returned_on IS ? AND cancelled_on IS ?',
        [
          loanId(i),
          borrowed ? null : on(seed.age),
          borrowed ? on(seed.age) : null,
          borrowed
              ? on(seed.status == 'returned' ? seed.age + 14 : seed.due)
              : null,
          ready ? on(seed.age + 1) : null,
          ready ? on(seed.status == 'expired' ? seed.age + 7 : seed.due) : null,
          seed.status == 'returned' ? on(seed.age + 8) : null,
          seed.status == 'cancelled' ? on(seed.age + 8) : null,
        ],
      );
    }
    return DemoFixtureReport(baseOn, counts);
  }
}

class DemoFixtureReport {
  final String baseOn;
  final Map<String, int> counts;
  const DemoFixtureReport(this.baseOn, this.counts);
  Map<String, Object?> toJson() => {
    'scenario': 'standard',
    'version': 1,
    'base_on': baseOn,
    'passed': true,
    'counts': counts,
    'not_implemented': ['bookshelf', 'reviews', 'preferred_branch_inheritance'],
  };
}

class _LoanSeed {
  final int book;
  final String system;
  final String status;
  final int due;
  final int branch;
  final int age;
  const _LoanSeed(
    this.book,
    this.system,
    this.status, {
    this.due = 0,
    this.branch = 0,
    this.age = -10,
  });
}
