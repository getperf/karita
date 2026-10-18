// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(settingsChanges)
final settingsChangesProvider = SettingsChangesProvider._();

final class SettingsChangesProvider
    extends $FunctionalProvider<AsyncValue<String>, String, Stream<String>>
    with $FutureModifier<String>, $StreamProvider<String> {
  SettingsChangesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsChangesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsChangesHash();

  @$internal
  @override
  $StreamProviderElement<String> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<String> create(Ref ref) {
    return settingsChanges(ref);
  }
}

String _$settingsChangesHash() => r'0f025921cc307653ea74542e8d455c48914b1351';

@ProviderFor(themeMode)
final themeModeProvider = ThemeModeProvider._();

final class ThemeModeProvider
    extends $FunctionalProvider<ThemeMode, ThemeMode, ThemeMode>
    with $Provider<ThemeMode> {
  ThemeModeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeModeHash();

  @$internal
  @override
  $ProviderElement<ThemeMode> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeMode create(Ref ref) {
    return themeMode(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode>(value),
    );
  }
}

String _$themeModeHash() => r'96ad1f779a1958106b25ab7ceb299c77fa24481b';

@ProviderFor(ThemeSave)
final themeSaveProvider = ThemeSaveProvider._();

final class ThemeSaveProvider
    extends $NotifierProvider<ThemeSave, ThemeSaveState> {
  ThemeSaveProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeSaveProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeSaveHash();

  @$internal
  @override
  ThemeSave create() => ThemeSave();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeSaveState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeSaveState>(value),
    );
  }
}

String _$themeSaveHash() => r'24f6ffa92c4857f353e75b0bcbbc42370ec5d231';

abstract class _$ThemeSave extends $Notifier<ThemeSaveState> {
  ThemeSaveState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ThemeSaveState, ThemeSaveState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThemeSaveState, ThemeSaveState>,
              ThemeSaveState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(syncStatus)
final syncStatusProvider = SyncStatusProvider._();

final class SyncStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<AppSyncStatus>,
          AppSyncStatus,
          Stream<AppSyncStatus>
        >
    with $FutureModifier<AppSyncStatus>, $StreamProvider<AppSyncStatus> {
  SyncStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncStatusHash();

  @$internal
  @override
  $StreamProviderElement<AppSyncStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<AppSyncStatus> create(Ref ref) {
    return syncStatus(ref);
  }
}

String _$syncStatusHash() => r'c71d1221d04d0df13491305ddf36c0f11d858821';
