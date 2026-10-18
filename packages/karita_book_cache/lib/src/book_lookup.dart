/// OpenBD の書誌と書影を、端末の都合で抱える側。
///
/// **クライアントは1回の取得しか知らない。** 同じ本が画面に10箇所現れることも、戻ってきた
/// 利用者が同じ棚をまた開くことも端末の事情である。ここは保持・期限・同時実行上限を持つ。
/// 同じキーの要求共有はRiverpod familyに任せ、この層には重ねない。
///
/// **失敗も持つ。** 持たないと、画面を組み直すたびに同じ要求が外へ出る。圏外の端末で本棚を
/// 繰ると、それだけで数十本になる。
library;

import 'dart:async';

import 'package:karita_public_api_client/karita_public_api_client.dart';

import 'api_cache.dart';
import 'api_defaults.dart';

/// 書誌と書影の取得口。**画面はここだけを見る。**
class BookLookup {
  final OpenBdClient _client;
  final ExpiringCache<String, OpenBdResult> _records;
  final ExpiringCache<String, CoverImageResult> _covers;
  int _inFlight = 0;
  int _epoch = 0;
  bool _closed = false;
  final List<Completer<void>> _waiting = [];

  BookLookup(
    this._client, {
    DateTime Function()? now,
    int maxRecords = maxBookRecords,
    int maxImages = maxCoverEntries,
    int maxImageBytes = maxCoverBytes,
  }) : _records = ExpiringCache(maxEntries: maxRecords, now: now),
       _covers = ExpiringCache(
         maxEntries: maxImages,
         maxWeight: maxImageBytes,
         // **持っているバイトで数える。** 復号した後の絵は Flutter の側の勘定である。
         weigh: (result) => result.bytes?.length ?? 1,
         now: now,
       );

  /// 抱えている書誌の件数。**観測のためだけに出す。**
  int get recordCount => _records.length;

  /// 抱えている書影のバイト。
  int get coverBytes => _covers.weight;

  /// いま外へ出ている要求の本数。
  int get inFlight => _inFlight;

  // Sharing belongs to Riverpod. This gate only bounds concurrent HTTP work.
  Future<T> _run<T>(Future<T> Function() fetch) async {
    if (_closed) throw StateError('Book cache is closed');
    if (_inFlight >= 4) {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    } else {
      _inFlight++;
    }
    try {
      if (_closed) throw StateError('Book cache is closed');
      return await fetch();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _inFlight--;
      }
    }
  }

  /// 書誌を引く。
  ///
  /// [refresh] は利用者の明示した取り直しである。**削除の反映でもある** — 先に捨ててから
  /// 取りに行くので、相手が収録をやめていればその結果に入れ替わる。
  Future<OpenBdResult> book(String isbn13, {bool refresh = false}) {
    if (refresh) {
      _epoch++;
      _records.remove(isbn13);
    }
    final cached = _records.read(isbn13);
    if (cached != null) return Future.value(cached);
    final epoch = _epoch;
    return _run(() async {
      final result = await _client.fetchBook(isbn13);
      if (!_closed && epoch == _epoch) {
        _records.write(isbn13, result, _recordTtl(result.outcome));
      }
      return result;
    });
  }

  /// 書影を取る。**URL は [BookRecord.coverUrl] が返したものだけを渡す。**
  Future<CoverImageResult> cover(Uri coverUrl, {bool refresh = false}) {
    final key = coverUrl.toString();
    if (refresh) {
      _epoch++;
      _covers.remove(key);
    }
    final cached = _covers.read(key);
    if (cached != null) return Future.value(cached);
    final epoch = _epoch;
    return _run(() async {
      final result = await _client.fetchCoverImage(coverUrl);
      if (!_closed && epoch == _epoch) {
        _covers.write(key, result, _coverTtl(result.outcome));
      }
      return result;
    });
  }

  /// 抱えているものを捨てる。**利用者からの「キャッシュを消す」がここへ来る。**
  ///
  /// 走っている要求の結果は呼出元へ返すが、世代が変わったキャッシュへ再格納しない。
  void clearCache() {
    _epoch++;
    _records.clear();
    _covers.clear();
  }

  void close() {
    _closed = true;
    clearCache();
    _client.close();
  }

  void invalidateBook(String isbn) {
    _epoch++;
    _records.remove(isbn);
  }

  /// 結末ごとの期限。**「無い」と「取れなかった」を同じ長さで持たない。**
  static Duration _recordTtl(OpenBdOutcome outcome) => switch (outcome) {
    OpenBdOutcome.found => bookRecordTtl,
    OpenBdOutcome.notListed => bookNotListedTtl,
    OpenBdOutcome.failed => apiFailureTtl,
  };

  static Duration _coverTtl(CoverImageOutcome outcome) => switch (outcome) {
    CoverImageOutcome.fetched => coverImageTtl,
    CoverImageOutcome.notFound => coverMissingTtl,
    CoverImageOutcome.failed => apiFailureTtl,
  };
}
