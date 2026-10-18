/// 設定の［バックアップ］［復元］の2行と、復元の2枚のダイアログ。
///
/// 仕様は `../karita-ui-probe/docs/screens/settings.md`「本番の設定」— **共通管理画面は
/// 置かない。** 復元だけが「選択 → 影響確認」の2枚で、どちらも下部に［復元］［キャンセル］を
/// 1行で並べる。**確認画面で押したときだけ実行する。**
///
/// **止まった端末では選択の先頭に「別の端末で復元されたデータに合わせる」を出す**
/// （2026-09-24。`非公開資料:production-wiring-auth-backup-sync.md`「止まった端末は
/// ［復元］の選択から戻る」）。無いと、止まった側がバックアップを選んで今度は相手を止める。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';

import '../composition.dart';
import '../first_run/view.dart' show backupMoment, backupOrigin, platformLabel;
import '../notice.dart';
import '../setting_row.dart';
import 'state.dart';

/// ［バックアップ］行。現在値は最終作成日時または「未作成」。
class KaritaBackupRow extends ConsumerWidget {
  const KaritaBackupRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppBackupFacts facts;
    try {
      facts = ref.watch(backupFactsProvider);
    } catch (error) {
      return KaritaSettingRow(
        name: 'バックアップ',
        value: '状態を読み込めません。',
        trailing: KaritaNotice(
          'バックアップの状態を読み込めません。',
          issue: appIssueOf(error),
          retry: () => ref.invalidate(backupFactsProvider),
        ),
      );
    }
    if (!facts.available) {
      return const KaritaSettingRow(
        name: 'バックアップ',
        value: 'デモモードでは利用できません',
        description: 'デモでは Google ドライブへ保存しません。',
      );
    }
    final action = ref.watch(backupCreateProvider);
    final last = facts.lastBackupAt;
    return KaritaSettingRow(
      name: 'バックアップ',
      value: last == null ? '未作成' : backupMoment(last),
      description: 'この端末のデータを Google ドライブの専用領域へ保存します。',
      control: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 128),
        child: OutlinedButton(
          onPressed: action.busy
              ? null
              : () => ref.read(backupCreateProvider.notifier).create(),
          child: const Text('バックアップ'),
        ),
      ),
      trailing: action.busy
          ? const LinearProgressIndicator()
          : action.error == null
          ? null
          : KaritaNotice(
              'バックアップを作成できませんでした。この端末のデータは変わっていません。',
              issue: action.error,
              retry: () => ref.read(backupCreateProvider.notifier).create(),
            ),
    );
  }
}

/// ［復元］行。現在値は最終復元の対象または「未実行」。
class KaritaRestoreRow extends ConsumerWidget {
  const KaritaRestoreRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppBackupFacts facts;
    try {
      facts = ref.watch(backupFactsProvider);
    } catch (error) {
      return KaritaSettingRow(
        name: '復元',
        value: '状態を読み込めません。',
        trailing: KaritaNotice(
          '復元の状態を読み込めません。',
          issue: appIssueOf(error),
          retry: () => ref.invalidate(backupFactsProvider),
        ),
      );
    }
    if (!facts.available) {
      return const KaritaSettingRow(
        name: '復元',
        value: 'デモモードでは利用できません',
        description: 'デモでは Google ドライブから読み込みません。',
      );
    }
    return KaritaSettingRow(
      name: '復元',
      value: restoreTargetLabel(facts),
      description: facts.generationChanged
          ? '別の端末でデータが復元され、同期が止まっています。［復元］で'
                '「別の端末で復元されたデータに合わせる」を選ぶと再開します。'
          : 'バックアップを選び、この端末と他の端末の新しい正本にします。',
      control: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 128),
        child: OutlinedButton(
          onPressed: () => showRestoreDialog(context, ref),
          child: const Text('復元'),
        ),
      ),
    );
  }
}

