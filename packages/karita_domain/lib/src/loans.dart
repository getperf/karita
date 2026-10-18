/// Loan の作成と、状態・日付の記録。
///
/// 外部サイトを開くことや所蔵照会はここに持ち込まない。**利用者が確認した一件の事実だけ**を
/// Loan・DomainEvent・SyncEvent として同時に確定する。
///
/// 移送元: book-sync-model の `src/bops_application/loans.py`。
library;

import 'package:karita_contract/karita_contract.dart';

import 'books.dart';
import 'bookshelf.dart';
import 'context.dart';
import 'errors.dart';

/// 記録できる操作。**行き先と業務記録の名前だけを持つ。**
///
/// **前状態は持たない**（2026-09-19 改定）。元は `from` を持つ `loanTransitions` で、許された
/// 遷移だけを通していた。**やめた** — このアプリが書くのは利用者が館サイトで確認した事実で
/// あって、アプリの側に「その順でしか起こらないはず」と言える根拠が無い。館は予約を取り消さ
/// ずに取置へ回すことも、返却済みの扱いを後から直すこともある。棚卸で手元を事実へ合わせる
/// のに、アプリの推測が邪魔をしてはいけない（UI 仕様 `screens/lending.md` §2「状態と期限は
/// 一覧から直接変更する」）。
///
/// **`invalid-transition` はこの経路から消えた。** `karita_domain` の `errors.dart` が挙げて
/// いる共有 code のうち、この1つだけが使われなくなる。
class LoanAction {
  /// 書き込む状態。
  final String to;

  /// 残す DomainEvent の名前。**語彙は bops の持ち物である。**
  final String eventType;

  const LoanAction(this.to, this.eventType);
}

const Map<String, LoanAction> loanActions = {
  /// 予約中へ戻す。**館サイトがそう見せているなら、そう書ける。**
  'reserve': LoanAction('reserved', 'LoanReserved'),
  'ready-for-pickup': LoanAction('ready_for_pickup', 'LoanReadyForPickup'),
  'borrow': LoanAction('borrowed', 'LoanBorrowed'),
  'renew': LoanAction('borrowed', 'LoanRenewed'),
  'correct-due-date': LoanAction('borrowed', 'LoanDueDateCorrected'),
  'correct-pickup-due-date':
      LoanAction('ready_for_pickup', 'LoanPickupDueDateCorrected'),
  'return': LoanAction('returned', 'LoanReturned'),
  'cancel': LoanAction('cancelled', 'LoanCancelled'),
  'expire': LoanAction('expired', 'LoanExpired'),
};

/// 棚卸の対象になる Loan の状態。**一覧に出るのはこの3つである。**
///
/// **遷移の規則ではない。** どの状態からどの状態へ書けるかは縛らない（[LoanAction]）。ここが
/// 決めているのは「まだ手元で面倒を見ている利用か」だけで、読む側（`LoanReporting`）の絞り
/// 込みに使う。
const List<String> activeLoanStatuses = [
  'reserved',
  'ready_for_pickup',
  'borrowed',
];

/// 開始できる状態。**予約と借出だけである** — 取置・返却・取消は既存の Loan の遷移であり、
/// そこから始まる利用は無い。
const List<String> loanStartStatuses = ['reserved', 'borrowed'];

/// 既定の貸出期間と取置期間。館ごとの規則ではなく、**入力を省いたときの当たり**である。
const int defaultLoanDays = 14;
const int defaultPickupDays = 7;

class Loans {
  final DomainContext context;
  final Books books;

  Loans(this.context) : books = Books(context);

  /// 新規利用を `reserved` または `borrowed` から開始する。
  Envelope start({
    required String loanId,
    required String bookId,
    required String status,
    required String systemId,
    String? pickupLibraryId,
    String? reservedOn,
    String? borrowedOn,
    String? dueOn,
    String? note,
    String? operationOn,
    required String now,
  }) {
    if (context.aggregates.read(context.db, entityLoan, loanId) != null) {
      throw LoanError('Loan が既にあります: $loanId', code: 'loan-exists');
    }
    final built = _startPayload(
      bookId: bookId,
      status: status,
      systemId: systemId,
      pickupLibraryId: pickupLibraryId,
      reservedOn: reservedOn,
      borrowedOn: borrowedOn,
      dueOn: dueOn,
      note: note,
      operationOn: operationOn,
      now: now,
    );
    return transaction(
      context.db,
      () => context.emit(
        entityType: entityLoan,
        entityId: loanId,
        payload: built.payload,
        domainEventType: built.eventType,
        aggregateType: 'loan',
        now: now,
      ),
    );
  }

