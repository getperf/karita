/// 図書館管理の流れがログから追えること。**そして秘密が1つも出ないこと。**
///
/// 正本は `非公開資料:logging-and-diagnostics.md`。**書かないものの一覧**（token・
/// appkey・キー付き URL・生の応答・利用者入力）は宣言では守れないので、実際に流れた行を
/// 集めて見る。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:logging/logging.dart';

const String _koto = 'Tokyo_Koto';
const String _sumida = 'Tokyo_Sumida';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;
  late List<LogRecord> records;

  setUp(() async {
    // **sink は据えない。** 据えるのは `installLogging` の仕事で、ここが見たいのは
    // 「どの行が流れたか」である。
    Logger.root.level = Level.ALL;
    records = [];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    home = Directory.systemTemp.createTempSync('karita-log-lib-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
  });
  tearDown(() {
    Logger.root.level = Level.INFO;
    app.close();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  List<String> eventsOf({Level? atLeast}) => [
    for (final record in records)
      if (atLeast == null || record.level >= atLeast) record.message,
  ];

  Map<String, Object?> fieldsOf(String event) {
    final record = records.lastWhere((r) => r.message == event);
    return logFields(record);
  }

  test('**蔵書を押したのに外へ出ない端末が、記録から分かる**', () async {
    // 同梱キーの無い端末。`api.fetch` は1本も出ないので、押した事実が他に残らない。
    expect(app.calilKey.usable, isFalse);
    final result = await app.checkHoldings(
      lookup: app.holdings,
      isbn13s: const ['9784274219337'],
      systemIds: const ['Tokyo_Koto'],
    );
    expect(result.outcome, HoldingsRunOutcome.nothingToDo);
    expect(eventsOf(), contains('holdings.check.unavailable'));
    // **ISBN も書名も出さない。**
    final record = records.lastWhere(
      (r) => r.message == 'holdings.check.unavailable',
    );
    expect(record.message, isNot(contains('9784274219337')));
  });

  test('組み上がった端末の素性が1行出る。**取りに行かない口もそこに出る**', () {
    final fields = fieldsOf('app.composed');
    expect(fields['gate'], isTrue, reason: 'デモはゲートが開く');
    expect(
      fields['calil_library'],
      isFalse,
      reason: '図書館候補の取得はまだ合成していない。「取りに行っていない」が行から読める',
    );
    expect(fields['refresh'], isFalse, reason: 'デモは周期リフレッシュを登録しない');
  });

  test('台帳を読むたびに件数が出る', () {
    records.clear();
    app.loadLibraries();
    final fields = fieldsOf('libraries.loaded');
    expect(fields['systems'], 5);
    expect(fields['branches'], 10);
    expect(fields['level'], Level.FINE.name, reason: 'デバッグ水準である');
  });

  test('読めなければ分類だけが出る。例外の文言は出さない', () {
    app.db.execute('DROP TABLE library_systems');
    records.clear();
    expect(app.loadLibraries, throwsA(isA<AppIssue>()));
    final fields = fieldsOf('libraries.load.failed');
    expect(fields['code'], 'libraries-load');
    expect(fields.containsKey('message'), isFalse);
    expect('$fields', isNot(contains('SELECT')));
  });

  test('常用館の保存・解除・削除が INFO で1行ずつ出る', () async {
    final branch = app.librarySystems.read(_sumida)!.branches.first;
    records.clear();

    await app.savePreferredBranch(_sumida, branch.id);
    await app.clearPreferredBranch(_sumida);
    await app.removeLibrarySystem(_sumida);

    expect(
      eventsOf(atLeast: Level.INFO),
      containsAllInOrder([
        'library.preferred_branch.set',
        'library.preferred_branch.cleared',
        'library.removed',
      ]),
    );
    expect(fieldsOf('library.preferred_branch.set')['system'], _sumida);
    // **残るものを削除の行に載せる。** 後から台帳を引き直さずに答えられる。
    expect(fieldsOf('library.removed')['memberships'], 1);
    expect(fieldsOf('library.removed')['loans'], isA<int>());
  });

  test('業務が弾いたら分類だけが出て、成功の行は出ない', () async {
    records.clear();
    await expectLater(
      app.savePreferredBranch(_koto, 'calil:not-a-branch'),
      throwsA(isA<AppIssue>()),
    );
    expect(fieldsOf('library.preferred_branch.set.failed')['code'],
        'library-setting');
    expect(eventsOf(), isNot(contains('library.preferred_branch.set')));
    // **業務の文言は画面が出す側である。** ログに要るのは分類だけ。
    expect('${fieldsOf('library.preferred_branch.set.failed')}',
        isNot(contains('分館にありません')));
  });

  test('参照切れだけが出る。正常な読み取りは館ごとに行を増やさない', () {
    final koto = app.librarySystems.read(_koto)!;
    app.librarySystems.register(
      system: koto.copyWith(branches: [koto.branches.last]),
      now: nowUtc(),
    );
    records.clear();
    app.preferredBranchFor(_sumida); // 未設定
    expect(eventsOf(), isEmpty);
    app.preferredBranchFor(_koto); // 参照切れ
    expect(eventsOf(), ['library.preferred_branch.dangling']);
  });

  test('台帳の変更通知が1行出る。**再読込が起きたかどうかがここで決まる**', () async {
    records.clear();
    await app.syncAfterDomainWrite();
    expect(eventsOf(), contains('ledger.changed'));
  });

  test('テーマの保存が出る。**値は端末設定なので出してよい**', () {
    records.clear();
    app.saveTheme('dark');
    expect(fieldsOf('settings.theme.saved')['theme'], 'dark');
  });

  test('FINE がファイルの行になる。INFO では消える', () async {
    // **末端まで通す。** ここまでは `Logger.root` を覗いていただけで、sink を据えた先に
    // 行が届くかは別である（`installLogging` が `karita_app` の持ち物）。
    final logDir = '${home.path}${Platform.pathSeparator}logs';
    String read() =>
        File('$logDir${Platform.pathSeparator}karita.log').readAsStringSync();

    installLogging(logDir: logDir, level: Level.FINE, format: LogFormat.text);
    addTearDown(uninstallLogging);
    app.loadLibraries();
    await app.syncAfterDomainWrite();
    expect(read(), contains('FINE    karita.app libraries.loaded systems=5'));
    expect(read(), contains('karita.app ledger.changed'));

    // **既定の水準では消える。** 残るのは台帳を変えた事実だけである。
    installLogging(logDir: logDir, level: Level.INFO, format: LogFormat.text);
    final before = read().length;
    app.loadLibraries();
    expect(read().length, before, reason: 'FINE の行が INFO で出た');
    app.saveTheme('dark');
    expect(read(), contains('INFO    karita.app settings.theme.saved theme=dark'));
  });

  test('**秘密が1行も出ない。** 通した全部の行を見る', () async {
    await app.savePreferredBranch(
      _koto,
      app.librarySystems.read(_koto)!.branches.first.id,
    );
    app.saveTheme('light');
    app.loadLibraries();
    await app.runDoctor();

    final all = [for (final record in records) '${logFields(record)}'].join('\n');
    expect(all, isNotEmpty);
    for (final forbidden in const [
      'appkey',
      'token',
      'Bearer',
      'api.calil.jp',
      'api.openbd.jp',
      'https://',
      'SELECT',
    ]) {
      expect(all, isNot(contains(forbidden)), reason: '$forbidden が行に出た');
    }
    // パスも出さない（`KARITA_HOME` の下を名指ししない）。
    expect(all, isNot(contains(home.path)));
  });
}
