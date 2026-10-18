/// `*.expect.json` の `script` を、**実物の ② に対して**駆動する。
///
/// **インメモリの模擬ではない。** SQLite と転送を通る。`script` の各動作は `SyncEngine` の
/// 公開 API へ一対一で写る — `seed` はローカル発行、`apply` は転送先へ封筒を置く操作、
/// `push` / `pull` / `sync` は `run` の3モード、`config` は自動解決の切替、`resolve` は競合の
/// 手動解決である。**テスト専用の裏口を実装に作らない** — ここが使うのは製品が使うのと
/// 同じ経路である。
///
/// 正本にも同じ fixture を読む横断ランナーがあり、そちらは同等の CLI 呼び出しへ写している。
/// **測るものは同じである** — 同じ fixture を読み、同じ DB 状態を突き合わせる。
///
/// 転送とプロファイルの組み立ては呼び出し側が行う（`karita_sync` は `dir` の実装を持たない）。
library;

import 'package:karita_contract/karita_contract.dart';

import 'engine.dart';
import 'fixtures.dart';
import 'transport.dart';

/// `apply` に `now` が書かれていないときに使う時刻。
///
/// `expect.json` の `apply` は `now` を持たない。この時刻が効くのは、まだ世代が無いときに
/// 置かれる起点の manifest だけであり、測る対象ではない。
/// **実時刻にしない** — ゴールデンが日々変わる形を持ち込まない。
const String driverDefaultNow = '2026-08-04T09:00:00Z';

/// 1プロファイル。DB・転送・device_id・設定を束ねる。
class DriverProfile {
  final String name;
  final SyncEngine engine;

  /// 転送先の生の中身。**組み立て側が渡す。**
  ///
  /// `remote` の表明（転送先のファイル数と相異なる `eventId` 数）は port を通しては測れない —
  /// [TransportPort.list] は `eventId` で畳んだ後を返すので、**畳む前の件数が消えている。**
  /// 「重複リモートイベントを作らない」（受入ケース08）は DB にも現れないので、転送先そのものを
  /// 見るしかない。
  ///
  /// 渡されなければ `remote` を持つケースは明示的に落ちる。**黙って素通りさせない。**
  final Future<List<String>> Function()? remoteContents;

  /// 次の転送に注入する故障。**駆動側が立てて、駆動側が落とす。**
  ///
  /// **組み立て側が作った集合をそのまま受け取る。** 転送はこの集合を握っているので、中身を
  /// 書き換えれば次の呼び出しから効く。ここで新しい集合を作ると繋がりが切れ、`fault` を
  /// 書いたケースが**故障の入らないまま緑になる。**
  ///
  /// 渡されなければ、故障を指定したケースは明示的に落ちる。
  final Set<String>? faults;

  DriverProfile(this.name, this.engine, {this.remoteContents, this.faults});

  Db get db => engine.db;
}

class FixtureDriver {
  final Contracts contracts;
  final EnvelopeCodec codec;
  final Mapping mapping;
  final Aggregates aggregates;

  /// プロファイル名 → 組み立て済みのエンジン。**遅延生成する** — script が触れたものだけを作る。
  final DriverProfile Function(String name) profileFactory;
  final Map<String, DriverProfile> _profiles = {};

  FixtureDriver(this.contracts, this.profileFactory)
      : codec = EnvelopeCodec(contracts),
        mapping = Mapping(contracts),
        aggregates = Aggregates(Mapping(contracts));

  DriverProfile profile(String name) =>
      _profiles.putIfAbsent(name, () => profileFactory(name));

