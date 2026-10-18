/// 図書館管理の画面がまたいで使う枠。**どの画面の持ち物でもないものだけを置く。**
///
/// 画面ごとに別のライブラリへ割ったので、`_` の付いた名前は共有できない。**公開するのは
/// ここの2つだけ**で、`karita_ui.dart` からは export しない — package の外から触れる必要は
/// 無い（`lending/shared.dart`・`bookshelf/shared.dart` と同じ扱いである）。
library;

import 'package:flutter/material.dart';

/// 見出し・説明・本文の枠。**設定画面の行と同じ寸法である**（余白14・角丸14は初期値）。
class LibraryCard extends StatelessWidget {
  const LibraryCard({required this.title, this.description, this.body});

  final String title;

  /// 説明。**無い方が読めるなら置かない**（2026-09-18）。
  final String? description;
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (body != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: body!),
        ],
      ),
    );
  }
}

class LibraryParagraph extends StatelessWidget {
  const LibraryParagraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
