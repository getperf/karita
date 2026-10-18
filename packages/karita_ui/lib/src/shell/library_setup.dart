/// 図書館の登録を促す段。**ゲートが開いた後、タブ本体の前に居る。**
///
/// 図書館が1件も無いと、予約・貸出し・本棚のどれも行き先が無い。**初回起動の2択は台帳を
/// 作るまでで、図書館は決めない**（`first_run/view.dart`）ので、その後にここで促す。
///
/// **条件で決める。持ち回る旗を作らない。** 初回・復元後・ブラウザーからの受信・既に使って
/// いた端末で図書館が0件になった場合のどれでも、同じ1本で効く。
///
/// **同期が一巡するまで促さない。** 「新しく始める」は既存の世代へ `adopt` することがあり、
/// 他端末の登録は封筒を取り込むまで届かない。取り込む前の0件を未登録と読むと、登録済みの
/// 利用者に促してしまう。判定に使うのは `lastSuccessAt`（取り込みまで成功した最後の run）で
/// ある。**送信だけの run は数えない**ので、「取り込んだうえで0件」と言える。
///
/// **`pendingHandoffTriage` より先である。** 受信した配送は Provider が持ち続けるので、登録が
/// 済んでから行き先の選択へ戻る。地区の選択肢は登録済みの館を読むため、0件では出せない。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../density.dart';
import '../libraries/add.dart';
import '../libraries/state.dart';
import '../settings/state.dart';
import 'navigation.dart';

part 'library_setup.g.dart';

/// 登録を促す段を出すか。
///
/// **一度出したら、利用者が終えるまで出し続ける。** 終わりは登録の件数では決めない —
/// 1件で外すと、同じ地区の複数の館や、別の地区の館を続けて登録できない。途中で同期が走っても
/// （`syncing` になっても）、選んでいる最中の県や候補の一覧を手放さない。
///
/// **終わるのは [finish] だけである**（戻る矢印・［完了］・［あとで］）。**セッションの中だけで、
/// 永続しない** — 0件のまま終えれば、次の起動でまた促す。
@Riverpod(keepAlive: true)
class LibraryEnsure extends _$LibraryEnsure {
  bool _latched = false;
  bool _done = false;

  @override
  bool build() {
    if (_done) return false;
    // **台帳が読めないときは促さない。** 読めない理由は別の画面が出す。
    final Map<String, LibrarySystem> registered;
    try {
      registered = ref.watch(librariesProvider);
    } catch (_) {
      return false;
    }
    if (_latched) return true;
    if (registered.isNotEmpty) return false;
    final status = ref.watch(syncStatusProvider).asData?.value;
    if (status == null || status.lastSuccessAt == null) return false;
    if (status.state == AppSyncState.syncing) return false;
    _latched = true;
    return true;
  }

  /// 終える。**この起動のあいだは促さない。**
  void finish() {
    _done = true;
    ref.invalidateSelf();
  }
}

/// 登録を促す画面。**県を選ぶ → 候補から登録する、の2段である。** 登録しても閉じない —
/// 続けて別の館を登録でき、終えるのは戻る矢印（1段目で）か［完了］［あとで］である。
///
/// 段は図書館管理の追加（`libraries/add.dart`）をそのまま使う。**経路の状態
/// （`LibrariesRoute`）は使わない** — あちらは `ledgerSessionProvider` で作り直されるため、
/// 起動直後の同期で選択を失う（`handoff_triage.dart`）。県はこの画面が持つ。
class LibrarySetupScreen extends ConsumerStatefulWidget {
  const LibrarySetupScreen({super.key});

  @override
  ConsumerState<LibrarySetupScreen> createState() => _LibrarySetupScreenState();
}

class _LibrarySetupScreenState extends ConsumerState<LibrarySetupScreen> {
  /// 選んだ県。`null` は県を選ぶ段。
  String? _pref;

  /// 登録済みの件数。**読めなければ0として扱う**（促しの判定と同じ）。
  int _registeredCount() {
    try {
      return ref.watch(librariesProvider).length;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final density = ref.watch(densityProvider);
    final pref = _pref;
    final count = _registeredCount();
    // **戻るは1段ずつ降り、1段目で終える。** 矢印も OS の戻る操作も同じである。
    void back() {
      if (_pref != null) {
        setState(() => _pref = null);
      } else {
        ref.read(libraryEnsureProvider.notifier).finish();
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: density.control,
                          minHeight: density.control,
                        ),
                        child: IconButton(
                          onPressed: back,
                          icon: const Icon(Icons.arrow_back),
                          tooltip: '戻る',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                pref ?? '図書館を登録してください',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // **始める条件をヘッダーで言う。** 登録が無いと、どのタブも
                            // 使えない。登録できたら、続けられることと終え方を言う。
                            Text(
                              count == 0
                                  ? 'karita を使い始めるには、図書館の登録が必要です。'
                                  : '$count 件を登録しました。続けて追加できます。'
                                        '終えるときは［完了］を押してください。',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(libraryEnsureProvider.notifier).finish(),
                        child: Text(count == 0 ? 'あとで' : '完了'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: ConstrainedBox(
                    key: const ValueKey('library-setup-content'),
                    constraints: BoxConstraints(
                      maxWidth: ShellTab.settings.contentMaxWidth,
                    ),
                    child: pref == null
                        ? AddPrefectureScreen(
                            onPick: (value) => setState(() => _pref = value),
                          )
                        : AddSearchScreen(
                            key: ValueKey('setup-add:$pref'),
                            pref: pref,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
