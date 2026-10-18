# テスト

ルートで `flutter pub get` を実行してから、各パッケージのディレクトリで実行します。

```powershell
cd packages/karita_platform
dart test
```

Flutter に依存する `karita_app` / `karita_ui` / `karita_platform_flutter` と example/harness は `flutter test` を使います。apps/karita には単独のテストファイルがなく、Windows ビルドと合成層の試験で確認します。
その他のテストを持つ packages、tools/conformance は `dart test` を使います。karita_book_cache と tools/drive_probe には単独の test ディレクトリがなく、利用側の試験で確認します。

実 Drive の試験は `dart test -P drive`、実公開 API は `dart test -P live` として各パッケージで明示します。
通常実行では除外されます。実資格情報・ネットワークが必要な試験は通常の単体試験と分けてください。

conformance の Python 相互運用試験は任意です。兄弟ディレクトリの参照実装 book-sync-model と uv が必要で、
環境がない場合はスキップされます。公開リポジトリ単独の受け入れではこの試験の成功を主張しません。
各試験のスキップ理由を確認します。

golden を更新する場合は tools/conformance の CLI を使い、fixture と検算値を一緒に確認します。

```powershell
cd tools/conformance
dart run bin/conformance.dart --help
```

## 既知の失敗

移行時の通常試験で `tools/conformance/test/reservation_sync_test.dart` の
`wanted preference travels through sync, clear, backup and restore` が失敗しています。
元リポジトリでも同じ試験が失敗することを確認しており、移行による差異とは区別しています。
同期の wanted preference の解除に関する期待値不一致です。修正と再検証が必要です。