  /// 候補の採用と新規 Loan を、イベントを含めて**原子的に**確定する。
  ///
  /// 検索・所蔵照会・ブラウザ操作は呼出側で完了済みであること。ここには利用者が最終確認した
  /// 書誌と結果だけを渡すため、取消や外部 I/O の失敗ではこの関数を呼ばない。
  Envelope startFromCandidate({
    required String loanId,
    required BookCandidateInput candidate,
    required String status,
    required String systemId,
    String? pickupLibraryId,
    String? reservedOn,
    String? borrowedOn,
    String? dueOn,
    String? note,
    String? operationOn,
    required String now,
  }) {
    if (context.aggregates.read(context.db, entityLoan, loanId) != null) {
      throw LoanError('Loan が既にあります: $loanId', code: 'loan-exists');
    }
    return transaction(context.db, () {
      // 採用の規則（重複検査、候補の検証、payload、採番）は [Books] が持つ。**開いた
      // トランザクションの中で呼ぶ。** `bookId` は Books が ISBN から導く — ここで採番すると
      // 入口ごとに規則が分かれる。
      final adoption = books.emitAdoption(
        title: candidate.title,
        authors: candidate.authors,
        isbn13: candidate.isbn13,
        publisher: candidate.publisher,
        sourceUrl: candidate.sourceUrl,
        provider: candidate.provider,
        now: now,
      );
      final built = _startPayload(
        bookId: adoption.entityId,
        status: status,
        systemId: systemId,
        pickupLibraryId: pickupLibraryId,
        reservedOn: reservedOn,
        borrowedOn: borrowedOn,
        dueOn: dueOn,
        note: note,
        operationOn: operationOn,
        now: now,
      );
      return context.emit(
        entityType: entityLoan,
        entityId: loanId,
        payload: built.payload,
        domainEventType: built.eventType,
        aggregateType: 'loan',
        now: now,
      );
    });
  }

