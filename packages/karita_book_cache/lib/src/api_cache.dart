/// 外部 API の応答を端末に留めておく分。**上限付きのメモリだけである。**
///
/// ディスクには置かない（`非公開資料:external-data-access.md`）。取ってきたものは
/// 表示のための一時情報であり、同期にもバックアップにも乗らない。**アプリを閉じれば消えてよい** —
/// 消えて困るものは利用者が採用した時点で台帳へ入っている。
///
/// **期限は「結末ごと」に違う。** 未収録はしばらく変わらないが、通信の失敗は次の瞬間に直りうる。
/// 同じ長さで持つと、圏外で1回外したことが1時間残るか、収録されていない本を1分ごとに聞き直す
/// かのどちらかになる。だから期限は入れる側が結末を見て決め、この容れ物は言われた長さを守る
/// だけにする。
library;

/// 1件ぶん。**入れた時刻ではなく、切れる時刻を持つ。**
class _Entry<V> {
  final V value;
  final DateTime expiresAt;
  final int weight;

  const _Entry(this.value, this.expiresAt, this.weight);
}

/// 期限と上限を持つメモリキャッシュ。
///
/// **溢れたときに捨てるのは、いちばん古く入れたものである。** 使った順ではない — 使った順で
/// 守ると、一度開いた本の書影が、その後ずっと開いていない本の書影を押しのけ続ける。本棚を
/// 上から下まで繰ると、結局どちらでも入れ替わる。**単純なほうを採る。**
///
/// [maxWeight] は書影のように1件の大きさが桁違いに違うものへ使う。件数だけで縛ると、
/// 小さい表紙500枚と大きい表紙500枚で端末の使う量が10倍違う。
class ExpiringCache<K, V> {
  /// 件数の上限。
  final int maxEntries;

  /// 重さの合計の上限。**`null` なら件数だけで縛る。**
  final int? maxWeight;

  /// 1件の重さ。**`null` なら全部 1 として数える。**
  final int Function(V value)? weigh;

  final DateTime Function() _now;
  final Map<K, _Entry<V>> _entries = {};
  int _weight = 0;

  ExpiringCache({
    required this.maxEntries,
    this.maxWeight,
    this.weigh,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  int get length => _entries.length;

  /// 保持している重さの合計。**件数で縛っているときは件数と同じである。**
  int get weight => _weight;

  /// 読む。**切れていれば `null` を返し、その場で捨てる。**
  ///
  /// 切れたものを残しておくと、上限に当たったときに生きているものを押し出す。
  V? read(K key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (!_now().isBefore(entry.expiresAt)) {
      _drop(key);
      return null;
    }
    return entry.value;
  }

  /// 入れる。**同じ鍵は入れ直しになる** — 古いほうの重さは引く。
  ///
  /// [ttl] が 0 以下なら入れない。「持たない」と決めた結末をここで表せるようにしておく。
  void write(K key, V value, Duration ttl) {
    if (ttl <= Duration.zero) {
      _drop(key);
      return;
    }
    _drop(key);
    final entry = _Entry(value, _now().add(ttl), weigh?.call(value) ?? 1);
    _entries[key] = entry;
    _weight += entry.weight;
    _evict();
  }

  /// 捨てる。**明示的な再取得の前に呼ぶ** — 再取得は削除の反映でもある。
  void remove(K key) => _drop(key);

  /// 全部捨てる。**利用者からの「キャッシュを消す」がここへ来る。**
  void clear() {
    _entries.clear();
    _weight = 0;
  }

  void _drop(K key) {
    final removed = _entries.remove(key);
    if (removed != null) _weight -= removed.weight;
  }

  void _evict() {
    // **切れたものから先に捨てる。** 生きているものを押し出す前に、ただの燃え殻を落とす。
    final now = _now();
    for (final key in _entries.keys.toList()) {
      if (!now.isBefore(_entries[key]!.expiresAt)) _drop(key);
    }
    while (_entries.length > maxEntries ||
        (maxWeight != null && _weight > maxWeight! && _entries.isNotEmpty)) {
      _drop(_entries.keys.first);
    }
  }
}

/// 同じ照会の進行中の要求を1本にまとめる。
///
/// **本棚を開くと同じ本が何度も現れる。** 画面が組み上がる間に同じ ISBN の書影を10箇所が
/// 求めても、外へ出す要求は1本でよい。**要求の数はこちらの都合で増えるが、相手の枠は
/// こちらの都合を知らない。**
///
/// 終わったら控えから外す。**結果は持たない** — 持つのは [ExpiringCache] の仕事で、ここは
/// 「いま走っているか」だけを見る。両方を1つにすると、期限が切れた瞬間に走っている要求まで
/// 捨てることになる。
class SharedRequests<K, V> {
  final Map<K, Future<V>> _running = {};

  /// いま走っている本数。
  int get inFlight => _running.length;

  /// 走っていれば相乗りし、走っていなければ [start] で始める。
  Future<V> run(K key, Future<V> Function() start) {
    final running = _running[key];
    if (running != null) return running;
    final future = start();
    _running[key] = future;
    // **失敗しても外す。** 残すと、一度失敗した鍵が二度と走らなくなる。
    return future.whenComplete(() => _running.remove(key));
  }
}
