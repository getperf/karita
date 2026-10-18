/// 蔵書の観測を、端末の都合で抱える側。
///
/// **クライアントは1回の照会しか知らない。** 1回に頼める量に上限が在ることも、100冊の棚を
/// 何回かに分けることも、同じ本をまた開く利用者が居ることも端末の事情である。ここが分割・
/// 保持・期限・中止を持つ。
///
/// **`BookLookup` と同じ形にしてある**（上限付きメモリ、失敗も持つ、ディスクへ置かない）。
/// 違うのは**分割と間欠**で、それはカーリルの `/check` が 冊数 × 館数 で枠を食うからである。
library;

import 'dart:async';

import 'package:karita_public_api_client/karita_public_api_client.dart';

import 'api_cache.dart';
import 'api_defaults.dart';

/// ある鍵について、いま持っている観測。**部分結果である。**
class HoldingsObservation {
  /// 館ごとに分かっていること。**`systemId` を鍵にして塊をまたいで溜める。**
  final Map<String, SystemHolding> bySystem;

  /// 最後に観測した時刻。
  final DateTime observedAt;

  /// 取得そのものの失敗。**部分結果が在っても残す。**
  final ApiFailure? failure;

  const HoldingsObservation({
    required this.bySystem,
    required this.observedAt,
    this.failure,
  });
}

/// 1回の走りの結末。**画面が案内を出し分けるためだけに要る。**
enum HoldingsRunOutcome {
  /// 全部の塊が終わった。
  completed,

  /// 上限に達して打ち切った。**残りの本は「未照会」のままである。**
  rateLimited,

  /// 走り全体の期限に達して打ち切った。
  deadline,

  /// 中止された（画面を離れた・背面へ回った）。
  cancelled,

  /// 照会する対象が無かった（ISBNなし・登録館なし）。
  nothingToDo,

  /// 想定外の失敗。**塊ごとの失敗はここへ来ない**（部分結果として観測に残る）。
  ///
  /// 持っているのは**画面を「確認中」のまま残さない**ためである。押した結果が何も返らない
  /// と、利用者には壊れたボタンにしか見えない。
  failed,
}

/// 1回の走りの結果。
class HoldingsRunResult {
  final HoldingsRunOutcome outcome;

  /// 実際に外へ出した塊の数。
  final int chunks;

  /// 消費した書籍リクエストの数（冊数 × 館数の合計）。**枠の勘定である。**
  final int bookRequests;

  const HoldingsRunResult({
    required this.outcome,
    this.chunks = 0,
    this.bookRequests = 0,
  });
}

/// 1つの塊。**冊と館の組である。**
class HoldingsChunk {
  final List<String> isbn13s;
  final List<String> systemIds;

  const HoldingsChunk(this.isbn13s, this.systemIds);

  /// この塊が食う書籍リクエストの数。
  int get bookRequests => isbn13s.length * systemIds.length;
}

/// 蔵書の取得口。**画面はここだけを見る。**
class HoldingsLookup {
  final CalilCheckClient _client;
  final ExpiringCache<String, HoldingsObservation> _cache;

  /// 1塊の冊数の上限。
  final int chunkBooks;

  /// 塊のあいだに待つ長さ。
  final Duration chunkPause;

  /// 走り全体の期限。
  final Duration runDeadline;

  /// 1塊に許す書籍リクエスト数。**クライアントと同じ値を持つ** — 超えると向こうが投げる。
  final int bookRequestBudget;

  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  /// いつまで上限に達したものとして扱うか。**走り全体を1つの旗で止める。**
  ///
  /// 鍵ごとに見ないのは、枠がキー単位で尽きるからである。1冊が上限で落ちたなら、次の冊も
  /// 落ちる。
  DateTime? _rateLimitedUntil;

  bool _running = false;
  bool _cancelled = false;
  StreamSubscription<HoldingsSnapshot>? _subscription;

  /// いま待っている塊の終わり。**中止が待ちを解くために要る。**
  ///
  /// **購読を切ると `onDone` は来ない。** ここを持たずに中止すると、待っている塊が永久に
  /// 返らず、走りが終わらない。
  Completer<ApiFailure?>? _chunkDone;
  bool _closed = false;

