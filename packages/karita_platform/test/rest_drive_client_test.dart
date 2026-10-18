/// Drive REST adapter を偽 Drive サーバに対して通す。**ネットワークも token も要らない。**
///
/// ここが測るのは口の**向こう側**である — 要求の組み立て、resumable upload の手順、
/// `pageToken` のループ、チャンク download、401 の分類と取り直し。判定・整列・重複排除・
/// 二段名・検算は層1（`drive_transport_test` / `drive_backup_store_test`）が持つ。
///
/// **層1 と層2 を通せば、実 Drive に残る問いは「Google が実際にどう振る舞うか」だけになる。**
library;

import 'dart:convert';
import 'dart:io';

import 'package:karita_contract/errors.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

import 'fake_drive_server.dart';

/// 呼ばれた回数と、取り直しを求められたかを数えるトークン供給。
class _Tokens implements AccessTokenProvider {
  /// 取り直しのたびに次の値へ進む。
  final List<String> issue;

  /// 取り直しそのものが失敗する。**認可を本当に失った状態である。**
  bool refreshFails;

  int calls = 0;
  int refreshes = 0;

  _Tokens(this.issue, {this.refreshFails = false});

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    calls++;
    if (forceRefresh) {
      refreshes++;
      if (refreshFails) {
        // 資格情報そのものが無効になった。再ログイン以外に回復手段は無い。
        throw TransportAuthError('$invalidGrant: 再ログインが必要です。');
      }
      if (issue.length > 1) issue.removeAt(0);
    }
    return issue.first;
  }
}

