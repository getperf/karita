# karita

複数の図書館の予約・貸出し記録と読書履歴をまとめて管理する Windows / Android アプリです。
書誌情報はカーリル・openBD へ端末から問い合わせ、アプリデータは利用者自身の Google Drive のアプリ専用領域で同期します。

## 利用案内

使い方・対応環境・入手方法は [公式ガイド](https://karita.getperf.net/) を参照してください。

- [使い方ガイド](https://karita.getperf.net/guide/)
- [ブラウザー拡張の入れ方](https://karita.getperf.net/extensions/)
- [プライバシーポリシー](https://karita.getperf.net/privacy/)
- [利用規約](https://karita.getperf.net/terms/)

ブラウザー拡張「karita に送る」は、利用者が選んだページの URL を同じ端末のアプリへ渡します。
図書館サイトへのログイン・予約手続きはブラウザーで行い、アプリが自動取得するものではありません。

## 開発

- [環境構築・起動](docs/development.md)
- [構成](docs/architecture.md)
- [テスト](docs/testing.md)
- [配布物の生成](docs/release.md)

## ライセンス

本体・ブラウザー拡張を含むオリジナルコードは [MIT License](LICENSE) で提供します。
第三者ライブラリ・素材はそれぞれのライセンスに従います。
