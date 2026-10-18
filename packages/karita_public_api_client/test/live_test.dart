@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:test/test.dart';

/// 実物を叩く分。**無印の `dart test` では走らない**（`dart_test.yaml` が既定から外している）。
///
///     dart test -P live
///
/// **相手の中身は測らない。** 収録内容も貸出状況も日々変わるので、ここで見るのは
/// 「こちらの組み立てた要求に、相手が約束した形で答えるか」だけである。実 API が落ちていても
/// 通常の試験は緑のままでなければならない — だからこれを既定から外してある。
///
/// **ただしこの回は、決めるために測る分を含む。** 2026-09-16 の初回確認
/// （記録（非公開資料））で継続取得の枝が
/// 踏めず、図書館追加を何段階にするか（都道府県のあとに市区町村を挟むか）も、
/// `/library` が都道府県まるごとを返せるかどうか次第で決まらなかった。
/// **その2つを1回の実行で取る**（→ 結果（非公開資料））。
///
/// 測った値は `[観測]` の行として標準出力へ出る。**`printOnFailure` にしない** — 落ちなくても
/// 読むために取っているからである。
void main() {
  group('OpenBD', () {
    test('実 API から書誌が読める', () async {
      final client = OpenBdClient();
      addTearDown(client.close);

      // 公開の ISBN。**書影が在るとは限らない** — そこは測らない。
      final result = await client.fetchBook('9784780802047');

      expect(result.outcome, isNot(OpenBdOutcome.failed),
          reason: '失敗の理由: ${result.failure}');
      if (result.outcome == OpenBdOutcome.found) {
        expect(result.record!.isbn13, '9784780802047');
        printOnFailure('title: ${result.record!.title}');
      }
    });

    test('未収録の ISBN が未収録として返る', () async {
      final client = OpenBdClient();
      addTearDown(client.close);

      // 形は正しく、実在しない ISBN。
      final result = await client.fetchBook('9784000000017');

      expect(result.outcome, isNot(OpenBdOutcome.failed),
          reason: '失敗の理由: ${result.failure}');
    });
  });

  group('カーリル /library', () {
    final appkey = _calilAppkey();
    final skip = appkey.isEmpty ? 'KARITA_CALIL_APPKEY が無い' : null;

    test('`pref` ＋ `city` が JSON で返る。**3段目の形である**', () async {
      final client = CalilLibraryClient(appkey: appkey);
      addTearDown(client.close);

      final result = await client.listByPref('東京都', city: '江東区', limit: 50);

      expect(result.failure, isNull, reason: '失敗の理由: ${result.failure}');
      expect(result.systems, isNotEmpty);
      expect(result.systems.first.branches, isNotEmpty);
      expect(result.rejectedSystemIds, isEmpty,
          reason: 'systemid に `/` を含む館が実在した場合はここで気づく');

      _report('pref+city 東京都/江東区: ${result.systems.length}システム / '
          '${_branchCount(result)}分館 / 切り詰め=${result.truncated}');

      // **`city` が空の行が在るか。** `prepareRegistration` は pref と city の両方を必須に
      // しており、空のまま渡すと登録が `DomainError` で止まる。埋める規則を作る必要があるか
      // どうかは「実際に空が来るか」で決まる。
      final blank = result.systems.where((s) => s.city.isEmpty).toList();
      _report('city が空のシステム: ${blank.length}件'
          '${blank.isEmpty ? '' : ' → ${blank.map((s) => s.systemId).join(', ')}'}');
    }, skip: skip);

    test('`pref` だけで都道府県まるごとを引けるか。**図書館追加が何段階かが決まる**', () async {
      final client = CalilLibraryClient(appkey: appkey);
      addTearDown(client.close);

      // **東京都を選ぶ。** 都道府県のうち行がいちばん多い（2026-09-16 の実測で 850行。
      // 次が北海道の 425行で、他は 400行前後）。
      //
      // **旧既定の 500 では足りなかった。** その値を残して測り続けるのは、「上げたのは
      // 余裕を見たからではなく、足りなかったからである」を試験の側に置いておくためである。
      const wasDefault = 500;
      final atOld = await client.listByPref('東京都', limit: wasDefault);
      expect(atOld.failure, isNull, reason: '失敗の理由: ${atOld.failure}');
      _report('pref のみ 東京都 limit=$wasDefault（旧既定）: '
          '${atOld.systems.length}システム / ${_branchCount(atOld)}分館 / '
          '切り詰め=${atOld.truncated}');

      // **いまの既定なら全部取れるか。** 取れないなら都道府県まるごとは引けず、
      // 都道府県とシステムの間に市区町村を挟んで引き直すしかなくなる。
      final raised = await client.listByPref('東京都', limit: defaultLibraryLimit);
      expect(raised.failure, isNull, reason: '失敗の理由: ${raised.failure}');
      _report('pref のみ 東京都 limit=$defaultLibraryLimit（既定）: '
          '${raised.systems.length}システム / ${_branchCount(raised)}分館 / '
          '切り詰め=${raised.truncated}');
      expect(raised.truncated, isFalse,
          reason: '既定の limit で都道府県まるごとが取れなくなった。'
              '都道府県を選んで1回引けば足りる、という前提が崩れる');

      // **応答の大きさを測る。** `defaultMaxCalilResponseBytes` は 4MiB で、超えたら読むのを
      // やめる造りである。都道府県まるごとを1回で引く設計にする以上、いちばん大きい応答が
      // その上限に収まることを確かめておく。
      final raw = await http.get(calilApiBase.replace(
        path: '${calilApiBase.path}/library',
        queryParameters: {
          'appkey': appkey,
          'pref': '東京都',
          'limit': '$defaultLibraryLimit',
          'format': 'json',
          'callback': '',
        },
      ));
      _report('東京都 limit=$defaultLibraryLimit の応答: ${raw.bodyBytes.length} バイト '
          '（上限 $defaultMaxCalilResponseBytes）');
      expect(raw.bodyBytes.length, lessThan(defaultMaxCalilResponseBytes));

      // **表示順を決める材料。** 語がシステム本体（`systemname` / `city`）に当たったのか、
      // 分館の名前・住所にだけ当たったのかで、順位付けの規則が変わる。
      //
      // **市区町村で絞るより広い**ことも、ここで見える。本体に当たらず分館にだけ当たる行は、
      // 市区町村を選ばせる形にすると候補から落ちる。
      const needle = '江東区';
      final hits = filterSystems(raised.systems, needle);
      _report('「$needle」での絞込み: ${hits.length}件 / 全 ${raised.systems.length}件');
      for (final system in hits) {
        _report('  ${system.systemId}(city=${system.city}) '
            '${_matchedInBody(system, needle) ? '本体に一致' : '**分館にだけ一致**'}');
      }

      _report(raised.truncated
          ? '判定: 都道府県まるごとは取れない。**市区町村を挟んで引き直す形になる**'
          : '判定: 都道府県まるごとが取れた。**都道府県→システムの2段階で足りる**');
    }, timeout: const Timeout(Duration(minutes: 2)), skip: skip);

    test('**`category` に何が来るか。** 自治体を上へ置く規則を何で判定するかが決まる',
        () async {
      // **生の応答を読む。** `LibrarySystemCandidate` は `category` を持っていない。
      // 持たせるかどうかを決めるための測定なので、モデルを変える前に中身を見る。
      final raw = await http.get(calilApiBase.replace(
        path: '${calilApiBase.path}/library',
        queryParameters: {
          'appkey': appkey,
          'pref': '東京都',
          'limit': '$defaultLibraryLimit',
          'format': 'json',
          'callback': '',
        },
      ));
      expect(raw.statusCode, 200);
      final rows = (jsonDecode(utf8.decode(raw.bodyBytes)) as List)
          .cast<Map<String, Object?>>();

      // systemid ごとに category を集める。**1システムで割れるかどうかも見る。**
      final bySystem = <String, Set<String>>{};
      for (final row in rows) {
        final systemId = row['systemid'] as String?;
        if (systemId == null) continue;
        bySystem
            .putIfAbsent(systemId, () => <String>{})
            .add((row['category'] as String?) ?? '(無し)');
      }

      final tally = <String, int>{};
      for (final categories in bySystem.values) {
        for (final category in categories) {
          tally[category] = (tally[category] ?? 0) + 1;
        }
      }
      final sorted = tally.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _report('systemid ごとの category: '
          '${sorted.map((e) => '${e.key}=${e.value}').join(' ')}');

      final split = bySystem.entries.where((e) => e.value.length > 1).toList();
      _report('1システムで category が割れたもの: ${split.length}件'
          '${split.isEmpty ? '' : ' → ${split.take(3).map((e) => '${e.key}${e.value}').join(', ')}'}');

      // **`systemid` の接頭辞でも判定できるか。** できるなら `category` を持たずに済む。
      final prefixed = bySystem.keys.where((id) => id.startsWith('Tokyo_'));
      final categoriesOfPrefixed = <String>{
        for (final id in prefixed) ...bySystem[id]!,
      };
      _report('`Tokyo_` 接頭辞のシステム: ${prefixed.length}件 / '
          'その category: ${categoriesOfPrefixed.join(', ')}');

      // **規則の候補を測る。** `category` は館ごとで、1システムの中で割れる（上の観測）。
      // だから「このシステムは何か」は1行では決まらない。**全部の行が UNIV か SPECIAL
      // なら大学・専門である**、という束ね方なら決まるはずである。
      bool onlyAcademic(Set<String> categories) =>
          categories.isNotEmpty &&
          categories.every((c) => c == 'UNIV' || c == 'SPECIAL');

      final academic =
          bySystem.entries.where((e) => onlyAcademic(e.value)).toList();
      final public =
          bySystem.entries.where((e) => !onlyAcademic(e.value)).toList();
      _report('規則「全行が UNIV か SPECIAL」: 大学・専門=${academic.length} / '
          '公共=${public.length}');

      // **`Tokyo_` 接頭辞がどちらへ落ちるか。** 接頭辞は命名規約であって契約ではないので、
      // 規則の側がそれと一致するなら接頭辞を見ずに済む。
      final misplaced =
          academic.where((e) => e.key.startsWith('Tokyo_')).toList();
      _report('自治体の接頭辞なのに大学・専門へ落ちたもの: ${misplaced.length}件'
          '${misplaced.isEmpty ? '' : ' → ${misplaced.map((e) => '${e.key}${e.value}').join(', ')}'}');

      final publicNonPrefixed =
          public.where((e) => !e.key.startsWith('Tokyo_')).toList();
      _report('公共だが接頭辞が違うもの: ${publicNonPrefixed.length}件'
          '${publicNonPrefixed.isEmpty ? '' : ' → ${publicNonPrefixed.take(5).map((e) => e.key).join(', ')}'}');
      for (final entry in sorted) {
        final ids = bySystem.entries
            .where((e) => e.value.contains(entry.key))
            .map((e) => e.key)
            .take(3);
        _report('  ${entry.key}: ${ids.join(', ')}');
      }
    }, timeout: const Timeout(Duration(minutes: 2)), skip: skip);

    test('**同じ要求を2回出すと同じ並びで返るか。** 差分で書き戻す形が成立するかが決まる',
        () async {
      final client = CalilLibraryClient(appkey: appkey);
      addTearDown(client.close);

      // **登録済みの図書館を取り直して、違っていたら台帳を更新する**という形を採るなら、
      // 「違っている」の判定が安定していなければならない。`LibrarySystem` の等価性は
      // **分館の並びまで見る**ので、応答順が呼ぶたびに変わると、中身が同じでも毎回
      // 「違う」と判定して封筒を積むことになる（同期に乗る書込みである）。
      //
      // **2回続けて叩くだけでは日をまたいだ安定性は分からない。** ここで分かるのは
      // 「同じ要求に対して並びが揺れるかどうか」だけである。
      final first = await client.listByPref('東京都', limit: defaultLibraryLimit);
      final second = await client.listByPref('東京都', limit: defaultLibraryLimit);
      expect(first.failure, isNull, reason: '失敗の理由: ${first.failure}');
      expect(second.failure, isNull, reason: '失敗の理由: ${second.failure}');

      List<String> branchIds(LibrarySystemCandidate system) =>
          [for (final branch in system.branches) branch.id];

      final before = {
        for (final system in first.systems) system.systemId: system,
      };
      final after = {
        for (final system in second.systems) system.systemId: system,
      };

      _report('システムの数: ${before.length} → ${after.length}');
      _report('システムの並び: '
          '${_sameList(before.keys.toList(), after.keys.toList()) ? '同じ' : '**変わった**'}');

      final orderChanged = <String>[];
      final setChanged = <String>[];
      for (final entry in before.entries) {
        final other = after[entry.key];
        if (other == null) {
          setChanged.add(entry.key);
          continue;
        }
        final a = branchIds(entry.value);
        final b = branchIds(other);
        if (_sameList(a, b)) continue;
        if (a.toSet().difference(b.toSet()).isEmpty &&
            b.toSet().difference(a.toSet()).isEmpty) {
          orderChanged.add(entry.key);
        } else {
          setChanged.add(entry.key);
        }
      }

      _report('分館の並びだけが変わったシステム: ${orderChanged.length}件'
          '${orderChanged.isEmpty ? '' : ' → ${orderChanged.take(5).join(', ')}'}');
      _report('分館の顔ぶれが変わったシステム: ${setChanged.length}件'
          '${setChanged.isEmpty ? '' : ' → ${setChanged.take(5).join(', ')}'}');

      _report(orderChanged.isEmpty && setChanged.isEmpty
          ? '判定: 2回とも同じ。**並びまで見る等価性で差分を判定してよい**'
          : '判定: 揺れた。**差分の判定は並びを正規化してから行う**');
    }, timeout: const Timeout(Duration(minutes: 2)), skip: skip);

    test('**1システムの分館は何件あるか。** 常用館の選択リストに絞込みが要るかが決まる',
        () async {
      final client = CalilLibraryClient(appkey: appkey);
      addTearDown(client.close);

      // **都道府県まるごとの1回で足りる。** 分館は同じ応答の行として返っているので、
      // 数えるために別の要求を足さない。
      final result = await client.listByPref('東京都', limit: defaultLibraryLimit);
      expect(result.failure, isNull, reason: '失敗の理由: ${result.failure}');
      expect(result.truncated, isFalse);

      int countOf(LibrarySystemCandidate system) => system.branches.length;

      void describe(String label, List<LibrarySystemCandidate> systems) {
        if (systems.isEmpty) {
          _report('$label: 0件');
          return;
        }
        final counts = [for (final system in systems) countOf(system)]..sort();
        final median = counts[counts.length ~/ 2];
        _report('$label: ${systems.length}システム / '
            '分館 最小${counts.first} 中央値$median 最大${counts.last} / '
            '10件以上=${counts.where((n) => n >= 10).length} '
            '20件以上=${counts.where((n) => n >= 20).length}');
      }

      describe('東京都の全システム', result.systems);

      // **利用者が登録するのは自治体の図書館である。** カーリルの `systemid` は自治体系が
      // `Tokyo_<市区町村>`、大学が `Univ_*`、専門・美術館が `Special_*` である。
      // 大学の1館だけのシステムを混ぜて中央値を出しても、常用館の選択リストの話にならない。
      final municipal = [
        for (final system in result.systems)
          if (system.systemId.startsWith('Tokyo_')) system,
      ];
      describe('自治体（Tokyo_*）', municipal);

      final ranked = [...municipal]
        ..sort((a, b) => countOf(b).compareTo(countOf(a)));
      for (final system in ranked.take(5)) {
        _report('  最多 ${system.systemId}(${system.systemName}): '
            '${countOf(system)}分館');
      }

      // デモ fixture の5区。**手元で見ている画面の実寸である。**
      for (final id in const [
        'Tokyo_Koto',
        'Tokyo_Sumida',
        'Tokyo_Minato',
        'Tokyo_Katsushika',
        'Tokyo_Edogawa',
      ]) {
        final system =
            result.systems.where((s) => s.systemId == id).firstOrNull;
        _report('  デモの区 $id: '
            '${system == null ? '応答に無い' : '${countOf(system)}分館'}');
      }
    }, timeout: const Timeout(Duration(minutes: 2)), skip: skip);

    test('**カーリルが appkey を検証しているか。** 検証を始めたらここで気づく', () async {
      // **実在しないキーである。** 隠す値ではないので、そのまま書ける。
      const bogus = 'karita-live-test-not-a-real-appkey';

      // 2026-09-16 の観測では、`/library` も `/check` も**不正なキーで 200 と正しい結果を
      // 返した。** つまり 401・403 は起きず、「キーが失効した」「打ち間違えた」という失敗は
      // 表に出てこない。出るのは「キーが空で照会に行かない」だけである。
      //
      // **だからといってキーを送らなくてよいのではない。** 検証していないのは相手の実装の
      // 都合であって、利用条件は appkey を求めているし、上限はキー／IP 単位で掛かる。
      // ここが測るのは**こちらの設計が前提にしてよい相手の性質**であり、
      // この試験が落ちたときは「カーリルが検証を始めた」であって、
      // `ApiFailure.unauthorized` の経路を実際に使う番が来たということである。
      final libraryRaw = await http.get(calilApiBase.replace(
        path: '${calilApiBase.path}/library',
        queryParameters: {
          'appkey': bogus,
          'pref': '東京都',
          'city': '江東区',
          'limit': '5',
          'format': 'json',
          'callback': '',
        },
      ));
      _report('不正キー /library: status=${libraryRaw.statusCode} '
          '${_head(_flatten(libraryRaw.bodyBytes), 120)}');

      final checkRaw = await http.get(calilApiBase.replace(
        path: '${calilApiBase.path}/check',
        queryParameters: {
          'appkey': bogus,
          'isbn': '9784780802047',
          'systemid': 'Tokyo_Koto',
          'format': 'json',
          'callback': 'no',
        },
      ));
      _report('不正キー /check: status=${checkRaw.statusCode} '
          '${_head(_flatten(checkRaw.bodyBytes), 120)}');

      final client = CalilLibraryClient(appkey: bogus);
      addTearDown(client.close);
      final result = await client.listByPref('東京都', city: '江東区', limit: 5);
      _report('不正キーでクライアントが返したもの: '
          'failure=${result.failure?.name ?? '-'} / ${result.systems.length}システム');

      expect(libraryRaw.statusCode, 200,
          reason: 'カーリルが /library で appkey を検証し始めた。'
              'unauthorized の経路と再設定の導線を設計すること');
      expect(checkRaw.statusCode, 200,
          reason: 'カーリルが /check で appkey を検証し始めた。'
              'unauthorized の経路と再設定の導線を設計すること');
    }, skip: skip);
  });

  group('カーリル /check', () {
    final appkey = _calilAppkey();
    final skip = appkey.isEmpty ? 'KARITA_CALIL_APPKEY が無い' : null;

    test('継続取得を実物で踏み、**確定済みが消えないことを見る**', () async {
      final client = CalilCheckClient(appkey: appkey);
      addTearDown(client.close);

      final snapshots = <HoldingsSnapshot>[];
      await for (final snapshot
          in client.check(isbn13s: _checkIsbns, systemIds: _checkSystems)) {
        snapshots.add(snapshot);
        _report('check #${snapshots.length} complete=${snapshot.complete} '
            'failure=${snapshot.failure?.name ?? '-'} ${_summarize(snapshot)}');
      }

      expect(snapshots, isNotEmpty);

      // **踏めなくても落とさない。** 相手に結果が残っていれば1回で終わるのは正常であり、
      // こちらの組み立ての誤りではない。踏めたかどうかを記録するだけにする。
      _report(snapshots.length > 1
          ? '継続取得を踏んだ（応答 ${snapshots.length} 回）'
          : '継続取得は踏めなかった（1回で完了）。相手に結果が残っていた');

      // **ここが本命である。** `CalilCheckClient` は継続応答で `byIsbn` を丸ごと置き換える
      // （`calil_check.dart` の `byIsbn = parsed.byIsbn`）。カーリルが継続応答へ「まだ走って
      // いる館だけ」を載せる仕様なら、**先に確定した館の答えがそこで消える。** 偽サーバは
      // 同じ仮定で書いてあるので捕まえられない — 実物でしか測れない枝である。
      for (var i = 1; i < snapshots.length; i++) {
        final settledBefore = _keys(snapshots[i - 1], settledOnly: true);
        final presentNow = _keys(snapshots[i], settledOnly: false);
        expect(presentNow, containsAll(settledBefore),
            reason: '応答 #${i + 1} で確定済みの館が落ちた。継続応答が差分なら、'
                'byIsbn の置き換えを累積へ直すこと');
      }

      // **知らない status が来ていないか。** 来ても畳まない造りだが、記録は残す。
      final statuses = <String>{
        for (final holdings in snapshots.last.byIsbn.values)
          for (final holding in holdings) holding.status,
      };
      _report('観測した status: ${(statuses.toList()..sort()).join(', ')}');

      // **頼んだ組が全部返るとは限らない。** 返らなかった組は「蔵書なし」ではなく**未照会**で
      // あり、画面が「この館には無い」と言ってよい根拠にならない。何組欠けるかを記録する。
      final asked = <String>{
        for (final isbn in _checkIsbns)
          for (final systemId in _checkSystems) '$isbn/$systemId',
      };
      final answered = _keys(snapshots.last, settledOnly: false);
      final missing = asked.difference(answered);
      _report('頼んだ組 ${asked.length} / 返った組 ${answered.length} / '
          '応答に現れない組 ${missing.length}'
          '${missing.isEmpty ? '' : ' → ${missing.take(6).join(', ')}'}');
    },
        // 全体の期限が 60 秒、間隔が 2 秒。既定の 30 秒では打ち切りへ届く前に試験が落ちる。
        timeout: const Timeout(Duration(minutes: 3)),
        skip: skip);
  });
}

