/// Android の環境検査。**Play services 無しで測る。**
///
/// 実機で確かめるのは Play services のふるまいであって、こちらの判断ではない。判断
/// （何を検査し、何を検査しないか）は偽の口に対して固定できる。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_platform_flutter/karita_platform_flutter.dart';
import 'package:karita_sync/karita_sync.dart';

/// 認可の有無だけを台本にする偽の Play services。
class _FakeClient implements AndroidAuthorizationClient {
  final String? silent;
  final Object? failure;

  const _FakeClient({this.silent, this.failure});

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> tokenForScopes(List<String> scopes) async {
    final error = failure;
    if (error != null) throw error;
    return silent;
  }

  @override
  Future<String> requestScopes(List<String> scopes) async =>
      fail('画面を出す requestScopes が自己診断から呼ばれた');

  @override
  Future<void> clearToken(String accessToken) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  late Directory home;

  Future<DoctorReport> check(_FakeClient client, {String? at}) =>
      AndroidEnvironmentDoctor(
        paths: AndroidAppPaths.at(at ?? home.path),
        tokens: AndroidAccessTokenProvider(client),
      ).check();

  setUp(() {
    home = Directory.systemTemp.createTempSync('karita-android-doctor-');
  });
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  test('資格情報は検査しない', () async {
    // **Android の OAuth クライアントにシークレットは無い。** 検査する対象そのものが無く、
    // `credentialsPath` は触ると落ちる。
    final report = await check(const _FakeClient(silent: 'at-1'));
    expect(report.checked, isNot(contains(DoctorCheck.credentials)));
    expect(report.notChecked, contains(DoctorCheck.credentials));
  });

  test('走るのはデータ領域と認可の2つだけ', () async {
    final report = await check(const _FakeClient(silent: 'at-1'));
    expect(
      report.checked,
      equals({DoctorCheck.homeWritable, DoctorCheck.authorization}),
    );
  });

  test('台帳の検査はここに無い', () async {
    final report = await check(const _FakeClient(silent: 'at-1'));
    expect(
      report.notChecked,
      containsAll(<DoctorCheck>[
        DoctorCheck.deviceId,
        DoctorCheck.tableOwnership,
        DoctorCheck.versionGap,
      ]),
    );
  });

  test('無音で取れるなら何も引っかからない', () async {
    expect((await check(const _FakeClient(silent: 'at-1'))).findings, isEmpty);
  });

  test('grant が無ければ authorization が引っかかる', () async {
    // **`blocked_auth` とは別である。** 送るものが1件も無い端末ではあちらが立たない。
    final report = await check(const _FakeClient());
    final finding = report.findings
        .firstWhere((f) => f.check == DoctorCheck.authorization);
    expect(finding.detail, equals('(none)'));
    expect(report.failed, isTrue);
  });

  test('Play services が応じないことも所見である', () async {
    // **握り潰さない。** ただし例外文には端末の識別子が混ざりうるので、種別だけを出す。
    final report = await check(
      _FakeClient(failure: StateError('play services said no: user 1234')),
    );
    final finding = report.findings
        .firstWhere((f) => f.check == DoctorCheck.authorization);
    expect(finding.detail, equals('StateError'));
    expect(finding.detail, isNot(contains('1234')));
  });

  test('データ領域へ書けなければ引っかかる', () async {
    final blocked =
        '${home.path}${Platform.pathSeparator}blocked${Platform.pathSeparator}karita';
    File('${home.path}${Platform.pathSeparator}blocked')
        .writeAsStringSync('not a directory');

    final report = await check(const _FakeClient(silent: 'at-1'), at: blocked);
    final finding =
        report.findings.firstWhere((f) => f.check == DoctorCheck.homeWritable);
    expect(finding.detail, equals(blocked));
  });
}
