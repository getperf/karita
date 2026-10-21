# 配布物の生成

アプリの版と MSIX 版は apps/karita/pubspec.yaml、拡張の版は extension/chromium/manifest.json で管理します。

## Windows

Windows 開発環境で、自分の Desktop OAuth 設定とビルド設定を用意して実行します。

```powershell
tools/build-windows-store.ps1 -DesktopCredentials <設定ファイルのパス> -DefinesFile <ビルド設定のパス>
```

`-DefinesFile` の相対パスはリポジトリのルートを基準に解決されます（省略時は `.env`）。

実行例:

```powershell
tools/build-windows-store.ps1 -DesktopCredentials $env:LOCALAPPDATA\Karita\credentials\karita-core-desktop.json -DefinesFile .env
```

既定の MSIX identity は製品の登録値です。第三者が独自配布する場合は自分の発行元・identity を設定してください。
このコマンドはStore提出用の未署名パッケージを生成し、ローカルへのインストールやStore申請は行いません。
通常の開発ビルドには `flutter build windows --release` を使えます。

生成物は apps/karita/build/msix-store/karita-store.msix です。LICENSE の同梱、版、identity、
token / .env / 不要な資格情報が入っていないことを確認し、必要な単体試験と WACK を実行します。
審査結果は検証対象のハッシュと対応させます。既存の提出済みファイルを同じ版の別内容と混同しないでください。

## Android

**事前準備:** release keystore と `apps/karita/android/key.properties` が必要です。
初回の作成手順は [development.md — Android release 署名](development.md#android-release-署名) を参照してください。

```powershell
cd apps/karita
flutter build apk --release --dart-define-from-file=../../.env
```

生成物は `apps/karita/build/app/outputs/flutter-apk/app-release.apk` です。
token / .env / 不要な資格情報が含まれていないことを確認し、実機に入れて Google サインインと
基本動作を確認します。Google Play で配布する場合は Play Console へのアップロードに別途手順が必要です。

## ブラウザー拡張

```powershell
cd <リポジトリのルート>/extension/chromium
npx --yes web-ext@10.7.0 lint --ignore-files README.md web-ext-artifacts
npx --yes web-ext@10.7.0 build --ignore-files README.md web-ext-artifacts
```

生成物は extension/chromium/web-ext-artifacts/karita_-<版>.zip です。
同じ版の ZIP が既にあると build は失敗します。作り直す場合は既存の ZIP を退避してから実行してください。

ZIP に manifest.json、popup.html、popup.js、LICENSE、icons/ の3サイズが入ることを確認します。
Firefox はMozillaの署名・審査、Chrome / Edge は各ストアへの登録が必要です。
Firefox は142以降を対象に、ローカルアプリへのURL受け渡しを browsingActivity として申告しています。
ストア入力・公開予定・審査メモ・提出履歴は公開ソースとは別に管理します。
