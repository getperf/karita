/// 端末設定（`config/device.json`）の読み書き。
///
/// **層は「端末設定」である** — その端末でどう動くかだけを持ち、同期もせず復元でも運ばれない。
/// 端末をまたいで持ち越したいものは集約（台帳）へ置く。分割線の正本は
/// `非公開資料:settings-and-parameters.md` にある。
///
/// **置き場所を決めるのは ③ である。** `AppPaths` が `configDir` を持つのと同じ理由でここに
/// 置く。**水準と書式の語彙は持たない** — `INFO` や `jsonl` が何であるかを知っているのは
/// ログの側（`karita_app`）なので、ここは生の文字列を運ぶだけにする。そうしないと、語彙が
/// 2箇所に写る。
///
/// **読めないことを起動の失敗にしない。** 起動しなければ設定画面へ到達できず、利用者が直す
/// 経路そのものが無くなる。**黙って直しもしない** — 壊れた事実は [DeviceSettings.issues] に
/// 残し、呼ぶ側が `doctor` の所見とログに出す。
library;

import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';
import 'browser_choice.dart';

/// 設定を読むときに起きたこと。**どれも起動を止めない。**
enum DeviceSettingProblem {
  /// JSON として壊れている、または読めない。**既定で起動し、所見とログに出す。**
  unreadable,

  /// `schemaVersion` がこの版より新しい。**読める鍵だけ読み、所見にする。**
  schemaAhead,

  /// 値が範囲外・型違い。**その鍵だけ既定へ落とし、ログに出す。所見にはしない。**
  valueIgnored,
}

/// 落とした1件。**件数と鍵と生値だけを持ち、文言を持たない。**
class DeviceSettingIssue {
  final DeviceSettingProblem problem;

  /// 落とした鍵。`sync.autoRefreshSeconds` のような点つなぎ。ファイル全体なら空。
  final String key;

  /// 落とした理由の生値。**値そのものを出す** — 伏せると直しようがない。
  final String? detail;

  const DeviceSettingIssue(this.problem, {this.key = '', this.detail});

  /// `doctor` の所見にするか。
  ///
  /// **範囲外の値は所見にしない。** 版を落とした端末や書き損じが毎回「異常」を名乗ると、
  /// 所見が読まれなくなる。ログには残るので、切り分けの材料は失われない。
  bool get reportable => problem != DeviceSettingProblem.valueIgnored;

  Map<String, Object?> toMap() => {
        'problem': problem.name,
        if (key.isNotEmpty) 'key': key,
        if (detail != null) 'detail': detail,
      };

  @override
  String toString() => '${problem.name}${key.isEmpty ? '' : ' $key'}'
      '${detail == null ? '' : ' ($detail)'}';
}

/// 端末設定。**既定値はコードが持ち、ファイルに全鍵を書き出さない。**
///
/// 無い鍵は既定として読む。**知らない鍵は無視し、所見にもしない** — 版を落とした端末が
/// 壊れないためである。書き戻すときは知らない鍵をそのまま残す。
class DeviceSettings {
  /// この版が扱う `schemaVersion`。
  ///
  /// **台帳のマイグレーションとは別系統である。** 読み手はこのファイルを読む側だけなので、
  /// 版を上げても台帳は動かない。
  static const int supportedSchemaVersion = 1;

  static const bool defaultAutoRefreshEnabled = true;
  static const int defaultAutoRefreshSeconds = 30;

  /// 周期の下限と上限（秒）。**下限は既定値と同じ 30 秒である。** これより短くしても、
  /// 1回の同期（何も無い回で1〜2秒）と重なって飛ばされる回が増えるだけで、届くのは速くならない。
  static const int minAutoRefreshSeconds = 30;
  static const int maxAutoRefreshSeconds = 86400;
  static const String defaultTheme = 'system';
  static const String defaultBrowserApp = systemBrowser;

  /// 周期リフレッシュを回すか。**利用者設定ではない**（診断からしか変えない）。
  final bool autoRefreshEnabled;

  /// 周期リフレッシュの間隔（秒）。**利用者設定ではない。**
  ///
  /// **2026-10-08 に分から秒へ改めた**（`非公開資料:production-sync-small-changes.md`
  /// 「前面同期の短縮」）。旧鍵 `sync.autoRefreshMinutes` は読まない — 全端末が既定値 `15` を
  /// 書き出しているので、引き継ぐと 30 秒への変更がどの端末にも届かない。
  final int autoRefreshSeconds;

