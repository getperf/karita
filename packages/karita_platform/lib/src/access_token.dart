/// 認可の口。**「必要時に access token を取得すること」だけ**を抽象する。
///
/// Windows は loopback + PKCE で自分で refresh し、Android は Play services の
/// Authorization API に任せる。両者に共通する形はこれしか無い — 取得の手順も、保存の場所も、
/// refresh token の有無すら違う。**共通部分を広げるほど、どちらかの実装が嘘をつく。**
///
/// **口は純 Dart に置く。** Android の実装は Flutter プラグインを要るので
/// `karita_platform_flutter` が持ち、Windows の実装だけがここに来る。`BackupStorePort` を
/// 定義側と実装側に割ったのと同じ形である。
///
/// 移送元: book-sync-model の `src/bsync_core/gauth.py`（呼び出し側から見える部分）。
library;

import 'package:karita_sync/karita_sync.dart';

abstract interface class AccessTokenProvider {
  /// 有効な access token を返す。
  ///
  /// **取れなければ [TransportAuthError] を投げる。** 空文字や null を返さない — 呼び出し側が
  /// 「認可が無い」と「トークンが空だった」を区別できないまま要求を組み、サーバの 401 として
  /// 返ってくることになる。同じ結末に見えて、outbox の行が `blocked_auth` へ落ちる根拠が
  /// 一段遠くなる。
  ///
  /// [forceRefresh] は、いま持っているトークンをサーバが 401 で拒んだときに立てる。**これが
  /// 無いと、期限切れの1回が「認可を失った」と区別できない。** 実際に失われているなら、
  /// refresh もまた [TransportAuthError] で落ちる。
  Future<String> accessToken({bool forceRefresh = false});
}

/// 資格情報そのものが無効になったことを表す OAuth のエラーコード。
///
/// refresh の応答がこれを返したら、**再ログイン以外に回復手段は無い**。通信の失敗と混ぜない —
/// 混ぜると、回線が落ちているだけの端末が「サインインが必要」と表示し続ける。
const String invalidGrant = 'invalid_grant';
