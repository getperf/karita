/// 受信口を、**OS 側の受信部無しで**測る。
///
/// 実機で確かめるのは「共有・拡張から実際に届くか」であって、こちらの判断ではない。判断
/// （番号と URL が揃っていなければ受け取らない・受信部が無い端末では黙って空を返す）は偽の
/// channel に対して固定できる。**固定しておかないと、受信部の無いビルドで起動そのものが
/// 落ちる形に気づけない。**
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_platform_flutter/karita_platform_flutter.dart';

const MethodChannel _channel = MethodChannel(shareChannelName);

void _answer(Object? Function() reply) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
    expect(call.method, shareSnapshotMethod);
    return reply();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('番号と URL が揃っていれば受け取る', () async {
    _answer(() => {'id': 3, 'url': 'https://calil.jp/book/427421933X',
          'source': 'share'});

    final delivery = await ChannelShareInbox().poll();

    expect(delivery?.id, 3);
    expect(delivery?.url, 'https://calil.jp/book/427421933X');
    expect(delivery?.source, 'share');
  });

  test('番号 0 は「まだ何も来ていない」', () async {
    _answer(() => {'id': 0});
    expect(await ChannelShareInbox().poll(), isNull);
  });

  test('URL が無い・空のものは受け取らない', () async {
    _answer(() => {'id': 1});
    expect(await ChannelShareInbox().poll(), isNull);

    _answer(() => {'id': 1, 'url': ''});
    expect(await ChannelShareInbox().poll(), isNull);
  });

  test('素性が無くても受け取る。診断のための値だからである', () async {
    _answer(() => {'id': 1, 'url': 'https://example.jp/'});
    expect((await ChannelShareInbox().poll())?.source, 'unknown');
  });

  test('受信部が無い端末では空を返す。落とさない', () async {
    // mock を置かない = `MissingPluginException`。**「届いていない」であって「壊れている」
    // ではない。**
    expect(await ChannelShareInbox().poll(), isNull);
  });

  test('OS 側が失敗しても空を返す', () async {
    _answer(() => throw PlatformException(code: 'unavailable'));
    expect(await ChannelShareInbox().poll(), isNull);
  });

  test('URL の中身は見ない。受理規則は karita_handoff が持つ', () async {
    _answer(() => {'id': 1, 'url': 'not a url at all', 'source': 'paste'});
    expect((await ChannelShareInbox().poll())?.url, 'not a url at all');
  });
}
