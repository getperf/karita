part of '../composition.dart';

/// 図書館管理。図書館の登録・分館の更新・蔵書照会。
///
/// **状態（フィールド）は持たない** — 拡張は持てないので、本体（`composition.dart`）に置く。
extension CompositionLibraries on Composition {
  LibrarySystems get librarySystems => LibrarySystems(domain);

  // --- 図書館管理の画面へ出す口 -------------------------------------------
  //
  // **画面はここだけを見る。** [domain] も [librarySystems] も公開されたままだが、
  // 画面から `LibrarySettings(domain)` を組まない — 組んだ時点で、集約の境界と
  // トランザクションの単位を画面が知ることになる
  // （`非公開資料:ui-state-model.md` §3.1）。
  //
  // **どれも読み直す。** 画面用のキャッシュをここに作らない。相乗りは Riverpod の
  // `family` が持つ側である（同 §3.1）。

  /// 登録済みの図書館システム。**失敗は [AppIssue]。0件は正常な結果である。**
  ///
  /// **`FINE` で1行出す。** 台帳を読み直した回数と件数が追えないと、「一覧が変わらない」の
  /// 原因が読込にあるのか、そもそも書かれていないのかを切り分けられない。
  List<LibrarySystem> loadLibraries() {
    try {
      final systems = readLibrarySystems(domain);
      _log.fine('libraries.loaded', {
        'systems': systems.length,
        'branches': systems.fold<int>(0, (n, s) => n + s.branches.length),
      });
      return systems;
    } on AppIssue catch (issue) {
      _log.warning('libraries.load.failed', {'code': issue.code});
      rethrow;
    }
  }

  /// 常用館1件。**未設定・解決済み・参照切れの3つに分かれる。**
  PreferredBranch preferredBranchFor(String systemId) {
    final branch = readPreferredBranch(domain, systemId);
    // **参照切れだけを出す。** 正常な読み取りは件数で足りており、毎回出すと一覧の描画のたびに
    // 館の数だけ行が増える。
    if (branch.state == PreferredBranchState.dangling) {
      _log.fine('library.preferred_branch.dangling', {'system': systemId});
    }
    return branch;
  }

  /// 削除で残るものの勘定。**消さずに数えるだけである。**
  LibraryRemovalImpact removalImpactFor(String systemId) =>
      readRemovalImpact(domain, systemId);

  CalilLibraryClient _requireLibraryClient() {
    if (!calilKey.usable) {
      // **401 は起きない**（2026-09-16 実測）。出る失敗はこれと通信失敗の2つだけである。
      throw const AppIssue(
        'calil-key-missing',
        'No Calil appkey is configured on this device.',
      );
    }
    return _libraryClient ??= CalilLibraryClient(appkey: calilKey.key);
  }

  HoldingsLookup? get holdings {
    if (_closed || !calilKey.usable) return null;
    return _holdings ??= HoldingsLookup(CalilCheckClient(appkey: calilKey.key));
  }

  /// 蔵書を照会する。**記録を付けるためにここを通す。**
  ///
  /// `fetchBytes` が1回の取得ごとに `api.fetch provider=calil op=check` を出すが、それは
  /// **外へ出た分しか出ない。** 「押したのに何も起きない」を切り分けるには、押した事実と
  /// 結末のほうが要る — 対象が0冊だったのか、上限で止めたのか、そもそも走らなかったのか。
  ///
  /// **[lookup] を受け取る。** ここで [holdings] を自分で解決しない — 行のバッジが読むのと
  /// **同じ入れ物へ書き込む**ことが要るからである。別に解決すると、口を差し替えた画面が
  /// 「走ったのに何も出ない」になる。
  ///
  /// **冊数と館数しか出さない。** ISBN も書名も出さない（`logging-and-diagnostics.md`）。
  Future<HoldingsRunResult> checkHoldings({
    required HoldingsLookup? lookup,
    required List<String> isbn13s,
    required List<String> systemIds,
    void Function()? onProgress,
  }) async {
    if (lookup == null) {
      _log.fine('holdings.check.unavailable');
      return const HoldingsRunResult(outcome: HoldingsRunOutcome.nothingToDo);
    }
    _log.fine('holdings.check.started', {
      'books': isbn13s.length,
      'systems': systemIds.length,
    });
    final HoldingsRunResult result;
    try {
      result = await lookup.check(
        isbn13s: isbn13s,
        systemIds: systemIds,
        onProgress: onProgress,
      );
    } catch (error) {
      // **握り潰さない。** ここで落ちると画面が「確認中」のまま残る。
      _log.warning('holdings.check.failed', {'error': error.runtimeType});
      return const HoldingsRunResult(outcome: HoldingsRunOutcome.failed);
    }
    _log.info('holdings.check.done', {
      'outcome': result.outcome.name,
      'chunks': result.chunks,
      'requests': result.bookRequests,
    });
    return result;
  }

