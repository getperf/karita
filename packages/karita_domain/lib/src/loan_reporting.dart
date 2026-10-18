/// Loan の参照専用レポート。**書込みユースケースと端末表示から独立させる。**
///
/// **重複した Loan を畳むのは表示だけである。データは両方そのまま残す。** 同じ本を同じ図書館
/// システムで本当に二件予約したのか、一件の予約を二端末で記録しただけなのかは、館の予約番号を
/// 持たないアプリには判定できない。統合すれば、前者のとき実在の予約を一件消す。
///
/// 移送元: book-sync-model の `src/bops_application/loan_reporting.py`。
library;

import 'dart:convert';

import 'package:karita_contract/karita_contract.dart';

import 'library_areas.dart';
import 'loans.dart';

class LoanReportItem {
  final String loanId;
  final String bookId;
  final String systemId;
  final String systemName;
  final String pref;
  final String city;
  final String status;
  final String title;
  final bool bookAvailable;
  final List<String> authors;
  final String? isbn13;
  final String? reservedOn;
  final String? pickupAvailableOn;
  final String? pickupDueOn;
  final String? borrowedOn;
  final String? dueOn;
  final String? pickupLibraryId;
  final String? pickupLibraryName;
  final String? loanLibraryId;
  final String? loanLibraryName;
  final String? urgency;
  final bool configured;

  /// 同一 `systemId`・同一 `bookId` のアクティブ Loan のうち実効の1件。**残りも消さない。**
  final bool effective;
  final String? duplicateOf;

  /// 同じ本のアクティブ Loan がある**他の**図書館システム。畳まず注記だけを出す。別の区で
  /// 予約し、早く来た方を取るのは正当な運用であり、片方が受取可能になったらもう片方を取り消す、
  /// という判断に直接効く。
  final List<String> parallelSystemIds;
  final List<String> parallelLabels;

  const LoanReportItem({
    required this.loanId,
    required this.bookId,
    required this.systemId,
    required this.systemName,
    required this.pref,
    required this.city,
    required this.status,
    required this.title,
    required this.bookAvailable,
    required this.authors,
    required this.configured,
    this.isbn13,
    this.reservedOn,
    this.pickupAvailableOn,
    this.pickupDueOn,
    this.borrowedOn,
    this.dueOn,
    this.pickupLibraryId,
    this.pickupLibraryName,
    this.loanLibraryId,
    this.loanLibraryName,
    this.urgency,
    this.effective = true,
    this.duplicateOf,
    this.parallelSystemIds = const [],
    this.parallelLabels = const [],
  });
}

class AreaLoanReport {
  final String pref;
  final String city;
  final List<String> systemIds;
  final int borrowedCount;
  final int readyForPickupCount;
  final int reservedCount;
  final List<LoanReportItem> items;

  /// 見出しの件数は**実効のみを数える。** 「何冊借りているか」への答えを歪めないため、重複は
  /// 件数に混ぜず、別に数えて注記する。
  final int duplicateCount;

  const AreaLoanReport({
    required this.pref,
    required this.city,
    required this.systemIds,
    required this.borrowedCount,
    required this.readyForPickupCount,
    required this.reservedCount,
    required this.items,
    this.duplicateCount = 0,
  });
}

class LoanReport {
  final String asOf;
  final int borrowedCount;
  final int readyForPickupCount;
  final int reservedCount;
  final List<AreaLoanReport> areas;
  final int duplicateCount;

  const LoanReport({
    required this.asOf,
    required this.borrowedCount,
    required this.readyForPickupCount,
    required this.reservedCount,
    required this.areas,
    this.duplicateCount = 0,
  });
}

class LoanReporting {
  final Db db;

  const LoanReporting(this.db);

