// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_setup.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 登録を促す段を出すか。
///
/// **一度出したら、利用者が終えるまで出し続ける。** 終わりは登録の件数では決めない —
/// 1件で外すと、同じ地区の複数の館や、別の地区の館を続けて登録できない。途中で同期が走っても
/// （`syncing` になっても）、選んでいる最中の県や候補の一覧を手放さない。
///
/// **終わるのは [finish] だけである**（戻る矢印・［完了］・［あとで］）。**セッションの中だけで、
/// 永続しない** — 0件のまま終えれば、次の起動でまた促す。

@ProviderFor(LibraryEnsure)
final libraryEnsureProvider = LibraryEnsureProvider._();

/// 登録を促す段を出すか。
///
/// **一度出したら、利用者が終えるまで出し続ける。** 終わりは登録の件数では決めない —
/// 1件で外すと、同じ地区の複数の館や、別の地区の館を続けて登録できない。途中で同期が走っても
/// （`syncing` になっても）、選んでいる最中の県や候補の一覧を手放さない。
///
/// **終わるのは [finish] だけである**（戻る矢印・［完了］・［あとで］）。**セッションの中だけで、
/// 永続しない** — 0件のまま終えれば、次の起動でまた促す。
final class LibraryEnsureProvider
    extends $NotifierProvider<LibraryEnsure, bool> {
  /// 登録を促す段を出すか。
  ///
  /// **一度出したら、利用者が終えるまで出し続ける。** 終わりは登録の件数では決めない —
  /// 1件で外すと、同じ地区の複数の館や、別の地区の館を続けて登録できない。途中で同期が走っても
  /// （`syncing` になっても）、選んでいる最中の県や候補の一覧を手放さない。
  ///
  /// **終わるのは [finish] だけである**（戻る矢印・［完了］・［あとで］）。**セッションの中だけで、
  /// 永続しない** — 0件のまま終えれば、次の起動でまた促す。
  LibraryEnsureProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryEnsureProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryEnsureHash();

  @$internal
  @override
  LibraryEnsure create() => LibraryEnsure();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$libraryEnsureHash() => r'e6f393b4b9127b2776dee33cc4c397cf5f9c4fe2';

/// 登録を促す段を出すか。
///
/// **一度出したら、利用者が終えるまで出し続ける。** 終わりは登録の件数では決めない —
/// 1件で外すと、同じ地区の複数の館や、別の地区の館を続けて登録できない。途中で同期が走っても
/// （`syncing` になっても）、選んでいる最中の県や候補の一覧を手放さない。
///
/// **終わるのは [finish] だけである**（戻る矢印・［完了］・［あとで］）。**セッションの中だけで、
/// 永続しない** — 0件のまま終えれば、次の起動でまた促す。

abstract class _$LibraryEnsure extends $Notifier<bool> {
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
