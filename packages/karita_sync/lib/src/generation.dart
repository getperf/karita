/// 同期世代の解決。
///
/// **世代は保管先が決め、端末はそれに従う。** 有効世代は `baseline-<seq>-<generation-id>.blib`
/// のうち最大 `seq` を持つものであり、可変ファイルを置き換えていく形は取らない（保管先は同名の
/// 重複作成を許すため、単一の可変ファイルは「2つある状態」が普通に起こる）。
///
/// 端末側が持つのは「いま自分がどの世代に乗っているか」だけで、`sync_state` の
/// `generation_id` / `generation_seq` にある。**`.blib` には入らない**（`deviceStateKeys`）。
///
/// ## 4つの状態
///
/// | 端末 | 保管先 | 判定 | すること |
/// |---|---|---|---|
/// | 無し | baseline 無し | `bootstrap` | 現状態を baseline 0001 にして始める |
/// | 無し | baseline 有り | `adopt` | 有効世代に乗る |
/// | 有り | 同じ | `current` | 通常同期を続ける |
/// | 有り | 違う | `changed` | **通常同期を止め、完全復元を求める** |
///
/// `adopt` を `changed` と同じ扱いにしない。**まだ一度も同期していない端末**が有効世代に乗るのは
/// 世代の切替ではなく参加であり、止める理由が無い。止めると、二端末目を用意する経路がすべて
/// 「まず復元しろ」になる。世代変更の検出（`changed`）が守るのは「**復元より後に、復元前の世代の
/// まま同期を続けてしまう**」ことであって、参加ではない。
///
/// ## 止められた端末が戻る先は起点である
///
/// `changed` で止めた端末が**バックアップを指して**復元すると、それはもう一度の宣言になり、
/// 世代がさらに1つ上がって今度は相手が止まる。二端末は交互に止まり続け、**同じ世代へ戻る経路が
/// どこにも無くなる。**
///
/// そこで復元を二つに分ける。バックアップを指す復元は**宣言**であり世代を進める。有効世代の
/// 起点へ戻る `restoreFromBaseline` は**参加**であり、**世代を進めない。**
///
/// 移送元: book-sync-model の `src/bsync_core/generation.py`。
library;

import 'package:karita_contract/karita_contract.dart';

import 'backup_store.dart';

const String generationBootstrap = 'bootstrap';
const String generationAdopt = 'adopt';
const String generationCurrent = 'current';
const String generationChanged = 'changed';
const String generationUnknown = 'unknown';

/// 有効世代が端末の世代と違う。**通常同期を止める。**
class GenerationChangedError extends SyncDataError {
  final String localId;
  final int localSeq;
  final BaselineRef active;

  // super パラメータへは畳めない（明示の super 呼び出しで code を固定するため）。
  // ignore: use_super_parameters
  GenerationChangedError(this.localId, this.localSeq, this.active)
      : super(
          '同期世代が変わりました（この端末は ${_pad(localSeq)}/$localId、'
          '保管先の有効世代は ${_pad(active.seq)}/${active.generationId}）。'
          '通常同期は続けられません。有効世代の起点へ完全復元すると、世代を進めずに'
          'この世代へ乗れます。',
          code: 'generation-changed',
        );
}

String _pad(int seq) => seq.toString().padLeft(seqWidth, '0');

/// 世代の解決結果。`state` は上の表の4つ（と `unknown`）。
class GenerationResolution {
  final String state;
  final String generationId;
  final int seq;

  /// `unknown` のとき、保管先を読めなかった理由。**それ以外では `null`。**
  ///
  /// 呼び出し側は理由で分ける（2026-10-08）。認可切れなら先へ進めてよい — 書き込みも認可で
  /// 落ち、outbox が `blocked_auth` になって再サインインの状態へ届く。**それ以外で先へ進むと、
  /// 世代が変わっていた場合に旧世代の名前で書く**（`SyncEngine` の run）。
  final SyncDataError? unreadable;

  const GenerationResolution(this.state, this.generationId, this.seq,
      {this.unreadable});

  /// この端末が baseline を公開しなければならないか。
  bool get needsBaseline => state == generationBootstrap;
}

/// 端末が乗っている世代。**片方だけある状態を「持っている」と読まない。**
///
/// `seq` を 0 で補うと、有効世代より小さい seq を持つ端末が生まれ、`changed` の判定が
/// 「常に変わった」に倒れる。
({String id, int seq})? localGeneration(Db db) {
  final id = getState(db, stateGenerationId);
  final rawSeq = getState(db, stateGenerationSeq);
  if (id == null || id.isEmpty || rawSeq == null || rawSeq.isEmpty) return null;
  final seq = int.tryParse(rawSeq);
  if (seq == null || seq < firstSeq) return null;
  return (id: id, seq: seq);
}

void setLocalGeneration(Db db, String generationId, int seq) {
  transaction(db, () {
    setState(db, stateGenerationId, generationId);
    setState(db, stateGenerationSeq, '$seq');
  });
}

/// 端末の世代と保管先の有効世代を突き合わせる。
///
/// `newGenerationId` は `bootstrap` のときにだけ使う。呼び出し側が UUID を作って渡すのは、
/// 生成を差し替えてゴールデンを固定できる状態を保つためである。
///
/// **保管先を読めなかったときは落とさない。** 認可切れやネットワーク断で baseline を数え
/// られないのは「世代が変わった」ことではない。ここで落とすと、`push` が転送を組む前に落ちて
/// outbox の行が `blocked_auth` にならず、P2 で作る状態機械へ到達できない。
///
/// 読めなかった場合は `unknown` を返し、**baseline を公開しない。** 世代を確かめられないまま
/// 起点を置くと、既にある世代を知らずに 0001 を作り直す。
Future<GenerationResolution> resolveGeneration(
  BackupStorePort store,
  ({String id, int seq})? local, {
  required String newGenerationId,
}) async {
  final List<BaselineRef> baselines;
  try {
    baselines = await store.listBaselines();
  } on SyncDataError catch (error) {
    if (local == null) {
      return GenerationResolution(generationUnknown, newGenerationId, firstSeq,
          unreadable: error);
    }
    return GenerationResolution(generationUnknown, local.id, local.seq,
        unreadable: error);
  }

  final active = activeBaseline(baselines);

  if (local == null) {
    if (active == null) {
      return GenerationResolution(generationBootstrap, newGenerationId, firstSeq);
    }
    return GenerationResolution(generationAdopt, active.generationId, active.seq);
  }

  if (active == null) {
    // 端末は世代を持つのに保管先に baseline が無い。転送先を空にした直後がこれである。
    // **止めない。** 端末の世代のまま続け、baseline は次の復元が置く。ここで止めると、
    // 転送先の初期化のたびに全端末が復元を要求される。
    return GenerationResolution(generationCurrent, local.id, local.seq);
  }
  if (active.generationId == local.id) {
    // seq は保管先を正とする。同じ世代に別の seq が付くことはないが、付いたときに端末側の
    // 古い値を持ち回らない。
    return GenerationResolution(generationCurrent, local.id, active.seq);
  }
  throw GenerationChangedError(local.id, local.seq, active);
}

/// 次の baseline の `seq`。**現世代を壊さずに1つ進める。**
Future<int> nextGenerationSeq(BackupStorePort store) async {
  final active = activeBaseline(await store.listBaselines());
  return active == null ? firstSeq : active.seq + 1;
}