  /// `script` を1本走らせ、`expect` の不一致を返す。空なら緑である。
  Future<List<String>> runScript(FixtureCase input, List<Object?> script) async {
    final fails = <String>[];
    for (final raw in script) {
      final action = raw as Map<String, Object?>;
      final op = action['do'] as String;
      final name = action['profile'] as String?;
      final now = action['now'] as String?;

      switch (op) {
        case 'seed':
          seed(name!, input.step(action['step'] as int), now!);
        case 'apply':
          await _withFault(name!, action, () async {
            await applyEnvelopes(name, input.step(action['step'] as int), now: now);
          });
        case 'push':
          await _withFault(
              name!, action, () => profile(name).engine.run(modePush, now: now!));
        case 'pull':
          await _withFault(
              name!, action, () => profile(name).engine.run(modePull, now: now!));
        case 'sync':
          await _withFault(
              name!, action, () => profile(name).engine.run(modeRun, now: now!));
        case 'unlock':
          unlock(name!, now!);
        case 'retry':
          retry(name!, action['event_id'] as String, now!);
        case 'config':
          config(name!, action['key'] as String, action['value'] as String);
        case 'resolve':
          resolve(name!, action['take'] as String, now!);
        case 'expect':
          final note = action['note'] == null ? '' : '（${action['note']}）';
          for (final failure in await expect(name!, action)) {
            fails.add('[$name] $failure$note');
          }
        default:
          fails.add('未対応の do: $op');
      }
    }
    return fails;
  }

  /// 1動作のあいだだけ故障を立てる。
  ///
  /// **必ず落とす。** 立てっぱなしにすると、次の動作が「故障の無い状態」を測れなくなる。
  /// ケース08 は `upload-timeout` の直後に素の `push` を置いて lease のふるまいを測るので、
  /// ここが漏れるとケースそのものが成立しない。
  ///
  /// **失敗した動作でも落とす。** 故障注入の狙いは例外を起こすことなので、例外の経路の方が
  /// 通常である。
  Future<void> _withFault(
      String name, Map<String, Object?> action, Future<void> Function() body) async {
    final raw = action['fault'];
    // **カンマ区切りを受ける。** 正本の fixture が `"shuffle,paginate"` の形で書いており、
    // 形式は契約である。ここで受けないと、そのケースだけ読めない。
    final faults = switch (raw) {
      null => const <String>[],
      String value => [
          for (final part in value.split(','))
            if (part.trim().isNotEmpty) part.trim(),
        ],
      List value => [for (final item in value) '$item'],
      _ => throw SyncDataError('fault は文字列か配列です: $raw', code: 'fixture-fault'),
    };
    final target = profile(name).faults;
    if (target == null) {
      if (faults.isEmpty) return body();
      // 黙って素通りさせない。故障の入らないケースが緑になるのが一番悪い。
      throw SyncDataError('この組み立ては故障注入を受けられません: $faults',
          code: 'fixture-fault-unsupported');
    }
    target
      ..clear()
      ..addAll(faults);
    try {
      await body();
    } on TransportAuthError {
      // **故障が起こした認可の失敗はここで受ける。** 受入ケース10 は「401 を受けた行だけが
      // `blocked_auth` になり、残りは pending のまま」を測る。例外が script の外へ抜けると、
      // その表明に到達しない。
    } on TransportTimeout {
      // 同じ理由。受入ケース08 は「応答は失われたが実体は書かれている」の後を測る。
    } finally {
      target.clear();
    }
  }

  /// `admin outbox unlock`。**失効した lease だけを外す。**
  ///
  /// 生きている lease を剥がすと lease は何も守らない（受入ケース09）。失効の判定は
  /// `unlockExpired` が持つ。
  void unlock(String name, String now) {
    transaction(profile(name).db, () => unlockExpired(profile(name).db, now: now));
  }

  /// `admin outbox retry`。`blocked_auth` の行を送信待ちへ戻す。
  ///
  /// **再認可の後に人が行う操作である。** 自動で戻すと、認可が切れたままの端末が送信を
  /// 繰り返す。
  void retry(String name, String eventId, String now) {
    transaction(profile(name).db,
        () => retryOutbox(profile(name).db, eventId, now: now));
  }