  /// アクティブ Loan を**一度だけ読み**、書誌・管理区・分館名を解決する。
  List<LoanReportItem> readActiveLoans(
    LibrariesConfig config, {
    Set<String>? systemIds,
    String? asOf,
  }) {
    var query = '''
        SELECT loans.id AS loan_id, loans.book_id, loans.system_id, loans.status,
               loans.reserved_on, loans.pickup_available_on, loans.pickup_due_on,
               loans.borrowed_on, loans.due_on, loans.pickup_library_id,
               loans.loan_library_id, loans.updated_at_utc, loans.updated_by_device_id,
               books.id AS book_row_id, books.title, books.authors, books.isbn13,
               books.is_deleted
          FROM loans
          LEFT JOIN books ON books.id = loans.book_id
         WHERE loans.status IN ('reserved', 'ready_for_pickup', 'borrowed')
    ''';
    var params = <Object?>[];
    if (systemIds != null) {
      if (systemIds.isEmpty) return const [];
      final ordered = systemIds.toList()..sort();
      query += ' AND loans.system_id IN (${ordered.map((_) => '?').join(',')})';
      params = [...ordered];
    }
    query += ' ORDER BY loans.updated_at_utc, loans.id';

    final systems = {for (final system in config.librarySystems) system.id: system};
    final rows = db.select(query, params);
    final effectiveOf = _effectiveLoans(rows);
    // **絞り込みに影響されない。** `systemIds` で絞ると区をまたいだ並行予約が見えなくなるため、
    // 並行の判定だけは全アクティブ Loan を読む。
    final parallel = _parallelSystems();

    final values = <LoanReportItem>[];
    for (final row in rows) {
      final systemId = '${row['system_id'] ?? ''}';
      final system = systems[systemId];
      final branchNames = _branchNames(system);
      final rawTitle = row['title'];
      // **書名の有無で Book の有無を測らない。** 書誌の取れない ISBN は書名 NULL で保存される
      // （`reservations.dart`）。書名で測ると、台帳に在る本まで「書誌未登録」になり、
      // ISBN も捨てて書影を引けなくなる。
      final hasBook =
          row['book_row_id'] != null && (row['is_deleted'] as int? ?? 0) != 1;
      final loanId = '${row['loan_id']}';
      final winner = effectiveOf[loanId] ?? loanId;
      final bookId = '${row['book_id'] ?? ''}';
      final others = ((parallel[bookId] ?? const <String>{}).toList()
            ..remove(systemId))
          ..sort();
      final status = '${row['status']}';

      values.add(LoanReportItem(
        loanId: loanId,
        bookId: bookId,
        systemId: systemId,
        systemName: system?.name ??
            '未設定システム ${systemId.isEmpty ? '(なし)' : systemId}',
        pref: system?.pref ?? '',
        city: system?.city ??
            '未設定システム ${systemId.isEmpty ? '(なし)' : systemId}',
        status: status,
        title: !hasBook
            ? '書誌未登録 ($bookId)'
            : rawTitle == null
                ? '書名なし'
                : '$rawTitle',
        bookAvailable: hasBook,
        authors: hasBook ? _authors(row['authors']) : const [],
        isbn13: hasBook && row['isbn13'] != null ? '${row['isbn13']}' : null,
        reservedOn: row['reserved_on'] as String?,
        pickupAvailableOn: row['pickup_available_on'] as String?,
        pickupDueOn: row['pickup_due_on'] as String?,
        borrowedOn: row['borrowed_on'] as String?,
        dueOn: row['due_on'] as String?,
        pickupLibraryId: row['pickup_library_id'] as String?,
        pickupLibraryName: branchNames['${row['pickup_library_id'] ?? ''}'],
        loanLibraryId: row['loan_library_id'] as String?,
        loanLibraryName: branchNames['${row['loan_library_id'] ?? ''}'],
        urgency: _urgency(status, row['pickup_due_on'] as String?,
            row['due_on'] as String?, asOf),
        configured: system != null,
        effective: winner == loanId,
        duplicateOf: winner == loanId ? null : winner,
        parallelSystemIds: others,
        parallelLabels: [
          for (final other in others) systems[other]?.city ?? other,
        ],
      ));
    }
    return values;
  }

