/// 送信。outbox の行を転送先へ載せる。
///
/// 送信は lease で押さえる。`pending` → `uploading`（lease）→ `uploaded` の三段で、確定はそれぞれ
/// 独立したトランザクションである。**送信結果が不明な行は lease を保持したまま `uploading` に
/// 残す。** 他のプロセスが直ちに再送すると重複リモートイベントを作るためである（受入ケース08）。
///
/// 競合の検出は push を止めない。自端末の更新を送らなければ相手は競合を検出できず、往復が
/// 始まらない（`blocked_conflict` は未使用である）。
///
/// 移送元: book-sync-model の `src/bsync_cli/commands/sync_cmd.py`（push_outbox）。
library;

import 'package:karita_contract/karita_contract.dart';

import 'transport.dart';

class PushResult {
  final List<Map<String, Object?>> sent;
  final List<Map<String, Object?>> stopped;

  const PushResult(this.sent, this.stopped);
}

/// 転送先に同じイベントが既にあるか。**`payloadHash` が一致するときだけ**既送信とみなす。
///
/// `eventId` が見つかっただけで既送信とすると、内容の違う封筒が同じ `eventId` で先に置かれて
/// いた場合に、自分の更新が送られないまま `uploaded` になる。
///
/// 転送の `find` を使う。全件一覧から探すと、実 Drive では再送1件ごとに `pageToken` のループが
/// 1周する。
Future<String?> alreadyUploaded(
    EnvelopeCodec codec, TransportPort transport, Envelope envelope) async {
  final item = await transport.find(envelope.eventId);
  if (item == null) return null;
  try {
    final remote = codec.loads(item.text);
    return remote.payloadHash == envelope.payloadHash ? item.remoteId : null;
  } on SyncDataError {
    // 読めない封筒は一致の根拠にならない。送り直す方が安全である。
    return null;
  }
}

/// 送信待ちの outbox を送る。`(送れたもの, 送れなかったもの)` を返す。
///
/// 1件ごとに独立したトランザクションで状態を進める。まとめて確定すると、途中で落ちたときに
/// 「送ったが pending のまま」の行と「送っていないが uploaded」の行が混ざる。前者は再送で
/// 回復できるが、後者は永久に届かない。**送信の後に `uploaded` を確定する**順序を守る。
///
/// lease の確定だけは送信の前に置く。送信中であることが他のプロセスから見えなければ、lease は
/// 何も守らない。
Future<PushResult> pushOutbox(
  Db db,
  EnvelopeCodec codec,
  TransportPort transport, {
  required String now,
  required String runId,
}) async {
  final sent = <Map<String, Object?>>[];
  final stopped = <Map<String, Object?>>[];
  final handled = <String>{};

  while (true) {
    final row = transaction(db, () => claimOutbox(db, runId: runId, now: now));
    if (row == null) break;
    final eventId = row['event_id'] as String;
    if (!handled.add(eventId)) break; // 状態遷移の取りこぼし避け。

    // **封筒に組み立て直せない行がある。** 自端末が発行した後に、その `entityType` を受理
    // しなくなった場合である。**この1件で run を止めない。** 落とした集約の未送信行が1件でも
    // 残っていると、以後 push も pull も動かなくなる。
    //
    // **lease を解放しない。** `pending` へ戻すと同じ run の次の `claimOutbox` が同じ行を
    // 拾い直し、後ろに並ぶ正常な行が送られないまま `handled` の判定で止まる。lease を持たせた
    // まま置けば `claimOutbox` はこの行を飛ばし、残りを送り切れる。**行は捨てない。**
    final Envelope envelope;
    try {
      envelope = envelopeFromOutboxRow(codec, row);
    } on SyncDataError catch (exc) {
      transaction(db, () {
        setOutboxState(db, eventId, row['state'] as String,
            updatedAtUtc: now, lastError: exc.message);
        recordAttempt(db,
            runId: runId,
            eventId: eventId,
            direction: 'push',
            outcome: 'error',
            detail: '[${exc.code}] ${exc.message}',
            atUtc: now);
      });
      stopped.add(
          {'event_id': eventId, 'state': row['state'], 'reason': exc.message});
      continue;
    }

    var remoteId = row['remote_file_id'] as String?;
    var resent = false;

    // **検索も try の中に置く。** 認可を失った状態で再取得した行は、送信ではなく検索の側で
    // 401 を受ける。ここを外に出すと例外が push ループの外へ抜け、`blocked_auth` にならない
    // まま `uploading` と lease が残る。
    try {
      if (remoteId == null && (row['attempts'] as int) > 1) {
        // 再取得。応答で file id を得られなかった場合だけ検索する。初回から一覧を引くと、
        // 送信のたびに転送先の全件取得が入る。
        remoteId = await alreadyUploaded(codec, transport, envelope);
        resent = remoteId != null;
      }
      remoteId ??= await transport.put(envelope.eventId, envelope.canonicalText());
    } on TransportAuthError catch (exc) {
      // 401 を受けた行だけを止める。残りは pending のまま残す — 送れたかもしれない行の状態を
      // 推測で書かない。outbox は捨てない。
      transaction(db, () {
        setOutboxState(db, envelope.eventId, outboxBlockedAuth,
            updatedAtUtc: now, lastError: exc.message, clearLease: true);
        recordAttempt(db,
            runId: runId,
            eventId: envelope.eventId,
            direction: 'push',
            outcome: 'error',
            detail: '[${exc.code}] ${exc.message}',
            atUtc: now);
      });
      stopped.add({
        'event_id': envelope.eventId,
        'state': outboxBlockedAuth,
        'reason': exc.message,
      });
      break;
    } on TransportTimeout catch (exc) {
      // **lease を解放しない。** 届いたかどうかが不明な行であり、失効するまでは誰も触っては
      // ならない。回復は時間に任せる。
      transaction(db, () {
        setOutboxState(db, envelope.eventId, row['state'] as String,
            updatedAtUtc: now, lastError: exc.message);
        recordAttempt(db,
            runId: runId,
            eventId: envelope.eventId,
            direction: 'push',
            outcome: 'error',
            detail: '[${exc.code}] ${exc.message}',
            atUtc: now);
      });
      stopped.add({
        'event_id': envelope.eventId,
        'state': row['state'],
        'reason': exc.message,
      });
      continue;
    }

    transaction(db, () {
      setOutboxState(db, envelope.eventId, outboxUploaded,
          updatedAtUtc: now, remoteFileId: remoteId, clearLease: true);
      recordAttempt(db,
          runId: runId,
          eventId: envelope.eventId,
          direction: 'push',
          outcome: 'uploaded',
          detail: remoteId,
          atUtc: now);
    });
    sent.add({
      'event_id': envelope.eventId,
      'entity_type': envelope.entityType,
      'entity_id': envelope.entityId,
      'result_version': envelope.resultVersion,
      'remote_id': remoteId,
      // 転送先に既にあったので送り直していない。重複リモートイベントを作らない経路。
      'resent': resent,
    });
  }
  return PushResult(sent, stopped);
}
