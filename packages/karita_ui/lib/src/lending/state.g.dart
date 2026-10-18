// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 初期画面と詳細の行き来。**Navigator ではなく状態で持つ**（図書館管理と同じ前例）。
///
/// **`keepAlive` にする。** 幅で外殻が入れ替わる一瞬に捨てられると、詳細を見ていた利用者が
/// 初期画面へ戻される。**セッション交換では捨てる** — [build] が `compositionProvider` を
/// watch している。

@ProviderFor(LendingRoute)
final lendingRouteProvider = LendingRouteProvider._();

/// 初期画面と詳細の行き来。**Navigator ではなく状態で持つ**（図書館管理と同じ前例）。
///
/// **`keepAlive` にする。** 幅で外殻が入れ替わる一瞬に捨てられると、詳細を見ていた利用者が
/// 初期画面へ戻される。**セッション交換では捨てる** — [build] が `compositionProvider` を
/// watch している。
final class LendingRouteProvider
    extends $NotifierProvider<LendingRoute, LendingRouteState> {
  /// 初期画面と詳細の行き来。**Navigator ではなく状態で持つ**（図書館管理と同じ前例）。
  ///
  /// **`keepAlive` にする。** 幅で外殻が入れ替わる一瞬に捨てられると、詳細を見ていた利用者が
  /// 初期画面へ戻される。**セッション交換では捨てる** — [build] が `compositionProvider` を
  /// watch している。
  LendingRouteProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lendingRouteProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lendingRouteHash();

  @$internal
  @override
  LendingRoute create() => LendingRoute();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LendingRouteState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LendingRouteState>(value),
    );
  }
}

String _$lendingRouteHash() => r'15dea0233d170fabeab7e94ce57dc0c501cb298e';

/// 初期画面と詳細の行き来。**Navigator ではなく状態で持つ**（図書館管理と同じ前例）。
///
/// **`keepAlive` にする。** 幅で外殻が入れ替わる一瞬に捨てられると、詳細を見ていた利用者が
/// 初期画面へ戻される。**セッション交換では捨てる** — [build] が `compositionProvider` を
/// watch している。

abstract class _$LendingRoute extends $Notifier<LendingRouteState> {
  LendingRouteState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LendingRouteState, LendingRouteState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LendingRouteState, LendingRouteState>,
              LendingRouteState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 一括取消の選択。**区を出ると消える。**
///
/// **取消を一括にしたのはモックに合わせたからである**（2026-09-20）。行の操作列は4つの状態と
/// 期限で埋まっていて（`.book-controls` は `repeat(4, minmax(0, 1fr)) 76px`）、5つ目を足すと
/// 440dp 未満でどれも1〜2文字まで潰れる。取消がまとまって出るのは予約中の棚卸であり、
/// 1件ずつではない。**返却は行内に残す** — モック自身がそう言っている（`renderActionBar` の
/// 「返却は行内で完結するので、バーの一括操作は取消だけを扱う」）。
///
/// **[build] が [lendingRouteProvider] を watch している。** 初期画面へ戻ると選択は空へ戻り、
/// **後始末を呼び手ごとに書かなくてよい**（`LibrariesRoute` の `_returnTo` と同じ考え方）。

@ProviderFor(LendingSelection)
final lendingSelectionProvider = LendingSelectionProvider._();

/// 一括取消の選択。**区を出ると消える。**
///
/// **取消を一括にしたのはモックに合わせたからである**（2026-09-20）。行の操作列は4つの状態と
/// 期限で埋まっていて（`.book-controls` は `repeat(4, minmax(0, 1fr)) 76px`）、5つ目を足すと
/// 440dp 未満でどれも1〜2文字まで潰れる。取消がまとまって出るのは予約中の棚卸であり、
/// 1件ずつではない。**返却は行内に残す** — モック自身がそう言っている（`renderActionBar` の
/// 「返却は行内で完結するので、バーの一括操作は取消だけを扱う」）。
///
/// **[build] が [lendingRouteProvider] を watch している。** 初期画面へ戻ると選択は空へ戻り、
/// **後始末を呼び手ごとに書かなくてよい**（`LibrariesRoute` の `_returnTo` と同じ考え方）。
final class LendingSelectionProvider
    extends $NotifierProvider<LendingSelection, LendingSelectionState> {
  /// 一括取消の選択。**区を出ると消える。**
  ///
  /// **取消を一括にしたのはモックに合わせたからである**（2026-09-20）。行の操作列は4つの状態と
  /// 期限で埋まっていて（`.book-controls` は `repeat(4, minmax(0, 1fr)) 76px`）、5つ目を足すと
  /// 440dp 未満でどれも1〜2文字まで潰れる。取消がまとまって出るのは予約中の棚卸であり、
  /// 1件ずつではない。**返却は行内に残す** — モック自身がそう言っている（`renderActionBar` の
  /// 「返却は行内で完結するので、バーの一括操作は取消だけを扱う」）。
  ///
  /// **[build] が [lendingRouteProvider] を watch している。** 初期画面へ戻ると選択は空へ戻り、
  /// **後始末を呼び手ごとに書かなくてよい**（`LibrariesRoute` の `_returnTo` と同じ考え方）。
  LendingSelectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lendingSelectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lendingSelectionHash();

  @$internal
  @override
  LendingSelection create() => LendingSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LendingSelectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LendingSelectionState>(value),
    );
  }
}

