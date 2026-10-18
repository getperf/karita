/// 本番アプリの runner。**器である** — 合成は作らず、画面も持たない。
///
/// 持つのは3つだけである。
///
/// - `karita_app` の [boot] を1回呼ぶこと
/// - `ProviderScope` へ渡して `KaritaShell` を出すこと
/// - Windows のマウス戻るを Navigator へ渡すこと
///
/// **合成をここに書かない。** パスの解決・`device.json`・ログ sink・周期リフレッシュの配線は
/// 全部 `karita_app` が順番どおりに立てる。ここで組み立てると、harness が通っている経路と
/// 本番の経路が割れる（本番アプリの合成（非公開資料））。
///
/// **`shell_probe.dart` の後継である。** harness の3つ目の entrypoint は、この器ができた
/// 時点で消えた。読み取り帯は `src/readout.dart` の debug ビルド限定へ移してある。
///
/// ```powershell
/// tools/run-dev.ps1                       # 本番モード。Windows
/// tools/run-dev.ps1 -Device <android-id>  # Android の実機
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_ui/karita_ui.dart';

import 'src/readout.dart';

void main() => runApp(const KaritaApp());

class KaritaApp extends StatefulWidget {
  const KaritaApp({super.key});

  @override
  State<KaritaApp> createState() => _KaritaAppState();
}

class _KaritaAppState extends State<KaritaApp> {
  /// 組み立ては非同期である（Android の既定パスが `Future` を返す）。**1回だけ呼ぶ。**
  late final Future<Composition> _composition = boot();

  /// Windows のマウス戻るを、Android のシステム戻ると同じ Navigator へ渡す。
  ///
  /// 画面の入れ替えは Navigator に積まず各 feature の [PopScope] で受ける場合もある。
  /// `maybePop` なら、ダイアログを先に閉じたうえでその既存経路を通る。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => FutureBuilder<Composition>(
    future: _composition,
    builder: (context, snapshot) {
      final error = snapshot.error;
      if (error != null) return _raw('$error');
      final composition = snapshot.data;
      if (composition == null) {
        return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      return ProviderScope(
        overrides: [compositionProvider.overrideWithValue(composition)],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            title: 'karita',
            navigatorKey: _navigatorKey,
            theme: karitaTheme(Brightness.light),
            darkTheme: karitaTheme(Brightness.dark),
            themeMode: ref.watch(themeModeProvider),
            // Navigator の overlay まで含めて受ける。外殻の内側に置くと、ダイアログを
            // 開いている間は戻るボタンが届かない。
            builder: (context, child) => Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                if (defaultTargetPlatform != TargetPlatform.windows) return;
                if ((event.buttons & kBackMouseButton) == 0) return;
                _navigatorKey.currentState?.maybePop();
              },
              child: withDebugReadout(child),
            ),
            home: const KaritaShell(),
          ),
        ),
      );
    },
  );

  /// 組み立ての失敗を生値で出す。
  ///
  /// **利用者向けの文言はまだ無い。未決である** — 資格情報が無い・`LOCALAPPDATA` が無い・
  /// ネイティブ SQLite が無いはどれも起動時に分かるが、仕様（`../karita-ui-probe`）に
  /// 起動失敗の画面が無い。**隠さずに出すほうを選ぶ。**
  Widget _raw(String text) => MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    ),
  );
}
