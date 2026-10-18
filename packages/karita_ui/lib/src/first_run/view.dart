/// 初回起動の画面。**起動ゲートの本体である。**
///
/// 仕様は `../karita-ui-probe/docs/screens/settings.md`「初回と復元」 —
/// **初回はサインイン後、通常の開始・合流と補助の復旧導線を表示する**である。
///
/// **先頭はサインインである。** 未認可では一覧が引けない（`TransportAuthError`）ので、
/// サインインしていない端末に2択を見せても片方が必ず失敗する
/// （`非公開資料:production-wiring-auth-backup-sync.md`「実装順」）。
///
/// **ここは Navbar の外である。** ゲートが閉じている間はタブを出さない — 行き先のどれもが
/// 台帳を要るためである（`shell/shell.dart`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';

import '../account/state.dart';
import '../notice.dart';
import 'state.dart';

/// 本文の最大幅。**設定画面と同じ数字である**（`settings/view.dart`）。
const double _contentMaxWidth = 640;

class FirstRunScreen extends ConsumerWidget {
  const FirstRunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authStatusProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: status.when(
                loading: () => const _Frame(
                  key: ValueKey('first-run-loading'),
                  children: [LinearProgressIndicator()],
                ),
                error: (_, _) => _Frame(
                  key: const ValueKey('first-run-auth-error'),
                  children: [
                    KaritaNotice(
                      '接続の状態を読み込めません。',
                      issue: const AppIssue(
                        'auth-status-read',
                        'Auth status could not be read.',
                      ),
                      retry: () => ref.invalidate(authStatusProvider),
                    ),
                  ],
                ),
                // **サインイン済みのときだけ2択を出す。**
                data: (value) => value.state == AppAuthState.signedIn
                    ? const _Choice()
                    : const _SignIn(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 見出しと本文の枠。**3つの段（サインイン・2択・一覧）で同じ形を使う。**
class _Frame extends StatelessWidget {
  const _Frame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('karita をはじめる', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

/// 段1。**先頭はサインインである。**
class _SignIn extends ConsumerWidget {
  const _SignIn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(authActionProvider);
    // **「接続が切れた」と「まだ繋いでいない」で文言を変える。** どちらも押す操作は同じ
    // ［サインイン］だが、利用者から見ると起きたことが違う。
    final reauth = ref
        .watch(authStatusProvider)
        .when(
          data: (value) => value.state == AppAuthState.reauthRequired,
          loading: () => false,
          error: (_, _) => false,
        );
    return _Frame(
      key: const ValueKey('first-run-sign-in'),
      children: [
        Text(
          reauth
              ? '接続が切れています。同じ Google アカウントでサインインし直してください。'
              : '記録の同期とバックアップに Google ドライブを使います。'
                    'はじめにサインインしてください。',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: action.busy
                ? null
                : () => ref.read(authActionProvider.notifier).signIn(),
            child: const Text('サインイン'),
          ),
        ),
        if (action.busy) const LinearProgressIndicator(),
        if (!action.busy && action.error != null)
          KaritaNotice(
            'サインインできませんでした。この端末の接続は変わっていません。',
            issue: action.error,
            retry: () => ref.read(authActionProvider.notifier).signIn(),
          ),
      ],
    );
  }
}

/// 段2。**通常の開始・合流を主操作とし、復旧はリンクで案内する。**
///
/// **言葉は保管先の事実で変える**（2026-10-15）。ほかの端末が使っている記録があるときの
/// 「引き継ぐ」は、新しい端末を足す操作ではなく**全端末を選んだ時点へ戻す宣言**である。
/// 機種変更のつもりで選ぶと、他の端末が止まり、［合わせる］で古い時点へ巻き戻る。
/// そこで記録があるときは、合流を先頭の主ボタンに置き、戻す方は控えめにして確認を挟む。
class _Choice extends ConsumerStatefulWidget {
  const _Choice();

  @override
  ConsumerState<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends ConsumerState<_Choice> {
  /// 一覧を開いているか。**画面の中だけの表示条件である**（機能の Draft にしない）。
  bool _choosing = false;

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(firstRunSetupProvider);
    final probe = ref.watch(firstRunSharedRecordsProvider);
    if (probe.isLoading) {
      return const _Frame(
        key: ValueKey('first-run-probing'),
        children: [
          Text('この Google アカウントの記録を確かめています。'),
          SizedBox(height: 12),
          LinearProgressIndicator(),
        ],
      );
    }
    // **読めなければ「ある」側で出す。** 無い側の言葉で出すと、確認を挟まずに他の端末を
    // 戻せてしまう。読めない保管先では「新しく始める」もどのみち完了しない。
    final shared = probe.value ?? true;
    if (_choosing) {
      return _BackupList(busy: setup.busy, shared: shared, onBack: _back);
    }

    final notifier = ref.read(firstRunSetupProvider.notifier);
    return _Frame(
      key: const ValueKey('first-run-choice'),
      children: [
        Text(
          shared ? 'この Google アカウントには、ほかの端末で使っている記録があります。' : 'この端末の始め方を選びます。',
        ),
        const SizedBox(height: 16),
        if (shared) ...[
          _Option(
            title: '今の記録に合流する（おすすめ）',
            description:
                'ほかの端末で使っている記録を、そのままこの端末に取り込みます。'
                'ほかの端末には影響しません。新しい端末を追加するときはこちらを選びます。',
            action: '合流する',
            onPressed: setup.busy ? null : notifier.startFresh,
          ),
        ] else ...[
          _Option(
            title: '新しく始める',
            description: 'この端末で記録を始めます。',
            action: '新しく始める',
            onPressed: setup.busy ? null : notifier.startFresh,
          ),
        ],
        ref
            .watch(firstRunBackupsProvider)
            .when(
              loading: () => const Text('バックアップを確認しています。'),
              error: (_, _) => KaritaNotice(
                'バックアップの一覧を読み込めません。通常の開始・合流はそのまま行えます。',
                issue: const AppIssue(
                  'backup-list',
                  'Backups could not be listed.',
                ),
                retry: () => ref.invalidate(firstRunBackupsProvider),
              ),
              data: (listing) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (listing.items.isNotEmpty) ...[
                    TextButton(
                      onPressed: setup.busy
                          ? null
                          : () => setState(() => _choosing = true),
                      child: const Text('バックアップから復旧する'),
                    ),
                    Text(
                      '記録を過去の時点へ戻す場合に使います。端末追加には不要です。'
                      '${shared ? 'ほかの端末は同期が止まり、復元したデータに合わせる操作が必要です。' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (listing.skipped > 0)
                    Text('読み取れないバックアップが ${listing.skipped} 件あります。'),
                ],
              ),
            ),
        if (setup.busy) const LinearProgressIndicator(),
        if (!setup.busy && setup.error != null) _SetupError(state: setup),
      ],
    );
  }

  void _back() => setState(() => _choosing = false);
}

/// 通常の開始・合流の案内。
class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.description,
    required this.action,
    required this.onPressed,
  });

