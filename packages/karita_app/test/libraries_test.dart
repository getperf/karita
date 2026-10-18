/// 図書館管理へ公開した口。**画面が知るのはここまでである。**
///
/// 測るのは3つ — 常用館が2集約をまたいで解決すること、削除で残るものを数えること、
/// **失敗が `AppIssue` になり、秘密もパスも例外の `toString()` も出ないこと**である
/// （設定の段で決めた前例）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_platform/karita_platform.dart';

const String _koto = 'Tokyo_Koto';
const String _sumida = 'Tokyo_Sumida';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Composition app;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('karita-app-lib-');
    app = await compose(
      paths: WindowsAppPaths.at(home.path)..ensure(),
      settings: const DeviceSettings(),
      mode: const AppMode(DemoMode.memory),
    );
  });
  tearDown(() {
    app.close();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  Composition withRefresh(
    RefreshLoop refresh, {
    CalilLibraryClient? libraryClient,
  }) => Composition(
    paths: app.paths,
    settings: const DeviceSettings(),
    mode: app.mode,
    auth: app.auth,
    client: app.client,
    session: app.session,
    engine: app.engine,
    domain: app.domain,
    deviceId: app.deviceId,
    environmentDoctor: app.environmentDoctor,
    background: app.background,
    handoff: app.handoff,
    openBrowser: app.openBrowser,
    refresh: refresh,
    libraryClient: libraryClient,
    calilKey: const CalilKeyChoice('test-key', CalilKeySource.none),
  );

  test('再取得は順序だけなら同期せず、変更を反映し、不完全な応答を適用しない', () async {
    final seeded = app.librarySystems.read(_koto)!;
    // Fixture IDs are bare numbers; real API registrations use calil:<libid>.
    final current = seeded.copyWith(
      branches: [
        for (final b in seeded.branches)
          Branch(id: 'calil:${b.id}', calilLibkey: b.calilLibkey, name: b.name),
      ],
    );
    app.librarySystems.register(system: current, now: nowUtc());
    var rows = [
      for (final b in current.branches)
        <String, Object?>{
          'libid': b.id.replaceFirst('calil:', ''),
          'libkey': b.calilLibkey,
          'formal': b.name,
          'systemid': current.id,
          'systemname': current.name,
          'pref': current.pref,
          'city': current.city,
          'url_pc': current.homepageUrl,
        },
    ];
    var runs = 0;
    final client = CalilLibraryClient(
      appkey: 'test-key',
      httpClient: MockClient((request) async {
        if (request.url.queryParameters.containsKey('city')) {
          expect(request.url.queryParameters['city'], current.city);
        }
        return http.Response.bytes(utf8.encode(jsonEncode(rows)), 200);
      }),
    );
    addTearDown(client.close);
    final local = withRefresh(
      RefreshLoop(
        ready: () => true,
        enabled: true,
        interval: const Duration(minutes: 5),
        run: (_) async {
          runs++;
        },
      ),
      libraryClient: client,
    );
    final version = app.librarySystems.aggregateVersion(_koto);
    rows = rows.reversed.toList();
    expect(await local.refreshLibraryBranches(_koto), 0);
    expect(runs, 0);
    expect(app.librarySystems.aggregateVersion(_koto), version);
    rows.first['formal'] = '変更した館名';
    expect(await local.refreshLibraryBranches(_koto), 1);
    expect(runs, 1);
    final saved = app.librarySystems.read(_koto);
    rows = [
      rows.first,
      {'systemid': _koto},
    ];
    await expectLater(
      local.refreshLibraryBranches(_koto),
      throwsA(isA<AppIssue>()),
    );
    expect(app.librarySystems.read(_koto), saved);
    await local.libraryCandidates('東京都');
    expect(app.librarySystems.read(_koto), saved);
    final validRow = rows.first;
    rows = [
      for (var i = 0; i < 2000; i++) {...validRow, 'libid': '$i'},
    ];
    await expectLater(
      local.refreshLibraryBranches(_koto),
      throwsA(isA<AppIssue>()),
    );
    await local.libraryCandidates('東京都');
    expect(app.librarySystems.read(_koto), saved, reason: '取得上限に達した応答も適用しない');
    rows = [];
    await expectLater(
      local.refreshLibraryBranches(_koto),
      throwsA(isA<AppIssue>()),
    );
    expect(app.librarySystems.read(_koto), saved);
    expect(runs, 1);
  });

  for (final clear in [false, true]) {
    test('常用館の${clear ? '解除' : '保存'}は同期完了を待たず、同期失敗でも保存を維持する', () async {
      final gate = Completer<void>();
      final finished = Completer<void>();
      var runs = 0;
      final local = withRefresh(
        RefreshLoop(
          ready: () => true,
          enabled: true,
          interval: const Duration(minutes: 5),
          run: (_) async {
            runs++;
            try {
              await gate.future;
            } finally {
              finished.complete();
            }
          },
        ),
      );
      final branch = app.librarySystems.read(_koto)!.branches.last;
      try {
        await (clear
                ? local.clearPreferredBranch(_koto)
                : local.savePreferredBranch(_koto, branch.id))
            .timeout(const Duration(seconds: 2));
        expect(runs, 1);
        expect(gate.isCompleted, isFalse);
        expect(
          local.preferredBranchFor(_koto).branchId,
          clear ? null : branch.id,
        );
      } finally {
        gate.completeError(StateError('offline'));
        await finished.future;
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        local.preferredBranchFor(_koto).branchId,
        clear ? null : branch.id,
      );
    });
  }

  for (final action in [
    'urlSave',
    'urlClear',
    'register',
    'refresh',
    'remove',
  ]) {
    test('$action は端末内保存後に返り、同期失敗でも台帳を維持する', () async {
      final gate = Completer<void>();
      var runs = 0;
      final local = withRefresh(
        RefreshLoop(
          ready: () => true,
          enabled: true,
          interval: const Duration(minutes: 5),
          run: (_) async {
            runs++;
            await gate.future;
          },
        ),
      );
      final candidate = LibrarySystemCandidate(
        systemId: _koto,
        systemName: '更新後の江東区',
        pref: '東京都',
        city: '江東区',
        branches: const [
          BranchCandidate(id: 'calil:new', libkey: '新館', name: '新館'),
        ],
      );
      if (action == 'urlClear') {
        await app.saveMypageUrl(_koto, Uri.parse('https://example.org/mypage'));
      }
      Object? savedValue() => switch (action) {
        'urlSave' || 'urlClear' => LibrarySettings(
          app.domain,
        ).read(_koto, settingMypageUrl)?.value,
        _ => app.librarySystems.read(_koto),
      };
      final before = savedValue();
      try {
        final operation = switch (action) {
          'urlSave' => local.saveMypageUrl(
            _koto,
            Uri.parse('https://example.org/mypage'),
          ),
          'urlClear' => local.clearMypageUrl(_koto),
          'register' => local.registerLibrary(candidate),
          'refresh' => local.refreshRegisteredFrom([candidate]),
          _ => local.removeLibrarySystem(_koto),
        };
        await operation.timeout(const Duration(seconds: 2));
        expect(runs, 1);
        expect(gate.isCompleted, isFalse);
        expect(savedValue(), isNot(before));
        final committed = savedValue();
        gate.completeError(StateError('offline'));
        await Future<void>.delayed(Duration.zero);
        expect(savedValue(), committed);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await Future<void>.delayed(Duration.zero);
      }
    });
  }

  group('読む', () {
    test('登録済みの図書館システムを返す。0件は正常な結果である', () {
      expect(app.loadLibraries().map((system) => system.id), [
        'Tokyo_Edogawa',
        'Tokyo_Katsushika',
        _koto,
        'Tokyo_Minato',
        _sumida,
      ]);
      for (final id in app.loadLibraries().map((s) => s.id).toList()) {
        app.librarySystems.remove(systemId: id, now: nowUtc());
      }
      expect(app.loadLibraries(), isEmpty);
    });

    test('読めなければ AppIssue。例外の toString もパスも出さない', () {
      app.db.execute('DROP TABLE library_systems');
      final issue = _issueFrom(app.loadLibraries);
      expect(issue.code, 'libraries-load');
      // 型名だけである。SQL 文も DB のパスも含めない。
      expect(
        issue.message,
        'Library systems could not be read (SqliteException).',
      );
      expect(issue.message, isNot(contains(home.path)));
      expect(issue.message, isNot(contains('SELECT')));
    });

    test('常用館は未設定・解決済み・参照切れの3つに分かれる', () {
      final koto = app.librarySystems.read(_koto)!;
      expect(
        app.preferredBranchFor(_koto),
        PreferredBranch.resolved(
          koto.branches.first.id,
          koto.branches.first.name,
        ),
      );
      expect(app.preferredBranchFor(_sumida), const PreferredBranch.unset());

      // **分館が1件消えた端末からの適用**を再登録（スナップショット）で作る。
      app.librarySystems.register(
        system: koto.copyWith(branches: [koto.branches.last]),
        now: nowUtc(),
      );
      expect(
        app.preferredBranchFor(_koto),
        PreferredBranch.dangling(koto.branches.first.id),
      );
      expect(app.preferredBranchFor(_koto).branchName, isNull);
    });

    test('参照切れの口は systemId で絞る。doctor の全件とは用途が違う', () {
      final koto = app.librarySystems.read(_koto)!;
      app.librarySystems.register(
        system: koto.copyWith(branches: [koto.branches.last]),
        now: nowUtc(),
      );
      expect(
        LibrarySettings(app.domain).danglingPreferredBranches().length,
        1,
        reason: '診断の側は全件を返す',
      );
      expect(
        app.preferredBranchFor('Tokyo_Minato').state,
        PreferredBranchState.resolved,
        reason: '他のシステムは巻き込まない',
      );
    });

    test('削除で残るものを数える', () {
      final impact = app.removalImpactFor(_koto);
      expect(impact.memberships, 1);
      expect(impact.loans, app.librarySystems.referencingLoans(_koto));
      expect(impact.loans, greaterThan(0));
      expect(impact.hasPreferredBranch, isTrue);
      expect(impact.hasMypageUrl, isTrue);

      // **既定値表は台帳の行ではない。** 消えるのは利用者が保存した値だけである。
      final sumida = app.removalImpactFor(_sumida);
      expect(sumida.hasPreferredBranch, isFalse);
      expect(sumida.hasMypageUrl, isFalse);
      expect(app.mypageUrlFor(_sumida).source, MypageUrlSource.bundled);
    });

    test('マイページも読めなければ AppIssue。未設定へ潰さない', () {
      app.db.execute('DROP TABLE library_settings');
      expect(
        _issueFrom(() => app.mypageUrlFor(_koto)).code,
        'library-setting-load',
      );
      expect(
        _issueFrom(() => app.preferredBranchFor(_koto)).code,
        'library-setting-load',
      );
    });
  });

  group('書く', () {
    test('常用館を保存・解除する。業務の口は2本のままである', () async {
      final branch = app.librarySystems.read(_sumida)!.branches.last;
      await app.savePreferredBranch(_sumida, branch.id);
      expect(app.preferredBranchFor(_sumida).branchId, branch.id);

      await app.clearPreferredBranch(_sumida);
      expect(app.preferredBranchFor(_sumida).state, PreferredBranchState.unset);
    });

    test('業務の失敗はコードとメッセージのまま渡る', () async {
      final issue = await _asyncIssueFrom(
        () => app.savePreferredBranch(_koto, 'calil:not-a-branch'),
      );
      // **`code` は言語間で共有する契約の文字列である**（`errors.dart`）。
      expect(issue.code, 'library-setting');
      expect(issue.message, contains('分館にありません'));

      expect(
        (await _asyncIssueFrom(
          () => app.removeLibrarySystem('Tokyo_Nerima'),
        )).code,
        'library-system-missing',
      );
    });

    test('削除は tombstone として立ち、参照は残る', () async {
      final loans = app.removalImpactFor(_koto).loans;
      await app.removeLibrarySystem(_koto);
      expect(app.loadLibraries().any((system) => system.id == _koto), isFalse);
      // **残骸は許容する。** 台帳は既に耐えている。
      expect(app.librarySystems.referencingLoans(_koto), loans);
      expect(app.librarySystems.referencingMemberships(_koto), 1);
    });

    test('業務以外の失敗は型名だけにする', () async {
      app.db.execute('DROP TABLE library_settings');
      final issue = await _asyncIssueFrom(
        () => app.savePreferredBranch(
          _koto,
          app.librarySystems.read(_koto)!.branches.first.id,
        ),
      );
      expect(issue.code, 'library-write');
      expect(issue.message, 'The change could not be saved (SqliteException).');
    });

    test('閉じたセッションへ書かない', () async {
      app.close();
      expect(
        (await _asyncIssueFrom(() => app.removeLibrarySystem(_koto))).code,
        'session-closed',
      );
    });
  });

  group('候補から台帳へ', () {
    LibrarySystemCandidate candidate({
      String systemId = 'Tokyo_Chiyoda',
      String systemName = '東京都千代田区',
      String city = '千代田区',
      String? homepageUrl = 'https://www.library.chiyoda.tokyo.jp/',
      List<BranchCandidate> branches = const [
        BranchCandidate(id: 'calil:1', libkey: '四番町', name: '千代田区立四番町図書館'),
      ],
    }) => LibrarySystemCandidate(
      systemId: systemId,
      systemName: systemName,
      pref: '東京都',
      city: city,
      branches: branches,
      homepageUrl: homepageUrl,
    );

    test('分館の id は calil:<libid>、libkey は外部キーとしてだけ入る', () {
      final system = librarySystemOf(candidate());
      expect(system.id, 'Tokyo_Chiyoda');
      // **カーリルの systemname をそのまま採る**（2026-09-16 決定）。
      expect(system.name, '東京都千代田区');
      expect(system.branches.single.id, 'calil:1');
      expect(system.branches.single.calilLibkey, '四番町');
      // カーリルは検索テンプレートを返さない。**利用者が手で入れる値である。**
      expect(system.opacSearchUrlTemplate, isNull);
    });

    test('登録すると一覧に出る', () async {
      await app.registerLibrary(candidate());
      final registered = app.loadLibraries().where(
        (s) => s.id == 'Tokyo_Chiyoda',
      );
      expect(registered, hasLength(1));
      expect(registered.single.branches, hasLength(1));
    });

    test('分館が0件・市区町村が空の候補は登録できない', () async {
      expect(
        (await _asyncIssueFrom(
          () => app.registerLibrary(candidate(branches: const [])),
        )).code,
        'library-system',
      );
      expect(
        (await _asyncIssueFrom(
          () => app.registerLibrary(candidate(city: '  ')),
        )).code,
        'library-system',
      );
      expect(app.loadLibraries().any((s) => s.id == 'Tokyo_Chiyoda'), isFalse);
    });

    test('手で直した homepageUrl を候補で上書きしない', () {
      final current = LibrarySystems(app.domain).load();
      final prepared = prepareCandidate(
        LibrariesConfig([
          ...current.librarySystems,
          librarySystemOf(candidate()).copyWith(homepageUrl: 'https://手で直した/'),
        ]),
        candidate(homepageUrl: 'https://カーリル由来/'),
      );
      expect(prepared!.homepageUrl, 'https://手で直した/');
    });
  });

  group('取り直し（差分があるときだけ書く）', () {
    /// いまの台帳の1件から、同じ内容の候補を組む。**これを渡せば差分は出ない。**
    LibrarySystemCandidate sameAs(LibrarySystem system) =>
        LibrarySystemCandidate(
          systemId: system.id,
          systemName: system.name,
          pref: system.pref,
          city: system.city,
          homepageUrl: system.homepageUrl,
          branches: [
            for (final branch in system.branches)
              BranchCandidate(
                id: branch.id,
                libkey: branch.calilLibkey,
                name: branch.name,
              ),
          ],
        );

    int envelopes() =>
        app.db.select('SELECT COUNT(*) AS n FROM outbox_events').first['n']
            as int;

    test('同じなら1通も積まない', () async {
      var runs = 0;
      final local = withRefresh(
        RefreshLoop(
          ready: () => true,
          enabled: true,
          interval: const Duration(minutes: 5),
          run: (_) async {
            runs++;
          },
        ),
      );
      final before = envelopes();
      final version = app.librarySystems.aggregateVersion(_koto);
      final updated = await local.refreshRegisteredFrom([
        for (final system in app.loadLibraries()) sameAs(system),
      ]);
      expect(updated, 0);
      expect(runs, 0, reason: '変更がなければ同期を開始しない');
      expect(envelopes(), before, reason: '同期に乗る書込みを増やさない');
      expect(app.librarySystems.aggregateVersion(_koto), version);
    });

    test('分館が増えていたら書き直す。**違うものだけ**', () async {
      final koto = app.librarySystems.read(_koto)!;
      final others = app.loadLibraries().where((s) => s.id != _koto);
      final grown = sameAs(koto);
      final updated = await app.refreshRegisteredFrom([
        LibrarySystemCandidate(
          systemId: grown.systemId,
          systemName: grown.systemName,
          pref: grown.pref,
          city: grown.city,
          homepageUrl: grown.homepageUrl,
          branches: [
            ...grown.branches,
            const BranchCandidate(
              id: 'calil:new',
              libkey: '新館',
              name: '江東区立新館',
            ),
          ],
        ),
        for (final system in others) sameAs(system),
      ]);
      expect(updated, 1);
      expect(app.librarySystems.read(_koto)!.branches, hasLength(3));
      // 他の区は版が動かない。
      expect(app.librarySystems.read(_sumida)!.branches, hasLength(2));
    });

    test('登録していないシステムは触らない', () async {
      final before = app.loadLibraries().length;
      final updated = await app.refreshRegisteredFrom([
        LibrarySystemCandidate(
          systemId: 'Tokyo_NotRegistered',
          systemName: '東京都未登録区',
          pref: '東京都',
          city: '未登録区',
          branches: const [
            BranchCandidate(id: 'calil:9', libkey: 'x', name: '未登録図書館'),
          ],
        ),
      ]);
      expect(updated, 0);
      expect(app.loadLibraries(), hasLength(before));
    });

    test('常用館は洗い替えの対象ではない。分館が消えれば参照切れになる', () async {
      final koto = app.librarySystems.read(_koto)!;
      final kept = koto.branches.last;
      await app.refreshRegisteredFrom([
        LibrarySystemCandidate(
          systemId: koto.id,
          systemName: koto.name,
          pref: koto.pref,
          city: koto.city,
          homepageUrl: koto.homepageUrl,
          branches: [
            BranchCandidate(
              id: kept.id,
              libkey: kept.calilLibkey,
              name: kept.name,
            ),
          ],
        ),
      ]);
      // 設定の行は残り、参照先だけを失う（`0011`）。
      expect(
        app.preferredBranchFor(_koto).state,
        PreferredBranchState.dangling,
      );
      expect(app.preferredBranchFor(_koto).branchId, koto.branches.first.id);
    });

    test('マイページの取り込み値も残る', () async {
      final koto = app.librarySystems.read(_koto)!;
      await app.refreshRegisteredFrom([sameAs(koto)]);
      expect(app.mypageUrlFor(_koto).source, MypageUrlSource.imported);
    });
  });

  group('候補の取得', () {
    test('キーが空の端末では照会に行かない。**401 は起きない**', () async {
      // 試験のビルドに同梱値は入っていない（`--dart-define` が無い）。
      expect(app.calilKey.usable, isFalse);
      expect(
        (await _asyncIssueFrom(() => app.libraryCandidates('東京都'))).code,
        'calil-key-missing',
      );
    });
  });

  group('マイページ URL', () {
    Uri url(String value) => Uri.parse(value);

    test('保存すると出典が取り込み値になり、確認日が入る', () async {
      expect(app.mypageUrlFor(_sumida).source, MypageUrlSource.bundled);
      await app.saveMypageUrl(
        _sumida,
        url('https://www.library.sumida.tokyo.jp/idcheck'),
      );
      final saved = app.mypageUrlFor(_sumida);
      expect(saved.source, MypageUrlSource.imported);
      expect(saved.value, 'https://www.library.sumida.tokyo.jp/idcheck');
      // **利用者が取り込んだ日である**（既定値の採取日ではない）。
      expect(saved.checkedOn, nowUtc().split('T').first);
      expect(saved.checkedOn, isNot(app.mypageDefaults.checkedOn));
    });

    test('拒否する3つは書かない', () async {
      for (final rejected in const [
        'ftp://example.org/login',
        'https://user:pass@example.org/login',
        'https://example.org/login?jsessionid=abc',
        'https://example.org/idcheck;jsessionid=abc',
      ]) {
        final issue = await _asyncIssueFrom(
          () => app.saveMypageUrl(_sumida, url(rejected)),
        );
        expect(issue.code, 'mypage-url-rejected', reason: rejected);
      }
      expect(app.mypageUrlFor(_sumida).source, MypageUrlSource.bundled);
    });

    test('別ホストでも警告せず、保存を止めない', () {
      final check = app.checkMypageUrl(
        _sumida,
        url('https://opac.example.net/'),
      );
      expect(check.issues, isEmpty);
      expect(check.saveable, isTrue);
      // 比べた相手を渡す。**画面が両方のホストを並べられる。**
      expect(check.comparedTo!.host, contains('sumida'));
    });

    test('比較先がなくても警告しない', () {
      app.librarySystems.register(
        system: const LibrarySystem(
          id: 'Tokyo_Chuo',
          pref: '東京都',
          city: '中央区',
          name: '東京都中央区',
          branches: [
            Branch(id: 'calil:1', calilLibkey: '京橋', name: '中央区立京橋図書館'),
          ],
        ),
        now: nowUtc(),
      );
      final check = app.checkMypageUrl(
        'Tokyo_Chuo',
        url('https://example.org/login'),
      );
      expect(check.issues, isEmpty);
      expect(check.issues, isNot(contains(UrlSaveIssue.hostMismatch)));
      expect(check.comparedTo, isNull);
      expect(check.saveable, isTrue);
    });

    test('解除は「未設定」ではなく、既定値表へ戻る', () async {
      // 江東だけ取り込み値を持つ fixture である。
      expect(app.mypageUrlFor(_koto).source, MypageUrlSource.imported);
      await app.clearMypageUrl(_koto);
      expect(app.mypageUrlFor(_koto).source, MypageUrlSource.bundled);
    });

    test('比べる相手は既定値・公式サイトであって、取り込み値ではない', () async {
      // 取り込み値を別ホストにしても、比べる先は既定値のままである。
      await app.saveMypageUrl(_koto, url('https://opac.example.net/login'));
      final check = app.checkMypageUrl(
        _koto,
        url('https://www.koto-lib.tokyo.jp/x'),
      );
      expect(check.comparedTo!.host, 'www.koto-lib.tokyo.jp');
      expect(check.issues, isNot(contains(UrlSaveIssue.hostMismatch)));
    });

    test('保存したら起動情報を消費する。**保存しなければ残す**', () async {
      void remember() => app.handoff.remember(
        LaunchContext(
          purpose: LaunchPurpose.mypageUrl,
          systemId: _sumida,
          host: 'www.library.sumida.tokyo.jp',
          startedAt: DateTime.now(),
        ),
      );

      // 拒否された値では消費しない。**受信画面を閉じただけ・拒否しただけでは消さない。**
      remember();
      await expectLater(
        app.saveMypageUrl(_sumida, url('https://x.example/?jsessionid=a')),
        throwsA(isA<AppIssue>()),
      );
      expect(app.handoff.launch, isNotNull);

      await app.saveMypageUrl(
        _sumida,
        url('https://www.library.sumida.tokyo.jp/idcheck'),
      );
      expect(app.handoff.launch, isNull);
    });

    test('開く先が無ければ開かない。起動情報も置かない', () async {
      app.librarySystems.register(
        system: const LibrarySystem(
          id: 'Tokyo_Chuo',
          pref: '東京都',
          city: '中央区',
          name: '東京都中央区',
          branches: [
            Branch(id: 'calil:1', calilLibkey: '京橋', name: '中央区立京橋図書館'),
          ],
        ),
        now: nowUtc(),
      );
      // **ブラウザーを開く試験はしない**（実物が起動してしまう）。ここで測るのは、
      // 開く前に止まる枝である。
      expect(
        (await _asyncIssueFrom(() => app.openLibrarySite('Tokyo_Chuo'))).code,
        'mypage-url-unset',
      );
      expect(app.handoff.launch, isNull);
    });
  });

  group('受信を用途で絞る', () {
    LaunchContext launch(LaunchPurpose purpose) => LaunchContext(
      purpose: purpose,
      systemId: _koto,
      host: 'www.koto-lib.tokyo.jp',
      startedAt: DateTime.utc(2026, 9, 18, 1, 2, 3),
    );

    final webUrl = parseHandoff('https://www.koto-lib.tokyo.jp/login');
    final book = parseHandoff('https://calil.jp/book/427421933X');
    final notice = parseHandoff('複数 https://a.example/ https://b.example/');

    test('マイページの用途で開いた後の Web URL だけが候補になる', () {
      final candidate = mypageCandidateOf(
        webUrl,
        launch(LaunchPurpose.mypageUrl),
      )!;
      expect(candidate.systemId, _koto);
      expect(candidate.url.host, 'www.koto-lib.tokyo.jp');
      // **古さを画面に出すために運ぶ**（一時保持に期限は置かない）。
      expect(candidate.startedAt, DateTime.utc(2026, 9, 18, 1, 2, 3));
    });

    test('候補にしないのは4つ。**捨ててよいという意味ではない**', () {
      expect(webUrl, isA<HandoffWebUrl>());
      expect(book, isA<HandoffBook>());
      expect(notice, isA<HandoffNotice>());

      // 貸出しの用途で開いた → この画面の候補ではない。
      expect(mypageCandidateOf(webUrl, launch(LaunchPurpose.lending)), isNull);
      // 起動情報が無い → 用途が決まらない。
      expect(mypageCandidateOf(webUrl, null), isNull);
      // 書籍は予約（段階2）、Notice は別タスクの Activity である。
      expect(mypageCandidateOf(book, launch(LaunchPurpose.mypageUrl)), isNull);
      expect(
        mypageCandidateOf(notice, launch(LaunchPurpose.mypageUrl)),
        isNull,
      );
    });
  });

  group('受信を用途で絞る（貸出し）', () {
    LaunchContext launch(LaunchPurpose purpose) => LaunchContext(
      purpose: purpose,
      systemId: _koto,
      host: 'www.koto-lib.tokyo.jp',
      startedAt: DateTime.utc(2026, 9, 18, 1, 2, 3),
    );

    final webUrl = parseHandoff('https://www.koto-lib.tokyo.jp/login');
    final book = parseHandoff('https://calil.jp/book/427421933X');
    final notice = parseHandoff('複数 https://a.example/ https://b.example/');

    test('貸出しの用途で開いた後の Web URL だけが候補になる', () {
      final candidate = lendingCandidateOf(
        webUrl,
        launch(LaunchPurpose.lending),
      )!;
      expect(candidate.systemId, _koto);
      // **古さを画面に出すために運ぶ**（一時保持に期限は置かない）。
      expect(candidate.startedAt, DateTime.utc(2026, 9, 18, 1, 2, 3));
    });

    test('候補にしないのは4つ。**捨ててよいという意味ではない**', () {
      expect(webUrl, isA<HandoffWebUrl>());
      expect(book, isA<HandoffBook>());
      expect(notice, isA<HandoffNotice>());

      // マイページの用途で開いた → この画面の候補ではない。
      expect(
        lendingCandidateOf(webUrl, launch(LaunchPurpose.mypageUrl)),
        isNull,
      );
      // 起動情報が無い → 用途が決まらない。
      expect(lendingCandidateOf(webUrl, null), isNull);
      // 書籍は予約（段階2）、Notice は別タスクの Activity である。
      expect(lendingCandidateOf(book, launch(LaunchPurpose.lending)), isNull);
      expect(
        lendingCandidateOf(notice, launch(LaunchPurpose.lending)),
        isNull,
      );
    });
  });
}

AppIssue _issueFrom(void Function() body) {
  try {
    body();
  } on AppIssue catch (issue) {
    return issue;
  }
  fail('AppIssue が投げられなかった');
}

Future<AppIssue> _asyncIssueFrom(Future<void> Function() body) async {
  try {
    await body();
  } on AppIssue catch (issue) {
    return issue;
  }
  fail('AppIssue が投げられなかった');
}
