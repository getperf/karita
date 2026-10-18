// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'boot_gate.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 起動準備が済んでいるか。**外殻はこれ1つで開く。**
///
/// **同期の読み取りなので `Provider` である**（§3）。`Composition.bootReady` は台帳の
/// 1行をその場で引くだけで、待つものが無い。
///
/// **再読込の契機は `ref.invalidate` である。** 初回起動の2択（新規／復元）が済んだ時点で
/// その画面が無効化する — **この Provider が自分で気付く手段は無い**（台帳を監視していない）。
/// **繋いだ**（2026-09-23。`first_run/state.dart` の `FirstRunSetup`）。
///
/// **`keepAlive` にする。** 外殻が幅で入れ替わる間に捨てられると、開いたゲートを開き直す。

@ProviderFor(bootReady)
final bootReadyProvider = BootReadyProvider._();

/// 起動準備が済んでいるか。**外殻はこれ1つで開く。**
///
/// **同期の読み取りなので `Provider` である**（§3）。`Composition.bootReady` は台帳の
/// 1行をその場で引くだけで、待つものが無い。
///
/// **再読込の契機は `ref.invalidate` である。** 初回起動の2択（新規／復元）が済んだ時点で
/// その画面が無効化する — **この Provider が自分で気付く手段は無い**（台帳を監視していない）。
/// **繋いだ**（2026-09-23。`first_run/state.dart` の `FirstRunSetup`）。
///
/// **`keepAlive` にする。** 外殻が幅で入れ替わる間に捨てられると、開いたゲートを開き直す。

final class BootReadyProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// 起動準備が済んでいるか。**外殻はこれ1つで開く。**
  ///
  /// **同期の読み取りなので `Provider` である**（§3）。`Composition.bootReady` は台帳の
  /// 1行をその場で引くだけで、待つものが無い。
  ///
  /// **再読込の契機は `ref.invalidate` である。** 初回起動の2択（新規／復元）が済んだ時点で
  /// その画面が無効化する — **この Provider が自分で気付く手段は無い**（台帳を監視していない）。
  /// **繋いだ**（2026-09-23。`first_run/state.dart` の `FirstRunSetup`）。
  ///
  /// **`keepAlive` にする。** 外殻が幅で入れ替わる間に捨てられると、開いたゲートを開き直す。
  BootReadyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bootReadyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bootReadyHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return bootReady(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$bootReadyHash() => r'cf96c9bea927a888a5d9c426782d24aea2af56fb';