String _$lendingSelectionHash() => r'e90cf1b2c6539ed4230dfe4619aea6541a75d556';

/// 一括取消の選択。**区を出ると消える。**
///
/// **取消を一括にしたのはモックに合わせたからである**（2026-09-20）。行の操作列は4つの状態と
/// 期限で埋まっていて（`.book-controls` は `repeat(4, minmax(0, 1fr)) 76px`）、5つ目を足すと
/// 440dp 未満でどれも1〜2文字まで潰れる。取消がまとまって出るのは予約中の棚卸であり、
/// 1件ずつではない。**返却は行内に残す** — モック自身がそう言っている（`renderActionBar` の
/// 「返却は行内で完結するので、バーの一括操作は取消だけを扱う」）。
///
/// **[build] が [lendingRouteProvider] を watch している。** 初期画面へ戻ると選択は空へ戻り、
/// **後始末を呼び手ごとに書かなくてよい**（`LibrariesRoute` の `_returnTo` と同じ考え方）。

abstract class _$LendingSelection extends $Notifier<LendingSelectionState> {
  LendingSelectionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LendingSelectionState, LendingSelectionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LendingSelectionState, LendingSelectionState>,
              LendingSelectionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 貸出し一覧。**読み直す契機を2つに絞った Notifier である。**
///
/// **`keepAlive` にする。** 外殻の `IndexedStack` が本文を生かしたままにしているので、
/// タブを移って戻ってきても一覧は読み直されない — それがこの段の狙いそのものである。

@ProviderFor(Lending)
final lendingProvider = LendingProvider._();

/// 貸出し一覧。**読み直す契機を2つに絞った Notifier である。**
///
/// **`keepAlive` にする。** 外殻の `IndexedStack` が本文を生かしたままにしているので、
/// タブを移って戻ってきても一覧は読み直されない — それがこの段の狙いそのものである。
final class LendingProvider extends $NotifierProvider<Lending, LendingState> {
  /// 貸出し一覧。**読み直す契機を2つに絞った Notifier である。**
  ///
  /// **`keepAlive` にする。** 外殻の `IndexedStack` が本文を生かしたままにしているので、
  /// タブを移って戻ってきても一覧は読み直されない — それがこの段の狙いそのものである。
  LendingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lendingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lendingHash();

  @$internal
  @override
  Lending create() => Lending();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LendingState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LendingState>(value),
    );
  }
}

String _$lendingHash() => r'09027eeac55798e6edef67ed207518e8b990765e';

