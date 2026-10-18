/// 故障注入の転送。**受入ケースが踏まない規則をここで縛る。**
///
/// ケース07〜10 は故障の**結果**（outbox の行き先、転送先の件数）を測る。ここが測るのは
/// 故障そのものの約束 — 書いてから投げること、名前を間違えたら落ちること、順序の壊し方が
/// 再現できることである。
library;

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

/// `eventId` をそのまま名前にする、最小の疑似転送。
class _Memory implements DuplicatingTransport {
  final Map<String, String> entries = {};
  int _duplicates = 0;

  @override
  String get kind => 'memory';

  @override
  Future<String> put(String eventId, String text) async {
    entries[eventId] = text;
    return eventId;
  }

  @override
  Future<String> putDuplicate(String eventId, String text) async {
    final name = '$eventId--${++_duplicates}';
    entries[name] = text;
    return name;
  }

  @override
  Future<List<RemoteEvent>> list({KnownEvent? known}) async => [
        for (final entry in entries.entries)
          RemoteEvent(
              remoteId: entry.key, eventId: entry.key, text: entry.value),
      ];

  @override
  Future<RemoteEvent?> find(String eventId) async =>
      firstMatching(await list(), eventId);

  @override
  Future<void> delete(String remoteId) async => entries.remove(remoteId);
}

/// 複製を作れない転送。`duplicate-name` はこれを明示的に拒む。
class _Plain implements TransportPort {
  @override
  String get kind => 'plain';
  @override
  Future<String> put(String eventId, String text) async => eventId;
  @override
  Future<List<RemoteEvent>> list({KnownEvent? known}) async => const [];
  @override
  Future<RemoteEvent?> find(String eventId) async => null;
  @override
  Future<void> delete(String remoteId) async {}
}

void main() {
  late _Memory inner;

  setUp(() => inner = _Memory());

  FaultTransport faulted(List<String> faults) => FaultTransport(inner, faults);

  test('故障が無ければ包んでいる転送と同じである', () async {
    // 「故障の無い fault 転送」が素の転送と別物になると、比較の基準が失われる。
    final transport = faulted(const []);
    expect(transport.kind, 'memory');
    await transport.put('e1', '{}');
    expect(await transport.find('e1'), isNotNull);
  });

  test('未知の故障名は落とす', () async {
    // 綴り間違いを黙って受けると、「故障を入れたつもりで入っていない」まま緑になる。
    expect(() => faulted(const ['upload-timout']),
        throwsA(isA<SyncDataError>().having((e) => e.code, 'code', 'fault-name')));
  });

  group('upload-timeout', () {
    test('書いてから投げる。実体は残る', () async {
      // **順序が要点である。** 先に投げると実体の無い「不明」になり、受入ケース08 が測るもの
      // （応答は失われたが実体は書かれている）が変わってしまう。
      final transport = faulted(const [faultUploadTimeout]);
      await expectLater(
          transport.put('e1', '{}'), throwsA(isA<TransportTimeout>()));
      expect(inner.entries.keys, ['e1']);
    });

    test('読み取りには効かない', () async {
      await inner.put('e1', '{}');
      expect(await faulted(const [faultUploadTimeout]).list(), hasLength(1));
    });
  });

  group('duplicate-name', () {
    test('同じ eventId の実体をもう1つ作る', () async {
      final transport = faulted(const [faultDuplicateName]);
      final first = await transport.put('e1', '{}');
      final second = await transport.put('e1', '{}');
      expect(first, isNot(second));
      expect(inner.entries, hasLength(2));
    });

    test('複製を作れない転送は明示的に拒む', () async {
      // 黙って1件だけ書くと、重複排除を測るケースが「重複が無い」まま緑になる。
      final transport = FaultTransport(_Plain(), const [faultDuplicateName]);
      await expectLater(
          transport.put('e1', '{}'),
          throwsA(isA<SyncDataError>()
              .having((e) => e.code, 'code', 'fault-unsupported')));
    });
  });

  group('auth-401', () {
    test('put も list も delete も等しく落ちる', () async {
      final transport = faulted(const [faultAuth401]);
      await expectLater(
          transport.put('e1', '{}'), throwsA(isA<TransportAuthError>()));
      await expectLater(transport.list(), throwsA(isA<TransportAuthError>()));
      await expectLater(
          transport.delete('e1'), throwsA(isA<TransportAuthError>()));
    });

    test('検索も落ちる。再送は検索の側で 401 を受ける', () async {
      // 実 Drive が出した穴がこれである。`attempts > 1` の行は put の前に転送先を検索する
      // ので、認可を失っていると検索の側で 401 を受ける。
      await expectLater(
          faulted(const [faultAuth401]).find('e1'),
          throwsA(isA<TransportAuthError>()));
    });

    test('何も書かない', () async {
      await expectLater(faulted(const [faultAuth401]).put('e1', '{}'),
          throwsA(isA<TransportAuthError>()));
      expect(inner.entries, isEmpty);
    });
  });

  group('delayed-visibility', () {
    test('この転送を通じて書いたものだけを隠す', () async {
      await inner.put('before', '{}');
      final transport = faulted(const [faultDelayedVisibility]);
      await transport.put('after', '{}');

      final visible = [for (final event in await transport.list()) event.eventId];
      expect(visible, ['before'], reason: '先にあったものまで隠している');
      // 再送の検索が既送信を見つけられない。その結果の重複は正しい振る舞いである。
      expect(await transport.find('after'), isNull);
    });
  });

  group('順序を壊す', () {
    Future<List<String?>> idsAfter(List<String> faults) async {
      for (var n = 0; n < 7; n++) {
        await inner.put('e$n', '{}');
      }
      return [for (final event in await faulted(faults).list()) event.eventId];
    }

    test('paginate はページ内の並びを保ったまま全体を壊す', () async {
      // ページを跨いだ大域の順序が無いことを模す。ページ内は崩さない。
      // 3件ずつ [e0 e1 e2][e3 e4 e5][e6] に割れ、ページの順序だけを逆にする。
      expect(await idsAfter(const [faultPaginate]),
          ['e6', 'e3', 'e4', 'e5', 'e0', 'e1', 'e2']);
    });

    test('shuffle は同じ種から同じ並びを出す', () async {
      // **故障は再現できなければ検証にならない。** 落ちたときに同じ並びで再現できること。
      final first = await idsAfter(const [faultShuffle]);
      inner.entries.clear();
      final second = await idsAfter(const [faultShuffle]);
      expect(first, second);
      expect(first, isNot(['e0', 'e1', 'e2', 'e3', 'e4', 'e5', 'e6']),
          reason: '並べ替えが効いていない');
    });
  });
}
