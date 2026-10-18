/// 集約規則の試験。**「蔵書なし」を名乗れる条件を固定する。**
///
/// ここが緩むと画面が「この館には無い」と言い切る。実測で 24組のうち 22組しか返らない回が
/// 出ているので（2026-09-16）、**応答に現れない館を数える枝は必ず踏む。**
library;

import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:test/test.dart';

SystemHolding _settled(String id, Map<String, String> libkey) =>
    SystemHolding(systemId: id, status: 'OK', libkeyStatuses: libkey);

void main() {
  final observedAt = DateTime.utc(2026, 9, 21, 12, 34);

  HoldingsSummary summarize(
    List<String> requested,
    List<SystemHolding>? holdings, {
    ApiFailure? failure,
  }) => summarizeHoldings(
    requestedSystemIds: requested,
    holdings: holdings,
    observedAt: holdings == null ? null : observedAt,
    failure: failure,
  );

  group('呼ぶ前に分かるもの', () {
    test('観測が無ければ未照会。**蔵書なしではない**', () {
      final summary = summarize(['A'], null);
      expect(summary.state, HoldingsState.notRequested);
      expect(summary.observedAt, isNull);
    });

    test('登録館が無ければ、館を登録してくださいになる', () {
      expect(
        summarize(const [], null).state,
        HoldingsState.noLibrary,
      );
      // 頼む館が無いのに観測が在ることは無いが、順序の取り違えで蔵書なしを出さないこと。
      expect(summarize(const [], const []).state, HoldingsState.noLibrary);
    });

    test('ISBNなしと appkey なしは定数で持つ', () {
      expect(HoldingsSummary.noIsbn.state, HoldingsState.noIsbn);
      expect(HoldingsSummary.keyMissing.state, HoldingsState.keyMissing);
      expect(HoldingsSummary.noIsbn.found, isFalse);
    });
  });

  group('貸出可と蔵書あり', () {
    test('libkey に貸出可が在れば貸出可', () {
      final summary = summarize(['A'], [
        _settled('A', {'豊洲': '貸出可', '東雲': '貸出中'}),
      ]);
      expect(summary.state, HoldingsState.available);
      expect(summary.settled, 1);
      expect(summary.pending, 0);
      expect(summary.partial, isFalse);
      expect(summary.observedAt, observedAt);
    });

    test('貸出中は貸出中として出す', () {
      expect(
        summarize(['A'], [
          _settled('A', {'豊洲': '貸出中'}),
        ]).state,
        HoldingsState.borrowed,
      );
    });

    test('予約中・準備中は準備中にまとめる。**待てば借りられる側である**', () {
      for (final status in ['予約中', '準備中']) {
        expect(
          summarize(['A'], [
            _settled('A', {'豊洲': status}),
          ]).state,
          HoldingsState.preparing,
          reason: status,
        );
      }
    });

    test('館内のみ・休館中・不明は貸出し不可にまとめる', () {
      for (final status in ['館内のみ', '休館中', '不明']) {
        expect(
          summarize(['A'], [
            _settled('A', {'豊洲': status}),
          ]).state,
          HoldingsState.restricted,
          reason: status,
        );
      }
    });

    test('**知らない貸出状態は不明と同じに置く。** 借りられる側へ寄せない', () {
      final summary = summarize(['A'], [
        _settled('A', {'豊洲': '取次中'}),
      ]);
      expect(summary.state, HoldingsState.restricted);
      expect(summary.state, isNot(HoldingsState.available));
      // **蔵書なしにはしない。** 所蔵は在る。
      expect(summary.found, isTrue);
    });

    test('**同じ本が複数の館に在れば、いちばん良いものを出す**', () {
      // 1館が貸出中でも、別の館で借りられるなら借りに行ける。
      expect(
        summarize(['A', 'B'], [
          _settled('A', {'豊洲': '貸出中'}),
          _settled('B', {'東雲': '貸出可'}),
        ]).state,
        HoldingsState.available,
      );
      // 館内のみより準備中のほうが良い。
      expect(
        summarize(['A', 'B'], [
          _settled('A', {'豊洲': '館内のみ'}),
          _settled('B', {'東雲': '予約中'}),
        ]).state,
        HoldingsState.preparing,
      );
      // 同じ館の中でも良いほうを採る。
      expect(
        summarize(['A'], [
          _settled('A', {'豊洲': '貸出中', '東雲': '貸出可'}),
        ]).state,
        HoldingsState.available,
      );
    });
  });

  group('蔵書なしを名乗れる条件', () {
    test('頼んだ館すべてが答え、どこにも libkey が無いときだけ蔵書なし', () {
      final summary = summarize(['A', 'B'], [
        _settled('A', const {}),
        _settled('B', const {}),
      ]);
      expect(summary.state, HoldingsState.absent);
      expect(summary.settled, 2);
      expect(summary.pending, 0);
    });

    test('**応答に現れない館が在れば蔵書なしにしない。** 確認中である', () {
      final summary = summarize(['A', 'B'], [_settled('A', const {})]);
      expect(summary.state, HoldingsState.checking);
      expect(summary.settled, 1);
      expect(summary.pending, 1);
    });

    test('Running が残っていれば蔵書なしにしない', () {
      final summary = summarize(['A', 'B'], [
        _settled('A', const {}),
        const SystemHolding(systemId: 'B', status: 'Running'),
      ]);
      expect(summary.state, HoldingsState.checking);
      expect(summary.pending, 1);
    });

    test('知らない status も決着させない', () {
      final summary = summarize(['A'], [
        const SystemHolding(systemId: 'A', status: 'Queued'),
      ]);
      expect(summary.state, HoldingsState.checking);
      expect(summary.pending, 1);
      expect(summary.settled, 0);
    });

    test('Error だけが返った回は蔵書なしではなく確認できません', () {
      final summary = summarize(['A'], [
        const SystemHolding(systemId: 'A', status: 'Error'),
      ]);
      expect(summary.state, HoldingsState.failed);
      expect(summary.errored, 1);
    });

    test('頼んでいない館の答えは勘定に入れない', () {
      final summary = summarize(['A'], [
        _settled('A', const {}),
        _settled('Z', {'よそ': '貸出可'}),
      ]);
      expect(summary.state, HoldingsState.absent);
      expect(summary.settled, 1);
    });
  });

  group('部分結果と失敗', () {
    test('見つかっていれば、失敗しても肯定を出す。**部分結果は捨てない**', () {
      final summary = summarize(
        ['A', 'B'],
        [_settled('A', {'豊洲': '貸出可'})],
        failure: ApiFailure.timeout,
      );
      expect(summary.state, HoldingsState.available);
      expect(summary.pending, 1, reason: 'B は未確認のまま残る');
      expect(summary.partial, isTrue);
      expect(summary.failure, ApiFailure.timeout);
    });

    test('何も見つからずに失敗したら確認できません', () {
      final summary = summarize(
        ['A'],
        const [],
        failure: ApiFailure.network,
      );
      expect(summary.state, HoldingsState.failed);
    });

    test('**上限は他の失敗と分ける。** 時間を置けば直る', () {
      final summary = summarize(
        ['A'],
        const [],
        failure: ApiFailure.rateLimited,
      );
      expect(summary.state, HoldingsState.rateLimited);
    });
  });
}