/// 継続取得を誘うための組。**ISBN数 × systemid数 が書籍リクエストの勘定である**
/// （3 × 8 = 24 で、目安の 50 に収まる）。
///
/// systemid は 2026-09-16 に `/library?pref=東京都&city=江東区` が実際に返した8件である。
/// **6件が大学図書館なのを逆手に取る** — 公共より照会が薄いぶん、カーリル側に結果が残って
/// いない見込みが高い。`Cache` で返ってしまうと継続の枝へ入らない。
const List<String> _checkSystems = [
  'Tokyo_Koto',
  'Special_Mot',
  'Univ_Ariake',
  'Univ_Kaiyodai',
  'Univ_Musashino',
  'Univ_Shibaura_It',
  'Univ_Tau',
  'Univ_Tpu',
];

/// 1件目は 2026-09-16 に `Cache` で返った ISBN。**確定済みの行を1つ確実に作るために入れる**
/// — それが継続応答で消えるかどうかが、この試験の測りたいことである。
/// 残り2件は技術書で、大学図書館へ聞き直しが行く見込みが高い。
const List<String> _checkIsbns = [
  '9784780802047',
  '9784274069321',
  '9784274226298',
];

/// 語がシステム本体（`systemid` / `systemname` / `pref` / `city`）に当たったか。
///
/// **当たらないなら、分館の名前・libkey・住所のどれかに当たっている** — そうでなければ
/// [filterSystems] を通っていない。順位付けはこの区別で決まる。
bool _matchedInBody(LibrarySystemCandidate system, String needle) =>
    _fold([system.systemId, system.systemName, system.pref, system.city].join(' '))
        .contains(_fold(needle));

