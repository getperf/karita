import 'dart:io';

import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String local;
  late String executable;
  late File bundled;

  setUp(() {
    root = Directory.systemTemp.createTempSync('karita-credentials-');
    local = '${root.path}/home/credentials/karita-core-desktop.json';
    executable = '${root.path}/package/karita.exe';
    bundled = File(
      '${root.path}/package/data/credentials/karita-core-desktop.json',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  String resolve() =>
      resolveDesktopCredentialsPath(local, executablePath: executable);
  void bundle() => bundled
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      '{"installed":{"client_id":"bundled-id","client_secret":"bundled-secret"}}',
    );

  test('新規利用者は読み取り専用の同梱元から読み、データ領域へコピーしない', () {
    bundle();
    expect(loadDesktopClient(resolve()).clientId, 'bundled-id');
    expect(File(local).existsSync(), isFalse);
  });

  test('既存の手動配置を優先する', () {
    bundle();
    File(local)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '{"installed":{"client_id":"local-id","client_secret":"local-secret"}}',
      );
    expect(resolve(), local);
    expect(loadDesktopClient(resolve()).clientId, 'local-id');
  });

  test('壊れた手動配置を同梱版で隠さない', () {
    bundle();
    File(local)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{broken');
    expect(
      () => loadDesktopClient(resolve()),
      throwsA(isA<TransportAuthError>()),
    );
  });

  test('両方なければ従来の不足エラー', () {
    expect(resolve(), local);
    expect(
      () => loadDesktopClient(resolve()),
      throwsA(isA<TransportAuthError>()),
    );
  });

  test('WebクライアントをDesktopとして受け入れない', () {
    bundled
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '{"web":{"client_id":"web-id","client_secret":"web-secret"}}',
      );
    expect(
      () => loadDesktopClient(resolve()),
      throwsA(isA<TransportAuthError>()),
    );
  });
}
