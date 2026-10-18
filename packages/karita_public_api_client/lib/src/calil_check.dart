/// カーリルの `/check` で、ISBN × 図書館システムの蔵書と貸出状況を見る。
///
/// **1回では終わらない。** 相手は各館へ問い合わせに行くので、最初の応答は「まだ走っている」
/// ことが多い。`session` を持って `continue` が 0 になるまで聞き直す。だからここが返すのは
/// 値ではなく**流れ**で、届いたところまでを順に出す。
///
/// **Running・Error・未照会を「蔵書なし」に畳まない。** 畳むと、画面が「この館には無い」と
/// 言い切ってしまう — 利用者はそれを見て予約をやめる。分からないことは分からないまま上へ渡す。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'defaults.dart';
import 'failures.dart';
import 'fetch.dart';

/// 1つの図書館システムについて、今わかっていること。
class SystemHolding {
  final String systemId;

  /// API が返した状態の**生の値**。`OK` / `Cache` / `Running` / `Error` と、知らない値。
  ///
  /// **enum に畳まない。** 知らない値が来たときに既知のどれかへ寄せると、寄せた先の意味で
  /// 表示されてしまう。寄せるのではなく、そのまま持って上へ渡す。
  final String status;

  /// 館ごとの貸出状況。`{"東雲": "貸出可"}` の形。**値も生のままである。**
  final Map<String, String> libkeyStatuses;

  /// 予約ページ。相手が返したときだけ在る。
  final Uri? reserveUrl;

  const SystemHolding({
    required this.systemId,
    required this.status,
    this.libkeyStatuses = const {},
    this.reserveUrl,
  });

  /// まだ走っている。**「蔵書なし」ではない。**
  bool get isRunning => status == 'Running';

  /// この館の照会が失敗した。**「蔵書なし」ではない。**
  bool get isError => status == 'Error';

  /// 相手が答え終えた。`OK` と `Cache` の2つで、どちらも結果として同じに扱う。
  bool get isSettled => status == 'OK' || status == 'Cache';
}

/// ある時点までに分かっていること。**部分結果である。**
class HoldingsSnapshot {
  /// 観測した時刻。**古い観測を今の確定結果に見せないために要る。**
  final DateTime observedAt;

  /// 全部の館が答え終えたか。
  final bool complete;

  /// ISBN → その本について分かっている館ぶん。
  final Map<String, List<SystemHolding>> byIsbn;

  /// 取得そのものが失敗したなら理由。**そのときも [byIsbn] は残っている分を持つ。**
  final ApiFailure? failure;

  const HoldingsSnapshot({
    required this.observedAt,
    required this.complete,
    required this.byIsbn,
    this.failure,
  });
}

class CalilCheckClient {
  final http.Client _httpClient;
  final Uri apiBase;
  final String appkey;

  /// 聞き直す間隔。**[minPollInterval] を下回れない。**
  final Duration pollInterval;

  /// 1要求ぶんの期限。
  final Duration timeout;

  /// 照会全体の期限。**達したら止めて、取れている分を残す。**
  final Duration overallTimeout;

  final int maxBytes;

  /// 1回の照会に許す書籍リクエスト数。
  final int bookRequestBudget;

  /// 待つ手段。**試験が待たずに回すために外から差せる。**
  ///
  /// 差し替えても間隔の規則は消えない — 呼ぶときの [Duration] は本物と同じ値なので、
  /// 試験はその値を見て「2秒を下回っていないこと」を測れる。
  final Future<void> Function(Duration) delay;

  /// 時刻。全体の期限を測るのに使う。
  final DateTime Function() now;

  CalilCheckClient({
    required this.appkey,
    http.Client? httpClient,
    Uri? apiBase,
    this.pollInterval = minPollInterval,
    this.timeout = defaultCalilTimeout,
    this.overallTimeout = defaultCalilOverallTimeout,
    this.maxBytes = defaultMaxCalilResponseBytes,
    this.bookRequestBudget = defaultBookRequestBudget,
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
  })  : _httpClient = httpClient ?? http.Client(),
        apiBase = apiBase ?? calilApiBase,
        delay = delay ?? Future<void>.delayed,
        now = now ?? DateTime.now {
    if (appkey.isEmpty) {
      throw ArgumentError.value(appkey, 'appkey', 'キーなしでは照会しない');
    }
    if (pollInterval < minPollInterval) {
      throw ArgumentError.value(
          pollInterval, 'pollInterval', '2秒を下回らないこと（公式の求め）');
    }
  }

  void close() => _httpClient.close();

