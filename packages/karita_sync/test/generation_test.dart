/// 名前の規則と世代の状態機械。**保管先の実装を要らない部分だけをここで測る。**
///
/// `.blib` の実物を通す試験（export / restore / 一覧の除外）は、`dir` の実装が置いてある
/// `tools/conformance` 側にある。
library;

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String _genA = '11111111-0000-4000-8000-000000000001';
const String _genB = '22222222-0000-4000-8000-000000000002';
const String _backupId = '33333333-0000-4000-8000-000000000003';

/// baseline の列だけを持つ保管先。世代の判定に要るのは名前だけである。
class _FakeStore implements BackupStorePort {
  List<BaselineRef> baselines;
  bool unreadable;

  _FakeStore({this.baselines = const [], this.unreadable = false});

  @override
  String get kind => 'fake';
  @override
  Future<List<BaselineRef>> listBaselines() async {
    if (unreadable) {
      // 認可切れやネットワーク断。**「世代が変わった」ではない。**
      throw const SyncDataError('保管先を読めません。', code: 'transport-auth');
    }
    return baselines;
  }

  @override
  Future<String> put(String backupId, String path) async => backupId;
  @override
  Future<BackupListing> list() async => const BackupListing();
  @override
  Future<String> get(String backupId, String destPath) async => destPath;
  @override
  Future<int> delete(String backupId) async => 0;
  @override
  Future<String> putBaseline(int seq, String generationId, String path) async =>
      generationId;
  @override
  Future<String> getBaseline(BaselineRef ref, String destPath) async => destPath;
}

BaselineRef _baseline(int seq, String generationId) => BaselineRef(
      seq: seq,
      generationId: generationId,
      remoteId: baselineName(seq, generationId),
    );

