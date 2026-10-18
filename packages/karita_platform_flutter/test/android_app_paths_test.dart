/// Android の既定パス。**`path_provider` を要らない部分だけを測る。**
///
/// `getApplicationSupportDirectory()` そのものは Flutter プラグインで、実機か統合試験でしか
/// 通らない。ここで固定するのは**その周りの判断** — 差し替えが効くこと、Android に無いものを
/// 触ったら落ちること、台帳の名前が Windows と同じであることである。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_contract/errors.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_platform_flutter/karita_platform_flutter.dart';

void main() {
  test('KARITA_HOME があれば丸ごとそちらを使う', () async {
    final paths = await AndroidAppPaths.resolve(
      environment: <String, String>{homeEnvVar: '/data/karita-b'},
    );

    expect(paths.home, '/data/karita-b');
  });

  test('空白だけの KARITA_HOME は無いものとして扱う', () async {
    // 立てたつもりの空文字で既定の解決を飛ばさない。**既定の解決が本番の経路である。**
    // ここで `path_provider` へ落ちるので、プラグインの無い試験では例外になる。
    // 「差し替えが効かなかった」ことだけを確かめれば足りる。
    await expectLater(
      AndroidAppPaths.resolve(
        environment: <String, String>{homeEnvVar: '   '},
      ),
      throwsA(anything),
    );
  });

  test('台帳の名前は Windows と同じ library.db である', () {
    // **端末を跨いで同じ名前にする。** `.blib` の復元先が端末ごとに違うと、切り分けのたびに
    // 場所を確かめ直すことになる。
    expect(AndroidAppPaths.at('/data/karita').dbPath, contains('library.db'));
  });

  test('tokenPath は無い。触ったら落ちる', () {
    // 使われないパスを返すと、いつか誰かがそこを読み、空を「認可が無い」と読み違える。
    expect(
      () => AndroidAppPaths.at('/data/karita').tokenPath,
      throwsA(
        isA<SyncDataError>()
            .having((e) => e.code, 'code', 'paths-not-applicable'),
      ),
    );
  });

  test('credentialsPath は無い。触ったら落ちる', () {
    expect(
      () => AndroidAppPaths.at('/data/karita').credentialsPath,
      throwsA(
        isA<SyncDataError>()
            .having((e) => e.code, 'code', 'paths-not-applicable'),
      ),
    );
  });

  test('AppPaths として渡せる', () {
    final AppPaths paths = AndroidAppPaths.at('/data/karita');
    expect(paths.home, '/data/karita');
  });
}
