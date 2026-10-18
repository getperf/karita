/// Drive の失敗を転送の語彙へ写す。
///
/// 転送が持つ失敗は3つしかない。**認可されなかった**（`TransportAuthError`）、**結果が不明**
/// （`TransportTimeout`）、**それ以外の入出力**（`transport-io`）である。どれに写すかで
/// outbox の行き先が決まるので、ここが写像の唯一の場所である。
///
/// 移送元: book-sync-model の `src/bsync_core/drive.py`（`translate`）。
library;

import 'package:karita_contract/errors.dart';
import 'package:karita_sync/karita_sync.dart';

/// 認可の失敗として扱う HTTP status。
///
/// 403 も入れる。`drive.appdata` のスコープを外して認可し直した端末はこれを受け、利用者から
/// 見れば「サインインし直せば直る」で正しい。
const Set<int> unauthorizedStatuses = {401, 403};

/// 失敗を転送の例外へ写す。
///
/// **`TransportTimeout` は書き込みでしか使わない。** これは「届いたかもしれない」という意味を
/// 持ち、lease を保持したまま `uploading` に残す判断へ直結する。読み取りの失敗を同じ例外へ
/// 写すと、送っていない行が `uploading` に落ちて、lease が失効するまで誰も触れなくなる。
///
/// **認可の失敗は書き込みでも `TransportAuthError` にする。** 401 で拒否された要求は処理されて
/// おらず、**「届いたかもしれない」ではない。**
///
/// [detail] に要求の中身を入れない。この文字列は記録と画面に出る。
SyncDataError translateDriveFailure({
  required String label,
  required bool writing,
  int? status,
  String? kind,
}) {
  final detail = status != null ? 'HTTP $status' : (kind ?? '通信の失敗');
  if (status != null && unauthorizedStatuses.contains(status)) {
    return TransportAuthError(
        'Drive の$labelで認可されませんでした（$detail）。サインインし直してください。');
  }
  if (writing) {
    return TransportTimeout('Drive の$labelの結果を確認できませんでした（$detail）。');
  }
  return SyncDataError('Drive の$labelに失敗しました（$detail）。', code: 'transport-io');
}
