/// OpenBD とカーリルの応答を返す偽サーバ。**`dart:io` の `HttpServer` を localhost に立てる。**
///
/// **手元で作れないと確かめられない枝がある。** 未収録・壊れた JSON・404・429・途中で終わる
/// 継続取得は、実 API へ頼んでも都合よくは返ってこない。ここが返せば、全部の枝を通常の
/// `dart test` で踏める。`karita_platform` の偽 Drive サーバと同じ考え方である。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakePublicApiServer {
  final HttpServer _server;

  /// 受けた要求。**順番も見る** — 継続取得が session だけで聞き直しているかを測る。
  final List<Uri> requests = [];

  /// OpenBD の `/v1/get` が返す本文。
  String openBdBody = '[null]';
  int openBdStatus = 200;

  /// 書影の中身と status。
  List<int> imageBytes = const [1, 2, 3, 4];
  int imageStatus = 200;

  /// カーリル `/library` の本文。
  String libraryBody = '[]';
  int libraryStatus = 200;

  /// カーリル `/check` が返す本文を、呼ばれた順に取り出す。
  ///
  /// **1回目と2回目で違うものを返せることが要る。** 継続取得はそこにしか現れない。
  /// 尽きたら最後のものを返し続ける。
  List<String> checkBodies = ['{"session":"s","continue":0,"books":{}}'];
  int checkStatus = 200;

  FakePublicApiServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<FakePublicApiServer> start() async =>
      FakePublicApiServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  /// OpenBD のつもりの base。
  Uri get openBdBase => Uri.parse('http://127.0.0.1:${_server.port}/v1');

  /// カーリルのつもりの base。
  Uri get calilBase => Uri.parse('http://127.0.0.1:${_server.port}');

  /// 書影の URL。**`https` でないと本番の検証に落ちるので、試験は用途で使い分ける。**
  Uri imageUri(String name) =>
      Uri.parse('http://127.0.0.1:${_server.port}/img/$name');

  Future<void> close() => _server.close(force: true);

  int _checkCalls = 0;

  Future<void> _handle(HttpRequest request) async {
    requests.add(request.uri);
    final path = request.uri.path;
    if (path == '/v1/get') {
      await _send(request, openBdStatus, utf8.encode(openBdBody),
          contentType: 'application/json');
    } else if (path.startsWith('/img/')) {
      await _send(request, imageStatus, imageBytes, contentType: 'image/jpeg');
    } else if (path == '/library') {
      await _send(request, libraryStatus, utf8.encode(libraryBody),
          contentType: 'application/json');
    } else if (path == '/check') {
      final index = _checkCalls < checkBodies.length
          ? _checkCalls
          : checkBodies.length - 1;
      _checkCalls++;
      await _send(request, checkStatus, utf8.encode(checkBodies[index]),
          contentType: 'application/json');
    } else {
      await _send(request, 404, const []);
    }
  }

  Future<void> _send(HttpRequest request, int status, List<int> body,
      {String? contentType}) async {
    request.response.statusCode = status;
    if (contentType != null) {
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    request.response.add(body);
    await request.response.close();
  }
}
