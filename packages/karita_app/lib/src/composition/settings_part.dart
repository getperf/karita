part of '../composition.dart';

/// 設定と端末ごとの記録。テーマ・開くブラウザー・拡張との連携。
/// **端末設定（`device.json`）を書くのはここだけである。**
///
/// **状態（フィールド）は持たない** — 拡張は持てないので、本体（`composition.dart`）に置く。
extension CompositionSettings on Composition {
  /// 変更する鍵だけ受ける。失敗した値を現在設定として公開しない。
  void saveTheme(String value) {
    _requireOpen();
    if (!const ['system', 'light', 'dark'].contains(value)) {
      throw const AppIssue('theme-invalid', 'Expected system, light or dark.');
    }
    final next = _settings.copyWith(theme: value);
    try {
      next.write(paths.configDir);
    } on FileSystemException catch (error) {
      // OS の数値だけ。パスやファイル内容は公開しない。
      final code = error.osError?.errorCode;
      _log.warning('settings.theme.save.failed', {'os': code ?? 'unknown'});
      throw AppIssue(
        'settings-write',
        'Device settings could not be saved (OS ${code ?? "unknown"}).',
      );
    }
    // 明示保存で修復した所見も、現在のファイルから取り直す。
    _settings = DeviceSettings.read(paths.configDir);
    _log.info('settings.theme.saved', {'theme': _settings.theme});
    _settingsChanges.add(_settings.theme);
  }

  /// ブラウザーとつなぐ段を持つ端末か。**Windows の本番だけである**（2026-10-15）。
  ///
  /// Android は共有メニューから送るので拡張が要らない。デモは台帳が使い捨てで、端末設定へ
  /// 書く理由が無い。
  bool get browserLinkApplicable => Platform.isWindows && !mode.isDemo;

  /// 開くブラウザー（[browserChoices] の1つ）。**端末ごとの設定である**（`device.json`）。
  String get browserChoice => _settings.browserApp;

  /// 見つかったブラウザー。**探せなければ空。**
  Future<Set<String>> installedBrowsers() => browserLinkApplicable
      ? browsers.installed()
      : Future.value(const <String>{});

  /// 開くブラウザーを保存する。**変わったことは [browserLinkChanges] で知らせる。**
  void saveBrowserChoice(String value) {
    _requireOpen();
    if (!browserChoices.contains(value)) {
      throw AppIssue(
        'browser-choice-invalid',
        'Expected one of ${browserChoices.join(', ')}.',
      );
    }
    _saveSettings(
      _settings.copyWith(browserApp: value),
      'settings.browser_choice.saved',
    );
    _browserLinkChanges.add(null);
  }

  /// 選んだブラウザーで開く。**開けなければ OS の既定で開き直す** — 図書館サイトへ行けない
  /// ことのほうが、拡張の無いブラウザーで開くことより困る。
  ///
  /// **画面からブラウザーを開くときは、[openBrowser] ではなくこれを呼ぶ。** [openBrowser] は
  /// サインインと同じ OS の既定の口で、選択が効かない。
  Future<void> openSite(Uri url) async {
    final choice = _settings.browserApp;
    // **選べない端末は [NoBrowserLauncher] が投げ、OS の既定へ落ちる。** 端末で分けない。
    if (choice == systemBrowser) {
      await openBrowser(url);
      return;
    }
    try {
      await browsers.open(choice, url);
    } catch (error) {
      _log.warning('browser.choice.open.failed', {
        'browser': choice,
        'reason': error.runtimeType.toString(),
      });
      await openBrowser(url);
    }
  }

  /// 拡張から karita まで届いたことを確かめたか。**端末ごとの事実である**（`device.json`）。
  bool get browserLinked => _settings.browserLinkedAt != null;

  /// ［拡張なしで始める］を選んだか。選んでいれば初回のウィザードは出さない。
  bool get browserLinkSkipped => _settings.browserSkippedAt != null;

  /// 連携の状態が変わった。**確認ページが届いたとき・見送ったときに出る。**
  Stream<void> get browserLinkChanges => _browserLinkChanges.stream;

  /// ［拡張なしで始める］。**確認は取り消さない** — 後から確認できれば、それが勝つ。
  void skipBrowserLink() {
    _requireOpen();
    _saveSettings(
      _settings.copyWith(browserSkippedAt: nowUtc()),
      'settings.browser_link.skipped',
    );
    _browserLinkChanges.add(null);
  }

  /// 確認ページが届いたら記録する。**ウィザードの外で届いても記録する** — 設定画面から
  /// 確かめ直す場合も、利用者が自分で確認ページを送った場合も同じ事実である。
  void _watchBrowserLink() {
    _linkChecks = handoff.deliveries.where((d) => d is HandoffLinkCheck).listen(
      (_) {
        if (_closed) return;
        try {
          _saveSettings(
            _settings.copyWith(browserLinkedAt: nowUtc()),
            'settings.browser_link.linked',
          );
        } on AppIssue {
          // **書けなくても届いた事実は画面へ伝える。** 次の起動でもう一度確かめればよい。
        }
        _browserLinkChanges.add(null);
      },
    );
  }

  /// 端末設定を書いて読み直す。**[saveTheme] と同じ手順である。**
  void _saveSettings(DeviceSettings next, String event) {
    try {
      next.write(paths.configDir);
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      _log.warning('$event.failed', {'os': code ?? 'unknown'});
      throw AppIssue(
        'settings-write',
        'Device settings could not be saved (OS ${code ?? "unknown"}).',
      );
    }
    _settings = DeviceSettings.read(paths.configDir);
    _log.info(event);
  }
}