  /// `admin fixture seed`。集約スナップショットと outbox 行を投入する。
  ///
  /// ステップの profile が呼び出し側の profile と食い違えば拒否する。二端末シミュレーションで、
  /// 片方の操作をもう片方の端末へ投入する取り違えを機械で防ぐ。
  void seed(String name, FixtureStep step, String now) {
    _requireOwner(name, step);
    final p = profile(name);
    p.engine.emitLocal([
      for (final event in step.events)
        toEnvelope(codec, event, deviceId: p.engine.deviceId, createdAtUtc: now),
    ]);
  }

  /// `admin fixture apply`。ステップの `envelopes` を転送先へ逐語で置く。
  ///
  /// 値は書かれた通りを使い、バイト列だけ正準化する。`payloadHash` も `schemaVersion` も
  /// 補完しない。壊れたハッシュや未対応版をそのまま受信側へ届けられることが、この経路の
  /// 存在理由である。**SQLite は変えない** — 適用は続く `pull` が判定表に従って行う。
  ///
  /// **有効世代の転送へ置く。** 世代を決めずに書くと、その封筒はどの端末の一覧にも出ない。
  /// まだ世代が無ければここで起点を置く — 受信側だけで始まるケースがあるためである。
  Future<void> applyEnvelopes(String name, FixtureStep step, {String? now}) async {
    _requireOwner(name, step);
    if (step.envelopes.isEmpty) {
      throw SyncDataError(
        'step ${step.step} に envelopes がありません。'
        'ローカル発行の events は seed で投入してください。',
        code: 'fixture-no-envelopes',
      );
    }
    final transport = await profile(name)
        .engine
        .activeTransport(establish: true, now: now ?? driverDefaultNow);
    for (final envelope in step.envelopes) {
      final eventId = envelope['eventId'];
      if (eventId is! String || eventId.isEmpty) {
        throw SyncDataError('step ${step.step} の envelopes に eventId がありません。',
            code: 'fixture-envelope');
      }
      await transport.put(eventId, dumpsText(envelope));
    }
  }

  /// `config set <key> <value>` に当たる。**検証が持つ切替であり、製品の設定面ではない。**
  ///
  /// 一般の設定袋にしない。未知のキーを黙って受けると、fixture の綴り間違いが「設定したつもりで
  /// 効いていない」まま緑になる。受けるのは自動解決の切替だけである。
  void config(String name, String key, String value) {
    if (key != settingAutoResolve) {
      throw SyncDataError('検証ランナーが受ける設定は $settingAutoResolve だけです: $key',
          code: 'config-key');
    }
    profile(name).engine.autoResolve = switch (value) {
      autoResolveLww => AutoResolvePolicy.lww,
      autoResolveManual => AutoResolvePolicy.manual,
      _ => throw SyncDataError(
          '$settingAutoResolve は $autoResolveLww か $autoResolveManual です: $value',
          code: 'config-value'),
    };
  }

  /// `conflict resolve <id> --take <take>`。開いている先頭の競合を解く。
  void resolve(String name, String take, String now) {
    final engine = profile(name).engine;
    final conflictId = engine.firstOpenConflictId();
    if (conflictId == null) {
      throw SyncDataError('解決すべき open な競合がありません。', code: 'conflict-not-found');
    }
    engine.resolveConflictById(conflictId, take: take, now: now);
  }