void main() {
  late FakeDriveServer server;
  late _Tokens tokens;
  late RestDriveClient client;
  late Directory work;

  setUp(() async {
    server = await FakeDriveServer.start();
    tokens = _Tokens(['token-1']);
    client = RestDriveClient(
      tokens: tokens,
      apiBase: server.apiBase,
      uploadBase: server.uploadBase,
      pageSize: 2,
      // 刻みを小さくして、resumable の複数往復を通常の経路にする。
      chunkBytes: 16,
    );
    work = Directory.systemTemp.createTempSync('karita-rest-');
  });

  tearDown(() async {
    client.close();
    await server.close();
    work.deleteSync(recursive: true);
  });

  String fileAt(String name, List<int> bytes) {
    final path = '${work.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(bytes, flush: true);
    return path;
  }

  group('要求の組み立て', () {
    test('封筒は multipart で載り、appDataFolder を親にする', () async {
      final id = await client.create('event-1.json', {
        'eventId': 'e1',
      }, '{"eventId":"e1"}');

      expect(server.files[id]!.name, 'event-1.json');
      expect(server.files[id]!.appProperties, {'eventId': 'e1'});
      expect(utf8.decode(server.files[id]!.body), '{"eventId":"e1"}');

      final sent = server.requests.single;
      expect(sent.method, 'POST');
      expect(sent.uri.queryParameters['uploadType'], 'multipart');
      expect(sent.headers['content-type'], contains('multipart/related'));
      // **親を書き忘れると、利用者から見える My Drive に置かれる。**
      expect(sent.bodyText, contains('"parents":["appDataFolder"]'));
    });

    test('一覧は appDataFolder に限り、要る項目だけを求める', () async {
      await client.listPage();

      final sent = server.requests.single;
      expect(sent.uri.queryParameters['spaces'], 'appDataFolder');
      expect(sent.uri.queryParameters['pageSize'], '2');
      // 項目を絞らないと、使わないものまで運ぶ。
      expect(
        sent.uri.queryParameters['fields'],
        'nextPageToken,files(id,name,appProperties,size)',
      );
      expect(sent.uri.queryParameters.containsKey('q'), isFalse);
    });

    test('検索はサーバ側クエリを載せる', () async {
      await client.listPage(query: eventIdQuery('e9'));
      expect(
        server.requests.single.uri.queryParameters['q'],
        contains("value='e9'"),
      );
    });

    test('本文の取得は alt=media を付ける', () async {
      final id = server.seed('event-1.json', const {}, 'raw-body');
      expect(await client.getText(id), 'raw-body');
      expect(server.requests.single.uri.queryParameters['alt'], 'media');
    });

    test('改名は PATCH で名前だけを送る', () async {
      final id = server.seed('incoming-1.blib', const {}, 'x');
      await client.rename(id, 'backup-1.blib');

      expect(server.files[id]!.name, 'backup-1.blib');
      final sent = server.requests.single;
      expect(sent.method, 'PATCH');
      expect(jsonDecode(sent.bodyText), {'name': 'backup-1.blib'});
    });

    test('削除は DELETE で 204 を受ける', () async {
      final id = server.seed('event-1.json', const {}, 'x');
      await client.delete(id);
      expect(server.files, isEmpty);
    });

    test('size は文字列で返る。数として読み違えない', () async {
      // 実 Drive は `size` を文字列で返す。数値として読むと 0 に落ち、baseline の大きさが
      // すべて 0 になる。
      server.seed('event-1.json', const {}, '1234567890');
      final page = await client.listPage();
      expect(page.files.single.sizeBytes, 10);
    });
  });

  group('about.get', () {
    test('要る項目だけを求め、permissionId とメールを読む', () async {
      final info = await client.about();
      expect(info.permissionId, 'server-account-1');
      expect(info.emailAddress, 'server@example.com');

      final sent = server.requests.single;
      expect(sent.method, 'GET');
      expect(sent.uri.path, '/drive/v3/about');
      expect(
        sent.uri.queryParameters['fields'],
        'user(emailAddress,permissionId,displayName)',
      );
    });

    test('emailAddress が返らなくても permissionId だけは読める', () async {
      server.account = const {'permissionId': 'server-account-1'};
      final info = await client.about();
      expect(info.permissionId, 'server-account-1');
      expect(info.emailAddress, isNull);
    });
  });

  group('pageToken のループ', () {
    test('ページを跨いで全件を返す', () async {
      for (var n = 0; n < 5; n++) {
        server.seed('event-$n.json', {'eventId': 'e$n'}, '{}');
      }
      expect(server.pageSize, 2, reason: '5件が3ページに割れること');

      final seen = <String>[];
      String? pageToken;
      var pages = 0;
      while (true) {
        final page = await client.listPage(pageToken: pageToken);
        pages++;
        seen.addAll([for (final ref in page.files) ref.fileId]);
        pageToken = page.nextPageToken;
        if (pageToken == null) break;
      }

      expect(pages, 3);
      expect(seen, hasLength(5));
      // 最後のページだけが `nextPageToken` を持たない。
      expect(server.requests.last.uri.queryParameters['pageToken'], '4');
    });
  });

  group('resumable upload', () {
    test('セッションを開いてから刻んで載せる', () async {
      final payload = List<int>.generate(40, (n) => n % 251);
      final uploaded = await client.createBinary(
        'incoming-1.blib',
        const {},
        fileAt('a.blib', payload),
      );

      expect(server.files[uploaded.fileId]!.body, payload);
      expect(uploaded.sizeBytes, 40);
      expect(uploaded.md5, isNotEmpty);

      // 1回目がセッションを開く POST、以降が PUT である。
      final opening = server.requests.first;
      expect(opening.method, 'POST');
      expect(opening.uri.queryParameters['uploadType'], 'resumable');
      expect(opening.headers['x-upload-content-length'], '40');
      // **検算の2つを名指しする。** 求めないと保管先は返さず、公開が必ず落ちる。
      expect(opening.uri.queryParameters['fields'], 'id,md5Checksum,size');

      final puts = server.requests.where((r) => r.method == 'PUT').toList();
      expect(puts, hasLength(3), reason: '16 バイト刻みで 40 バイトなら3回');
      expect(puts.first.headers['content-range'], 'bytes 0-15/40');
      expect(puts.last.headers['content-range'], 'bytes 32-39/40');
    });

    test('308 で部分受理されたら、サーバの言う続きから送る', () async {
      // **次の起点はサーバが決める。** こちらの数え方で進めると、取りこぼした分を送り直せない。
      server.acceptPerPut = 10;
      final payload = List<int>.generate(40, (n) => n % 251);
      final uploaded = await client.createBinary(
        'incoming-1.blib',
        const {},
        fileAt('a.blib', payload),
      );

      expect(
        server.files[uploaded.fileId]!.body,
        payload,
        reason: '受理済みの末尾を無視すると、内容が欠けるか重複する',
      );
      final puts = server.requests.where((r) => r.method == 'PUT').toList();
      expect(puts.first.headers['content-range'], 'bytes 0-15/40');
      // 10 バイトしか受理されなかったので、次は 10 から始まる。
      expect(puts[1].headers['content-range'], 'bytes 10-25/40');
    });

    test('検算の値が返らない応答をそのまま持ち帰る', () async {
      // 落とすかどうかを決めるのは保管先の層である（層1）。ここは**返らなかったことを
      // 返らなかったまま**上へ渡す。0 や空文字を捏造すると、上の検算が「一致した」に倒れる。
      server.omitSize = true;
      server.omitMd5 = true;
      final uploaded = await client.createBinary(
        'incoming-1.blib',
        const {},
        fileAt('a.blib', [1, 2, 3]),
      );
      expect(uploaded.sizeBytes, 0);
      expect(uploaded.md5, isEmpty);
    });

    test('セッションが開けなければ黙って成功しない', () async {
      // Location が無ければ載せる先が無い。
      server.failNextWith = 500;
      await expectLater(
        client.createBinary(
          'incoming-1.blib',
          const {},
          fileAt('a.blib', [1, 2, 3]),
        ),
        throwsA(isA<TransportTimeout>()),
      );
    });
  });

  group('チャンク download', () {
    test('落としたものが元と同じで、.part を残さない', () async {
      final payload = List<int>.generate(1000, (n) => n % 251);
      final id = server.seed('backup-1.blib', const {}, '');
      server.files[id]!.body = payload;

      final dest = '${work.path}${Platform.pathSeparator}out.blib';
      await client.download(id, dest);

      expect(File(dest).readAsBytesSync(), payload);
      expect(File('$dest.part').existsSync(), isFalse);
    });

    test('落ちた download は完成品の名前を残さない', () async {
      // 中断した download が完成品の名前で残ると、次の復元がそれを選ぶ。
      server.failNextWith = 500;
      final dest = '${work.path}${Platform.pathSeparator}out.blib';
      await expectLater(
        client.download('file1', dest),
        throwsA(isA<SyncDataError>()),
      );
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.part').existsSync(), isFalse);
    });
  });

  group('401 の分類', () {
    test('期限切れは一度だけ取り直して送り直す', () async {
      // 1回の 401 で「認可を失った」と決めると、使っている端末が毎日サインインを求められる。
      tokens = _Tokens(['stale', 'token-1']);
      client = RestDriveClient(
        tokens: tokens,
        apiBase: server.apiBase,
        uploadBase: server.uploadBase,
      );
      server.seed('event-1.json', const {}, 'body');

      final page = await client.listPage();
      expect(page.files, hasLength(1), reason: '取り直した後の要求が通っていない');
      expect(tokens.refreshes, 1);
      // 401 を受けた1回と、取り直して送り直した1回。
      expect(server.requests, hasLength(2));
    });

    test('取り直しても駄目なら認可の失敗である', () async {
      tokens = _Tokens(['stale'], refreshFails: true);
      client = RestDriveClient(
        tokens: tokens,
        apiBase: server.apiBase,
        uploadBase: server.uploadBase,
      );
      await expectLater(client.listPage(), throwsA(isA<TransportAuthError>()));
    });

    test('取り直しが通らない 401 は認可の失敗であって「不明」ではない', () async {
      // 取り直したトークンもサーバが拒む。**書き込みでも `TransportTimeout` にしない** —
      // 401 で拒否された要求は処理されておらず、届いたかもしれないではない。
      tokens = _Tokens(['wrong']);
      client = RestDriveClient(
        tokens: tokens,
        apiBase: server.apiBase,
        uploadBase: server.uploadBase,
      );
      await expectLater(
        client.create('event-1.json', const {}, '{}'),
        throwsA(isA<TransportAuthError>()),
      );
    });

    test('書き込みの 401 も再送を作らない', () async {
      // 401 を受けた要求は何も書いていない。送り直しても重複にならない。
      tokens = _Tokens(['stale', 'token-1']);
      client = RestDriveClient(
        tokens: tokens,
        apiBase: server.apiBase,
        uploadBase: server.uploadBase,
      );
      await client.create('event-1.json', const {}, '{}');
      expect(server.files, hasLength(1), reason: '重複が作られている');
    });
  });

  group('その他の失敗', () {
    test('書き込みの失敗は「結果が不明」である', () async {
      // lease を保持したまま `uploading` に残す判断へ直結する。
      server.failNextWith = 500;
      await expectLater(
        client.create('event-1.json', const {}, '{}'),
        throwsA(isA<TransportTimeout>()),
      );
    });

    test('読み取りの失敗は「不明」ではない', () async {
      // 読み取りを同じ例外に写すと、送っていない行が uploading に落ちる。
      server.failNextWith = 503;
      await expectLater(
        client.listPage(),
        throwsA(
          isA<SyncDataError>().having((e) => e.code, 'code', 'transport-io'),
        ),
      );

      // 型そのものを見る。`transport-io` の code だけでは、`TransportTimeout` が code を
      // 変えて同じ枝に入っても気づけない。
      server.failNextWith = 503;
      await expectLater(
        client.listPage(),
        throwsA(predicate((e) => e is! TransportTimeout)),
      );
    });

    test('繋がらない相手は書き込みでも読み取りでも語彙どおりに写る', () async {
      // status を持たない失敗。**通信が落ちただけの状態を認可喪失として記録しない。**
      final dead = RestDriveClient(
        tokens: _Tokens(['token-1']),
        apiBase: Uri.parse('http://127.0.0.1:1/drive/v3'),
        uploadBase: Uri.parse('http://127.0.0.1:1/upload/drive/v3'),
      );
      await expectLater(
        dead.listPage(),
        throwsA(
          isA<SyncDataError>().having((e) => e.code, 'code', 'transport-io'),
        ),
      );
      await expectLater(
        dead.create('event-1.json', const {}, '{}'),
        throwsA(isA<TransportTimeout>()),
      );
      dead.close();
    });

    test('失敗の文言に要求の中身を載せない', () async {
      server.failNextWith = 500;
      try {
        await client.create('event-1.json', const {}, '{"secret":"x"}');
        fail('落ちるはずである');
      } on SyncDataError catch (exc) {
        expect(exc.message, isNot(contains('secret')));
        expect(exc.message, isNot(contains('Bearer')));
      }
    });
  });

  group('層1 と繋いだ往復', () {
    // **層1 の規則が、口の向こうが本物の HTTP でも変わらないこと。** ここが通れば、実 Drive に
    // 残る問いは「Google が実際にどう振る舞うか」だけになる。
    const gen = '99999999-0000-4000-8000-000000000009';
    const e1 = '10000000-0000-4000-8000-000000000001';

    test('DriveTransport が REST の上で往復する', () async {
      final transport = DriveTransport(client, gen);
      final text = '{"eventId":"$e1","createdAtUtc":"2026-08-04T09:00:00Z"}';
      await transport.put(e1, text);

      // 名前空間の外にあるものは拾わない。
      server.seed('someone-elses-probe.json', const {}, '{}');

      final events = await transport.list();
      expect(events, hasLength(1));
      expect(events.single.eventId, e1);
      expect((await transport.find(e1))?.text, text);
    });

    test('DriveBackupStore が REST の上で二段名を通る', () async {
      final store = DriveBackupStore(client);
      final path = fileAt('b.blib', List<int>.generate(40, (n) => n));

      final remoteId = await store.putBaseline(1, gen, path);
      expect(server.files[remoteId]!.name, 'baseline-0001-$gen.blib');

      final baselines = await store.listBaselines();
      expect(baselines, hasLength(1));
      expect(baselines.single.seq, 1);
      expect(baselines.single.sizeBytes, 40);

      final dest = '${work.path}${Platform.pathSeparator}back.blib';
      await store.getBaseline(baselines.single, dest);
      expect(File(dest).readAsBytesSync(), File(path).readAsBytesSync());
    });
  });
}
