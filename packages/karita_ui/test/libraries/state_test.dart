/// 基本ステートの1本目。**台帳を読んで一覧と詳細が引けるところまでを widget で測る。**
///
/// 足場は `karita_app` のデモ（`DemoMode.memory`）である。5区10分館の fixture が既にあるので、
/// DB の用意を書かずに済む。**runner（`apps/karita`）はまだ無い** — 無くてもここまでは固定
/// できる（`非公開資料:ui-state-model.md` §4 段階1 の着手順）。
///
/// **合成は `setUp` で立てる。** `testWidgets` の本体は fake async の中を走るので、そこで
/// `compose()` を待つと asset の読み出しが返らずに固まる。`setUp` は素の非同期である。
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition composition;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-ui-');
    composition = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
  });
  tearDown(() {
    composition.close();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  /// 立てたデモを画面へ差し込む。**合成はここで作らない — `karita_app` が作る。**
  Future<ProviderContainer> pumpProbe(
    WidgetTester tester, {
    String systemId = _koto,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [compositionProvider.overrideWithValue(composition)],
        child: _Probe(systemId),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byType(_Probe)));
  }

  testWidgets('一覧が引ける（5区）', (tester) async {
    await pumpProbe(tester);
    expect(find.textContaining('systems=5'), findsOneWidget);
    // 名前はカーリルの `systemname` をそのまま採る（2026-09-16 の決定）。
    expect(find.text('東京都江東区'), findsOneWidget);
    expect(find.text('東京都墨田区'), findsOneWidget);
  });

  testWidgets('詳細が引ける（ID 指定。分館 2 件）', (tester) async {
    await pumpProbe(tester);
    expect(find.text('$_koto 東京都江東区 branches=2'), findsOneWidget);
  });

  testWidgets('全区で分館は 10 件', (tester) async {
    await pumpProbe(tester);
    expect(find.textContaining('branchTotal=10'), findsOneWidget);
  });

  testWidgets('未登録の systemId は null であり、失敗ではない', (tester) async {
    await pumpProbe(tester, systemId: 'Tokyo_NotRegistered');
    // 一覧は引けたまま、詳細だけが空である。
    expect(find.textContaining('systems=5'), findsOneWidget);
    expect(find.text('Tokyo_NotRegistered none'), findsOneWidget);
  });

  testWidgets('詳細はコレクションの同じ1件である', (tester) async {
    final container = await pumpProbe(tester);
    expect(
      identical(
        container.read(librariesProvider)[_koto],
        container.read(libraryProvider(_koto)),
      ),
      isTrue,
    );
    // 台帳が返したものと同じ並びである（合成層越しに読んでいること）。
    expect(
      container.read(librariesProvider).keys,
      composition.librarySystems.load().librarySystems.map((s) => s.id),
    );
  });

  testWidgets('コレクションは不変である', (tester) async {
    final container = await pumpProbe(tester);
    expect(
      () => container.read(librariesProvider).remove(_koto),
      throwsUnsupportedError,
    );
  });

  testWidgets('登録後の合成層通知で一覧と詳細が揃う', (tester) async {
    await pumpProbe(tester, systemId: _chiyoda);
    expect(find.text('$_chiyoda none'), findsOneWidget);

    composition.librarySystems.register(
      system: const LibrarySystem(
        id: _chiyoda,
        pref: '東京都',
        city: '千代田区',
        name: '東京都千代田区',
        branches: [
          Branch(id: 'calil:1', calilLibkey: '四番町図書館', name: '千代田区立四番町図書館'),
        ],
      ),
      now: nowUtc(),
    );

    await composition.syncAfterDomainWrite();
    await tester.pump();

    // **一覧と詳細が同時に揃う。** 詳細はコレクションから取り出すだけなので、別々に読み直す
    // 経路が無い。
    expect(find.textContaining('systems=6'), findsOneWidget);
    expect(find.text('$_chiyoda 東京都千代田区 branches=1'), findsOneWidget);
  });
}

const String _koto = 'Tokyo_Koto';
const String _chiyoda = 'Tokyo_Chiyoda';

/// 一覧と詳細を1枚に出すだけの足場。**`karita_ui` の画面はまだ無い**（外殻は次の段）。
class _Probe extends ConsumerWidget {
  const _Probe(this.systemId);

  final String systemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraries = ref.watch(librariesProvider);
    final detail = ref.watch(libraryProvider(systemId));
    final branchTotal = libraries.values.fold<int>(
      0,
      (sum, system) => sum + system.branches.length,
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          Text('systems=${libraries.length} branchTotal=$branchTotal'),
          for (final system in libraries.values) Text(system.name),
          Text(
            detail == null
                ? '$systemId none'
                : '$systemId ${detail.name} branches=${detail.branches.length}',
          ),
        ],
      ),
    );
  }
}
