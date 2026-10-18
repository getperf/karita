/// Drive REST v3 の一部を話す偽サーバ。**`dart:io` の `HttpServer` で、localhost に立てる。**
///
/// **これが P2 の要である。** Python が実 Drive まで持ち越した実装の穴は、どれも「クライアント
/// ライブラリが応答を包んでいて手前で作れなかった」ことに由来する。ローカルの HTTP サーバなら、
/// 401 も 308 も途中で切れた応答も**こちらが返せる**。
///
/// 偽クライアント（`fake_drive_client.dart`）と役割が違う。あちらが模すのは**保管先のふるまい**
/// （同名の重複作成、ページ分割、検算値を返さない応答）で、こちらが模すのは**プロトコル**
/// （要求の組み立て、resumable の手順、status の分類）である。層1 と層2 の境目がそのまま
/// この2つの境目になる。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// 保管しているファイル1件。
class ServerFile {
  String name;
  Map<String, String> appProperties;
  List<int> body;

  ServerFile(this.name, this.appProperties, this.body);
}

/// 開きかけの resumable セッション。
class _Session {
  final String name;
  final Map<String, String> appProperties;
  final int declaredLength;
  final List<int> received = [];

  _Session(this.name, this.appProperties, this.declaredLength);
}

class FakeDriveServer {
  final HttpServer _server;

  final Map<String, ServerFile> files = {};
  final Map<String, _Session> _sessions = {};

  /// 受け付けたトークン。これ以外は 401 を返す。
  String expectedToken;

  /// `about.get` が返す `user`。**`emailAddress` を省くと未応答を試験できる。**
  Map<String, Object?> account = const {
    'permissionId': 'server-account-1',
    'emailAddress': 'server@example.com',
    'displayName': 'Server Account',
  };

  /// 1ページの件数。**小さくして、ページ跨ぎを通常の経路にする。**
  int pageSize;

  /// resumable の PUT を、1回につきこのバイト数だけ受理する。null なら全部受け取る。
  ///
  /// **部分受理は実 Drive でも起こる。** 308 と `Range` を返す枝を通すために要る。
  int? acceptPerPut;

  /// 次の要求にだけ返す status。**故障を1回だけ差し込む。**
  int? failNextWith;

  /// 二値の応答から `size` を落とす。検算が走らないまま公開されないことを見る。
  bool omitSize = false;

  /// 二値の応答から `md5Checksum` を落とす。
  bool omitMd5 = false;

  /// 受け取った要求の記録。**組み立てを検査するためにある。**
  final List<RecordedRequest> requests = [];

  FakeDriveServer._(this._server, this.expectedToken, this.pageSize);

