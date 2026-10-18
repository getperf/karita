/// 図書館管理が足した Provider。**画面を立てずに測る。**
///
/// 基本ステートの1本目は `state_test.dart` が widget で固定してあり、そちらは動かさない。
/// ここは `ProviderContainer` を直に作る — 並び順も常用館の3状態も、描かずに決まる。
///
/// 足場は `karita_app` のデモ（`DemoMode.memory`）。5区10分館で、**4区に常用館、墨田だけ
/// 未設定、江東だけマイページの取り込み値**という並びが fixture に既にある。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

const String _koto = 'Tokyo_Koto';
const String _sumida = 'Tokyo_Sumida';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition composition;
  late ProviderContainer container;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-ui-lib-');
    composition = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
    container = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(composition)],
    );
  });
  tearDown(() {
    container.dispose();
    composition.close();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  LibrarySystem systemOf(String id) => container.read(librariesProvider)[id]!;

  /// 台帳を直に書いた後、UI へ通知が届いたことにする。
  ///
  /// **業務の口（`Composition` の操作）を通した場合は要らない** — あちらは
  /// `syncAfterDomainWrite()` を呼ぶ。ここが要るのは、同期で他端末の変更が適用された状況を
  /// 作るために `librarySystems` を直に叩いたときだけである。
  void notifyLedger() =>
      container.read(ledgerRevisionProvider.notifier).state++;

  group('並び順', () {
    test('純関数：都道府県 → 名称 → id', () {
      LibrarySystem at(String id, String pref, String name) => LibrarySystem(
        id: id,
        pref: pref,
        city: '市',
        name: name,
        branches: const [Branch(id: 'b', calilLibkey: 'k', name: '館')],
      );
      expect(
        compareLibrarySystems(at('a', '北海道', 'あ'), at('b', '東京都', 'あ')),
        isNot(0),
      );
      expect(
        compareLibrarySystems(at('a', '東京都', 'あ'), at('b', '東京都', 'い')),
        lessThan(0),
      );
      // 同名なら id で決めきる。**並びが揺れないこと自体が要件である。**
      expect(
        compareLibrarySystems(at('b', '東京都', 'あ'), at('a', '東京都', 'あ')),
        greaterThan(0),
      );
      expect(
        compareLibrarySystems(at('a', '東京都', 'あ'), at('a', '東京都', 'あ')),
        0,
      );
    });

    test('一覧は台帳の system_id 順ではない', () {
      expect(container.read(librariesProvider).keys, [
        'Tokyo_Edogawa',
        'Tokyo_Katsushika',
        'Tokyo_Koto',
        'Tokyo_Minato',
        'Tokyo_Sumida',
      ]);
      expect(
        container.read(libraryListProvider).map((system) => system.id).toList(),
        isNot([
          'Tokyo_Edogawa',
          'Tokyo_Katsushika',
          'Tokyo_Koto',
          'Tokyo_Minato',
          'Tokyo_Sumida',
        ]),
      );
    });

    test('一覧は不変である', () {
      expect(
        () => container.read(libraryListProvider).removeAt(0),
        throwsUnsupportedError,
      );
    });
  });

  group('常用館', () {
    test('設定してあり、分館にも在る', () {
      final branch = container.read(preferredBranchProvider(_koto));
      expect(branch.state, PreferredBranchState.resolved);
      expect(branch.branchId, systemOf(_koto).branches.first.id);
      expect(branch.branchName, systemOf(_koto).branches.first.name);
    });

    test('未設定は失敗ではない（fixture は墨田だけ空にしてある）', () {
      final branch = container.read(preferredBranchProvider(_sumida));
      expect(branch.state, PreferredBranchState.unset);
      expect(branch.branchId, isNull);
    });

    test('分館が消えると参照切れになり、名前は引けない', () {
      // **カタログは洗い替えの対象、利用者値はそうではない**（`0011`）。分館を1件消した
      // 端末からの適用を、再登録（スナップショット）で作る。
      final koto = systemOf(_koto);
      composition.librarySystems.register(
        system: koto.copyWith(branches: [koto.branches.last]),
        now: nowUtc(),
      );
      notifyLedger();

      final branch = container.read(preferredBranchProvider(_koto));
      expect(branch.state, PreferredBranchState.dangling);
      expect(branch.branchId, koto.branches.first.id);
      expect(branch.branchName, isNull);
    });

    test('システムごと消えても参照切れとして出る', () {
      composition.librarySystems.remove(systemId: _koto, now: nowUtc());
      notifyLedger();
      expect(
        container.read(preferredBranchProvider(_koto)).state,
        PreferredBranchState.dangling,
      );
    });
  });

  group('マイページの出典', () {
    test('取り込み値が既定値より優先する（fixture は江東だけ持たせてある）', () {
      expect(
        container.read(mypageUrlProvider(_koto)).source,
        MypageUrlSource.imported,
      );
    });

    test('取り込み値が無ければ既定値表。確認日は作者の採取日である', () {
      final url = container.read(mypageUrlProvider(_sumida));
      expect(url.source, MypageUrlSource.bundled);
      expect(url.checkedOn, '2026-08-15');
    });

    test('既定値表に無ければ公式サイト、それも無ければ未設定', () {
      composition.librarySystems.register(
        system: const LibrarySystem(
          id: 'Tokyo_Chiyoda',
          pref: '東京都',
          city: '千代田区',
          name: '東京都千代田区',
          branches: [
            Branch(id: 'calil:1', calilLibkey: '四番町', name: '千代田区立四番町図書館'),
          ],
          homepageUrl: 'https://www.library.chiyoda.tokyo.jp/',
        ),
        now: nowUtc(),
      );
      composition.librarySystems.register(
        system: const LibrarySystem(
          id: 'Tokyo_Chuo',
          pref: '東京都',
          city: '中央区',
          name: '東京都中央区',
          branches: [
            Branch(id: 'calil:2', calilLibkey: '京橋', name: '中央区立京橋図書館'),
          ],
        ),
        now: nowUtc(),
      );
      notifyLedger();
      expect(
        container.read(mypageUrlProvider('Tokyo_Chiyoda')).source,
        MypageUrlSource.official,
      );
      expect(
        container.read(mypageUrlProvider('Tokyo_Chuo')).source,
        MypageUrlSource.unset,
      );
    });
  });

  group('削除で残るもの', () {
    test('棚卸記録と Loan を数え、利用者値の有無も出す', () {
      final impact = container.read(libraryRemovalImpactProvider(_koto));
      expect(impact.memberships, 1);
      expect(impact.loans, greaterThan(0));
      expect(impact.hasPreferredBranch, isTrue);
      expect(impact.hasMypageUrl, isTrue);
    });

    test('墨田は常用館もマイページの取り込み値も持たない', () {
      final impact = container.read(libraryRemovalImpactProvider(_sumida));
      expect(impact.hasPreferredBranch, isFalse);
      // **既定値表は台帳の行ではない。** 消えるのは利用者が保存した値だけである。
      expect(impact.hasMypageUrl, isFalse);
    });
  });

  group('台帳の変更通知', () {
    test('1回の保存で一覧・詳細・常用館が揃う', () async {
      expect(container.read(libraryListProvider).length, 5);
      expect(
        container.read(preferredBranchProvider(_sumida)).state,
        PreferredBranchState.unset,
      );

      await composition.savePreferredBranch(
        _sumida,
        systemOf(_sumida).branches.first.id,
      );

      expect(container.read(librariesProvider).length, 5);
      expect(
        container.read(preferredBranchProvider(_sumida)).state,
        PreferredBranchState.resolved,
      );
    });

    test('版は必ず動く（同じ値で止まる形になっていない）', () async {
      expect(container.read(ledgerRevisionProvider), 0);
      await composition.syncAfterDomainWrite();
      expect(container.read(ledgerRevisionProvider), 1);
      await composition.syncAfterDomainWrite();
      expect(container.read(ledgerRevisionProvider), 2);
    });
  });

  group('画面状態', () {
    test('閉じた状態から始まり、1つずつ戻る', () {
      final route = container.read(librariesRouteProvider.notifier);
      expect(container.read(librariesRouteProvider).isOpen, isFalse);
      expect(route.back(), isFalse, reason: '閉じているときの戻るは外へ渡す');

      route.openList();
      route.openDetail(_koto);
      route.openPreferredBranch(_koto);
      expect(container.read(librariesRouteProvider).systemId, _koto);

      expect(route.back(), isTrue);
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.detail,
      );
      expect(route.back(), isTrue);
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.list,
      );
      expect(route.back(), isTrue);
      expect(container.read(librariesRouteProvider).isOpen, isFalse);
      expect(route.back(), isFalse);
    });

    test('対象を失った画面からは一覧へ落とす', () {
      final route = container.read(librariesRouteProvider.notifier);
      route.openPreferredBranch(_koto);
      route.backToList();
      expect(
        container.read(librariesRouteProvider).screen,
        LibrariesScreen.list,
      );
      expect(container.read(librariesRouteProvider).systemId, isNull);
    });
  });

  group('操作', () {
    test('常用館を保存し、解除して未設定へ戻せる', () async {
      final save = container.read(preferredBranchSaveProvider.notifier);
      final branchId = systemOf(_sumida).branches.last.id;

      expect(await save.save(_sumida, branchId), isTrue);
      expect(container.read(preferredBranchSaveProvider).error, isNull);
      expect(
        container.read(preferredBranchProvider(_sumida)).branchId,
        branchId,
      );

      expect(await save.save(_sumida, null), isTrue);
      expect(
        container.read(preferredBranchProvider(_sumida)).state,
        PreferredBranchState.unset,
      );
    });

    test('分館に無い値は業務が弾く。コードとメッセージが残り、前の設定は変わらない', () async {
      final save = container.read(preferredBranchSaveProvider.notifier);
      expect(await save.save(_koto, 'calil:not-a-branch'), isFalse);
      final error = container.read(preferredBranchSaveProvider).error;
      expect(error, isNotNull);
      expect(error!.code, 'library-setting');
      expect(error.message, contains('分館にありません'));
      expect(
        container.read(preferredBranchProvider(_koto)).state,
        PreferredBranchState.resolved,
      );
    });

    test('削除すると一覧から消えるが、Loan の行は残る', () async {
      expect(
        await container.read(libraryRemoveProvider.notifier).remove(_koto),
        isTrue,
      );
      expect(container.read(librariesProvider).containsKey(_koto), isFalse);
      expect(container.read(libraryProvider(_koto)), isNull);
      // **台帳は既に耐えている**（`loan_reporting.dart` の `configured`）。
      expect(
        composition.db.select(
          'SELECT COUNT(*) AS n FROM loans WHERE system_id = ?',
          [_koto],
        ).first['n'],
        greaterThan(0),
      );
    });

    test('登録されていないシステムの削除は業務が弾く', () async {
      final remove = container.read(libraryRemoveProvider.notifier);
      expect(await remove.remove('Tokyo_NotRegistered'), isFalse);
      expect(
        container.read(libraryRemoveProvider).error!.code,
        'library-system-missing',
      );
    });

    test('閉じたセッションへ書かない', () async {
      composition.close();
      expect(
        await container.read(libraryRemoveProvider.notifier).remove(_koto),
        isFalse,
      );
      expect(
        container.read(libraryRemoveProvider).error!.code,
        'session-closed',
      );
    });
  });
}
