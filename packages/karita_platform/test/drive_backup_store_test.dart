/// `appDataFolder` のバックアップ保管先。**ネットワークに触らない。**
///
/// 偽クライアントに対して、二段名・検算・一覧の除外規則・有効世代の決定・重複の削除を通す。
/// 検算の3つの枝（内容違い・大きさ不足・値が返らない）はここでしか作れない — 実 Drive は
/// 求めても壊れた応答を返してくれない。
///
/// `.blib` はここで最小の形に組む。SQLite も同期エンジンも通さないのは、保管先が見るのが
/// **manifest と名前とバイト列の大きさ**だけだからである。中身の正しさは復元側が見る。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

import 'fake_drive_client.dart';

const String b1 = 'cccccccc-0001-4000-8000-000000000001';
const String b2 = 'cccccccc-0002-4000-8000-000000000002';
const String g1 = '99999999-0000-4000-8000-000000000009';

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('karita-drive-store-'));
  tearDown(() => work.deleteSync(recursive: true));

  /// 最小の `.blib`。manifest と DB の2件を持つ zip である。
  String blib(String backupId, {String profile = 'windows-a', int filler = 64}) {
    final manifest = {
      'backup_id': backupId,
      'backup_version': 2,
      'schema_version': 9,
      'created_at_utc': '2026-08-04T09:00:00Z',
      'source_device_id': 'windows-00000000-0000-4000-8000-000000000001',
      'source_profile': profile,
      'source_platform': 'windows',
      'counts': {'books': 3, 'loans': 1},
    };
    final manifestBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
    final payload = List<int>.filled(filler, 0x41);
    final archive = Archive()
      ..addFile(ArchiveFile(manifestName, manifestBytes.length, manifestBytes))
      ..addFile(ArchiveFile(dbName, payload.length, payload));
    final path = '${work.path}${Platform.pathSeparator}$backupId.blib';
    File(path).writeAsBytesSync(ZipEncoder().encode(archive), flush: true);
    return path;
  }

  ({DriveBackupStore store, FakeDriveClient client}) open({
    bool corruptUpload = false,
    bool truncatedUpload = false,
    bool silentUpload = false,
  }) {
    final client = FakeDriveClient(
      corruptUpload: corruptUpload,
      truncatedUpload: truncatedUpload,
      silentUpload: silentUpload,
    );
    return (store: DriveBackupStore(client), client: client);
  }

  group('二段名', () {
    test('検算を通ってから backup- を名乗る', () async {
      final (:store, :client) = open();
      await store.put(b1, blib(b1));

      // **先に `incoming-` を名乗り、改名で公開する。** 最初から `backup-` で載せると、
      // 途中で落ちた実体が正しい名前のまま一覧に出て、利用者が選べてしまう。
      expect(client.files.values.single.names, [incomingName(b1), backupName(b1)]);

      final listing = await store.list();
      expect([for (final ref in listing.refs) ref.backupId], [b1]);
      expect(listing.refs.single.summary['sourceProfile'], 'windows-a');
      expect(listing.refs.single.summary['counts'], 'books=3 loans=1');
    });

    test('取り出したものが元の .blib と同じ', () async {
      final (:store, :client) = open();
      final source = blib(b1);
      await store.put(b1, source);

      final dest = '${work.path}${Platform.pathSeparator}fetched.blib';
      await store.get(b1, dest);
      expect(File(dest).readAsBytesSync(), File(source).readAsBytesSync());
      expect(readManifest(dest)['backup_id'], b1);
    });
  });

  group('検算', () {
    // 検算を通らなかったものに `backup-` を名乗らせない。これが二段名の理由である。最初から
    // `backup-` にすると、壊れた実体が正しい名前で一覧に出る。
    for (final flaw in const [
      // 内容が違う。md5 が捕まえる。
      'corruptUpload',
      // md5 は合っているのに大きさが足りない。**md5 だけでは捕まらない。**
      'truncatedUpload',
      // 大きさも md5 も返ってこない。**検算が走っていない。**
      'silentUpload',
    ]) {
      test('$flaw のときは公開しない', () async {
        // `silentUpload` が実 Drive の疎通で見つかった穴である。md5 だけを見ていたときは、
        // 保管先が md5 を返さなければ照合ごと飛んで公開が成功していた。「一致した」のか
        // 「返ってこなかった」のかを区別できないまま成功する形だった。大きさの照合を無条件の
        // ガードにして塞いだ。
        final (:store, :client) = open(
          corruptUpload: flaw == 'corruptUpload',
          truncatedUpload: flaw == 'truncatedUpload',
          silentUpload: flaw == 'silentUpload',
        );

        await expectLater(
            store.put(b1, blib(b1)),
            throwsA(isA<BackupError>()
                .having((e) => e.code, 'code', 'backup-store-upload')));
        // 載せたものは**公開の名前を一度も名乗らないまま**捨てる。
        expect(client.files, isEmpty);
        expect(client.deletedNames, [incomingName(b1)]);
        expect((await store.list()).refs, isEmpty);
      });
    }

    test('baseline も同じ検算を通る', () async {
      // 有効世代の決定に使われる分こちらの方が重い。途中で落ちた upload が `baseline-` を
      // 名乗ると、全端末が実体の無い世代を有効と判断する。
      final (:store, :client) = open(truncatedUpload: true);
      await expectLater(store.putBaseline(1, g1, blib(b1)), throwsA(isA<BackupError>()));
      expect(client.files, isEmpty);
      expect(client.deletedNames, [incomingBaselineName(1, g1)]);
      expect(await store.listBaselines(), isEmpty);
    });

    test('読めない .blib でも upload は止めない', () async {
      // 索引を作れないことは保管しない理由にならない。名前と `backupId` の一致は保つ。
      final (:store, :client) = open();
      final broken = '${work.path}${Platform.pathSeparator}broken.blib';
      File(broken).writeAsStringSync('not a zip');

      await store.put(b1, broken);
      expect([for (final file in client.files.values) file.name], [backupName(b1)]);
      final listing = await store.list();
      expect([for (final ref in listing.refs) ref.backupId], [b1]);
      // 索引は空でも、名前と `backupId` が一致しているので選べる。
      expect(listing.refs.single.summary['sourceProfile'], '');
    });
  });

  group('一覧', () {
    test('backup- 以外の同居ファイルは見ない', () async {
      // 封筒・baseline・途中 upload が同じ場所に同居する。
      final (:store, :client) = open();
      await store.put(b1, blib(b1));
      await client.create('event-$g1-$b1.json', {'eventId': b1}, '{}');
      await client.create(baselineName(1, g1), {'backupId': b2}, 'x');
      await client.create(incomingName(b2), {'backupId': b2}, 'x');

      final listing = await store.list();
      expect([for (final ref in listing.refs) ref.backupId], [b1]);
      expect(listing.skipped, 0);
    });

    test('索引を読めないものは選ばせないが数は残す', () async {
      // 黙って消すと、索引を書けていない不具合が「バックアップが1つも無い」という形でしか
      // 現れない。
      final (:store, :client) = open();
      await client.create(backupName(b1), const {}, 'x');

      final listing = await store.list();
      expect(listing.refs, isEmpty);
      expect(listing.skipped, 1);
    });

    test('名前と索引が食い違うものも選ばせない', () async {
      // 名前を信じると、削除が別物に当たる。
      final (:store, :client) = open();
      await client.create(backupName(b1), {'backupId': b2}, 'x');

      final listing = await store.list();
      expect(listing.refs, isEmpty);
      expect(listing.skipped, 1);
    });

    test('ページに割れても全件を見る', () async {
      final (:store, :client) = open();
      expect(client.pageSize, 3);
      for (var n = 0; n < 7; n++) {
        final id = 'cccccccc-000$n-4000-8000-000000000001';
        await store.put(id, blib(id));
      }
      expect((await store.list()).refs, hasLength(7));
    });
  });

  group('世代の起点', () {
    test('名前だけで集め、seq の最大が有効世代になる', () async {
      final (:store, :client) = open();
      const g2 = '77777777-0000-4000-8000-000000000007';
      await store.putBaseline(1, g1, blib(b1));
      await store.putBaseline(2, g2, blib(b2));
      await client.create('event-$g1-$b1.json', {'eventId': b1}, '{}');
      // baseline も `incoming-` を通ってから公開の名前になる。
      expect(client.files.values.first.names,
          [incomingBaselineName(1, g1), baselineName(1, g1)]);

      final baselines = await store.listBaselines();
      expect([for (final ref in baselines) ref.seq], [1, 2]);
      expect(activeBaseline(baselines)?.generationId, g2);
      // 中身は取らない。世代を決めるために毎回 .blib を開くと、通常同期のたびに全件を取る。
      expect(client.fetched, isEmpty);
      // **名前で絞って問い合わせる**（2026-10-08）。全ファイルを読むと封筒の数だけ延びる。
      expect(client.queries.last, "name contains 'baseline-'");
    });

    test('索引の無い起点でも取り出せる', () async {
      // 有効世代は名前だけで決まっている。ここで索引を要求すると、索引を書けていない起点が
      // 「有効世代なのに復元できない」状態になる。
      final (:store, :client) = open();
      await client.create(baselineName(3, g1), const {}, 'baseline-body');

      final ref = activeBaseline(await store.listBaselines())!;
      final dest = '${work.path}${Platform.pathSeparator}baseline.blib';
      await store.getBaseline(ref, dest);
      expect(File(dest).readAsStringSync(), 'baseline-body');
    });
  });

  group('削除', () {
    test('名指しされた backupId の実体をすべて消す', () async {
      // 重複があるとき片方を残すと、利用者から見れば「消したのに消えていない」になる。
      final (:store, :client) = open();
      await store.put(b1, blib(b1));
      await store.put(b1, blib(b1));
      expect(client.files, hasLength(2));

      expect(await store.delete(b1), 2);
      expect(client.files, isEmpty);
    });

    test('知らない backupId は失敗する', () async {
      final (:store, client: _) = open();
      await expectLater(store.delete(b1), throwsA(isA<BackupNotFound>()));
    });
  });

  test('保管先の種別は転送先と同じ drive である', () async {
    // 保管先は転送先と同じ場所にする。別に選べるようにすると、製品に存在しない組み合わせを
    // 作れてしまい、世代の判定がその組み合わせまで面倒を見ることになる。
    final (:store, client: _) = open();
    expect(store.kind, transportDrive);
  });
}
