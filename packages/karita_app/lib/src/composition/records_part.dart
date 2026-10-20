part of '../composition.dart';

/// 予約・本棚・貸出し。業務の記録を画面へ出す口と、書いた後の同期。
///
/// **状態（フィールド）は持たない** — 拡張は持てないので、本体（`composition.dart`）に置く。
extension CompositionRecords on Composition {
  Books get books => Books(domain);

  Loans get loans => Loans(domain);

  String newReservationId() => domain.uuid();

  String reservationBookId(String? isbn) =>
      isbn == null ? domain.uuid() : deterministicId(entityBook, isbn);

  ReservationBook? findReservationBook(String isbn) =>
      Reservations(domain).findBook(isbn);

  List<ReservationBook> loadReservationBooks() => Reservations(domain).books();

  List<String> activeReservationSystems(String id) =>
      Reservations(domain).activeSystems(id);

  /// The synchronous domain commit finishes before sync is scheduled.
  String saveReservation({
    required ReservationBook book,
    required String operationId,
    required List<String> systems,
    required bool wanted,
  }) {
    _requireOpen();
    if (book.isbn13 != null && normalizeIsbn13(book.isbn13!) != book.isbn13) {
      throw const ReservationIssue('Invalid ISBN.', code: 'isbn-invalid');
    }
    final local = DateTime.now().toIso8601String().substring(0, 10);
    final id = Reservations(domain).save(
      book: book,
      operationId: operationId,
      systems: systems,
      wanted: wanted,
      reservedOn: local,
      now: nowUtc(),
    );
    _syncAfterWrite('reservation');
    return id;
  }

  List<ShelfBook> loadBookshelf({String? bookId, bool includeHidden = false}) {
    _requireOpen();
    return Bookshelf(domain).read(bookId: bookId, includeHidden: includeHidden);
  }

  void setShelfState(String bookId, String state) {
    _requireOpen();
    Bookshelf(
      domain,
    ).setState(bookId, state, now: nowUtc(), readOn: localToday());
    _notifyStatus();
    _syncAfterWrite('bookshelf.state');
  }

  void saveBookReview(
    String bookId, {
    required int? rating,
    required String review,
    required String expectedRevision,
  }) {
    _requireOpen();
    Bookshelf(domain).saveReview(
      bookId,
      rating: rating,
      review: review,
      expectedRevision: expectedRevision,
      now: nowUtc(),
    );
    _notifyStatus();
    _syncAfterWrite('bookshelf.review');
  }

  // --- 貸出し画面へ出す口 -------------------------------------------------
  //
  // **画面はここだけを見る。** `Loans(domain)` も `LoanReporting(domain.db)` も画面からは
  // 組ませない（`非公開資料:ui-state-model.md` §3.1）。両方を組ませると、画面が
  // 「読みは DB、書きは業務」という層の割れ目を知ることになる。
  //
  // **`LoanReport` / `AreaLoanReport` は通さない。** あちらは pref・city 単位の集計で、
  // 貸出し仕様の「`systemid` を越えてグループ化しない」と単位が違う。
  // 通すのは `LoanReportItem` の平らな
  // 列だけで、束ね方は画面が決める。

  /// アクティブな Loan。**読み直す契機を決めるのは画面である。**
  ///
  /// **合成層は貸出し専用の変更通知を配らない。** いつ読み直すかは画面が決める（段階3、
  /// 2026-10-20 改め）— 初期画面は台帳の変更で読み直し、詳細は `↻ 更新` まで並びを動かさない。
  /// 棚卸は館サイトを見ながら手元を合わせる作業で、同期や書込みのたびに並びが変わると
  /// どこまで直したかを見失う。
  ///
  /// [loanId] を渡すとその1件だけを返す。**それでも台帳は全件読む** — `effective`（重複の
  /// 畳み）と `parallelSystemIds`（別システムの並行予約）は他の Loan を見なければ決まらず、
  /// 1行だけを読むと書込みのたびにその2つが狂う。
  ///
  /// [asOf] は `urgency`（期限切れ・期限間近）の基準日である。**既定は端末のローカル日付。**
  /// UTC で採ると、日付が変わる前後の9時間で期限の警告が1日ずれる。
  List<LoanReportItem> loadActiveLoans({String? asOf, String? loanId}) {
    _requireOpen();
    try {
      final items = LoanReporting(domain.db).readActiveLoans(
        LibrariesConfig(readLibrarySystems(domain)),
        asOf: asOf ?? localToday(),
      );
      final selected = loanId == null
          ? items
          : [
              for (final item in items)
                if (item.loanId == loanId) item,
            ];
      _log.fine('loans.loaded', {'items': selected.length});
      return selected;
    } on AppIssue catch (issue) {
      _log.warning('loans.load.failed', {'code': issue.code});
      rethrow;
    } catch (error) {
      // **`toString()` を配らない。** SQLite の例外は SQL 文と DB のパスを含みうる。
      throw AppIssue(
        'loans-load',
        'Active loans could not be read (${error.runtimeType}).',
      );
    }
  }

