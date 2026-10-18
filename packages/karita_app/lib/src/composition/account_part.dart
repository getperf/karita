part of '../composition.dart';

/// アカウント。認可の状態・サインイン・サインアウト・アカウントの切替。
///
/// **状態（フィールド）は持たない** — 拡張は持てないので、本体（`composition.dart`）に置く。
extension CompositionAccount on Composition {
  /// ［アカウント］行の3状態。**トークンもメールも生では出さない。**
  ///
  /// **2つの事実から組む。** 接続の有無は認可の実装（[Authorization.authorized]）、認可を
  /// 失って止まっているかは7状態（`signInRequired`）である。**判定規則を複製しない** —
  /// `blocked_auth` の読み方は `SyncEngine` に1つだけ在る。
  ///
  /// **接続が無いほうが強い。** 両方立ちうる端末は「未サインイン」と出す — まだ一度も
  /// 繋いでいない端末に「再サインインが必要」と出しても、何を再びするのか分からない。
  Future<AppAuthStatus> authStatus() async {
    _requireOpen();
    final present = await auth.authorized();
    final state = !present
        ? AppAuthState.signedOut
        : syncStatus.state == AppSyncState.signInRequired
        ? AppAuthState.reauthRequired
        : AppAuthState.signedIn;
    return AppAuthStatus(
      state: state,
      kind: auth.kind,
      available: mode.gate.open,
      canSwitchAccount: Platform.isAndroid,
    );
  }

  /// 設定画面の表示時に呼ぶ。**保管先を読めなければ何もしない**
  /// （[_checkAccountIdentity]。`非公開資料:production-wiring-auth-backup-sync.md`
  /// 「同期の前と設定画面の表示時に突き合わせる」）。
  Future<void> refreshAccountIdentity() async {
    _requireOpen();
    if (!mode.gate.open) return;
    await _checkAccountIdentity();
  }

  /// Google アカウントの切替導線。**このアプリから grant を取り消せない**ので、外部の
  /// アカウント管理ページへ出す（`非公開資料:production-wiring-auth-backup-sync.md`
  /// 「切替の導線」）。
  ///
  /// **Android の分である。** Windows はサインインのたびにブラウザでアカウント選択が出るので
  /// この導線を要らない — 画面のどこにボタンを出すかは呼び出し側（Android の判定）が決める。
  Future<void> openAccountSwitch() async {
    _requireOpen();
    await openSite(Uri.parse('https://myaccount.google.com/connections'));
  }

  /// ［サインイン］。**走ったときだけ `true` を返す**（デモでは走らない）。
  ///
  /// **成功後に2つ打つ。** 画面への通知（[_notifyStatus]）と、起動時と同じ同期の契機
  /// （[RefreshTrigger.startup]）である。繋がないと、サインインしたのに画面が古いままで、
  /// 次の周期が来るまで同期も始まらない。
  Future<bool> signIn() async {
    _requireOpen();
    final Attempt<Object?> attempt;
    try {
      attempt = await mode.gate.run<Object?>(() async {
        await auth.signIn();
        return null;
      });
    } catch (error) {
      _failed('auth.sign_in.failed', error);
    }
    if (attempt.wasSkipped) return false;
    _log.info('auth.signed_in', {'kind': auth.kind});
    _notifyStatus();
    await refresh?.trigger(RefreshTrigger.startup);
    return true;
  }

  /// ［サインアウト］。**接続の解除までである。**
  ///
  /// **grant は Google 側に残る**ので、画面は「サインアウトした」と言い切らない。
  /// 別アカウントへの切替は非目標で、
  /// 変えるときは外部の導線（`myaccount.google.com/connections`）へ出す — それは段5 である。
  ///
  /// **同期の契機を打たない。** 解除した直後に走らせると、認可が無いまま転送へ出て
  /// `blocked_auth` を自分で作る。
  Future<bool> signOut() async {
    _requireOpen();
    final Attempt<Object?> attempt;
    try {
      attempt = await mode.gate.run<Object?>(() async {
        await auth.signOut();
        return null;
      });
    } catch (error) {
      _failed('auth.sign_out.failed', error);
    }
    if (attempt.wasSkipped) return false;
    _log.info('auth.signed_out', {'kind': auth.kind});
    _notifyStatus();
    return true;
  }
}
