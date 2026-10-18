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

## Android release 署名

release APK の生成には、次の2つのローカルファイルが必要です。どちらも Git 管理外です。

| ファイル | 内容 |
| --- | --- |
| release keystore（例: `apps/karita/android/keystore/release.jks`） | 署名鍵を収めたファイル。既存アプリを更新する場合は、前回と同じものを使います |
| `apps/karita/android/key.properties` | keystore の場所とパスワード。`key.properties.example` をコピーして作ります |

`key.properties` には次の4項目を記入します。空欄の項目があるとビルドは失敗します。

| キー | 記入する値 |
| --- | --- |
| `storeFile` | keystore ファイルのパス。`apps/karita/android/app` からの相対パス、または絶対パス。Windows でも `/` 区切りで書けます |
| `storePassword` | keystore 自体のパスワード（`keytool -genkeypair` の `-storepass`） |
| `keyAlias` | keystore 内で署名に使う鍵の別名（`-alias`） |
| `keyPassword` | その鍵のパスワード（`-keypass`）。作成時に省略した場合は `storePassword` と同じ値 |

記入例（値はダミーです）:

```properties
storeFile=../keystore/release.jks
storePassword=your-store-password
keyAlias=karita
keyPassword=your-key-password
```

keystore をまだ持っていない場合は、次のように作成します。`-alias` に指定した値が `keyAlias` になります。
一度配布した後に keystore を失うと同じアプリとして更新できないため、パスワードと合わせて保管してください。

```powershell
mkdir apps/karita/android/keystore
keytool -genkeypair -v -keystore apps/karita/android/keystore/release.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias karita
```

既存の keystore の alias が判らない場合は `keytool -list -keystore <keystore のパス>` で確認できます。

release ビルドでは debug 鍵への自動切り替えは行いません。
`key.properties` が無い・項目が空・keystore が見つからない場合は、Gradle がその旨のエラーで停止します。
release 署名の SHA-1 は debug 鍵と異なるため、Android の Google 認証を使う場合は OAuth の Android クライアントにも登録します。

1. SHA-1 を確認する
   - APK を直接配布する場合: `keytool -list -v -keystore <keystore のパス> -alias <keyAlias>` の `SHA1:` 行
   - Google Play で配布する場合（Play アプリ署名）: Play Console → 対象アプリ → テストとリリース → アプリの完全性 → アプリ署名 → 「アプリ署名鍵の証明書」の SHA-1
2. Google Cloud Console → 対象プロジェクト → API とサービス → 認証情報 → 認証情報を作成 → OAuth クライアント ID
3. アプリケーションの種類に「Android」を選び、パッケージ名 `net.getperf.karita` と手順 1 の SHA-1 を入力して作成
4. 反映まで数分かかることがあります。release APK を実機に入れて Google サインインを確認します

```powershell
cd apps/karita
flutter build apk --release --dart-define-from-file=../../.env
```

生成物は `apps/karita/build/app/outputs/flutter-apk/app-release.apk` です。