  HoldingsLookup(
    this._client, {
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    this.chunkBooks = holdingsChunkBooks,
    this.chunkPause = holdingsChunkPause,
    this.runDeadline = holdingsRunDeadline,
    this.bookRequestBudget = defaultBookRequestBudget,
    int maxEntries = maxHoldingsEntries,
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       _cache = ExpiringCache(maxEntries: maxEntries, now: now);

  /// 抱えている観測の組数。**観測のためだけに出す。**
  int get entryCount => _cache.length;

  /// いま走っているか。
  bool get running => _running;

  /// 上限に達したものとして扱っている間か。**画面が案内を出し続けるために見る。**
  bool get rateLimited {
    final until = _rateLimitedUntil;
    if (until == null) return false;
    if (!_now().isBefore(until)) {
      _rateLimitedUntil = null;
      return false;
    }
    return true;
  }

  /// 持っている観測からサマリを作る。**通信しない。**
  ///
  /// [isbn13] が `null` なら照会不可。**呼ぶ側で正規化してから渡す** —
  /// `CalilCheckClient` は正規化済みの ISBN-13 以外で投げる。
  HoldingsSummary summaryFor({
    required String? isbn13,
    required List<String> systemIds,
  }) {
    if (isbn13 == null) return HoldingsSummary.noIsbn;
    final systems = _sorted(systemIds);
    if (systems.isEmpty) return HoldingsSummary.noLibrary;
    final observation = _cache.read(_key(isbn13, systems));
    return summarizeHoldings(
      requestedSystemIds: systems,
      holdings: observation?.bySystem.values.toList(),
      observedAt: observation?.observedAt,
      failure: observation?.failure,
    );
  }

  /// 塊に分ける。**画面と試験が同じ規則を見られるように、外へ出しておく。**
  ///
  /// 館が予算を超える端末では**館の側も分ける。** 分けた結果は `systemId` を鍵にして
  /// 溜めるので、1冊の答えが複数の塊にまたがっても揃う。
  List<HoldingsChunk> planChunks({
    required List<String> isbn13s,
    required List<String> systemIds,
  }) {
    final systems = _sorted(systemIds);
    final books = <String>{...isbn13s}.toList();
    if (systems.isEmpty || books.isEmpty) return const [];
    final systemGroups = systems.length <= bookRequestBudget
        ? [systems]
        : _slice(systems, bookRequestBudget);
    // **冊数は上限と予算の小さいほうである。** 10冊固定にすると6館の端末で向こうが投げる。
    final perChunk = (bookRequestBudget ~/ systemGroups.first.length).clamp(
      1,
      chunkBooks,
    );
    return [
      for (final bookGroup in _slice(books, perChunk))
        for (final systemGroup in systemGroups)
          HoldingsChunk(bookGroup, systemGroup),
    ];
  }

  /// 照会する。**塊に分け、間に待つ。届いた分から [onProgress] を呼ぶ。**
  ///
  /// **押されたら期限内でも取り直す** — 利用者が押したのだから、その意思が鮮度に勝つ。
  /// ただし上限に達している間は外へ出さない（[rateLimited]）。
  Future<HoldingsRunResult> check({
    required List<String> isbn13s,
    required List<String> systemIds,
    void Function()? onProgress,
  }) async {
    if (_closed) throw StateError('Holdings cache is closed');
    // **二重に走らせない。** 画面はボタンを無効にするが、ここでも止める。
    if (_running) {
      return const HoldingsRunResult(outcome: HoldingsRunOutcome.cancelled);
    }
    if (rateLimited) {
      return const HoldingsRunResult(outcome: HoldingsRunOutcome.rateLimited);
    }
    final chunks = planChunks(isbn13s: isbn13s, systemIds: systemIds);
    if (chunks.isEmpty) {
      return const HoldingsRunResult(outcome: HoldingsRunOutcome.nothingToDo);
    }
    final systems = _sorted(systemIds);

    _running = true;
    _cancelled = false;
    final startedAt = _now();
    var done = 0;
    var requests = 0;
    var outcome = HoldingsRunOutcome.completed;
    try {
      for (final chunk in chunks) {
        if (_cancelled) {
          outcome = HoldingsRunOutcome.cancelled;
          break;
        }
        if (done > 0) {
          await _delay(chunkPause);
          // **待っている間に離れたかを見る。** 見ないと、タブを離れても塊が出続ける。
          if (_cancelled) {
            outcome = HoldingsRunOutcome.cancelled;
            break;
          }
        }
        // **走り全体の期限。** 1セッションの60秒は塊ごとに掛かるので、ここが無いと
        // 10塊で10分走る。
        //
        // **待った後に見る。** 先に見ると、待っている間に過ぎた期限を1塊ぶん見逃す。
        // 訊くべきは「いまから次を出す時間が在るか」である。
        if (_now().difference(startedAt) >= runDeadline) {
          outcome = HoldingsRunOutcome.deadline;
          break;
        }
        done++;
        requests += chunk.bookRequests;
        final failure = await _runChunk(chunk, systems, onProgress);
        if (_cancelled) {
          outcome = HoldingsRunOutcome.cancelled;
          break;
        }
        if (failure == ApiFailure.rateLimited) {
          // **残りの塊はやめる。** 枠はキー単位で尽きているので、続けても全部落ちる。
          // 頼まなかった本は「未照会」のままにする — 聞いていないものを
          // 「確認できません」に塗らない。
          _rateLimitedUntil = _now().add(holdingsRateLimitedTtl);
          outcome = HoldingsRunOutcome.rateLimited;
          break;
        }
      }
    } finally {
      _running = false;
      _subscription = null;
    }
    return HoldingsRunResult(
      outcome: outcome,
      chunks: done,
      bookRequests: requests,
    );
  }

  /// 1塊ぶんを走らせ、届いた snapshot を溜める。**返すのは失敗の理由だけである。**
  Future<ApiFailure?> _runChunk(
    HoldingsChunk chunk,
    List<String> systems,
    void Function()? onProgress,
  ) async {
    final completer = Completer<ApiFailure?>();
    // **購読する前に控える。** 相手が同期的に答える場では、`listen` が返る前に中止が来る。
    _chunkDone = completer;
    ApiFailure? failure;
    // 相手が自分で終わったか。**終わった購読へ cancel を重ねない。**
    var finished = false;
    final subscription = _client
        .check(isbn13s: chunk.isbn13s, systemIds: chunk.systemIds)
        .listen(
          (snapshot) {
            failure = snapshot.failure;
            _absorb(chunk, systems, snapshot);
            onProgress?.call();
          },
          onError: (Object error) {
            // **クライアントは失敗を snapshot で返す。** ここへ来るのは想定外のほうで、
            // 走り全体を落とさずに1塊の失敗として扱う。
            failure = error is ApiFailureException
                ? error.failure
                : ApiFailure.server;
            finished = true;
            if (!completer.isCompleted) completer.complete(failure);
          },
          onDone: () {
            finished = true;
            if (!completer.isCompleted) completer.complete(failure);
          },
          cancelOnError: true,
        );
    _subscription = subscription;
    try {
      return await completer.future;
    } finally {
      _chunkDone = null;
      _subscription = null;
      // **自分で終わった購読は切らない。** 済んだ購読へ cancel を重ねても得るものが無く、
      // done を配っている最中に cancel を差すと、その場で噛み合って両方返らなくなる。
      //
      // **切るときも待たない。** `onCancel` は cancel を呼んだその場で走るので、聞き直しは
      // すでに止まっている。待つと、読みかけの応答が終わるまで次の塊へ行けない。
      if (!finished) unawaited(subscription.cancel());
    }
  }

  /// 届いた snapshot を鍵ごとに溜める。**塊をまたいで館を足していく。**
  void _absorb(
    HoldingsChunk chunk,
    List<String> systems,
    HoldingsSnapshot snapshot,
  ) {
    // **期限は結末で変える。** 上限は押し直しを10分止め、ほかの失敗は60秒で忘れる。
    final failure = snapshot.failure;
    final ttl = switch (failure) {
      null => holdingsTtl,
      ApiFailure.rateLimited => holdingsRateLimitedTtl,
      _ => apiFailureTtl,
    };
    for (final isbn13 in chunk.isbn13s) {
      final key = _key(isbn13, systems);
      final previous = _cache.read(key);
      final bySystem = <String, SystemHolding>{...?previous?.bySystem};
      for (final holding
          in snapshot.byIsbn[isbn13] ?? const <SystemHolding>[]) {
        bySystem[holding.systemId] = holding;
      }
      _cache.write(
        key,
        HoldingsObservation(
          bySystem: bySystem,
          observedAt: snapshot.observedAt,
          failure: failure,
        ),
        ttl,
      );
    }
  }

  /// 止める。**画面を離れた・背面へ回ったがここへ来る。**
  ///
  /// 走っている塊の購読を切り、次の塊へ行かせない。**持っている観測は捨てない** — 戻って
  /// きたときに同じ結果を、同じ確認時刻のまま出す。
  void cancel() {
    _cancelled = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
    // **購読を切ると `onDone` は来ない。** 待っている塊を自分で終わらせないと、走りが
    // 返らないまま残る。
    final pending = _chunkDone;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    cancel();
    _cache.clear();
    _client.close();
  }

  /// 鍵は ISBN と**館の集合**である。**館が変われば別の鍵になる。**
  ///
  /// 図書館を1つ足したあとに古い結果を出すと、足した館を確認済みに見せてしまう。
  static String _key(String isbn13, List<String> systems) =>
      '$isbn13|${systems.join(',')}';

  static List<String> _sorted(List<String> ids) =>
      <String>{...ids}.toList()..sort();

  static List<List<String>> _slice(List<String> items, int size) => [
    for (var i = 0; i < items.length; i += size)
      items.sublist(i, i + size > items.length ? items.length : i + size),
  ];
}
