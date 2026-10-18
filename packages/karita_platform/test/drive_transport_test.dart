/// `appDataFolder` の転送 adapter。**ネットワークに触らない。**
///
/// 偽クライアントに対して、名前空間の決定・ページ跨ぎ・重複排除・サーバ側クエリ・遅延反映を
/// 通す。ここで通るものは、口の向こう（HTTP）がどう実装されても変わらない規則である。
library;

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

import 'fake_drive_client.dart';

const String t0 = '2026-08-04T09:00:00Z';

/// 封筒は世代の名前空間に置かれる。
const String gen = '99999999-0000-4000-8000-000000000009';
const String e1 = '10000000-0000-4000-8000-000000000001';
const String e2 = '10000000-0000-4000-8000-000000000002';

String envelope(
  String eventId, {
  Map<String, Object?> payload = const {'title': 'x'},
  String entityId = 'bbbbbbbb-0001-4000-8000-000000000001',
  String createdAtUtc = t0,
}) => dumpsText({
  'schemaVersion': 1,
  'eventId': eventId,
  'deviceId': 'windows-00000000-0000-4000-8000-000000000001',
  'createdAtUtc': createdAtUtc,
  'entityType': 'book',
  'entityId': entityId,
  'operation': 'upsert',
  'baseVersion': 0,
  'resultVersion': 1,
  'payloadHash': payloadHash(payload),
  'resolvesEventIds': const [],
  'payload': payload,
});

