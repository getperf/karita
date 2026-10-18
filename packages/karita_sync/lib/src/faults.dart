/// 故障注入の転送。受入ケース07〜10 を fixture から再現する。
///
/// **これは製品側にある。** 偽クライアント（③ の試験にある）と役割が違う — あちらが模すのは
/// 保管先の既定のふるまいで、試験のコードから直接使う。こちらは **fixture が名前で指定する**
/// （`{"do": "push", "fault": "upload-timeout"}`）ので、名前と意味が製品の語彙になければ
/// ケースを駆動できない。**区別の基準は「fixture から名前で指定できる必要があるか」である。**
///
/// **包む側にする。** 故障ごとに転送を作り分けると、「故障の無い fault 転送」と素の転送が別物に
/// なり、比較の基準が失われる。
///
/// **転送は封筒を解釈しない。** 故障を入れても、運ぶのは生の文字列のままである。
///
/// 移送元: book-sync-model の `src/bsync_core/faults.py`。
library;

import 'dart:math';

import 'package:karita_contract/errors.dart';

import 'transport.dart';

const String transportFault = 'fault';

/// 応答を得られないまま、実体は書かれている。**失敗ではなく「不明」である。**
const String faultUploadTimeout = 'upload-timeout';

/// 同じ `eventId` の実体をもう1つ作る。**置き換えの無い保管先の既定のふるまいである。**
const String faultDuplicateName = 'duplicate-name';

/// 一覧の順序を壊す。ページを跨いだ大域の順序が無いことを模す。
const String faultShuffle = 'shuffle';

/// ページ内でしか整列していない一覧を返す。
const String faultPaginate = 'paginate';

/// 認可されない。`put` も `list` も `delete` も等しく落ちる。
const String faultAuth401 = 'auth-401';

/// 書いた直後のものが一覧に出ない。
const String faultDelayedVisibility = 'delayed-visibility';

const List<String> faultNames = [
  faultUploadTimeout,
  faultDuplicateName,
  faultShuffle,
  faultPaginate,
  faultAuth401,
  faultDelayedVisibility,
];

/// ページの大きさと並べ替えの種は固定する。**故障は再現できなければ検証にならない。**
const int faultPageSize = 3;
const int _shuffleSeed = 20260804;

/// 同じ `eventId` の実体を**もう1つ**作れる転送。
///
/// 通常の [TransportPort] には作れない。`put` は `eventId` から決定的な名前を組むので、二度
/// 呼んでも同じ実体を指す。置き換えの無い保管先では同名の実体が2つできるので、その状態を
/// 疑似転送で作るにはこの1つだけ能力が要る。
///
/// **口を分けたのは、通常の port に載せないためである。** `put` の隣に置くと、製品のどこかが
/// 複製を作れることになる。故障注入だけが呼ぶ。
abstract interface class DuplicatingTransport implements TransportPort {
  /// 同じ `eventId` で、別の実体をもう1つ作る。返るのは転送先の識別子。
  ///
  /// **有効世代の名前空間に置く。** 前置を外すと一覧に出ず、重複排除を試験できない。
  Future<String> putDuplicate(String eventId, String text);
}

class FaultTransport implements TransportPort {
  final TransportPort inner;
  final Set<String> faults;

  /// `delayed-visibility` が隠す対象。**この転送を通じて送ったものだけ**を隠す。
  final Set<String> _justWritten = {};

  FaultTransport(this.inner, Iterable<String> faults)
      : faults = {...faults} {
    for (final name in this.faults) {
      if (!faultNames.contains(name)) {
        // 綴り間違いを黙って受けると、「故障を入れたつもりで入っていない」まま緑になる。
        throw SyncDataError('未知の故障です: $name（$faultNames）', code: 'fault-name');
      }
    }
  }

  @override
  String get kind => faults.isEmpty ? inner.kind : transportFault;

  bool _has(String name) => faults.contains(name);

