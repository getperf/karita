import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:test/test.dart';

/// 既定値が定数と同じであることを見る。
///
/// **書いてある値が正しいことは、ここでは測れない。** 測れるのは「散らばっていないこと」だけ
/// である。引数の既定へ直接数字を書き戻すと、設定の文書と突き合わせる相手が消える。
void main() {
  group('既定値は定数から来る', () {
    test('OpenBD', () {
      final client = OpenBdClient();
      addTearDown(client.close);

      expect(client.recordTimeout, defaultRecordTimeout);
      expect(client.imageTimeout, defaultImageTimeout);
      expect(client.maxRecordBytes, defaultMaxRecordBytes);
      expect(client.maxImageBytes, defaultMaxImageBytes);
      expect(client.apiBase, openBdApiBase);
    });

    test('カーリル `/library`', () {
      final client = CalilLibraryClient(appkey: 'k');
      addTearDown(client.close);

      expect(client.timeout, defaultCalilTimeout);
      expect(client.maxBytes, defaultMaxCalilResponseBytes);
      expect(client.apiBase, calilApiBase);
    });

    test('カーリル `/check`', () {
      final client = CalilCheckClient(appkey: 'k');
      addTearDown(client.close);

      expect(client.pollInterval, minPollInterval);
      expect(client.timeout, defaultCalilTimeout);
      expect(client.overallTimeout, defaultCalilOverallTimeout);
      expect(client.maxBytes, defaultMaxCalilResponseBytes);
      expect(client.bookRequestBudget, defaultBookRequestBudget);
      expect(client.apiBase, calilApiBase);
    });
  });

  group('値そのものの決まりごと', () {
    test('**聞き直しの下限は2秒。** 測って変える値ではなく、相手との約束である', () {
      expect(minPollInterval, const Duration(seconds: 2));
    });

    test('**書影の期限は書誌より長い。** 相手も大きさも違う', () {
      expect(defaultImageTimeout > defaultRecordTimeout, isTrue);
    });

    test('接続先は公式の HTTPS で固定する', () {
      for (final base in [openBdApiBase, calilApiBase]) {
        expect(base.scheme, 'https', reason: '$base');
      }
    });

    test('予算の目安は10冊 × 5館である', () {
      expect(defaultBookRequestBudget, 10 * 5);
    });

    test('全体の期限の中で、2秒間隔なら何回か聞き直せる', () {
      // 1回で終わる前提の値にすると、継続取得そのものが成り立たない。
      expect(defaultCalilOverallTimeout.inSeconds ~/ minPollInterval.inSeconds,
          greaterThan(5));
    });
  });
}
