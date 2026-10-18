/// 業務層が投げる例外。
///
/// **`code` は言語間で共有する契約である。** Python の `BlibError` 系と同じ文字列を使う
/// （`candidate`・`book-exists`・`start-status`・`invalid-transition` …）。Dart の enum へ
/// 写すと写しがずれ、ずれても両方の試験が自分の正本に対して緑になる。
///
/// **`SyncDataError` を継ぐ形にはしない。** 業務の失敗と契約の失敗は別物で、混ぜると
/// 「封筒が規則に合わない」と「その遷移は許されない」が同じ枝に落ちる。
///
/// 移送元: book-sync-model の `BookError` / `LoanError`（`contracts.errors.BlibError` の下）。
library;

class DomainError implements Exception {
  final String message;
  final String code;

  const DomainError(this.message, {this.code = 'domain'});

  @override
  String toString() => '[$code] $message';
}

/// Book の採用で落ちたもの。
class BookError extends DomainError {
  const BookError(super.message, {super.code});
}

/// Loan の作成・遷移で落ちたもの。
class LoanError extends DomainError {
  const LoanError(super.message, {super.code});
}

/// 図書館システムの登録・削除で落ちたもの。
class LibrarySystemError extends DomainError {
  const LibrarySystemError(super.message, {super.code});
}