/// ［初期化］行。**［復元］の下に独立して置く。**
///
/// 「空にしてやり直す」を復元ダイアログの選べる1候補に並べると、他のバックアップと同格の
/// 選択肢に見える。実体は業務データを消す別種の操作なので、専用の行と専用の確認ダイアログを
/// 持つ（2026-09-30。復元の選択肢に混ぜる案は違和感があるとして撤回した）。
class KaritaResetRow extends ConsumerWidget {
  const KaritaResetRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppBackupFacts facts;
    try {
      facts = ref.watch(backupFactsProvider);
    } catch (error) {
      return KaritaSettingRow(
        name: '初期化',
        value: '状態を読み込めません。',
        trailing: KaritaNotice(
          '初期化の状態を読み込めません。',
          issue: appIssueOf(error),
          retry: () => ref.invalidate(backupFactsProvider),
        ),
      );
    }
    if (!facts.available) {
      return const KaritaSettingRow(
        name: '初期化',
        value: 'デモモードでは利用できません',
        description: 'デモでは Google ドライブへ触れません。',
      );
    }
    return KaritaSettingRow(
      name: '初期化',
      description: 'この端末の本・貸出し・図書館の記録をすべて消し、空の状態から始めます。',
      control: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 128),
        child: OutlinedButton(
          onPressed: () => showResetDialog(context, ref),
          child: const Text('初期化'),
        ),
      ),
    );
  }
}

/// 初期化の確認ダイアログを開く。**走っている間は閉じられない。**
Future<void> showResetDialog(BuildContext context, WidgetRef ref) {
  ref.read(resetRunProvider.notifier).reset();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ResetDialog(),
  );
}

/// 初期化の確認。**選択画面は無い一発の確認である。** 押すまで何も変えない。
class ResetDialog extends ConsumerWidget {
  const ResetDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(resetRunProvider);
    // **成功したら閉じる。** 台帳は入れ替わり、画面の保持は `ledgerSessionProvider` で捨てられる。
    ref.listen(resetRunProvider, (previous, next) {
      if (next.done && !(previous?.done ?? false)) {
        Navigator.of(context).pop();
      }
    });
    final facts = ref.watch(backupFactsProvider);
    final lines = <String>[
      'この端末の本・貸出し・図書館の記録をすべて消し、'
          '空の状態を PC・スマホの新しい正本にします。',
      '他の端末は同期を停止します。その端末では［復元］から、'
          'このデータに合わせられます。',
      if (facts.unsent > 0) 'この端末でまだ送っていない変更 ${facts.unsent}件は失われます。',
    ];
    return PopScope(
      canPop: !run.busy,
      child: AlertDialog(
        title: const Text('初期化'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in lines) Text(line),
                if (run.busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (!run.busy && run.error != null)
                  KaritaNotice('初期化できませんでした。', issue: run.error),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('reset-proceed'),
            onPressed: run.busy
                ? null
                : () => ref.read(resetRunProvider.notifier).run(),
            child: const Text('実行'),
          ),
          TextButton(
            onPressed: run.busy ? null : () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
  }
}

/// 最終復元の対象。**復元した時刻ではなく、戻した先の時点を出す**（仕様「最終復元の対象」）。
String restoreTargetLabel(AppBackupFacts facts) {
  if (facts.lastRestoreAt == null) return '未実行';
  final created = facts.lastRestoreCreatedAt;
  final moment = created == null || created.isEmpty
      ? '作成日時が不明'
      : backupMoment(created);
  return '$moment・${platformLabel(facts.lastRestorePlatform)}';
}

/// 復元のダイアログを開く。**走っている間は閉じられない。**
///
/// [initial] は選択画面で最初から選ばれている1件である。世代変更の手順のダイアログの［合わせる］が
/// `RestoreChoice.rejoin()` を渡す（`backup/generation_notice.dart`）。**確認画面は飛ばさない**
/// — 置き換えの影響は必ず2枚目で見せてから実行する。
Future<void> showRestoreDialog(
  BuildContext context,
  WidgetRef ref, {
  RestoreChoice? initial,
}) {
  ref.read(restoreRunProvider.notifier).reset();
  ref.invalidate(restoreCandidatesProvider);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RestoreDialog(initial: initial),
  );
}

/// 選択 → 影響確認の2枚。**1つのダイアログの中で入れ替える。**
class RestoreDialog extends ConsumerStatefulWidget {
  const RestoreDialog({super.key, this.initial});

  /// 最初から選ばれている1件。`null` なら何も選ばれていない。
  final RestoreChoice? initial;

