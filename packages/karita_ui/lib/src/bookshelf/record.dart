/// 本の記録。**一覧とは別の1枚である**（`screens/bookshelf.md` §6）。
///
/// 並びは 戻る／状態 → 書誌 → 状態操作 → 返却履歴 → 手動読書 → 評価 → レビュー。
/// **蔵書は出さない**（2026-09-21）— ここは保存された記録の画面で、外から取ってきた観測を
/// 混ぜると「記録された事実」に見える。
///
/// 保存と除外は成功したら一覧へ戻り、結果は notice で出す。失敗はここに留まり、入力と
/// 本文のメッセージを残す。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_domain/karita_domain.dart';

import '../book_cover.dart';
import '../composition.dart';
import 'shared.dart';
import 'state.dart';

class ShelfRecord extends ConsumerStatefulWidget {
  const ShelfRecord({super.key, required this.book, required this.onBack});
  final ShelfBook book;
  final VoidCallback onBack;
  @override
  ConsumerState<ShelfRecord> createState() => _ShelfRecordState();
}

class _ShelfRecordState extends ConsumerState<ShelfRecord> {
  late final TextEditingController review;
  int? rating;
  late String revision, originalText;
  int? originalRating;
  bool busy = false;
  String message = '';
  bool get dirty => review.text != originalText || rating != originalRating;
  @override
  void initState() {
    super.initState();
    review = TextEditingController();
    _load();
  }

  void _load() {
    review.text = originalText = widget.book.review;
    rating = originalRating = widget.book.rating;
    revision = widget.book.reviewRevision;
  }

  @override
  void didUpdateWidget(covariant ShelfRecord old) {
    super.didUpdateWidget(old);
    if (!dirty && revision != widget.book.reviewRevision) _load();
  }

  @override
  void dispose() {
    review.dispose();
    super.dispose();
  }