/// [filterSystems] と同じ揃え方。**英字の大小と空白だけで、表記ゆれは推測しない。**
String _fold(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// 分館の総数。**返った行数とほぼ同じである**（`libid` を持つ行が1つの分館になる）。
int _branchCount(LibraryLookupResult result) =>
    result.systems.fold(0, (sum, system) => sum + system.branches.length);

/// `<isbn>/<systemid>` の集合。
Set<String> _keys(HoldingsSnapshot snapshot, {required bool settledOnly}) => {
      for (final entry in snapshot.byIsbn.entries)
        for (final holding in entry.value)
          if (!settledOnly || holding.isSettled)
            '${entry.key}/${holding.systemId}',
    };

/// 1回ぶんの中身を1行へ畳む。**館ごとの状態までは出さない** — 出すと行が長すぎて読めない。
String _summarize(HoldingsSnapshot snapshot) {
  var running = 0;
  var settled = 0;
  var error = 0;
  var other = 0;
  for (final holdings in snapshot.byIsbn.values) {
    for (final holding in holdings) {
      if (holding.isRunning) {
        running++;
      } else if (holding.isSettled) {
        settled++;
      } else if (holding.isError) {
        error++;
      } else {
        other++;
      }
    }
  }
  return 'settled=$settled running=$running error=$error other=$other';
}

String _head(String value, int limit) =>
    value.length <= limit ? value : '${value.substring(0, limit)}…';

/// 応答の本文を1行へ潰す。**`http` の `body` を使わない** — charset の申告が無いと latin1 で
/// 読まれて日本語が壊れる。
String _flatten(List<int> bodyBytes) =>
    utf8.decode(bodyBytes, allowMalformed: true).replaceAll(RegExp(r'\s+'), ' ');

/// 測った値を標準出力へ出す。**落ちなくても読む前提なので `printOnFailure` にしない。**
void _report(String line) => print('[観測] $line');

/// カーリルの appkey を探す。**環境変数が先、無ければリポジトリ直下の `.env`。**
///
/// `.env` はビルド入力の正本であって、実行中の環境変数ではない。本番は開発起動スクリプトが
/// そこから読んで `--dart-define` へ渡すが、**`dart test` はその経路を通らない。** 環境変数
/// だけを見ていると、`.env` にキーを書いた人が「入れたのに飛んだ」に遭う（実際に遭った）。
/// 読むのは試験だけで、製品のコードはこの経路を持たない。
///
/// **値をログにも失敗の文言にも出さない。**
String _calilAppkey() {
  final fromProcess = Platform.environment['KARITA_CALIL_APPKEY'] ?? '';
  if (fromProcess.isNotEmpty) return fromProcess;

  // 試験の作業ディレクトリはパッケージの根なので、2つ上がリポジトリの根である。
  final dotenv = File('../../.env');
  if (!dotenv.existsSync()) return '';
  for (final line in dotenv.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separator = trimmed.indexOf('=');
    if (separator <= 0) continue;
    if (trimmed.substring(0, separator).trim() != 'KARITA_CALIL_APPKEY') {
      continue;
    }
    // 値を囲む引用符は落とす。**中身は検めない** — 弾かれたら 401 で分かる。
    return trimmed
        .substring(separator + 1)
        .trim()
        .replaceAll(RegExp(r'''^["']|["']$'''), '');
  }
  return '';
}

/// 2つの並びが同じか。**順序まで見る。**
bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
