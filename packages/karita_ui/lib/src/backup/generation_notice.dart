/// 同期世代が変わって止まっている端末の帯と、戻る手順。
///
/// **全画面に出し、帯から戻れるようにする**（2026-10-08 改訂。
/// `非公開資料:production-wiring-auth-backup-sync.md`「世代変更は通知だけにする」）。
/// 設定の帯だけでは、予約・貸出し・本棚しか開かない利用者が5日間止まったことに気づかなかった。
///
/// 帯は［手順］［詳細］の2つだけを持つ。**［合わせる］は手順のダイアログの中に置く**
/// （2026-10-08）— 帯にも並べると同じ操作が2か所に出て、手順を読まずに押せてしまう。
/// ［合わせる］は復元のダイアログを「別の端末で復元されたデータに合わせる」を選んだ状態で
/// 開く。**確認画面は飛ばさない** — この端末の変更が失われる操作なので、影響は必ず2枚目で
/// 見せる。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';

import '../notice.dart';
import 'state.dart';
import 'view.dart';

/// 帯の文言。**何が起きたか・どうなっているか・何を押せばよいか**の3つだけを書く。
const String generationChangedNotice =
    '他の端末でデータが復元されたため、この端末の同期は停止しています。'
    '［手順］から、そのデータに合わせると同期が再開します。';

/// 手順のダイアログの本文。**設定から辿る道を省かずに書く** — ［合わせる］が使えない場面
/// （帯を閉じた後に思い出したときなど）でも、同じ操作に辿り着けるようにする。
const List<String> generationChangedSteps = [
  '別の端末で、バックアップからの復元が行われました。'
      'そのため、この端末の同期を停止しています。',
  '次の手順で、この端末のデータを別の端末で復元されたデータに合わせると、同期が再開します。',
  '',
  '1. ［設定］を開き、［復元］行の［復元］を押す',
  '2. 「別の端末で復元されたデータに合わせる」を選び、［復元］を押す',
  '3. 「完全復元」の確認で内容を確かめ、［復元］を押す',
  '',
  '下の［合わせる］を押すと、手順2を選んだ状態から始められます。',
  '',
  '同期が止まった後にこの端末で加えた変更は失われます。他の端末には影響しません。',
];

/// 世代変更の帯。**旗が立っているときだけ描く。**
class GenerationChangedNotice extends ConsumerWidget {
  const GenerationChangedNotice({super.key, required this.issue});

  /// 詳細に出す1件（`generation-changed`）。
  final AppIssue issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) => KaritaNotice(
    generationChangedNotice,
    issue: issue,
    actions: [
      KaritaNoticeAction(
        '手順',
        () => showGenerationChangedSteps(context, ref),
        key: const ValueKey('generation-steps'),
      ),
    ],
  );
}

/// 手順のダイアログを開く。下部に［合わせる］［閉じる］を並べる。
Future<void> showGenerationChangedSteps(BuildContext context, WidgetRef ref) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('同期が停止しています'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in generationChangedSteps)
                  line.isEmpty ? const SizedBox(height: 8) : Text(line),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('generation-steps-rejoin'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(
                showRestoreDialog(
                  context,
                  ref,
                  initial: const RestoreChoice.rejoin(),
                ),
              );
            },
            child: const Text('合わせる'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
