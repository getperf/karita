// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'handoff_triage.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PendingHandoffTriage)
final pendingHandoffTriageProvider = PendingHandoffTriageProvider._();

final class PendingHandoffTriageProvider
    extends $NotifierProvider<PendingHandoffTriage, HandoffTriage?> {
  PendingHandoffTriageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingHandoffTriageProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingHandoffTriageHash();

  @$internal
  @override
  PendingHandoffTriage create() => PendingHandoffTriage();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HandoffTriage? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HandoffTriage?>(value),
    );
  }
}

String _$pendingHandoffTriageHash() =>
    r'a04e818502527e30d9d24f73945162ffd4d355ec';

abstract class _$PendingHandoffTriage extends $Notifier<HandoffTriage?> {
  HandoffTriage? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<HandoffTriage?, HandoffTriage?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HandoffTriage?, HandoffTriage?>,
              HandoffTriage?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
