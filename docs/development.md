# 開発

Flutter / Dart の pub workspace です。Windows のビルドには Flutter の Windows desktop 開発環境
（Visual Studio の C++ desktop workload と Windows SDK）が必要です。
Dart SDK の制約はルート pubspec.yaml、Flutter の制約は apps/karita/pubspec.yaml を参照してください。

リポジトリ直下で依存関係を解決します。

```powershell
flutter pub get
Copy-Item .env.example .env
```

`.env` のカーリル appkey は自分の値に置き換えるか、未設定なら行ごと削除します。
未設定でも起動しますが、蔵書照会など一部の機能は利用できません。`.env` の値はビルド時に組み込まれます。
OAuth token や秘密情報を記入しないでください。

画面だけを確認する場合:

```powershell
tools/run-dev.ps1 --dart-define=KARITA_DEMO=memory
```

通常起動:

```powershell
tools/run-dev.ps1
tools/run-dev.ps1 -Device <android-device-id>
```

Windows の Google サインインには自分の Desktop OAuth クライアント設定が必要です。
`KARITA_HOME/credentials/karita-core-desktop.json` に installed 形式の設定を用意します。
ファイル名は既存互換のため維持しています。既定の通常データ領域は `%LOCALAPPDATA%/Karita` です。
隔離する場合は `tools/run-dev.ps1 -KaritaHome <専用の絶対パス>` を使います。
Android の Google 認証には自分のパッケージ・署名に対応する設定が必要です。
開発者の資格情報はこのリポジトリには含みません。

本番・harness を同じデータ領域で同時起動しないでください。同期・復元の試験には専用アカウントとデータを使います。
