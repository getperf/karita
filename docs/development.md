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

1. Google Cloud Console → 対象プロジェクト → API とサービス → ライブラリ → 「Google Drive API」を有効化
2. OAuth 同意画面（Google Auth Platform）を設定する
   - データアクセスにスコープ `https://www.googleapis.com/auth/drive.appdata` を追加
   - 公開ステータスが「テスト」の場合は、サインインに使うアカウントをテストユーザーに追加
3. API とサービス → 認証情報 → 認証情報を作成 → OAuth クライアント ID → アプリケーションの種類「デスクトップ アプリ」で作成
4. 作成したクライアントの「JSON をダウンロード」で JSON を保存する（`{"installed": {...}}` 形式）
5. 保存した JSON を `karita-core-desktop.json` にリネームし、`KARITA_HOME/credentials/` に置く（既定では `%LOCALAPPDATA%/Karita/credentials/`。このフォルダーは自動作成されないため手で作る）

ファイル名は既存互換のため維持しています。既定の通常データ領域は `%LOCALAPPDATA%/Karita` です。
隔離する場合は `tools/run-dev.ps1 -KaritaHome <専用の絶対パス>` を使います。
Android の Google 認証には自分のパッケージ・署名に対応する設定が必要です。
開発者の資格情報はこのリポジトリには含みません。

本番・harness を同じデータ領域で同時起動しないでください。同期・復元の試験には専用アカウントとデータを使います。

## 初回セットアップの再現（使い捨て環境）

「karita をはじめる」からの初回導線や、同期・復元の動きを確かめるときは、本番データに触れずに
何度でもやり直せる使い捨て環境を使います。`tools/first-run-env.ps1` が、端末ごとの
`KARITA_HOME` を作り直し、その領域で release 版を起動します。

前提として、本番とは別の検証用 Google アカウントを使います（同期・復元の試験で本番の記録を
壊さないため）。Desktop の資格情報は、既定では本番の
`%LOCALAPPDATA%/Karita/credentials/karita-core-desktop.json` から1ファイルだけ写します
（`-Credentials` で変更できます）。領域の置き場は既定で `%TEMP%/karita-first-run`（`-Root` で変更）です。

| 操作 | 内容 |
| --- | --- |
| `-Action status` | 領域の状態（目印・資格情報・token・台帳の有無）を表示する |
| `-Action reset [-Device a\|b]` | 端末の領域を消して作り直し、資格情報だけを置き直す |
| `-Action run [-Device a\|b]` | その領域で release 版を起動する |
| `-Action whoami` | その領域で接続中のアカウントを表示する |
| `-Action purge-drive -Account <検証用> [-Yes]` | 検証用アカウントの Drive データを空にする。`-Yes` が無ければ件数を数えるだけ |

端末名（`-Device`）ごとに領域が分かれるので、`a` と `b` を順に起動すると「既存の端末がある」状態を作れます。
一周の例:

```powershell
tools/first-run-env.ps1 -Action reset           # 端末 a を初期インストール前の状態に戻す
tools/first-run-env.ps1 -Action run             # 検証用アカウントでサインイン →「新しく始める」
tools/first-run-env.ps1 -Action whoami          # 接続先が検証用アカウントか確かめる
tools/first-run-env.ps1 -Action reset -Device b
tools/first-run-env.ps1 -Action run -Device b   # 「今の記録に合流する」が出る
tools/first-run-env.ps1 -Action purge-drive -Account <検証用アカウント>        # 件数だけ
tools/first-run-env.ps1 -Action purge-drive -Account <検証用アカウント> -Yes   # Drive を空に戻す
```

安全装置:

- 消すのは目印（`.karita-disposable`）を置いた使い捨て領域だけです。既定の `%LOCALAPPDATA%/Karita`
  やパッケージ専用領域（`%LOCALAPPDATA%/Packages/`）と重なる場所を指定すると、作る前に止まります。
- `purge-drive` は、Drive に接続中のアカウントが `-Account` と一致するときだけ消します。未サインイン・
  アカウント不一致・`-Account` 未指定のときは何もしません。
- `KARITA_HOME` はその実行のあいだだけ効き、呼び出し元のセッションには残しません。
- 別の karita（Store 版・テスト MSIX・開発版）が動いていると起動は既存の窓へ転送されるため、起動前に閉じます。
  端末 a と b も同時には起動できません。

## Android release 署名

release APK のビルドには Git 管理外の2ファイルが必要です。

| ファイル | 内容 |
| --- | --- |
| release keystore（例: `apps/karita/android/keystore/release.jks`） | 署名鍵。既存アプリを更新する場合は前回と同じものを使います |
| `apps/karita/android/key.properties` | keystore の場所とパスワード |

### 手順 1 — keystore を作成する（初回のみ）

一度配布した後に keystore を失うと同じアプリとして更新できないため、パスワードと合わせて安全な場所に保管してください。

```powershell
mkdir apps/karita/android/keystore
keytool -genkeypair -v -keystore apps/karita/android/keystore/release.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias karita
```

`-alias` に指定した値が `keyAlias` になります。既存の keystore の alias が分からない場合は次で確認できます。

```powershell
keytool -list -keystore apps/karita/android/keystore/release.jks
```

### 手順 2 — SHA-1 を取得して Google OAuth Android クライアントを登録する

release 署名の SHA-1 は debug 鍵と異なるため、Android の Google 認証を使う場合は OAuth クライアントへの登録が必要です。

**SHA-1 を確認する:**

```powershell
# APK を直接配布する場合
keytool -list -v -keystore apps/karita/android/keystore/release.jks -alias karita
# → 出力の「SHA1:」行の値を控える
```

Google Play で配布する場合（Play アプリ署名）は、Play Console → 対象アプリ → テストとリリース → アプリの完全性 → アプリ署名 →「アプリ署名鍵の証明書」の SHA-1 を使います。

**OAuth クライアントを登録する:**

1. Google Cloud Console → 対象プロジェクト → API とサービス → 認証情報 → 認証情報を作成 → OAuth クライアント ID
2. アプリケーションの種類に「Android」を選び、パッケージ名 `net.getperf.karita` と上記の SHA-1 を入力して作成

### 手順 3 — key.properties を作成・編集する

```powershell
Copy-Item apps/karita/android/key.properties.example apps/karita/android/key.properties
```

次の4項目を記入します。空欄があるとビルドは失敗します。

| キー | 記入する値 |
| --- | --- |
| `storeFile` | keystore のパス。`apps/karita/android/app` からの相対パス、または絶対パス。Windows でも `/` 区切りで書けます |
| `storePassword` | keystore 自体のパスワード（`-storepass` に渡した値） |
| `keyAlias` | 署名に使う鍵の別名（`-alias` に渡した値） |
| `keyPassword` | その鍵のパスワード（`-keypass`）。作成時に省略した場合は `storePassword` と同じ値 |

記入例（値はダミーです）:

```properties
storeFile=../keystore/release.jks
storePassword=your-store-password
keyAlias=karita
keyPassword=your-key-password
```

### 手順 4 — release APK をビルドする

```powershell
cd apps/karita
flutter build apk --release --dart-define-from-file=../../.env
```

生成物は `apps/karita/build/app/outputs/flutter-apk/app-release.apk` です。
反映まで数分かかることがあります。release APK を実機に入れて Google サインインを確認してください。

`key.properties` が無い・項目が空・keystore が見つからない場合は Gradle がその旨のエラーで停止します。