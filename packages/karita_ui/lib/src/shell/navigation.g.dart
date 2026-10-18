// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'navigation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// いま居る場所。**起動は常に先頭（予約）である。**
///
/// **`ui.lastTab` を読まない**（2026-09-16 に閉じた。§4「直近タブは復元しない」）。復元が
/// 効くのは起動時だけで、前面復帰では Riverpod にナビ状態が残っており、Android の
/// プロセス kill 後は Draft ごと消えるので足りない。
///
/// **`Notifier` である**（§3）。同期の読み取りに見えるが、[select] という操作を持つ。
///
/// **`keepAlive` にする。** 誰も見ていない一瞬（幅の切替で外殻が入れ替わる間）に捨てられると、
/// 選択が先頭へ戻る。

@ProviderFor(CurrentTab)
final currentTabProvider = CurrentTabProvider._();

/// いま居る場所。**起動は常に先頭（予約）である。**
///
/// **`ui.lastTab` を読まない**（2026-09-16 に閉じた。§4「直近タブは復元しない」）。復元が
/// 効くのは起動時だけで、前面復帰では Riverpod にナビ状態が残っており、Android の
/// プロセス kill 後は Draft ごと消えるので足りない。
///
/// **`Notifier` である**（§3）。同期の読み取りに見えるが、[select] という操作を持つ。
///
/// **`keepAlive` にする。** 誰も見ていない一瞬（幅の切替で外殻が入れ替わる間）に捨てられると、
/// 選択が先頭へ戻る。
final class CurrentTabProvider extends $NotifierProvider<CurrentTab, ShellTab> {
  /// いま居る場所。**起動は常に先頭（予約）である。**
  ///
  /// **`ui.lastTab` を読まない**（2026-09-16 に閉じた。§4「直近タブは復元しない」）。復元が
  /// 効くのは起動時だけで、前面復帰では Riverpod にナビ状態が残っており、Android の
  /// プロセス kill 後は Draft ごと消えるので足りない。
  ///
  /// **`Notifier` である**（§3）。同期の読み取りに見えるが、[select] という操作を持つ。
  ///
  /// **`keepAlive` にする。** 誰も見ていない一瞬（幅の切替で外殻が入れ替わる間）に捨てられると、
  /// 選択が先頭へ戻る。
  CurrentTabProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentTabProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentTabHash();

  @$internal
  @override
  CurrentTab create() => CurrentTab();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShellTab value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShellTab>(value),
    );
  }
}

String _$currentTabHash() => r'9526497373783c29ed140bd46c86beba0519ae92';

/// いま居る場所。**起動は常に先頭（予約）である。**
///
/// **`ui.lastTab` を読まない**（2026-09-16 に閉じた。§4「直近タブは復元しない」）。復元が
/// 効くのは起動時だけで、前面復帰では Riverpod にナビ状態が残っており、Android の
/// プロセス kill 後は Draft ごと消えるので足りない。
///
/// **`Notifier` である**（§3）。同期の読み取りに見えるが、[select] という操作を持つ。
///
/// **`keepAlive` にする。** 誰も見ていない一瞬（幅の切替で外殻が入れ替わる間）に捨てられると、
/// 選択が先頭へ戻る。

abstract class _$CurrentTab extends $Notifier<ShellTab> {
  ShellTab build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ShellTab, ShellTab>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ShellTab, ShellTab>,
              ShellTab,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
