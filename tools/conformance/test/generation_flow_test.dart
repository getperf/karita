/// 同期世代の二端末ふるまい。
///
/// **復元は宣言と参加に分かれる。** バックアップを指す復元は世代を +1 する宣言、有効世代の起点へ
/// 戻るのは参加で**世代を進めない**。分けないと、世代変更で止められた端末が復元するたびに相手が
/// 止まり、**同じ世代へ戻る経路が無くなる。**
///
/// 移送元: book-sync-model の `tests/test_generation.py`。
library;

import 'dart:io';

import 'package:conformance/src/harness.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String t0 = '2026-08-04T09:00:00Z';
const String t1 = '2026-08-05T09:00:00Z';
const String t2 = '2026-08-06T09:00:00Z';
const String t3 = '2026-08-07T09:00:00Z';
const String t4 = '2026-08-08T09:00:00Z';

const String bookId = 'aaaaaaaa-0101-4000-8000-000000000001';

void main() {
  late Harness harness;
  late Device windows;
  late Device android;

  void seedBook(Device device,
      {required String title, required int base, required String now}) {
    final codec = EnvelopeCodec(harness.contracts);
    device.engine.emitLocal([
      codec.build(
        eventId: harness.uuid(),
        deviceId: device.deviceId,
        createdAtUtc: now,
        entityType: 'book',
        entityId: bookId,
        operation: 'upsert',
        baseVersion: base,
        resultVersion: base + 1,
        payload: {'title': title},
      ),
    ]);
  }

  String? titleOf(Device device) {
    final rows =
        device.db.select('SELECT title FROM books WHERE id = ?', [bookId]);
    return rows.isEmpty ? null : rows.first['title'] as String?;
  }

  ({String id, int seq})? generationOf(Device device) =>
      localGeneration(device.db);

  setUp(() {
    harness = Harness.create(Contracts.load(), prefix: 'karita-gen-');
    windows = harness.device('windows-a');
    android = harness.device('android-b');
  });
  tearDown(() => harness.dispose());

  test('最初の同期が起点 0001 を置き、二台目はそこへ参加する', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    final first = await windows.engine.run(modeRun, now: t0);

    expect(first.generation.state, equals(generationBootstrap));
    expect(first.generation.seq, equals(firstSeq));
    expect((await harness.store.listBaselines()).length, equals(1));
    expect(generationOf(windows)!.seq, equals(firstSeq));

    // **まだ一度も同期していない端末**が有効世代に乗るのは切替ではなく参加である。
    final second = await android.engine.run(modeRun, now: t0);
    expect(second.generation.state, equals(generationAdopt));
    expect(second.generation.generationId, equals(first.generation.generationId));
    expect(titleOf(android), equals('リファクタリング'));
    expect((await harness.store.listBaselines()).length, equals(1), reason: '参加は世代を進めない');
  });

  test('起点はバックアップ一覧に出ない', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    await windows.engine.run(modeRun, now: t0);

    // 名前が `backup-` ではないため、利用者が「作った覚えのないバックアップ」を見ることはない。
    expect((await windows.engine.listBackups()).refs, isEmpty);
    expect((await windows.engine.listBackups()).skipped, equals(0));
    expect(
        harness.appDataNames().where((n) => n.startsWith(baselinePrefix)).length,
        equals(1));
  });

  test('バックアップを指す復元は宣言であり、世代を1つ進める', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    await windows.engine.run(modeRun, now: t0);
    await android.engine.run(modeRun, now: t0);

    final saved = await windows.engine.exportBackup(now: t1);
    seedBook(windows, title: '改訂版', base: 1, now: t1);
    await windows.engine.run(modeRun, now: t1);

    final outcome =
        await windows.engine.restoreFromBackup(now: t2, backupId: saved.backupId);

    expect(outcome.declared, isTrue);
    expect(outcome.seq, equals(firstSeq + 1));
    expect(activeBaseline(await harness.store.listBaselines())!.seq, equals(2));
    expect(titleOf(windows), equals('リファクタリング'), reason: '巻き戻っていない');
    expect(generationOf(windows), equals((id: outcome.generationId, seq: 2)));
  });

  test('旧世代のイベントは復元後に再生されない', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    await windows.engine.run(modeRun, now: t0);
    await android.engine.run(modeRun, now: t0);

    final saved = await windows.engine.exportBackup(now: t1);
    seedBook(windows, title: '改訂版', base: 1, now: t1);
    await windows.engine.run(modeRun, now: t1);
    expect(titleOf(windows), equals('改訂版'));

    await windows.engine.restoreFromBackup(now: t2, backupId: saved.backupId);
    // 新世代で同期しても、旧世代の封筒は名前で落ちるので拾わない。
    await windows.engine.run(modeRun, now: t3);
    expect(titleOf(windows), equals('リファクタリング'),
        reason: '巻き戻したはずの更新が戻っている');
    // **旧世代のイベントは物理削除しない。** 新世代から見えなくするだけである。
    expect(harness.appDataNames().where((n) => n.startsWith(filenamePrefix)),
        isNotEmpty);
  });

  test('もう一方の端末は世代変更を検出して通常同期を止める', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    await windows.engine.run(modeRun, now: t0);
    await android.engine.run(modeRun, now: t0);

    final saved = await windows.engine.exportBackup(now: t1);
    await windows.engine.restoreFromBackup(now: t2, backupId: saved.backupId);

    await expectLater(android.engine.run(modeRun, now: t3),
        throwsA(isA<GenerationChangedError>()));
  });

  test('止められた端末は起点へ戻って同じ世代へ乗る（参加、世代は進まない）', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    await windows.engine.run(modeRun, now: t0);
    await android.engine.run(modeRun, now: t0);

    final saved = await windows.engine.exportBackup(now: t1);
    final declared =
        await windows.engine.restoreFromBackup(now: t2, backupId: saved.backupId);
    await expectLater(android.engine.run(modeRun, now: t3),
        throwsA(isA<GenerationChangedError>()));

    // **参加は世代を進めない。** 進めると二端末が交互に止まり続ける。
    final joined = await android.engine.restoreFromBaseline(now: t3);
    expect(joined.declared, isFalse);
    expect(joined.seq, equals(declared.seq));
    expect(joined.generationId, equals(declared.generationId));
    expect((await harness.store.listBaselines()).length, equals(2), reason: '起点は増えない');

    final resumed = await android.engine.run(modeRun, now: t4);
    expect(resumed.generation.state, equals(generationCurrent));
    expect(generationOf(android), equals(generationOf(windows)));
  });

  test('復元の後、両端末が同じ内容へ収束する', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    await windows.engine.run(modeRun, now: t0);
    await android.engine.run(modeRun, now: t0);

    final saved = await windows.engine.exportBackup(now: t1);
    seedBook(windows, title: '改訂版', base: 1, now: t1);
    await windows.engine.run(modeRun, now: t1);
    await android.engine.run(modeRun, now: t1);
    expect(titleOf(android), equals('改訂版'));

    await windows.engine.restoreFromBackup(now: t2, backupId: saved.backupId);
    await android.engine.restoreFromBaseline(now: t3);

    await windows.engine.run(modeRun, now: t4);
    await android.engine.run(modeRun, now: t4);

    expect(titleOf(windows), equals('リファクタリング'));
    expect(titleOf(android), equals('リファクタリング'));
    expect(generationOf(windows), equals(generationOf(android)));
  });

  test('起点が無ければ参加はできない', () async {
    await expectLater(windows.engine.restoreFromBaseline(now: t1),
        throwsA(predicate(
            (e) => e is SyncDataError && e.code == 'generation-no-baseline')));
  });

  test('オフラインだった端末の更新は新世代へ漏れない', () async {
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    await windows.engine.run(modeRun, now: t0);
    await android.engine.run(modeRun, now: t0);

    final saved = await windows.engine.exportBackup(now: t1);
    // android はオフラインのまま更新を積む（送信していない）。
    seedBook(android, title: 'オフラインの更新', base: 1, now: t1);

    await windows.engine.restoreFromBackup(now: t2, backupId: saved.backupId);
    // 送ろうとした時点で世代変更に当たり、**新世代へは1件も書けない。**
    await expectLater(android.engine.run(modeRun, now: t3),
        throwsA(isA<GenerationChangedError>()));

    await windows.engine.run(modeRun, now: t3);
    expect(titleOf(windows), equals('リファクタリング'),
        reason: 'オフラインの更新が新世代へ漏れている');
  });

  test('読めないバックアップは起点を1つも公開しない', () async {
    // **順序は「検証 → 起点を公開 → 置換」である。** 逆にすると、読めないバックアップを指す
    // 起点が有効世代になり、現 DB が無事でも他の全端末がその壊れた起点からの完全復元を
    // 求められる。
    seedBook(windows, title: 'リファクタリング', base: 0, now: t0);
    await windows.engine.run(modeRun, now: t0);
    final before = await harness.store.listBaselines();
    expect(before.length, equals(1));

    final broken = '${harness.root.path}${Platform.pathSeparator}broken.blib';
    File(broken).writeAsStringSync('not a zip');
    await expectLater(windows.engine.restoreFromBackup(now: t1, path: broken),
        throwsA(isA<BackupError>()));

    final after = await harness.store.listBaselines();
    expect(after.length, equals(1), reason: '壊れたバックアップを指す起点が公開されている');
    expect(activeBaseline(after)!.generationId,
        equals(activeBaseline(before)!.generationId));
    // 現 DB も世代も動いていない。
    expect(titleOf(windows), equals('リファクタリング'));
    expect(generationOf(windows)!.seq, equals(firstSeq));
  });
}
