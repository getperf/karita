// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 2行に出す事実。**台帳の通知ごとに読み直す** — 作成・復元・世代変更の旗は、どれも合成層が
/// `statusChanges` を打つ。

@ProviderFor(backupFacts)
final backupFactsProvider = BackupFactsProvider._();

/// 2行に出す事実。**台帳の通知ごとに読み直す** — 作成・復元・世代変更の旗は、どれも合成層が
/// `statusChanges` を打つ。

final class BackupFactsProvider
    extends $FunctionalProvider<AppBackupFacts, AppBackupFacts, AppBackupFacts>
    with $Provider<AppBackupFacts> {
  /// 2行に出す事実。**台帳の通知ごとに読み直す** — 作成・復元・世代変更の旗は、どれも合成層が
  /// `statusChanges` を打つ。
  BackupFactsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupFactsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupFactsHash();

  @$internal
  @override
  $ProviderElement<AppBackupFacts> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppBackupFacts create(Ref ref) {
    return backupFacts(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppBackupFacts value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppBackupFacts>(value),
    );
  }
}

String _$backupFactsHash() => r'f55a6843742fecb2f3ab0c5f93d8dc6fc6e3c894';

/// 復元で選べるもの。**ダイアログを開くたびに引き直す**（自動破棄）。

@ProviderFor(restoreCandidates)
final restoreCandidatesProvider = RestoreCandidatesProvider._();

/// 復元で選べるもの。**ダイアログを開くたびに引き直す**（自動破棄）。

final class RestoreCandidatesProvider
    extends
        $FunctionalProvider<
          AsyncValue<AppBackupListing>,
          AppBackupListing,
          FutureOr<AppBackupListing>
        >
    with $FutureModifier<AppBackupListing>, $FutureProvider<AppBackupListing> {
  /// 復元で選べるもの。**ダイアログを開くたびに引き直す**（自動破棄）。
  RestoreCandidatesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'restoreCandidatesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$restoreCandidatesHash();

  @$internal
  @override
  $FutureProviderElement<AppBackupListing> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AppBackupListing> create(Ref ref) {
    return restoreCandidates(ref);
  }
}

String _$restoreCandidatesHash() => r'345eb402e81a3170d9b7dee8f3dcc6b98a55d072';

/// ［バックアップ］。
///
/// **押せるかは画面が決めない。** `available` が `false`（デモ）なら合成層が本体の手前で止める。

@ProviderFor(BackupCreate)
final backupCreateProvider = BackupCreateProvider._();

/// ［バックアップ］。
///
/// **押せるかは画面が決めない。** `available` が `false`（デモ）なら合成層が本体の手前で止める。
final class BackupCreateProvider
    extends $NotifierProvider<BackupCreate, BackupActionState> {
  /// ［バックアップ］。
  ///
  /// **押せるかは画面が決めない。** `available` が `false`（デモ）なら合成層が本体の手前で止める。
  BackupCreateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupCreateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupCreateHash();

  @$internal
  @override
  BackupCreate create() => BackupCreate();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupActionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupActionState>(value),
    );
  }
}

String _$backupCreateHash() => r'a83a1fc2b66f7cbdf351bec24b023fbe9fca76b3';

/// ［バックアップ］。
///
/// **押せるかは画面が決めない。** `available` が `false`（デモ）なら合成層が本体の手前で止める。

abstract class _$BackupCreate extends $Notifier<BackupActionState> {
  BackupActionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BackupActionState, BackupActionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BackupActionState, BackupActionState>,
              BackupActionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// ［復元］の実行。**影響確認で押されたときだけ呼ばれる。**
///
/// **[ledgerSessionProvider] を見ない。** 見ると、自分が入れ替えた台帳で自分の結果が捨てられ、
/// 成否がダイアログへ届かない。

@ProviderFor(RestoreRun)
final restoreRunProvider = RestoreRunProvider._();

/// ［復元］の実行。**影響確認で押されたときだけ呼ばれる。**
///
/// **[ledgerSessionProvider] を見ない。** 見ると、自分が入れ替えた台帳で自分の結果が捨てられ、
/// 成否がダイアログへ届かない。
final class RestoreRunProvider
    extends $NotifierProvider<RestoreRun, BackupActionState> {
  /// ［復元］の実行。**影響確認で押されたときだけ呼ばれる。**
  ///
  /// **[ledgerSessionProvider] を見ない。** 見ると、自分が入れ替えた台帳で自分の結果が捨てられ、
  /// 成否がダイアログへ届かない。
  RestoreRunProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'restoreRunProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$restoreRunHash();

  @$internal
  @override
  RestoreRun create() => RestoreRun();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupActionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupActionState>(value),
    );
  }
}

String _$restoreRunHash() => r'fa18f3a1daae20d7cdaa0e38bd13ab63ace6ad40';

/// ［復元］の実行。**影響確認で押されたときだけ呼ばれる。**
///
/// **[ledgerSessionProvider] を見ない。** 見ると、自分が入れ替えた台帳で自分の結果が捨てられ、
/// 成否がダイアログへ届かない。

abstract class _$RestoreRun extends $Notifier<BackupActionState> {
  BackupActionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BackupActionState, BackupActionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BackupActionState, BackupActionState>,
              BackupActionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// ［初期化］の実行。**確認ダイアログで押されたときだけ呼ばれる。**
///
/// 選択は無い一発の操作なので、[RestoreRun] のような選んだ1件を受けない。状態の形
/// （[BackupActionState]）と、成功後にダイアログが閉じる合図（`done`）は共通で使う。

@ProviderFor(ResetRun)
final resetRunProvider = ResetRunProvider._();

/// ［初期化］の実行。**確認ダイアログで押されたときだけ呼ばれる。**
///
/// 選択は無い一発の操作なので、[RestoreRun] のような選んだ1件を受けない。状態の形
/// （[BackupActionState]）と、成功後にダイアログが閉じる合図（`done`）は共通で使う。
final class ResetRunProvider
    extends $NotifierProvider<ResetRun, BackupActionState> {
  /// ［初期化］の実行。**確認ダイアログで押されたときだけ呼ばれる。**
  ///
  /// 選択は無い一発の操作なので、[RestoreRun] のような選んだ1件を受けない。状態の形
  /// （[BackupActionState]）と、成功後にダイアログが閉じる合図（`done`）は共通で使う。
  ResetRunProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'resetRunProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$resetRunHash();

  @$internal
  @override
  ResetRun create() => ResetRun();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupActionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupActionState>(value),
    );
  }
}

String _$resetRunHash() => r'09b785ffa38ca98adee9dc43c68c0249c3a1d1c5';

/// ［初期化］の実行。**確認ダイアログで押されたときだけ呼ばれる。**
///
/// 選択は無い一発の操作なので、[RestoreRun] のような選んだ1件を受けない。状態の形
/// （[BackupActionState]）と、成功後にダイアログが閉じる合図（`done`）は共通で使う。

abstract class _$ResetRun extends $Notifier<BackupActionState> {
  BackupActionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BackupActionState, BackupActionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BackupActionState, BackupActionState>,
              BackupActionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