  /// アクティブ Loan を管理区単位に集約する。
  LoanReport buildLoanReport(
    LibrariesConfig config, {
    required String asOf,
    String? systemId,
    bool includeEmpty = false,
  }) {
    _requireLocalDate(asOf);
    final items = readActiveLoans(config,
        systemIds: systemId == null ? null : {systemId}, asOf: asOf);

    final grouped = <String, List<LoanReportItem>>{};
    final groupSystemIds = <String, Set<String>>{};
    final keyOf = <String, (String, String)>{};

    void ensure(String pref, String city) {
      final key = '$pref $city';
      grouped.putIfAbsent(key, () => []);
      groupSystemIds.putIfAbsent(key, () => {});
      keyOf[key] = (pref, city);
    }

    final selected = [
      for (final system in config.librarySystems)
        if (systemId == null || system.id == systemId) system,
    ];
    final configuredKeys = <String>[];
    for (final system in selected) {
      final key = '${system.pref} ${system.city}';
      if (!configuredKeys.contains(key)) configuredKeys.add(key);
      keyOf[key] = (system.pref, system.city);
    }
    if (includeEmpty) {
      for (final system in selected) {
        ensure(system.pref, system.city);
        groupSystemIds['${system.pref} ${system.city}']!.add(system.id);
      }
    }
    for (final item in items) {
      ensure(item.pref, item.city);
      final key = '${item.pref} ${item.city}';
      grouped[key]!.add(item);
      groupSystemIds[key]!.add(item.systemId);
    }

    // **設定済みの区を宣言順で先に出し、未設定の区を後ろへ回す。** 見出しの並びが実行ごとに
    // 動くと、同じ台帳のレポートが毎回違う形になる。
    final unknownKeys = grouped.keys
        .where((key) => !configuredKeys.contains(key))
        .toList()
      ..sort();
    final order = [
      ...configuredKeys.where(grouped.containsKey),
      ...unknownKeys,
    ];

    final areas = <AreaLoanReport>[];
    for (final key in order) {
      final (pref, city) = keyOf[key]!;
      final areaItems = [...grouped[key]!]..sort(_compareItems);
      areas.add(AreaLoanReport(
        pref: pref,
        city: city,
        systemIds: groupSystemIds[key]!.toList()..sort(),
        borrowedCount: _count(areaItems, 'borrowed'),
        readyForPickupCount: _count(areaItems, 'ready_for_pickup'),
        reservedCount: _count(areaItems, 'reserved'),
        items: areaItems,
        duplicateCount: areaItems.where((item) => !item.effective).length,
      ));
    }

    return LoanReport(
      asOf: asOf,
      borrowedCount: _count(items, 'borrowed'),
      readyForPickupCount: _count(items, 'ready_for_pickup'),
      reservedCount: _count(items, 'reserved'),
      areas: areas,
      duplicateCount: items.where((item) => !item.effective).length,
    );
  }

  /// **実効のみを数える。** 重複を混ぜると「何冊借りているか」への答えが歪む。
  int _count(List<LoanReportItem> items, String status) =>
      items.where((item) => item.status == status && item.effective).length;

  /// `loanId` → その Loan が属する組の実効 `loanId`。
  ///
  /// 同一 `systemId` かつ同一 `bookId` のアクティブ Loan が複数あるとき、次の全順序で最大の
  /// ものを実効とする。**同一 `systemId` 内に限る** — 別の区で同じ本を予約し、早く来た方を
  /// 取るのは正当な運用であり、これを重複として畳むと複数の管理区を並行して使う運用が壊れる。
  ///
  /// | 順 | キー | 意味 |
  /// |---|---|---|
  /// | 1 | 開始日（`reserved_on`。無ければ `borrowed_on`） | 「後の予約を採る」の一次基準 |
  /// | 2 | `updated_at_utc` | 同日登録の決着。後から記録した方が新しい認識である |
  /// | 3 | `updated_by_device_id` | |
  /// | 4 | `loan_id` | 必ず一意に決まる |
  ///
  /// **LWW の決定キーと同じ構造である。** 同じデータに同じ純関数を当てるため、全端末が同じ
  /// 実効 Loan を選ぶ。
  Map<String, String> _effectiveLoans(List<Map<String, Object?>> rows) {
    final groups = <String, List<(List<String>, String)>>{};
    for (final row in rows) {
      final loanId = '${row['loan_id']}';
      final key = [
        '${row['reserved_on'] ?? row['borrowed_on'] ?? ''}',
        '${row['updated_at_utc'] ?? ''}',
        '${row['updated_by_device_id'] ?? ''}',
        loanId,
      ];
      final group = '${row['system_id'] ?? ''} ${row['book_id'] ?? ''}';
      groups.putIfAbsent(group, () => []).add((key, loanId));
    }
    final effective = <String, String>{};
    for (final members in groups.values) {
      var winner = members.first;
      for (final member in members.skip(1)) {
        if (_compareKeys(member.$1, winner.$1) > 0) winner = member;
      }
      for (final member in members) {
        effective[member.$2] = winner.$2;
      }
    }
    return effective;
  }

