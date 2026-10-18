/// 受信の最終判定を唯一ここで受け、行き先へ配る。
///
/// **`handoffTriage` を購読する箇所はここ1つだけである。** `LendingRoute`/`LibrariesRoute` は
/// `ledgerSessionProvider` も見ているため、起動直後の同期状態変化（`ledger.changed`）だけで
/// 何度も作り直される — その一瞬に購読を張り直すと broadcast stream の性質上イベントを
/// 取りこぼす（実機で確認: 配送は正しく受信・解析されているのに画面が遷移しない不具合）。
/// このクラスは `compositionProvider` しか見ないので作り直されにくく、かつ [build] で
/// [HandoffQueue.latest] を pull 型で一度読むことで、購読が間に合わなかった分も拾う。
///
/// Amazon の受信（`ShelfReturnCandidate` ほか4つ）も**ここから**本棚・予約へ渡す。どれも
/// 利用者の選択を待たないので state には入れない
/// （`非公開資料:amazon-share-handoff.md` §3）。
///
/// 地区が一意に決まった受信（`LendingTriageCandidate`/`MypageTriageCandidate`）は
/// `LendingRoute.onLendingCandidate`/`LibrariesRoute.onMypageCandidate` へ**ここから**渡す。
/// 「利用者の選択が要る」2種類（`DistrictChoiceNeeded`/`PurposeChoiceNeeded`）だけを自分の
/// state に持ち、cold start の選択画面（[HandoffTriageScreen]）へ渡す
/// （`../../../karita-ui-probe/docs/browser-handoff.md` §3）。
///
/// **`FirstRunScreen` と同じ「外殻をプリエンプトする」前例に倣う**（`shell.dart`）。karita
/// 未起動時に届いた配送でも、台帳の準備（初回起動の2択）は先に済ませる — 地区選択は
/// `LibrarySystems` を読むので、台帳が無い状態では意味のある選択肢を出せない。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../bookshelf/state.dart';
import '../composition.dart';
import '../lending/state.dart';
import '../libraries/state.dart';
import '../reservation/state.dart';
import 'navigation.dart';

part 'handoff_triage.g.dart';

@Riverpod(keepAlive: true)
class PendingHandoffTriage extends _$PendingHandoffTriage {
  /// 直前まで見ていた配送の番号。**同じ配送を二度配らないためにある。**
  int _seenId = 0;

