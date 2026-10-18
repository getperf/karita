/// 既定のブラウザーで開く。**Android の分である。**
///
/// Windows は `rundll32.exe url.dll,FileProtocolHandler` のままで、ここへは来ない
/// （`karita_app` の `openSystemBrowser` が端末で分ける。`_shareInbox()` と同じ形）。
///
/// **認可の経路を変えない。** `LoopbackLogin` が Windows でブラウザーを開く経路は動かして
/// いない — 実物で通っている経路を、別の用途のために置き換えない。Android の認可は
/// Play services なのでブラウザーを使わず、**この関数の読み手は図書館サイトを開く操作だけ**
/// である。
///
/// **`externalApplication` を指定する。** 既定（`platformDefault`）は Android で Custom Tab を
/// 選びうる。連携方針（非公開資料） §2 が
/// Custom Tabs を「補助としても不採用」と決めており、**通常のタブで開いて標準共有で戻る**のが
/// 主導線である。Custom Tab で開くと、その主導線のタブ操作が前提にできなくなる。
library;

import 'package:url_launcher/url_launcher.dart';

/// 開く。**開けなければ投げる。**
///
/// 起動の成功は**ページ表示でもログイン成功でもない**。
/// 呼ぶ側は「開いた」以上のことを
/// この戻り値から読まない。
Future<void> openInExternalBrowser(Uri url) async {
  final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!launched) {
    throw StateError('Could not open the browser for ${url.scheme}');
  }
}
