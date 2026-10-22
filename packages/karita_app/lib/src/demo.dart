/// デモの差し替え。**合成層の1箇所である。**
///
/// 正本は `非公開資料:demo-mode.md`。デモは UI 開発と検証のための起動構成であって、
/// 製品の別実装ではない。**本番と共通の業務処理・SQLite を使う。**
///
/// **`isDemo` を画面や業務へ配らない。** 意味は「データの出所と保存先」と「対象外の操作」に
/// 閉じる。画面が知るのは**戻り値がスキップかどうか**だけで、旗ではない。旗を配ると、ptune の
/// ように「デモの定義が2つある」状態になる。
///
/// **差し替えるのは3つである** — 業務DB、操作入口、自動処理の登録。4つ目だった起動準備
/// （fixture の投入）は [AppMode.seed] へ分けた。**デモかどうかと、種を撒くかどうかは
/// 直交する**（`非公開資料:demo-mode.md`「差し替えるのは3つ＋直交する種」）。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';

/// ビルド時の旗。`off` / `memory` / `temp`。**既定は `off`。**
///
/// **空文字は「未指定」である。** `--dart-define-from-file` は `KARITA_DEMO=` と書かれた行の
/// 空の値もそのまま渡すので、`defaultValue` が効かない
/// （`非公開資料:settings-and-parameters.md`「ビルド入力」）。
const String defineDemo = String.fromEnvironment(
  'KARITA_DEMO',
  defaultValue: 'off',
);

/// 種のシナリオ。**既定は無し**（空文字＝未指定）。
///
/// [defineDemo] とは直交する旗で、意味は「空の台帳に fixture を入れるか」だけである。
/// 組合せの意味と安全の境界は `非公開資料:p5b-verification-mode.md` が持つ。
const String defineSeed = String.fromEnvironment('KARITA_SEED');


/// 業務DBの保管方式。**違うのはそこだけである。**
///
/// **`temp` でもバックアップ・復元はスキップする。** `temp` が残る理由は「ファイル台帳
/// （`SqliteDb.open`）の経路を本番と同じに通すこと」であって、復元を触るためではない。
enum DemoMode {
  /// 本番。`home` の台帳を開く。
  off,

  /// メモリ SQLite。**終了後に端末へ何も残らない。**
  memory,

  /// 本番DBから分離した一時ファイルの SQLite。
  temp,
}

/// 対象外の操作をなぜ飛ばしたか。
///
/// **成功にも例外にもしない。** 成功にすると同期したように見え、例外にすると障害に見える。
enum SkipReason { demoMode }

/// 走らせたか、飛ばしたか。
///
/// **飛ばしたときは通信もファイル操作も始まっていない** — [OperationGate] が本体を呼ぶ前に
/// 決めるからである。
class Attempt<T> {
  final T? _value;
  final SkipReason? skipped;

  const Attempt.done(T value) : _value = value, skipped = null;

  const Attempt.skipped(SkipReason this.skipped) : _value = null;

  bool get wasSkipped => skipped != null;

  /// 走ったときの結果。**飛ばした呼び出しで読むと落ちる。**
  T get value => skipped == null
      ? _value as T
      : throw StateError('$skipped で飛ばした操作の結果は無い');
}

/// 対象外の操作を、始まる前に止める口。
///
/// **本番では素通りする。** `reason` が `null` のときは本体をそのまま呼ぶので、経路は1本の
/// ままである — デモのためだけの分岐が呼び出し側に増えない。
class OperationGate {
  final SkipReason? reason;

  const OperationGate([this.reason]);

  bool get open => reason == null;

  /// [body] を走らせる。飛ばすときは**呼ばない。**
  Future<Attempt<T>> run<T>(Future<T> Function() body) async {
    final skip = reason;
    if (skip != null) return Attempt<T>.skipped(skip);
    return Attempt<T>.done(await body());
  }
}

/// この起動の性格。**ログの最初の行に出す。**
class AppMode {
  final DemoMode demo;

  /// 種のシナリオ。`null` は「種なし」。**[demo] とは直交する。**
  ///
  /// 本番モード（`off`）に種を撒いたものが**検証モード**である — 実認可・実 Drive・実同期が
  /// 通る台帳に、デモと同じ30冊が載る（`非公開資料:p5b-verification-mode.md`）。
  final String? seed;

  const AppMode(this.demo, {this.seed});

