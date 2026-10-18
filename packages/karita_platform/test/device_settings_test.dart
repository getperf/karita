/// 端末設定。**「読めないときの定義」の表をそのまま測る。**
///
/// 正本は `非公開資料:settings-and-parameters.md` の同名の節である。6行それぞれに
/// 試験を1つ置く — **設定ファイルが読めないことを起動の失敗にしない**という規則は、実装より
/// 先にここで固定しておく。
library;

import 'dart:convert';
import 'dart:io';

import 'package:karita_platform/karita_platform.dart';
import 'package:test/test.dart';

void main() {
  late Directory home;
  late String configDir;

  void put(String text) {
    Directory(configDir).createSync(recursive: true);
    File(AppLayout.under(configDir, AppLayout.deviceConfig))
        .writeAsStringSync(text);
  }

  Map<String, Object?> readBack() => jsonDecode(
        File(AppLayout.under(configDir, AppLayout.deviceConfig))
            .readAsStringSync(),
      ) as Map<String, Object?>;

  setUp(() {
    home = Directory.systemTemp.createTempSync('karita-device-settings-');
    configDir = WindowsAppPaths.at(home.path).configDir;
  });
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  group('読めないときの定義', () {
    test('ファイルが無ければ既定で起動し、所見にしない', () {
      final settings = DeviceSettings.read(configDir);
      expect(settings.autoRefreshEnabled, isTrue);
      expect(settings.autoRefreshSeconds, 30);
      expect(settings.logLevel, isNull);
      expect(settings.theme, 'system');
      expect(settings.issues, isEmpty);
    });

    test('JSON として壊れていれば既定で起動し、所見にする', () {
      put('{ "sync": ');
      final settings = DeviceSettings.read(configDir);
      expect(settings.autoRefreshSeconds, 30);
      expect(settings.reportableIssues.single.problem,
          DeviceSettingProblem.unreadable);
    });

    test('壊れていても書き直さない', () {
      put('{ broken');
      DeviceSettings.read(configDir);
      expect(File(AppLayout.under(configDir, AppLayout.deviceConfig))
          .readAsStringSync(), '{ broken');
    });

    test('鍵が無ければその鍵だけ既定', () {
      put(jsonEncode({
        'schemaVersion': 1,
        'sync': {'autoRefreshSeconds': 45},
      }));
      final settings = DeviceSettings.read(configDir);
      expect(settings.autoRefreshSeconds, 45);
      expect(settings.autoRefreshEnabled, isTrue);
      expect(settings.issues, isEmpty);
    });

    test('旧鍵 autoRefreshMinutes は読まず、書き戻しで消す（2026-10-08）', () {
      // 全端末が既定値 15 を書き出している。引き継ぐと 30 秒がどの端末にも届かない。
      put(jsonEncode({
        'schemaVersion': 1,
        'sync': {'autoRefreshEnabled': true, 'autoRefreshMinutes': 15},
      }));
      final settings = DeviceSettings.read(configDir);
      expect(settings.autoRefreshSeconds, 30);
      expect(settings.issues, isEmpty);

      settings.write(configDir);
      final sync = readBack()['sync'] as Map;
      expect(sync.containsKey('autoRefreshMinutes'), isFalse);
      expect(sync['autoRefreshSeconds'], 30);
    });

    test('知らない鍵は無視し、所見にしない', () {
      put(jsonEncode({
        'schemaVersion': 1,
        'somethingNew': {'a': 1},
        'ui': {'theme': 'dark', 'unknownKey': 3},
      }));
      final settings = DeviceSettings.read(configDir);
      expect(settings.theme, 'dark');
      expect(settings.issues, isEmpty);
    });

    test('範囲外・型違いはその鍵だけ既定へ落とし、所見にはしない', () {
      put(jsonEncode({
        'schemaVersion': 1,
        'sync': {'autoRefreshEnabled': 'yes', 'autoRefreshSeconds': 29},
      }));
      final settings = DeviceSettings.read(configDir);
      expect(settings.autoRefreshEnabled, isTrue);
      expect(settings.autoRefreshSeconds, 30);
      expect(settings.issues.map((i) => i.key),
          containsAll(['sync.autoRefreshEnabled', 'sync.autoRefreshSeconds']));
      // **ログには出るが、`doctor` の所見にはしない。**
      expect(settings.reportableIssues, isEmpty);
    });

    test('schemaVersion が新しければ読める鍵だけ読み、所見にする', () {
      put(jsonEncode({
        'schemaVersion': 99,
        'log': {'level': 'WARNING'},
      }));
      final settings = DeviceSettings.read(configDir);
      expect(settings.logLevel, 'WARNING');
      expect(settings.reportableIssues.single.problem,
          DeviceSettingProblem.schemaAhead);
    });
  });

  group('読む', () {
    test('全部書いてあれば全部読む', () {
      put(jsonEncode({
        'schemaVersion': 1,
        'sync': {'autoRefreshEnabled': false, 'autoRefreshSeconds': 120},
        'log': {'level': 'FINE', 'format': 'jsonl'},
        'ui': {'theme': 'dark', 'lastTab': 'operations'},
      }));
      final settings = DeviceSettings.read(configDir);
      expect(settings.autoRefreshEnabled, isFalse);
      expect(settings.autoRefreshSeconds, 120);
      expect(settings.logLevel, 'FINE');
      expect(settings.logFormat, 'jsonl');
      expect(settings.theme, 'dark');
      expect(settings.lastTab, 'operations');
      expect(settings.issues, isEmpty);
    });

    test('水準と書式の語彙は見ない', () {
      // 名前が水準として通るかを知っているのはログの側である。ここは運ぶだけにする。
      put(jsonEncode({
        'log': {'level': 'LOUD', 'format': 'yaml'},
      }));
      final settings = DeviceSettings.read(configDir);
      expect(settings.logLevel, 'LOUD');
      expect(settings.logFormat, 'yaml');
      expect(settings.issues, isEmpty);
    });

    test('節そのものが object でなければ、その節だけ落とす', () {
      put(jsonEncode({'sync': 'on', 'ui': {'theme': 'light'}}));
      final settings = DeviceSettings.read(configDir);
      expect(settings.autoRefreshSeconds, 30);
      expect(settings.theme, 'light');
      expect(settings.issues.single.key, 'sync');
    });
  });

  group('書く', () {
    test('知らない鍵を残す', () {
      put(jsonEncode({
        'schemaVersion': 1,
        'somethingNew': {'a': 1},
        'ui': {'theme': 'dark', 'unknownKey': 3},
      }));
      DeviceSettings.read(configDir)
          .copyWith(autoRefreshSeconds: 60)
          .write(configDir);

      final written = readBack();
      expect(written['somethingNew'], {'a': 1});
      expect((written['ui'] as Map)['unknownKey'], 3);
      expect((written['sync'] as Map)['autoRefreshSeconds'], 60);
      expect(written['schemaVersion'], 1);
    });

    test('書いたものを読み直せる', () {
      const DeviceSettings(logLevel: 'WARNING', logFormat: 'jsonl')
          .copyWith(autoRefreshEnabled: false)
          .write(configDir);
      final settings = DeviceSettings.read(configDir);
      expect(settings.logLevel, 'WARNING');
      expect(settings.logFormat, 'jsonl');
      expect(settings.autoRefreshEnabled, isFalse);
      expect(settings.issues, isEmpty);
    });

    test('ファイルに全鍵を書き出さない — 無い値は書かない', () {
      const DeviceSettings().write(configDir);
      final written = readBack();
      expect(written['log'], isEmpty);
      expect((written['ui'] as Map).containsKey('lastTab'), isFalse);
      expect(written.containsKey('browser'), isFalse, reason: '未確認の端末に節を作らない');
    });

    test('ブラウザー連携の確認・見送りを読み直せる（2026-10-15）', () {
      const DeviceSettings()
          .copyWith(browserSkippedAt: '2026-10-15T01:00:00Z')
          .write(configDir);
      DeviceSettings.read(configDir)
          .copyWith(browserLinkedAt: '2026-10-15T02:00:00Z')
          .write(configDir);
      final settings = DeviceSettings.read(configDir);
      expect(settings.browserLinkedAt, '2026-10-15T02:00:00Z');
      expect(settings.browserSkippedAt, '2026-10-15T01:00:00Z');
      expect(settings.issues, isEmpty);
    });

    test('開くブラウザーを読み直せる。既定は OS の既定（2026-10-16）', () {
      expect(DeviceSettings.read(configDir).browserApp, 'system');
      const DeviceSettings().copyWith(browserApp: 'chrome').write(configDir);
      final settings = DeviceSettings.read(configDir);
      expect(settings.browserApp, 'chrome');
      expect(settings.issues, isEmpty);
    });

    test('知らないブラウザーは既定へ落とし、所見にしない', () {
      Directory(configDir).createSync(recursive: true);
      File('$configDir/device.json')
          .writeAsStringSync('{"browser": {"app": "opera"}}');
      final settings = DeviceSettings.read(configDir);
      expect(settings.browserApp, 'system');
      expect(settings.issues.single.key, 'browser.app');
      expect(settings.reportableIssues, isEmpty);
    });
  });

  group('カーリルの appkey', () {
    test('端末上書きとして読める。**前後の空白は落とす**', () {
      put('{"calil":{"appkey":"  device-key  "}}');
      final settings = DeviceSettings.read(configDir);

      expect(settings.calilAppkey, 'device-key');
      expect(settings.issues, isEmpty);
    });

    test('無ければ null。**同梱値を使うのは合成層の判断である**', () {
      put('{}');
      expect(DeviceSettings.read(configDir).calilAppkey, isNull);
    });

    test('**落としても値を出さない。** 出すのは鍵の名前だけである', () {
      for (final document in [
        '{"calil":{"appkey":12345}}',
        '{"calil":{"appkey":"   "}}',
      ]) {
        put(document);
        final settings = DeviceSettings.read(configDir);
        expect(settings.calilAppkey, isNull, reason: document);
        final issue = settings.issues.single;
        expect(issue.key, 'calil.appkey', reason: document);
        // ここが要点である。**ログにも所見にも生の値を載せない。**
        expect(issue.detail, isNull, reason: document);
      }
    });

    test('区画ごと書き間違えても、中身を出さない', () {
      // `"calil": "<鍵そのもの>"` と書かれうる。**他の区画と同じ扱いにすると値が漏れる。**
      put('{"calil":"looks-like-a-key"}');
      final settings = DeviceSettings.read(configDir);

      expect(settings.calilAppkey, isNull);
      expect(settings.issues.single.key, 'calil');
      expect(settings.issues.single.detail, isNull);
    });

    test('ログの最初の1行に載らない', () {
      put('{"calil":{"appkey":"device-key"}}');
      final fields = DeviceSettings.read(configDir).toLogFields();

      expect(fields.values.join(' '), isNot(contains('device-key')));
      expect(fields.keys.join(' '), isNot(contains('calil')));
    });

    test('**他の値を書き換えても落ちない。** copyWith が持ち越す', () {
      put('{"calil":{"appkey":"device-key"}}');
      final settings = DeviceSettings.read(configDir).copyWith(theme: 'dark');

      expect(settings.calilAppkey, 'device-key');
    });

    test('書き戻しても消えない。**知らない鍵と同じく残る**', () {
      put('{"calil":{"appkey":"device-key"}}');
      DeviceSettings.read(configDir).copyWith(theme: 'dark').write(configDir);

      expect(DeviceSettings.read(configDir).calilAppkey, 'device-key');
    });
  });
}