  /// `bookId` → その本のアクティブ Loan がある図書館システムの集合。
  ///
  /// **絞り込まない。** 絞った側だけを見ると、区をまたいだ並行予約は相手が視界の外にあるため
  /// 一件も見えない。これは Book を一意にして初めて突き合わせできるようになった。
  Map<String, Set<String>> _parallelSystems() {
    final result = <String, Set<String>>{};
    final placeholders = activeLoanStatuses.map((_) => '?').join(',');
    for (final row in db.select(
      'SELECT book_id, system_id FROM loans WHERE status IN ($placeholders)',
      [...activeLoanStatuses],
    )) {
      result
          .putIfAbsent('${row['book_id'] ?? ''}', () => {})
          .add('${row['system_id'] ?? ''}');
    }
    return result;
  }

  Map<String, String> _branchNames(LibrarySystem? system) => system == null
      ? const {}
      : {for (final branch in system.branches) branch.id: branch.name};

  List<String> _authors(Object? raw) {
    if (raw is! String) return const [];
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (parsed is! List) return const [];
    return [
      for (final value in parsed)
        if (value is String) value,
    ];
  }

  /// 期限までの残り。`overdue` / `due_soon` / なし。
  String? _urgency(
      String status, String? pickupDueOn, String? dueOn, String? asOf) {
    final deadline = status == 'ready_for_pickup'
        ? pickupDueOn
        : status == 'borrowed'
            ? dueOn
            : null;
    if (deadline == null || deadline.isEmpty || asOf == null) return null;
    final DateTime end;
    final DateTime from;
    try {
      end = _requireLocalDate(deadline);
      from = _requireLocalDate(asOf);
    } on FormatException {
      return null;
    }
    final remaining = end.difference(from);
    if (remaining.isNegative) return 'overdue';
    return remaining.inDays <= 2 ? 'due_soon' : null;
  }

  int _compareItems(LoanReportItem a, LoanReportItem b) {
    const order = {'ready_for_pickup': 0, 'borrowed': 1, 'reserved': 2};
    String relevant(LoanReportItem item) =>
        (item.status == 'ready_for_pickup'
            ? item.pickupDueOn
            : item.status == 'borrowed'
                ? item.dueOn
                : item.reservedOn) ??
        '9999-12-31';
    final byStatus = (order[a.status] ?? 9).compareTo(order[b.status] ?? 9);
    if (byStatus != 0) return byStatus;
    final byDate = relevant(a).compareTo(relevant(b));
    if (byDate != 0) return byDate;
    final byTitle = a.title.compareTo(b.title);
    return byTitle != 0 ? byTitle : a.loanId.compareTo(b.loanId);
  }
}

/// Python の tuple 比較と同じ順序。**要素ごとに前から比べる。**
int _compareKeys(List<String> a, List<String> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    final result = a[i].compareTo(b[i]);
    if (result != 0) return result;
  }
  return a.length.compareTo(b.length);
}

DateTime _requireLocalDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw FormatException('日付は YYYY-MM-DD で指定してください: $value');
  }
  final parts = value.split('-').map(int.parse).toList();
  final moment = DateTime.utc(parts[0], parts[1], parts[2]);
  if (moment.month != parts[1] || moment.day != parts[2]) {
    throw FormatException('日付は YYYY-MM-DD で指定してください: $value');
  }
  return moment;
}
