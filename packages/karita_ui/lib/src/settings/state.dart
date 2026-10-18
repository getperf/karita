import 'package:flutter/material.dart';
import 'package:karita_app/karita_app.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../composition.dart';

part 'state.g.dart';

ThemeMode themeModeFor(String value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

@Riverpod(keepAlive: true)
Stream<String> settingsChanges(Ref ref) =>
    ref.watch(compositionProvider).settingsChanges;

@Riverpod(keepAlive: true)
ThemeMode themeMode(Ref ref) {
  ref.watch(settingsChangesProvider);
  return themeModeFor(ref.watch(compositionProvider).theme);
}

class ThemeSaveState {
  final bool saving;
  final String? attempted;
  final AppIssue? error;
  const ThemeSaveState({this.saving = false, this.attempted, this.error});
}

@Riverpod(keepAlive: true)
class ThemeSave extends _$ThemeSave {
  @override
  ThemeSaveState build() {
    ref.watch(compositionProvider);
    return const ThemeSaveState();
  }

  Future<void> save(String value) async {
    if (state.saving) return;
    final composition = ref.read(compositionProvider);
    state = ThemeSaveState(saving: true, attempted: value);
    AppIssue? error;
    try {
      await Future.sync(() => composition.saveTheme(value));
    } on AppIssue catch (issue) {
      error = issue;
    } catch (_) {
      error = const AppIssue(
        'settings-write',
        'Device settings could not be saved.',
      );
    }
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return;
    }
    state = ThemeSaveState(attempted: value, error: error);
  }
}

@Riverpod(keepAlive: true)
Stream<AppSyncStatus> syncStatus(Ref ref) {
  final composition = ref.watch(compositionProvider);
  // 先に購読を接続してから初期値を読む。初期読込との間の通知を落とさない。
  return Stream.multi((controller) {
    void read() {
      try {
        controller.add(composition.syncStatus);
      } catch (_) {
        controller.addError(
          const AppIssue('sync-status-read', 'Sync status could not be read.'),
        );
      }
    }

    // **同期の状態の通知を見る**（2026-10-08）。台帳の通知（`statusChanges`）のときも必ず
    // 出るので、こちら1本で足りる。
    final subscription = composition.syncStatusChanges.listen(
      (_) => read(),
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
    read();
  });
}