  @override
  HandoffTriage? build() {
    final app = ref.watch(compositionProvider);
    // **既に届いていた分を、フレームの後に一度読む。** 起動直後は、この Notifier が作られる
    // より前に配送が処理し終わっていることがある（`AppLinksShareInbox` の初期リンクは合成が
    // 終わった直後に届く）。組み立ての最中に他プロバイダ（`lendingRouteProvider` 等）を書き
    // 換えないよう、`reservation/state.dart` の `Reservation.build()` と同じく
    // `scheduleMicrotask` で1呼吸置く。
    scheduleMicrotask(() {
      if (ref.mounted) _checkLatest(app);
    });
    final subscription = app.handoffTriage.listen((_) {
      if (ref.mounted) _checkLatest(app);
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    return null;
  }

  void _checkLatest(Composition app) {
    final handoff = app.handoff;
    final id = handoff.latestId;
    if (id == _seenId) return;
    _seenId = id;
    final latest = handoff.latest;
    if (latest == null) return;
    final triage = app.triageOf(latest, handoff.launch, handoff.latestPurposeHint);
    if (triage != null) onTriage(triage);
  }

  /// 受信の最終判定が届いた。**公開しているのは試験のためである。**
  void onTriage(HandoffTriage triage) {
    switch (triage) {
      case LendingTriageCandidate(:final systemId):
        ref.read(lendingRouteProvider.notifier).onLendingCandidate(systemId);
      case MypageTriageCandidate(:final systemId, :final url):
        ref.read(librariesRouteProvider.notifier).onMypageCandidate(systemId, url);
      case DistrictChoiceNeeded() || PurposeChoiceNeeded():
        state = triage;
      case ShelfReturnCandidate(:final bookId):
        // **使ったので消す。** 判定（`triageOf`）は記録を消さないので、配ったここで消す。
        // 残すと、後日の別の本の共有を元の画面へ引き戻す。
        ref.read(compositionProvider).handoff.consume();
        _openShelf(bookId);
      case ShelfBookFound(:final bookId):
        _openShelf(bookId);
      case ShelfBookDraft(:final book):
        final reservation = ref.read(reservationProvider.notifier);
        // ［本を追加］と同じ文脈で下書きにする。保存・破棄で本棚へ戻る。
        reservation.openFromBookshelf();
        reservation.receive(
          BookDelivery(ref.read(compositionProvider).handoff.latestId, book),
        );
        ref.read(currentTabProvider.notifier).select(ShellTab.reserve);
      case AmazonNoIsbn():
        ref.read(reservationProvider.notifier).notice(amazonNoIsbnMessage);
        ref.read(currentTabProvider.notifier).select(ShellTab.reserve);
    }
  }

  /// 本棚へ戻す。[bookId] があればその本の記録、無ければ一覧。
  ///
  /// `openShelfRecord` と同じ順（相手の状態を先に置き、それからタブを移す）。帰り先は
  /// 持たない — 本棚から出た往復なので、閉じたら本棚の一覧でよい。
  void _openShelf(String? bookId) {
    ref.read(shelfReturnProvider.notifier).set(null);
    if (bookId != null) {
      ref.read(shelfOpenRequestProvider.notifier).open(bookId);
    }
    ref.read(currentTabProvider.notifier).select(ShellTab.bookshelf);
  }

  /// 解決した。**triage 画面が確定操作の最後に呼ぶ。**
  void resolve() => state = null;
}

/// 用途未確定の選択画面。**ブラウザーを再度開かない** — 受信済みの URL をその場で使う。
class HandoffTriageScreen extends ConsumerStatefulWidget {
  const HandoffTriageScreen({super.key, required this.triage});

  final HandoffTriage triage;

  @override
  ConsumerState<HandoffTriageScreen> createState() =>
      _HandoffTriageScreenState();
}

class _HandoffTriageScreenState extends ConsumerState<HandoffTriageScreen> {
  LaunchPurpose? _purpose;

  void _confirm(LaunchPurpose purpose, String systemId, Uri url) {
    switch (purpose) {
      case LaunchPurpose.lending:
        ref.read(lendingRouteProvider.notifier).openArea(systemId);
        ref.read(currentTabProvider.notifier).select(ShellTab.lending);
      case LaunchPurpose.mypageUrl:
        ref.read(librariesRouteProvider.notifier).openMypageUrl(
          systemId,
          returnTo: ShellTab.reserve,
          prefillUrl: url.toString(),
        );
      // この画面の選択肢に本棚は無い（`_PurposeChoice` は2択）。
      case LaunchPurpose.bookshelf:
        break;
    }
    ref.read(pendingHandoffTriageProvider.notifier).resolve();
  }

  @override
  Widget build(BuildContext context) {
    final triage = widget.triage;
    return Scaffold(
      appBar: AppBar(
        title: const Text('行き先を選ぶ'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'キャンセル',
          onPressed: () =>
              ref.read(pendingHandoffTriageProvider.notifier).resolve(),
        ),
      ),
      body: SafeArea(
        child: switch (triage) {
          DistrictChoiceNeeded(
            :final purpose,
            :final url,
            :final systemIdChoices,
          ) =>
            _DistrictChooser(
              choices: systemIdChoices,
              onPick: (systemId) => _confirm(purpose, systemId, url),
            ),
          PurposeChoiceNeeded(:final url) => _purpose == null
              ? _PurposeChoice(
                  onPick: (purpose) => setState(() => _purpose = purpose),
                )
              : _DistrictChooser(
                  choices: const [],
                  onPick: (systemId) => _confirm(_purpose!, systemId, url),
                ),
          // `LendingTriageCandidate`/`MypageTriageCandidate` はここへ来ない
          // （`PendingHandoffTriage.onTriage` が state に入れず直接タブへ渡す）。
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

/// 用途を選ぶ最初の1歩。**マイページ登録・貸出しを開くの2択。**
class _PurposeChoice extends StatelessWidget {
  const _PurposeChoice({required this.onPick});

  final ValueChanged<LaunchPurpose> onPick;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('何をしますか？'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => onPick(LaunchPurpose.lending),
          child: const Text('貸出しを開く'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => onPick(LaunchPurpose.mypageUrl),
          child: const Text('マイページ登録'),
        ),
      ],
    ),
  );
}

/// 地区を選ぶ。[choices] が空なら登録済み全システムをフォールバック表示する。
class _DistrictChooser extends ConsumerWidget {
  const _DistrictChooser({required this.choices, required this.onPick});

  final List<String> choices;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systems = choices.isEmpty
        ? ref.watch(libraryListProvider)
        : [
            for (final id in choices)
              if (ref.watch(libraryProvider(id)) case final system?) system,
          ];
    if (systems.isEmpty) {
      return const Center(child: Text('登録した図書館はありません。'));
    }
    return ListView.builder(
      itemCount: systems.length,
      itemBuilder: (context, index) {
        final system = systems[index];
        return ListTile(
          title: Text(system.name),
          subtitle: Text(system.pref),
          onTap: () => onPick(system.id),
        );
      },
    );
  }
}
