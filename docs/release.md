# 配布物の生成

アプリの版と MSIX 版は apps/karita/pubspec.yaml、拡張の版は extension/chromium/manifest.json で管理します。

## Windows

Windows 開発環境で、自分の Desktop OAuth 設定とビルド設定を用意して実行します。

```powershell
tools/build-windows-store.ps1 -DesktopCredentials <設定ファイルの絶対パス> -DefinesFile <ビルド設定の絶対パス>
```

既定の MSIX identity は製品の登録値です。第三者が独自配布する場合は自分の発行元・identity を設定してください。
このコマンドはStore提出用の未署名パッケージを生成し、ローカルへのインストールやStore申請は行いません。
通常の開発ビルドには `flutter build windows --release` を使えます。

生成物は apps/karita/build/msix-store/karita-store.msix です。LICENSE の同梱、版、identity、
token / .env / 不要な資格情報が入っていないことを確認し、必要な単体試験と WACK を実行します。
審査結果は検証対象のハッシュと対応させます。既存の提出済みファイルを同じ版の別内容と混同しないでください。

## ブラウザー拡張

```powershell
npx --yes web-ext@10.7.0 lint --source-dir extension/chromium --ignore-files README.md web-ext-artifacts
npx --yes web-ext@10.7.0 build --source-dir extension/chromium --artifacts-dir extension/chromium/web-ext-artifacts --ignore-files README.md web-ext-artifacts
```

ZIP に manifest.json、popup.html、popup.js、LICENSE、icons/ の3サイズが入ることを確認します。
Firefox はMozillaの署名・審査、Chrome / Edge は各ストアへの登録が必要です。
Firefox は142以降を対象に、ローカルアプリへのURL受け渡しを browsingActivity として申告しています。
ストア入力・公開予定・審査メモ・提出履歴は公開ソースとは別に管理します。
