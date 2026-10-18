/// 初回起動の2択の状態。
///
/// 段階5 の段2（`非公開資料:ui-state-model.md` §4）。**段1 と同じ単位で入れる** —
/// 分けると「サインインしたのに何も起きない画面」が中間状態として残る。
///
/// **順序を画面が持たない。** 「一覧 → 選択 → 検証 → 起点を公開 → 置換」は
/// `SyncEngine.setupFromBackup` の中で閉じている。ここが持つのは2択の提示と、一覧から1件を
/// 選ばせることだけである。
library;

import 'package:karita_app/karita_app.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../browser_link/state.dart';
import '../composition.dart';
import '../shell/boot_gate.dart';

part 'state.g.dart';

/// 復旧できるバックアップ。初回の開始画面で確認し、存在するときだけ復旧リンクを出す。
@Riverpod(keepAlive: true)
Future<AppBackupListing> firstRunBackups(Ref ref) =>
    ref.watch(compositionProvider).listBackups();

/// ほかの端末が使っている記録が保管先にあるか。**2択の言葉と確認をこれで変える。**
///
/// 2択を出す時点で引く（2026-10-15）。元は「押すまで転送先へ行かない」だったが、言葉が
/// 事実に依らないと、新しい端末を足すつもりの利用者が「引き継ぐ」を選び、他の端末を選んだ
/// 時点へ巻き戻す（`非公開資料:p5c-windows-store.md` の Todo）。
@Riverpod(keepAlive: true)
Future<bool> firstRunSharedRecords(Ref ref) =>
    ref.watch(compositionProvider).hasSharedRecords();

/// 走っている途中と、失敗の1件。
class FirstRunState {
  final bool busy;

  /// **最後に選んだ枝。** 再試行の相手を決めるために持つ。`null` はまだ選んでいない。
  final String? backupId;
  final bool fromBackup;

  final AppIssue? error;

  const FirstRunState({
    this.busy = false,
    this.fromBackup = false,
    this.backupId,
    this.error,
  });
}

/// 2択の実行。
///
/// **二度押せない。** エンジンが `_requireNotSetUp` で止めるが、画面も走っている間は
/// 押させない — 二度目の失敗を利用者が読む必要が無い。
@Riverpod(keepAlive: true)
class FirstRunSetup extends _$FirstRunSetup {
  @override
  FirstRunState build() {
    ref.watch(compositionProvider);
    return const FirstRunState();
  }

  /// 「新しく始める」。**既に有効世代があれば、その記録へ合流する**（`adopt`）。
  Future<void> startFresh() => _run(fromBackup: false);

  /// 「バックアップから引き継ぐ」。
  Future<void> startFromBackup(String backupId) =>
      _run(fromBackup: true, backupId: backupId);

  Future<void> _run({required bool fromBackup, String? backupId}) async {
    if (state.busy) return;
    final composition = ref.read(compositionProvider);
    state = FirstRunState(
      busy: true,
      fromBackup: fromBackup,
      backupId: backupId,
    );
    AppIssue? error;
    try {
      // **戻り値を受けない。** `GenerationResolution` も `RestoreOutcome` も同期の語彙で、
      // 画面が持つと境界が型の側から崩れる
      // （`非公開資料:production-wiring-auth-backup-sync.md`「合成層の窓口」）。
      if (fromBackup) {
        await composition.setupFromBackup(backupId!);
      } else {
        await composition.setupFresh();
      }
    } on AppIssue catch (issue) {
      error = issue;
    } catch (failure) {
      error = appIssueOf(failure);
    }
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return;
    }
    state = FirstRunState(
      fromBackup: fromBackup,
      backupId: backupId,
      error: error,
    );
    // **セットアップの続きとして、ブラウザーとつなぐ段を出す**（`browser_link/state.dart`）。
    if (error == null) {
      ref.read(setupCompletedThisSessionProvider.notifier).mark();
    }
    // **ここが起動ゲートを開ける唯一の契機である。** `bootReady` は台帳を監視していないので、
    // 済ませた画面が無効化する（`shell/boot_gate.dart` の注記）。
    ref.invalidate(bootReadyProvider);
  }
}
