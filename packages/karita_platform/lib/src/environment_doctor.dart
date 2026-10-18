/// 自己診断の**環境の分**。口と、Windows の実装。
///
/// 台帳から読める分は `karita_sync` の `ledgerDoctor` が見る。ここが見るのは
/// **台帳の外にあるもの** — データ領域へ書けるか、資格情報が読めるか、認可があるかである。
///
/// **口を純 Dart に置き、Windows の実装をここに置く。** Android は `path_provider` と
/// Play services を要るので `karita_platform_flutter` が持つ。`AppPaths` と
/// `AccessTokenProvider` を定義側と実装側に割ったのと同じ形で、これが3回目である。
///
/// **端末によって走る検査が違う。** Android には資格情報のファイルも保存トークンも無い。
/// だから [DoctorReport.checked] に「走らせた分」を入れて返す — **「異常が無い」と
/// 「検査していない」を混ぜないため**である。
///
/// **通信しない。** 自己診断がネットワークを要求すると、回線が落ちているだけの端末が
/// 「異常」を名乗る。オフラインかどうかは導出が `offline` として別に受け取っている。
///
/// 移送元: book-sync-model の `bsync admin doctor`（HOME の書き込み可否と設定の検査）。
library;

import 'dart:io';

import 'package:karita_sync/karita_sync.dart';

import 'app_paths.dart';
import 'credentials.dart';
import 'google_auth.dart';

/// 環境を見る口。**実装は端末ごとに違う。**
abstract interface class EnvironmentDoctor {
  /// 走らせた検査と、引っかかったものを返す。
  Future<DoctorReport> check();
}

/// Windows の環境検査。
///
/// **3つ全部を見る。** データ領域へ書けるか、Desktop クライアントの資格情報が読めるか、
/// 保存したトークンがあるか。Android と違い、どれもファイルとして手元にある。
class WindowsEnvironmentDoctor implements EnvironmentDoctor {
  final AppPaths paths;

  /// 保存したトークンを見る側。**値は出さない** — 有無と期限だけを読む。
  final GoogleAccessTokenProvider tokens;

  const WindowsEnvironmentDoctor({required this.paths, required this.tokens});

  @override
  Future<DoctorReport> check() async {
    final findings = <DoctorFinding>[];

    // --- データ領域へ書けるか -----------------------------------------------
    //
    // **実際に書いて消す。** 存在の確認だけでは、読めるが書けない場所（権限、同期フォルダの
    // 競合、ディスク満杯）を捕まえられない。台帳が書けないことは起動してから分かるのでは遅い。
    final home = paths.home;
    try {
      Directory(home).createSync(recursive: true);
      final probe = File('$home${Platform.pathSeparator}.doctor-probe');
      probe.writeAsStringSync('', flush: true);
      probe.deleteSync();
    } on FileSystemException {
      findings.add(DoctorFinding(DoctorCheck.homeWritable, 1, home));
    }

    // --- 資格情報 -----------------------------------------------------------
    //
    // 手動配置を優先し、なければ配布物の同梱 JSON を見る。認証と同じ解決規則。
    // **中身は読まない** — client secret を診断のために触る理由が無い。
    final credentials = resolveDesktopCredentialsPath(paths.credentialsPath);
    if (!File(credentials).existsSync()) {
      findings.add(DoctorFinding(DoctorCheck.credentials, 1, credentials));
    }

    // --- 認可 ---------------------------------------------------------------
    //
    // **`blocked_auth` とは別のことを見ている。** あちらは「認可を失って止まった outbox が
    // ある」で、こちらは「そもそも認可が無い」である。送るものが1件も無い端末では前者が
    // 立たないので、新しい端末の「まだサインインしていない」はここでしか出ない。
    //
    // **期限切れは所見にしない**（2026-09-06）。access token の寿命は1時間程度で、
    // **アイドルを跨げば必ず切れる。** 切れていることは異常ではなく時計であり、次の転送で
    // refresh が回復させる。[DoctorReport.failed] は重みづけを持たないので、ここへ足すと
    // **1時間放置しただけの端末が「異常」を名乗る。**
    //
    // **refresh もできない状態は、ここでは区別できない。** 区別するのは `blocked_auth` の
    // 仕事である — 認可を失って止まった outbox には専用の名前がある。ここは `present` だけを
    // 見て、Android（期限の概念を持たず、無音取得の可否だけを見る）と同じことを測る。
    //
    // **無いことと、あるが開けないことを分ける**（2026-10-18）。後者は保護済みの token を
    // 別ユーザー・別 PC・改変などで開けない状態で、再サインインで置き換わる。値は出さない。
    final status = tokens.status();
    if (!status.present) {
      findings.add(
        DoctorFinding(DoctorCheck.authorization, 1, switch (status.state) {
          TokenLoadState.unreadable => '(unreadable)',
          TokenLoadState.ioFailed => '(io-failed)',
          _ => '(none)',
        }),
      );
    }

    return DoctorReport(
      checked: const {
        DoctorCheck.homeWritable,
        DoctorCheck.credentials,
        DoctorCheck.authorization,
      },
      findings: findings,
    );
  }
}