void main() {
  group('名前の規則', () {
    test('世代を足しても封筒の前置は変わらない', () {
      // `generation-...` のような別前置にすると、新世代のイベントが一覧の名前判定に1件も
      // 当たらず、「同期済み・0件」という静かな成功になる。
      expect(eventName(_genA, _backupId).startsWith(filenamePrefix), isTrue);
      // `.blib` の3種は封筒の名前判定に当たらない。追加の除外規則が要らないことを縛る。
      for (final name in [
        backupName(_backupId),
        incomingName(_backupId),
        baselineName(1, _genA),
      ]) {
        expect(isEventName(name, _genA), isFalse, reason: '$name が封筒として拾われている');
      }
    });

    test('有効世代の封筒だけが当たる', () {
      expect(isEventName(eventName(_genA, _backupId), _genA), isTrue);
      expect(isEventName(eventName(_genB, _backupId), _genA), isFalse);
    });

    test('baseline の名前は往復する', () {
      final parsed = parseBaselineName(baselineName(7, _genA))!;
      expect(parsed.seq, equals(7));
      expect(parsed.generationId, equals(_genA));
      expect(parseBaselineName(backupName(_backupId)), isNull);
      // **seq の桁数は固定で見る。** 可変長を許すと、桁の違う2つが文字列順と数値順で食い違い、
      // 端末ごとに違う世代を有効と判断する経路ができる。
      expect(parseBaselineName('baseline-7-$_genA.blib'), isNull);
      expect(parseBaselineName('baseline-0000-$_genA.blib'), isNull);
      expect(parseBaselineName('baseline-0001-not-a-uuid.blib'), isNull);
      expect(() => baselineName(0, _genA), throwsA(isA<BackupError>()));
      expect(() => baselineName(maxSeq + 1, _genA), throwsA(isA<BackupError>()));
    });

    test('backup の名前は uuid だけを受ける', () {
      expect(parseBackupName(backupName(_backupId)), equals(_backupId));
      expect(parseBackupName('backup-windows-a-2026.blib'), isNull);
      expect(parseBackupName(incomingName(_backupId)), isNull,
          reason: '途中 upload を選べる一覧に出さない');
    });

    test('最大 seq が有効世代で、同点は generationId で決まる', () {
      // **決定規則を持たない状態を作らない。** どちらを採るか決めないと、端末ごとに違う世代を
      // 選び、両方が「相手が旧世代だ」と結論する。
      expect(activeBaseline([]), isNull);
      expect(activeBaseline([_baseline(1, _genB), _baseline(2, _genA)])!.seq, equals(2));
      expect(
        activeBaseline([_baseline(2, _genB), _baseline(2, _genA)])!.generationId,
        equals(_genA),
      );
    });
  });

  group('世代の状態機械', () {
    late DbSession session;
    Db db() => session.db;

    setUp(() {
      session = DbSession.memory();
      migrate(session.db, now: '2026-08-04T09:00:00Z');
    });
    tearDown(() => session.close());

    Future<GenerationResolution> resolve(_FakeStore store) =>
        resolveGeneration(store, localGeneration(db()), newGenerationId: _genB);

    test('端末も保管先も世代を持たなければ bootstrap', () async {
      final resolution = await resolve(_FakeStore());
      expect(resolution.state, equals(generationBootstrap));
      expect(resolution.seq, equals(firstSeq));
      expect(resolution.needsBaseline, isTrue);
    });

    test('世代を持たない端末は止まらずに参加する（adopt）', () async {
      // **まだ一度も同期していない端末**が有効世代に乗るのは切替ではなく参加である。止めると、
      // 二端末目を用意する経路がすべて「まず復元しろ」になる。
      final resolution = await resolve(_FakeStore(baselines: [_baseline(3, _genA)]));
      expect(resolution.state, equals(generationAdopt));
      expect(resolution.generationId, equals(_genA));
      expect(resolution.seq, equals(3));
      expect(resolution.needsBaseline, isFalse);
    });

    test('同じ世代なら current。seq は保管先を正とする', () async {
      setLocalGeneration(db(), _genA, 2);
      final resolution = await resolve(_FakeStore(baselines: [_baseline(3, _genA)]));
      expect(resolution.state, equals(generationCurrent));
      expect(resolution.seq, equals(3));
    });

    test('違う世代なら止める（changed）', () async {
      setLocalGeneration(db(), _genA, 1);
      await expectLater(
        resolve(_FakeStore(baselines: [_baseline(2, _genB)])),
        throwsA(isA<GenerationChangedError>()),
      );
    });

    test('保管先に起点が無くなっても、世代を持つ端末は止めない', () async {
      // 転送先を空にした直後がこれである。ここで止めると、初期化のたびに全端末が復元を要求される。
      setLocalGeneration(db(), _genA, 2);
      final resolution = await resolve(_FakeStore());
      expect(resolution.state, equals(generationCurrent));
      expect(resolution.generationId, equals(_genA));
      expect(resolution.seq, equals(2));
    });

    test('保管先を読めないことは「世代が変わった」ではない', () async {
      // ここで落とすと、push が転送を組む前に落ちて outbox の行が blocked_auth にならない。
      setLocalGeneration(db(), _genA, 2);
      final resolution = await resolve(_FakeStore(unreadable: true));
      expect(resolution.state, equals(generationUnknown));
      expect(resolution.needsBaseline, isFalse,
          reason: '確かめられないまま起点を置くと、既にある世代を知らずに 0001 を作り直す');
    });

    test('片方だけ書かれた世代は「持っていない」とする', () {
      // seq を 0 で補うと、有効世代より小さい seq を持つ端末が生まれ、changed の判定が
      // 「常に変わった」に倒れる。
      transaction(db(), () => setState(db(), stateGenerationId, _genA));
      expect(localGeneration(db()), isNull);
      transaction(db(), () => setState(db(), stateGenerationSeq, '0'));
      expect(localGeneration(db()), isNull);
    });

    test('次の seq は現世代を壊さずに1つ進める', () async {
      expect(await nextGenerationSeq(_FakeStore()), equals(firstSeq));
      expect(await nextGenerationSeq(_FakeStore(baselines: [_baseline(4, _genA)])),
          equals(5));
    });
  });
}
