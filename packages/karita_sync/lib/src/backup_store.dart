/// バックアップの保管先の **port**。実装に依らない部分だけを置く。
///
/// **転送（`transport.dart`）とは別の口である。** 転送が運ぶのは不変の封筒で、`eventId` で畳み
/// `createdAtUtc` で並べる規則を持つ。バックアップは畳まないし、並べ方も違い、明示削除がある。
/// 同じ port に載せると、片方にしか意味の無い規則がもう片方へ漏れる。
///
/// **保管先は転送先と同じ場所にする。** 別に選べるようにすると「封筒は dir、バックアップは
/// Drive」という製品に存在しない組み合わせを作れてしまい、世代の判定がその組み合わせまで
/// 面倒を見ることになる。
///
/// 名前で棲み分ける。封筒は `event-`、バックアップは `backup-`、upload 中は `incoming-`、
/// 世代の起点は `baseline-` である（`karita_contract` の `backup.dart`）。
///
/// **ここに実装を置かない。** Drive は `karita_platform` が P2 で持ち、`dir` 相当は試験側が
/// 持つ。整列・重複の畳み込み・有効世代の決定だけは共有する — 実装ごとに違うと、端末ごとに
/// 違う世代を有効と判断し、両方が「相手が旧世代だ」と結論する。
///
/// 移送元: book-sync-model の `src/bsync_core/backup_store.py`（実装に依らない部分）。
library;

import 'package:karita_contract/karita_contract.dart';

/// 保管先にある1件。**本文は含まない。**
///
/// `summary` は表示のための索引であり、正しさの根拠ではない。復元は必ず取得後の manifest と
/// 内容 hash から判定する。
///
/// `duplicateRemoteIds` は、同じ `backupId` を持っていて一覧で畳まれた側である。落とした事実
/// まで消すと、同じ id を二度公開する不具合に誰も気づかない。
class BackupRef {
  final String backupId;
  final String remoteId;
  final int sizeBytes;
  final Map<String, String> summary;
  final List<String> duplicateRemoteIds;

  const BackupRef({
    required this.backupId,
    required this.remoteId,
    this.sizeBytes = 0,
    this.summary = const {},
    this.duplicateRemoteIds = const [],
  });

  String get createdAtUtc => summary['createdAtUtc'] ?? '';

  BackupRef withDuplicate(String remoteId) => BackupRef(
        backupId: backupId,
        remoteId: this.remoteId,
        sizeBytes: sizeBytes,
        summary: summary,
        duplicateRemoteIds: [...duplicateRemoteIds, remoteId],
      );
}

/// 一覧の結果。
///
/// `skipped` は、名前は `backup-<uuid>.blib` なのに索引を読めなかったものの数である。
/// **選べる一覧からは外すが、数は残す。** 黙って消すと、索引を書けていない不具合が
/// 「バックアップが1つも無い」という形でしか現れない。
class BackupListing {
  final List<BackupRef> refs;
  final int skipped;

  const BackupListing({this.refs = const [], this.skipped = 0});
}

/// 世代の起点1件。**`seq` の最大が有効世代である。**
class BaselineRef {
  final int seq;
  final String generationId;
  final String remoteId;
  final int sizeBytes;

  const BaselineRef({
    required this.seq,
    required this.generationId,
    required this.remoteId,
    this.sizeBytes = 0,
  });
}

/// **口は非同期である。** 理由は転送（`transport.dart`）と同じで、実装が待つのはネットワーク
/// である。`.blib` は MB 級になりうるので、こちらは1回の待ちが転送より長い。
abstract interface class BackupStorePort {
  String get kind;

  /// `incoming-` へ書いてから `backup-` へ改名する。返るのは保管先の識別子。
  Future<String> put(String backupId, String path);

  Future<BackupListing> list();

  /// `backupId` の実体を `destPath` へ取り出す。
  Future<String> get(String backupId, String destPath);

  /// 名指しされた `backupId` の実体をすべて消す。消した数を返す。
  Future<int> delete(String backupId);

  Future<String> putBaseline(int seq, String generationId, String path);

  Future<List<BaselineRef>> listBaselines();

  Future<String> getBaseline(BaselineRef ref, String destPath);
}

class BackupNotFound extends BackupError {
  // super パラメータへは畳めない（明示の super 呼び出しで code を固定するため）。
  // ignore: use_super_parameters
  BackupNotFound(String backupId)
      : super('バックアップが保管先にありません: $backupId', code: 'backup-store-missing');
}

/// `(seq, generationId)` 昇順。**末尾が有効世代になる。**
///
/// 作成時刻を使わない。端末の時計と保管先の時計を混ぜると基準が端末をまたいで揺れる（封筒の
/// 整列で同じ判断をしている）。ここで揺れると、端末ごとに違う世代を有効と判断し、**両方が
/// 「相手が旧世代だ」と結論する。**
int compareBaseline(BaselineRef a, BaselineRef b) {
  final bySeq = a.seq.compareTo(b.seq);
  return bySeq != 0 ? bySeq : a.generationId.compareTo(b.generationId);
}

/// 有効世代の baseline。無ければ null。
///
/// **最大 `seq`**、同じ `seq` が複数あれば **`generationId` の昇順で先頭**を採る。
/// **決定規則を持たない状態を作らない** — どちらを採るか決めないと、端末ごとに違う世代を選び、
/// 両方が「相手が旧世代だ」と結論する。
BaselineRef? activeBaseline(List<BaselineRef> refs) {
  if (refs.isEmpty) return null;
  var top = refs.first;
  for (final ref in refs.skip(1)) {
    if (ref.seq > top.seq ||
        (ref.seq == top.seq && ref.generationId.compareTo(top.generationId) < 0)) {
      top = ref;
    }
  }
  return top;
}

/// `(createdAtUtc, backupId)` 昇順。
///
/// **これは表示順であって、正しさに関わらない。** `createdAtUtc` は作成端末の時計であり、
/// 端末をまたぐと揺れる。揺れて困るのは有効世代の決定で、そこは baseline の `seq` で決める。
/// 一覧の並び順に同じ厳しさは要らない。第2キーは、同じ時刻の2件が列挙順に依存しないため。
int compareBackup(BackupRef a, BackupRef b) {
  final byCreated = a.createdAtUtc.compareTo(b.createdAtUtc);
  return byCreated != 0 ? byCreated : a.backupId.compareTo(b.backupId);
}

/// 同じ `backupId` を畳む。**整列してから呼ぶ。**
///
/// 保管先は同名ファイルの重複作成を許すため、upload の応答を得られずに送り直すと同じ
/// `backupId` の実体が2つできる。どちらを採るかが列挙順に依存しないよう、整列後の先頭を採り、
/// 落とした側は `duplicateRemoteIds` に残す。
///
/// **内容の一致は見ない。** 封筒（`dedupe`）は本文を持っているので比べられるが、ここで比べるには
/// 両方を取得することになる。採った側は復元時に hash を検査するので、壊れていればそこで止まる。
List<BackupRef> collapseBackups(List<BackupRef> refs) {
  final indexOf = <String, int>{};
  final kept = <BackupRef>[];
  for (final ref in refs) {
    final index = indexOf[ref.backupId];
    if (index == null) {
      indexOf[ref.backupId] = kept.length;
      kept.add(ref);
      continue;
    }
    kept[index] = kept[index].withDuplicate(ref.remoteId);
  }
  return kept;
}

BackupRef resolveBackup(BackupListing listing, String backupId) {
  for (final ref in listing.refs) {
    if (ref.backupId == backupId) return ref;
  }
  throw BackupNotFound(backupId);
}
