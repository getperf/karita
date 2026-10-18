/// Book の採用。
///
/// 採用とは、外部の書誌検索で得た候補（[BookCandidate]）を台帳の実体へ昇格させることである。
/// 検索結果そのものは台帳の正本ではないため、**利用者が最終確認した書誌だけ**をここへ渡す。
/// 外部 I/O の失敗や取消ではこのモジュールを呼ばない。
///
/// Loan から切り出してあるのは、採用の入口が二つあるためである。
///
/// | 入口 | 経路 |
/// |---|---|
/// | `adopt` | 非対話。採用だけを確定する |
/// | `Loans.startFromCandidate` | 対話。採用と Loan の開始を一つのトランザクションで確定する |
///
/// **採番規則をここ一箇所に置くのが目的である。** 入口ごとに `bookId` の作り方が違うと、
/// 採用元によって二端末の同一性が成立したりしなかったりする。
///
/// 移送元: book-sync-model の `src/bops_application/books.py`。
library;

import 'package:karita_contract/karita_contract.dart';

import 'context.dart';
import 'errors.dart';

/// 採用は入口が二つあるが、**記録する事実は一つである。** 入口ごとに型を分けると、同じ事実が
/// どこから入ったかによって別の業務イベントとして残る。
const String adoptionEventType = 'BookRegisteredFromReference';

class Books {
  final DomainContext context;

  const Books(this.context);

  /// 採用を確定する。**トランザクションを開かない。**
  ///
  /// 採用と Loan の開始を一つのトランザクションで確定する経路があるため、ここでは開けない。
  /// 単独で使う入口は [adopt] を呼ぶ。
  ///
  /// **`bookId` は ISBN から決定的に導く。** 二端末が同じ ISBN を独立に採用しても同じ id に
  /// なり、二重登録が競合として立って LWW が一件へ収束させる。id を外から渡せるようには
  /// しない — 入口ごとに採番が散ると、採用元によって同一性が成立したりしなかったりする。
  ///
  /// 導出するのは**採用時の一度だけ**であり、採用後に ISBN を訂正しても id は動かさない。id は
  /// 「同時採用の衝突を一致させるための種」であって書誌の従属属性ではなく、動かすと
  /// `Loan.bookId` の参照が宙に浮く。集約間参照に外部キーを張らない設計のため、**これは静かに
  /// 壊れる。**
  Envelope emitAdoption({
    required String title,
    required List<String> authors,
    required String isbn13,
    String? publisher,
    String? sourceUrl,
    required String provider,
    required String now,
  }) {
    // **検証が先で採番が後である。** ISBN が id の種になるため、形の崩れた ISBN から id を
    // 導いてはならない。導いてしまうと、同じ本が表記ゆれの数だけ別の実体になる。
    if (title.trim().isEmpty ||
        isbn13.length != 13 ||
        !_digits.hasMatch(isbn13)) {
      throw const BookError('候補にはタイトルと13桁ISBNが必要です。', code: 'candidate');
    }
    final bookId = deterministicId(entityBook, isbn13);
    if (context.aggregates.read(context.db, entityBook, bookId) != null) {
      throw BookError('同じISBNの Book が既にあります: $bookId（ISBN $isbn13）',
          code: 'book-exists');
    }

    final reference = <String, Object?>{'provider': provider};
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      reference['source_url'] = sourceUrl;
    }
    final payload = <String, Object?>{
      'title': title,
      'authors': [...authors],
      'isbn13': isbn13,
      'book_references': [reference],
    };
    if (publisher != null && publisher.isNotEmpty) {
      payload['publisher'] = publisher;
    }

    return context.emit(
      entityType: entityBook,
      entityId: bookId,
      payload: payload,
      domainEventType: adoptionEventType,
      aggregateType: 'book',
      now: now,
    );
  }

  /// 採用だけを単独で確定する。集約更新と発行の記録（outbox と `applied_events`）が同時に
  /// 確定する。
  Envelope adopt({
    required String title,
    required List<String> authors,
    required String isbn13,
    String? publisher,
    String? sourceUrl,
    required String provider,
    required String now,
  }) =>
      transaction(
        context.db,
        () => emitAdoption(
          title: title,
          authors: authors,
          isbn13: isbn13,
          publisher: publisher,
          sourceUrl: sourceUrl,
          provider: provider,
          now: now,
        ),
      );

  /// 候補からそのまま採用する。**書誌の取り出し方をここに閉じる。**
  Envelope adoptCandidate(BookCandidateInput candidate, {required String now}) =>
      adopt(
        title: candidate.title,
        authors: candidate.authors,
        isbn13: candidate.isbn13,
        publisher: candidate.publisher,
        sourceUrl: candidate.sourceUrl,
        provider: candidate.provider,
        now: now,
      );
}

/// 採用へ渡す確定済みの書誌。**候補そのものではない** — ISBN を持たない候補は採用できず、
/// 利用者が最終確認した後にしかこの形にならない。
class BookCandidateInput {
  final String title;
  final List<String> authors;
  final String isbn13;
  final String? publisher;
  final String? sourceUrl;
  final String provider;

  const BookCandidateInput({
    required this.title,
    required this.authors,
    required this.isbn13,
    required this.provider,
    this.publisher,
    this.sourceUrl,
  });
}

final RegExp _digits = RegExp(r'^\d+$');
