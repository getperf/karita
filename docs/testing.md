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

conformance の Python 相互運用試験、golden の更新、既知の失敗は [tools/conformance/README.md](../tools/conformance/README.md) を参照してください。