  /// Loan 一件の遷移、または日付の訂正。**規則は `Loans` が持つ。**
  ///
  /// 日付の既定（取置7日・借出14日・延長は操作日+14日）を**ここで再定義しない** — 正本は
  /// `非公開資料:loan-lifecycle.md` で、既定を作るのは `Loans.update` である。
  ///
  /// [operationOn] の既定が端末のローカル日付なのは、`Loans.update` が渡された `now`（UTC）
  /// から操作日を導くためである。日本時間の朝9時までに操作すると、UTC ではまだ前日になる。
  void updateLoan({
    required String loanId,
    required String action,
    String? reservedOn,
    String? pickupAvailableOn,
    String? pickupDueOn,
    String? borrowedOn,
    String? dueOn,
    String? returnedOn,
    String? cancelledOn,
    String? operationOn,
  }) {
    _requireOpen();
    Loans(domain).update(
      loanId: loanId,
      action: action,
      reservedOn: reservedOn,
      pickupAvailableOn: pickupAvailableOn,
      pickupDueOn: pickupDueOn,
      borrowedOn: borrowedOn,
      dueOn: dueOn,
      returnedOn: returnedOn,
      cancelledOn: cancelledOn,
      operationOn: operationOn ?? localToday(),
      now: nowUtc(),
    );
    _log.info('loan.updated', {'action': action});
    _notifyStatus();
    _syncAfterWrite('loan.update');
  }

  /// 行1件の受取館を選び直す。**常用館は動かさない。**
  ///
  /// **分館がその図書館システムに在ることを見るのはここである。** `Loans` は
  /// `LibrarySystems` を知らない層で（`Reservations` が常用館を解決する側であるのと同じ
  /// 切り方）、2つの集約をまたげるのは合成層だけである。
  ///
  /// **削除済みのシステムはここで止まる。** カタログが無ければ分館の一覧も無く、選び直す
  /// 先が無い。
  void changeLoanPickupLibrary({
    required String loanId,
    required String systemId,
    required String branchId,
  }) {
    _requireOpen();
    final system = LibrarySystems(domain).read(systemId);
    if (system == null || !system.hasBranch(branchId)) {
      throw const AppIssue(
        'pickup-library-unknown',
        'The branch is not in this library system.',
      );
    }
    Loans(domain).correctPickupLibrary(
      loanId: loanId,
      pickupLibraryId: branchId,
      now: nowUtc(),
    );
    _log.info('loan.pickup_library.changed', {'system': systemId});
    _notifyStatus();
    _syncAfterWrite('loan.pickup_library');
  }

  /// 棚卸のために館サイトを開く。**用途は `lending` である。**
  ///
  /// 開く先は [openLibrarySite] と同じ解決済みマイページ URL だが、置いてくる
  /// [LaunchContext] の用途が違う。`mypageCandidateOf` が用途で弾くので、**ここから開いた
  /// 往復は URL 設定の候補にならない。**
  Future<void> openLendingSite(String systemId) =>
      openLibrarySite(systemId, purpose: LaunchPurpose.lending);

  /// 通常の書込みに共通の後始末。**保存の成否と同期の成否は別である。**
  ///
  /// `saveReservation` と同じ形にする — 台帳へのコミットは既に終わっており、同期が落ちても
  /// 保存済みのデータを未保存へ戻さない。
  void _syncAfterWrite(String event) {
    unawaited(
      syncAfterDomainWrite().catchError((Object error) {
        _log.warning('$event.sync.failed', {
          'type': error.runtimeType.toString(),
        });
      }),
    );
  }
}