  final String title;
  final String description;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(description, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(onPressed: onPressed, child: Text(action)),
          ),
        ],
      ),
    );
  }
}

/// 引き継ぐ1件を選ぶ。**選べるのは一覧に出るものだけである。**
class _BackupList extends ConsumerWidget {
  const _BackupList({
    required this.busy,
    required this.shared,
    required this.onBack,
  });

  final bool busy;

  /// ほかの端末が使っている記録があるか。**あれば、選んだ後に影響の確認を挟む。**
  final bool shared;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(firstRunBackupsProvider);
    final setup = ref.watch(firstRunSetupProvider);
    return _Frame(
      key: const ValueKey('first-run-backups'),
      children: [
        const Text('復旧する時点のバックアップを選びます。'),
        const SizedBox(height: 12),
        listing.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => KaritaNotice(
            'バックアップの一覧を読み込めません。',
            issue: const AppIssue(
              'backup-list',
              'Backups could not be listed.',
            ),
            retry: () => ref.invalidate(firstRunBackupsProvider),
          ),
          data: (value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value.items.isEmpty)
                const Text('選べるバックアップがありません。')
              else
                for (final backup in value.items)
                  _BackupTile(
                    backup: backup,
                    onPressed: busy
                        ? null
                        : () => _startChecked(
                            context,
                            ref,
                            backup,
                            shared: shared,
                          ),
                  ),
              // **読めなかったものは数だけ出す。** 黙って落とすと、索引を書けていない
              // 不具合が「1つも無い」という形でしか現れない。
              if (value.skipped > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '読み取れないバックアップが ${value.skipped} 件あります。'
                    '一覧には出していません。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (!busy && setup.error != null) _SetupError(state: setup),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: busy ? null : onBack,
            child: const Text('戻る'),
          ),
        ),
      ],
    );
  }
}

