/// いま何が効いているかを右上へ出す帯。**debug ビルドだけである。**
///
/// harness の `shell_probe.dart` が持っていたものを、器ができた時点でここへ移した
/// （本番アプリの合成（非公開資料）
/// 「`shell_probe.dart` の期限」）。**捨てられない** — 実機で「440dp を跨いだか」を確かめる
/// 手段が他に無く、窓を引っぱっている本人には形の変化としてしか見えない。
///
/// **出すのは enum 識別子と生値だけである。** 文言は `karita_ui` の持ち物で、ここは器である。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_ui/karita_ui.dart';

/// [child] の上に読み取り帯を重ねる。**release では [child] をそのまま返す。**
///
/// `MaterialApp.builder` から呼ぶ。外殻の内側ではなく Navigator の overlay まで含めて
/// 覆うので、ダイアログを開いている間も数字が見える。
Widget withDebugReadout(Widget? child) {
  final body = child ?? const SizedBox.shrink();
  if (!kDebugMode) return body;
  return Stack(
    children: [body, const Positioned(top: 0, right: 0, child: _Readout())],
  );
}

class _Readout extends ConsumerWidget {
  const _Readout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final rail = width >= shellRailBreakpoint;
    final density = ref.watch(densityProvider);
    final tab = ref.watch(currentTabProvider);
    final ready = ref.watch(bootReadyProvider);
    return IgnorePointer(
      child: Container(
        color: const Color(0xCC000000),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'w=${width.round()} bp=${shellRailBreakpoint.round()} '
          '${rail ? 'rail' : 'bar'} '
          '${density.pointer.name} control=${density.control.round()} '
          'gate=$ready tab=${tab.name}',
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
