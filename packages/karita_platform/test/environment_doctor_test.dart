/// Windows の環境検査。**実ファイルに対して測る。**
///
/// 「どこを見るか」も規則の一部である。偽の `AppPaths` に対して測るだけにすると、実際には
/// 触っていない場所を検査したつもりになる。
library;

import 'dart:convert';
import 'dart:io';

import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:test/test.dart';

const String _now = '2026-08-05T09:00:00Z';

/// 差し替えた `AppPaths`。**`KARITA_HOME` の経路を通す** — 引数では受けない規則のままで、
/// 試験だけがその環境変数を立てる。
AppPaths _pathsAt(String home) =>
    WindowsAppPaths.resolve(environment: {homeEnvVar: home});

GoogleAccessTokenProvider _tokens(AppPaths paths) => GoogleAccessTokenProvider(
      store: TokenStore(paths.tokenPath),
      // 通信しないので、口が揃っていれば足りる。診断は `status()` しか呼ばない。
      oauth: GoogleOAuth(const DesktopClient(clientId: 'x', clientSecret: 'y')),
      now: () => _now,
    );

void main() {
  late Directory home;
  late AppPaths paths;

  Future<DoctorReport> check() =>
      WindowsEnvironmentDoctor(paths: paths, tokens: _tokens(paths)).check();


  setUp(() {
    home = Directory.systemTemp.createTempSync('karita-env-doctor-');
    paths = _pathsAt(home.path);
  });
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  test('3つとも走る', () async {
    final report = await check();
    expect(
      report.checked,
      equals({
        DoctorCheck.homeWritable,
        DoctorCheck.credentials,
        DoctorCheck.authorization,
      }),
    );
  });

  test('台帳の検査はここに無い', () async {
    // 台帳から読める分は `karita_sync` の `ledgerDoctor` が見る。
    final report = await check();
    expect(
      report.notChecked,
      containsAll(<DoctorCheck>[
        DoctorCheck.deviceId,
        DoctorCheck.tableOwnership,
        DoctorCheck.versionGap,
      ]),
    );
  });

  test('何も置いていない領域では、資格情報と認可が引っかかる', () async {
    final report = await check();
    final checks = report.findings.map((f) => f.check).toSet();
    expect(checks, contains(DoctorCheck.credentials));
    expect(checks, contains(DoctorCheck.authorization));
    // **書けることは確かめられている。** 領域そのものは作れている。
    expect(checks, isNot(contains(DoctorCheck.homeWritable)));
    expect(report.failed, isTrue);
  });

  test('資格情報を置けば、その分だけ消える', () async {
    _writeCredentials(paths);
    final checks = (await check()).findings.map((f) => f.check).toSet();
    expect(checks, isNot(contains(DoctorCheck.credentials)));
    expect(checks, contains(DoctorCheck.authorization));
  });

  test('資格情報の中身は読まない', () async {
    // client secret を診断のために触る理由が無い。**壊れた JSON でも引っかからない。**
    File(paths.credentialsPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{ this is not json');
    final checks = (await check()).findings.map((f) => f.check).toSet();
    expect(checks, isNot(contains(DoctorCheck.credentials)));
  });

  test('トークンがあれば認可は引っかからない', () async {
    _writeCredentials(paths);
    TokenStore(paths.tokenPath).save(_token(expiry: '2026-08-06T09:00:00Z'));
    expect((await check()).findings, isEmpty);
  });

  test('あるが開けないトークンは、無いこととは別の所見にする', () async {
    // 別ユーザー・別 PC・改変で保護を開けない状態。再サインインで置き換わる。
    _writeCredentials(paths);
    File(paths.tokenPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([0x4B, 0x52, 0x54, 0x4B, 1, 0, 1, 2, 3]);
    final finding = (await check()).findings.single;
    expect(finding.check, DoctorCheck.authorization);
    expect(jsonEncode(finding.toMap()), contains('(unreadable)'));
  });

  test('期限切れは所見にしない', () async {
    // **期限切れは異常ではなく時計である。** access token の寿命は1時間程度で、アイドルを
    // 跨げば必ず切れる。`failed` は重みづけを持たないので、ここへ足すと**1時間放置しただけの
    // 端末が異常を名乗る。** 次の転送で refresh が回復させ、回復できなければ `blocked_auth`
    // が立つ — 区別はそちらの仕事である。
    _writeCredentials(paths);
    TokenStore(paths.tokenPath).save(_token(expiry: '2026-08-04T09:00:00Z'));

    final report = await check();
    expect(report.findings, isEmpty);
    // **検査は走っている。**「異常が無い」と「検査していない」を混ぜない。
    expect(report.checked, contains(DoctorCheck.authorization));
  });

  test('トークンの値は出さない', () async {
    _writeCredentials(paths);
    TokenStore(paths.tokenPath).save(_token(expiry: '2026-08-04T09:00:00Z'));

    final dumped = jsonEncode((await check()).toMap());
    expect(dumped, isNot(contains('at-secret')));
    expect(dumped, isNot(contains('rt-secret')));
  });

  test('データ領域へ書けなければ引っかかる', () async {
    // 領域そのものをファイルにしてしまうと、ディレクトリとして作れない。
    final blocked =
        '${home.path}${Platform.pathSeparator}blocked${Platform.pathSeparator}karita';
    File('${home.path}${Platform.pathSeparator}blocked')
        .writeAsStringSync('not a directory');

    final report =
        await WindowsEnvironmentDoctor(paths: _pathsAt(blocked), tokens: _tokens(_pathsAt(blocked)))
            .check();
    final finding = report.findings
        .firstWhere((f) => f.check == DoctorCheck.homeWritable);
    expect(finding.detail, equals(blocked));
  });
}

void _writeCredentials(AppPaths paths) {
  File(paths.credentialsPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('{"installed": {"client_id": "x", "client_secret": "y"}}');
}

Token _token({required String expiry}) => Token(
      accessToken: 'at-secret',
      refreshToken: 'rt-secret',
      expiryUtc: expiry,
      scopes: const [appDataScope],
    );
