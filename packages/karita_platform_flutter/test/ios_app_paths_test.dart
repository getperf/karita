/// iOS の既定パス。**`path_provider` を要らない部分だけを測る。**
///
/// 測るものは `android_app_paths_test.dart` と同じ — 差し替えが効くこと、iOS に無いものを
/// 触ったら落ちること、台帳の名前が他の端末と同じであることである。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_contract/errors.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_platform_flutter/karita_platform_flutter.dart';

void main() {
  test('KARITA_HOME があれば丸ごとそちらを使う', () async {
    final paths = await IosAppPaths.resolve(
      environment: <String, String>{homeEnvVar: '/var/karita-b'},
    );

    expect(paths.home, '/var/karita-b');
  });

  test('台帳の名前は他の端末と同じ library.db である', () {
    expect(IosAppPaths.at('/var/karita').dbPath, contains('library.db'));
  });

  test('tokenPath は無い。触ったら落ちる', () {
    expect(
      () => IosAppPaths.at('/var/karita').tokenPath,
      throwsA(
        isA<SyncDataError>()
            .having((e) => e.code, 'code', 'paths-not-applicable'),
      ),
    );
  });

  test('credentialsPath は無い。触ったら落ちる', () {
    expect(
      () => IosAppPaths.at('/var/karita').credentialsPath,
      throwsA(
        isA<SyncDataError>()
            .having((e) => e.code, 'code', 'paths-not-applicable'),
      ),
    );
  });
}
