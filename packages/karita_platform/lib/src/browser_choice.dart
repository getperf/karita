/// 開くブラウザーの選択（2026-10-16）。**Windows の分である。**
///
/// karita → 図書館サイト → 拡張 → karita の往復は、**拡張を入れたブラウザーで開かないと
/// 切れる。** OS の既定が Edge で拡張が Chrome にある端末のために、図書館サイトを開く先を
/// 端末ごとに選べるようにする。
///
/// **サインインには使わない。** `LoopbackLogin` は OS の既定のまま — 実物で通っている経路を、
/// 別の用途のために置き換えない。
///
/// **プロファイルは選ばない。** Chrome・Edge は最後に使ったプロファイルで開く。拡張の無い
/// プロファイルで開いたときの案内はガイドサイトに置く。
library;

import 'dart:io';

/// 選べる値。**先頭が既定である。** `device.json` の `browser.app` に入る。
const List<String> browserChoices = ['system', 'edge', 'chrome', 'firefox'];

/// OS の既定のブラウザーを使う値。
const String systemBrowser = 'system';

/// 開く口。**合成層が端末ごとに差し替える。**
abstract interface class BrowserLauncher {
  /// 見つかったブラウザー（[systemBrowser] を除く値）。**探せなければ空。投げない。**
  Future<Set<String>> installed();

  /// [choice] で [url] を開く。**見つからない・起動できないときは投げる** — 呼ぶ側が
  /// OS の既定で開き直す。
  Future<void> open(String choice, Uri url);
}

/// 選べない端末の口。**何も見つからず、開こうとすれば投げる。**
class NoBrowserLauncher implements BrowserLauncher {
  const NoBrowserLauncher();

  @override
  Future<Set<String>> installed() async => const {};

  @override
  Future<void> open(String choice, Uri url) async =>
      throw StateError('No browser launcher on this device');
}

/// Windows の口。**実行ファイルは `App Paths` で探し、無ければ既知の置き場を見る。**
///
/// パスを決め打ちにしない — Chrome を利用者単位で入れると `%LOCALAPPDATA%` の下に入る。
/// `App Paths` は HKCU を先に見る（利用者単位の導入が登録する側）。
class WindowsBrowserLauncher implements BrowserLauncher {
  const WindowsBrowserLauncher({
    this.environment,
    this.runReg = _runReg,
    this.exists = _exists,
    this.start = _start,
  });

  /// 既知の置き場を組むための環境変数。**`null` は `Platform.environment`。**
  final Map<String, String>? environment;

  /// `reg query <key> /ve` の出力を返す。**失敗は `null`。** 試験の差し替え口。
  final Future<String?> Function(String key) runReg;

  final bool Function(String path) exists;

  final Future<void> Function(String exe, List<String> args) start;

  static const Map<String, String> _exe = {
    'edge': 'msedge.exe',
    'chrome': 'chrome.exe',
    'firefox': 'firefox.exe',
  };

  /// 実行ファイルの場所。**見つからなければ `null`。**
  Future<String?> locate(String choice) async {
    final exe = _exe[choice];
    if (exe == null) return null;
    for (final hive in const ['HKCU', 'HKLM']) {
      final output = await runReg(
        '$hive\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\$exe',
      );
      final path = output == null ? null : parseRegDefault(output);
      if (path != null && exists(path)) return path;
    }
    for (final path in _knownPaths(choice)) {
      if (exists(path)) return path;
    }
    return null;
  }

  Iterable<String> _knownPaths(String choice) sync* {
    final env = environment ?? Platform.environment;
    final roots = [
      env['ProgramFiles'],
      env['ProgramFiles(x86)'],
      env['LOCALAPPDATA'],
    ].whereType<String>();
    final tail = switch (choice) {
      'edge' => r'Microsoft\Edge\Application\msedge.exe',
      'chrome' => r'Google\Chrome\Application\chrome.exe',
      'firefox' => r'Mozilla Firefox\firefox.exe',
      _ => null,
    };
    if (tail == null) return;
    for (final root in roots) {
      yield '$root\\$tail';
    }
  }

  @override
  Future<Set<String>> installed() async {
    final found = <String>{};
    for (final choice in _exe.keys) {
      try {
        if (await locate(choice) != null) found.add(choice);
      } catch (_) {
        // **1つ探せなくても他は出す。**
      }
    }
    return found;
  }

  @override
  Future<void> open(String choice, Uri url) async {
    final exe = await locate(choice);
    if (exe == null) throw StateError('Browser not found: $choice');
    // **URL は1つの引数で渡す。** シェルを通さないので、クエリの `&` で切れない。
    await start(exe, [if (choice == 'firefox') '-new-tab', '$url']);
  }

  /// `reg query … /ve` の出力から既定値を取り出す。**値の名前は OS の言語で変わる**
  /// （`(既定)`・`(Default)`）ので、型の語 `REG_SZ` / `REG_EXPAND_SZ` の後ろを読む。
  static String? parseRegDefault(String output) {
    final pattern = RegExp(r'\sREG_(?:EXPAND_)?SZ\s+(.+)$', multiLine: true);
    final match = pattern.firstMatch(output);
    if (match == null) return null;
    var value = match.group(1)!.trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    value = value.replaceAllMapped(
      RegExp('%([^%]+)%'),
      (m) => Platform.environment[m.group(1)!] ?? m.group(0)!,
    );
    return value.isEmpty ? null : value;
  }

  static Future<String?> _runReg(String key) async {
    try {
      final result = await Process.run('reg', ['query', key, '/ve']);
      return result.exitCode == 0 ? '${result.stdout}' : null;
    } on ProcessException {
      return null;
    }
  }

  static bool _exists(String path) => File(path).existsSync();

  static Future<void> _start(String exe, List<String> args) async {
    await Process.start(exe, args, mode: ProcessStartMode.detached);
  }
}
