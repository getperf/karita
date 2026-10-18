# conformance

同期契約の fixture・golden と検証 CLI です。fixture・golden の正本は `data/` です。

## テスト

```powershell
cd tools/conformance
dart test
```

既定ではネットワークも token も使いません。実 Drive を挟む相互運用試験は `drive` タグで分けてあり、
`dart test -P drive` で明示したときだけ実行されます（`-t drive` では選べません）。

Python 相互運用試験は任意です。兄弟ディレクトリの参照実装 book-sync-model と uv が必要で、
環境がない場合はスキップされます。公開リポジトリ単独の受け入れではこの試験の成功を主張しません。
各試験のスキップ理由を確認します。

## 検証 CLI

```powershell
cd tools/conformance
dart run bin/conformance.dart all                      # D1〜D3 をすべて検証
dart run bin/conformance.dart update-goldens           # 差分を出すだけ
dart run bin/conformance.dart update-goldens --write   # golden を書き換える
```

`canonical`（D1）、`envelope`（D2）、`sync`（D3）を個別に実行することもできます。
終了コードは全一致で 0、1件でも不一致・エラーがあれば 1 です。

golden の更新は規則を意図的に変えたときだけ行い、fixture と検算値を一緒に確認します。

## 既知の失敗

移行時の通常試験で `test/reservation_sync_test.dart` の
`wanted preference travels through sync, clear, backup and restore` が失敗しています。
元リポジトリでも同じ試験が失敗することを確認しており、移行による差異とは区別しています。
同期の wanted preference の解除に関する期待値不一致です。修正と再検証が必要です。
