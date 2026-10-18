/// 外部 API のキー供給。**「端末上書きが同梱値に優先する」をここで固定する。**
///
/// 正本は `非公開資料:settings-and-parameters.md` の
/// 「appkey の置き場と項目名」である。保管の形（`device.json` の `calil.appkey`）は
/// `karita_platform` が、`.env` をビルドへ渡すのは `tools/run-dev.ps1` が持つ。
/// **ここが決めるのは、両方が在ったときにどちらを採るかだけである。**
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';

void main() {
  group('カーリルの appkey を選ぶ', () {
    test('**端末上書きが同梱値に優先する**', () {
      final choice =
          resolveCalilAppkey(deviceOverride: 'device', bundled: 'bundled');

      expect(choice.key, 'device');
      expect(choice.source, CalilKeySource.deviceOverride);
      expect(choice.usable, isTrue);
    });

    test('上書きが無ければ同梱値を使う。**利用者に個人キーを求めない**', () {
      final choice = resolveCalilAppkey(bundled: 'bundled');

      expect(choice.key, 'bundled');
      expect(choice.source, CalilKeySource.bundled);
      expect(choice.usable, isTrue);
    });

    test('どちらも無ければ使えない。**「蔵書なし」ではない**', () {
      final choice = resolveCalilAppkey(bundled: '');

      expect(choice.usable, isFalse);
      expect(choice.key, isEmpty);
      expect(choice.source, CalilKeySource.none);
    });

    test('空白だけの値は「無い」と同じに扱う', () {
      // 書き損じを「設定してある」と数えると、401 が続く理由が「キーが無い」ではなく
      // 「キーが違う」に見える。
      expect(resolveCalilAppkey(deviceOverride: '   ', bundled: 'bundled').source,
          CalilKeySource.bundled);
      expect(resolveCalilAppkey(deviceOverride: '  ', bundled: '  ').source,
          CalilKeySource.none);
    });

    test('前後の空白は落として渡す', () {
      expect(resolveCalilAppkey(deviceOverride: ' device ').key, 'device');
      expect(resolveCalilAppkey(bundled: ' bundled ').key, 'bundled');
    });

    test('**ログに出るのは出どころだけである。** 値は出さない', () {
      final fields =
          resolveCalilAppkey(deviceOverride: 'secret-value').toLogFields();

      expect(fields, {'calil_key': 'deviceOverride'});
      expect(fields.values.join(' '), isNot(contains('secret-value')));
    });

    test('焼き込みの既定は空である。**渡さなければ使えない**', () {
      // `--dart-define` を渡さずに建てた実行ファイルがこれになる。
      expect(defineCalilAppkey, isEmpty);
      expect(resolveCalilAppkey().usable, isFalse);
    });
  });
}
