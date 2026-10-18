/// 実 Drive を叩く。**無印の `dart test` では走らない**（`dart test -P drive`）。
///
/// **ここが答えるのは「Google が実際にどう振る舞うか」だけである。** 判定・整列・重複排除・
/// 二段名・検算は層1 が、要求の組み立て・resumable の手順・401 の分類は層2 が既に通している。
/// 実物に残る問いは、こちらの理解が実際の応答と合っているかどうかに絞られる。
///
/// **隔離は世代の名前空間で取る。** 転送先を初期化できないという制約に対して、封筒の名前が
/// `event-<generationId>-<eventId>.json` である以上、run ごとに新しい `generationId` を使えば
/// その run だけの空間になる。おかげで**件数の絶対値まで表明できる** — 正本の横断ランナーが
/// 諦めていたことである。
///
/// **書いたものは自分で消す。** 使い捨ての世代に置いた封筒を残すと、`appDataFolder` に永久に
/// 溜まる。通常運用の `prune` を drive で拒むのとは別の話で、これは自分が作った試験の残骸で
/// ある。
@Tags(['drive'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

/// 実 Drive を叩けるか。飛ばすときは理由を返す。
///
/// **karita-core の単体試験が認可を要求するようにはしない。** 資格情報も token も無い環境で
/// 「なぜ飛んだか」が見えることの方が、赤くなることより役に立つ。
String? skipReason() {
  final AppPaths paths;
  try {
    paths = WindowsAppPaths.resolve();
  } on SyncDataError catch (exc) {
    return '既定のデータ領域を決められない: ${exc.message}';
  }
  if (!File(paths.credentialsPath).existsSync()) {
    return '資格情報が無い（${paths.credentialsPath}）';
  }
  if (TokenStore(paths.tokenPath).load() == null) {
    return 'token が無い（dart run drive_probe:drive_probe login で認可する）';
  }
  return null;
}

String nowUtc() =>
    '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

/// この run だけの世代。**実行ごとに新しくする。**
String freshGeneration() {
  final stamp = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16);
  return '11111111-0000-4000-8000-${stamp.padLeft(12, '0').substring(0, 12)}';
}

String envelopeText(
  String eventId, {
  String title = 'x',
  String? createdAtUtc,
}) {
  final payload = {'title': title};
  return dumpsText({
    'schemaVersion': 1,
    'eventId': eventId,
    'deviceId': 'windows-00000000-0000-4000-8000-000000000001',
    'createdAtUtc': createdAtUtc ?? '2026-09-02T09:00:00Z',
    'entityType': 'book',
    'entityId': 'bbbbbbbb-0001-4000-8000-000000000001',
    'operation': 'upsert',
    'baseVersion': 0,
    'resultVersion': 1,
    'payloadHash': payloadHash(payload),
    'resolvesEventIds': const [],
    'payload': payload,
  });
}

void main() {
  final skip = skipReason();
  if (skip != null) {
    // 飛ばした理由は必ず見えるところへ出す。黙って 0 件成功にしない。
    print('実 Drive の確認を飛ばす: $skip');
  }

  late AppPaths paths;
  late RestDriveClient client;
  late GoogleOAuth oauth;
  late String generationId;
  late Directory work;

  /// この run が作ったもの。**片付けるために覚えておく。**
  final created = <String>[];

  setUpAll(() {
    if (skip != null) return;
    paths = WindowsAppPaths.resolve();
    oauth = GoogleOAuth(loadDesktopClient(paths.credentialsPath));
    client = RestDriveClient(
      tokens: GoogleAccessTokenProvider(
        store: TokenStore(paths.tokenPath),
        oauth: oauth,
        now: nowUtc,
      ),
      // **小さくする。** 実 Drive でページ跨ぎを通常の経路にするためで、既定の 100 では
      // 数件しか置かない試験が1ページで終わってしまう。
      pageSize: 2,
      chunkBytes: 256 * 1024,
    );
    generationId = freshGeneration();
    work = Directory.systemTemp.createTempSync('karita-drive-live-');
    print('この run の世代: $generationId');
  });

  tearDownAll(() async {
    if (skip != null) return;
    // **自分が作ったものだけを消す。** 名前で拾って消すと、同居している他のものに当たる。
    for (final remoteId in created) {
      try {
        await client.delete(remoteId);
      } on SyncDataError {
        // 消せなくても他の片付けを続ける。残っても次の run は別の世代を使う。
      }
    }
    client.close();
    oauth.close();
    work.deleteSync(recursive: true);
  });

  Future<String> put(
    DriveTransport transport,
    String eventId,
    String text,
  ) async {
    final remoteId = await transport.put(eventId, text);
    created.add(remoteId);
    return remoteId;
  }

  group('S5 確認1 — 認可', () {
    test('要求している scope は drive.appdata だけである', () {
      // 広げると、appDataFolder の外を触れる資格情報が端末に残る。
      final token = TokenStore(paths.tokenPath).load()!;
      expect(token.scopes, [appDataScope]);
      expect(
        token.refreshToken,
        isNotNull,
        reason: 'refresh token が無いと、期限が切れた時点で回復手段が無い',
      );
    }, skip: skip);
  });

  group('P5 単位E — about.get', () {
    test('permissionId が読め、emailAddress が返るかを実測する', () async {
      // **実応答は未測定だった。** scope（drive.appdata）が about.get を受理することは
      // 公式ドキュメントで確認済みだが、emailAddress が実際に返るかどうかはここでしか
      // 測れない（`非公開資料:production-wiring-auth-backup-sync.md`「未決」）。
      final info = await client.about();
      expect(
        info.permissionId,
        isNotEmpty,
        reason: '安定 ID が読めないと、別アカウントの同一性判定が成立しない',
      );
      // **返らなくても判定は成立する。** permissionId だけで足りる設計であることの確認で、
      // 表明はしない — 「返らない場合がある」という公式の注記どおりの挙動を記録するだけ。
      print(
        '確認 about.get: emailAddress は'
        '${info.emailAddress == null ? "返らなかった" : "返った"}',
      );
    }, skip: skip);
  });

  group('S5 確認2 — 単端末の往復', () {
    test('置いたものが一覧と検索の両方に出て、本文が一致する', () async {
      final transport = DriveTransport(client, generationId);
      const eventId = '10000000-0000-4000-8000-0000000000a1';
      final text = envelopeText(eventId);
      final remoteId = await put(transport, eventId, text);

      // **件数の絶対値を表明できる。** 世代で名前空間が分かれているためである。
      final events = await transport.list();
      expect(events, hasLength(1));
      expect(events.single.remoteId, remoteId);
      expect(events.single.text, text);

      final found = await transport.find(eventId);
      expect(found?.text, text, reason: 'サーバ側クエリが実 Drive で効いていない');
    }, skip: skip);
  });

  group('S5 確認3 — 書込み直後の可視性', () {
    test('直後に見えなくても、待てば必ず見える', () async {
      // **「直後に見えること」を表明しない。** 一度観測されなかったことは起こらないことの
      // 証明ではなく、遅延は保管先の性質として許されている。受け止めるのは受信側の重複排除
      // （受入ケース07）である。ここは観測を記録し、**最終的に見えること**だけを縛る。
      final transport = DriveTransport(client, generationId);
      const eventId = '10000000-0000-4000-8000-0000000000a2';
      await put(transport, eventId, envelopeText(eventId));

      final immediately = await transport.find(eventId);
      print('確認3 書込み直後の可視性: ${immediately == null ? '遅延あり' : '直後に見えた'}');

      if (immediately == null) {
        await Future<void>.delayed(const Duration(seconds: 5));
        expect(await transport.find(eventId), isNotNull, reason: '5秒待っても現れない');
      }
    }, skip: skip);
  });

  group('S5 確認6 — 同名重複', () {
    test('同じ名前で二度作れ、受信側が eventId で畳む', () async {
      // **置き換えが無いことは故障ではなく仕様である。** それを実物で確かめる。
      final transport = DriveTransport(client, generationId);
      const eventId = '10000000-0000-4000-8000-0000000000a3';
      final text = envelopeText(eventId);

      final first = await put(transport, eventId, text);
      final second = await put(transport, eventId, text);
      expect(first, isNot(second), reason: '同名で上書きされている（仕様の理解が違う）');

      final events = await transport.list();
      final matched = events
          .where((event) => event.eventId == eventId)
          .toList();
      expect(matched, hasLength(1), reason: '重複が畳まれていない');
      expect(matched.single.duplicateRemoteIds, hasLength(1));
      expect(matched.single.duplicateMismatch, isFalse);
    }, skip: skip);
  });

  group('S5 確認7 — ページ順序', () {
    test('pageToken のループが実 Drive で回り、全件が揃う', () async {
      final transport = DriveTransport(client, generationId);
      final ids = [
        for (var n = 0; n < 5; n++) '10000000-0000-4000-8000-0000000000b$n',
      ];
      for (final eventId in ids) {
        await put(transport, eventId, envelopeText(eventId));
      }

      final events = await transport.list();
      final seen = {
        for (final event in events)
          if (event.eventId != null) event.eventId!,
      };
      // 前の試験が置いたものも同じ世代にいる。**この5件が全部あることを見る。**
      expect(seen.containsAll(ids), isTrue, reason: 'ページを跨いだ分を取りこぼしている');
    }, skip: skip);
  });

  group('S5 確認8 — 再送時の find', () {
    test('appProperties のクエリが1件だけを返す', () async {
      // 再送の行は put の前にここを通る。全件一覧から探すと、再送1件ごとにループが1周する。
      final transport = DriveTransport(client, generationId);
      const eventId = '10000000-0000-4000-8000-0000000000c1';
      final text = envelopeText(eventId, title: 'find-target');
      await put(transport, eventId, text);

      final found = await transport.find(eventId);
      expect(found?.text, text);
      expect(
        await transport.find('10000000-0000-4000-8000-0000000000ff'),
        isNull,
        reason: '無いものを見つけている',
      );
    }, skip: skip);
  });

  group('S5 確認5 — 認可喪失', () {
    test('壊れた access token は 401 を経て取り直しへ落ちる', () async {
      // **実物のトークンを壊さない。** 写しを壊して、そこだけを見る。
      final real = TokenStore(paths.tokenPath).load()!;
      final copyPath = '${work.path}${Platform.pathSeparator}broken.json';
      TokenStore(copyPath).save(
        Token(
          accessToken: 'broken-on-purpose',
          refreshToken: real.refreshToken,
          // 期限は未来のままにする。**refresh を挟ませず、Drive に 401 を返させる。**
          expiryUtc: '2099-01-01T00:00:00Z',
          scopes: real.scopes,
        ),
      );

      final probe = RestDriveClient(
        tokens: GoogleAccessTokenProvider(
          store: TokenStore(copyPath),
          oauth: oauth,
          now: nowUtc,
        ),
      );
      // 401 → 取り直し → 通る。**refresh token は生きているので回復する。**
      final page = await probe.listPage();
      expect(page.files, isNotNull);
      probe.close();
    }, skip: skip);

    test('refresh token まで壊れていれば認可の失敗になる', () async {
      // ここまで来たら再ログイン以外に回復手段は無い。
      final copyPath = '${work.path}${Platform.pathSeparator}dead.json';
      TokenStore(copyPath).save(
        const Token(
          accessToken: 'broken-on-purpose',
          refreshToken: 'also-broken',
          expiryUtc: '2000-01-01T00:00:00Z',
        ),
      );

      final probe = RestDriveClient(
        tokens: GoogleAccessTokenProvider(
          store: TokenStore(copyPath),
          oauth: oauth,
          now: nowUtc,
        ),
      );
      await expectLater(probe.listPage(), throwsA(isA<TransportAuthError>()));
      probe.close();
    }, skip: skip);
  });

  group('B2 — バックアップの保管先', () {
    test('resumable で載り、改名で公開され、取り出すと一致する', () async {
      final store = DriveBackupStore(client);

      // 刻みを跨ぐ大きさにする。**1回で終わると resumable の往復を通らない。**
      final payload = List<int>.generate(700 * 1024, (n) => n % 251);
      final source = '${work.path}${Platform.pathSeparator}source.blib';
      File(source).writeAsBytesSync(payload, flush: true);

      final remoteId = await store.putBaseline(1, generationId, source);
      created.add(remoteId);

      // 名前だけで有効世代が決まる。**中身は取らない。**
      final baselines = await store.listBaselines();
      final mine = baselines
          .where((ref) => ref.generationId == generationId)
          .toList();
      expect(mine, hasLength(1));
      expect(mine.single.seq, 1);
      expect(
        mine.single.sizeBytes,
        payload.length,
        reason: 'size を数として読み違えている',
      );

      final dest = '${work.path}${Platform.pathSeparator}fetched.blib';
      await store.getBaseline(mine.single, dest);
      expect(
        File(dest).readAsBytesSync(),
        payload,
        reason: 'チャンク download が欠けているか重複している',
      );
    }, skip: skip);

    test('封筒と .blib が同居しても混ざらない', () async {
      // 一覧はどちらも名前で絞る。同じ空間に置いても、互いのものを数えない。
      final transport = DriveTransport(client, generationId);
      final store = DriveBackupStore(client);

      final events = await transport.list();
      expect(
        events.every((event) => event.parsed),
        isTrue,
        reason: '.blib を封筒として読もうとしている',
      );

      final listing = await store.list();
      expect(
        listing.refs.every((ref) => ref.summary['backupId'] == ref.backupId),
        isTrue,
      );
    }, skip: skip);

    test('明示削除は恒久である', () async {
      final store = DriveBackupStore(client);
      final backupId =
          '${generationId.substring(0, 8)}-0002-4000-8000-000000000002';

      // 索引と名前が揃った `.blib` を1つ作る。manifest を持たせないと一覧に出ない。
      final source = '${work.path}${Platform.pathSeparator}deletable.blib';
      File(source).writeAsBytesSync(utf8.encode('not-a-real-zip'), flush: true);
      final remoteId = await store.put(backupId, source);

      // 名前と索引が一致するので一覧に出る（manifest は読めないので中身は空）。
      final before = await store.list();
      expect([for (final ref in before.refs) ref.backupId], contains(backupId));

      expect(await store.delete(backupId), 1);
      final after = await store.list();
      expect(
        [for (final ref in after.refs) ref.backupId],
        isNot(contains(backupId)),
        reason: 'ゴミ箱へ入っただけで消えていない',
      );
      created.remove(remoteId);
    }, skip: skip);
  });

  group('S5 確認9 — 一覧のコスト', () {
    test('件数と所要時間を控える', () async {
      // **判断材料を採るだけで、表明しない。** Drive Changes cursor を入れるかどうかは
      // 正しさを確認した後の話であり、この確認では入れない。
      final transport = DriveTransport(client, generationId);
      final watch = Stopwatch()..start();
      final events = await transport.list();
      watch.stop();
      print(
        '確認9 一覧のコスト: この世代の封筒 ${events.length} 件 / '
        '${watch.elapsedMilliseconds} ms',
      );
      expect(events, isNotEmpty);
    }, skip: skip);
  });
}
