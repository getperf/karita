part of '../composition.dart';

/// 診断とデモ。自己診断と、デモの検査・作り直し。
///
/// **状態（フィールド）は持たない** — 拡張は持てないので、本体（`composition.dart`）に置く。
extension CompositionDiagnostics on Composition {
  /// 同じ接続から再検査する。編集後は初期状態と異なるため不合格になりうる。
  DemoFixtureReport verifyDemoFixture() {
    final fixture = _fixture;
    if (_closed || fixture == null) throw StateError('No active demo fixture');
    return fixture.verify(db);
  }

  /// 旧接続を閉じてから新セッションを作る。古いDomainContextから新DBへは書けない。
  /// UI側は古い画面を破棄する。外部要求の無効化は後続。
  ///
  /// **旧い共有待ちは捨てる。** 新しい [HandoffQueue] は番号を 0 から数え直すので、リセット前に
  /// OS 側の holder に残っていた配送を「新しい配送」として拾ってしまう。取りに行って処理済みに
  /// してから返す。
  /// **種モードには出さない。** あちらの作り直しは起動時に一度だけ走るもので、画面の操作
  /// 入口を持たない（`非公開資料:demo-mode.md`「種モードの自動リセット」）。
  Future<Composition> resetDemo({DateTime? date}) async {
    if (_closed || _fixture == null || !mode.isDemo) {
      throw StateError('No active demo session');
    }
    final catalog = jsonEncode(_fixture!.catalog);
    close();
    final next = await compose(
      paths: paths,
      settings: settings,
      mode: mode,
      demoCatalog: catalog,
      demoDate: date,
    );
    await next.handoff.discardPending();
    return next;
  }

  /// 台帳・環境・合成の3層を1つにする。**合成規則は `karita_sync` が持つ。**
  ///
  /// ここが決めるのは**いつ走らせるか**と、**合成層にしか見えないもの**だけである。何を健全と
  /// するかを harness が決めると、本番 GUI が別の規則を書く。
  Future<DoctorReport> runDoctor() async {
    final report = DoctorReport.merge([
      engine.doctor(),
      await environmentDoctor.check(),
      compositionDoctor(),
    ]);
    lastDoctor = report;
    _notifyStatus();
    _log.info('doctor.completed', {
      'failed': report.failed,
      'findings': report.findings.length,
    });
    return report;
  }

  /// 合成層の分。**端末設定と、業務の参照切れを見る。**
  ///
  /// **業務の参照切れをここに置くのは、①②が業務集約を知らないからである。** `karita_sync` の
  /// 台帳検査へ入れると、業務側の集約定義の変更が同期の側へ漏れる。合成層は両方を見られる
  /// 唯一の層である。
  DoctorReport compositionDoctor() => DoctorReport(
    checked: const {DoctorCheck.deviceConfig, DoctorCheck.danglingReference},
    findings: [
      for (final issue in settings.reportableIssues)
        DoctorFinding(DoctorCheck.deviceConfig, 1, '$issue'),
      for (final setting in LibrarySettings(domain).danglingPreferredBranches())
        DoctorFinding(
          DoctorCheck.danglingReference,
          1,
          '${setting.systemId}/${setting.key}',
        ),
    ],
  );
}