  /// 蔵書を見に行く。**購読をやめれば聞き直しも止まる。**
  ///
  /// 画面から離れた・背面へ回った、のどちらも購読をやめることで表す。ここが自分の時計で
  /// 走り続けると、閉じた画面のために書籍リクエストの枠を使うことになる。
  Stream<HoldingsSnapshot> check({
    required List<String> isbn13s,
    required List<String> systemIds,
  }) {
    for (final isbn13 in isbn13s) {
      requireIsbn13(isbn13);
    }
    // **重複を除いてから数える。** 同じ館を2回渡しても枠は1つぶんである。
    final books = isbn13s.toSet().toList();
    final systems = systemIds.toSet().toList();
    if (books.isEmpty || systems.isEmpty) {
      throw ArgumentError('ISBN と systemid を1つ以上渡すこと');
    }
    final requested = books.length * systems.length;
    if (requested > bookRequestBudget) {
      throw ArgumentError('1回の照会が $requested 書籍リクエストになる'
          '（目安は $bookRequestBudget）。分けるのは呼ぶ側の仕事である');
    }

    late final StreamController<HoldingsSnapshot> controller;
    var cancelled = false;

    Future<void> run() async {
      final startedAt = now();
      var byIsbn = <String, List<SystemHolding>>{};
      var uri = _startUri(books, systems);
      while (true) {
        if (cancelled) return;
        final _CheckResponse parsed;
        try {
          parsed = await _poll(uri);
        } on ApiFailureException catch (error) {
          // **部分結果は捨てない。** 失敗したのは今回の1回であって、前に届いた館の答えが
          // 間違いになったわけではない。
          controller.add(HoldingsSnapshot(
            observedAt: now(),
            complete: false,
            byIsbn: byIsbn,
            failure: error.failure,
          ));
          return;
        }
        if (cancelled) return;
        byIsbn = parsed.byIsbn;
        controller.add(HoldingsSnapshot(
          observedAt: now(),
          complete: !parsed.shouldContinue,
          byIsbn: byIsbn,
        ));
        if (!parsed.shouldContinue) return;

        // 次の1回を待っている間に期限を越えるなら、待たずにここで止める。
        // **打ち切りであって、蔵書が無いことではない。**
        if (now().difference(startedAt) + pollInterval > overallTimeout) {
          controller.add(HoldingsSnapshot(
            observedAt: now(),
            complete: false,
            byIsbn: byIsbn,
            failure: ApiFailure.timeout,
          ));
          return;
        }
        await delay(pollInterval);
        uri = _sessionUri(parsed.session!);
      }
    }

    controller = StreamController<HoldingsSnapshot>(
      onListen: () => run().whenComplete(controller.close),
      onCancel: () => cancelled = true,
    );
    return controller.stream;
  }

  /// 最初の1回。**`callback=no` で素の JSON にする** — 既定は JSONP である。
  Uri _startUri(List<String> books, List<String> systems) =>
      apiBase.replace(path: '${apiBase.path}/check', queryParameters: {
        'appkey': appkey,
        'isbn': books.join(','),
        'systemid': systems.join(','),
        'format': 'json',
        'callback': 'no',
      });

  /// 2回目以降。**ISBN も systemid も送らない** — 送ると新しい照会になり、枠を二重に使う。
  Uri _sessionUri(String session) =>
      apiBase.replace(path: '${apiBase.path}/check', queryParameters: {
        'appkey': appkey,
        'session': session,
        'format': 'json',
        'callback': 'no',
      });

  Future<_CheckResponse> _poll(Uri uri) async {
    final response = await fetchBytes(_httpClient, uri,
        maxBytes: maxBytes,
        timeout: timeout,
        provider: 'calil',
        operation: 'check');
    throwForStatus(response.statusCode);
    return _read(response.bodyBytes);
  }

  static _CheckResponse _read(List<int> bodyBytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes));
    } catch (error) {
      throw ApiFailureException(ApiFailure.invalidData, '$error');
    }
    if (decoded is! Map) {
      throw const ApiFailureException(ApiFailure.invalidData, 'object ではない');
    }
    // `continue` は 1 / 0 で来る。**真偽値ではない。**
    final shouldContinue =
        decoded['continue'] == 1 || decoded['continue'] == '1';
    final session = decoded['session'];
    if (shouldContinue && session is! String) {
      throw const ApiFailureException(
          ApiFailure.invalidData, 'continue が立っているのに session が無い');
    }
    final books = decoded['books'];
    if (books is! Map) {
      throw const ApiFailureException(ApiFailure.invalidData, 'books が無い');
    }

    final byIsbn = <String, List<SystemHolding>>{};
    for (final bookEntry in books.entries) {
      final isbn = bookEntry.key;
      final systems = bookEntry.value;
      if (isbn is! String || systems is! Map) continue;
      final holdings = <SystemHolding>[];
      for (final systemEntry in systems.entries) {
        final systemId = systemEntry.key;
        final body = systemEntry.value;
        if (systemId is! String || body is! Map) continue;
        final status = body['status'];
        final reserveUrl = body['reserveurl'];
        holdings.add(SystemHolding(
          systemId: systemId,
          status: status is String ? status : '',
          libkeyStatuses: _libkeys(body['libkey']),
          reserveUrl: reserveUrl is String && reserveUrl.isNotEmpty
              ? Uri.tryParse(reserveUrl)
              : null,
        ));
      }
      byIsbn[isbn] = holdings;
    }
    return _CheckResponse(
      byIsbn: byIsbn,
      shouldContinue: shouldContinue,
      session: session is String ? session : null,
    );
  }

  /// 館ごとの状態。**知らない文字列もそのまま入れる。**
  static Map<String, String> _libkeys(Object? value) {
    if (value is! Map) return const {};
    final statuses = <String, String>{};
    for (final entry in value.entries) {
      final libkey = entry.key;
      final status = entry.value;
      if (libkey is String && status is String) statuses[libkey] = status;
    }
    return statuses;
  }
}

class _CheckResponse {
  final Map<String, List<SystemHolding>> byIsbn;
  final bool shouldContinue;
  final String? session;

  const _CheckResponse({
    required this.byIsbn,
    required this.shouldContinue,
    this.session,
  });
}
