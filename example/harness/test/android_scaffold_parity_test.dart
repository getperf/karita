/// Android の足場が2セットあることの代償を、人手の注意ではなく機械で塞ぐ。
///
/// `apps/karita/android/` と `example/harness/android/` は別々に存在する。**2セットあること
/// 自体は避けられない。ずれることは避けられる**（`非公開資料:production-app-composition.md`
/// 「代償は Android の足場が2セットになること」）。2026-09-14 の上げ替えで Gradle / AGP / KGP の
/// 三点が下限割れしていたのは harness の `android/` であり、**上げ替えの手順が一番厚くなるのは
/// ここである。**
///
/// **行の完全一致では見ない。** `namespace` と `applicationId` は**必ず違う**（本番が
/// `net.getperf.karita`、harness が `net.getperf.karita.dev`）。見るのは版と opt-out の値だけで
/// ある。
///
/// 片方だけ上げると赤になる。**赤を消す直し方は「両方を同じ版にする」であって、この試験を
/// 緩めることではない。**
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// この試験の作業ディレクトリは `example/harness` である。
const String _harness = 'android';
const String _production = '../../apps/karita/android';

/// 揃える値。**キーは「どのファイルの何を見るか」で、値は抜き出す正規表現である。**
final Map<String, RegExp> _pinned = {
  'gradle/wrapper/gradle-wrapper.properties: distributionUrl': RegExp(
    r'^distributionUrl=(.+)$',
    multiLine: true,
  ),
  'settings.gradle.kts: flutter-plugin-loader': RegExp(
    r'id\("dev\.flutter\.flutter-plugin-loader"\) version "([^"]+)"',
  ),
  'settings.gradle.kts: AGP': RegExp(
    r'id\("com\.android\.application"\) version "([^"]+)"',
  ),
  'settings.gradle.kts: KGP': RegExp(
    r'id\("org\.jetbrains\.kotlin\.android"\) version "([^"]+)"',
  ),
  'gradle.properties: android.useAndroidX': RegExp(
    r'^android\.useAndroidX=(.+)$',
    multiLine: true,
  ),
  'gradle.properties: android.newDsl': RegExp(
    r'^android\.newDsl=(.+)$',
    multiLine: true,
  ),
  'gradle.properties: android.builtInKotlin': RegExp(
    r'^android\.builtInKotlin=(.+)$',
    multiLine: true,
  ),
  'app/build.gradle.kts: sourceCompatibility': RegExp(
    r'sourceCompatibility = (JavaVersion\.\w+)',
  ),
  'app/build.gradle.kts: targetCompatibility': RegExp(
    r'targetCompatibility = (JavaVersion\.\w+)',
  ),
  'app/build.gradle.kts: jvmTarget': RegExp(r'jvmTarget = ([\w.]+)'),
};

/// **キーの前半がファイル名である。** 表を1つに保つために、そこから読む先を決める。
String _read(String scaffold, String key) {
  final file = File('$scaffold/${key.split(':').first}');
  if (!file.existsSync()) throw StateError('足場のファイルが無い: ${file.path}');
  return file.readAsStringSync();
}

String? _extract(String scaffold, String key) =>
    _pinned[key]!.firstMatch(_read(scaffold, key))?.group(1)?.trim();

void main() {
  test('本番と harness の Android 足場は、版と opt-out が同値である', () {
    final mismatched = <String>[];
    for (final key in _pinned.keys) {
      final production = _extract(_production, key);
      final harness = _extract(_harness, key);
      expect(production, isNotNull, reason: '本番から読めない: $key');
      expect(harness, isNotNull, reason: 'harness から読めない: $key');
      if (production != harness) {
        mismatched.add('$key\n    apps/karita: $production\n    harness:     $harness');
      }
    }
    expect(
      mismatched,
      isEmpty,
      reason:
          '片方だけ上げた足場がある。両方を同じ版にすること\n${mismatched.join('\n')}',
    );
  });

  test('applicationId と namespace は分かれている', () {
    final id = RegExp(r'applicationId = "([^"]+)"');
    final namespace = RegExp(r'namespace = "([^"]+)"');
    final production = _read(_production, 'app/build.gradle.kts');
    final harness = _read(_harness, 'app/build.gradle.kts');

    expect(id.firstMatch(production)?.group(1), 'net.getperf.karita');
    expect(id.firstMatch(harness)?.group(1), 'net.getperf.karita.dev');
    expect(namespace.firstMatch(production)?.group(1), 'net.getperf.karita');
    expect(namespace.firstMatch(harness)?.group(1), 'net.getperf.karita.dev');
  });
}
