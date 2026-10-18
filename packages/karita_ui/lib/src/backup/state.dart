/// ［バックアップ］［復元］の状態。**事実の読みと、3つの操作だけである。**
///
/// 段階5 の段3・段4（`非公開資料:ui-state-model.md` §4）。設計の正本は
/// 本番の認証・バックアップ・同期の結合（非公開資料）。
///
/// **順序はここに無い。** 「検証 → 起点を公開 → 置換」はエンジンの中で閉じていて、画面が
/// 持つのは選ばせることと、影響を確認させることだけである。
library;

import 'package:karita_app/karita_app.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../composition.dart';
import '../libraries/state.dart';
import '../settings/state.dart';

part 'state.g.dart';

/// 2行に出す事実。**台帳の通知ごとに読み直す** — 作成・復元・世代変更の旗は、どれも合成層が
/// `statusChanges` を打つ。
///
/// **同期の状態の通知でも読み直す**（2026-10-08）。未送信の件数は送信だけの run で減り、
/// その run は台帳の通知を打たない（`Composition.syncStatusChanges`）。
@Riverpod(keepAlive: true)
AppBackupFacts backupFacts(Ref ref) {
  ref.watch(ledgerRevisionProvider);
  ref.watch(syncStatusProvider);
  return ref.watch(compositionProvider).backupFacts();
}

/// 復元で選べるもの。**ダイアログを開くたびに引き直す**（自動破棄）。
@riverpod
Future<AppBackupListing> restoreCandidates(Ref ref) =>
    ref.watch(compositionProvider).listBackups();

/// 選んだ1件。**「合わせる」（起点への参加）とバックアップ（宣言）を1つの型で持つ。**
///
/// 影響確認の文面が2つで違う — 参加は他の端末を止めない。
///
/// **「空にしてやり直す」はここに無い。** 選ぶ／選ばれるものの一覧に並べると、他のバックアップ
/// と同格の1候補に見える。実体は業務データを消す別種の操作なので、独立した行と専用の確認
/// ダイアログ（[KaritaResetRow]・[ResetDialog]）を持つ。
class RestoreChoice {
  /// `null` なら「別の端末で復元されたデータに合わせる」。
  final AppBackup? backup;

  const RestoreChoice.rejoin() : backup = null;
  const RestoreChoice.backup(AppBackup this.backup);

  bool get rejoin => backup == null;

  @override
  bool operator ==(Object other) =>
      other is RestoreChoice && other.backup?.backupId == backup?.backupId;

  @override
  int get hashCode => backup?.backupId.hashCode ?? 0;
}

/// 操作の途中と、失敗の1件。
class BackupActionState {
  final bool busy;
  final AppIssue? error;

  /// 最後に走らせた操作が成功したか。**ダイアログを閉じる合図である。**
  final bool done;

  const BackupActionState({this.busy = false, this.error, this.done = false});
}

/// ［バックアップ］。
///
/// **押せるかは画面が決めない。** `available` が `false`（デモ）なら合成層が本体の手前で止める。
@Riverpod(keepAlive: true)
class BackupCreate extends _$BackupCreate {
  @override
  BackupActionState build() {
    ref.watch(compositionProvider);
    return const BackupActionState();
  }

  Future<void> create() async {
    if (state.busy) return;
    final composition = ref.read(compositionProvider);
    state = const BackupActionState(busy: true);
    AppIssue? error;
    var done = false;
    try {
      done = await composition.createBackup();
    } catch (failure) {
      error = appIssueOf(failure);
    }
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return;
    }
    state = BackupActionState(error: error, done: done);
  }
}

/// ［復元］の実行。**影響確認で押されたときだけ呼ばれる。**
///
/// **[ledgerSessionProvider] を見ない。** 見ると、自分が入れ替えた台帳で自分の結果が捨てられ、
/// 成否がダイアログへ届かない。
@Riverpod(keepAlive: true)
class RestoreRun extends _$RestoreRun {
  @override
  BackupActionState build() {
    ref.watch(compositionProvider);
    return const BackupActionState();
  }

  /// 新しいダイアログを開くときに前回の結果を捨てる。
  void reset() {
    if (!state.busy) state = const BackupActionState();
  }

  Future<void> run(RestoreChoice choice) async {
    if (state.busy) return;
    final composition = ref.read(compositionProvider);
    state = const BackupActionState(busy: true);
    AppIssue? error;
    var done = false;
    try {
      // **戻り値は `bool` だけである。** `RestoreOutcome` は同期の語彙で、画面が持つと境界が
      // 型の側から崩れる。
      done = choice.rejoin
          ? await composition.rejoinGeneration()
          : await composition.restoreFromBackup(choice.backup!.backupId);
    } catch (failure) {
      error = appIssueOf(failure);
    }
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return;
    }
    state = BackupActionState(error: error, done: done);
  }
}

/// ［初期化］の実行。**確認ダイアログで押されたときだけ呼ばれる。**
///
/// 選択は無い一発の操作なので、[RestoreRun] のような選んだ1件を受けない。状態の形
/// （[BackupActionState]）と、成功後にダイアログが閉じる合図（`done`）は共通で使う。
@Riverpod(keepAlive: true)
class ResetRun extends _$ResetRun {
  @override
  BackupActionState build() {
    ref.watch(compositionProvider);
    return const BackupActionState();
  }

  /// 新しいダイアログを開くときに前回の結果を捨てる。
  void reset() {
    if (!state.busy) state = const BackupActionState();
  }

  Future<void> run() async {
    if (state.busy) return;
    final composition = ref.read(compositionProvider);
    state = const BackupActionState(busy: true);
    AppIssue? error;
    var done = false;
    try {
      done = await composition.restoreEmpty();
    } catch (failure) {
      error = appIssueOf(failure);
    }
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return;
    }
    state = BackupActionState(error: error, done: done);
  }
}
