/// ブラウザープラグインのインストール画面。**初回セットアップの段と、後から確かめ直す画面を
/// 兼ねる。**
///
/// 段は2つだけである — ガイドで拡張を入れてツールバーに出す、確認用ページを拡張で送る。
/// 入れ方の細部は書かない（ガイドの持ち物。`state.dart` の宣言）。
///
/// **完了は「届いたこと」で決まる。** 押しただけ・ページを開いただけでは進めない。届けば
/// 合成層が端末設定へ記録し、この画面は「つながりました」に替わる。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_handoff/karita_handoff.dart';

import '../composition.dart';
import '../libraries/state.dart';
import 'state.dart';

/// 本文の最大幅。**初回起動の画面と同じ数字である**（`first_run/view.dart`）。
const double _contentMaxWidth = 640;

/// 後から確かめ直す画面を開く。**予約画面と設定の入口が使う。**
Future<void> openBrowserLinkScreen(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BrowserLinkScreen(standalone: true),
      ),
    );

class BrowserLinkScreen extends ConsumerStatefulWidget {
  const BrowserLinkScreen({super.key, this.standalone = false});

  /// 後から開いたか。`false` は初回セットアップの段で、終わり方が［次へ］と
  /// ［プラグインなしで進む］になる。
  final bool standalone;

  @override
  ConsumerState<BrowserLinkScreen> createState() => _BrowserLinkScreenState();
}

class _BrowserLinkScreenState extends ConsumerState<BrowserLinkScreen> {
  /// 開いた時点の確認日時。**これと違う値になったら、この画面で届いたと読む。**
  ///
  /// 確かめ直すときは既に `linkedAt` が入っているので、「確認済みか」では届いたかが分からない。
  ///
  /// **`initState` で読む。** 遅延初期化にすると、最初の描画で短絡評価に飛ばされ、届いた後に
  /// 初めて読まれて「開いた時点」が「届いた後」になる。
  String? _openedWith;

  @override
  void initState() {
    super.initState();
    _openedWith = ref.read(browserLinkProvider).linkedAt;
  }

  String? _openFailure;

  Future<void> _open(Uri url) async {
    setState(() => _openFailure = null);
    try {
      await ref.read(compositionProvider).openSite(url);
    } catch (_) {
      if (mounted) {
        setState(() => _openFailure = 'ブラウザーを開けませんでした。次のアドレスを開いてください: $url');
      }
    }
  }

  void _finish() => ref.read(browserLinkEnsureProvider.notifier).finish();

  void _skip() {
    ref.read(browserLinkProvider.notifier).skip();
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ref.watch(browserLinkProvider);
    final arrived = status.linked && status.linkedAt != _openedWith;
    // 図書館が読めなければ、未登録として「次へ」を出す（登録を促す段が同じ判断をする）。
    bool hasLibraries;
    try {
      hasLibraries = ref.watch(librariesProvider).isNotEmpty;
    } catch (_) {
      hasLibraries = false;
    }

    final body = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!widget.standalone) ...[
          Text('karita をはじめる', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
        ],
        Text('ブラウザープラグインのインストール', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'カーリルや図書館のサイトから本を送るために、ブラウザーにプラグイン「karita に送る」を'
          '入れます。Edge・Chrome・Firefox で使えます。',
        ),
        if (widget.standalone && status.linked && !arrived)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'この端末は確認済みです。ブラウザーを替えたときは、もう一度送って確かめてください。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        _Step(
          number: 1,
          title: 'プラグインを入れて、ツールバーに出す',
          body: '入れ方・ツールバーへのピン留め・初めて送るときの許可は、ガイドにまとめています。',
          action: OutlinedButton.icon(
            key: const ValueKey('browser-link-guide'),
            onPressed: () => _open(extensionGuideUrl),
            icon: const Icon(Icons.open_in_new),
            label: const Text('入れ方を開く'),
          ),
        ),
        _Step(
          number: 2,
          title: '送ってみる',
          body:
              '確認用ページを開き、ツールバーの karita ボタンを押してください。そのまま'
              '送られます。「karita を開きますか」と出たら［開く］を押します。',
          action: FilledButton.icon(
            key: const ValueKey('browser-link-check'),
            onPressed: () => _open(linkCheckUrl),
            icon: const Icon(Icons.open_in_new),
            label: const Text('確認用ページを開く'),
          ),
        ),
        if (_openFailure != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(
              _openFailure!,
              style: TextStyle(color: scheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Container(
            key: ValueKey(
              arrived ? 'browser-link-arrived' : 'browser-link-waiting',
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: arrived
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (arrived)
                  Icon(Icons.check_circle, color: scheme.primary)
                else
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    arrived
                        ? 'つながりました。プラグインから karita へ届きました。'
                        : '確認用ページから届くのを待っています。'
                              '届かないときは、ガイドの「うまくいかないとき」を見てください。',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final actions = widget.standalone
        ? [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ]
        : arrived
        ? [
            FilledButton(
              key: const ValueKey('browser-link-start'),
              onPressed: _finish,
              // **次は図書館の登録である。** 既に図書館がある端末（合流）なら、ここで始まる。
              child: Text(hasLibraries ? 'karita を始める' : '次へ'),
            ),
          ]
        : [
            TextButton(
              key: const ValueKey('browser-link-skip'),
              onPressed: _skip,
              child: const Text('プラグインなしで進む（あとで設定）'),
            ),
          ];

    final footer = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // **逃げ道で何を失うかを1行で言う。** 失うのは送る手段だけで、記録はできる。
            if (!widget.standalone && !arrived)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'プラグインが無くても、URL の貼り付けや手入力で記録できます。'
                  '予約画面と設定から、いつでもインストールできます。',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.end,
                ),
              ),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        footer,
      ],
    );

    return Scaffold(
      appBar: widget.standalone
          ? AppBar(title: const Text('ブラウザープラグイン'))
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// 段の1枚。
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.action,
  });

  final int number;
  final String title;
  final String body;
  final Widget action;

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
          Text('$number. $title', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Align(alignment: AlignmentDirectional.centerStart, child: action),
        ],
      ),
    );
  }
}
