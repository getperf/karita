/// 開発・検証専用のハーネス。**本番 GUI ではない。**
///
/// 本番 GUI の正本は `../karita-ui-probe` にある。ここが答えるのは「エンジンの公開 API だけで
/// 操作・観測・状態が成り立つか」であって、「利用者が誤らないか」ではない。
///
/// 2つの規則を守る。
///
/// - **規則1: 文言を書かない。** enum 識別子・生値・件数だけを出す。表示名・アイコン・色・
///   説明文を持たない。`test/no_wording_test.dart` が機械で判定する
/// - **規則2: `karita_*` の公開 API だけを使う。** internal に触らない。これが同時に **API の
///   使い勝手の検査**になり、本番 GUI が同じ口で書けることの保証になる
library;

import 'package:flutter/material.dart';
import 'package:karita_app/karita_app.dart';

import 'src/raw.dart';
import 'src/tabs/observation.dart';
import 'src/tabs/operations.dart';
import 'src/tabs/state.dart';

void main() => runApp(const HarnessApp());

class HarnessApp extends StatelessWidget {
  const HarnessApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'karita harness',
        theme: ThemeData(useMaterial3: true),
        home: const _Boot(),
      );
}

/// 組み立ては非同期である（Android の既定パスが `Future` を返す）。**失敗を隠さない。**
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  /// **合成を作らない。** `karita_app` の [boot] を呼ぶだけである（P5a）。パスの解決・
  /// `device.json`・ログ sink・周期リフレッシュの配線は全部あちらが順番どおりに立てる。
  ///
  /// **ここで合成を書くと、本番で通っていない経路を harness が緑にする。** 非同期なのは
  /// Android の既定パスが `Future` を返すためで、起動時に他のことはしない。
  ///
  /// **背面同期は持たない**（2026-09-13）。`initializeBackground()` はここにあったが、
  /// `workmanager` ごと落ちた（P5a）。戻す先は合成層の背面の口である。
  late final Future<Composition> _composition = boot();

  @override
  Widget build(BuildContext context) => FutureBuilder<Composition>(
        future: _composition,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // **組み立ての失敗も生値で出す。** 資格情報が無い、`LOCALAPPDATA` が無い、
            // ネイティブ SQLite が無い — どれも起動時に分かる形にする。
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  '${snapshot.error}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            );
          }
          final composition = snapshot.data;
          if (composition == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return _Tabs(composition);
        },
      );
}

class _Tabs extends StatelessWidget {
  final Composition composition;

  const _Tabs(this.composition);

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            // **題は device_id である。** 3台を並べて回すとき、どの端末の画面かが分かる
            // 必要がある。製品名を書くところではない。
            title: RawRow('deviceId', composition.deviceId),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'operations'),
                Tab(text: 'observation'),
                Tab(text: 'state'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              OperationsTab(composition),
              ObservationTab(composition),
              StateTab(composition),
            ],
          ),
        ),
      );
}
