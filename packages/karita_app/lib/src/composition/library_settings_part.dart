part of '../composition.dart';

/// 図書館ごとの設定。マイページ URL・常用館・図書館サイトを開く・図書館の削除。
///
/// **状態（フィールド）は持たない** — 拡張は持てないので、本体（`composition.dart`）に置く。
extension CompositionLibrarySettings on Composition {
  /// 出典つきで解決したマイページ URL。**順序は `karita_domain` の純関数が持つ。**
  ///
  /// 取り込み値（`LibrarySetting`）→ 既定値表 → 公式サイト（カタログの `homepage_url`）→
  /// 未設定。**出典を保存しない** — 「保存値があるか」だけで決まる。
  ///
  /// **読めなければ [AppIssue] を投げる。** 画面が出典を出す値なので、台帳が読めなかったことを
  /// `未設定` に潰さない — 「取り込んだ値が消えた」に見える。
  MypageUrl mypageUrlFor(String systemId) {
    final LibrarySetting? imported;
    final String? homepageUrl;
    try {
      imported = LibrarySettings(domain).read(systemId, settingMypageUrl);
      homepageUrl = LibrarySystems(domain).read(systemId)?.homepageUrl;
    } catch (error) {
      throw AppIssue(
        'library-setting-load',
        'Library settings could not be read (${error.runtimeType}).',
      );
    }
    return resolveMypageUrl(
      imported: imported?.value,
      importedCheckedOn: imported?.checkedOn,
      bundled: mypageDefaults.urlFor(systemId),
      bundledCheckedOn: mypageDefaults.checkedOn,
      homepageUrl: homepageUrl,
    );
  }

  /// 図書館サイトを開き、**戻ってきた URL の宛先を覚えておく。**
  ///
  /// 開くのは解決済みのマイページ URL（取り込み値 → 既定値 → 公式サイト）。**未設定なら
  /// 開けない** — 行き先が無い。
  ///
  /// **起動の成功はページ表示でもログイン成功でもない**。
  /// 失敗が分かったら今回の候補を捨てる。
  /// **以前の候補を復活させない。**
  Future<void> openLibrarySite(
    String systemId, {
    // **用途は呼び手が決める。** URL の解決も起動も同じだが、置いてくる候補の意味が違う —
    // `mypageCandidateOf` はこの値で受信を弾くので、貸出しの往復はマイページ候補にならない。
    LaunchPurpose purpose = LaunchPurpose.mypageUrl,
  }) async {
    _requireOpen();
    final resolved = mypageUrlFor(systemId);
    final value = resolved.value;
    if (value == null || value.isEmpty) {
      throw const AppIssue(
        'mypage-url-unset',
        'No URL is available for this library.',
      );
    }
    final url = Uri.tryParse(value);
    if (url == null || !url.hasAuthority) {
      throw const AppIssue(
        'mypage-url-broken',
        'The stored URL is not usable.',
      );
    }
    handoff.remember(
      LaunchContext(
        purpose: purpose,
        systemId: systemId,
        // **ホストだけを持つ。** 起動 URL 全文は一時保持にも診断にも残さない。
        host: url.host,
        startedAt: DateTime.now(),
      ),
    );
    _log.info('library.site.opened', {
      'system': systemId,
      'purpose': purpose.name,
    });
    try {
      await openSite(url);
    } catch (error) {
      handoff.clearLaunch();
      _log.warning('library.site.open.failed', {
        'system': systemId,
        'reason': error.runtimeType.toString(),
      });
      throw const AppIssue(
        'browser-open',
        'The browser could not be opened on this device.',
      );
    }
  }

  /// 保存してよいかを検査する。**保存はしない。**
  ///
  /// 比べる相手は**既定値または公式サイト**で、取り込み値とは比べない — 比べたい問いは
  /// 「この URL は本当にこの館のものか」であって「前と同じか」ではない。
  MypageUrlCheck checkMypageUrl(String systemId, Uri url) {
    final bundled = mypageDefaults.urlFor(systemId);
    final homepage = LibrarySystems(domain).read(systemId)?.homepageUrl;
    final compareTo = Uri.tryParse(
      (bundled != null && bundled.isNotEmpty) ? bundled : (homepage ?? ''),
    );
    final usable = compareTo != null && compareTo.hasAuthority
        ? compareTo
        : null;
    return MypageUrlCheck(checkSaveableUrl(url, compareTo: usable), usable);
  }