  /// 都道府県まるごとの候補を取る。**通信はここ1回だけである。**
  ///
  /// 絞込みは端末側（`filterSystems`）で、市区町村を間に挟まない。`/library` は自由語検索を
  /// 持たないので、**この段取りは UI の好みではなく API の制約である**
  /// （`非公開資料:external-data-access.md` の 2026-09-15 決定）。
  ///
  /// **取った直後に、登録済みの分を取り直す**（[refreshRegisteredFrom]）。別の要求は足さない。
  Future<LibraryCandidates> libraryCandidates(String pref) async {
    _requireOpen();
    final result = await _requireLibraryClient().listByPref(pref);
    final failure = result.failure;
    if (failure != null) {
      throw AppIssue(
        'calil-library-failed',
        'Library candidates could not be fetched (${failure.name}).',
      );
    }
    _log.fine('library.candidates.loaded', {
      'systems': result.systems.length,
      'truncated': result.truncated,
      'rejected': result.rejectedSystemIds.length,
    });
    // **取ってきたついでに洗い替える。** 失敗させない — 候補を出すほうが主で、取り直しは
    // おまけである。
    try {
      if (!result.truncated &&
          !result.incomplete &&
          result.rejectedSystemIds.isEmpty) {
        await refreshRegisteredFrom(result.systems);
      }
    } on AppIssue catch (issue) {
      _log.warning('library.refresh.failed', {'code': issue.code});
    }
    return LibraryCandidates(
      systems: result.systems,
      truncated: result.truncated,
    );
  }

  /// Refresh one registered system. Missing/partial responses never erase data.
  Future<int> refreshLibraryBranches(String systemId) async {
    _requireOpen();
    final token = ledgerSessionToken;
    final current = librarySystems.read(systemId);
    if (current == null) {
      throw const AppIssue(
        'library-missing',
        'Library is no longer registered.',
      );
    }
    final result = await _requireLibraryClient().listByPref(
      current.pref,
      city: current.city,
    );
    _requireOpen();
    if (!identical(token, ledgerSessionToken)) {
      throw const AppIssue('session-changed', 'The ledger has changed.');
    }
    final matches = result.systems
        .where((s) => s.systemId == systemId)
        .toList();
    if (result.failure != null ||
        result.truncated ||
        result.incomplete ||
        result.rejectedSystemIds.isNotEmpty ||
        matches.length != 1 ||
        matches.single.branches.isEmpty ||
        matches.single.branches.map((b) => b.id).toSet().length !=
            matches.single.branches.length ||
        prepareCandidate(librarySystems.load(), matches.single) == null) {
      throw const AppIssue(
        'library-refresh-incomplete',
        'A complete branch list could not be obtained.',
      );
    }
    if (librarySystems.read(systemId) == null) {
      throw const AppIssue(
        'library-missing',
        'Library is no longer registered.',
      );
    }
    return refreshRegisteredFrom(matches);
  }

  /// 候補1件を登録する。**登録と更新は同じ口である。**
  Future<void> registerLibrary(LibrarySystemCandidate candidate) async {
    _requireOpen();
    final prepared = prepareCandidate(LibrarySystems(domain).load(), candidate);
    if (prepared == null) {
      throw const AppIssue(
        'library-system',
        'This library cannot be registered (no branch or no city).',
      );
    }
    _write('library.registered', candidate.systemId, () {
      LibrarySystems(domain).register(system: prepared, now: nowUtc());
    }, fields: {'branches': prepared.branches.length});
    _syncAfterWrite('library.registered');
  }

  /// 応答に居る**登録済みの**システムを、違っていたら書き直す。
  ///
  /// **違うときだけ書く**（2026-09-17 決定）。再登録は同期する書込みで、集約の版が上がって
  /// 封筒が outbox へ積まれ、他端末へ伝わって LWW に乗る。**変わっていないのに積まない。**
  ///
  /// **比べるのは「書こうとしている値」である**（[prepareCandidate]）。生の候補と比べると、
  /// `homepageUrl` を手で直した端末では毎回「違う」になる。
  ///
  /// **利用者値は触らない**（`0011`）。分館が消えれば常用館は参照切れになり、その表示は既に在る。
  ///
  /// 書き直した件数を返す。
  Future<int> refreshRegisteredFrom(
    List<LibrarySystemCandidate> candidates,
  ) async {
    _requireOpen();
    final systems = LibrarySystems(domain);
    var checked = 0;
    var updated = 0;
    for (final candidate in candidates) {
      final current = systems.read(candidate.systemId);
      if (current == null) continue; // 登録していないものは触らない。
      checked++;
      final prepared = prepareCandidate(systems.load(), candidate);
      if (prepared == null) continue;
      // API ordering is not a catalog change. Compare both sides by branch ID.
      final oldBranches = [...current.branches]
        ..sort((a, b) => a.id.compareTo(b.id));
      final newBranches = [...prepared.branches]
        ..sort((a, b) => a.id.compareTo(b.id));
      if (current.copyWith(branches: oldBranches) ==
          prepared.copyWith(branches: newBranches))
        continue;
      runLibraryWrite(() => systems.register(system: prepared, now: nowUtc()));
      updated++;
    }
    if (checked > 0) {
      _log.info('library.refreshed', {'checked': checked, 'updated': updated});
    }
    if (updated > 0) _syncAfterWrite('library.refreshed');
    return updated;
  }
}
