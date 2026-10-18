/// 異常の帯。**全 feature が使うので `lib/src/` の直下に置く**（`density.dart` と同じ位置）。
///
/// 設定の段で決めた形をそのまま持ってきた（2026-09-17）。**エラー詳細はコードとメッセージの
/// 2つだけで**、選択可能なテキストで示す。問い合わせ用の情報一式も履歴管理も作らない。
/// HTTP 本文・例外の `toString()`・設定の生値は秘密を含み得るので、ここへは来ない
/// （`非公開資料:ui-state-model.md`「設定でこの段に決めたこと」）。
///
/// **色は `ColorScheme` から採る。** 異常の帯は `errorContainer` / `onErrorContainer` である。
library;

import 'package:flutter/material.dart';
import 'package:karita_app/karita_app.dart';

/// 帯に並べる対応の1つ。**［詳細］［再試行］の手前に出す。**
class KaritaNoticeAction {
  const KaritaNoticeAction(this.label, this.onPressed, {this.key});

  final String label;
  final VoidCallback onPressed;
  final Key? key;
}

/// 短い状態文と、必要な対応だけ。
class KaritaNotice extends StatelessWidget {
  const KaritaNotice(
    this.text, {
    super.key,
    this.issue,
    this.retry,
    this.actions = const [],
  });

  final String text;

  /// 帯から直接とれる対応。**直す操作がある異常にだけ付ける**（世代変更の［合わせる］など）。
  final List<KaritaNoticeAction> actions;

  /// 詳細ダイアログに出す1件。**コードとメッセージの2つだけである。**
  final AppIssue? issue;

  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        color: scheme.errorContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
            ),
            Wrap(
              children: [
                for (final action in actions)
                  TextButton(
                    key: action.key,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onErrorContainer,
                    ),
                    onPressed: action.onPressed,
                    child: Text(action.label),
                  ),
                if (issue != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onErrorContainer,
                    ),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('エラーの詳細'),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            '${issue!.code}\n${issue!.message}',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('閉じる'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('詳細'),
                  ),
                if (retry != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onErrorContainer,
                    ),
                    onPressed: retry,
                    child: const Text('再試行'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
