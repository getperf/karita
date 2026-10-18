/// 完全バックアップの書き出しと復元。
///
/// 通常同期とは別の経路である。ここが見るのは次の3つで、どれも「壊れたときに静かである」ものを
/// 明示的な失敗へ変えられているかを確かめる。
///
/// - 復元は現 DB を**最後の1手**でだけ置き換える。途中で落ちたら現 DB が残る。
/// - 作成元の `device_id` を復元しない。二台が同じ端末 ID を使うと LWW の全順序が壊れる。
/// - 同期の作業状態はバックアップへ入らない。入れると復元先が他端末の送信待ちを引き継ぐ。
///
/// 移送元: book-sync-model の `tests/test_backup.py`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:conformance/src/harness.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String t0 = '2026-08-04T09:00:00Z';
const String t1 = '2026-08-05T09:00:00Z';
const String t2 = '2026-08-06T09:00:00Z';

void main() {
  late Harness harness;
  late Device windows;

  /// windows-a に業務データを1件入れる。**seed と同じ経路**（ローカル発行）を通す。
  void seedBook(Device device, {required String title, required String now}) {
    final codec = EnvelopeCodec(harness.contracts);
    device.engine.emitLocal([
      codec.build(
        eventId: harness.uuid(),
        deviceId: device.deviceId,
        createdAtUtc: now,
        entityType: 'book',
        entityId: 'aaaaaaaa-0101-4000-8000-000000000001',
        operation: 'upsert',
        baseVersion: 0,
        resultVersion: 1,
        payload: {'title': title},
      ),
    ]);
  }

  int rows(Device device, String table) =>
      device.db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;

  setUp(() {
    harness = Harness.create(Contracts.load(), prefix: 'karita-backup-');
    windows = harness.device('windows-a');
    seedBook(windows, title: 'リファクタリング', now: t0);
  });
  tearDown(() => harness.dispose());

  test('.blib は manifest と DB の2つだけを持つ zip である', () async {
    final out = '${harness.root.path}${Platform.pathSeparator}out.blib';
    final result = await windows.engine.exportBackup(now: t1, outPath: out);

    final archive = ZipDecoder().decodeBytes(File(out).readAsBytesSync());
    expect(archive.files.map((f) => f.name).toList()..sort(),
        equals([dbName, manifestName]));

    final manifest = jsonDecode(utf8.decode(
        archive.files.firstWhere((f) => f.name == manifestName).content
            as List<int>)) as Map<String, Object?>;
    expect(manifest['backup_version'], equals(backupVersion));
    expect(manifest['backup_id'], equals(result.backupId));
    expect(manifest['schema_version'], equals(latestVersion()));
    expect(manifest['source_profile'], equals('windows-a'));
    expect(manifest['source_device_id'], equals(windows.deviceId));
    expect((manifest['counts'] as Map)['books'], equals(1));
    // 保管先へは入れていないので、最終バックアップ日時は進めない。
    expect(getState(windows.db, stateLastBackupAt), isNull);
  });

  test('同期の作業状態と端末固有の識別を持ち込まない', () async {
    // 発行済みの outbox と applied がある状態で書き出す。
    expect(rows(windows, 'outbox_events'), equals(1));
    expect(rows(windows, 'applied_events'), equals(1));

    final out = '${harness.root.path}${Platform.pathSeparator}stripped.blib';
    await windows.engine.exportBackup(now: t1, outPath: out);

    final work = Directory.systemTemp.createTempSync('blib-check-');
    try {
      final archive = ZipDecoder().decodeBytes(File(out).readAsBytesSync());
      final payload = archive.files.firstWhere((f) => f.name == dbName).content
          as List<int>;
      final path = '${work.path}${Platform.pathSeparator}$dbName';
      File(path).writeAsBytesSync(payload);
      final copy = SqliteDb.open(path);
      try {
        for (final table in excludedTables) {
          if (!tableExists(copy, table)) continue;
          expect(copy.select('SELECT COUNT(*) AS n FROM $table').first['n'],
              equals(0),
              reason: '$table がバックアップに残っている');
        }
        for (final key in deviceStateKeys) {
          expect(getState(copy, key), isNull, reason: '$key がバックアップに残っている');
        }
        // 業務データは残る。落とすのは作業状態と素性だけである。
        expect(copy.select('SELECT COUNT(*) AS n FROM books').first['n'], equals(1));
      } finally {
        copy.close();
      }
    } finally {
      work.deleteSync(recursive: true);
    }
  });

  test('復元しても作成元の device_id を名乗らない', () async {
    final out = '${harness.root.path}${Platform.pathSeparator}move.blib';
    await windows.engine.exportBackup(now: t1, outPath: out);

    final android = harness.device('android-b');
    expect(rows(android, 'books'), equals(0));
    final outcome = await android.engine.restoreFromBackup(now: t2, path: out);

    expect(rows(android, 'books'), equals(1));
    expect(outcome.counts['books'], equals(1));
    // **二台が同じ device_id を使うと LWW の全順序が壊れる。**
    expect(getState(android.db, stateDeviceId), equals(android.deviceId));
    expect(getState(android.db, stateProfileName), equals('android-b'));
    // 作業状態は引き継がない。
    expect(rows(android, 'outbox_events'), equals(0));
  });

  test('復元は最終復元とその対象を残し、次のバックアップへは持ち込まない', () async {
    final out = '${harness.root.path}${Platform.pathSeparator}restore.blib';
    await windows.engine.exportBackup(now: t1, outPath: out);

    final android = harness.device('android-b');
    await android.engine.restoreFromBackup(now: t2, path: out);

    expect(getState(android.db, stateLastRestoreAt), equals(t2));
    // **対象は作成元の時刻と素性である。** backup_id では後から日時へ戻せない。
    expect(getState(android.db, stateLastRestoreCreatedAt), equals(t1));
    expect(getState(android.db, stateLastRestorePlatform), equals('windows'));

    // 復元した端末のバックアップを別の端末へ戻しても、作成元の「最終復元」は名乗らない。
    final again = '${harness.root.path}${Platform.pathSeparator}again.blib';
    await android.engine.exportBackup(now: t2, outPath: again);
    final third = harness.device('windows-c');
    await third.engine.restoreFromBackup(now: t2, path: again);
    expect(getState(third.db, stateLastRestorePlatform), equals('android'));
  });

  test('保管先へ入れたときだけ最終バックアップ日時が進む', () async {
    final result = await windows.engine.exportBackup(now: t1);
    expect(result.storedIn, equals(transportDir));
    expect(result.location, equals(backupName(result.backupId)));
    expect(getState(windows.db, stateLastBackupAt), equals(t1));
    // **`incoming-` は残さない。** 検証を通るまで `backup-` を名乗らせない二段名である。
    expect(harness.appDataNames().where((n) => n.startsWith(incomingPrefix)), isEmpty);
    expect(harness.appDataNames(), contains(backupName(result.backupId)));
  });

  test('保管先の一覧と削除は backup_id で引く', () async {
    final first = await windows.engine.exportBackup(now: t1);
    final second = await windows.engine.exportBackup(now: t2);

    final listing = await windows.engine.listBackups();
    expect(listing.refs.map((r) => r.backupId).toList(),
        equals([first.backupId, second.backupId]),
        reason: '(createdAtUtc, backupId) 昇順');
    expect(listing.skipped, equals(0));

    expect(await windows.engine.deleteBackup(first.backupId), equals(1));
    expect((await windows.engine.listBackups()).refs.map((r) => r.backupId).toList(),
        equals([second.backupId]));
  });

  test('読めない .blib は選べる一覧から外すが、数は残す', () async {
    final good = await windows.engine.exportBackup(now: t1);
    // 名前だけ正しく、中身が壊れているもの。
    final broken = '11111111-0000-4000-8000-000000000009';
    File('${harness.appData.path}${Platform.pathSeparator}${backupName(broken)}')
        .writeAsStringSync('not a zip');

    final listing = await windows.engine.listBackups();
    expect(listing.refs.map((r) => r.backupId).toList(), equals([good.backupId]));
    // 黙って消すと、索引を書けていない不具合が「1つも無い」という形でしか現れない。
    expect(listing.skipped, equals(1));
  });

  test('壊れたバックアップは現 DB を置き換えない', () async {
    final broken = '${harness.root.path}${Platform.pathSeparator}broken.blib';
    File(broken).writeAsStringSync('not a zip');

    await expectLater(windows.engine.restoreFromBackup(now: t2, path: broken),
        throwsA(isA<BackupError>()));
    // 置換だけが不可逆な一歩であり、それを最後の1手にまとめている。
    expect(rows(windows, 'books'), equals(1));
    expect(rows(windows, 'outbox_events'), equals(1));
  });


  test('内容 hash が合わなければ復元しない', () async {
    final out = '${harness.root.path}${Platform.pathSeparator}tampered.blib';
    await windows.engine.exportBackup(now: t1, outPath: out);

    // manifest はそのままに、中の DB だけ差し替える。
    final archive = ZipDecoder().decodeBytes(File(out).readAsBytesSync());
    final manifest = archive.files
        .firstWhere((f) => f.name == manifestName)
        .content as List<int>;
    final fake = utf8.encode('tampered');
    final rebuilt = Archive()
      ..addFile(ArchiveFile(manifestName, manifest.length, manifest))
      ..addFile(ArchiveFile(dbName, fake.length, fake));
    File(out).writeAsBytesSync(ZipEncoder().encode(rebuilt));

    await expectLater(windows.engine.restoreFromBackup(now: t2, path: out),
        throwsA(predicate((e) => e is BackupError && e.code == 'backup-hash')));
  });

  test('未対応の形式はアプリの更新を求める', () async {
    final out = '${harness.root.path}${Platform.pathSeparator}future.blib';
    await windows.engine.exportBackup(now: t1, outPath: out);

    final archive = ZipDecoder().decodeBytes(File(out).readAsBytesSync());
    final manifest = jsonDecode(utf8.decode(archive.files
        .firstWhere((f) => f.name == manifestName)
        .content as List<int>)) as Map<String, Object?>;
    final payload =
        archive.files.firstWhere((f) => f.name == dbName).content as List<int>;

    void write(Map<String, Object?> changed) {
      final text = utf8.encode(jsonEncode(changed));
      final rebuilt = Archive()
        ..addFile(ArchiveFile(manifestName, text.length, text))
        ..addFile(ArchiveFile(dbName, payload.length, payload));
      File(out).writeAsBytesSync(ZipEncoder().encode(rebuilt));
    }

    write({...manifest, 'backup_version': backupVersion + 1});
    await expectLater(windows.engine.restoreFromBackup(now: t2, path: out),
        throwsA(predicate((e) => e is BackupError && e.code == 'backup-version')));

    // 新しい schema のバックアップを古い端末が読もうとしている。migration は前へしか進めない。
    write({...manifest, 'schema_version': latestVersion() + 1});
    await expectLater(windows.engine.restoreFromBackup(now: t2, path: out),
        throwsA(predicate((e) => e is BackupError && e.code == 'backup-schema')));

    // 版2で必須にした backup_id。名前だけが正しく中身に id が無いものを明示的に弾く。
    write(Map<String, Object?>.from(manifest)..remove('backup_id'));
    await expectLater(windows.engine.restoreFromBackup(now: t2, path: out),
        throwsA(predicate((e) => e is BackupError && e.code == 'backup-manifest')));
  });

  test('無いバックアップは明示的に失敗する', () async {
    await expectLater(
        windows.engine.restoreFromBackup(
            now: t2,
            path: '${harness.root.path}${Platform.pathSeparator}nope.blib'),
        throwsA(predicate((e) => e is BackupError && e.code == 'backup-missing')));
    await expectLater(
        windows.engine.restoreFromBackup(
            now: t2, backupId: '99999999-0000-4000-8000-000000000009'),
        throwsA(isA<BackupNotFound>()));
  });

  test('復元元は PATH と backupId のどちらか一つである', () async {
    await expectLater(windows.engine.restoreFromBackup(now: t2),
        throwsA(isA<SyncDataError>()));
    expect(
        () => windows.engine
            .restoreFromBackup(now: t2, path: 'x.blib', backupId: 'y'),
        throwsA(isA<SyncDataError>()));
  });

  test('必要な表が欠けていれば復元しない', () async {
    final out = '${harness.root.path}${Platform.pathSeparator}notables.blib';
    await windows.engine.exportBackup(now: t1, outPath: out);

    // 台帳は「適用済み」のまま表だけを落とす。migration は前へしか進まないので作り直されず、
    // **「読めたが表が足りない」状態**になる。ここで止めなければ静かに壊れた DB が正本になる。
    final work = Directory.systemTemp.createTempSync('blib-drop-');
    try {
      final archive = ZipDecoder().decodeBytes(File(out).readAsBytesSync());
      final manifest = jsonDecode(utf8.decode(archive.files
          .firstWhere((f) => f.name == manifestName)
          .content as List<int>)) as Map<String, Object?>;
      final path = '${work.path}${Platform.pathSeparator}$dbName';
      File(path).writeAsBytesSync(archive.files
          .firstWhere((f) => f.name == dbName)
          .content as List<int>);

      final db = SqliteDb.open(path);
      try {
        db.execute('DROP TABLE books');
      } finally {
        db.close();
      }
      for (final suffix in ['-wal', '-shm']) {
        final residue = File('$path$suffix');
        if (residue.existsSync()) residue.deleteSync();
      }

      final payload = File(path).readAsBytesSync();
      final fixed = {...manifest, 'content_hash': sha256.convert(payload).toString()};
      final text = utf8.encode(jsonEncode(fixed));
      final rebuilt = Archive()
        ..addFile(ArchiveFile(manifestName, text.length, text))
        ..addFile(ArchiveFile(dbName, payload.length, payload));
      File(out).writeAsBytesSync(ZipEncoder().encode(rebuilt));
    } finally {
      work.deleteSync(recursive: true);
    }

    await expectLater(windows.engine.restoreFromBackup(now: t2, path: out),
        throwsA(predicate((e) => e is BackupError && e.code == 'backup-tables')));
    expect(rows(windows, 'books'), equals(1), reason: '現 DB は元のまま残る');
  });
}
