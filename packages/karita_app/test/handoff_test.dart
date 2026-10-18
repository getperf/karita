import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:logging/logging.dart';

const String _bookUrl = 'https://calil.jp/book/427421933X';
const String _isbn13 = '9784274219337';

/// 番号を持つ holder を真似る。**読んでも番号は進まない。**
class _FakeInbox extends ShareInbox {
  InboxDelivery? pending;
  int polls = 0;

  void accept(
    int id,
    String url, {
    String source = 'share',
    InboxDeliveryForm form = InboxDeliveryForm.sharedText,
  }) =>
      pending =
          InboxDelivery(id: id, url: url, source: source, form: form);

  @override
  Future<InboxDelivery?> poll() async {
    polls++;
    return pending;
  }
}

void main() {
  test('届いた URL を分類して流す', () async {
    final inbox = _FakeInbox()..accept(1, _bookUrl);
    final queue = HandoffQueue(inbox);
    final seen = <Handoff>[];
    queue.deliveries.listen(seen.add);

    final result = await queue.drain();

    expect(result, isA<HandoffBook>());
    expect((result! as HandoffBook).isbn13, _isbn13);
    expect(queue.latest, result);
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    queue.dispose();
  });

  test('同じ配送は二度処理しない。番号が進めば処理する', () async {
    final inbox = _FakeInbox()..accept(1, _bookUrl);
    final queue = HandoffQueue(inbox);

    expect(await queue.drain(), isA<HandoffBook>());
    // 画面の再生成でもう一度呼ばれた。**同じ番号なので何もしない。**
    expect(await queue.drain(), isNull);
    // The first drain also checks that no further delivery remains.
    expect(inbox.polls, 3);

    // 利用者が同じ URL をもう一度送った。**番号が進むので処理する。**
    inbox.accept(2, _bookUrl);
    expect(await queue.drain(), isA<HandoffBook>());
    queue.dispose();
  });

  test('受理しない入力は理由付きで流れる。業務状態は関係しない', () async {
    final inbox = _FakeInbox()..accept(1, 'https://calil.jp/search?q=x');
    final queue = HandoffQueue(inbox);

    final result = await queue.drain();

    expect(result, const HandoffNotice(HandoffReason.calilNonBook));
    queue.dispose();
  });

  test('一般の Web URL はそのまま渡る。用途は決めない', () async {
    final inbox = _FakeInbox()..accept(1, 'https://www.koto-lib.tokyo.jp/');
    final queue = HandoffQueue(inbox);

    expect(await queue.drain(), isA<HandoffWebUrl>());
    queue.dispose();
  });

  group('外側の封筒は端末の入口で決まる', () {
    final encoded = Uri.encodeComponent(_bookUrl);

    test('配送 URI は1回だけ復号してから共通解析へ渡す', () async {
      final inbox = _FakeInbox()
        ..accept(1, 'karita://share?url=$encoded',
            source: 'uri', form: InboxDeliveryForm.deliveryUri);
      final queue = HandoffQueue(inbox);

      final result = await queue.drain();

      expect(result, isA<HandoffBook>());
      expect((result! as HandoffBook).isbn13, _isbn13);
      queue.dispose();
    });

    test('共有テキストとして届いた配送 URI は受けない', () async {
      // **形を素性から推測しない。** Android の共有から `karita://` が来ても、封筒として
      // 扱ってよい理由にはならない。
      final inbox = _FakeInbox()..accept(1, 'karita://share?url=$encoded');
      final queue = HandoffQueue(inbox);

      expect(await queue.drain(), const HandoffNotice(HandoffReason.badScheme));
      queue.dispose();
    });

    test('封筒の形が違えば断る', () async {
      final inbox = _FakeInbox()
        ..accept(1, _bookUrl, form: InboxDeliveryForm.deliveryUri);
      final queue = HandoffQueue(inbox);

      expect(
          await queue.drain(), const HandoffNotice(HandoffReason.badDelivery));
      queue.dispose();
    });
  });

  test('Amazon は URL 全文も ISBN の値もログへ出さない', () async {
    const url =
        'https://www.amazon.co.jp/%E6%9B%B8%E5%90%8D/dp/427421933X?crid=SECRET&k=word';
    final inbox = _FakeInbox()..accept(1, url);
    final queue = HandoffQueue(inbox);
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    final result = await queue.drain();

    expect(
      result,
      const HandoffAmazon(_isbn13, AmazonShape.isbn10, 'www.amazon.co.jp'),
    );
    final received = records.singleWhere(
      (r) => r.message == 'handoff.received',
    );
    expect(received.error, {
      'id': 1,
      'source': 'share',
      'kind': 'amazon',
      'host': 'www.amazon.co.jp',
      'shape': 'isbn10',
      'isbn': true,
    });
    final text = '${received.message} ${received.error}';
    for (final secret in ['SECRET', 'word', '427421933X', _isbn13, '/dp/']) {
      expect(text, isNot(contains(secret)));
    }
    // 保持するのも URL を持たない枝だけである。
    expect('${queue.latest}', isNot(contains('SECRET')));
    // **書籍の受信待ちには入れない。** 着地は合成層が決める。
    expect(queue.takeBooks(), isEmpty);
    queue.dispose();
  });

  test('配送 URI の via はログに経路として出し、解析結果は変えない', () async {
    final encoded = Uri.encodeComponent('https://www.amazon.co.jp/dp/427421933X');
    final inbox = _FakeInbox()
      ..accept(1, 'karita://share?url=$encoded',
          form: InboxDeliveryForm.deliveryUri);
    final queue = HandoffQueue(inbox);
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    await queue.drain();
    inbox.accept(2, 'karita://share?url=$encoded&via=retry',
        form: InboxDeliveryForm.deliveryUri);
    await queue.drain();

    final received =
        records.where((r) => r.message == 'handoff.received').toList();
    expect(received, hasLength(2));
    expect((received[0].error as Map).containsKey('via'), isFalse);
    expect((received[1].error as Map)['via'], 'retry');
    expect(queue.latest,
        const HandoffAmazon(_isbn13, AmazonShape.isbn10, 'www.amazon.co.jp'));
    queue.dispose();
  });

  test('受信部が無ければ何も起きない', () async {
    final queue = HandoffQueue(const NoShareInbox());
    expect(await queue.drain(), isNull);
    expect(queue.latest, isNull);
    queue.dispose();
  });

  test('捨てるときは番号だけ進めて処理しない', () async {
    final inbox = _FakeInbox()..accept(7, _bookUrl);
    final queue = HandoffQueue(inbox);
    queue.remember(LaunchContext(
      purpose: LaunchPurpose.lending,
      systemId: 'Tokyo_Koto',
      host: 'www.koto-lib.tokyo.jp',
      startedAt: DateTime.utc(2026, 9, 15),
    ));

    await queue.discardPending();

    expect(queue.latest, isNull, reason: '捨てた配送を最新として残さない');
    expect(queue.launch, isNull, reason: 'リセットは起動情報も捨てる');
    // **番号は進んでいる。** 進めないと、リセット直後の排出が同じ配送を拾う。
    expect(await queue.drain(), isNull);
    queue.dispose();
  });

  group('起動情報の一時保持', () {
    final context = LaunchContext(
      purpose: LaunchPurpose.mypageUrl,
      systemId: 'Tokyo_Minato',
      host: 'www.lib.city.minato.tokyo.jp',
      startedAt: DateTime.utc(2026, 9, 15, 10),
    );

    test('最新1件へ置き換える。タブごとの履歴は作らない', () {
      final queue = HandoffQueue(const NoShareInbox());
      queue.remember(context);
      queue.remember(LaunchContext(
        purpose: LaunchPurpose.lending,
        systemId: 'Tokyo_Koto',
        host: 'www.koto-lib.tokyo.jp',
        startedAt: DateTime.utc(2026, 9, 15, 11),
      ));

      expect(queue.launch?.purpose, LaunchPurpose.lending);
      expect(queue.launch?.systemId, 'Tokyo_Koto');
      queue.dispose();
    });

    test('確定で消費する。二度は取れない', () {
      final queue = HandoffQueue(const NoShareInbox());
      queue.remember(context);

      final used = queue.consume(now: DateTime.utc(2026, 9, 15, 10, 30));

      expect(used?.systemId, 'Tokyo_Minato');
      expect(queue.launch, isNull);
      expect(queue.consume(), isNull);
      queue.dispose();
    });

    test('起動に失敗したら今回の候補を捨てる。以前のものを復活させない', () {
      final queue = HandoffQueue(const NoShareInbox());
      queue.remember(context);
      queue.clearLaunch();

      expect(queue.launch, isNull);
      queue.dispose();
    });
  });
}
