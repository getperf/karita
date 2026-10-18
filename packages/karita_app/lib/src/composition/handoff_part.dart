part of '../composition.dart';

/// 受信の振り分け。拡張・共有から届いたものを用途と地区へ振り分ける。Amazon の受信も持つ。
///
/// **状態（フィールド）は持たない** — 拡張は持てないので、本体（`composition.dart`）に置く。
extension CompositionHandoff on Composition {
  /// マイページ URL の候補。**受信を用途で絞ってから画面へ渡す。**
  ///
  /// **用途を決めるのはこの層である**（`handoff.dart` の宣言）。書籍 URL だけが URL 単体で
  /// 判定でき、残り2つはどちらも「館サイトの一般 URL」で区別がつかない。手がかりは
  /// [HandoffQueue.launch] だけで、**それは候補であって証明ではない。**
  ///
  /// **書籍と Notice はここを通らない。** 予約は段階2、Notice は別タスクの Activity である。
  /// この段で配線したのはマイページ用途の1本だけで、**他の配送は取りに行かれるが行き先が無い**
  /// （この段より前と同じ状態である）。
  Stream<MypageCandidate> get mypageCandidates => handoff.deliveries
      .map((delivery) => mypageCandidateOf(delivery, handoff.launch))
      .where((candidate) => candidate != null)
      .cast<MypageCandidate>();

  /// 用途ヒント・ホスト逆引きまで含めた最終判定。**貸出しタブ・cold start 用の画面が使う。**
  ///
  /// [mypageCandidates] が扱う「一時保持が信頼できるケース」はここでも同じ結果になる
  /// （`MypageUrlScreen` は開いた後の値埋めに引き続き `mypageCandidates` を使うので、あちらは
  /// 残す）。貸出し側は候補確認の専用画面が無い（[LendingCandidate]/[lendingCandidateOf] は
  /// 対称な純関数として残すが、配線は本枠を使う）ため、`LendingRoute` はここだけを見る。
  Stream<HandoffTriage> get handoffTriage => handoff.deliveries
      .map(
        (delivery) =>
            triageOf(delivery, handoff.launch, handoff.latestPurposeHint),
      )
      .where((triage) => triage != null)
      .cast<HandoffTriage>();

  /// [handoffTriage] の判定本体。**優先順位の正本は
  /// `../../../karita-ui-probe/docs/browser-handoff.md` §3。**
  ///
  /// **公開しているのは試験のためである**（`mypageUrlFor`/`checkMypageUrl` と同じ扱い）。
  /// 呼ぶのは通常 [handoffTriage] 経由でよい。
  HandoffTriage? triageOf(
    Handoff delivery,
    LaunchContext? launch,
    DeliveryPurposeHint? hint,
  ) {
    if (delivery is HandoffAmazon) return _amazonTriage(delivery, launch);
    if (delivery is! HandoffWebUrl) return null;
    final url = delivery.url;

    // 1) 一時保持があり、**そのホストが実際に届いた URL と一致し**、目的もヒントと一致
    //    （またはヒント無し）→ 一時保持をそのまま使う。
    //
    // **ホストが違えば、目的が一致していても信用しない。** 一時保持に期限は無いので
    // （決定G）、何日も前の別の館を開いた記録が残っていることがある。目的が偶然同じ
    // （例: どちらも lending）だけでは、それが「今回の往復」だという証拠にならない
    // （実機で確認: 港区の URL で開いたのに、古い江東区の一時保持を使ってしまう不具合）。
    // `LaunchContext.host` は本来この比較のためにある
    // （`../../../karita-ui-probe/docs/browser-handoff.md` §3「共有 URL との違いを示す材料」）。
    //
    // **本棚の記録はここで使わない。** 図書館の URL を本棚の記録で振り分けない。
    final launchMatchesUrl =
        launch != null &&
        launch.purpose != LaunchPurpose.bookshelf &&
        launch.host == url.host;
    if (launchMatchesUrl && (hint == null || _matches(hint, launch.purpose))) {
      return _libraryCandidate(
        launch.purpose,
        launch.systemId,
        url,
        launch.startedAt,
      );
    }

    // 2)&3) ヒントがある（一時保持と不一致、または一時保持が無い）→ ヒントの用途を採り、
    //        対象地区はホスト逆引きへ（一時保持の systemId は一切見ない）。
    if (hint != null) {
      final purpose = _purposeOf(hint);
      final matches = systemIdsByMypageHost(url.host);
      if (matches.length == 1) {
        return _libraryCandidate(purpose, matches.single, url, DateTime.now());
      }
      return DistrictChoiceNeeded(purpose, url, matches);
    }

    // 4) 一時保持もヒントも無い → 従来どおり手動選択。
    return PurposeChoiceNeeded(url);
  }