void main() {
  late FakeDriveClient fake;
  late DriveTransport transport;

  setUp(() {
    fake = FakeDriveClient();
    transport = DriveTransport(fake, gen);
  });

  group('索引', () {
    test('載せるのは3つだけで、schemaVersion は載せない', () async {
      final properties = indexProperties(e1, envelope(e1));
      expect(properties, {
        'eventId': e1,
        'entityType': 'book',
        'createdAtUtc': t0,
      });
      // 索引に版を置くと、転送層が未対応版を弾く実装への誘惑が生まれる。
      expect(properties.containsKey('schemaVersion'), isFalse);
    });

    test('本文を読めなくても送信は続く', () async {
      // 索引を作れないことは送らない理由にならない。転送は封筒を解釈しない。
      expect(indexProperties(e1, '{ broken'), {'eventId': e1});
    });

    test('クエリの値はエスケープされる', () async {
      expect(eventIdQuery("a'b"), contains("value='a\\'b'"));
    });
  });

  group('受信は差分で取る（2026-10-08）', () {
    const other = '88888888-0000-4000-8000-000000000008';

    test('一覧は世代の前置で絞って問い合わせる', () async {
      await transport.put(e1, envelope(e1));
      await DriveTransport(fake, other).put(e2, envelope(e2));
      fake.queries.clear();

      final events = await transport.list();
      expect(fake.queries, ["name contains 'event-$gen-'"]);
      expect([for (final event in events) event.eventId], [e1]);
    });

    test('既知の封筒は本文を取らない', () async {
      await transport.put(e1, envelope(e1));
      await transport.put(e2, envelope(e2));
      fake.fetched.clear();

      final events = await transport.list(known: (id) => id == e1);
      expect([for (final event in events) event.eventId], [e2]);
      expect(fake.fetched, hasLength(1), reason: '既知の e1 まで本文を取っている');
    });

    test('名前から読む eventId は世代の封筒だけである', () {
      expect(eventIdOfName(eventName(gen, e1), gen), e1);
      expect(eventIdOfName(eventName(other, e1), gen), isNull);
      expect(eventIdOfName('baseline-0001-$gen.blib', gen), isNull);
    });
  });

  group('往復', () {
    test('put したものが list に出る', () async {
      final remoteId = await transport.put(e1, envelope(e1));
      final events = await transport.list();
      expect(events, hasLength(1));
      expect(events.single.remoteId, remoteId);
      expect(events.single.eventId, e1);
      expect(events.single.createdAtUtc, t0);
    });

    test('delete で消える', () async {
      await transport.delete(await transport.put(e1, envelope(e1)));
      expect(await transport.list(), isEmpty);
    });
  });

  group('名前空間', () {
    test('同居する他アプリのファイルはイベントではない', () async {
      // 転送先は「アプリ × ユーザ」単位で共有される。名前で絞らないと、同じ Cloud project の
      // 別のものが書いた JSON を invalid として数え、恒久的に失敗し続ける。実 Drive で実際に
      // 起きた。
      await fake.create(
        'book-sync-personal-pkce-probe-v1.json',
        const {},
        '{"format":"drive-appdata-pkce-probe/v1","runId":"x"}',
      );
      await transport.put(e1, envelope(e1));
      fake.fetched.clear();

      expect([for (final event in await transport.list()) event.eventId], [e1]);
      // 名前で落とすのは本文を取る前である。要らないものを download しない。
      expect(fake.fetched, hasLength(1));
    });

    test('別世代の封筒は自分の一覧に出ない', () async {
      const other = '88888888-0000-4000-8000-000000000008';
      await fake.create(eventName(other, e1), {'eventId': e1}, envelope(e1));
      expect(await transport.list(), isEmpty);
    });

    test('壊れた封筒でも名前が合っていれば運ぶ', () async {
      // 名前空間で絞るのは封筒の解釈ではない。取り込めない封筒を転送層で捨てると、受信側が
      // 「取り込めないイベントを破棄しない」を守れなくなる。
      await fake.create(eventName(gen, e1), {'eventId': e1}, '{ broken');
      final events = await transport.list();
      expect(events, hasLength(1));
      expect(events.single.eventId, isNull);
    });
  });

  group('重複', () {
    test('同名の重複作成を一覧が畳む', () async {
      // 置き換えが無いことは故障ではなく仕様である。受信側が eventId で畳む（受入ケース07）。
      final text = envelope(e1);
      final first = await transport.put(e1, text);
      final second = await transport.put(e1, text);
      expect(first, isNot(second));
      expect(fake.files, hasLength(2));

      final events = await transport.list();
      expect(events, hasLength(1));
      expect(events.single.duplicateRemoteIds, [second]);
      expect(events.single.duplicateMismatch, isFalse);
    });

    test('内容の違う複製は報告する', () async {
      // 「転送先のイベントは不変」の違反である。黙って落とすと、片方の端末だけが壊れた封筒を
      // 書き続けても誰も気づかない。
      await transport.put(e1, envelope(e1));
      await transport.put(e1, envelope(e1, payload: const {'title': 'y'}));
      final events = await transport.list();
      expect(events, hasLength(1));
      expect(events.single.duplicateMismatch, isTrue);
    });
  });

  group('ページ跨ぎ', () {
    test('ページに割れても結果は変わらない', () async {
      // ページを跨いだ大域の順序は無い。整列は転送層が行う。
      final ids = [
        for (var n = 0; n < 7; n++) '1000000$n-0000-4000-8000-000000000001',
      ];
      for (final eventId in ids.reversed) {
        await transport.put(eventId, envelope(eventId));
      }
      expect(fake.pageSize, 3, reason: '7件が3ページに割れること');

      expect([
        for (final event in await transport.list()) event.eventId,
      ], [...ids]..sort());
    });

    test('ページ境界で同じ file id が二度返っても複製にならない', () async {
      // file id は一意なので、ここで落とすのは複製ではなく重複ページである。
      final client = _RepeatingPageClient(FakeDriveClient(pageSize: 2));
      final repeating = DriveTransport(client, gen);
      for (final eventId in [e1, e2]) {
        await repeating.put(eventId, envelope(eventId));
      }
      final events = await repeating.list();
      expect(events, hasLength(2));
      expect(
        [for (final event in events) event.duplicateRemoteIds],
        [<String>[], <String>[]],
      );
    });
  });

  group('検索', () {
    test('サーバ側クエリで絞る', () async {
      await transport.put(e1, envelope(e1));
      await transport.put(
        e2,
        envelope(e2, entityId: 'bbbbbbbb-0002-4000-8000-000000000002'),
      );
      fake.fetched.clear();

      final found = await transport.find(e2);
      expect(found?.eventId, e2);
      // 索引で絞っているので、本文を取ったのは1件だけである。
      expect(fake.fetched, hasLength(1));
      expect(fake.queries.last, contains(e2));
    });

    test('索引ではなく本文を信じる', () async {
      // 索引は後から書き換えられうるメタデータであり、既送信とみなす根拠にならない。
      await fake.create('${generationPrefix(gen)}x.json', {
        'eventId': e1,
      }, envelope(e2));
      expect(await transport.find(e1), isNull);
    });

    test('無ければ null', () async {
      expect(await transport.find(e1), isNull);
    });

    test('検索の認可失敗は TransportAuthError のまま出る', () async {
      // 再送の行は put の前に転送先を検索する。ここで認可を失うと、送信側は「書けていない」
      // ことすら確かめられない。呼び出し側が blocked_auth へ落とせるよう、認可の語彙のまま
      // 抜ける必要がある — 実 Drive では、この経路だけが uploading に滞留した。
      fake.failListWithAuth = true;
      await expectLater(transport.find(e1), throwsA(isA<TransportAuthError>()));
      await expectLater(transport.list(), throwsA(isA<TransportAuthError>()));
    });
  });

  test('書込み直後に見えない転送先では検索が既送信を見つけられない', () async {
    // その結果として重複が作られるのは実装の誤りではなく、保管先の性質に対して正しく振る
    // 舞った結果である。受け止めるのは受信側の重複排除（受入ケース07）である。
    final hiding = FakeDriveClient(hideNew: true);
    final delayed = DriveTransport(hiding, gen);
    await delayed.put(e1, envelope(e1));
    expect(await delayed.find(e1), isNull);
    expect(await delayed.list(), isEmpty);

    hiding.reveal();
    expect(await delayed.find(e1), isNotNull);
  });
}

/// すべてのページの先頭1件を、そのページにもう一度混ぜて返す。
///
/// 実 Drive の一覧はページの境界で同じファイルを二度返すことがある。偽クライアントの既定は
/// 素直に割るので、この経路だけ包んで作る。
class _RepeatingPageClient implements DriveClient {
  final FakeDriveClient inner;

  _RepeatingPageClient(this.inner);

  @override
  Future<DrivePage> listPage({String? pageToken, String? query}) async {
    final page = await inner.listPage(pageToken: pageToken, query: query);
    if (page.files.isEmpty) return page;
    return DrivePage([page.files.first, ...page.files], page.nextPageToken);
  }

  @override
  Future<String> create(
    String name,
    Map<String, String> appProperties,
    String text,
  ) => inner.create(name, appProperties, text);

  @override
  Future<Uploaded> createBinary(
    String name,
    Map<String, String> appProperties,
    String path,
  ) => inner.createBinary(name, appProperties, path);

  @override
  Future<void> delete(String fileId) => inner.delete(fileId);

  @override
  Future<void> download(String fileId, String destPath) =>
      inner.download(fileId, destPath);

  @override
  Future<String> getText(String fileId) => inner.getText(fileId);

  @override
  Future<void> rename(String fileId, String name) => inner.rename(fileId, name);

  @override
  Future<DriveAccountInfo> about() => inner.about();
}
