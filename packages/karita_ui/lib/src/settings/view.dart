import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';

import '../account/view.dart';
import '../backup/generation_notice.dart';
import '../backup/view.dart';
import '../browser_link/state.dart';
import '../browser_link/view.dart';
import '../composition.dart';
import '../density.dart';
import '../libraries/state.dart';
import '../libraries/view.dart';
import '../notice.dart';
import '../setting_row.dart';
import 'state.dart';
import 'wording.dart';

/// ［設定］タブの本文。**設定画面と図書館管理を入れ替える器である。**
///
/// 図書館管理は専用の Navbar タブを持たず、設定の［図書館設定］行から入る
/// （`karita-ui-probe/docs/screens/libraries.md`）。**外殻は触らない** — 行き先は4つのままで、
/// 入れ替わるのはこのタブの中だけである。
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key, required this.contentMaxWidth});
  final double contentMaxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(librariesRouteProvider).isOpen
      ? LibrariesView(contentMaxWidth: contentMaxWidth)
      : _SettingsScreen(contentMaxWidth: contentMaxWidth);
}

class _SettingsScreen extends ConsumerWidget {
  const _SettingsScreen({required this.contentMaxWidth});
  final double contentMaxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ref.watch(syncStatusProvider);
    final mode = ref.watch(themeModeProvider);
    final save = ref.watch(themeSaveProvider);
    final density = ref.watch(densityProvider);
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 画面自身のヘッダー。異常文・文字拡大に合わせて高さが伸びる。
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('設定', style: theme.textTheme.titleMedium),
                  status.when(
                    data: (value) {
                      // **宣言順で1つだけ出す。** 同時に立ちうるが、並べると利用者が
                      // どちらへ対応すべきか読めない。7状態が最優先。
                      final notice = syncNotice(value.state);
                      if (notice != null) {
                        return KaritaNotice(notice, issue: value.issue);
                      }
                      if (value.accountMismatch != null) {
                        return KaritaNotice(
                          accountMismatchNotice,
                          issue: value.accountMismatch,
                        );
                      }
                      if (value.generationChanged != null) {
                        return GenerationChangedNotice(
                          issue: value.generationChanged!,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => KaritaNotice(
                      '同期状態を読み込めません。',
                      issue: const AppIssue(
                        'sync-status-read',
                        'Sync status could not be read.',
                      ),
                      retry: () => ref.invalidate(syncStatusProvider),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: ConstrainedBox(
                key: const ValueKey('settings-content'),
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                  children: [
                    const _Heading('基本設定'),
                    const KaritaAccountRow(),
                    KaritaSettingRow(
                      name: 'テーマ',
                      description: 'この端末での表示に適用します。',
                      control: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: density.control),
                        child: DropdownButton<String>(
                          value: mode.name,
                          isDense: true,
                          items: [
                            for (final item in themeLabels.entries)
                              DropdownMenuItem(
                                value: item.key,
                                child: Text(item.value),
                              ),
                          ],
                          onChanged: save.saving
                              ? null
                              : (value) async {
                                  if (value != null) {
                                    await ref
                                        .read(themeSaveProvider.notifier)
                                        .save(value);
                                  }
                                },
                        ),
                      ),
                      trailing: save.saving
                          ? const LinearProgressIndicator()
                          : save.error == null
                          ? null
                          : KaritaNotice(
                              'テーマを保存できませんでした。前の設定を使用しています。',
                              issue: save.error,
                              retry: () => ref
                                  .read(themeSaveProvider.notifier)
                                  .save(save.attempted!),
                            ),
                    ),
                    const _LibrariesRow(),
                    const _BrowserLinkRow(),
                    const _BrowserChoiceRow(),
                    const _Heading('その他'),
                    const KaritaBackupRow(),
                    const KaritaRestoreRow(),
                    const KaritaResetRow(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ブラウザープラグインの行。**Windows の本番だけに出す**（2026-10-15）。
class _BrowserLinkRow extends ConsumerWidget {
  const _BrowserLinkRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(browserLinkProvider);
    if (!link.applicable) return const SizedBox.shrink();
    return KaritaSettingRow(
      key: const ValueKey('settings-browser-link'),
      name: 'ブラウザープラグイン',
      value: link.linked
          ? '確認済み'
          : link.skipped
          ? '未設定（あとで設定）'
          : '未確認',
      description: 'Edge・Chrome・Firefox のプラグインから karita へ送れるかを確かめます。',
      control: TextButton(
        onPressed: () => openBrowserLinkScreen(context),
        child: const Text('確認する'),
      ),
    );
  }
}

/// 開くブラウザーの行（2026-10-16）。**プラグインの行と同じく Windows の本番だけに出す。**
///
/// 見つからないブラウザーは選べなくする。選んであったものが消えたときは、OS の既定で
/// 開くことを行の下で知らせる（合成層が開き直す）。
class _BrowserChoiceRow extends ConsumerWidget {
  const _BrowserChoiceRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(browserLinkProvider).applicable) {
      return const SizedBox.shrink();
    }
    final choice = ref.watch(browserChoiceProvider);
    final installed = ref.watch(installedBrowsersProvider);
    final density = ref.watch(densityProvider);
    final found = installed.value;
    bool available(String value) =>
        value == 'system' || found == null || found.contains(value);
    return KaritaSettingRow(
      key: const ValueKey('settings-browser-choice'),
      name: '開くブラウザー',
      description: '図書館サイトを開くブラウザーです。プラグインを入れたものを選びます。',
      control: ConstrainedBox(
        constraints: BoxConstraints(minHeight: density.control),
        child: DropdownButton<String>(
          value: choice.value,
          isDense: true,
          items: [
            for (final item in browserLabels.entries)
              DropdownMenuItem(
                value: item.key,
                enabled: available(item.key),
                child: Text(
                  available(item.key) ? item.value : '${item.value}（見つかりません）',
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              ref.read(browserChoiceProvider.notifier).save(value);
            }
          },
        ),
      ),
      trailing: choice.error != null
          ? KaritaNotice(
              '開くブラウザーを保存できませんでした。前の設定を使用しています。',
              issue: choice.error,
            )
          : !available(choice.value)
          ? const KaritaNotice('選んだブラウザーが見つかりません。システムの既定で開きます。')
          : null,
    );
  }
}

/// 図書館設定の行。**現在値は区のリスト、操作は専用 UI への［設定］である**
/// （`karita-ui-probe/docs/screens/settings.md` の表）。
class _LibrariesRow extends ConsumerWidget {
  const _LibrariesRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String value;
    try {
      final systems = ref.watch(libraryListProvider);
      // **`name` を並べない。** カーリルの `systemname` をそのまま採っているので
      // （2026-09-16 の決定）、`東京都江東区・東京都墨田区・…` と都道府県が繰り返される。
      // 仕様が言う「区のリスト」は `city` のほうである。
      value = systems.isEmpty
          ? '未登録'
          : systems.map((system) => system.city).join('・');
    } catch (error) {
      final issue = appIssueOf(error);
      // **入口は閉じない。** 一覧の側も同じ失敗を出して再試行を持つので、行から進めなく
      // すると読み直す手段が設定の行だけになる。
      return KaritaSettingRow(
        name: '図書館設定',
        description: '利用する図書館、常用館、マイページを設定します。',
        control: TextButton(
          onPressed: () => ref.read(librariesRouteProvider.notifier).openList(),
          child: const Text('設定'),
        ),
        trailing: KaritaNotice(
          '図書館を読み込めません。',
          issue: issue,
          retry: () => ref.invalidate(librariesProvider),
        ),
      );
    }
    return KaritaSettingRow(
      name: '図書館設定',
      value: value,
      description: '利用する図書館、常用館、マイページを設定します。',
      control: TextButton(
        onPressed: () => ref.read(librariesRouteProvider.notifier).openList(),
        child: const Text('設定'),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