  /// ログの水準。**`null` は「ファイルに無い」** で、`--dart-define` の値を使う。
  ///
  /// **語彙の検査はここでしない。** 名前が水準として通るかを知っているのはログの側である。
  final String? logLevel;

  /// ログの書式。**`null` は「ファイルに無い」。**
  final String? logFormat;

  /// 表示テーマ。
  final String theme;

  /// 最後に見ていたタブ。**`null` は先頭のタブ。**
  final String? lastTab;

  /// カーリルの appkey。**端末ごとの上書きで、`null` は「ファイルに無い」。**
  ///
  /// 無ければアプリ同梱値（`--dart-define`）を使う。どちらを採るかを決めるのは合成層である
  /// （`非公開資料:settings-and-parameters.md`）。
  ///
  /// **この値はログにも所見にも出さない。** 落としたときに出すのは鍵の名前だけで、生の値は
  /// 出さない — 他の設定が「直しようがないので値を出す」のと逆にする理由は、ここだけが
  /// 資格情報だからである。同期にもバックアップにも乗らない。
  final String? calilAppkey;

  /// ブラウザー拡張から karita まで届いたことを確かめた日時（UTC・RFC3339）。**`null` は未確認。**
  ///
  /// **端末ごとの事実である**（2026-10-15）。拡張は PC とブラウザーごとに入れるもので、同期にも
  /// バックアップにも乗せない。初回のウィザードの「ブラウザーとつなぐ」を出すかを決める。
  final String? browserLinkedAt;

  /// ［拡張なしで始める］を選んだ日時。**`null` は選んでいない。** 選んでいれば、初回の
  /// ウィザードは出さず、予約・設定の案内だけを残す。
  final String? browserSkippedAt;

  /// 図書館サイトなどを開くブラウザー（[browserChoices] の1つ）。**既定は OS の既定である**
  /// （2026-10-16）。拡張を入れたブラウザーと OS の既定が違う端末のためにある。
  final String browserApp;

  /// 読んだときに落としたもの。**空なら「素直に読めた」である。**
  final List<DeviceSettingIssue> issues;

  /// 読み取った元の文書。**知らない鍵を書き戻しで失わないために持つ。**
  final Map<String, Object?> _raw;

  const DeviceSettings({
    this.autoRefreshEnabled = defaultAutoRefreshEnabled,
    this.autoRefreshSeconds = defaultAutoRefreshSeconds,
    this.logLevel,
    this.logFormat,
    this.theme = defaultTheme,
    this.lastTab,
    this.calilAppkey,
    this.browserLinkedAt,
    this.browserSkippedAt,
    this.browserApp = defaultBrowserApp,
    this.issues = const [],
    Map<String, Object?> raw = const {},
  }) : _raw = raw;

  /// `doctor` の所見にする分。**ログにだけ出すものは落とす。**
  List<DeviceSettingIssue> get reportableIssues =>
      [for (final issue in issues) if (issue.reportable) issue];

  /// 設定を読む。**壊れていても投げない。**
  ///
  /// [configDir] は `AppPaths.configDir` である。ファイル名は [AppLayout.deviceConfig]。
  static DeviceSettings read(String configDir) {
    final file = File(AppLayout.under(configDir, AppLayout.deviceConfig));

    final String text;
    try {
      if (!file.existsSync()) {
        // **所見にしない。** 初回起動がこれである。
        return const DeviceSettings();
      }
      text = file.readAsStringSync();
    } on FileSystemException catch (e) {
      return DeviceSettings(issues: [
        DeviceSettingIssue(DeviceSettingProblem.unreadable, detail: '${e.osError ?? e.message}'),
      ]);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return DeviceSettings(issues: [
        DeviceSettingIssue(DeviceSettingProblem.unreadable, detail: e.message),
      ]);
    }
    if (decoded is! Map<String, Object?>) {
      return DeviceSettings(issues: [
        const DeviceSettingIssue(DeviceSettingProblem.unreadable,
            detail: 'top-level は object である必要があります'),
      ]);
    }

    final issues = <DeviceSettingIssue>[];

    final version = decoded['schemaVersion'];
    if (version is int) {
      if (version > supportedSchemaVersion) {
        // **読める鍵だけ読む。** 起動は止めない。
        issues.add(DeviceSettingIssue(DeviceSettingProblem.schemaAhead,
            key: 'schemaVersion', detail: '$version'));
      }
    } else if (version != null) {
      issues.add(DeviceSettingIssue(DeviceSettingProblem.valueIgnored,
          key: 'schemaVersion', detail: '$version'));
    }

    final sync = _section(decoded, 'sync', issues);
    final log = _section(decoded, 'log', issues);
    final ui = _section(decoded, 'ui', issues);
    final calil = _secretSection(decoded, 'calil', issues);
    final browser = _section(decoded, 'browser', issues);

    return DeviceSettings(
      autoRefreshEnabled: _bool(sync, 'sync.autoRefreshEnabled',
          defaultAutoRefreshEnabled, issues),
      autoRefreshSeconds: _seconds(sync, issues),
      logLevel: _string(log, 'log.level', issues),
      logFormat: _string(log, 'log.format', issues),
      theme: _string(ui, 'ui.theme', issues) ?? defaultTheme,
      lastTab: _string(ui, 'ui.lastTab', issues),
      calilAppkey: _secret(calil, 'calil.appkey', issues),
      browserLinkedAt: _string(browser, 'browser.linkedAt', issues),
      browserSkippedAt: _string(browser, 'browser.skippedAt', issues),
      browserApp: _choice(browser, 'browser.app', browserChoices, issues) ??
          defaultBrowserApp,
      issues: issues,
      raw: decoded,
    );
  }