/// 貸出し一覧。**読み直す契機を2つに絞った Notifier である。**
///
/// **`keepAlive` にする。** 外殻の `IndexedStack` が本文を生かしたままにしているので、
/// タブを移って戻ってきても一覧は読み直されない — それがこの段の狙いそのものである。

abstract class _$Lending extends $Notifier<LendingState> {
  LendingState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LendingState, LendingState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LendingState, LendingState>,
              LendingState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 詳細で選び直せる分館。**その図書館システムの分だけである。**
///
/// **台帳から消えたシステムでは空になる。** そのとき受取館のリンクは押せない — 選び直す先が
/// 無く、合成層も `pickup-library-unknown` で止める。

@ProviderFor(lendingBranches)
final lendingBranchesProvider = LendingBranchesFamily._();

/// 詳細で選び直せる分館。**その図書館システムの分だけである。**
///
/// **台帳から消えたシステムでは空になる。** そのとき受取館のリンクは押せない — 選び直す先が
/// 無く、合成層も `pickup-library-unknown` で止める。

final class LendingBranchesProvider
    extends $FunctionalProvider<List<Branch>, List<Branch>, List<Branch>>
    with $Provider<List<Branch>> {
  /// 詳細で選び直せる分館。**その図書館システムの分だけである。**
  ///
  /// **台帳から消えたシステムでは空になる。** そのとき受取館のリンクは押せない — 選び直す先が
  /// 無く、合成層も `pickup-library-unknown` で止める。
  LendingBranchesProvider._({
    required LendingBranchesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lendingBranchesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lendingBranchesHash();

  @override
  String toString() {
    return r'lendingBranchesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<Branch>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<Branch> create(Ref ref) {
    final argument = this.argument as String;
    return lendingBranches(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Branch> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Branch>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LendingBranchesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lendingBranchesHash() => r'd13f007c81ed874a40bc7e3dffc9567cabc02626';

/// 詳細で選び直せる分館。**その図書館システムの分だけである。**
///
/// **台帳から消えたシステムでは空になる。** そのとき受取館のリンクは押せない — 選び直す先が
/// 無く、合成層も `pickup-library-unknown` で止める。

final class LendingBranchesFamily extends $Family
    with $FunctionalFamilyOverride<List<Branch>, String> {
  LendingBranchesFamily._()
    : super(
        retry: null,
        name: r'lendingBranchesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 詳細で選び直せる分館。**その図書館システムの分だけである。**
  ///
  /// **台帳から消えたシステムでは空になる。** そのとき受取館のリンクは押せない — 選び直す先が
  /// 無く、合成層も `pickup-library-unknown` で止める。

  LendingBranchesProvider call(String systemId) =>
      LendingBranchesProvider._(argument: systemId, from: this);

  @override
  String toString() => r'lendingBranchesProvider';
}

/// 追加の候補。**台帳に在る書誌のうち、この区でまだ生きた記録を持たないもの。**
///
/// **キーワードによる書誌検索ではない**（`lending.md` §6）。外へは一切問い合わせず、既に
/// アプリが持っている書誌を出すだけである。モックの追加ダイアログが絞っているのも、
/// 同じくローカルの `catalog` から `registeredBookIds` を除いたものである。新しい書誌は
/// 予約画面から入る（§5）。
///
/// **除外は一覧が持っている行から決める。** ここで台帳へ問い直すと、この画面が「読み直す
/// 契機は2つだけ」と決めたものの外に3つ目ができる。台帳の側の判断は `saveReservation` が
/// `active-wip` で下すので、取りこぼしても二重には登録されない。

@ProviderFor(lendingAddCandidates)
final lendingAddCandidatesProvider = LendingAddCandidatesFamily._();

/// 追加の候補。**台帳に在る書誌のうち、この区でまだ生きた記録を持たないもの。**
///
/// **キーワードによる書誌検索ではない**（`lending.md` §6）。外へは一切問い合わせず、既に
/// アプリが持っている書誌を出すだけである。モックの追加ダイアログが絞っているのも、
/// 同じくローカルの `catalog` から `registeredBookIds` を除いたものである。新しい書誌は
/// 予約画面から入る（§5）。
///
/// **除外は一覧が持っている行から決める。** ここで台帳へ問い直すと、この画面が「読み直す
/// 契機は2つだけ」と決めたものの外に3つ目ができる。台帳の側の判断は `saveReservation` が
/// `active-wip` で下すので、取りこぼしても二重には登録されない。

final class LendingAddCandidatesProvider
    extends
        $FunctionalProvider<
          List<ReservationBook>,
          List<ReservationBook>,
          List<ReservationBook>
        >
    with $Provider<List<ReservationBook>> {
  /// 追加の候補。**台帳に在る書誌のうち、この区でまだ生きた記録を持たないもの。**
  ///
  /// **キーワードによる書誌検索ではない**（`lending.md` §6）。外へは一切問い合わせず、既に
  /// アプリが持っている書誌を出すだけである。モックの追加ダイアログが絞っているのも、
  /// 同じくローカルの `catalog` から `registeredBookIds` を除いたものである。新しい書誌は
  /// 予約画面から入る（§5）。
  ///
  /// **除外は一覧が持っている行から決める。** ここで台帳へ問い直すと、この画面が「読み直す
  /// 契機は2つだけ」と決めたものの外に3つ目ができる。台帳の側の判断は `saveReservation` が
  /// `active-wip` で下すので、取りこぼしても二重には登録されない。
  LendingAddCandidatesProvider._({
    required LendingAddCandidatesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lendingAddCandidatesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lendingAddCandidatesHash();

  @override
  String toString() {
    return r'lendingAddCandidatesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<ReservationBook>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<ReservationBook> create(Ref ref) {
    final argument = this.argument as String;
    return lendingAddCandidates(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ReservationBook> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ReservationBook>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LendingAddCandidatesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lendingAddCandidatesHash() =>
    r'fe57fe3da03a43f97c6c340f852fbff96330c794';

/// 追加の候補。**台帳に在る書誌のうち、この区でまだ生きた記録を持たないもの。**
///
/// **キーワードによる書誌検索ではない**（`lending.md` §6）。外へは一切問い合わせず、既に
/// アプリが持っている書誌を出すだけである。モックの追加ダイアログが絞っているのも、
/// 同じくローカルの `catalog` から `registeredBookIds` を除いたものである。新しい書誌は
/// 予約画面から入る（§5）。
///
/// **除外は一覧が持っている行から決める。** ここで台帳へ問い直すと、この画面が「読み直す
/// 契機は2つだけ」と決めたものの外に3つ目ができる。台帳の側の判断は `saveReservation` が
/// `active-wip` で下すので、取りこぼしても二重には登録されない。

final class LendingAddCandidatesFamily extends $Family
    with $FunctionalFamilyOverride<List<ReservationBook>, String> {
  LendingAddCandidatesFamily._()
    : super(
        retry: null,
        name: r'lendingAddCandidatesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 追加の候補。**台帳に在る書誌のうち、この区でまだ生きた記録を持たないもの。**
  ///
  /// **キーワードによる書誌検索ではない**（`lending.md` §6）。外へは一切問い合わせず、既に
  /// アプリが持っている書誌を出すだけである。モックの追加ダイアログが絞っているのも、
  /// 同じくローカルの `catalog` から `registeredBookIds` を除いたものである。新しい書誌は
  /// 予約画面から入る（§5）。
  ///
  /// **除外は一覧が持っている行から決める。** ここで台帳へ問い直すと、この画面が「読み直す
  /// 契機は2つだけ」と決めたものの外に3つ目ができる。台帳の側の判断は `saveReservation` が
  /// `active-wip` で下すので、取りこぼしても二重には登録されない。

  LendingAddCandidatesProvider call(String systemId) =>
      LendingAddCandidatesProvider._(argument: systemId, from: this);

  @override
  String toString() => r'lendingAddCandidatesProvider';
}
