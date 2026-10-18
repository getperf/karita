// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(reservationLookup)
final reservationLookupProvider = ReservationLookupFamily._();

final class ReservationLookupProvider
    extends
        $FunctionalProvider<
          AsyncValue<OpenBdResult>,
          OpenBdResult,
          FutureOr<OpenBdResult>
        >
    with $FutureModifier<OpenBdResult>, $FutureProvider<OpenBdResult> {
  ReservationLookupProvider._({
    required ReservationLookupFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'reservationLookupProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reservationLookupHash();

  @override
  String toString() {
    return r'reservationLookupProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<OpenBdResult> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<OpenBdResult> create(Ref ref) {
    final argument = this.argument as String;
    return reservationLookup(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReservationLookupProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reservationLookupHash() => r'04e30339c87eb312cf58dcbd0154707d706c8f22';

final class ReservationLookupFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<OpenBdResult>, String> {
  ReservationLookupFamily._()
    : super(
        retry: null,
        name: r'reservationLookupProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ReservationLookupProvider call(String isbn) =>
      ReservationLookupProvider._(argument: isbn, from: this);

  @override
  String toString() => r'reservationLookupProvider';
}

@ProviderFor(reservationCover)
final reservationCoverProvider = ReservationCoverFamily._();

final class ReservationCoverProvider
    extends
        $FunctionalProvider<
          AsyncValue<CoverImageResult>,
          CoverImageResult,
          FutureOr<CoverImageResult>
        >
    with $FutureModifier<CoverImageResult>, $FutureProvider<CoverImageResult> {
  ReservationCoverProvider._({
    required ReservationCoverFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'reservationCoverProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reservationCoverHash();

  @override
  String toString() {
    return r'reservationCoverProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<CoverImageResult> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CoverImageResult> create(Ref ref) {
    final argument = this.argument as String;
    return reservationCover(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReservationCoverProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reservationCoverHash() => r'4b3d1b6b19d18144a0a5f79d09f77abeec93831d';

final class ReservationCoverFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<CoverImageResult>, String> {
  ReservationCoverFamily._()
    : super(
        retry: null,
        name: r'reservationCoverProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ReservationCoverProvider call(String url) =>
      ReservationCoverProvider._(argument: url, from: this);

  @override
  String toString() => r'reservationCoverProvider';
}

@ProviderFor(Reservation)
final reservationProvider = ReservationProvider._();

final class ReservationProvider
    extends $NotifierProvider<Reservation, ReservationState> {
  ReservationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reservationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reservationHash();

  @$internal
  @override
  Reservation create() => Reservation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReservationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReservationState>(value),
    );
  }
}

String _$reservationHash() => r'a0af034d2d530a2f5ae299c620474048f40b6c77';

abstract class _$Reservation extends $Notifier<ReservationState> {
  ReservationState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ReservationState, ReservationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ReservationState, ReservationState>,
              ReservationState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