  /// 不正値では起動を中止する。本番DBへフォールバックしない。
  ///
  /// **空文字は「値を与えなかった」であって不正値ではない。** `--dart-define-from-file` は
  /// 空の値もそのまま渡すので、読み手の側で1行ぶん区別する。
  ///
  /// 種には3つのガードが順に効く（`非公開資料:p5b-verification-mode.md`「安全の境界」）。
  ///
  /// ① **デスクトップでしか立たない**（ここ）。② **`release` ビルドでは受け付けない**（ここ）。
  /// ③ **本番のデータ領域では立たない**（[refuseSeedOnProductionHome]。置き場所を決める側）。
  ///
  /// **①だけでは配布物に種が焼ける事故を塞げず、②だけでは今後の運用（`--debug`）で一度も
  /// 効かない。** ③ は「消してよい台帳か」を見るもので、①②とは別のことを測っている。
  ///
  /// **2026-09-23 に ① を書き換えた。** 元は「`KARITA_HOME` を明示したときだけ使える」で、
  /// 既定のデータ領域を守るのに**人が毎回パスを打つこと**を求めていた。守りたいのは
  /// 「本番の台帳を消さない」であって「明示すること」ではないので、③ で直接見る形にし、
  /// 種モードには**専用の既定の置き場所**（OS の一時領域）を与えた。
  factory AppMode.resolve({
    String demo = defineDemo,
    String seed = defineSeed,
    bool releaseMode = kReleaseMode,
    // **既定は `Platform` から採る**（定数にできないので `null` を挟む）。試験だけが差し替える。
    bool? mobile,
  }) {
    final wanted = demo.trim().toLowerCase();
    DemoMode? mode = wanted.isEmpty ? DemoMode.off : null;
    for (final candidate in DemoMode.values) {
      if (candidate.name == wanted) mode = candidate;
    }
    if (mode == null) {
      throw const FormatException('KARITA_DEMO must be off, memory or temp');
    }

    final scenario = seed.trim();
    if (scenario.isEmpty) return AppMode(mode);
    // ① Android・iOS では使えない。**データ領域を分ける手段が無い** — `KARITA_HOME` を渡す経路が
    // 無く、アプリの領域は1つしかないので、種を撒けば実データの台帳を消すことになる。
    // 代わりに同期で流す（`非公開資料:p5b-verification-mode.md`「Android では種を使わない」）。
    if (mobile ?? (Platform.isAndroid || Platform.isIOS)) {
      throw StateError('KARITA_SEED は Android・iOS では使えない（同期で流す）');
    }
    // ② ①の二重化。**配布物に種が焼けること自体が別の事故である。**
    if (releaseMode) {
      throw StateError('release ビルドに KARITA_SEED は入れられない');
    }
    return AppMode(mode, seed: scenario);
  }

  bool get isDemo => demo != DemoMode.off;

  /// 種が実際に働くか。**デモは自分の起動準備で fixture を入れるので、種は要らない。**
  ///
  /// 台帳の自動リセットと転送先の掃除は、この旗が立っているときだけ走る。
  bool get seedMode => seed != null && !isDemo;

  /// 対象外の操作に使う口。**本番では素通りの口が返る。**
  OperationGate get gate => OperationGate(isDemo ? SkipReason.demoMode : null);

  /// **自動同期を登録しない。** デモは周期リフレッシュを回さない。
  bool get autoRefreshAllowed => !isDemo;

  /// ログの最初の行に載せる分。**デモの記録と本番の記録を混ぜない。**
  ///
  /// **種のときは `seed` を出す。** 証拠の記録から「この起動は種入りだった」が後から読める
  /// ようにするためで、出さないと検証の記録と本番の記録が見分けられない。
  Map<String, Object?> toLogFields() => {
    'mode': isDemo ? 'demo' : 'production',
    'ledger': switch (demo) {
      DemoMode.off => 'file',
      DemoMode.memory => 'memory',
      DemoMode.temp => 'temp',
    },
    if (seed != null) 'seed': seed,
  };
}

/// 開いた業務DBと、閉じるときにすること。
class Ledger {
  final DbSession session;
  final void Function() dispose;

  const Ledger(this.session, this.dispose);
}

/// 業務DBを開く。**本番DBを開く・削除する経路へフォールバックしない。**
///
/// `memory` と `temp` は本番の保存先に一切触れない。**本番データがある端末でデモを起動しても、
/// 本番の台帳は開かれない。**
Ledger openLedger(DemoMode mode, AppPaths paths) => switch (mode) {
  DemoMode.off => Ledger(DbSession.open(paths.dbPath), () {}),
  DemoMode.memory => Ledger(DbSession.memory(), () {}),
  DemoMode.temp => _temp(),
};

Ledger _temp() {
  // **本番の `home` の下に置かない。** 置くと、保持するログや設定を巻き込まずに回収する単位が
  // 作れない。異常終了で残った場合は OS の一時領域の掃除に任せる。
  final dir = Directory.systemTemp.createTempSync('karita-demo-');
  return Ledger(DbSession.open(AppLayout.under(dir.path, AppLayout.db)), () {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
}

/// デモの認可。**呼ばれたら落ちる。**
///
/// 認可の操作入口は [OperationGate] が先に止めるので、ここへは来ない。**来たことが分かる形に
/// しておく** — 静かに空のトークンを返すと、転送が 401 を受けてから「デモなのに通信した」と
/// 気づくことになる。
class DemoAccessTokenProvider implements AccessTokenProvider {
  const DemoAccessTokenProvider();

  @override
  Future<String> accessToken({bool forceRefresh = false}) async =>
      throw TransportAuthError('デモモードでは転送しません。');
}

/// デモの環境検査。**データ領域へ書けるかだけを見る。**
///
/// 資格情報も保存トークンも持たないので、その2つは**走らせない**。`DoctorReport.checked` に
/// 入れないことで、「異常が無い」と「検査していない」が混ざらない。
class DemoEnvironmentDoctor implements EnvironmentDoctor {
  final AppPaths paths;

  const DemoEnvironmentDoctor(this.paths);

  @override
  Future<DoctorReport> check() async {
    final findings = <DoctorFinding>[];
    try {
      Directory(paths.home).createSync(recursive: true);
      final probe = File(AppLayout.under(paths.home, '.doctor-probe'));
      probe.writeAsStringSync('', flush: true);
      probe.deleteSync();
    } on FileSystemException {
      findings.add(DoctorFinding(DoctorCheck.homeWritable, 1, paths.home));
    }
    return DoctorReport(
      checked: const {DoctorCheck.homeWritable},
      findings: findings,
    );
  }
}
