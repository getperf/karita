# karita に送る

Chrome / Edge / Firefox 共通の Manifest V3 拡張です。
利用者の操作で現在のページ、または許可された元のカーリル書籍の URL を同じ端末の karita へ渡します。
別途 Windows 版 karita と karita:// の起動登録が必要です。Firefox は142以降です。

- [入れ方と使い方](https://karita.getperf.net/extensions/)
- [プライバシーポリシー](https://karita.getperf.net/privacy/)
- [パッケージ生成](../../docs/release.md)
- [MIT License](LICENSE)

開発時、Chrome / Edge はこのディレクトリを展開して読み込めます。
Firefox の一時読み込みは再起動で消え、通常配布には署名が必要です。
URL をローカルアプリへ渡すため browsingActivity を申告しています。拡張は外部通信・永続保存を行いません。
ISBN の受理と用途の最終判断はアプリ側で行います。
