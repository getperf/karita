import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import '../composition.dart';

class BookshelfExportButton extends ConsumerStatefulWidget {
  const BookshelfExportButton({super.key});
  @override
  ConsumerState<BookshelfExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<BookshelfExportButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('shelf.export'),
    onPressed: busy ? null : _open,
    icon: const Icon(Icons.file_download_outlined),
    label: const Text('エクスポート'),
  );

  Future<void> _open() async {
    setState(() => busy = true);
    try {
      final app = ref.read(compositionProvider);
      final snapshot = app.prepareBookshelfExport();
      final result = await showDialog<BookshelfExportResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ExportDialog(app: app, snapshot: snapshot),
      );
      if (!mounted || result == null) return;
      final message = switch (result) {
        BookshelfExportResult.saved => '本棚を保存しました。',
        BookshelfExportResult.shared => '共有先にファイルを渡しました。',
        BookshelfExportResult.opened => '共有画面を開きました。',
        BookshelfExportResult.dismissed => 'エクスポートを取り消しました。',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('エクスポートの準備に失敗しました。もう一度お試しください。')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _ExportDialog extends StatefulWidget {
  final Composition app;
  final BookshelfExportSnapshot snapshot;
  const _ExportDialog({required this.app, required this.snapshot});
  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  BookshelfExportFormat format = BookshelfExportFormat.csv;
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final save = widget.app.bookshelfExportAction == BookshelfExportAction.save;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('本棚をエクスポート'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('読みたい・読んだの全${widget.snapshot.books.length}冊（レビューを含む）'),
              const Text('検索・絞り込みに関係なく全件を出力します。'),
              const SizedBox(height: 16),
              SegmentedButton<BookshelfExportFormat>(
                segments: const [
                  ButtonSegment(
                    value: BookshelfExportFormat.csv,
                    label: Text('CSV'),
                  ),
                  ButtonSegment(
                    value: BookshelfExportFormat.json,
                    label: Text('JSON'),
                  ),
                ],
                selected: {format},
                onSelectionChanged: busy
                    ? null
                    : (values) => setState(() => format = values.single),
              ),
              const SizedBox(height: 12),
              Text(
                format == BookshelfExportFormat.csv
                    ? '表計算向け。ISBN列は文字列として取り込んでください。'
                    : 'データの加工・再利用向け。',
              ),
              const Text('登録日時は図書を初めて登録した時刻（UTC）です。確認できない場合は空欄になります。'),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error!),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
          FilledButton(
            key: const ValueKey('shelf.export.confirm'),
            onPressed: busy || widget.snapshot.books.isEmpty ? null : _deliver,
            child: Text(save ? '保存先を選ぶ' : '共有する'),
          ),
        ],
      ),
    );
  }

  Future<void> _deliver() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.app.exportBookshelf(widget.snapshot, format);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = appIssueOf(e).message;
        });
      }
    }
  }
}
