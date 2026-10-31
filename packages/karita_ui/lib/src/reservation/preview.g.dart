// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'preview.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 確認画面に出す、その区の記録済みの行。
///
/// **貸出しの `lendingProvider` は借りない。** あちらは貸出しタブに入ったときに読む作りで、
/// 予約から読むと読まれていないことがあり、貸出しの選択・並びも巻き込む。台帳から直接、
/// 同じ読み口と同じ並び（[compareLoanItems]）で読む。

@ProviderFor(reservationPreviewLoans)
final reservationPreviewLoansProvider = ReservationPreviewLoansFamily._();

/// 確認画面に出す、その区の記録済みの行。
///
/// **貸出しの `lendingProvider` は借りない。** あちらは貸出しタブに入ったときに読む作りで、
/// 予約から読むと読まれていないことがあり、貸出しの選択・並びも巻き込む。台帳から直接、
/// 同じ読み口と同じ並び（[compareLoanItems]）で読む。

final class ReservationPreviewLoansProvider
    extends
        $FunctionalProvider<
          List<LoanReportItem>,
          List<LoanReportItem>,
          List<LoanReportItem>
        >
    with $Provider<List<LoanReportItem>> {
  /// 確認画面に出す、その区の記録済みの行。
  ///
  /// **貸出しの `lendingProvider` は借りない。** あちらは貸出しタブに入ったときに読む作りで、
  /// 予約から読むと読まれていないことがあり、貸出しの選択・並びも巻き込む。台帳から直接、
  /// 同じ読み口と同じ並び（[compareLoanItems]）で読む。
  ReservationPreviewLoansProvider._({
    required ReservationPreviewLoansFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'reservationPreviewLoansProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reservationPreviewLoansHash();

  @override
  String toString() {
    return r'reservationPreviewLoansProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<LoanReportItem>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<LoanReportItem> create(Ref ref) {
    final argument = this.argument as String;
    return reservationPreviewLoans(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LoanReportItem> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LoanReportItem>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReservationPreviewLoansProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reservationPreviewLoansHash() =>
    r'cd4cea59d9b0fc97f9dcce476b56f01d65fa9ac8';

/// 確認画面に出す、その区の記録済みの行。
///
/// **貸出しの `lendingProvider` は借りない。** あちらは貸出しタブに入ったときに読む作りで、
/// 予約から読むと読まれていないことがあり、貸出しの選択・並びも巻き込む。台帳から直接、
/// 同じ読み口と同じ並び（[compareLoanItems]）で読む。

final class ReservationPreviewLoansFamily extends $Family
    with $FunctionalFamilyOverride<List<LoanReportItem>, String> {
  ReservationPreviewLoansFamily._()
    : super(
        retry: null,
        name: r'reservationPreviewLoansProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 確認画面に出す、その区の記録済みの行。
  ///
  /// **貸出しの `lendingProvider` は借りない。** あちらは貸出しタブに入ったときに読む作りで、
  /// 予約から読むと読まれていないことがあり、貸出しの選択・並びも巻き込む。台帳から直接、
  /// 同じ読み口と同じ並び（[compareLoanItems]）で読む。

  ReservationPreviewLoansProvider call(String systemId) =>
      ReservationPreviewLoansProvider._(argument: systemId, from: this);

  @override
  String toString() => r'reservationPreviewLoansProvider';
}
