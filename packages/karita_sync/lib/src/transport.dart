/// 転送の **port**。実装に依らない部分だけを置く。
///
/// 転送先のイベントは不変で、決定的なファイル名と内容ハッシュを持つ。**転送は封筒を解釈
/// しない** — 生の文字列を運ぶだけで、検証も適用も呼び出し側が行う。壊れた封筒を転送層で
/// 捨てると、受信側が「取り込めないイベントを破棄しない」を守れなくなる。
///
/// **ここに実装を置かない。** `karita_platform` が Drive を実装し（P2）、`dir` 相当は試験側が
/// 持つ。整列（[sortKey]）と重複排除（[dedupe]）だけは共有する — 実装ごとに違うと、
/// 「一覧には出るのに検索では見つからない」封筒が生まれ、再送が重複リモートイベントを作る。
///
/// 移送元: book-sync-model の `src/bsync_core/transport.py`（実装に依らない部分）。
library;

import 'package:karita_contract/canonical.dart' as canonical;
import 'package:karita_contract/errors.dart';
import 'package:karita_contract/json_reader.dart';

const String transportDir = 'dir';
const String transportDrive = 'drive';

const String filenamePrefix = 'event-';
const String filenameSuffix = '.json';

/// その世代の封筒だけが持つ前置。
///
/// **`event-` を残したまま `generationId` を足す。** `generation-...` のような別前置にすると、
/// 新世代のイベントが一覧の名前判定に1件も当たらず、「同期済み・0件」という静かな成功になる。
String generationPrefix(String generationId) => '$filenamePrefix$generationId-';

String eventName(String generationId, String eventId) =>
    '${generationPrefix(generationId)}$eventId$filenameSuffix';

/// **有効世代の**封筒のファイル名か。
///
/// 転送先は他のものと共有されうる。名前で絞らないと、封筒でないものを `invalid` として数える。
bool isEventName(String name, String generationId) =>
    name.startsWith(generationPrefix(generationId)) && name.endsWith(filenameSuffix);

/// 封筒のファイル名が名乗る `eventId`。**有効世代の封筒でなければ `null`。**
///
/// **使ってよいのは「本文を取らずに済ませる」判定だけである**（[KnownEvent]）。適用の正しさは
/// 本文の `eventId` から決める。故障注入の複製（`<eventId>--<n>`）のように名前が ID そのもので
/// ないものは、どの表にも無い値になるので本文を取りに行く — 取りこぼしにはならない。
String? eventIdOfName(String name, String generationId) {
  if (!isEventName(name, generationId)) return null;
  return name.substring(
      generationPrefix(generationId).length, name.length - filenameSuffix.length);
}

/// 端末が既に知っている `eventId` か。**真なら一覧は本文を取らずに飛ばす**
/// （`非公開資料:sqlite-drive-sync-protocol.md`「受信は差分で取る」）。
typedef KnownEvent = bool Function(String eventId);

/// アップロードは届いたかもしれないが、応答を得られなかった。
///
/// **失敗ではなく「不明」である。** 未送信と決めつけて送り直すと重複イベントを作る。
class TransportTimeout extends SyncDataError {
  // super パラメータへは畳めない（明示の super 呼び出しで code を固定するため）。
  // ignore: use_super_parameters
  TransportTimeout(String message) : super(message, code: 'transport-timeout');
}

/// アクセストークンを得られない。outbox を捨てず `blocked_auth` にする。
class TransportAuthError extends SyncDataError {
  // super パラメータへは畳めない（明示の super 呼び出しで code を固定するため）。
  // ignore: use_super_parameters
  TransportAuthError(String message) : super(message, code: 'transport-auth');
}

/// 転送先にある1件。
///
/// `text` は受信した生の文字列である。解析前に捨てない。`eventId` は読めなければ null で、
/// その場合は呼び出し側が `invalid` として記録する。
///
/// `duplicateRemoteIds` は、同じ `eventId` を持っていて重複排除で落とされた側の識別子である。
/// 落とした事実まで消すと、片方の端末だけが壊れた封筒を書き続けても誰も気づかない。
/// `duplicateMismatch` は落とした側の内容が違っていたことを示す — 「転送先のイベントは不変」の
/// 違反であり、報告する義務がある。
class RemoteEvent {
  final String remoteId;
  final String? eventId;
  final String text;
  final String? createdAtUtc;
  final List<String> duplicateRemoteIds;
  final bool duplicateMismatch;

  const RemoteEvent({
    required this.remoteId,
    required this.eventId,
    required this.text,
    this.createdAtUtc,
    this.duplicateRemoteIds = const [],
    this.duplicateMismatch = false,
  });

  bool get parsed => eventId != null;

  RemoteEvent withDuplicate(String remoteId, {required bool mismatch}) => RemoteEvent(
        remoteId: this.remoteId,
        eventId: eventId,
        text: text,
        createdAtUtc: createdAtUtc,
        duplicateRemoteIds: [...duplicateRemoteIds, remoteId],
        duplicateMismatch: duplicateMismatch || mismatch,
      );
}

