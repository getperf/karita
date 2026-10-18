/// 契約層が投げる例外。
///
/// `SyncDataError` は封筒・payload・同期テーブルの内容が規則に合わないことを表す。
/// **持つのは `code`（文字列）と `message` だけである。** code は言語間で共有する契約であり、
/// `contracts/fixtures/invalid/manifest.json` の文字列と直接照合する。Dart の enum へ写すと
/// 写しがずれ、ずれても両方のテストが自分の正本に対して緑になる（注意点はこの文書の指す通り）。
library;

class SyncDataError implements Exception {
  final String message;
  final String code;

  const SyncDataError(this.message, {this.code = 'sync-data'});

  @override
  String toString() => '[$code] $message';
}
