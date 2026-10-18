/// 貸出し一覧の状態。**デモの台帳に対して、widget を立てずに測る。**
///
/// ここで確かめるのは段階3 の決定そのものである — 読み直す契機は2つだけ、書込みでは行が
/// 動かない、終端行は更新まで残る、件数はフィルタごとに全区の合計。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_ui/karita_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;
  late ProviderContainer container;
  late Lending actions;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-lending-ui-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
    container = ProviderContainer(
      overrides: [compositionProvider.overrideWithValue(app)],
    );
    container.read(lendingProvider);
    actions = container.read(lendingProvider.notifier);
    actions.refresh();
  });
  tearDown(() {
    container.dispose();
    app.close();
    home.deleteSync(recursive: true);
  });

  LendingState state() => container.read(lendingProvider);

  String loanIn(String systemId, String status) => state().order.firstWhere(
    (id) =>
        state().rows[id]!.systemId == systemId &&
        state().rows[id]!.status == status,
  );

  group('読み直す契機', () {
    test('build の直後は読んでいない。先頭のタブは予約である', () {
      final fresh = ProviderContainer(
        overrides: [compositionProvider.overrideWithValue(app)],
      );
      addTearDown(fresh.dispose);
      expect(fresh.read(lendingProvider).unread, isTrue);
      expect(fresh.read(lendingProvider).order, isEmpty);
      fresh.dispose();
    });

    test('タブ入場で読み直す', () async {
      final fresh = ProviderContainer(
        overrides: [compositionProvider.overrideWithValue(app)],
      );
      addTearDown(fresh.dispose);
      fresh.read(lendingProvider);
      expect(fresh.read(lendingProvider).unread, isTrue);
      fresh.read(currentTabProvider.notifier).select(ShellTab.lending);
      expect(fresh.read(lendingProvider).order, hasLength(13));
      // **同じタブに居続けても読み直さない。**
      fresh.read(currentTabProvider.notifier).select(ShellTab.lending);
      expect(fresh.read(lendingProvider).order, hasLength(13));
    });

    test('台帳が変わっても勝手には読み直さない', () async {
      final before = state().order.length;
      // 合成層の変更通知（`ledgerRevisionProvider` が見ている経路）を起こす。
      final sumida = app.loadLibraries().firstWhere(
        (s) => s.id == 'Tokyo_Sumida',
      );
      await app.savePreferredBranch('Tokyo_Sumida', sumida.branches.first.id);
      expect(state().order, hasLength(before), reason: '一覧は ledger を見ない');
    });
  });

  group('件数とフィルタ', () {
    test('件数は全管理区分の合計で、フィルタごとに出る', () {
      // デモ: 予約中7・取置中2・貸出中4（5区ぶん）。
      expect(state().countFor(LendingFilter.all), equals(13));
      expect(state().countFor(LendingFilter.reserved), equals(7));
      expect(
        state().countFor(LendingFilter.soon),
        lessThanOrEqualTo(6),
        reason: '受取と返却間近は取置中・貸出中（6）の部分集合である',
      );
    });

    test('フィルタは 全件・受取と返却間近・予約中 の3つで、既定は全件（2026-10-15）', () {
      expect(LendingFilter.values, [
        LendingFilter.all,
        LendingFilter.soon,
        LendingFilter.reserved,
      ]);
      expect(state().filter, LendingFilter.all, reason: '開いた直後に予約中の本も見える');
    });

    test('フィルタを変えても件数は動かない。押す前に分かる数である', () {
      final before = [
        for (final f in LendingFilter.values) state().countFor(f),
      ];
      actions.select(LendingFilter.reserved);
      expect([
        for (final f in LendingFilter.values) state().countFor(f),
      ], equals(before));
    });

    test('フィルタは全管理区分へ一括で効く。0件の区も落とさない', () {
      final systems = app.loadLibraries();
      actions.select(LendingFilter.reserved);
      final areas = state().areasFor(systems);
      expect(areas, hasLength(5), reason: '墨田も江戸川も枠として出る');
      expect(
        areas.every((a) => a.items.every((i) => i.status == 'reserved')),
        isTrue,
      );
      expect(areas.where((a) => a.items.isEmpty), isNotEmpty);
    });

    test('管理区分は systemid 単位である。区を越えて束ねない', () {
      final areas = state().areasFor(app.loadLibraries());
      expect(areas.map((a) => a.systemId).toSet(), hasLength(areas.length));
      for (final area in areas) {
        expect(area.items.every((i) => i.systemId == area.systemId), isTrue);
      }
    });
  });

  group('連続操作で行が動かない', () {
    test('状態を変えても並びも枠も変わらない', () {
      final before = [...state().order];
      final target = loanIn('Tokyo_Koto', 'reserved');
      final section = state().section[target];
      actions.apply(loanId: target, action: 'ready-for-pickup');

      expect(state().order, equals(before), reason: '並びは動かない');
      expect(state().rows[target]!.status, equals('ready_for_pickup'));
      expect(
        state().section[target],
        equals(section),
        reason: '枠は更新までそのまま。予約中の下に取置中の行が残る',
      );
      expect(section, equals(LendingSection.reserved));
    });

    /// **どの状態からどの状態へでも書ける**（2026-09-19 の差し替え）。前状態を見る規則は
    /// 業務層から落としたので、同じ行へ4つの状態を順に当てても全部通る。
    test('同じ行に4つの状態を順に当てても並びは一度も変わらない', () {
      final before = [...state().order];
      final target = loanIn('Tokyo_Koto', 'reserved');
      for (final (action, status) in const [
        ('borrow', 'borrowed'),
        ('reserve', 'reserved'),
        ('ready-for-pickup', 'ready_for_pickup'),
        ('return', 'returned'),
      ]) {
        actions.apply(loanId: target, action: action);
        expect(state().statusOf(target), equals(status), reason: action);
        expect(state().order, equals(before));
      }
    });

    test('受取館を変えてもその行だけが差し替わる', () {
      final before = [...state().order];
      final target = loanIn('Tokyo_Koto', 'reserved');
      final others = {
        for (final id in state().order)
          if (id != target) id: state().rows[id],
      };
      final branch = app
          .loadLibraries()
          .firstWhere((s) => s.id == 'Tokyo_Koto')
          .branches[1];

      actions.changePickupLibrary(
        loanId: target,
        systemId: 'Tokyo_Koto',
        branchId: branch.id,
      );

      expect(state().order, equals(before));
      expect(state().rows[target]!.pickupLibraryName, equals(branch.name));
      for (final entry in others.entries) {
        expect(
          identical(state().rows[entry.key], entry.value),
          isTrue,
          reason: '他の行は同じ instance のまま',
        );
      }
    });
  });

  group('一覧から外れる行', () {
    test('返却しても位置に残り、更新で外れる', () {
      final target = loanIn('Tokyo_Koto', 'borrowed');
      final index = state().order.indexOf(target);
      actions.apply(loanId: target, action: 'return');

      expect(state().leaving[target], equals('returned'));
      expect(state().statusOf(target), equals('returned'));
      expect(state().order.indexOf(target), equals(index), reason: '位置に残る');
      expect(state().rows[target], isNotNull, reason: '最後の中身を持ったまま出す');
      expect(state().leavingCount, equals(1));

      actions.refresh();
      expect(state().order.contains(target), isFalse);
      expect(state().leaving, isEmpty);
      expect(state().message, contains('1件'));
    });

    /// **外れた行も操作できる**（2026-09-19 の差し替え）。状態は自由に書き直せるので、
    /// 押し間違えた返却をその場で戻せる — 更新を待たされない。
    test('返却した行を貸出中へ戻すと一覧へ帰ってくる', () {
      final target = loanIn('Tokyo_Koto', 'borrowed');
      actions.apply(loanId: target, action: 'return');
      expect(state().leaving.containsKey(target), isTrue);

      actions.apply(loanId: target, action: 'borrow');
      expect(state().leaving.containsKey(target), isFalse);
      expect(state().statusOf(target), equals('borrowed'));
      expect(state().leavingCount, equals(0));
    });

    test('返却しても読んだには入らない', () {
      actions.apply(loanId: loanIn('Tokyo_Koto', 'borrowed'), action: 'return');
      // 段階3 では `読んだ`（ReadingRecord）を持たない。台帳に本棚の集約は無い。
      expect(
        app.db.select(
          "SELECT name FROM sqlite_master WHERE name = 'reading_records'",
        ),
        isEmpty,
      );
    });

    test('外れた行は件数から落ちる', () {
      final before = state().countFor(LendingFilter.all);
      actions.apply(loanId: loanIn('Tokyo_Koto', 'borrowed'), action: 'return');
      expect(state().countFor(LendingFilter.all), equals(before - 1));
    });
  });

  group('失敗', () {
    test('別システムの分館は止まる', () {
      final target = loanIn('Tokyo_Koto', 'reserved');
      final minato = app.loadLibraries().firstWhere(
        (s) => s.id == 'Tokyo_Minato',
      );
      actions.changePickupLibrary(
        loanId: target,
        systemId: 'Tokyo_Koto',
        branchId: minato.branches.first.id,
      );
      expect(state().message, contains('図書館管理'));
    });
  });

  group('削除済みの図書館システム', () {
    test('枠は残り、後ろへ回る', () async {
      await app.removeLibrarySystem('Tokyo_Koto');
      actions.refresh();
      final areas = state().areasFor(app.loadLibraries());
      final koto = areas.firstWhere((a) => a.systemId == 'Tokyo_Koto');
      expect(koto.configured, isFalse);
      expect(koto.items, isNotEmpty, reason: 'Loan は消えない');
      expect(areas.last.systemId, equals('Tokyo_Koto'));
    });

    test('分館の一覧が無いので受取館は選び直せない', () async {
      await app.removeLibrarySystem('Tokyo_Koto');
      actions.refresh();
      expect(container.read(lendingBranchesProvider('Tokyo_Koto')), isEmpty);
    });
  });
}
