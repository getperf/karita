/// `appDataFolder` を転送先にする `TransportPort` の実装。
///
/// **この層が持つのは、Drive API の応答を `RemoteEvent` の列に変換する部分だけ**である。整列
/// （`compareRemote`）と重複排除（`dedupe`）は `karita_sync` の共有実装をそのまま通す。置き場
/// ごとに別実装にすると、重複の畳み方が置き場で違ってしまい、同じ受入ケースが片方でだけ緑に
/// なる。
///
/// **転送は封筒を解釈しない。** 生の文字列を運ぶだけで、検証も適用も呼び出し側が行う。名前で
/// 絞るのは封筒の解釈ではなく、転送先の中で自分の名前空間（世代）を決めているだけである。
///
/// 移送元: book-sync-model の `src/bsync_core/drive.py`（`DriveTransport`）。
library;

import 'package:karita_sync/karita_sync.dart';

import 'drive_client.dart';

class DriveTransport implements TransportPort {
  final DriveClient client;
  final String generationId;

  DriveTransport(this.client, this.generationId);

  @override
  String get kind => transportDrive;

  /// 常に新しいファイルを作る。
  ///
  /// **同名ファイルの重複作成は故障ではなく仕様である。** Drive は `create` で既存を上書き
  /// しない。重複は受信側の `dedupe` が `eventId` で畳む（受入ケース07）。ここで「既にあるか」
  /// を調べてから書くと、書込み直後に一覧へ現れない転送先では調べるだけ無駄になり、往復だけが
  /// 倍になる。
  @override
  Future<String> put(String eventId, String text) => client.create(
    eventName(generationId, eventId),
    indexProperties(eventId, text),
    text,
  );

  /// **名前で世代に絞り、既知の封筒は本文を取らない**（`sqlite-drive-sync-protocol.md`
  /// 「受信は差分で取る」）。毎回全本文を取ると、所要時間がイベント数に比例する。
  @override
  Future<List<RemoteEvent>> list({KnownEvent? known}) =>
      _collect(namePrefixQuery(generationPrefix(generationId)), known: known);

  /// `appProperties` のサーバ側クエリで引く。
  ///
  /// 索引で絞った後、**本文の `eventId` が一致するものだけ**を採る。索引は後から書き換えられ
  /// うるメタデータであり、既送信とみなす根拠にはできない。
  @override
  Future<RemoteEvent?> find(String eventId) async =>
      firstMatching(await _collect(eventIdQuery(eventId)), eventId);

  /// 手で復旧するときの経路としてだけ持つ。
  ///
  /// 転送先にあるのはイベントだけで、消せば新しい端末はその分を再生できない。通常の運用から
  /// ここへ到達させない。
  @override
  Future<void> delete(String remoteId) => client.delete(remoteId);

  /// `pageToken` のループ。**ページを跨いだ大域の順序は無いものとして扱う。**
  ///
  /// 転送先は同じアプリの他のものと共有される。**名前で絞るのは本文を取る前である** — 封筒で
  /// ないファイルを `invalid` として数えないためと、要らない本文を落とさないためである。
  Future<List<RemoteEvent>> _collect(String? query, {KnownEvent? known}) async {
    final events = <RemoteEvent>[];
    final seen = <String>{};
    String? pageToken;
    while (true) {
      final page = await client.listPage(pageToken: pageToken, query: query);
      for (final ref in page.files) {
        if (!isEventName(ref.name, generationId)) continue;
        final named = eventIdOfName(ref.name, generationId);
        if (known != null && named != null && known(named)) continue;
        // ページの境界で同じファイルが二度返ることがある。file id は一意なので、ここで落とす
        // のは複製ではなく重複ページである。
        if (!seen.add(ref.fileId)) continue;
        events.add(await _toEvent(ref));
      }
      pageToken = page.nextPageToken;
      if (pageToken == null) break;
    }
    events.sort(compareRemote);
    return dedupe(events);
  }

  /// 本文を取ってから `RemoteEvent` にする。
  ///
  /// 整列に使う `createdAtUtc` は**本文から読む**。索引の値や保管先の作成時刻を使うと、端末の
  /// 時計と保管先の時計が混ざり、整列の基準が端末をまたいで揺れる。
  Future<RemoteEvent> _toEvent(FileRef ref) async {
    final text = await client.getText(ref.fileId);
    final ids = peekIds(text);
    return RemoteEvent(
      remoteId: ref.fileId,
      eventId: ids.eventId,
      text: text,
      createdAtUtc: ids.createdAtUtc,
    );
  }
}