  @override
  Future<String> put(String eventId, String text) async {
    if (_has(faultAuth401)) {
      throw TransportAuthError('アクセストークンを得られません（故障注入 $faultAuth401）。');
    }

    final String remoteId;
    if (_has(faultDuplicateName)) {
      final duplicating = inner;
      if (duplicating is! DuplicatingTransport) {
        throw SyncDataError(
          '$faultDuplicateName は同じ eventId の実体を2つ作れる転送が要ります: ${inner.kind}',
          code: 'fault-unsupported',
        );
      }
      remoteId = await duplicating.putDuplicate(eventId, text);
    } else {
      remoteId = await inner.put(eventId, text);
    }
    _justWritten.add(eventId);

    if (_has(faultUploadTimeout)) {
      // **書いた後で投げる。** アップロードは届いており、失われたのは応答だけである。先に
      // 投げると、実体の無い「不明」になってしまい、受入ケース08 が測るものが変わる。
      throw TransportTimeout(
          'アップロードの応答を得られませんでした（故障注入 $faultUploadTimeout）: $eventId');
    }
    return remoteId;
  }

  @override
  Future<List<RemoteEvent>> list({KnownEvent? known}) async {
    if (_has(faultAuth401)) {
      throw TransportAuthError('アクセストークンを得られません（故障注入 $faultAuth401）。');
    }

    var events = await inner.list(known: known);
    if (_has(faultDelayedVisibility)) {
      // 書込み直後の一覧に現れない。既に送ったものが「無い」ように見える。
      events = [
        for (final event in events)
          if (event.eventId == null || !_justWritten.contains(event.eventId))
            event,
      ];
    }
    if (_has(faultShuffle)) {
      events = [...events]..shuffle(_Deterministic(_shuffleSeed));
    }
    if (_has(faultPaginate)) {
      events = _repage(events);
    }
    return events;
  }

  /// 自分の [list] から探す。**故障は一覧に効いた後の結果に対して効く。**
  ///
  /// `auth-401` は [list] が投げ、`delayed-visibility` は自分が書いたものを隠すので、再送時の
  /// 検索が既送信を見つけられない。その結果として重複が作られる経路が、受入ケース07 と
  /// ケース08 を繋ぐ。`shuffle` と `paginate` は1件の検索には効かない。
  @override
  Future<RemoteEvent?> find(String eventId) async =>
      firstMatching(await list(), eventId);

  @override
  Future<void> delete(String remoteId) async {
    if (_has(faultAuth401)) {
      throw TransportAuthError('アクセストークンを得られません（故障注入 $faultAuth401）。');
    }
    await inner.delete(remoteId);
  }
}

/// ページ内でしか整列していない一覧を作る。
///
/// 実 Drive の一覧は `pageToken` のループで取り、ページを跨いだ大域の順序は保証されない。
/// **ページの順序を逆にする** — ページ内の並びを保ったまま、全体の並びだけを壊す。
List<RemoteEvent> _repage(List<RemoteEvent> events) {
  final pages = <List<RemoteEvent>>[];
  for (var index = 0; index < events.length; index += faultPageSize) {
    final end = index + faultPageSize;
    pages.add(events.sublist(index, end > events.length ? events.length : end));
  }
  return [for (final page in pages.reversed) ...page];
}

/// 種を固定した擬似乱数。`dart:math` の `Random` と同じ形で足りる分だけ。
///
/// **`Random(seed)` の並びは SDK の実装に属する。** ここで自前にするのは、SDK が変わっても
/// 同じ並びを出し続けるためである — 故障は再現できなければ検証にならない。
class _Deterministic implements Random {
  int _state;

  _Deterministic(int seed) : _state = seed & 0x7fffffff;

  @override
  int nextInt(int max) {
    // 線形合同法。値の質は問わない。**同じ種から同じ並びが出ることだけが要件である。**
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state % max;
  }

  @override
  double nextDouble() => nextInt(1 << 24) / (1 << 24);

  @override
  bool nextBool() => nextInt(2) == 0;
}