  /// マイページ URL を保存する。**検査に通らない値は書かない。**
  ///
  /// **警告は保存を止めない**（別ホストは外部 OPAC への正常な遷移でも起こる）。止めるのは
  /// http(s) 以外・userinfo つき・既知のセッションキーの3つである。
  ///
  /// **`checked_on` は利用者が取り込んだ日である**（既定値の採取日ではない）。UTC の日付を
  /// 採る — 台帳の他の時刻と同じ基準にする。
  Future<void> saveMypageUrl(String systemId, Uri url) async {
    _requireOpen();
    final check = checkMypageUrl(systemId, url);
    if (!check.saveable) {
      throw AppIssue(
        'mypage-url-rejected',
        'The URL cannot be saved (${check.issues.map((i) => i.name).join(',')}).',
      );
    }
    _write('library.mypage_url.set', systemId, () {
      LibrarySettings(domain).setMypageUrl(
        systemId: systemId,
        url: url.toString(),
        checkedOn: nowUtc().split('T').first,
        now: nowUtc(),
      );
    }, fields: {'host': url.host});
    // **確定したので候補を消費する。** 受信画面を閉じただけ・候補を拒否しただけでは消さない。
    handoff.consume();
    _syncAfterWrite('library.mypage_url.set');
  }

  /// 取り込み値を捨てる。**「未設定」ではなく、既定値表・公式サイトへ戻ることを意味する。**
  Future<void> clearMypageUrl(String systemId) async {
    _requireOpen();
    _write('library.mypage_url.cleared', systemId, () {
      LibrarySettings(domain).clearMypageUrl(systemId: systemId, now: nowUtc());
    });
    _syncAfterWrite('library.mypage_url.cleared');
  }

  /// 常用館を保存する。**分館一覧に在ることは業務側が要求する。**
  ///
  /// **保存と解除は別の口である**（`LibrarySettings` の宣言）。`null` を渡して解除する形に
  /// すると「変更なし」と「外す」が同じ値になる。
  /// 端末内への保存で完了する。同期は継続し、その完了を画面に待たせない。
  Future<void> savePreferredBranch(String systemId, String branchId) async {
    _requireOpen();
    _write('library.preferred_branch.set', systemId, () {
      LibrarySettings(domain).setPreferredBranch(
        systemId: systemId,
        branchId: branchId,
        now: nowUtc(),
      );
    });
    _syncAfterWrite('library.preferred_branch');
  }

  /// 常用館を未設定へ戻す。**個別に指定した受取館は変わらない。**
  Future<void> clearPreferredBranch(String systemId) async {
    _requireOpen();
    _write('library.preferred_branch.cleared', systemId, () {
      LibrarySettings(
        domain,
      ).clearPreferredBranch(systemId: systemId, now: nowUtc());
    });
    _syncAfterWrite('library.preferred_branch');
  }

  /// 図書館システムを削除する。**tombstone として他端末へ伝わる。**
  ///
  /// 事故ではなく期待した動作である（`非公開資料:libraries-in-sqlite.md` 4）。
  /// 残るもの（棚卸記録・Loan・利用者値の行）は [removalImpactFor] が数える。
  Future<void> removeLibrarySystem(String systemId) async {
    _requireOpen();
    // **残るものを削除の行に載せる。** 後から「何が残ったのか」を聞かれたときに、
    // 台帳を引き直さずに答えられる。
    final impact = removalImpactFor(systemId);
    _write('library.removed', systemId, () {
      LibrarySystems(domain).remove(systemId: systemId, now: nowUtc());
    }, fields: {'memberships': impact.memberships, 'loans': impact.loans});
    _syncAfterWrite('library.removed');
  }

  /// 業務の書込みを1本、記録つきで通す。**成功も失敗も1行ずつ出る。**
  ///
  /// **`INFO` である。** 台帳を変えた事実は既定の水準で残す — 後から「いつ誰が変えたか」を
  /// 問えるのはログだけで、`doctor` は所見しか持たない。
  void _write(
    String event,
    String systemId,
    void Function() body, {
    Map<String, Object?> fields = const {},
  }) {
    try {
      runLibraryWrite(body);
    } on AppIssue catch (issue) {
      // **メッセージを出さない。** 業務の文言は画面が出す側で、ログに要るのは分類である。
      _log.warning('$event.failed', {'system': systemId, 'code': issue.code});
      rethrow;
    }
    _log.info(event, {'system': systemId, ...fields});
  }
}