  /// 転送先のファイル数と、相異なる `eventId` 数を見る。
  ///
  /// **DB では表明できない。** 「重複リモートイベントを作らない」（受入ケース08）は、再送が
  /// 重複を作ったかどうかが転送先にしか現れない。port の `list` は `eventId` で畳んだ後を
  /// 返すので、畳む前を数えるには転送先そのものを見るしかない。
  ///
  /// **読めない封筒も1件として数える。** ファイル数はファイル数であって、解釈できたものの数
  /// ではない。`eventId` の方は読めたものだけを数える。
  Future<List<String>> _expectRemote(String name, Map<Object?, Object?> spec) async {
    final inspect = profile(name).remoteContents;
    if (inspect == null) {
      // 黙って素通りさせない。通ったように見えるのが一番悪い。
      return ['remote の表明を測れない（組み立てが転送先の中身を渡していない）'];
    }

    final contents = await inspect();
    final eventIds = <String>{};
    for (final text in contents) {
      final id = peekIds(text).eventId;
      if (id != null) eventIds.add(id);
    }

    final fails = <String>[];
    final files = spec['files'];
    if (files != null && contents.length != files) {
      fails.add('転送先のファイルが ${contents.length} 件（期待 $files）');
    }
    final events = spec['events'];
    if (events != null && eventIds.length != events) {
      fails.add('転送先の eventId が ${eventIds.length} 件（期待 $events）');
    }
    return fails;
  }

  void _requireOwner(String name, FixtureStep step) {
    if (step.profile != name) {
      throw SyncDataError(
        'step ${step.step} は profile ${step.profile} の操作です（いまは $name）。',
        code: 'fixture-profile-mismatch',
      );
    }
  }

  /// `expect` の1件を突き合わせ、不一致の説明を返す。
  ///
  /// **表名は `mapping` から引く。** 直書きすると、集約を足したときにランナーだけが古い一覧の
  /// まま残り、その集約を使うケースが書けない。
  Future<List<String>> expect(String name, Map<String, Object?> spec) async {
    final db = profile(name).db;
    final fails = <String>[];

    final remote = spec['remote'];
    if (remote is Map) {
      fails.addAll(await _expectRemote(name, remote));
    }

    final aggregatesSpec = spec['aggregates'];
    if (aggregatesSpec is Map) {
      aggregatesSpec.forEach((entityType, entities) {
        final type = entityType as String;
        final ids = entities as Map;
        if (ids.isEmpty) {
          final count = aggregates.count(db, type);
          if (count != 0) {
            fails.add('${mapping.specFor(type).table} が空ではありません（$count 件）');
          }
          return;
        }
        ids.forEach((entityId, fields) {
          final row = aggregates.read(db, type, entityId as String);
          if (row == null) {
            fails.add('$type $entityId がありません');
            return;
          }
          (fields as Map).forEach((column, expected) {
            final actual = row[column as String];
            if (!_valueEquals(actual, expected)) {
              fails.add('$type $entityId の $column が $actual（期待 $expected）');
            }
          });
        });
      });
    }

    final conflicts = spec['conflicts'];
    if (conflicts != null) {
      final actual = countOpenConflicts(db);
      if (actual != conflicts) {
        fails.add('未解決の競合が $actual 件（期待 $conflicts）');
      }
    }

    final pending = spec['pending_events'];
    if (pending is Map) {
      // **辞書ごと一致を見る。** 期待に無い reason の滞留も不一致にする。
      final actual = pendingCountsByReason(db);
      final expected = {
        for (final entry in pending.entries) entry.key as String: entry.value as int,
      };
      if (!_mapEquals(actual, expected)) {
        fails.add('pending_events が $actual（期待 $expected）');
      }
    }

    final appliedExpected = spec['applied_events'];
    if (appliedExpected != null) {
      final actual = countApplied(db);
      if (actual != appliedExpected) {
        fails.add('applied_events が $actual 件（期待 $appliedExpected）');
      }
    }

    final outbox = spec['outbox'];
    if (outbox is Map) {
      outbox.forEach((state, expected) {
        final actual = countOutbox(db, state as String);
        if (actual != expected) {
          fails.add('outbox($state) が $actual 件（期待 $expected）');
        }
      });
    }

    return fails;
  }
}

bool _valueEquals(Object? actual, Object? expected) {
  if (actual is num && expected is num) return actual == expected;
  return actual == expected;
}

bool _mapEquals(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