/// 転送の port。**定義だけを持ち、実装は持たない。**
///
/// **口は非同期である。** 実装が待つのはネットワークで、Dart に同期 HTTP は無い。同期に
/// しておくと、実装の側が isolate と遮断 socket で非同期を隠すことになり、その機構を転送の
/// 実装が一つ残らず抱える。**待つことを型に出す**方を選んだ。
///
/// 待ち点が入っても適用の原子性は変わらない。転送を呼ぶのは常に `transaction` の**外**で、
/// トランザクションに渡す閉包は DB だけの短い処理である。
///
/// [kind] だけは同期のまま置く。実装ごとの定数であり、待つものが何も無い。
abstract interface class TransportPort {
  String get kind;

  /// 決定的なファイル名へ書く。返るのは転送先の識別子。
  Future<String> put(String eventId, String text);

  /// 全件を整列し、`eventId` で重複を落として返す。
  ///
  /// [known] を渡したときは、名前の `eventId`（[eventIdOfName]）が既知のものを**本文を取らずに
  /// 落とす。** 返る列は「まだ知らないもの」だけになる。渡さなければ従来どおり全件である。
  Future<List<RemoteEvent>> list({KnownEvent? known});

  /// `eventId` で1件を引く。**一覧と同じ結果でなければならない。**
  Future<RemoteEvent?> find(String eventId);

  Future<void> delete(String remoteId);
}

/// 整列と重複排除に要る二つだけを先に読む。
///
/// **ここでスキーマ検証をしない。** 未対応 `schemaVersion` の封筒は形自体が変わりうるため、
/// 転送層で弾くと受入ケース06 が成立しない。
({String? eventId, String? createdAtUtc}) peekIds(String text) {
  Object? obj;
  try {
    obj = loadsJson(text, label: '封筒');
  } on SyncDataError {
    return (eventId: null, createdAtUtc: null);
  }
  if (obj is! Map<String, Object?>) return (eventId: null, createdAtUtc: null);
  final eventId = obj['eventId'];
  final created = obj['createdAtUtc'];
  return (
    eventId: (eventId is String && eventId.isNotEmpty) ? eventId : null,
    createdAtUtc: created is String ? created : null,
  );
}

/// `(createdAtUtc, eventId, 転送先の識別子)` 昇順。読めなかったものは末尾へ回す。
///
/// **整列は再現性のためであり、正しさを整列に依存させない。** 適用判定表は到着順に依存せず、
/// 順不同で同じ結果になる（受入ケース11）。
///
/// 末尾の `remoteId` は、同一 `eventId` の複製がある場合にどれを採るかを決める。これが無いと
/// 重複排除の結果がファイルの列挙順に依存する。
int compareRemote(RemoteEvent a, RemoteEvent b) {
  final rankA = a.eventId == null ? 1 : 0;
  final rankB = b.eventId == null ? 1 : 0;
  if (rankA != rankB) return rankA - rankB;
  if (rankA == 1) return a.remoteId.compareTo(b.remoteId);
  final byCreated = (a.createdAtUtc ?? '').compareTo(b.createdAtUtc ?? '');
  if (byCreated != 0) return byCreated;
  final byEvent = a.eventId!.compareTo(b.eventId!);
  if (byEvent != 0) return byEvent;
  return a.remoteId.compareTo(b.remoteId);
}

/// 二つの封筒が同じ内容か。正準化して比べる。
///
/// 読めない側は「違う」に倒す — 判定できないものを同一とみなすと、壊れた複製が黙って消える。
bool sameContent(String left, String right) {
  if (left == right) return true;
  try {
    return canonical.dumpsText(loadsJson(left, label: '封筒')) ==
        canonical.dumpsText(loadsJson(right, label: '封筒'));
  } on SyncDataError {
    return false;
  }
}

/// `eventId` で重複を落とす。**整列してから呼ぶ。**
///
/// 転送先は同名ファイルの重複作成を許すため、一覧結果には同じ `eventId` が複数現れうる。
/// どれを採るかが列挙順に依存しないよう、整列後の先頭を採る。落とした側は捨てず、採った1件の
/// `duplicateRemoteIds` に記録する。
List<RemoteEvent> dedupe(List<RemoteEvent> events) {
  final indexOf = <String, int>{};
  final kept = <RemoteEvent>[];
  for (final event in events) {
    final id = event.eventId;
    if (id == null) {
      kept.add(event);
      continue;
    }
    final index = indexOf[id];
    if (index == null) {
      indexOf[id] = kept.length;
      kept.add(event);
      continue;
    }
    final first = kept[index];
    kept[index] = first.withDuplicate(event.remoteId,
        mismatch: !sameContent(first.text, event.text));
  }
  return kept;
}

/// 整列・重複排除済みの一覧から1件を選ぶ。
///
/// `find` の意味を一覧と同じに保つための共通実装である。転送ごとに探し方を変えると、
/// 「一覧には出るのに検索では見つからない」封筒が生まれ、再送が重複リモートイベントを作る。
RemoteEvent? firstMatching(List<RemoteEvent> events, String eventId) {
  for (final event in events) {
    if (event.eventId == eventId) return event;
  }
  return null;
}
