/// 直接 API のログ。**出してよい項目だけが出ることを、実際に流れた行で見る。**
///
/// 正本は `非公開資料:logging-and-diagnostics.md`。直接 API については
/// **「provider、操作種別、結果分類、HTTP status、所要時間、キャッシュ有無、要求件数で
/// 診断する」**と書かれており、**書名・著者・ISBN も渡さない。**
///
/// **URL を出さないことがいちばん効く。** カーリルの URL は `appkey` をクエリに載せるので、
/// 1箇所でも出せばキーが漏れる。
library;

import 'dart:convert';

import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'fake_public_api_server.dart';

const String _appkey = 'secret-appkey-value';
const String _isbn = '9784780802047';

void main() {
  late FakePublicApiServer server;
  late List<LogRecord> records;

  setUp(() async {
    Logger.root.level = Level.ALL;
    records = [];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    addTearDown(() => Logger.root.level = Level.INFO);
    server = await FakePublicApiServer.start();
  });
  tearDown(() => server.close());

  List<String> events() => [for (final r in records) r.message];

  Map<Object?, Object?> fieldsOf(String event) {
    final record = records.lastWhere((r) => r.message == event);
    return record.object as Map<Object?, Object?>? ??
        record.error! as Map<Object?, Object?>;
  }

  /// 流れた行を丸ごと1本の文字列にする。**鍵も値も含めて見る。**
  String everything() => [
    for (final record in records) '${record.loggerName} ${record.message} '
        '${record.object ?? record.error}',
  ].join('\n');

  test('カーリル /library：provider・操作・status・件数が出る', () async {
    server.libraryBody = jsonEncode([
      {
        'libid': '1',
        'systemid': 'Tokyo_Koto',
        'systemname': '江東区',
        'formal': '江東区立豊洲図書館',
        'short': '豊洲',
        'libkey': '豊洲',
        'pref': '東京都',
        'city': '江東区',
        'url_pc': 'https://www.koto-lib.tokyo.jp/',
      },
    ]);
    final client =
        CalilLibraryClient(appkey: _appkey, apiBase: server.calilBase);
    addTearDown(client.close);

    await client.listByPref('東京都');

    final fetch = fieldsOf('api.fetch');
    expect(fetch['provider'], 'calil');
    expect(fetch['op'], 'library');
    expect(fetch['outcome'], 'ok');
    expect(fetch['status'], 200);
    expect(fetch['ms'], isA<int>());

    final listed = fieldsOf('calil.library.listed');
    expect(listed['systems'], 1);
    expect(listed['branches'], 1);
    expect(listed['truncated'], isFalse);
  });

  test('**appkey も URL も都道府県も館名も、1行も出ない**', () async {
    server.libraryBody = jsonEncode([
      {
        'libid': '1',
        'systemid': 'Tokyo_Koto',
        'systemname': '江東区',
        'formal': '江東区立豊洲図書館',
        'short': '豊洲',
        'libkey': '豊洲',
        'pref': '東京都',
        'city': '江東区',
        'url_pc': 'https://www.koto-lib.tokyo.jp/',
      },
    ]);
    final client =
        CalilLibraryClient(appkey: _appkey, apiBase: server.calilBase);
    addTearDown(client.close);
    await client.listByPref('東京都');

    expect(everything(), isNotEmpty);
    for (final forbidden in const [
      _appkey,
      'appkey',
      'http://',
      'https://',
      '東京都', // 利用者が選んだ値である
      '江東区立豊洲図書館',
      'Tokyo_Koto',
    ]) {
      expect(everything(), isNot(contains(forbidden)), reason: '$forbidden が出た');
    }
  });

  test('OpenBD：ISBN も書名も出さない。provider と操作だけ', () async {
    server.openBdBody = jsonEncode([
      {
        'summary': {
          'isbn': _isbn,
          'title': '秘密の書名',
          'author': '秘密の著者',
          'publisher': '出版社',
        },
      },
    ]);
    final client = OpenBdClient(apiBase: server.openBdBase);
    addTearDown(client.close);

    await client.fetchBook(_isbn);

    expect(fieldsOf('api.fetch')['provider'], 'openbd');
    expect(fieldsOf('api.fetch')['op'], 'book');
    expect(everything(), isNot(contains(_isbn)));
    expect(everything(), isNot(contains('秘密の書名')));
    expect(everything(), isNot(contains('秘密の著者')));
  });

  test('失敗は分類だけが WARNING で出る。本文も URL も出さない', () async {
    server.libraryStatus = 500;
    server.libraryBody = 'サーバの生の本文';
    final client =
        CalilLibraryClient(appkey: _appkey, apiBase: server.calilBase);
    addTearDown(client.close);

    final result = await client.listByPref('東京都');
    expect(result.failure, ApiFailure.server);

    // status の失敗は取得そのものが成功しているので `api.fetch` は `ok` である。
    // **分類は結果の行が出す。**
    expect(fieldsOf('calil.library.failed')['outcome'], 'server');
    expect(
      records.lastWhere((r) => r.message == 'calil.library.failed').level,
      Level.WARNING,
    );
    expect(everything(), isNot(contains('サーバの生の本文')));
  });

  test('通信できないときも分類だけが出る', () async {
    final client = CalilLibraryClient(
      appkey: _appkey,
      // 誰も待っていない port。**接続そのものが失敗する。**
      apiBase: Uri.parse('http://127.0.0.1:1'),
    );
    addTearDown(client.close);

    final result = await client.listByPref('東京都');
    expect(result.failure, ApiFailure.network);
    expect(fieldsOf('api.fetch')['outcome'], 'network');
    expect(events(), contains('calil.library.failed'));
    expect(everything(), isNot(contains('127.0.0.1')));
  });

  test('ログを出しても取得の結果は変わらない', () async {
    server.libraryBody = '[]';
    final client =
        CalilLibraryClient(appkey: _appkey, apiBase: server.calilBase);
    addTearDown(client.close);

    final result = await client.listByPref('東京都');
    expect(result.systems, isEmpty);
    expect(result.failure, isNull);
    expect(server.requests, hasLength(1));
  });
}
