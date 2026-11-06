# Windows Store 1.0.6 更新

2026-11-06（JST）。ソースは codex/windows-store-1.0.5 の cea96e8。origin/mainは取得して確認済みで、このブランチに未取り込みの変更なし。

- アプリ版 1.0.6+4、MSIX 1.0.6.0 / x64 / Getperf.karita。
- 変更：予約先の区の確認画面から、その本の図書館ページを開く（820a04a）。
- 成果物：apps/karita/build/msix-store/karita-store.msix。
- SHA-256：10EE3FEE3FB63347EF7169D9CB2D648ED413FADB9F4BDA52D639593371A5491B。
- tools/build-windows-store.ps1で生成。既存のbuild/release-inputのDesktop OAuth設定を使用。token.json・.env・Android資格情報の混入検査を通過。
- 予約UIテスト34件、蔵書照会テスト22件成功。全体・同期conformanceは再実行していない。
- WACK：build/wack/20261106-110810/report.xml。終了0、総合PASS。任意FAILはNOTICES.Zとプロセス起動API・実行ファイル名参照の2件。前回と同種。
- Partner Center：Store ID 9P4DVHV81JSP、Submission 7 / 1152921505702328981。1.0.6.0をアップロード・解析し、旧1.0.5.0を置換して保存。Packages Validated / Updated。
- 審査説明と日本語リリースノートを1.0.6へ更新。既存の手動公開設定を確認。
- Store経由の更新、Google認証・同期・再起動後保持、ガイドの実機受入は未実施。