  static Future<FakeDriveServer> start({
    String token = 'token-1',
    int pageSize = 2,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeDriveServer._(server, token, pageSize);
    unawaited(fake._serve());
    return fake;
  }

  Uri get apiBase => Uri.parse('http://127.0.0.1:${_server.port}/drive/v3');
  Uri get uploadBase =>
      Uri.parse('http://127.0.0.1:${_server.port}/upload/drive/v3');

  Future<void> close() => _server.close(force: true);

  /// 名前を指定して1件置く。試験の前提を作るための口である。
  String seed(String name, Map<String, String> appProperties, String body) {
    final id = 'file${files.length + 1}';
    files[id] = ServerFile(name, appProperties, utf8.encode(body));
    return id;
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      try {
        await _handle(request);
      } on Object catch (exc) {
        request.response.statusCode = 500;
        request.response.write('$exc');
        await request.response.close();
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await _readBytes(request);
    requests.add(
      RecordedRequest(
        method: request.method,
        uri: request.uri,
        headers: {
          for (final name in const [
            'authorization',
            'content-type',
            'content-range',
            'x-upload-content-length',
            'x-upload-content-type',
          ])
            if (request.headers.value(name) != null)
              name: request.headers.value(name)!,
        },
        body: body,
      ),
    );

    final failure = failNextWith;
    if (failure != null) {
      failNextWith = null;
      return _finish(request, failure, {'error': 'injected'});
    }

    // **認可はどの経路でも先に見る。** 一箇所でも素通りすると、その経路だけ 401 を作れない。
    if (request.headers.value('authorization') != 'Bearer $expectedToken') {
      return _finish(request, 401, {
        'error': {'code': 401, 'message': 'Invalid Credentials'},
      });
    }

    final path = request.uri.path;
    if (path == '/upload/drive/v3/files') {
      return _upload(request, body);
    }
    if (path.startsWith('/upload/session/')) {
      return _session(request, path.substring('/upload/session/'.length), body);
    }
    if (path == '/drive/v3/files') {
      return _list(request);
    }
    if (path == '/drive/v3/about') {
      return _finish(request, 200, {'user': account});
    }
    if (path.startsWith('/drive/v3/files/')) {
      final id = path.substring('/drive/v3/files/'.length);
      return switch (request.method) {
        'GET' => _get(request, id),
        'DELETE' => _delete(request, id),
        'PATCH' => _patch(request, id, body),
        _ => _finish(request, 405, {'error': 'method'}),
      };
    }
    return _finish(request, 404, {'error': 'not found'});
  }

  Future<void> _list(HttpRequest request) async {
    final query = request.uri.queryParameters;
    // 名前で絞る規則はクライアントが持つ。ここが解釈するのは `appProperties has` だけである。
    final wanted = RegExp(
      r"value='([^']*)'",
    ).firstMatch(query['q'] ?? '')?.group(1);
    final matched = [
      for (final entry in files.entries)
        if (wanted == null || entry.value.appProperties['eventId'] == wanted)
          entry,
    ];

    final offset = int.tryParse(query['pageToken'] ?? '0') ?? 0;
    final size = int.tryParse(query['pageSize'] ?? '') ?? pageSize;
    final take = size < pageSize ? size : pageSize;
    final end = offset + take;
    final page = matched.sublist(
      offset.clamp(0, matched.length),
      end.clamp(0, matched.length),
    );

    return _finish(request, 200, {
      if (end < matched.length) 'nextPageToken': '$end',
      'files': [
        for (final entry in page)
          {
            'id': entry.key,
            'name': entry.value.name,
            'appProperties': entry.value.appProperties,
            // **`size` は文字列で返る。** 実 Drive がそうなので、そこも模す。
            'size': '${entry.value.body.length}',
          },
      ],
    });
  }

  Future<void> _get(HttpRequest request, String id) async {
    final file = files[id];
    if (file == null) return _finish(request, 404, {'error': 'not found'});
    if (request.uri.queryParameters['alt'] != 'media') {
      return _finish(request, 200, {'id': id, 'name': file.name});
    }
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.binary;
    request.response.add(file.body);
    await request.response.close();
  }

  Future<void> _delete(HttpRequest request, String id) async {
    files.remove(id);
    request.response.statusCode = 204;
    await request.response.close();
  }

  Future<void> _patch(HttpRequest request, String id, List<int> body) async {
    final file = files[id];
    if (file == null) return _finish(request, 404, {'error': 'not found'});
    final payload = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    final name = payload['name'];
    if (name is String) file.name = name;
    return _finish(request, 200, {'id': id});
  }

  Future<void> _upload(HttpRequest request, List<int> body) async {
    final type = request.uri.queryParameters['uploadType'];
    if (type == 'multipart') {
      return _multipart(request, body);
    }
    if (type != 'resumable') {
      return _finish(request, 400, {'error': 'uploadType'});
    }

    // セッションを開く。**本体はまだ来ていない。**
    final metadata = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    final sessionId = 'session${_sessions.length + 1}';
    _sessions[sessionId] = _Session(
      '${metadata['name']}',
      _properties(metadata),
      int.tryParse(request.headers.value('x-upload-content-length') ?? '') ?? 0,
    );
    request.response.statusCode = 200;
    request.response.headers.set(
      'location',
      'http://127.0.0.1:${_server.port}/upload/session/$sessionId',
    );
    await request.response.close();
  }

  Future<void> _session(
    HttpRequest request,
    String sessionId,
    List<int> body,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) return _finish(request, 404, {'error': 'session'});

    final limit = acceptPerPut;
    final take = (limit == null || limit >= body.length) ? body.length : limit;
    session.received.addAll(body.sublist(0, take));

    if (session.received.length < session.declaredLength) {
      // **308 は失敗ではない。** 受理済みの末尾を返して続きを求める。
      request.response.statusCode = 308;
      request.response.headers.set(
        'range',
        'bytes=0-${session.received.length - 1}',
      );
      await request.response.close();
      return;
    }

    _sessions.remove(sessionId);
    final id = 'file${files.length + 1}';
    files[id] = ServerFile(
      session.name,
      session.appProperties,
      session.received,
    );
    return _finish(request, 200, _uploadResult(id, session.received));
  }

  Future<void> _multipart(HttpRequest request, List<int> body) async {
    final text = utf8.decode(body);
    final type = request.headers.value('content-type') ?? '';
    final boundary =
        RegExp(r'boundary=([^\s;]+)').firstMatch(type)?.group(1) ?? '';
    if (boundary.isEmpty) return _finish(request, 400, {'error': 'boundary'});

    // 2つの部分に割る。**素直に境界で切る** — ここで模したいのは組み立ての形であって、
    // MIME の網羅ではない。
    final parts = text
        .split('--$boundary')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != '--')
        .toList();
    if (parts.length != 2) return _finish(request, 400, {'error': 'parts'});

    String payloadOf(String part) {
      final separator = part.indexOf('\r\n\r\n');
      return separator < 0 ? '' : part.substring(separator + 4);
    }

    final metadata = jsonDecode(payloadOf(parts.first)) as Map<String, Object?>;
    final id = 'file${files.length + 1}';
    files[id] = ServerFile(
      '${metadata['name']}',
      _properties(metadata),
      utf8.encode(payloadOf(parts.last)),
    );
    return _finish(request, 200, {'id': id});
  }

  Map<String, Object?> _uploadResult(String id, List<int> content) => {
    'id': id,
    if (!omitMd5) 'md5Checksum': _md5Hex(content),
    // 実 Drive は文字列で返す。
    if (!omitSize) 'size': '${content.length}',
  };

  Map<String, String> _properties(Map<String, Object?> metadata) {
    final raw = metadata['appProperties'];
    return {
      for (final entry in (raw is Map ? raw : const {}).entries)
        '${entry.key}': '${entry.value}',
    };
  }

  Future<void> _finish(
    HttpRequest request,
    int status,
    Map<String, Object?> payload,
  ) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(payload));
    await request.response.close();
  }

  static Future<List<int>> _readBytes(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
    }
    return bytes;
  }
}

/// 受け取った要求の記録。組み立てを検査するために使う。
class RecordedRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;

  const RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  String get bodyText => utf8.decode(body);
}

/// 応答に載せる md5。`package:crypto` の値をそのまま使う。
String _md5Hex(List<int> content) => md5.convert(content).toString();
