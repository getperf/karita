/// ［アカウント］の状態。**3状態の読みと、2つの操作だけである。**
///
/// 段階5 の段1（`非公開資料:ui-state-model.md` §4）。設計の正本は
/// 本番の認証・バックアップ・同期の結合（非公開資料）。
///
/// **判定はここに無い。** 3状態を組むのは合成層（`Composition.authStatus()`）で、画面は
/// 受け取って文言を当てるだけである。`blocked_auth` の読み方を画面が持つと、7状態と
/// ［アカウント］行で判定が2つに割れる。
library;

import 'package:karita_app/karita_app.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../composition.dart';
import '../settings/state.dart';

part 'state.g.dart';

/// いまの接続。
///
/// **`Future` である。** Android は Play services へ無音で訊くしかなく、同期に読めない
/// （合成層の `Authorization.authorized` の注記）。
///
/// **7状態に追随する。** 認可を失って止まった端末は `signInRequired` になり、そのとき
/// ［アカウント］行も「再サインインが必要」へ変わる。**契機はその1本で足りる** — サインイン
/// とサインアウトは自分で無効化する（[AuthAction]）。
@Riverpod(keepAlive: true)
Future<AppAuthStatus> authStatus(Ref ref) {
  final composition = ref.watch(compositionProvider);
  ref.watch(syncStatusProvider);
  return composition.authStatus();
}

/// 操作の途中と、失敗の1件。
class AuthActionState {
  final bool busy;

  /// **最後に走らせた操作。** 再試行の相手を決めるために持つ。
  final bool signingIn;

  final AppIssue? error;

  const AuthActionState({this.busy = false, this.signingIn = true, this.error});
}

/// ［サインイン］と［サインアウト］。
///
/// **押せるかは画面が決めない。** `AppAuthStatus.available` が `false`（デモ）なら合成層が
/// 本体の手前で止め、ここは `false` を受け取って何も起きない。
@Riverpod(keepAlive: true)
class AuthAction extends _$AuthAction {
  @override
  AuthActionState build() {
    ref.watch(compositionProvider);
    return const AuthActionState();
  }

  Future<void> signIn() => _run(signingIn: true);

  Future<void> signOut() => _run(signingIn: false);

  Future<void> _run({required bool signingIn}) async {
    if (state.busy) return;
    final composition = ref.read(compositionProvider);
    state = AuthActionState(busy: true, signingIn: signingIn);
    AppIssue? error;
    try {
      await (signingIn ? composition.signIn() : composition.signOut());
    } on AppIssue catch (issue) {
      error = issue;
    } catch (failure) {
      // **生の例外を画面へ配らない。** 出るのはコードと型名だけである
      // （`../composition.dart` の [appIssueOf]）。
      error = appIssueOf(failure);
    }
    // 途中で合成が入れ替わったら（復元・デモのリセット）、古い結果を書き戻さない。
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return;
    }
    state = AuthActionState(signingIn: signingIn, error: error);
    // **押した後は必ず読み直す。** 成否にかかわらず、接続の有無は変わりうる。
    ref.invalidate(authStatusProvider);
  }
}

/// 操作の途中と、失敗の1件。**[AuthActionState] より軽い** — 再試行の相手を持たない。
class SwitchAccountState {
  final bool busy;
  final AppIssue? error;
  const SwitchAccountState({this.busy = false, this.error});
}

/// 別の Google アカウントに接続している端末の切替導線。**このアプリからは grant を
/// 取り消せないので、外部のアカウント管理ページを開くだけである**
/// （`非公開資料:production-wiring-auth-backup-sync.md`「切替の導線」）。
@Riverpod(keepAlive: true)
class AccountSwitchAction extends _$AccountSwitchAction {
  @override
  SwitchAccountState build() {
    ref.watch(compositionProvider);
    return const SwitchAccountState();
  }

  Future<void> open() async {
    if (state.busy) return;
    final composition = ref.read(compositionProvider);
    state = const SwitchAccountState(busy: true);
    AppIssue? error;
    try {
      await composition.openAccountSwitch();
    } on AppIssue catch (issue) {
      error = issue;
    } catch (failure) {
      error = appIssueOf(failure);
    }
    if (!ref.mounted ||
        !identical(composition, ref.read(compositionProvider))) {
      return;
    }
    state = SwitchAccountState(error: error);
  }
}
