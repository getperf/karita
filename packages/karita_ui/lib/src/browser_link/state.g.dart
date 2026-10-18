// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BrowserLink)
final browserLinkProvider = BrowserLinkProvider._();

final class BrowserLinkProvider
    extends $NotifierProvider<BrowserLink, BrowserLinkStatus> {
  BrowserLinkProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserLinkProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserLinkHash();

  @$internal
  @override
  BrowserLink create() => BrowserLink();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserLinkStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserLinkStatus>(value),
    );
  }
}

String _$browserLinkHash() => r'cf21bab6a838018f113c2cc89172c1baf4d54d15';

abstract class _$BrowserLink extends $Notifier<BrowserLinkStatus> {
  BrowserLinkStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BrowserLinkStatus, BrowserLinkStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BrowserLinkStatus, BrowserLinkStatus>,
              BrowserLinkStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// この起動で初回セットアップ（初回の2択）を済ませたか。**セッションの中だけで、永続しない。**
///
/// プラグインの段を、**セットアップの続きとしてだけ**出すためにある。既に使っている
/// 端末の起動に割り込まない — そちらは予約画面と設定の入口から確かめる。

@ProviderFor(SetupCompletedThisSession)
final setupCompletedThisSessionProvider = SetupCompletedThisSessionProvider._();

/// この起動で初回セットアップ（初回の2択）を済ませたか。**セッションの中だけで、永続しない。**
///
/// プラグインの段を、**セットアップの続きとしてだけ**出すためにある。既に使っている
/// 端末の起動に割り込まない — そちらは予約画面と設定の入口から確かめる。
final class SetupCompletedThisSessionProvider
    extends $NotifierProvider<SetupCompletedThisSession, bool> {
  /// この起動で初回セットアップ（初回の2択）を済ませたか。**セッションの中だけで、永続しない。**
  ///
  /// プラグインの段を、**セットアップの続きとしてだけ**出すためにある。既に使っている
  /// 端末の起動に割り込まない — そちらは予約画面と設定の入口から確かめる。
  SetupCompletedThisSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'setupCompletedThisSessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$setupCompletedThisSessionHash();

  @$internal
  @override
  SetupCompletedThisSession create() => SetupCompletedThisSession();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$setupCompletedThisSessionHash() =>
    r'0eb1bdf6fab20fd11b3509eb9f9445d56cddc6fc';

/// この起動で初回セットアップ（初回の2択）を済ませたか。**セッションの中だけで、永続しない。**
///
/// プラグインの段を、**セットアップの続きとしてだけ**出すためにある。既に使っている
/// 端末の起動に割り込まない — そちらは予約画面と設定の入口から確かめる。

abstract class _$SetupCompletedThisSession extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// プラグインの段を出すか。**`LibraryEnsure` と同じ形である。**
///
/// 一度出したら、利用者が終えるまで出し続ける — 届いた瞬間に消すと「つながりました」を
/// 読む前に画面が替わる。**終わるのは [finish] だけである**（［次へ］・
/// ［プラグインなしで進む］）。

@ProviderFor(BrowserLinkEnsure)
final browserLinkEnsureProvider = BrowserLinkEnsureProvider._();

/// プラグインの段を出すか。**`LibraryEnsure` と同じ形である。**
///
/// 一度出したら、利用者が終えるまで出し続ける — 届いた瞬間に消すと「つながりました」を
/// 読む前に画面が替わる。**終わるのは [finish] だけである**（［次へ］・
/// ［プラグインなしで進む］）。
final class BrowserLinkEnsureProvider
    extends $NotifierProvider<BrowserLinkEnsure, bool> {
  /// プラグインの段を出すか。**`LibraryEnsure` と同じ形である。**
  ///
  /// 一度出したら、利用者が終えるまで出し続ける — 届いた瞬間に消すと「つながりました」を
  /// 読む前に画面が替わる。**終わるのは [finish] だけである**（［次へ］・
  /// ［プラグインなしで進む］）。
  BrowserLinkEnsureProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserLinkEnsureProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserLinkEnsureHash();

  @$internal
  @override
  BrowserLinkEnsure create() => BrowserLinkEnsure();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$browserLinkEnsureHash() => r'a3f459947514f1b893ce5d8b9974c3df7763a1c8';

/// プラグインの段を出すか。**`LibraryEnsure` と同じ形である。**
///
/// 一度出したら、利用者が終えるまで出し続ける — 届いた瞬間に消すと「つながりました」を
/// 読む前に画面が替わる。**終わるのは [finish] だけである**（［次へ］・
/// ［プラグインなしで進む］）。

abstract class _$BrowserLinkEnsure extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(BrowserChoice)
final browserChoiceProvider = BrowserChoiceProvider._();

final class BrowserChoiceProvider
    extends $NotifierProvider<BrowserChoice, BrowserChoiceState> {
  BrowserChoiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserChoiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserChoiceHash();

  @$internal
  @override
  BrowserChoice create() => BrowserChoice();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserChoiceState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserChoiceState>(value),
    );
  }
}

String _$browserChoiceHash() => r'23f2715d2137655f4fc2f46946eaa47c2de98cc7';

abstract class _$BrowserChoice extends $Notifier<BrowserChoiceState> {
  BrowserChoiceState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BrowserChoiceState, BrowserChoiceState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BrowserChoiceState, BrowserChoiceState>,
              BrowserChoiceState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 見つかったブラウザー。**設定画面を開くたびに探し直す** — 入れた・消したを拾うため。

@ProviderFor(installedBrowsers)
final installedBrowsersProvider = InstalledBrowsersProvider._();

/// 見つかったブラウザー。**設定画面を開くたびに探し直す** — 入れた・消したを拾うため。

final class InstalledBrowsersProvider
    extends
        $FunctionalProvider<
          AsyncValue<Set<String>>,
          Set<String>,
          FutureOr<Set<String>>
        >
    with $FutureModifier<Set<String>>, $FutureProvider<Set<String>> {
  /// 見つかったブラウザー。**設定画面を開くたびに探し直す** — 入れた・消したを拾うため。
  InstalledBrowsersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'installedBrowsersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$installedBrowsersHash();

  @$internal
  @override
  $FutureProviderElement<Set<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Set<String>> create(Ref ref) {
    return installedBrowsers(ref);
  }
}

String _$installedBrowsersHash() => r'abb998b6c61d7f716fe2e2070189e1d48220dee2';