  Future<bool> confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('やめる'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('続ける'),
            ),
          ],
        ),
      ) ??
      false;
  Future<bool> discard() async =>
      !dirty || await confirm('保存していないレビューを破棄しますか？');
  Future<void> back() async {
    if (await discard() && mounted) widget.onBack();
  }

  Future<void> change(String state) async {
    if (busy || !await discard() || !mounted) return;
    if (state == 'removed' &&
        (!await confirm('本棚から外しますか？レビューと履歴は保持します。') || !mounted)) {
      return;
    }
    await perform(
      () => ref.read(compositionProvider).setShelfState(widget.book.id, state),
    );
    if (mounted && message == '保存しました。') {
      if (state == 'removed') {
        _leave('本棚から外しました。');
      } else {
        _load();
      }
    }
  }

  /// 保存が終わった操作は本棚へ戻し、結果は [SnackBar] で伝える。
  /// 失敗は詳細に留まり、`message` と入力を残す。
  void _leave(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    widget.onBack();
  }

  Future<void> perform(VoidCallback action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '';
    });
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      action();
      if (mounted) setState(() => message = '保存しました。');
    } on ShelfIssue catch (e) {
      if (mounted) {
        setState(
          () => message = switch (e.code) {
            'review-conflict' =>
              '別の端末でレビューが変更されました。入力を保持しています。最新内容を読み直して確認してください。',
            'review-read-only' => '本棚の状態が変わりました。読んだのときだけ編集できます。入力は保持しています。',
            _ => '保存できませんでした（${e.code}）。入力は保持しています。',
          },
        );
      }
    } catch (_) {
      if (mounted) setState(() => message = '保存できませんでした。入力は保持しています。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    await perform(
      () => ref
          .read(compositionProvider)
          .saveBookReview(
            widget.book.id,
            rating: rating,
            review: review.text,
            expectedRevision: revision,
          ),
    );
    if (mounted && message == '保存しました。') _leave('レビューを保存しました。');
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    final theme = Theme.of(context);
    final editable = b.state == 'read' && !busy;
    final libraries = shelfLibraries(ref);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 7),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(back());
      },
      child: ListView(
        key: PageStorageKey('shelf.record.${b.id}'),
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('shelf.back'),
                tooltip: shelfBackLabel(ref.watch(shelfReturnProvider)),
                onPressed: busy ? null : back,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(child: Text('本の記録', style: theme.textTheme.titleLarge)),
              // **「外した」と「まだ載せていない」を分ける**（2026-09-21）。貸出しの行から
              // 直に開けるようになり、本棚に一度も載せていない本がここへ来る。
              Text(switch (b.state) {
                'wanted' => '読みたい',
                'read' => '読んだ',
                'removed' => '本棚から除外',
                _ => '本棚に未登録',
              }),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCoverView(
                width: 76,
                colorSeed: b.id,
                title: b.title,
                isbn13: b.isbn13,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.title, style: theme.textTheme.titleMedium),
                    Text(b.authors.join('・')),
                    Text(b.isbn13 ?? 'ISBNなし'),
                  ],
                ),
              ),
            ],
          ),
          // 書影・書名の下に横幅いっぱいで置く。ISBN が無ければ何も出さない。
          if (shelfAmazonUrl(b.isbn13) != null) ...[
            const SizedBox(height: 12),
            ShelfAmazonButton(book: b, wide: true),
          ],
          heading('本棚の状態'),
          Wrap(
            spacing: 8,
            children: [
              for (final e in const {
                'wanted': '読みたいにする',
                'read': '読んだにする',
              }.entries)
                OutlinedButton(
                  style: shelfButtonStyle(ref),
                  onPressed: busy || b.state == e.key
                      ? null
                      : () => change(e.key),
                  child: Text('${b.state == e.key ? '✓ ' : ''}${e.value}'),
                ),
            ],
          ),
          heading('返却履歴'),
          if (b.histories.where((h) => !h.manual).isEmpty)
            const Text('返却履歴はありません。'),
          for (final h in b.histories.where((h) => !h.manual))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '${libraries[h.systemId]?.name ?? h.systemId ?? 'システム不明'}・${_branchName(libraries[h.systemId], h.branchId)}\n返却日 ${h.returnedOn ?? '不明'}・返却済み',
              ),
            ),
          if (b.histories.any((h) => h.manual)) ...[
            heading('手動の読書記録'),
            for (final h in b.histories.where((h) => h.manual))
              Text('読んだに登録 ${h.returnedOn ?? '不明'}'),
          ],
          heading('レーティング'),
          Wrap(
            children: [
              for (var n = 1; n <= 5; n++)
                IconButton(
                  tooltip: '$n点',
                  onPressed: editable ? () => setState(() => rating = n) : null,
                  icon: Icon(
                    rating != null && n <= rating!
                        ? Icons.star
                        : Icons.star_border,
                  ),
                ),
              TextButton(
                onPressed: editable
                    ? () => setState(() => rating = null)
                    : null,
                child: const Text('評価を解除'),
              ),
            ],
          ),
          Text(rating == null ? '未評価' : '$rating / 5'),
          heading('レビュー'),
          TextField(
            key: const ValueKey('shelf.review'),
            controller: review,
            readOnly: !editable,
            minLines: 4,
            maxLines: null,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '任意で記録します。本の状態は変更しません。',
              border: OutlineInputBorder(),
            ),
          ),
          if (revision != b.reviewRevision && dirty)
            TextButton(
              onPressed: () async {
                if (await discard() && mounted) setState(_load);
              },
              child: const Text('最新のレビューを読み直す'),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => change('removed'),
                  child: const Text('本棚から外す'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('shelf.save'),
                  onPressed: editable ? save : null,
                  child: const Text('レビューを保存'),
                ),
              ),
            ],
          ),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(message),
            ),
        ],
      ),
    );
  }
}

String _branchName(LibrarySystem? system, String? id) {
  if (id == null) return '受取館不明';
  return system?.branches.where((b) => b.id == id).firstOrNull?.name ?? id;
}
