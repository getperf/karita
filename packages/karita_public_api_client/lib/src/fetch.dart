/// HTTP を1回だけ叩く分。**待つのはここだけである。**
///
/// 上の adapter は URL の組み立てと応答の読み方しか持たない。回線が細い・相手が黙る・応答が
/// 際限なく続く、のどれもここで打ち切る。
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'failures.dart';

/// 外へ出た1回。**ここが直接 API の唯一の出口なので、記録もここに1つだけ置く。**
///
/// **`sink` は持たない。** どこへ書くかは合成層が決める
/// （`非公開資料:logging-and-diagnostics.md` 決定 A）。
final Logger _log = Logger('karita.api');

/// ログへ出してよい項目は決まっている。**provider・操作種別・結果分類・HTTP status・
/// 所要時間・要求件数だけである**（同文書「書かないもの」）。
///
/// **URL を出さない。** カーリルの URL は `appkey` をクエリに載せる。ホストだけでも出さない
/// のは、出してよい項目を数え上げた側の規則に合わせるためである — provider がその役を担う。
/// **応答の本文・書名・著者・ISBN も出さない。**
const String _fetchEvent = 'api.fetch';

/// 読み切った1回ぶんの応答。
class FetchedResponse {
  final int statusCode;
  final List<int> bodyBytes;

  const FetchedResponse(this.statusCode, this.bodyBytes);
}

/// GET して、上限まで読む。
///
/// **上限を超えたら読むのをやめる。** `Content-Length` を信じない — 相手が申告しないことも、
/// 申告と実体が違うこともある。数え終わってから捨てるのでは、その時点で端末のメモリに載って
/// いる。
///
/// 期限に達したら [abort] を完了させて、開いたままの接続を閉じる。**投げて放置しない** —
/// 本棚のように何十件も並ぶ画面では、放置した接続がそのまま積み上がる。
/// [provider] と [operation] は**ログにだけ使う。** 取得の振る舞いは変えない。
/// 既定を持たせず必須にしてあるのは、**新しい経路を足した人が名乗り忘れないため**である。
Future<FetchedResponse> fetchBytes(
  http.Client client,
  Uri uri, {
  required int maxBytes,
  required Duration timeout,
  required String provider,
  required String operation,
}) async {
  final abort = Completer<void>();
  final started = Stopwatch()..start();
  try {
    final response =
        await _fetch(client, uri, maxBytes, abort.future).timeout(timeout);
    _log.fine(_fetchEvent, {
      'provider': provider,
      'op': operation,
      'outcome': 'ok',
      'status': response.statusCode,
      'ms': started.elapsedMilliseconds,
      'bytes': response.bodyBytes.length,
    });
    return response;
  } on TimeoutException {
    if (!abort.isCompleted) abort.complete();
    _log.warning(_fetchEvent, {
      'provider': provider,
      'op': operation,
      'outcome': ApiFailure.timeout.name,
      'ms': started.elapsedMilliseconds,
    });
    throw const ApiFailureException(ApiFailure.timeout);
  } on http.ClientException catch (error) {
    // **`error.message` を出さない。** `http` の例外文は URL を含みうる。
    _log.warning(_fetchEvent, {
      'provider': provider,
      'op': operation,
      'outcome': ApiFailure.network.name,
      'ms': started.elapsedMilliseconds,
    });
    throw ApiFailureException(ApiFailure.network, error.message);
  } on ApiFailureException catch (error) {
    // 上限超過（`tooLarge`）はここへ来る。**status の失敗は [throwForStatus] の側で出す。**
    _log.warning(_fetchEvent, {
      'provider': provider,
      'op': operation,
      'outcome': error.failure.name,
      'ms': started.elapsedMilliseconds,
    });
    rethrow;
  }
}

Future<FetchedResponse> _fetch(
  http.Client client,
  Uri uri,
  int maxBytes,
  Future<void> abort,
) async {
  final response =
      await client.send(http.AbortableRequest('GET', uri, abortTrigger: abort));
  final body = <int>[];
  await for (final chunk in response.stream) {
    body.addAll(chunk);
    if (body.length > maxBytes) {
      throw ApiFailureException(ApiFailure.tooLarge, '$maxBytes バイトを超えた');
    }
  }
  return FetchedResponse(response.statusCode, body);
}

/// status を失敗の区別へ移す。**2xx なら何も起きない。**
///
/// 429 を `server` へ畳まないのは、時間を置けば直る失敗だけを再確認の対象にしたいからである。
/// 401・403 も分ける — キーの打ち間違いは利用者が直せるが、`server` のままでは伝えようがない。
void throwForStatus(int statusCode) {
  if (statusCode >= 200 && statusCode < 300) return;
  if (statusCode == 429) throw const ApiFailureException(ApiFailure.rateLimited);
  if (statusCode == 401 || statusCode == 403) {
    throw const ApiFailureException(ApiFailure.unauthorized);
  }
  throw ApiFailureException(ApiFailure.server, 'HTTP $statusCode');
}

/// 正規化済みの ISBN-13 であることだけを見る。
///
/// **ここで正規化しない。** ISBN-10 からの変換もハイフンの除去もチェック桁の検証も
/// `karita_handoff` の `normalizeIsbn13` が唯一の実装で、写しを作ると同じ本が別の
/// `entityId` になる経路ができる。ここへ来る値は合成層が既に通した後のものである。
///
/// したがって、これに掛かるのは利用者の入力ではなく**呼び方の間違い**である。失敗として
/// 返さず投げる。
void requireIsbn13(String isbn13) {
  if (!RegExp(r'^97[89][0-9]{10}$').hasMatch(isbn13)) {
    throw ArgumentError.value(
        isbn13, 'isbn13', '正規化済みの ISBN-13 を渡すこと（karita_handoff で正規化する）');
  }
}