  @override
  ConsumerState<RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends ConsumerState<RestoreDialog> {
  late RestoreChoice? _selected = widget.initial;
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(restoreRunProvider);
    // **成功したら閉じる。** 台帳は入れ替わり、画面の保持は `ledgerSessionProvider` で捨てられる。
    ref.listen(restoreRunProvider, (previous, next) {
      if (next.done && !(previous?.done ?? false)) {
        Navigator.of(context).pop();
      }
    });
    final facts = ref.watch(backupFactsProvider);
    final selected = _selected;
    final confirming = _confirming && selected != null;
    return PopScope(
      canPop: !run.busy,
      child: AlertDialog(
        title: Text(confirming ? '完全復元' : '復元するデータを選択'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: confirming
                ? _Impact(choice: selected, facts: facts, run: run)
                : _Choices(
                    facts: facts,
                    selected: selected,
                    onSelect: (choice) => setState(() => _selected = choice),
                  ),
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('restore-proceed'),
            onPressed: selected == null || run.busy
                ? null
                : confirming
                ? () => ref.read(restoreRunProvider.notifier).run(selected)
                : () => setState(() => _confirming = true),
            child: const Text('復元'),
          ),
          TextButton(
            onPressed: run.busy ? null : () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
  }
}

/// 1枚目。**止まった端末では先頭に「合わせる」を出し、区切ってからバックアップを並べる。**
class _Choices extends ConsumerWidget {
  const _Choices({
    required this.facts,
    required this.selected,
    required this.onSelect,
  });

  final AppBackupFacts facts;
  final RestoreChoice? selected;
  final ValueChanged<RestoreChoice> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(restoreCandidatesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (facts.generationChanged) ...[
          _ChoiceTile(
            key: const ValueKey('restore-rejoin'),
            title: '別の端末で復元されたデータに合わせる',
            subtitle: 'この端末の同期を再開します。他の端末には影響しません。',
            selected: selected == const RestoreChoice.rejoin(),
            onTap: () => onSelect(const RestoreChoice.rejoin()),
          ),
          const Divider(height: 24),
        ],
        listing.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => KaritaNotice(
            'バックアップの一覧を読み込めません。',
            issue: appIssueOf(error),
            retry: () => ref.invalidate(restoreCandidatesProvider),
          ),
          data: (value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value.items.isEmpty) const Text('選べるバックアップがありません。'),
              for (final backup in value.items)
                _ChoiceTile(
                  key: ValueKey('restore-${backup.backupId}'),
                  title: backupMoment(backup.createdAtUtc),
                  subtitle: backup.readable
                      ? [backupOrigin(backup), ?countsLabel(backup)].join('　')
                      : '新しい版のアプリで作られています。アプリの更新が必要です。',
                  selected: selected == RestoreChoice.backup(backup),
                  onTap: backup.readable
                      ? () => onSelect(RestoreChoice.backup(backup))
                      : null,
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
      ],
    );
  }
}

/// 件数の1行。索引に無ければ出さない。
String? countsLabel(AppBackup backup) {
  final books = backup.books;
  final loans = backup.loans;
  if (books == null && loans == null) return null;
  return [
    if (books != null) '本 $books冊',
    if (loans != null) '貸出記録 $loans件',
  ].join('・');
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    enabled: onTap != null,
    selected: selected,
    leading: Icon(
      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
    ),
    title: Text(title),
    subtitle: Text(subtitle),
    onTap: onTap,
  );
}

/// 2枚目。**押すまで何も変えない。**
///
/// 出すのは3つだけである — 選んだ時点より後の変更は戻らない、他の端末の同期が止まる
/// （「合わせる」では出さない）、この端末の未送信の変更は失われる。**「サインインし直し」は
/// 出さない** — 同じ端末の復元では資格情報も端末設定も置換の外にある。
class _Impact extends StatelessWidget {
  const _Impact({required this.choice, required this.facts, required this.run});

  final RestoreChoice choice;
  final AppBackupFacts facts;
  final BackupActionState run;

  @override
  Widget build(BuildContext context) {
    final backup = choice.backup;
    final lines = <String>[
      if (backup == null) ...[
        '選択: 別の端末で復元されたデータ',
        '',
        'この端末のデータを、別の端末で復元されたデータに置き換えます。',
        '他の端末には影響しません。',
      ] else ...[
        '選択: ${backupMoment(backup.createdAtUtc)} / '
            '${platformLabel(backup.createdOn)}',
        ?countsLabel(backup),
        '',
        '現在のデータをリセットし、このバックアップを'
            'PC・スマホの新しい正本にします。',
        'バックアップ後の変更は取り込みません。',
        '他の端末は同期を停止します。その端末では［復元］から、'
            'このデータに合わせられます。',
      ],
      if (facts.unsent > 0) 'この端末でまだ送っていない変更 ${facts.unsent}件は失われます。',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in lines)
          line.isEmpty ? const SizedBox(height: 8) : Text(line),
        if (run.busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (!run.busy && run.error != null)
          KaritaNotice('復元できませんでした。', issue: run.error),
      ],
    );
  }
}
