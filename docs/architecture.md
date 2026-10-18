# 構成

| 場所 | 責務 |
|---|---|
| apps/karita | Flutter のエントリーポイント・Windows / Android の runner |
| packages/karita_ui | 画面・状態・表示文言 |
| packages/karita_app | 起動・認証・同期などの合成 |
| packages/karita_domain | 蔵書・貸出し・図書館の業務規則 |
| packages/karita_contract / karita_sync | 保存・同期の契約、SQLite と同期処理 |
| packages/karita_platform / karita_platform_flutter | OS、認証、設定、バックアップの接続 |
| packages/karita_handoff | 外部 URL・ISBN の受理 |
| packages/karita_public_api_client / karita_book_cache / karita_cover | 公開 API、キャッシュ、書影 |
| extension/chromium | Chrome / Edge / Firefox 共通の拡張ソース |
| example/harness | 開発用の観測・動作確認アプリ |
| tools/conformance | 同期契約の fixture・golden と検証 CLI |

アプリ identity、URI scheme、保存先、workspace の識別名は更新互換のため維持しています。
リポジトリ名とルート pubspec の workspace 名は一致する必要がありません。

アプリデータは端末内と利用者の Google Drive のアプリ専用領域で扱います。
Windows の認可情報はユーザー単位 DPAPI で保護し、バックアップから認可情報を復元しません。
拡張は利用者の操作で URL を `karita://share` に渡し、予約の成立判定は行いません。

過去の判断経緯・詳細仕様・実機証跡・審査運用は非公開で管理しています。
ソースコメント中の「非公開資料」は履歴上の文書識別子であり、ビルド入力ではありません。
通常開発に必要な実装・schema・migration・fixture・golden は本リポジトリに含みます。

## 保存済みデータとの互換性

`packages/karita_contract/lib/src/generated/migrations.g.dart` の既存 SQL はコメントを含めて変更しません。
適用時の全文チェックサムがデータベースに保存されるため、文書参照の変更だけでも既存台帳が開けなくなります。
`schema.g.dart` も契約データです。文書の整理・参照置換の対象から除外します。
既存 migration の互換性は `migration_compatibility_test.dart` の固定値で確認します。