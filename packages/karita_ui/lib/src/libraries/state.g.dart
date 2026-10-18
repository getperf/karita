// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 台帳が変わったかもしれない回数。**購読はこの1本だけである。**
///
/// 発火するのは合成層の `statusChanges` — 業務を書いた直後（`syncAfterDomainWrite`）、同期 run
/// の開始記録後と終了／失敗時、前面復帰、診断の完了である（§2「更新の共通契約」）。
/// **同期が失敗しても、それまでのコミットは残る**ので、失敗の通知でも読み直す。
///
/// **`void` の Stream を watch する形にしない。** `AsyncData<void>(null)` は前回と等しく、
/// **依存側が再計算されない。** 単調増加の `int` なら必ず違う値になる。
///
/// **`keepAlive` にする。** 誰も見ていない一瞬に捨てると購読が切れ、その間の変更を落とす。

@ProviderFor(LedgerRevision)
final ledgerRevisionProvider = LedgerRevisionProvider._();

/// 台帳が変わったかもしれない回数。**購読はこの1本だけである。**
///
/// 発火するのは合成層の `statusChanges` — 業務を書いた直後（`syncAfterDomainWrite`）、同期 run
/// の開始記録後と終了／失敗時、前面復帰、診断の完了である（§2「更新の共通契約」）。
/// **同期が失敗しても、それまでのコミットは残る**ので、失敗の通知でも読み直す。
///
/// **`void` の Stream を watch する形にしない。** `AsyncData<void>(null)` は前回と等しく、
/// **依存側が再計算されない。** 単調増加の `int` なら必ず違う値になる。
///
/// **`keepAlive` にする。** 誰も見ていない一瞬に捨てると購読が切れ、その間の変更を落とす。
final class LedgerRevisionProvider
    extends $NotifierProvider<LedgerRevision, int> {
  /// 台帳が変わったかもしれない回数。**購読はこの1本だけである。**
  ///
  /// 発火するのは合成層の `statusChanges` — 業務を書いた直後（`syncAfterDomainWrite`）、同期 run
  /// の開始記録後と終了／失敗時、前面復帰、診断の完了である（§2「更新の共通契約」）。
  /// **同期が失敗しても、それまでのコミットは残る**ので、失敗の通知でも読み直す。
  ///
  /// **`void` の Stream を watch する形にしない。** `AsyncData<void>(null)` は前回と等しく、
  /// **依存側が再計算されない。** 単調増加の `int` なら必ず違う値になる。
  ///
  /// **`keepAlive` にする。** 誰も見ていない一瞬に捨てると購読が切れ、その間の変更を落とす。
  LedgerRevisionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ledgerRevisionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ledgerRevisionHash();

  @$internal
  @override
  LedgerRevision create() => LedgerRevision();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$ledgerRevisionHash() => r'8cdd5804129a097acae22f2e71c81b5c4011585f';

/// 台帳が変わったかもしれない回数。**購読はこの1本だけである。**
///
/// 発火するのは合成層の `statusChanges` — 業務を書いた直後（`syncAfterDomainWrite`）、同期 run
/// の開始記録後と終了／失敗時、前面復帰、診断の完了である（§2「更新の共通契約」）。
/// **同期が失敗しても、それまでのコミットは残る**ので、失敗の通知でも読み直す。
///
/// **`void` の Stream を watch する形にしない。** `AsyncData<void>(null)` は前回と等しく、
/// **依存側が再計算されない。** 単調増加の `int` なら必ず違う値になる。
///
/// **`keepAlive` にする。** 誰も見ていない一瞬に捨てると購読が切れ、その間の変更を落とす。

abstract class _$LedgerRevision extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 台帳の接続。**復元で `Db` が入れ替わったときだけ別の値になる。**
///
/// 画面の保持（貸出しの詳細・予約の下書き・図書館管理の位置・本棚の編集中入力）を捨てる
/// 契機である。**`compositionProvider` を見るだけでは足りない** — 復元では `Composition` が
/// 替わらない（`非公開資料:production-wiring-auth-backup-sync.md`「復元後の再接続」）。
///
/// [ledgerRevisionProvider] の通知ごとに読み直すが、**値は同じ token なので依存側は
/// 再計算されない。** 替わるのは接続が替わったときだけである。

@ProviderFor(ledgerSession)
final ledgerSessionProvider = LedgerSessionProvider._();

/// 台帳の接続。**復元で `Db` が入れ替わったときだけ別の値になる。**
///
/// 画面の保持（貸出しの詳細・予約の下書き・図書館管理の位置・本棚の編集中入力）を捨てる
/// 契機である。**`compositionProvider` を見るだけでは足りない** — 復元では `Composition` が
/// 替わらない（`非公開資料:production-wiring-auth-backup-sync.md`「復元後の再接続」）。
///
/// [ledgerRevisionProvider] の通知ごとに読み直すが、**値は同じ token なので依存側は
/// 再計算されない。** 替わるのは接続が替わったときだけである。

final class LedgerSessionProvider
    extends $FunctionalProvider<Object, Object, Object>
    with $Provider<Object> {
  /// 台帳の接続。**復元で `Db` が入れ替わったときだけ別の値になる。**
  ///
  /// 画面の保持（貸出しの詳細・予約の下書き・図書館管理の位置・本棚の編集中入力）を捨てる
  /// 契機である。**`compositionProvider` を見るだけでは足りない** — 復元では `Composition` が
  /// 替わらない（`非公開資料:production-wiring-auth-backup-sync.md`「復元後の再接続」）。
  ///
  /// [ledgerRevisionProvider] の通知ごとに読み直すが、**値は同じ token なので依存側は
  /// 再計算されない。** 替わるのは接続が替わったときだけである。
  LedgerSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ledgerSessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ledgerSessionHash();

  @$internal
  @override
  $ProviderElement<Object> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Object create(Ref ref) {
    return ledgerSession(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Object value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Object>(value),
    );
  }
}

String _$ledgerSessionHash() => r'37750126f7f8c24485a8cce0034fb5b46c8f893e';

/// 登録済みの図書館システム。**`systemId` を鍵にした挿入順の Map。**
///
/// 並びは台帳の `ORDER BY system_id, id` のままである。**表示の並び順・絞り込みはここで
/// 決めない** — 別の表示条件として扱う（§2）。一覧が使うのは [libraryListProvider] である。
///
/// 一覧は `.values`、詳細は `[systemId]`。**削除済み（tombstone）は入らない。**
///
/// **読込失敗は `AppIssue` として投げる。** 空の Map（未登録）へ潰さない（§2）。包むのは
/// 合成層で、生の例外は配らない。
///
/// **自動破棄しない**（§3）。基本コレクションはタブより上の共通スコープで共有し、利用開始後は
/// セッション内で保持する。タブを移るたびに捨てると、戻るたびに全件読み直すことになる。

@ProviderFor(libraries)
final librariesProvider = LibrariesProvider._();

/// 登録済みの図書館システム。**`systemId` を鍵にした挿入順の Map。**
///
/// 並びは台帳の `ORDER BY system_id, id` のままである。**表示の並び順・絞り込みはここで
/// 決めない** — 別の表示条件として扱う（§2）。一覧が使うのは [libraryListProvider] である。
///
/// 一覧は `.values`、詳細は `[systemId]`。**削除済み（tombstone）は入らない。**
///
/// **読込失敗は `AppIssue` として投げる。** 空の Map（未登録）へ潰さない（§2）。包むのは
/// 合成層で、生の例外は配らない。
///
/// **自動破棄しない**（§3）。基本コレクションはタブより上の共通スコープで共有し、利用開始後は
/// セッション内で保持する。タブを移るたびに捨てると、戻るたびに全件読み直すことになる。

final class LibrariesProvider
    extends
        $FunctionalProvider<
          Map<String, LibrarySystem>,
          Map<String, LibrarySystem>,
          Map<String, LibrarySystem>
        >
    with $Provider<Map<String, LibrarySystem>> {
  /// 登録済みの図書館システム。**`systemId` を鍵にした挿入順の Map。**
  ///
  /// 並びは台帳の `ORDER BY system_id, id` のままである。**表示の並び順・絞り込みはここで
  /// 決めない** — 別の表示条件として扱う（§2）。一覧が使うのは [libraryListProvider] である。
  ///
  /// 一覧は `.values`、詳細は `[systemId]`。**削除済み（tombstone）は入らない。**
  ///
  /// **読込失敗は `AppIssue` として投げる。** 空の Map（未登録）へ潰さない（§2）。包むのは
  /// 合成層で、生の例外は配らない。
  ///
  /// **自動破棄しない**（§3）。基本コレクションはタブより上の共通スコープで共有し、利用開始後は
  /// セッション内で保持する。タブを移るたびに捨てると、戻るたびに全件読み直すことになる。
  LibrariesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'librariesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$librariesHash();

  @$internal
  @override
  $ProviderElement<Map<String, LibrarySystem>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, LibrarySystem> create(Ref ref) {
    return libraries(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, LibrarySystem> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, LibrarySystem>>(value),
    );
  }
}

String _$librariesHash() => r'd56a4eb77bc6757ffd847d0751e4fd4cc044f0a9';

/// 図書館システム1件。**コレクションから取り出すだけである。**
///
/// **未登録と読込失敗を分ける必要がある**（§4 段階1）。ここが返す `null` は「その
/// `systemId` は登録されていない」であって、失敗ではない — 台帳が読めなければ
/// [libraries] が投げる。
///
/// **利用停止・削除した館も、既存 Loan の表示では参照できる必要がある。** 台帳から
/// 消えた館はここでは `null` になるので、Loan 側の表示はその `null` に耐える
/// （`loan_reporting.dart` の `configured` と同じ扱い）。
///
/// **詳細は自動破棄する**（§3）。`family` の鍵は `systemId` — 文字列なので等価比較は安定して
/// いる。誰も見ていない館の分を抱え続けない。
///
/// **関数名が `library` なのは意図である。** 生成される Provider の名前は関数名で決まり、
/// 設計が呼んでいるのは `libraryProvider` である。`library` は予約語ではなく組み込み識別子で、
/// 関数名には使える（型名には使えない）。

@ProviderFor(library)
final libraryProvider = LibraryFamily._();

/// 図書館システム1件。**コレクションから取り出すだけである。**
///
/// **未登録と読込失敗を分ける必要がある**（§4 段階1）。ここが返す `null` は「その
/// `systemId` は登録されていない」であって、失敗ではない — 台帳が読めなければ
/// [libraries] が投げる。
///
/// **利用停止・削除した館も、既存 Loan の表示では参照できる必要がある。** 台帳から
/// 消えた館はここでは `null` になるので、Loan 側の表示はその `null` に耐える
/// （`loan_reporting.dart` の `configured` と同じ扱い）。
///
/// **詳細は自動破棄する**（§3）。`family` の鍵は `systemId` — 文字列なので等価比較は安定して
/// いる。誰も見ていない館の分を抱え続けない。
///
/// **関数名が `library` なのは意図である。** 生成される Provider の名前は関数名で決まり、
/// 設計が呼んでいるのは `libraryProvider` である。`library` は予約語ではなく組み込み識別子で、
/// 関数名には使える（型名には使えない）。

final class LibraryProvider
    extends $FunctionalProvider<LibrarySystem?, LibrarySystem?, LibrarySystem?>
    with $Provider<LibrarySystem?> {
  /// 図書館システム1件。**コレクションから取り出すだけである。**
  ///
  /// **未登録と読込失敗を分ける必要がある**（§4 段階1）。ここが返す `null` は「その
  /// `systemId` は登録されていない」であって、失敗ではない — 台帳が読めなければ
  /// [libraries] が投げる。
  ///
  /// **利用停止・削除した館も、既存 Loan の表示では参照できる必要がある。** 台帳から
  /// 消えた館はここでは `null` になるので、Loan 側の表示はその `null` に耐える
  /// （`loan_reporting.dart` の `configured` と同じ扱い）。
  ///
  /// **詳細は自動破棄する**（§3）。`family` の鍵は `systemId` — 文字列なので等価比較は安定して
  /// いる。誰も見ていない館の分を抱え続けない。
  ///
  /// **関数名が `library` なのは意図である。** 生成される Provider の名前は関数名で決まり、
  /// 設計が呼んでいるのは `libraryProvider` である。`library` は予約語ではなく組み込み識別子で、
  /// 関数名には使える（型名には使えない）。
  LibraryProvider._({
    required LibraryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'libraryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$libraryHash();

  @override
  String toString() {
    return r'libraryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<LibrarySystem?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LibrarySystem? create(Ref ref) {
    final argument = this.argument as String;
    return library(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibrarySystem? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibrarySystem?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LibraryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$libraryHash() => r'd3efcf291809ca9bb86d94fd4bcc1eb75a89ff62';

/// 図書館システム1件。**コレクションから取り出すだけである。**
///
/// **未登録と読込失敗を分ける必要がある**（§4 段階1）。ここが返す `null` は「その
/// `systemId` は登録されていない」であって、失敗ではない — 台帳が読めなければ
/// [libraries] が投げる。
///
/// **利用停止・削除した館も、既存 Loan の表示では参照できる必要がある。** 台帳から
/// 消えた館はここでは `null` になるので、Loan 側の表示はその `null` に耐える
/// （`loan_reporting.dart` の `configured` と同じ扱い）。
///
/// **詳細は自動破棄する**（§3）。`family` の鍵は `systemId` — 文字列なので等価比較は安定して
/// いる。誰も見ていない館の分を抱え続けない。
///
/// **関数名が `library` なのは意図である。** 生成される Provider の名前は関数名で決まり、
/// 設計が呼んでいるのは `libraryProvider` である。`library` は予約語ではなく組み込み識別子で、
/// 関数名には使える（型名には使えない）。

final class LibraryFamily extends $Family
    with $FunctionalFamilyOverride<LibrarySystem?, String> {
  LibraryFamily._()
    : super(
        retry: null,
        name: r'libraryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 図書館システム1件。**コレクションから取り出すだけである。**
  ///
  /// **未登録と読込失敗を分ける必要がある**（§4 段階1）。ここが返す `null` は「その
  /// `systemId` は登録されていない」であって、失敗ではない — 台帳が読めなければ
  /// [libraries] が投げる。
  ///
  /// **利用停止・削除した館も、既存 Loan の表示では参照できる必要がある。** 台帳から
  /// 消えた館はここでは `null` になるので、Loan 側の表示はその `null` に耐える
  /// （`loan_reporting.dart` の `configured` と同じ扱い）。
  ///
  /// **詳細は自動破棄する**（§3）。`family` の鍵は `systemId` — 文字列なので等価比較は安定して
  /// いる。誰も見ていない館の分を抱え続けない。
  ///
  /// **関数名が `library` なのは意図である。** 生成される Provider の名前は関数名で決まり、
  /// 設計が呼んでいるのは `libraryProvider` である。`library` は予約語ではなく組み込み識別子で、
  /// 関数名には使える（型名には使えない）。

  LibraryProvider call(String systemId) =>
      LibraryProvider._(argument: systemId, from: this);

  @override
  String toString() => r'libraryProvider';
}

/// 一覧に出す並び。**都道府県 → 名称 → id。**
///
/// **台帳の `system_id` 順を使わない。** あれはカーリルの識別子のローマ字順
/// （`Tokyo_Edogawa`, `Tokyo_Katsushika`, …）で、利用者が見ている名前と関係が無い。
///
/// **絞込みは持たない**（2026-09-17 決定）。登録数は利用者の生活圏ぶんで、検索欄を置いても
/// 効果を測れず、次の単位の追加画面が持つ検索と操作が二重になる。
///
/// `id` まで見るのは、同名の図書館システムが2件あったときに並びを決めきるためである。

@ProviderFor(libraryList)
final libraryListProvider = LibraryListProvider._();

/// 一覧に出す並び。**都道府県 → 名称 → id。**
///
/// **台帳の `system_id` 順を使わない。** あれはカーリルの識別子のローマ字順
/// （`Tokyo_Edogawa`, `Tokyo_Katsushika`, …）で、利用者が見ている名前と関係が無い。
///
/// **絞込みは持たない**（2026-09-17 決定）。登録数は利用者の生活圏ぶんで、検索欄を置いても
/// 効果を測れず、次の単位の追加画面が持つ検索と操作が二重になる。
///
/// `id` まで見るのは、同名の図書館システムが2件あったときに並びを決めきるためである。

final class LibraryListProvider
    extends
        $FunctionalProvider<
          List<LibrarySystem>,
          List<LibrarySystem>,
          List<LibrarySystem>
        >
    with $Provider<List<LibrarySystem>> {
  /// 一覧に出す並び。**都道府県 → 名称 → id。**
  ///
  /// **台帳の `system_id` 順を使わない。** あれはカーリルの識別子のローマ字順
  /// （`Tokyo_Edogawa`, `Tokyo_Katsushika`, …）で、利用者が見ている名前と関係が無い。
  ///
  /// **絞込みは持たない**（2026-09-17 決定）。登録数は利用者の生活圏ぶんで、検索欄を置いても
  /// 効果を測れず、次の単位の追加画面が持つ検索と操作が二重になる。
  ///
  /// `id` まで見るのは、同名の図書館システムが2件あったときに並びを決めきるためである。
  LibraryListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryListHash();

  @$internal
  @override
  $ProviderElement<List<LibrarySystem>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<LibrarySystem> create(Ref ref) {
    return libraryList(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LibrarySystem> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LibrarySystem>>(value),
    );
  }
}

String _$libraryListHash() => r'fee1416d32dd5a613e5f99bab95f5e3e2784b384';

/// 常用館1件。**未設定・解決済み・参照切れの3つに分かれる。**
///
/// **`LibrarySystem` には入っていない。** 常用館は `LibrarySetting` の別集約で（`0011`）、
/// [libraries] を読み直しても拾えない。だからこちらも [ledgerRevisionProvider] を見る。

@ProviderFor(preferredBranch)
final preferredBranchProvider = PreferredBranchFamily._();

/// 常用館1件。**未設定・解決済み・参照切れの3つに分かれる。**
///
/// **`LibrarySystem` には入っていない。** 常用館は `LibrarySetting` の別集約で（`0011`）、
/// [libraries] を読み直しても拾えない。だからこちらも [ledgerRevisionProvider] を見る。

final class PreferredBranchProvider
    extends
        $FunctionalProvider<PreferredBranch, PreferredBranch, PreferredBranch>
    with $Provider<PreferredBranch> {
  /// 常用館1件。**未設定・解決済み・参照切れの3つに分かれる。**
  ///
  /// **`LibrarySystem` には入っていない。** 常用館は `LibrarySetting` の別集約で（`0011`）、
  /// [libraries] を読み直しても拾えない。だからこちらも [ledgerRevisionProvider] を見る。
  PreferredBranchProvider._({
    required PreferredBranchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'preferredBranchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$preferredBranchHash();

  @override
  String toString() {
    return r'preferredBranchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<PreferredBranch> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PreferredBranch create(Ref ref) {
    final argument = this.argument as String;
    return preferredBranch(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PreferredBranch value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PreferredBranch>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PreferredBranchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$preferredBranchHash() => r'0c02def33dd2a3f74444914f0de266a5fe10d186';

/// 常用館1件。**未設定・解決済み・参照切れの3つに分かれる。**
///
/// **`LibrarySystem` には入っていない。** 常用館は `LibrarySetting` の別集約で（`0011`）、
/// [libraries] を読み直しても拾えない。だからこちらも [ledgerRevisionProvider] を見る。

final class PreferredBranchFamily extends $Family
    with $FunctionalFamilyOverride<PreferredBranch, String> {
  PreferredBranchFamily._()
    : super(
        retry: null,
        name: r'preferredBranchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 常用館1件。**未設定・解決済み・参照切れの3つに分かれる。**
  ///
  /// **`LibrarySystem` には入っていない。** 常用館は `LibrarySetting` の別集約で（`0011`）、
  /// [libraries] を読み直しても拾えない。だからこちらも [ledgerRevisionProvider] を見る。

  PreferredBranchProvider call(String systemId) =>
      PreferredBranchProvider._(argument: systemId, from: this);

  @override
  String toString() => r'preferredBranchProvider';
}

/// 出典つきで解決したマイページ URL。**順序を画面で書き直さない**（§3.1）。
///
/// `取り込み値` → `既定値` → `公式サイト` → `未設定` の順は `karita_domain` の純関数が持つ。

@ProviderFor(mypageUrl)
final mypageUrlProvider = MypageUrlFamily._();

/// 出典つきで解決したマイページ URL。**順序を画面で書き直さない**（§3.1）。
///
/// `取り込み値` → `既定値` → `公式サイト` → `未設定` の順は `karita_domain` の純関数が持つ。

final class MypageUrlProvider
    extends $FunctionalProvider<MypageUrl, MypageUrl, MypageUrl>
    with $Provider<MypageUrl> {
  /// 出典つきで解決したマイページ URL。**順序を画面で書き直さない**（§3.1）。
  ///
  /// `取り込み値` → `既定値` → `公式サイト` → `未設定` の順は `karita_domain` の純関数が持つ。
  MypageUrlProvider._({
    required MypageUrlFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mypageUrlProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mypageUrlHash();

  @override
  String toString() {
    return r'mypageUrlProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<MypageUrl> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MypageUrl create(Ref ref) {
    final argument = this.argument as String;
    return mypageUrl(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MypageUrl value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MypageUrl>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MypageUrlProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mypageUrlHash() => r'e4a0cd69c5a3d21b70248e1a1c44aabfc7044155';

/// 出典つきで解決したマイページ URL。**順序を画面で書き直さない**（§3.1）。
///
/// `取り込み値` → `既定値` → `公式サイト` → `未設定` の順は `karita_domain` の純関数が持つ。

final class MypageUrlFamily extends $Family
    with $FunctionalFamilyOverride<MypageUrl, String> {
  MypageUrlFamily._()
    : super(
        retry: null,
        name: r'mypageUrlProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 出典つきで解決したマイページ URL。**順序を画面で書き直さない**（§3.1）。
  ///
  /// `取り込み値` → `既定値` → `公式サイト` → `未設定` の順は `karita_domain` の純関数が持つ。

  MypageUrlProvider call(String systemId) =>
      MypageUrlProvider._(argument: systemId, from: this);

  @override
  String toString() => r'mypageUrlProvider';
}

/// 削除で残るものの勘定。**確認ダイアログを開くときだけ読む。**

@ProviderFor(libraryRemovalImpact)
final libraryRemovalImpactProvider = LibraryRemovalImpactFamily._();

/// 削除で残るものの勘定。**確認ダイアログを開くときだけ読む。**

final class LibraryRemovalImpactProvider
    extends
        $FunctionalProvider<
          LibraryRemovalImpact,
          LibraryRemovalImpact,
          LibraryRemovalImpact
        >
    with $Provider<LibraryRemovalImpact> {
  /// 削除で残るものの勘定。**確認ダイアログを開くときだけ読む。**
  LibraryRemovalImpactProvider._({
    required LibraryRemovalImpactFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'libraryRemovalImpactProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$libraryRemovalImpactHash();

  @override
  String toString() {
    return r'libraryRemovalImpactProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<LibraryRemovalImpact> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LibraryRemovalImpact create(Ref ref) {
    final argument = this.argument as String;
    return libraryRemovalImpact(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryRemovalImpact value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryRemovalImpact>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LibraryRemovalImpactProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$libraryRemovalImpactHash() =>
    r'867a80fbc8f7d60338efedce09f00176a0f55b4b';

/// 削除で残るものの勘定。**確認ダイアログを開くときだけ読む。**

final class LibraryRemovalImpactFamily extends $Family
    with $FunctionalFamilyOverride<LibraryRemovalImpact, String> {
  LibraryRemovalImpactFamily._()
    : super(
        retry: null,
        name: r'libraryRemovalImpactProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 削除で残るものの勘定。**確認ダイアログを開くときだけ読む。**

  LibraryRemovalImpactProvider call(String systemId) =>
      LibraryRemovalImpactProvider._(argument: systemId, from: this);

  @override
  String toString() => r'libraryRemovalImpactProvider';
}

/// 一覧・詳細・常用館の行き来。**Navigator ではなく状態で持つ**（2026-09-17 決定）。
///
/// §5 の3・4 が要求する共有範囲と保持・破棄条件を、そのまま Provider の宣言として書ける。
/// widget 試験からも直接読める。
///
/// **共有範囲はアプリである。** `keepAlive` にするのは、幅で外殻が入れ替わる一瞬に捨てられると
/// 詳細を見ていた利用者が設定画面へ戻されるためである。**タブ切替でも保つ** — 外殻の
/// `IndexedStack` が本文を生かしたままにしているので、設定タブへ戻ると同じ画面が出る。
///
/// **再起動では捨てる。** `device.json` へ書かない（`ui.lastTab` を持たないのと同じ判断）。
/// **セッション交換でも捨てる** — [build] が `compositionProvider` を watch しているので、
/// デモのリセットで先頭（閉じた状態）へ戻る。

@ProviderFor(LibrariesRoute)
final librariesRouteProvider = LibrariesRouteProvider._();

/// 一覧・詳細・常用館の行き来。**Navigator ではなく状態で持つ**（2026-09-17 決定）。
///
/// §5 の3・4 が要求する共有範囲と保持・破棄条件を、そのまま Provider の宣言として書ける。
/// widget 試験からも直接読める。
///
/// **共有範囲はアプリである。** `keepAlive` にするのは、幅で外殻が入れ替わる一瞬に捨てられると
/// 詳細を見ていた利用者が設定画面へ戻されるためである。**タブ切替でも保つ** — 外殻の
/// `IndexedStack` が本文を生かしたままにしているので、設定タブへ戻ると同じ画面が出る。
///
/// **再起動では捨てる。** `device.json` へ書かない（`ui.lastTab` を持たないのと同じ判断）。
/// **セッション交換でも捨てる** — [build] が `compositionProvider` を watch しているので、
/// デモのリセットで先頭（閉じた状態）へ戻る。
final class LibrariesRouteProvider
    extends $NotifierProvider<LibrariesRoute, LibrariesRouteState> {
  /// 一覧・詳細・常用館の行き来。**Navigator ではなく状態で持つ**（2026-09-17 決定）。
  ///
  /// §5 の3・4 が要求する共有範囲と保持・破棄条件を、そのまま Provider の宣言として書ける。
  /// widget 試験からも直接読める。
  ///
  /// **共有範囲はアプリである。** `keepAlive` にするのは、幅で外殻が入れ替わる一瞬に捨てられると
  /// 詳細を見ていた利用者が設定画面へ戻されるためである。**タブ切替でも保つ** — 外殻の
  /// `IndexedStack` が本文を生かしたままにしているので、設定タブへ戻ると同じ画面が出る。
  ///
  /// **再起動では捨てる。** `device.json` へ書かない（`ui.lastTab` を持たないのと同じ判断）。
  /// **セッション交換でも捨てる** — [build] が `compositionProvider` を watch しているので、
  /// デモのリセットで先頭（閉じた状態）へ戻る。
  LibrariesRouteProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'librariesRouteProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$librariesRouteHash();

  @$internal
  @override
  LibrariesRoute create() => LibrariesRoute();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibrariesRouteState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibrariesRouteState>(value),
    );
  }
}

String _$librariesRouteHash() => r'd89b49be707d03f7baced3fba989e6295b519cc5';

/// 一覧・詳細・常用館の行き来。**Navigator ではなく状態で持つ**（2026-09-17 決定）。
///
/// §5 の3・4 が要求する共有範囲と保持・破棄条件を、そのまま Provider の宣言として書ける。
/// widget 試験からも直接読める。
///
/// **共有範囲はアプリである。** `keepAlive` にするのは、幅で外殻が入れ替わる一瞬に捨てられると
/// 詳細を見ていた利用者が設定画面へ戻されるためである。**タブ切替でも保つ** — 外殻の
/// `IndexedStack` が本文を生かしたままにしているので、設定タブへ戻ると同じ画面が出る。
///
/// **再起動では捨てる。** `device.json` へ書かない（`ui.lastTab` を持たないのと同じ判断）。
/// **セッション交換でも捨てる** — [build] が `compositionProvider` を watch しているので、
/// デモのリセットで先頭（閉じた状態）へ戻る。

abstract class _$LibrariesRoute extends $Notifier<LibrariesRouteState> {
  LibrariesRouteState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LibrariesRouteState, LibrariesRouteState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LibrariesRouteState, LibrariesRouteState>,
              LibrariesRouteState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 常用館の保存と解除。**`ThemeSave` と同じ形である**（設定の段の前例）。
///
/// **連打は保存中に止める。** **セッションが交換されたら古い操作結果を捨てる。**

@ProviderFor(PreferredBranchSave)
final preferredBranchSaveProvider = PreferredBranchSaveProvider._();

/// 常用館の保存と解除。**`ThemeSave` と同じ形である**（設定の段の前例）。
///
/// **連打は保存中に止める。** **セッションが交換されたら古い操作結果を捨てる。**
final class PreferredBranchSaveProvider
    extends $NotifierProvider<PreferredBranchSave, LibraryActionState> {
  /// 常用館の保存と解除。**`ThemeSave` と同じ形である**（設定の段の前例）。
  ///
  /// **連打は保存中に止める。** **セッションが交換されたら古い操作結果を捨てる。**
  PreferredBranchSaveProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'preferredBranchSaveProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$preferredBranchSaveHash();

  @$internal
  @override
  PreferredBranchSave create() => PreferredBranchSave();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryActionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryActionState>(value),
    );
  }
}

String _$preferredBranchSaveHash() =>
    r'127c619bd9cac6e623f2c7ae15363976f62782c5';

/// 常用館の保存と解除。**`ThemeSave` と同じ形である**（設定の段の前例）。
///
/// **連打は保存中に止める。** **セッションが交換されたら古い操作結果を捨てる。**

abstract class _$PreferredBranchSave extends $Notifier<LibraryActionState> {
  LibraryActionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LibraryActionState, LibraryActionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LibraryActionState, LibraryActionState>,
              LibraryActionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 図書館システムの削除。**確認の後にだけ呼ばれる。**

@ProviderFor(LibraryRemove)
final libraryRemoveProvider = LibraryRemoveProvider._();

/// 図書館システムの削除。**確認の後にだけ呼ばれる。**
final class LibraryRemoveProvider
    extends $NotifierProvider<LibraryRemove, LibraryActionState> {
  /// 図書館システムの削除。**確認の後にだけ呼ばれる。**
  LibraryRemoveProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryRemoveProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryRemoveHash();

  @$internal
  @override
  LibraryRemove create() => LibraryRemove();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryActionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryActionState>(value),
    );
  }
}

String _$libraryRemoveHash() => r'c84c80ed90180e0084bb020ac2c6aceb8bf95390';

/// 図書館システムの削除。**確認の後にだけ呼ばれる。**

abstract class _$LibraryRemove extends $Notifier<LibraryActionState> {
  LibraryActionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LibraryActionState, LibraryActionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LibraryActionState, LibraryActionState>,
              LibraryActionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 1つの都道府県の候補。**通信はここ1回だけである。**
///
/// **`family` の鍵は都道府県名。** 同じ県を10箇所が購読しても外へ出る要求は1本である
/// （`非公開資料:ui-state-model.md` §3.1「相乗りを自前で持たない」）。
///
/// **`keepAlive` にする。** 登録作業の途中で県を行き来しても取り直さない — それが
/// `libraryCatalogTtl` の24時間が効く唯一の場面であり、**セッション内で足りる**（§3.1 の
/// 差し戻し）。**DB は作らない。**
///
/// **`maxLibraryPrefectures`（3県）は強制していない。** 打ち切る仕組みが要るうえ、1回の
/// 登録で行き来するのはせいぜい隣接する2〜3県で、セッションも長くない。**段階2 で保持の
/// 置き場を決めるときに一緒に扱う。**

@ProviderFor(libraryCandidates)
final libraryCandidatesProvider = LibraryCandidatesFamily._();

/// 1つの都道府県の候補。**通信はここ1回だけである。**
///
/// **`family` の鍵は都道府県名。** 同じ県を10箇所が購読しても外へ出る要求は1本である
/// （`非公開資料:ui-state-model.md` §3.1「相乗りを自前で持たない」）。
///
/// **`keepAlive` にする。** 登録作業の途中で県を行き来しても取り直さない — それが
/// `libraryCatalogTtl` の24時間が効く唯一の場面であり、**セッション内で足りる**（§3.1 の
/// 差し戻し）。**DB は作らない。**
///
/// **`maxLibraryPrefectures`（3県）は強制していない。** 打ち切る仕組みが要るうえ、1回の
/// 登録で行き来するのはせいぜい隣接する2〜3県で、セッションも長くない。**段階2 で保持の
/// 置き場を決めるときに一緒に扱う。**

final class LibraryCandidatesProvider
    extends
        $FunctionalProvider<
          AsyncValue<LibraryCandidates>,
          LibraryCandidates,
          FutureOr<LibraryCandidates>
        >
    with
        $FutureModifier<LibraryCandidates>,
        $FutureProvider<LibraryCandidates> {
  /// 1つの都道府県の候補。**通信はここ1回だけである。**
  ///
  /// **`family` の鍵は都道府県名。** 同じ県を10箇所が購読しても外へ出る要求は1本である
  /// （`非公開資料:ui-state-model.md` §3.1「相乗りを自前で持たない」）。
  ///
  /// **`keepAlive` にする。** 登録作業の途中で県を行き来しても取り直さない — それが
  /// `libraryCatalogTtl` の24時間が効く唯一の場面であり、**セッション内で足りる**（§3.1 の
  /// 差し戻し）。**DB は作らない。**
  ///
  /// **`maxLibraryPrefectures`（3県）は強制していない。** 打ち切る仕組みが要るうえ、1回の
  /// 登録で行き来するのはせいぜい隣接する2〜3県で、セッションも長くない。**段階2 で保持の
  /// 置き場を決めるときに一緒に扱う。**
  LibraryCandidatesProvider._({
    required LibraryCandidatesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'libraryCandidatesProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$libraryCandidatesHash();

  @override
  String toString() {
    return r'libraryCandidatesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<LibraryCandidates> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LibraryCandidates> create(Ref ref) {
    final argument = this.argument as String;
    return libraryCandidates(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LibraryCandidatesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$libraryCandidatesHash() => r'5e4837f803bd6d9b33f881bce196b869a5c5b945';

/// 1つの都道府県の候補。**通信はここ1回だけである。**
///
/// **`family` の鍵は都道府県名。** 同じ県を10箇所が購読しても外へ出る要求は1本である
/// （`非公開資料:ui-state-model.md` §3.1「相乗りを自前で持たない」）。
///
/// **`keepAlive` にする。** 登録作業の途中で県を行き来しても取り直さない — それが
/// `libraryCatalogTtl` の24時間が効く唯一の場面であり、**セッション内で足りる**（§3.1 の
/// 差し戻し）。**DB は作らない。**
///
/// **`maxLibraryPrefectures`（3県）は強制していない。** 打ち切る仕組みが要るうえ、1回の
/// 登録で行き来するのはせいぜい隣接する2〜3県で、セッションも長くない。**段階2 で保持の
/// 置き場を決めるときに一緒に扱う。**

final class LibraryCandidatesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<LibraryCandidates>, String> {
  LibraryCandidatesFamily._()
    : super(
        retry: null,
        name: r'libraryCandidatesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// 1つの都道府県の候補。**通信はここ1回だけである。**
  ///
  /// **`family` の鍵は都道府県名。** 同じ県を10箇所が購読しても外へ出る要求は1本である
  /// （`非公開資料:ui-state-model.md` §3.1「相乗りを自前で持たない」）。
  ///
  /// **`keepAlive` にする。** 登録作業の途中で県を行き来しても取り直さない — それが
  /// `libraryCatalogTtl` の24時間が効く唯一の場面であり、**セッション内で足りる**（§3.1 の
  /// 差し戻し）。**DB は作らない。**
  ///
  /// **`maxLibraryPrefectures`（3県）は強制していない。** 打ち切る仕組みが要るうえ、1回の
  /// 登録で行き来するのはせいぜい隣接する2〜3県で、セッションも長くない。**段階2 で保持の
  /// 置き場を決めるときに一緒に扱う。**

  LibraryCandidatesProvider call(String pref) =>
      LibraryCandidatesProvider._(argument: pref, from: this);

  @override
  String toString() => r'libraryCandidatesProvider';
}

/// Session-local refresh result. Explicit retry invalidates this cache.

@ProviderFor(branchRefresh)
final branchRefreshProvider = BranchRefreshFamily._();

/// Session-local refresh result. Explicit retry invalidates this cache.

final class BranchRefreshProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Session-local refresh result. Explicit retry invalidates this cache.
  BranchRefreshProvider._({
    required BranchRefreshFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'branchRefreshProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$branchRefreshHash();

  @override
  String toString() {
    return r'branchRefreshProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    final argument = this.argument as String;
    return branchRefresh(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is BranchRefreshProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$branchRefreshHash() => r'f246d9bc5f331b286ec6edda367fd9bcfeeac4ec';

/// Session-local refresh result. Explicit retry invalidates this cache.

final class BranchRefreshFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<int>, String> {
  BranchRefreshFamily._()
    : super(
        retry: null,
        name: r'branchRefreshProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Session-local refresh result. Explicit retry invalidates this cache.

  BranchRefreshProvider call(String systemId) =>
      BranchRefreshProvider._(argument: systemId, from: this);

  @override
  String toString() => r'branchRefreshProvider';
}

/// 図書館の登録。**`PreferredBranchSave` と同じ形である。**

@ProviderFor(LibraryRegister)
final libraryRegisterProvider = LibraryRegisterProvider._();

/// 図書館の登録。**`PreferredBranchSave` と同じ形である。**
final class LibraryRegisterProvider
    extends $NotifierProvider<LibraryRegister, LibraryActionState> {
  /// 図書館の登録。**`PreferredBranchSave` と同じ形である。**
  LibraryRegisterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryRegisterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryRegisterHash();

  @$internal
  @override
  LibraryRegister create() => LibraryRegister();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryActionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryActionState>(value),
    );
  }
}

String _$libraryRegisterHash() => r'7eee9cf0435dd376f7a03ee70a58db63cf4da7e9';

/// 図書館の登録。**`PreferredBranchSave` と同じ形である。**

abstract class _$LibraryRegister extends $Notifier<LibraryActionState> {
  LibraryActionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LibraryActionState, LibraryActionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LibraryActionState, LibraryActionState>,
              LibraryActionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 受信したマイページ URL の候補。**用途で絞った後のものが流れてくる。**
///
/// **合成層が用途を決める**（`handoff.dart` の宣言）。画面は「どの館の候補か」を受け取り、
/// 対象と値を確認して確定する。**共有だけでは保存しない。**
///
/// **`keepAlive` にする。** 画面が立つ前に届いた1件を落とさない — 共有から起動された直後は
/// 受信のほうが早い。

@ProviderFor(mypageCandidates)
final mypageCandidatesProvider = MypageCandidatesProvider._();

/// 受信したマイページ URL の候補。**用途で絞った後のものが流れてくる。**
///
/// **合成層が用途を決める**（`handoff.dart` の宣言）。画面は「どの館の候補か」を受け取り、
/// 対象と値を確認して確定する。**共有だけでは保存しない。**
///
/// **`keepAlive` にする。** 画面が立つ前に届いた1件を落とさない — 共有から起動された直後は
/// 受信のほうが早い。

final class MypageCandidatesProvider
    extends
        $FunctionalProvider<
          AsyncValue<MypageCandidate>,
          MypageCandidate,
          Stream<MypageCandidate>
        >
    with $FutureModifier<MypageCandidate>, $StreamProvider<MypageCandidate> {
  /// 受信したマイページ URL の候補。**用途で絞った後のものが流れてくる。**
  ///
  /// **合成層が用途を決める**（`handoff.dart` の宣言）。画面は「どの館の候補か」を受け取り、
  /// 対象と値を確認して確定する。**共有だけでは保存しない。**
  ///
  /// **`keepAlive` にする。** 画面が立つ前に届いた1件を落とさない — 共有から起動された直後は
  /// 受信のほうが早い。
  MypageCandidatesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mypageCandidatesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mypageCandidatesHash();

  @$internal
  @override
  $StreamProviderElement<MypageCandidate> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<MypageCandidate> create(Ref ref) {
    return mypageCandidates(ref);
  }
}

String _$mypageCandidatesHash() => r'3edbb1b952f219084428c2aef814a60784bd1bac';

/// マイページ URL の編集。**欄の文字列を受けて、読めるかと保存してよいかを出す。**
///
/// **`autoDispose` にする。** 画面を閉じたら捨てる — 保存しなかった値を抱え続けない。
/// ただし**受信の候補は合成層の側に残る**ので、開き直せば取り直せる。

@ProviderFor(MypageEdit)
final mypageEditProvider = MypageEditFamily._();

/// マイページ URL の編集。**欄の文字列を受けて、読めるかと保存してよいかを出す。**
///
/// **`autoDispose` にする。** 画面を閉じたら捨てる — 保存しなかった値を抱え続けない。
/// ただし**受信の候補は合成層の側に残る**ので、開き直せば取り直せる。
final class MypageEditProvider
    extends $NotifierProvider<MypageEdit, MypageDraft> {
  /// マイページ URL の編集。**欄の文字列を受けて、読めるかと保存してよいかを出す。**
  ///
  /// **`autoDispose` にする。** 画面を閉じたら捨てる — 保存しなかった値を抱え続けない。
  /// ただし**受信の候補は合成層の側に残る**ので、開き直せば取り直せる。
  MypageEditProvider._({
    required MypageEditFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mypageEditProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mypageEditHash();

  @override
  String toString() {
    return r'mypageEditProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MypageEdit create() => MypageEdit();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MypageDraft value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MypageDraft>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MypageEditProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mypageEditHash() => r'35825db116ed3d92b0a2ffe659996701dc935832';

/// マイページ URL の編集。**欄の文字列を受けて、読めるかと保存してよいかを出す。**
///
/// **`autoDispose` にする。** 画面を閉じたら捨てる — 保存しなかった値を抱え続けない。
/// ただし**受信の候補は合成層の側に残る**ので、開き直せば取り直せる。

final class MypageEditFamily extends $Family
    with
        $ClassFamilyOverride<
          MypageEdit,
          MypageDraft,
          MypageDraft,
          MypageDraft,
          String
        > {
  MypageEditFamily._()
    : super(
        retry: null,
        name: r'mypageEditProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// マイページ URL の編集。**欄の文字列を受けて、読めるかと保存してよいかを出す。**
  ///
  /// **`autoDispose` にする。** 画面を閉じたら捨てる — 保存しなかった値を抱え続けない。
  /// ただし**受信の候補は合成層の側に残る**ので、開き直せば取り直せる。

  MypageEditProvider call(String systemId) =>
      MypageEditProvider._(argument: systemId, from: this);

  @override
  String toString() => r'mypageEditProvider';
}

/// マイページ URL の編集。**欄の文字列を受けて、読めるかと保存してよいかを出す。**
///
/// **`autoDispose` にする。** 画面を閉じたら捨てる — 保存しなかった値を抱え続けない。
/// ただし**受信の候補は合成層の側に残る**ので、開き直せば取り直せる。

abstract class _$MypageEdit extends $Notifier<MypageDraft> {
  late final _$args = ref.$arg as String;
  String get systemId => _$args;

  MypageDraft build(String systemId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MypageDraft, MypageDraft>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MypageDraft, MypageDraft>,
              MypageDraft,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// 図書館サイトを開く操作。**開いた事実で状態を変えない。**

@ProviderFor(LibrarySiteOpen)
final librarySiteOpenProvider = LibrarySiteOpenProvider._();

/// 図書館サイトを開く操作。**開いた事実で状態を変えない。**
final class LibrarySiteOpenProvider
    extends $NotifierProvider<LibrarySiteOpen, LibraryActionState> {
  /// 図書館サイトを開く操作。**開いた事実で状態を変えない。**
  LibrarySiteOpenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'librarySiteOpenProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$librarySiteOpenHash();

  @$internal
  @override
  LibrarySiteOpen create() => LibrarySiteOpen();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryActionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryActionState>(value),
    );
  }
}

String _$librarySiteOpenHash() => r'f17eb6564b3e7c9b021a04710b02e4965f1a6f85';

/// 図書館サイトを開く操作。**開いた事実で状態を変えない。**

abstract class _$LibrarySiteOpen extends $Notifier<LibraryActionState> {
  LibraryActionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LibraryActionState, LibraryActionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LibraryActionState, LibraryActionState>,
              LibraryActionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