  /// 値を差し替える。**渡さなかったものは動かない。**
  ///
  /// [lastTab] と [logLevel] を `null` へ戻す口は持たない。戻す操作が要るようになったら、
  /// 「変更なし」と区別できる形で足す。
  DeviceSettings copyWith({
    bool? autoRefreshEnabled,
    int? autoRefreshSeconds,
    String? logLevel,
    String? logFormat,
    String? theme,
    String? lastTab,
    String? browserLinkedAt,
    String? browserSkippedAt,
    String? browserApp,
  }) =>
      DeviceSettings(
        autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,
        autoRefreshSeconds: autoRefreshSeconds ?? this.autoRefreshSeconds,
        logLevel: logLevel ?? this.logLevel,
        logFormat: logFormat ?? this.logFormat,
        theme: theme ?? this.theme,
        lastTab: lastTab ?? this.lastTab,
        // **差し替える口を持たないが、落としもしない。** 再設定の導線は未決である。
        calilAppkey: calilAppkey,
        browserLinkedAt: browserLinkedAt ?? this.browserLinkedAt,
        browserSkippedAt: browserSkippedAt ?? this.browserSkippedAt,
        browserApp: browserApp ?? this.browserApp,
        issues: issues,
        raw: _raw,
      );

  /// 書き戻す。**知らない鍵を残す。**
  ///
  /// **起動時に黙って書き直すためのものではない。** 呼ぶのは設定画面（診断）からの明示的な
  /// 保存だけである。壊れたファイルの上へ保存したときは、読めなかった分が失われる — それが
  /// 「利用者が直した」ということである。
  void write(String configDir) {
    final document = <String, Object?>{
      ..._raw,
      'schemaVersion': supportedSchemaVersion,
      'sync': {
        // **旧鍵は書き戻さない。** 読まない鍵を残すと、ファイルを見た人が効いていると読む。
        for (final entry in _sectionOf(_raw, 'sync').entries)
          if (entry.key != _legacyMinutesKey) entry.key: entry.value,
        'autoRefreshEnabled': autoRefreshEnabled,
        'autoRefreshSeconds': autoRefreshSeconds,
      },
      'log': {
        ..._sectionOf(_raw, 'log'),
        if (logLevel != null) 'level': logLevel,
        if (logFormat != null) 'format': logFormat,
      },
      'ui': {
        ..._sectionOf(_raw, 'ui'),
        'theme': theme,
        if (lastTab != null) 'lastTab': lastTab,
      },
      if (browserLinkedAt != null ||
          browserSkippedAt != null ||
          browserApp != defaultBrowserApp)
        'browser': {
          ..._sectionOf(_raw, 'browser'),
          if (browserLinkedAt != null) 'linkedAt': browserLinkedAt,
          if (browserSkippedAt != null) 'skippedAt': browserSkippedAt,
          'app': browserApp,
        },
    };
    Directory(configDir).createSync(recursive: true);
    File(AppLayout.under(configDir, AppLayout.deviceConfig)).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(document)}\n',
      flush: true,
    );
  }

  /// ログの最初の1行へ載せる分。**値そのものを出す。**
  Map<String, Object?> toLogFields() => {
        'auto_refresh': autoRefreshEnabled,
        'auto_refresh_seconds': autoRefreshSeconds,
        if (logLevel != null) 'config_log_level': logLevel,
        if (logFormat != null) 'config_log_format': logFormat,
      };

  static Map<String, Object?> _sectionOf(Map<String, Object?> raw, String key) {
    final value = raw[key];
    return value is Map<String, Object?> ? value : const {};
  }

  static Map<String, Object?> _section(
      Map<String, Object?> raw, String key, List<DeviceSettingIssue> issues) {
    final value = raw[key];
    if (value == null) return const {};
    if (value is Map<String, Object?>) return value;
    issues.add(DeviceSettingIssue(DeviceSettingProblem.valueIgnored,
        key: key, detail: '$value'));
    return const {};
  }

  /// 資格情報を入れる区画。**形が違っても、中身を所見へ出さない。**
  ///
  /// `"calil": "…"` のように区画ごと書き間違えられたとき、[_section] だと値そのものが
  /// `detail` に載る。**そこに入っているのは鍵そのものでありうる。**
  static Map<String, Object?> _secretSection(
      Map<String, Object?> raw, String key, List<DeviceSettingIssue> issues) {
    final value = raw[key];
    if (value == null) return const {};
    if (value is Map<String, Object?>) return value;
    issues.add(DeviceSettingIssue(DeviceSettingProblem.valueIgnored, key: key));
    return const {};
  }

  /// 資格情報を読む。**落としても値を出さない。**
  ///
  /// 他の設定が生の値を出すのは「伏せると直しようがない」からだが、ここは逆である —
  /// 出す先はログと `doctor` の所見で、どちらも人が見て残る場所である。鍵の名前だけ在れば、
  /// どこを直せばよいかは伝わる。
  static String? _secret(Map<String, Object?> section, String path,
      List<DeviceSettingIssue> issues) {
    final value = section[path.split('.').last];
    if (value == null) return null;
    if (value is String && value.trim().isNotEmpty) return value.trim();
    issues.add(DeviceSettingIssue(DeviceSettingProblem.valueIgnored, key: path));
    return null;
  }

  static bool _bool(Map<String, Object?> section, String path, bool fallback,
      List<DeviceSettingIssue> issues) {
    final value = section[path.split('.').last];
    if (value == null) return fallback;
    if (value is bool) return value;
    issues.add(DeviceSettingIssue(DeviceSettingProblem.valueIgnored,
        key: path, detail: '$value'));
    return fallback;
  }

  static String? _string(Map<String, Object?> section, String path,
      List<DeviceSettingIssue> issues) {
    final value = section[path.split('.').last];
    if (value == null) return null;
    if (value is String && value.trim().isNotEmpty) return value;
    issues.add(DeviceSettingIssue(DeviceSettingProblem.valueIgnored,
        key: path, detail: '$value'));
    return null;
  }

  /// 決まった語彙の1つ。**外れた値は既定へ落とし、ログに出す。**
  static String? _choice(Map<String, Object?> section, String path,
      List<String> allowed, List<DeviceSettingIssue> issues) {
    final value = section[path.split('.').last];
    if (value == null) return null;
    if (value is String && allowed.contains(value)) return value;
    issues.add(DeviceSettingIssue(DeviceSettingProblem.valueIgnored,
        key: path, detail: '$value'));
    return null;
  }

  /// 周期は秒で、**30 秒未満と1日超は受けない。**
  ///
  /// 下限が無いと、設定を書き損じた端末が転送先を叩き続ける。上限が無いと、止まっているのか
  /// 待っているのかが読めなくなる。
  static int _seconds(
      Map<String, Object?> section, List<DeviceSettingIssue> issues) {
    const path = 'sync.autoRefreshSeconds';
    final value = section['autoRefreshSeconds'];
    if (value == null) return defaultAutoRefreshSeconds;
    if (value is int &&
        value >= minAutoRefreshSeconds &&
        value <= maxAutoRefreshSeconds) {
      return value;
    }
    issues.add(DeviceSettingIssue(DeviceSettingProblem.valueIgnored,
        key: path, detail: '$value'));
    return defaultAutoRefreshSeconds;
  }

  /// 2026-10-08 まで使っていた分の鍵。**読まず、書き戻しで消す。**
  static const String _legacyMinutesKey = 'autoRefreshMinutes';
}
