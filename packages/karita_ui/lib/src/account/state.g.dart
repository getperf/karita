// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// いまの接続。
///
/// **`Future` である。** Android は Play services へ無音で訊くしかなく、同期に読めない
/// （合成層の `Authorization.authorized` の注記）。
///
/// **7状態に追随する。** 認可を失って止まった端末は `signInRequired` になり、そのとき
/// ［アカウント］行も「再サインインが必要」へ変わる。**契機はその1本で足りる** — サインイン
/// とサインアウトは自分で無効化する（[AuthAction]）。

@ProviderFor(authStatus)
final authStatusProvider = AuthStatusProvider._();

/// いまの接続。
///
/// **`Future` である。** Android は Play services へ無音で訊くしかなく、同期に読めない
/// （合成層の `Authorization.authorized` の注記）。
///
/// **7状態に追随する。** 認可を失って止まった端末は `signInRequired` になり、そのとき
/// ［アカウント］行も「再サインインが必要」へ変わる。**契機はその1本で足りる** — サインイン
/// とサインアウトは自分で無効化する（[AuthAction]）。

final class AuthStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<AppAuthStatus>,
          AppAuthStatus,
          FutureOr<AppAuthStatus>
        >
    with $FutureModifier<AppAuthStatus>, $FutureProvider<AppAuthStatus> {
  /// いまの接続。
  ///
  /// **`Future` である。** Android は Play services へ無音で訊くしかなく、同期に読めない
  /// （合成層の `Authorization.authorized` の注記）。
  ///
  /// **7状態に追随する。** 認可を失って止まった端末は `signInRequired` になり、そのとき
  /// ［アカウント］行も「再サインインが必要」へ変わる。**契機はその1本で足りる** — サインイン
  /// とサインアウトは自分で無効化する（[AuthAction]）。
  AuthStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authStatusHash();

  @$internal
  @override
  $FutureProviderElement<AppAuthStatus> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AppAuthStatus> create(Ref ref) {
    return authStatus(ref);
  }
}

String _$authStatusHash() => r'ec5bdb0e004aa224d97adf03bce77ec8fd8f8288';

/// ［サインイン］と［サインアウト］。
///
/// **押せるかは画面が決めない。** `AppAuthStatus.available` が `false`（デモ）なら合成層が
/// 本体の手前で止め、ここは `false` を受け取って何も起きない。

@ProviderFor(AuthAction)
final authActionProvider = AuthActionProvider._();

/// ［サインイン］と［サインアウト］。
///
/// **押せるかは画面が決めない。** `AppAuthStatus.available` が `false`（デモ）なら合成層が
/// 本体の手前で止め、ここは `false` を受け取って何も起きない。
final class AuthActionProvider
    extends $NotifierProvider<AuthAction, AuthActionState> {
  /// ［サインイン］と［サインアウト］。
  ///
  /// **押せるかは画面が決めない。** `AppAuthStatus.available` が `false`（デモ）なら合成層が
  /// 本体の手前で止め、ここは `false` を受け取って何も起きない。
  AuthActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authActionHash();

  @$internal
  @override
  AuthAction create() => AuthAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthActionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthActionState>(value),
    );
  }
}

String _$authActionHash() => r'c9cdc69323648bb61fc96f6d2e89c5c6acdc44d6';

/// ［サインイン］と［サインアウト］。
///
/// **押せるかは画面が決めない。** `AppAuthStatus.available` が `false`（デモ）なら合成層が
/// 本体の手前で止め、ここは `false` を受け取って何も起きない。

abstract class _$AuthAction extends $Notifier<AuthActionState> {
  AuthActionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AuthActionState, AuthActionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AuthActionState, AuthActionState>,
              AuthActionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 別の Google アカウントに接続している端末の切替導線。**このアプリからは grant を
/// 取り消せないので、外部のアカウント管理ページを開くだけである**
/// （`非公開資料:production-wiring-auth-backup-sync.md`「切替の導線」）。

@ProviderFor(AccountSwitchAction)
final accountSwitchActionProvider = AccountSwitchActionProvider._();

/// 別の Google アカウントに接続している端末の切替導線。**このアプリからは grant を
/// 取り消せないので、外部のアカウント管理ページを開くだけである**
/// （`非公開資料:production-wiring-auth-backup-sync.md`「切替の導線」）。
final class AccountSwitchActionProvider
    extends $NotifierProvider<AccountSwitchAction, SwitchAccountState> {
  /// 別の Google アカウントに接続している端末の切替導線。**このアプリからは grant を
  /// 取り消せないので、外部のアカウント管理ページを開くだけである**
  /// （`非公開資料:production-wiring-auth-backup-sync.md`「切替の導線」）。
  AccountSwitchActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountSwitchActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountSwitchActionHash();

  @$internal
  @override
  AccountSwitchAction create() => AccountSwitchAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SwitchAccountState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SwitchAccountState>(value),
    );
  }
}

String _$accountSwitchActionHash() =>
    r'9478ab95659bdae80ca7a8687b519b481cc3d977';

/// 別の Google アカウントに接続している端末の切替導線。**このアプリからは grant を
/// 取り消せないので、外部のアカウント管理ページを開くだけである**
/// （`非公開資料:production-wiring-auth-backup-sync.md`「切替の導線」）。

abstract class _$AccountSwitchAction extends $Notifier<SwitchAccountState> {
  SwitchAccountState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SwitchAccountState, SwitchAccountState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SwitchAccountState, SwitchAccountState>,
              SwitchAccountState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