  HandoffTriage _libraryCandidate(
    LaunchPurpose purpose,
    String systemId,
    Uri url,
    DateTime startedAt,
  ) => switch (purpose) {
    LaunchPurpose.lending => LendingTriageCandidate(systemId, startedAt),
    LaunchPurpose.mypageUrl => MypageTriageCandidate(systemId, url, startedAt),
    // 呼び手が弾いているので来ない。来ても本棚へは振らず、利用者に選ばせる。
    LaunchPurpose.bookshelf => PurposeChoiceNeeded(url),
  };

  /// Amazon の受信の着地。**記録を消さない** — この関数は配送1件につき複数回呼ばれる
  /// （[handoffTriage] の map と、`PendingHandoffTriage` の pull 読み直し）。消すのは
  /// 配った側である。
  HandoffTriage _amazonTriage(HandoffAmazon delivery, LaunchContext? launch) {
    if (launch != null && launch.purpose == LaunchPurpose.bookshelf) {
      return ShelfReturnCandidate(launch.bookId, launch.startedAt);
    }
    final isbn13 = delivery.isbn13;
    if (isbn13 == null) return AmazonNoIsbn(delivery.shape);
    ReservationBook? found;
    try {
      found = findReservationBook(isbn13);
    } on ReservationIssue {
      // 同じ ISBN が複数ある。どれかを選ばず、下書きが重複の警告を出す。
      found = null;
    }
    if (found != null) return ShelfBookFound(found.id);
    return ShelfBookDraft(
      HandoffBook(isbn13, Uri(scheme: 'https', host: delivery.host, path: '/')),
    );
  }

  /// 本棚の［Amazonで見る］。**開く前に元の画面を記録する。**
  ///
  /// 記録するのはホストと本だけである（`openLibrarySite` と同じく URL 全文を持たない）。
  /// 起動に失敗したら今回の記録を捨てる。
  Future<void> openAmazon(Uri url, {String? bookId}) async {
    handoff.remember(
      LaunchContext(
        purpose: LaunchPurpose.bookshelf,
        systemId: '',
        host: url.host,
        startedAt: DateTime.now(),
        bookId: bookId,
      ),
    );
    _log.info('bookshelf.amazon.opened', {
      'from': bookId == null ? 'list' : 'record',
    });
    try {
      await openSite(url);
    } catch (error) {
      handoff.clearLaunch();
      _log.warning('bookshelf.amazon.open.failed', {
        'reason': error.runtimeType.toString(),
      });
      rethrow;
    }
  }

  bool _matches(DeliveryPurposeHint hint, LaunchPurpose purpose) =>
      switch ((hint, purpose)) {
        (DeliveryPurposeHint.lending, LaunchPurpose.lending) => true,
        (DeliveryPurposeHint.mypageUrl, LaunchPurpose.mypageUrl) => true,
        _ => false,
      };

  LaunchPurpose _purposeOf(DeliveryPurposeHint hint) => switch (hint) {
    DeliveryPurposeHint.lending => LaunchPurpose.lending,
    DeliveryPurposeHint.mypageUrl => LaunchPurpose.mypageUrl,
  };

  /// URL のホストから、取り込み値・既定値のマイページ URL が一致する図書館を逆引きする。
  ///
  /// **`homepageUrl`（公式サイト）は使わない**（2026-09-28 実証。5館 fixture で `official` は
  /// 2/5館ホスト不一致 — `../../../karita-ui-probe/docs/library-site-url.md`）。**公開している
  /// のは試験のためである。**
  List<String> systemIdsByMypageHost(String host) {
    final normalized = host.toLowerCase();
    final imported = <String, String>{
      for (final setting in LibrarySettings(domain).load())
        if (setting.key == settingMypageUrl) setting.systemId: setting.value,
    };
    final matches = <String>[];
    for (final system in LibrarySystems(domain).load().librarySystems) {
      final candidates = [
        imported[system.id],
        mypageDefaults.urlFor(system.id),
      ];
      for (final candidate in candidates) {
        if (candidate == null || candidate.isEmpty) continue;
        final parsed = Uri.tryParse(candidate);
        if (parsed != null && parsed.host.toLowerCase() == normalized) {
          matches.add(system.id);
          break;
        }
      }
    }
    return matches;
  }
}
