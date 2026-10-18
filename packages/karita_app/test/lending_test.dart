/// 貸出し画面へ出す窓口。**画面を立てずに合成層だけで測る。**
///
/// 見るのは4つ — 読み口が終端を落とすこと、書込みが台帳へ通って同期の起動が走ること、
/// 受取館の訂正がその Loan だけを動かすこと、そして**削除済みの図書館システムでも一覧が
/// 落ちない**こと（`非公開資料:ui-state-model.md`「削除で残るもの」）。
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_platform/karita_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-lending-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
  });
  tearDown(() {
    app.close();
    home.deleteSync(recursive: true);
  });

  LoanReportItem itemOf(String loanId) =>
      app.loadActiveLoans(loanId: loanId).single;

  LoanReportItem firstOf(String systemId, String status) => app
      .loadActiveLoans()
      .firstWhere((i) => i.systemId == systemId && i.status == status);

  group('読み口', () {
    test('返すのはアクティブな Loan だけである。終端は落ちる', () {
      final items = app.loadActiveLoans();
      expect(
        items.map((i) => i.status).toSet(),
        equals({'reserved', 'ready_for_pickup', 'borrowed'}),
      );
      expect(items, hasLength(13), reason: 'デモの5区ぶん');
      // 江戸川の expired と、江東・港の returned / cancelled は入らない。
      expect(items.where((i) => i.systemId == 'Tokyo_Edogawa'), isEmpty);
    });

    test('常用館が未設定のシステムは行を持たない', () {
      // 墨田だけ常用館を入れていない。受取館は記録に必須なので、予約そのものが無い。
      expect(
        app.preferredBranchFor('Tokyo_Sumida').state,
        equals(PreferredBranchState.unset),
      );
      expect(
        app.loadActiveLoans().where((i) => i.systemId == 'Tokyo_Sumida'),
        isEmpty,
      );
    });

    test('loanId で絞っても、重複と並行の判定は全件から決まる', () {
      // 港の予約は江東と同じ本である（デモの book 0）。1件だけ読んでも相手が見える。
      final minato = firstOf('Tokyo_Minato', 'reserved');
      expect(minato.parallelSystemIds, equals(['Tokyo_Koto']));
      expect(
        itemOf(minato.loanId).parallelSystemIds,
        equals(['Tokyo_Koto']),
        reason: '絞り込んでも全アクティブ Loan を読む',
      );
      expect(itemOf(minato.loanId).effective, isTrue);
    });

    test('受取館の名前はカタログから引く', () {
      final item = firstOf('Tokyo_Koto', 'borrowed');
      expect(item.pickupLibraryId, isNotNull);
      expect(item.pickupLibraryName, isNotNull);
      expect(item.configured, isTrue);
    });
  });

  group('書込み', () {
    test('遷移が通り、終端になると一覧から落ちる', () {
      final before = app.loadActiveLoans().length;
      final borrowed = firstOf('Tokyo_Koto', 'borrowed');
      app.updateLoan(loanId: borrowed.loanId, action: 'return');
      expect(app.loadActiveLoans(loanId: borrowed.loanId), isEmpty);
      expect(app.loadActiveLoans(), hasLength(before - 1));
    });

    test('日付の既定は業務側が作る。合成層は再定義しない', () {
      final reserved = firstOf('Tokyo_Koto', 'reserved');
      app.updateLoan(loanId: reserved.loanId, action: 'ready-for-pickup');
      final ready = itemOf(reserved.loanId);
      expect(ready.status, equals('ready_for_pickup'));
      final available = DateTime.parse(ready.pickupAvailableOn!);
      expect(
        DateTime.parse(ready.pickupDueOn!).difference(available).inDays,
        equals(7),
        reason: '取置は取置開始から7日',
      );
    });

    test('延長の起点は操作日である。元の期限ではない', () {
      final borrowed = firstOf('Tokyo_Koto', 'borrowed');
      app.updateLoan(loanId: borrowed.loanId, action: 'renew');
      final renewed = itemOf(borrowed.loanId);
      expect(renewed.status, equals('borrowed'));
      expect(
        DateTime.parse(
          renewed.dueOn!,
        ).difference(DateTime.parse(localToday())).inDays,
        equals(14),
      );
    });

    /// **前状態は問わない**（2026-09-19 の差し替え）。遷移の検査は業務層から落とした。
    test('どの状態からどの状態へでも書ける', () {
      final reserved = firstOf('Tokyo_Koto', 'reserved');
      app.updateLoan(loanId: reserved.loanId, action: 'return');
      expect(app.loadActiveLoans(loanId: reserved.loanId), isEmpty);

      app.updateLoan(loanId: reserved.loanId, action: 'reserve');
      expect(
        itemOf(reserved.loanId).status,
        equals('reserved'),
        reason: '返却済みから予約中へ戻せる',
      );
    });

    test('未知の操作だけは落ちる', () {
      final reserved = firstOf('Tokyo_Koto', 'reserved');
      expect(
        () => app.updateLoan(loanId: reserved.loanId, action: 'teleport'),
        throwsA(isA<LoanError>().having((e) => e.code, 'code', 'loan-action')),
      );
    });

    test('業務を書いたら同期の起動が走る', () async {
      final changed = app.statusChanges.first;
      final reserved = firstOf('Tokyo_Katsushika', 'reserved');
      app.updateLoan(loanId: reserved.loanId, action: 'cancel');
      await changed.timeout(const Duration(seconds: 2));
    });
  });

  group('受取館の訂正', () {
    test('その Loan だけが動く。常用館も他の行も動かない', () {
      final system = app.loadLibraries().firstWhere(
        (s) => s.id == 'Tokyo_Koto',
      );
      final other = system.branches[1];
      final target = firstOf('Tokyo_Koto', 'reserved');
      final sibling = app.loadActiveLoans().firstWhere(
        (i) => i.systemId == 'Tokyo_Koto' && i.loanId != target.loanId,
      );
      final preferred = app.preferredBranchFor('Tokyo_Koto');

      app.changeLoanPickupLibrary(
        loanId: target.loanId,
        systemId: 'Tokyo_Koto',
        branchId: other.id,
      );

      final moved = itemOf(target.loanId);
      expect(moved.pickupLibraryId, equals(other.id));
      expect(moved.pickupLibraryName, equals(other.name));
      expect(moved.status, equals(target.status), reason: '状態は動かない');
      expect(
        itemOf(sibling.loanId).pickupLibraryId,
        equals(sibling.pickupLibraryId),
        reason: '同じ区の他の行は動かない',
      );
      expect(
        app.preferredBranchFor('Tokyo_Koto'),
        equals(preferred),
        reason: '常用館は動かない',
      );
    });

    test('別のシステムの分館は合成層が止める', () {
      final target = firstOf('Tokyo_Koto', 'reserved');
      final minato = app.loadLibraries().firstWhere(
        (s) => s.id == 'Tokyo_Minato',
      );
      expect(
        () => app.changeLoanPickupLibrary(
          loanId: target.loanId,
          systemId: 'Tokyo_Koto',
          branchId: minato.branches.first.id,
        ),
        throwsA(
          isA<AppIssue>().having(
            (e) => e.code,
            'code',
            'pickup-library-unknown',
          ),
        ),
      );
      expect(
        itemOf(target.loanId).pickupLibraryId,
        equals(target.pickupLibraryId),
      );
    });

    /// **状態を見ない**（2026-09-19 の差し替え）。状態そのものを自由に書き直せる以上、
    /// 受取館だけを縛る理由が無い。
    test('返却済みの行でも直せる', () {
      final borrowed = firstOf('Tokyo_Koto', 'borrowed');
      final branch = app
          .loadLibraries()
          .firstWhere((s) => s.id == 'Tokyo_Koto')
          .branches[1];
      app.updateLoan(loanId: borrowed.loanId, action: 'return');
      app.changeLoanPickupLibrary(
        loanId: borrowed.loanId,
        systemId: 'Tokyo_Koto',
        branchId: branch.id,
      );
      // 一覧の読み口には出ないので、貸出中へ戻して確かめる。
      app.updateLoan(loanId: borrowed.loanId, action: 'borrow');
      expect(itemOf(borrowed.loanId).pickupLibraryId, equals(branch.id));
    });
  });

  group('削除済みの図書館システム', () {
    test('一覧は落ちない。館名が出なくなるだけである', () async {
      final before = app
          .loadActiveLoans()
          .where((i) => i.systemId == 'Tokyo_Koto')
          .length;
      expect(before, greaterThan(0));
      await app.removeLibrarySystem('Tokyo_Koto');

      final after = app
          .loadActiveLoans()
          .where((i) => i.systemId == 'Tokyo_Koto')
          .toList();
      expect(after, hasLength(before), reason: 'Loan は消えない');
      expect(after.every((i) => !i.configured), isTrue);
      expect(after.every((i) => i.pickupLibraryName == null), isTrue);
      expect(after.first.pickupLibraryId, isNotNull, reason: '記録した id は残る');
    });

    test('受取館は選び直せない。分館の一覧そのものが無い', () async {
      final target = firstOf('Tokyo_Koto', 'reserved');
      final branch = app
          .loadLibraries()
          .firstWhere((s) => s.id == 'Tokyo_Koto')
          .branches[1];
      await app.removeLibrarySystem('Tokyo_Koto');
      expect(
        () => app.changeLoanPickupLibrary(
          loanId: target.loanId,
          systemId: 'Tokyo_Koto',
          branchId: branch.id,
        ),
        throwsA(
          isA<AppIssue>().having(
            (e) => e.code,
            'code',
            'pickup-library-unknown',
          ),
        ),
      );
    });
  });
}
