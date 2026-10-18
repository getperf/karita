/// URI 起動の受信口を、**実際の URI 起動無しで**測る。
///
/// 実機で確かめるのは「拡張から押して届くか・Window が増えないか」であって、こちらの判断では
/// ない。判断（番号を進める・最新1件だけ持つ・読んでも進まない・封筒として申告する）は偽の
/// stream に対して固定できる。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_platform_flutter/karita_platform_flutter.dart';

void main() {
  late StreamController<Uri> links;
  late AppLinksShareInbox inbox;

  setUp(() {
    links = StreamController<Uri>();
    inbox = AppLinksShareInbox(links: links.stream);
  });

  tearDown(() {
    inbox.close();
    unawaited(links.close());
  });

  Future<void> deliver(String uri) async {
    links.add(Uri.parse(uri));
    await Future<void>.delayed(Duration.zero);
  }

  test('届く前は空である', () async {
    expect(await inbox.poll(), isNull);
  });

  test('届いたら封筒として申告する', () async {
    await deliver('karita://share?url=https%3A%2F%2Fcalil.jp%2Fbook%2F427421933X');

    final delivery = await inbox.poll();

    expect(delivery?.id, 1);
    expect(delivery?.form, InboxDeliveryForm.deliveryUri);
    expect(delivery?.source, appLinkSource);
    // **中身は見ない。** 復号も分類も `karita_handoff` の仕事である。
    expect(delivery?.url, startsWith('karita://share?url='));
  });

  test('読んでも番号は進まない', () async {
    await deliver('karita://share?url=x');

    expect((await inbox.poll())?.id, 1);
    expect((await inbox.poll())?.id, 1);
  });

  test('最新の1件だけを持つ。番号は進む', () async {
    await deliver('karita://share?url=x');
    await deliver('karita://share?url=y');

    final delivery = await inbox.poll();

    expect(delivery?.id, 2);
    expect(delivery?.url, endsWith('y'));
  });

  test('pending batch preserves FIFO and acknowledges only processed deliveries', () async {
    await deliver('karita://share?url=x');
    await deliver('karita://share?url=y');
    expect((await inbox.after(0)).map((d) => d.id), [1, 2]);
    expect((await inbox.after(1)).map((d) => d.id), [2]);
    await deliver('karita://share?url=z');
    expect((await inbox.after(1)).map((d) => d.id), [2, 3]);
    expect(await inbox.after(3), isEmpty);
  });

  test('封筒でない URI も運ぶ。断るのは共通解析である', () async {
    await deliver('https://calil.jp/book/427421933X');

    expect((await inbox.poll())?.form, InboxDeliveryForm.deliveryUri);
  });

  test('閉じた後は受け取らない', () async {
    inbox.close();
    await deliver('karita://share?url=x');

    expect(await inbox.poll(), isNull);
  });
}
