/// `home` の下の配置。**実装ごとに写しが増えていないことを測る。**
///
/// 端末を足すときに決めるのは `home` の1行だけである、という規則そのものを固定する
/// （`非公開資料:settings-and-parameters.md`）。
library;

import 'dart:io';

import 'package:karita_contract/errors.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:test/test.dart';

String _sep(String path) => path.replaceAll(Platform.pathSeparator, '/');

void main() {
  group('WindowsAppPaths.resolve', () {
    test('KARITA_HOME があれば丸ごと使う', () {
      final paths =
          WindowsAppPaths.resolve(environment: {homeEnvVar: r'D:\karita'});
      expect(paths.home, r'D:\karita');
    });

    test('無ければ %LOCALAPPDATA%\\Karita へ落ちる', () {
      final paths =
          WindowsAppPaths.resolve(environment: {'LOCALAPPDATA': r'C:\lad'});
      expect(_sep(paths.home), 'C:/lad/Karita');
    });

    test('LOCALAPPDATA が無ければ推測せずに落ちる', () {
      expect(
        () => WindowsAppPaths.resolve(environment: const {}),
        throwsA(isA<SyncDataError>()
            .having((e) => e.code, 'code', 'paths-unresolved')),
      );
    });
  });

  group('配置は AppLayout が1箇所で持つ', () {
    final paths = WindowsAppPaths.at(r'C:\home');

    test('すべてが home から決まる', () {
      expect(_sep(paths.dbPath), 'C:/home/library.db');
      expect(_sep(paths.tokenPath), 'C:/home/token.json');
      expect(_sep(paths.configDir), 'C:/home/config');
      expect(_sep(paths.logDir), 'C:/home/logs');
      expect(_sep(paths.credentialsPath),
          'C:/home/credentials/karita-core-desktop.json');
    });

    test('設定とログのファイル名は AppLayout から引く', () {
      expect(_sep(AppLayout.under(paths.configDir, AppLayout.deviceConfig)),
          'C:/home/config/device.json');
      expect(_sep(AppLayout.under(paths.logDir, AppLayout.logFile)),
          'C:/home/logs/karita.log');
    });

    test('KARITA_HOME を差し替えると全部が移る', () {
      final moved =
          WindowsAppPaths.resolve(environment: {homeEnvVar: r'E:\elsewhere'});
      for (final path in [
        moved.dbPath,
        moved.tokenPath,
        moved.configDir,
        moved.logDir,
        moved.credentialsPath,
      ]) {
        expect(_sep(path), startsWith('E:/elsewhere/'));
      }
    });
  });

  group('ensure', () {
    late Directory home;

    setUp(() => home = Directory.systemTemp.createTempSync('karita-paths-'));
    tearDown(() {
      if (home.existsSync()) home.deleteSync(recursive: true);
    });

    test('home と config と logs を作る', () {
      final paths = WindowsAppPaths.resolve(
          environment: {homeEnvVar: AppLayout.under(home.path, 'nested')});
      paths.ensure();
      expect(Directory(paths.home).existsSync(), isTrue);
      expect(Directory(paths.configDir).existsSync(), isTrue);
      expect(Directory(paths.logDir).existsSync(), isTrue);
    });

    test('credentials は作らない', () {
      // 中身を手で置くものなので、空の場所があると「置いたつもり」と見分けられなくなる。
      final paths =
          WindowsAppPaths.resolve(environment: {homeEnvVar: home.path});
      paths.ensure();
      expect(
        Directory(AppLayout.under(home.path, AppLayout.credentialsDirName))
            .existsSync(),
        isFalse,
      );
    });
  });
}
