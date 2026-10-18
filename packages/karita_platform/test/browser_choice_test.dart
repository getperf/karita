/// 開くブラウザーの探索と起動（2026-10-16）。**レジストリと起動は差し込む。**
library;

import 'package:karita_platform/karita_platform.dart';
import 'package:test/test.dart';

void main() {
  group('reg query の既定値', () {
    test('値の名前の言語に依らず読む', () {
      const ja =
          '\r\n'
          r'HKEY_CURRENT_USER\Software\chrome.exe'
          '\r\n'
          r'    (既定)    REG_SZ    C:\Users\u\AppData\Local\Google\Chrome\Application\chrome.exe'
          '\r\n\r\n';
      const en =
          '\r\n'
          r'HKEY_LOCAL_MACHINE\Software\msedge.exe'
          '\r\n'
          r'    (Default)    REG_SZ    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"'
          '\r\n';
      expect(
        WindowsBrowserLauncher.parseRegDefault(ja),
        r'C:\Users\u\AppData\Local\Google\Chrome\Application\chrome.exe',
      );
      expect(
        WindowsBrowserLauncher.parseRegDefault(en),
        r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      );
    });

    test('値が無ければ null', () {
      expect(
        WindowsBrowserLauncher.parseRegDefault(
          '    (既定)    REG_SZ    (値の設定なし)\r\n'.replaceAll('(値の設定なし)', ''),
        ),
        isNull,
      );
    });
  });

  group('探索と起動', () {
    const chrome = r'C:\L\Google\Chrome\Application\chrome.exe';
    const firefox = r'C:\P\Mozilla Firefox\firefox.exe';

    WindowsBrowserLauncher launcher(List<(String, List<String>)> started) =>
        WindowsBrowserLauncher(
          environment: const {'ProgramFiles': r'C:\P', 'LOCALAPPDATA': r'C:\L'},
          runReg: (key) async =>
              key.startsWith('HKCU') && key.endsWith('chrome.exe')
              ? '    (既定)    REG_SZ    $chrome\r\n'
              : null,
          exists: (path) => path == chrome || path == firefox,
          start: (exe, args) async => started.add((exe, args)),
        );

    test('App Paths と既知の置き場の両方で見つける', () async {
      expect(await launcher([]).installed(), {'chrome', 'firefox'});
    });

    test('URL を1つの引数で渡す。Firefox は新しいタブで', () async {
      final started = <(String, List<String>)>[];
      final url = Uri.parse('https://example.jp/opac?a=1&b=2');
      await launcher(started).open('chrome', url);
      await launcher(started).open('firefox', url);
      expect(started.map((s) => s.$1), [chrome, firefox]);
      expect(started[0].$2, ['$url']);
      expect(started[1].$2, ['-new-tab', '$url']);
    });

    test('見つからなければ投げる', () async {
      expect(
        launcher([]).open('edge', Uri.parse('https://example.jp/')),
        throwsStateError,
      );
    });
  });
}