/// 選んだ1件で始める。**記録があるときは、影響を見せてから進める。**
Future<void> _startChecked(
  BuildContext context,
  WidgetRef ref,
  AppBackup backup, {
  required bool shared,
}) async {
  if (shared && !await confirmRewindOthers(context, backup)) return;
  await ref
      .read(firstRunSetupProvider.notifier)
      .startFromBackup(backup.backupId);
}

/// 他の端末を選んだ時点へ戻すことの確認。**戻すときだけ `true`。**
///
/// 出すのは仕様の影響確認のうち初回に当てはまる2つ — 選んだ時点より後の変更が失われること、
/// 他の端末の同期が止まること（`karita-ui-probe/docs/screens/settings.md`「初回と復元」）。
/// この端末にはまだ未送信が無いので、件数は出さない。
Future<bool> confirmRewindOthers(BuildContext context, AppBackup backup) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('first-run-rewind-confirm'),
      title: const Text('ほかの端末の同期が止まります'),
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '選んだバックアップ（${backupMoment(backup.createdAtUtc)}・'
              '${platformLabel(backup.createdOn)}）の時点に、すべての端末を戻します。',
            ),
            const SizedBox(height: 8),
            const Text('・この時点より後にほかの端末で加えた変更は失われます。'),
            const Text('・ほかの端末では、［合わせる］の操作が必要になります。'),
            const SizedBox(height: 8),
            const Text('新しい端末を追加するだけなら、［今の記録に合流する］を使ってください。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('戻る'),
        ),
        FilledButton(
          key: const ValueKey('first-run-rewind-confirm-ok'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('戻して始める'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({required this.backup, required this.onPressed});

  final AppBackup backup;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(backupMoment(backup.createdAtUtc)),
                Text(backupOrigin(backup), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          FilledButton(
            onPressed: onPressed,
            child: const Text('このバックアップで復旧する'),
          ),
        ],
      ),
    );
  }
}

/// 失敗の帯。**2択と一覧で同じ文言を出す。**
class _SetupError extends ConsumerWidget {
  const _SetupError({required this.state});

  final FirstRunState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => KaritaNotice(
    state.fromBackup
        ? '引き継げませんでした。台帳はまだ作られていません。'
        : '始められませんでした。台帳はまだ作られていません。',
    issue: state.error,
    retry: () => state.fromBackup && state.backupId != null
        ? ref
              .read(firstRunSetupProvider.notifier)
              .startFromBackup(state.backupId!)
        : ref.read(firstRunSetupProvider.notifier).startFresh(),
  );
}

/// 作成時刻。**作成端末の時計である** — 秒とタイムゾーンまでは出さない。
///
/// 読めない値はそのまま出す。**取り繕わない** — 索引が壊れていることは見えたほうがよい。
String backupMoment(String createdAtUtc) {
  final parsed = DateTime.tryParse(createdAtUtc);
  if (parsed == null) return createdAtUtc.isEmpty ? '作成日時が不明' : createdAtUtc;
  final local = parsed.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// 作成端末の素性（`windows` / `android`）を利用者の言葉にする。
String platformLabel(String platform) => switch (platform) {
  'windows' => 'Windows',
  'android' => 'Android',
  '' => '作成端末が不明',
  final other => other,
};

/// 作成端末とおおよその大きさ。
String backupOrigin(AppBackup backup) {
  final platform = platformLabel(backup.createdOn);
  if (backup.sizeBytes <= 0) return platform;
  final mega = backup.sizeBytes / (1024 * 1024);
  final size = mega >= 1
      ? '${mega.toStringAsFixed(1)} MB'
      : '${(backup.sizeBytes / 1024).round()} KB';
  return '$platform・$size';
}