  /// 既存 Loan 一件の状態と日付を書く。**前の状態は問わない**（[LoanAction]）。
  Envelope update({
    required String loanId,
    required String action,
    String? pickupAvailableOn,
    String? pickupDueOn,
    String? borrowedOn,
    String? dueOn,
    String? returnedOn,
    String? cancelledOn,
    String? note,
    String? operationOn,
    required String now,
  }) => transaction(context.db, () {
    final row = context.aggregates.read(context.db, entityLoan, loanId);
    if (row == null) {
      throw LoanError('Loan がありません: $loanId', code: 'loan-not-found');
    }
    final operation = loanActions[action];
    if (operation == null) {
      throw LoanError('未知の更新操作です: $action', code: 'loan-action');
    }
    // **いまの状態は見ない。** 許される前状態という概念をこの層から落とした（[LoanAction]）。

    final defaultOn = _date(operationOn ?? _defaultDate(now), '操作日');
    final payload = context.mapping.rowToPayload(entityLoan, row);
    payload['status'] = operation.to;
    if (note != null) payload['note'] = note;

    switch (action) {
      case 'reserve':
        // **予約日だけを置く。** 既に在るなら動かさない — 予約した日は館サイト側の
        // 事実で、状態を書き直したこととは関係が無い。他の日付も消さない。
        payload['reserved_on'] = _date(
          payload['reserved_on'] as String? ?? defaultOn,
          '予約日',
        );
      case 'ready-for-pickup':
        final availableOn = _date(pickupAvailableOn ?? defaultOn, '取置開始日');
        payload['pickup_available_on'] = availableOn;
        payload['pickup_due_on'] = _date(
          pickupDueOn ?? _defaultDate(availableOn, defaultPickupDays),
          '取置期限',
        );
        if (_blank(payload['pickup_library_id']) &&
            _blank(payload['library_id'])) {
          throw const LoanError('取置開始には受取館が必要です。', code: 'pickup-library');
        }
      case 'borrow':
        // **貸出館は無い。館は受取館の1つだけである** — 受取も返却も同じ窓口で行う。
        // `loan_library_id` 列は読み取り互換のために残るが、**新規書込みはしない**
        // （`library_id` と同じ扱い）。判定は `ready-for-pickup` と同じ形にする。
        if (_blank(payload['pickup_library_id']) &&
            _blank(payload['library_id'])) {
          throw const LoanError('借出には受取館が必要です。', code: 'pickup-library');
        }
        final on = _date(borrowedOn ?? defaultOn, '貸出日');
        payload['borrowed_on'] = on;
        payload['due_on'] = _date(
          dueOn ?? _defaultDate(on, defaultLoanDays),
          '返却期限',
        );
      case 'renew':
      case 'correct-due-date':
        payload['due_on'] = _date(
          dueOn ?? _defaultDate(defaultOn, defaultLoanDays),
          '返却期限',
        );
      case 'return':
        if (payload['first_return_at_utc'] == null) {
          // 旧返却・訂正済み返却は新しい読書として復活させない。
          payload['first_return_basis'] =
              row['returned_on'] != null || row['status'] == 'returned'
              ? 'legacy'
              : Bookshelf(context).token(row['book_id'] as String);
          payload['first_return_at_utc'] = now;
        }
        payload['returned_on'] = _date(returnedOn ?? defaultOn, '返却日');
      case 'cancel':
        payload['cancelled_on'] = _date(cancelledOn ?? defaultOn, '取消日');
      case 'correct-pickup-due-date':
        // **取置開始日は動かさない。** 直したいのは館サイトで確認した取置期限だけで、
        // 起点を操作日へ動かすと「いつ確保されたか」の記録が失われる。
        payload['pickup_due_on'] = _date(
          pickupDueOn ??
              _defaultDate(
                payload['pickup_available_on'] as String? ?? defaultOn,
                defaultPickupDays,
              ),
          '取置期限',
        );
      case 'expire':
        payload['pickup_due_on'] = _date(
          pickupDueOn ?? payload['pickup_due_on'] as String?,
          '取置期限',
        );
    }

    return context.emit(
      entityType: entityLoan,
      entityId: loanId,
      payload: payload,
      domainEventType: operation.eventType,
      aggregateType: 'loan',
      now: now,
    );
  });

  /// 受取館だけを書き換える。**状態も日付も動かさない。**
  ///
  /// 常用館と違う館へ行く利用のためにある（UI 仕様 `screens/lending.md` §2「受取館はリンクと
  /// し、押すとそのシステム館の分館リストから選び直せる」）。**書き換えるのはこの Loan だけで
  /// あり、常用館は動かない** — 常用館の変更は既存の Loan に及ばない、の裏返しである
  /// （`非公開資料:loan-lifecycle.md`）。
  ///
  /// **[loanActions] に入れない。** あちらは状態を書く操作の表で、これは状態を書かない。
  ///
  /// **状態は見ない**（2026-09-19 改定）。元は終端の Loan を `invalid-transition` で弾いて
  /// いたが、状態そのものを自由に書き直せるようにした以上（[LoanAction]）、受取館だけを
  /// 縛る理由が無い。返却済みの行の館名が違っていれば直せる。
  ///
  /// **分館が当の図書館システムに在ることはここでは見ない。** この層は `LibrarySystems` を
  /// 知らない（`Reservations` が常用館を解決する側であるのと同じ切り方）。突き合わせるのは
  /// 合成層である。
  Envelope correctPickupLibrary({
    required String loanId,
    required String pickupLibraryId,
    String? note,
    required String now,
  }) {
    final row = context.aggregates.read(context.db, entityLoan, loanId);
    if (row == null) {
      throw LoanError('Loan がありません: $loanId', code: 'loan-not-found');
    }
    if (pickupLibraryId.isEmpty) {
      throw const LoanError('受取館は必須です。', code: 'pickup-library');
    }
    final payload = context.mapping.rowToPayload(entityLoan, row);
    payload['pickup_library_id'] = pickupLibraryId;
    if (note != null) payload['note'] = note;

    return transaction(
      context.db,
      () => context.emit(
        entityType: entityLoan,
        entityId: loanId,
        payload: payload,
        // **語彙は bops の持ち物で、封筒は運ぶだけである**（`sync-event` スキーマの
        // `domainEventType` は enum ではなく自由文字列）。足しても版は上がらない。
        domainEventType: 'LoanPickupLibraryCorrected',
        aggregateType: 'loan',
        now: now,
      ),
    );
  }

