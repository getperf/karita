/// Android の環境検査。
///
/// **Windows より見るものが少ない。** 資格情報のファイルも保存トークンも Android には無く、
/// grant を保持するのは Play services である。**無いものを検査しない** — 走らせなかった検査は
/// [DoctorReport.checked] に入れずに返し、「異常が無い」と「検査していない」を混ぜない。
///
/// **通信しない。** `authorizationForScopes` は Play services の手元を見るだけで、
/// 認可の画面も出さない。自己診断が回線や利用者の操作を要求すると、オフラインの端末や
/// 放置された端末が「異常」を名乗る。
library;

import 'dart:io';

import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';

import 'android_access_token.dart';

class AndroidEnvironmentDoctor implements EnvironmentDoctor {
  final AppPaths paths;

  /// 無音で取れる grant があるかを見る側。**画面を出さない。**
  final AndroidAccessTokenProvider tokens;

  const AndroidEnvironmentDoctor({required this.paths, required this.tokens});

  @override
  Future<DoctorReport> check() async {
    final findings = <DoctorFinding>[];

    // --- データ領域へ書けるか -----------------------------------------------
    //
    // **実際に書いて消す。** アプリのデータ領域は普通は書けるが、ストレージが尽きていれば
    // 書けない。台帳が書けないことは、業務操作を受けてから分かるのでは遅い。
    final home = paths.home;
    try {
      Directory(home).createSync(recursive: true);
      final probe = File('$home${Platform.pathSeparator}.doctor-probe');
      probe.writeAsStringSync('', flush: true);
      probe.deleteSync();
    } on FileSystemException {
      findings.add(DoctorFinding(DoctorCheck.homeWritable, 1, home));
    }

    // --- 資格情報は検査しない -----------------------------------------------
    //
    // **Android の OAuth クライアントにシークレットは無い。** Play services がパッケージ名と
    // 署名証明書から解決するので、端末にクライアント ID もシークレットも置かない。
    // `paths.credentialsPath` は触ると落ちる — 検査する対象そのものが無い。

    // --- 認可 ---------------------------------------------------------------
    //
    // **`blocked_auth` とは別のことを見ている。** あちらは「認可を失って止まった outbox が
    // ある」で、こちらは「そもそも grant が無い」である。送るものが1件も無い端末では前者が
    // 立たないので、新しい端末の「まだサインインしていない」はここでしか出ない。
    //
    // 期限の検査は無い。**Android は期限のあるトークンを持たない** — 要るたびに Play services
    // から取り直す。
    try {
      if (!await tokens.authorized()) {
        findings.add(DoctorFinding(DoctorCheck.authorization, 1, '(none)'));
      }
    } on Object catch (error) {
      // Play services が応じないこと自体が所見である。**握り潰さない。**
      // 種別だけを出す — 例外文には端末の識別子が混ざりうる。
      findings.add(
          DoctorFinding(DoctorCheck.authorization, 1, '${error.runtimeType}'));
    }

    return DoctorReport(
      checked: const {
        DoctorCheck.homeWritable,
        DoctorCheck.authorization,
      },
      findings: findings,
    );
  }
}
