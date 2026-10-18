/// ブラウザープラグインのインストールの段の状態。**Windows の初回セットアップで、始め方の次・
/// 図書館の登録の前に置く**（2026-10-15）。
///
/// Windows では「カーリル → 図書館サイト → 拡張 → karita」の往復が使い方の中心で、拡張が
/// 無いと予約・貸出しの記録がほぼ手入力になる。そこでサインインと同じ重さで扱い、**実際に
/// 1回送れたこと**を完了の条件にする。インストール・ピン留め・`karita://` の起動許可・
/// Windows の関連付けのどれが欠けても届かないので、1回届けば全部そろっている。
///
/// **必須にはしない。** 審査・管理された Edge・ストア未公開の拡張で行き止まりになるので、
/// ［プラグインなしで進む］を残し、予約画面と設定に入口を常設する。
///
/// 入れ方・ピン留め・許可の手順はアプリに持たない。ストア公開で変わるので、ガイドサイト
/// （[extensionGuideUrl]）に置き、アプリの更新なしに差し替えられるようにする。
library;

import 'dart:async';

import 'package:karita_app/karita_app.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../composition.dart';

part 'state.g.dart';

/// 拡張の入れ方・ピン留め・許可をまとめたガイドのページ。
final Uri extensionGuideUrl = Uri.parse(
  'https://karita.getperf.net/extensions/',
);

/// 連携の状態。**端末ごとの事実である**（`device.json`）。
class BrowserLinkStatus {
  /// この段を持つ端末か（Windows の本番だけ）。
  final bool applicable;

  /// 確かめた日時。**`null` は未確認。** 確かめ直したかを、開いた時点の値と比べて見る。
  final String? linkedAt;

  /// ［プラグインなしで進む］を選んだか。
  final bool skipped;

  const BrowserLinkStatus({
    required this.applicable,
    this.linkedAt,
    this.skipped = false,
  });

  bool get linked => linkedAt != null;
}

@Riverpod(keepAlive: true)
class BrowserLink extends _$BrowserLink {
  @override
  BrowserLinkStatus build() {
    final app = ref.watch(compositionProvider);
    final subscription = app.browserLinkChanges.listen((_) {
      if (ref.mounted) state = _read(app);
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    return _read(app);
  }

  BrowserLinkStatus _read(Composition app) => BrowserLinkStatus(
    applicable: app.browserLinkApplicable,
    linkedAt: app.settings.browserLinkedAt,
    skipped: app.browserLinkSkipped,
  );

  /// ［プラグインなしで進む］。**書けなくても先へは進める** — 次の起動でまた促すだけである。
  void skip() {
    try {
      ref.read(compositionProvider).skipBrowserLink();
    } on AppIssue {
      // 端末設定を書けない理由は設定画面の診断が出す。
    }
  }
}

/// この起動で初回セットアップ（初回の2択）を済ませたか。**セッションの中だけで、永続しない。**
///
/// プラグインの段を、**セットアップの続きとしてだけ**出すためにある。既に使っている
/// 端末の起動に割り込まない — そちらは予約画面と設定の入口から確かめる。
@Riverpod(keepAlive: true)
class SetupCompletedThisSession extends _$SetupCompletedThisSession {
  @override
  bool build() => false;

  void mark() => state = true;
}

/// プラグインの段を出すか。**`LibraryEnsure` と同じ形である。**
///
/// 一度出したら、利用者が終えるまで出し続ける — 届いた瞬間に消すと「つながりました」を
/// 読む前に画面が替わる。**終わるのは [finish] だけである**（［次へ］・
/// ［プラグインなしで進む］）。
@Riverpod(keepAlive: true)
class BrowserLinkEnsure extends _$BrowserLinkEnsure {
  bool _latched = false;
  bool _done = false;

  @override
  bool build() {
    if (_done) return false;
    final status = ref.watch(browserLinkProvider);
    if (_latched) return true;
    if (!ref.watch(setupCompletedThisSessionProvider)) return false;
    if (!status.applicable || status.linked || status.skipped) return false;
    _latched = true;
    return true;
  }

  void finish() {
    _done = true;
    ref.invalidateSelf();
  }
}

/// 開くブラウザーの選択（2026-10-16）。**端末ごとの設定である**（`device.json`）。
///
/// 拡張を入れたブラウザーと OS の既定が違う端末で、図書館サイトを拡張のある側で開く
/// ためにある。サインインは OS の既定のまま動かない。
class BrowserChoiceState {
  /// 選んでいる値（`system`・`edge`・`chrome`・`firefox`）。
  final String value;

  /// 保存できなかった理由。**`null` は失敗していない。**
  final AppIssue? error;

  const BrowserChoiceState(this.value, {this.error});
}

@Riverpod(keepAlive: true)
class BrowserChoice extends _$BrowserChoice {
  @override
  BrowserChoiceState build() {
    final app = ref.watch(compositionProvider);
    final subscription = app.browserLinkChanges.listen((_) {
      if (ref.mounted) state = BrowserChoiceState(app.browserChoice);
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    return BrowserChoiceState(app.browserChoice);
  }

  /// 保存する。**書けなければ前の値のまま、理由を持つ。**
  void save(String value) {
    final app = ref.read(compositionProvider);
    try {
      app.saveBrowserChoice(value);
      state = BrowserChoiceState(app.browserChoice);
    } on AppIssue catch (issue) {
      state = BrowserChoiceState(app.browserChoice, error: issue);
    }
  }
}

/// 見つかったブラウザー。**設定画面を開くたびに探し直す** — 入れた・消したを拾うため。
@riverpod
Future<Set<String>> installedBrowsers(Ref ref) =>
    ref.watch(compositionProvider).installedBrowsers();
