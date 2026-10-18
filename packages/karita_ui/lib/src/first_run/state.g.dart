// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 引き継げるバックアップ。**押したときだけ引く。**
///
/// 起動のたびに取りに行かない — 2択の片方を選ぶまでは要らないものであり、転送先への通信は
/// 利用者が選んだ後に始まる。

@ProviderFor(firstRunBackups)
final firstRunBackupsProvider = FirstRunBackupsProvider._();

/// 引き継げるバックアップ。**押したときだけ引く。**
///
/// 起動のたびに取りに行かない — 2択の片方を選ぶまでは要らないものであり、転送先への通信は
/// 利用者が選んだ後に始まる。

final class FirstRunBackupsProvider
    extends
        $FunctionalProvider<
          AsyncValue<AppBackupListing>,
          AppBackupListing,
          FutureOr<AppBackupListing>
        >
    with $FutureModifier<AppBackupListing>, $FutureProvider<AppBackupListing> {
  /// 引き継げるバックアップ。**押したときだけ引く。**
  ///
  /// 起動のたびに取りに行かない — 2択の片方を選ぶまでは要らないものであり、転送先への通信は
  /// 利用者が選んだ後に始まる。
  FirstRunBackupsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'firstRunBackupsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$firstRunBackupsHash();

  @$internal
  @override
  $FutureProviderElement<AppBackupListing> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AppBackupListing> create(Ref ref) {
    return firstRunBackups(ref);
  }
}

String _$firstRunBackupsHash() => r'5bc2352e84332f1040fb11c86c71811b92af5e1d';

/// ほかの端末が使っている記録が保管先にあるか。**2択の言葉と確認をこれで変える。**
///
/// 2択を出す時点で引く（2026-10-15）。元は「押すまで転送先へ行かない」だったが、言葉が
/// 事実に依らないと、新しい端末を足すつもりの利用者が「引き継ぐ」を選び、他の端末を選んだ
/// 時点へ巻き戻す（`非公開資料:p5c-windows-store.md` の Todo）。

@ProviderFor(firstRunSharedRecords)
final firstRunSharedRecordsProvider = FirstRunSharedRecordsProvider._();

/// ほかの端末が使っている記録が保管先にあるか。**2択の言葉と確認をこれで変える。**
///
/// 2択を出す時点で引く（2026-10-15）。元は「押すまで転送先へ行かない」だったが、言葉が
/// 事実に依らないと、新しい端末を足すつもりの利用者が「引き継ぐ」を選び、他の端末を選んだ
/// 時点へ巻き戻す（`非公開資料:p5c-windows-store.md` の Todo）。

final class FirstRunSharedRecordsProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// ほかの端末が使っている記録が保管先にあるか。**2択の言葉と確認をこれで変える。**
  ///
  /// 2択を出す時点で引く（2026-10-15）。元は「押すまで転送先へ行かない」だったが、言葉が
  /// 事実に依らないと、新しい端末を足すつもりの利用者が「引き継ぐ」を選び、他の端末を選んだ
  /// 時点へ巻き戻す（`非公開資料:p5c-windows-store.md` の Todo）。
  FirstRunSharedRecordsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'firstRunSharedRecordsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$firstRunSharedRecordsHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return firstRunSharedRecords(ref);
  }
}

String _$firstRunSharedRecordsHash() =>
    r'7e730ca377ad1dc16ad0a86a3f283f322e11b5b7';

/// 2択の実行。
///
/// **二度押せない。** エンジンが `_requireNotSetUp` で止めるが、画面も走っている間は
/// 押させない — 二度目の失敗を利用者が読む必要が無い。

@ProviderFor(FirstRunSetup)
final firstRunSetupProvider = FirstRunSetupProvider._();

/// 2択の実行。
///
/// **二度押せない。** エンジンが `_requireNotSetUp` で止めるが、画面も走っている間は
/// 押させない — 二度目の失敗を利用者が読む必要が無い。
final class FirstRunSetupProvider
    extends $NotifierProvider<FirstRunSetup, FirstRunState> {
  /// 2択の実行。
  ///
  /// **二度押せない。** エンジンが `_requireNotSetUp` で止めるが、画面も走っている間は
  /// 押させない — 二度目の失敗を利用者が読む必要が無い。
  FirstRunSetupProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'firstRunSetupProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$firstRunSetupHash();

  @$internal
  @override
  FirstRunSetup create() => FirstRunSetup();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FirstRunState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FirstRunState>(value),
    );
  }
}

String _$firstRunSetupHash() => r'3a58e376288d0ef14635c1c8917b192142fd88b5';

/// 2択の実行。
///
/// **二度押せない。** エンジンが `_requireNotSetUp` で止めるが、画面も走っている間は
/// 押させない — 二度目の失敗を利用者が読む必要が無い。

abstract class _$FirstRunSetup extends $Notifier<FirstRunState> {
  FirstRunState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FirstRunState, FirstRunState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FirstRunState, FirstRunState>,
              FirstRunState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
