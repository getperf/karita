/// 設定の［アカウント］行。
///
/// 表示するのは
/// **未サインイン／サインイン済み／再サインインが必要**と、必要時の［サインイン］である。
///
/// **メールアドレスを出さない。** この段で出せるのは3状態だけで、出せないものを空欄で
/// 見せない（`about.get` は段5 で入ったが、メール表示は本番 GUI の仕様に無い）。
///
/// **Windows・iOS の［サインアウト］は「接続の解除」までである。** grant は Google 側に残るので、
/// 「サインアウトしました」と言い切らない。別アカウントへの切替は非目標である
/// （仕様の「決着」②）。
///
/// **Android には［サインアウト］ボタンを置かない**（2026-09-25。実機で確認して撤回した）。
/// `AndroidAccessTokenProvider.accessToken` は `forceRefresh` に関わらず必ず
/// `tokenForScopes` を呼び、grant が生きている限り無音で新しいトークンを返す。**`clearLocalState`
/// を挟んでも次の同期呼び出しで再認可されてしまい、「同期を止める」が事実と合わない**
/// （`非公開資料:production-wiring-auth-backup-sync.md`「サインアウトが効かない」）。
/// **Android で唯一実効性を持つのは外部の接続解除導線だけなので、それを control のボタン
/// にした**（[AppAuthStatus.canSwitchAccount]）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';

import '../setting_row.dart';
import '../notice.dart';
import '../settings/state.dart' show syncStatusProvider;
import '../settings/wording.dart' show accountMismatchNotice;
import 'state.dart';

/// 3状態の文言。**画面のどこから出しても同じ言葉にする。**
String authLabel(AppAuthState state) => switch (state) {
  AppAuthState.signedOut => '未サインイン',
  AppAuthState.signedIn => 'サインイン済み',
  AppAuthState.reauthRequired => '再サインインが必要',
};

class KaritaAccountRow extends ConsumerWidget {
  const KaritaAccountRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authStatusProvider);
    final action = ref.watch(authActionProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final mismatch = syncStatus.maybeWhen(
      data: (value) => value.accountMismatch,
      orElse: () => null,
    );
    final switchAction = ref.watch(accountSwitchActionProvider);

    return status.when(
      loading: () => const KaritaSettingRow(name: 'アカウント', value: '確認しています…'),
      error: (_, _) => KaritaSettingRow(
        name: 'アカウント',
        value: '状態を読み込めません。',
        trailing: KaritaNotice(
          '接続の状態を読み込めません。',
          issue: const AppIssue(
            'auth-status-read',
            'Auth status could not be read.',
          ),
          retry: () => ref.invalidate(authStatusProvider),
        ),
      ),
      data: (value) {
        // **デモでは操作を置かない。** 合成層が「利用できない」と言っているものに、
        // 押せるボタンを出さない（押しても何も起きないボタンは不具合に見える）。
        if (!value.available) {
          return const KaritaSettingRow(
            name: 'アカウント',
            value: 'デモモードでは利用できません',
            description: 'デモでは Google アカウントへ接続しません。',
          );
        }
        final signedIn = value.state == AppAuthState.signedIn;
        // **Android では［サインアウト］そのものを持たない。** control のボタンは
        // サインイン／サインアウト／接続の解除画面の3択で、後2つは同時に出ない。
        final canSwitch = value.canSwitchAccount;

        final Widget control;
        if (!signedIn) {
          control = FilledButton(
            onPressed: action.busy
                ? null
                : () => ref.read(authActionProvider.notifier).signIn(),
            child: const Text('サインイン'),
          );
        } else if (canSwitch) {
          control = OutlinedButton(
            onPressed: switchAction.busy
                ? null
                : () => ref.read(accountSwitchActionProvider.notifier).open(),
            child: const Text('接続の解除画面を開く'),
          );
        } else {
          control = OutlinedButton(
            onPressed: action.busy
                ? null
                : () => ref.read(authActionProvider.notifier).signOut(),
            child: const Text('サインアウト'),
          );
        }

        Widget? trailing;
        if (action.busy || switchAction.busy) {
          trailing = const LinearProgressIndicator();
        } else if (action.error != null) {
          trailing = KaritaNotice(
            action.signingIn
                ? 'サインインできませんでした。この端末の接続は変わっていません。'
                : 'サインアウトできませんでした。接続は解除されていません。',
            issue: action.error,
            retry: () => action.signingIn
                ? ref.read(authActionProvider.notifier).signIn()
                : ref.read(authActionProvider.notifier).signOut(),
          );
        } else if (switchAction.error != null) {
          trailing = KaritaNotice(
            '接続の解除画面を開けませんでした。',
            issue: switchAction.error,
            retry: () => ref.read(accountSwitchActionProvider.notifier).open(),
          );
        } else if (signedIn && mismatch != null) {
          trailing = KaritaNotice(accountMismatchNotice, issue: mismatch);
        }

        return KaritaSettingRow(
          name: 'アカウント',
          value: authLabel(value.state),
          description: !signedIn
              ? 'サインインすると、Google ドライブの専用領域で同期とバックアップを行います。'
              : canSwitch
              ? 'この端末の接続を切り替えるには、外部の接続の解除画面から行ってください。'
              : 'サインアウトすると同期を止め、この端末の接続を解除します。'
                    'Google 側の許可は残ります。',
          control: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 128),
            child: control,
          ),
          trailing: trailing,
        );
      },
    );
  }
}
