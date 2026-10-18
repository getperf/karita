/// 同期ケースファイルの読み取り。
///
/// 形式の正本は book-sync-model の `非公開資料:sync-fixture-format.md` である。
/// **暗黙の形式にしない** — Python と Dart が同じファイルを読むため、読み方の緩さがずれると
/// 「両方が自分の解釈に対して緑」になる。
///
/// 1ステップ = 1トランザクション = そのステップの events である。`deviceId` は profile から、
/// `createdAtUtc` は now から入り、`payloadHash` は正準化から計算する。**これらを fixture に
/// 書かせない。** 書けるようにすると、fixture と実際の生成規則が静かにずれる。
///
/// ステップは二つの経路を持つ。
///
/// | キー | 経路 | 派生項目 |
/// |---|---|---|
/// | `events` | ローカル発行（`admin fixture seed`） | 実装が入れる。fixture には書けない |
/// | `envelopes` | 受信（転送先へ逐語で置く） | 入れない。書かれた通りを使う |
///
/// `envelopes` は**現行の実装では生成できない入力**を表現するための唯一の経路である。未対応
/// `schemaVersion` のケース06 は、派生項目の禁止規則により `events` では書けない。テスト専用の
/// 裏口を実装に作らず、fixture の形として持たせる。
///
/// 移送元: book-sync-model の `src/bsync_core/fixtures.py`。
library;

import 'package:karita_contract/karita_contract.dart';

const Set<String> caseKeys = {'case', 'title', 'description', 'steps'};
const Set<String> stepKeys = {'step', 'profile', 'note', 'events', 'envelopes'};
const Set<String> eventKeys = {
  'eventId',
  'entityType',
  'entityId',
  'operation',
  'baseVersion',
  'resultVersion',
  'resolvesEventIds',
  'payload',
};

/// profile と now と正準化から入るため、fixture には書けない。
const Set<String> derivedEventKeys = {
  'deviceId',
  'createdAtUtc',
  'payloadHash',
  'schemaVersion',
};

class FixtureStep {
  final int step;
  final String profile;
  final String note;
  final List<Map<String, Object?>> events;

  /// 受信側の転送先へ逐語で置く封筒。派生項目の禁止規則は掛からない。
  final List<Map<String, Object?>> envelopes;

  const FixtureStep({
    required this.step,
    required this.profile,
    required this.note,
    required this.events,
    required this.envelopes,
  });
}

class FixtureCase {
  final String name;
  final String title;
  final List<FixtureStep> steps;

  const FixtureCase({
    required this.name,
    required this.title,
    required this.steps,
  });

  FixtureStep step(int number) => steps.firstWhere(
        (item) => item.step == number,
        orElse: () => throw SyncDataError(
          '$name に step $number がありません（あるのは ${steps.map((s) => s.step).join('、')}）。',
          code: 'fixture-step',
        ),
      );

  /// ケースファイルの JSON を読む。**重複キーを拒否する読み取りを通してから渡すこと。**
  factory FixtureCase.parse(Object? raw, {String label = 'ケースファイル'}) {
    final root = _requireMap(raw, label);
    _rejectUnknown(root, caseKeys, label);

    final rawSteps = root['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      throw SyncDataError('$label に steps がありません。', code: 'fixture');
    }

    final steps = <FixtureStep>[];
    final seen = <int>{};
    for (var index = 0; index < rawSteps.length; index++) {
      final stepLabel = '$label の steps[$index]';
      final obj = _requireMap(rawSteps[index], stepLabel);
      _rejectUnknown(obj, stepKeys, stepLabel);

      final number = obj['step'];
      if (number is bool || number is! int) {
        throw SyncDataError('$stepLabel.step が整数ではありません。', code: 'fixture');
      }
      if (!seen.add(number)) {
        throw SyncDataError('$label に step $number が重複しています。', code: 'fixture');
      }

      final profile = obj['profile'];
      if (profile is! String || profile.isEmpty) {
        throw SyncDataError(
          '$label の step $number に profile がありません。どちらの端末の操作かを明示してください。',
          code: 'fixture',
        );
      }

      final rawEvents = obj['events'];
      final rawEnvelopes = obj['envelopes'];
      final hasEvents = rawEvents is List && rawEvents.isNotEmpty;
      final hasEnvelopes = rawEnvelopes is List && rawEnvelopes.isNotEmpty;
      if (!hasEvents && !hasEnvelopes) {
        throw SyncDataError(
            '$label の step $number に events も envelopes もありません。',
            code: 'fixture');
      }

      final events = <Map<String, Object?>>[];
      if (hasEvents) {
        for (var position = 0; position < rawEvents.length; position++) {
          final eventLabel = '$label の step $number の events[$position]';
          final event = _requireMap(rawEvents[position], eventLabel);
          _rejectUnknown(event, eventKeys, eventLabel);
          events.add(event);
        }
      }

      // envelopes は書かれた通りを使う。派生項目の禁止も項目の制限も掛けない。現行の実装が
      // 生成できない入力を表現するための経路だからである。
      final envelopes = <Map<String, Object?>>[];
      if (hasEnvelopes) {
        for (var position = 0; position < rawEnvelopes.length; position++) {
          envelopes.add(_requireMap(rawEnvelopes[position],
              '$label の step $number の envelopes[$position]'));
        }
      }

      steps.add(FixtureStep(
        step: number,
        profile: profile,
        note: (obj['note'] as String?) ?? '',
        events: events,
        envelopes: envelopes,
      ));
    }

    steps.sort((a, b) => a.step.compareTo(b.step));
    return FixtureCase(
      name: (root['case'] as String?) ?? label,
      title: (root['title'] as String?) ?? '',
      steps: steps,
    );
  }
}

/// fixture のイベントを封筒にする。**派生項目はここで入れる。**
Envelope toEnvelope(
  EnvelopeCodec codec,
  Map<String, Object?> event, {
  required String deviceId,
  required String createdAtUtc,
}) =>
    codec.build(
      eventId: event['eventId'],
      deviceId: deviceId,
      createdAtUtc: createdAtUtc,
      entityType: event['entityType'],
      entityId: event['entityId'],
      operation: event['operation'] ?? operationUpsert,
      baseVersion: event['baseVersion'],
      resultVersion: event['resultVersion'],
      payload: event['payload'] ?? <String, Object?>{},
      resolvesEventIds: event['resolvesEventIds'] ?? const [],
    );

Map<String, Object?> _requireMap(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw SyncDataError('$label はオブジェクトである必要があります。', code: 'fixture');
  }
  return value;
}

void _rejectUnknown(Map<String, Object?> obj, Set<String> allowed, String label) {
  final unknown = obj.keys.where((key) => !allowed.contains(key)).toList()..sort();
  if (unknown.isEmpty) return;
  final derived = unknown.where(derivedEventKeys.contains).toList();
  if (derived.isNotEmpty) {
    throw SyncDataError(
      '$label に ${derived.join('、')} は書けません。deviceId は profile から、'
      'createdAtUtc は now から入り、payloadHash は正準化から計算します。',
      code: 'fixture-derived-key',
    );
  }
  throw SyncDataError(
    '$label に未知の項目があります: ${unknown.join('、')}'
    '（使えるのは ${(allowed.toList()..sort()).join('、')}）',
    code: 'fixture-unknown-key',
  );
}