  /// 開始の payload。**`start` と `startFromCandidate` が同じものを通る。**
  ///
  /// 入れ子のトランザクションは SQLite の同一接続上で安全でないので、候補からの開始は `start`
  /// を呼び直せない。そこで payload を作るところだけを共有する — 二箇所に書くと、既定日の
  /// 規則が入口ごとにずれる。
  _StartPayload _startPayload({
    required String bookId,
    required String status,
    required String systemId,
    required String? pickupLibraryId,
    required String? reservedOn,
    required String? borrowedOn,
    required String? dueOn,
    required String? note,
    required String? operationOn,
    required String now,
  }) {
    if (!loanStartStatuses.contains(status)) {
      throw const LoanError(
          'loan start で開始できる状態は reserved または borrowed だけです。',
          code: 'start-status');
    }
    final defaultOn = _date(operationOn ?? _defaultDate(now), '操作日');
    final payload = <String, Object?>{
      'book_id': bookId,
      'system_id': systemId,
      'status': status,
    };
    if (note != null && note.isNotEmpty) payload['note'] = note;

    if (status == 'reserved') {
      if (pickupLibraryId == null || pickupLibraryId.isEmpty) {
        throw const LoanError('予約には受取館が必要です。', code: 'pickup-library');
      }
      payload['pickup_library_id'] = pickupLibraryId;
      payload['reserved_on'] = _date(reservedOn ?? defaultOn, '予約日');
      return _StartPayload(payload, 'LoanReserved');
    }

    // **借出開始も受取館を要る。** `貸出中` は受取館と返却期限を持つ（UI 仕様
    // `screens/lending.md`）。予約を経ずに直接借りた場合も、受け取った窓口は必ずある。
    if (pickupLibraryId == null || pickupLibraryId.isEmpty) {
      throw const LoanError('借出には受取館が必要です。', code: 'pickup-library');
    }
    final on = _date(borrowedOn ?? defaultOn, '貸出日');
    payload['pickup_library_id'] = pickupLibraryId;
    payload['borrowed_on'] = on;
    payload['due_on'] = _date(dueOn ?? _defaultDate(on, defaultLoanDays), '返却期限');
    return _StartPayload(payload, 'LoanBorrowed');
  }
}

class _StartPayload {
  final Map<String, Object?> payload;
  final String eventType;

  const _StartPayload(this.payload, this.eventType);
}

bool _blank(Object? value) => value == null || '$value'.isEmpty;

/// ローカル日付。**`YYYY-MM-DD` に固定する。** 集約行の日付列は文字列比較で並べるので、
/// 書式が揺れると期限の前後が狂う。
String _date(String? value, String label) {
  if (value == null || value.isEmpty) {
    throw LoanError('$label は必須です。', code: 'missing-date');
  }
  if (!_localDateRe.hasMatch(value)) {
    throw LoanError('$label は YYYY-MM-DD で指定してください: $value', code: 'date');
  }
  final parts = value.split('-').map(int.parse).toList();
  final moment = DateTime.utc(parts[0], parts[1], parts[2]);
  // うるう日でない 2/29 や 4/31 を弾く。`DateTime` は繰り上げてしまうため、戻して確かめる。
  if (moment.year != parts[0] ||
      moment.month != parts[1] ||
      moment.day != parts[2]) {
    throw LoanError('$label は YYYY-MM-DD で指定してください: $value', code: 'date');
  }
  return value;
}

/// 起点の日付から日数を足す。`now` を渡すときは日付部分だけを見る。
String _defaultDate(String from, [int days = 0]) {
  final head = from.length >= 10 ? from.substring(0, 10) : from;
  final parts = head.split('-').map(int.parse).toList();
  final moment =
      DateTime.utc(parts[0], parts[1], parts[2]).add(Duration(days: days));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${moment.year.toString().padLeft(4, '0')}-'
      '${two(moment.month)}-${two(moment.day)}';
}

final RegExp _localDateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
