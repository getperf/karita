/// Drive REST v3 を `package:http` で直に叩く [DriveClient]。
///
/// **クライアントライブラリを挟まない。** Python が実 Drive まで持ち越した穴のうち2つは、
/// `googleapiclient` が 401 をその場の refresh へ変えてしまい、呼び出し側が HTTP status を
/// 見られなかったことに由来する。直に叩けば、status も本文もこちらが見る — 偽サーバがその応答を
/// 返せば手元で再現できる。
///
/// **待つのはここだけである。** 上の `DriveTransport` と `DriveBackupStore` は判定と名前の
/// 規則しか持たず、この下に HTTP がある。層1 で通した規則は、ここが何を返しても変わらない。
///
/// 移送元: book-sync-model の `src/bsync_core/drive.py`（`GoogleDriveClient`）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:karita_contract/errors.dart';
import 'package:karita_sync/karita_sync.dart';

import 'access_token.dart';
import 'drive_client.dart';
import 'drive_errors.dart';

/// 実 Drive の口。
final Uri driveApiBase = Uri.parse('https://www.googleapis.com/drive/v3');
final Uri driveUploadBase = Uri.parse(
  'https://www.googleapis.com/upload/drive/v3',
);

/// resumable upload の1回ぶん。**回線が切れる前提で刻む。**
const int defaultChunkBytes = 8 * 1024 * 1024;

/// 一覧で要求する項目。**要るものだけを名指しする。**
///
/// 既定の応答は全項目を返す。`appDataFolder` に数百件が溜まった端末で、使わない項目まで運ぶ
/// 理由が無い。
const String _listFields = 'nextPageToken,files(id,name,appProperties,size)';

/// 二値を載せた後に要求する項目。**検算に使う2つを必ず名指しする。**
///
/// `size` と `md5Checksum` を求めないと、保管先は返さない。呼び出し側の検算は
/// 「返らなかった」を失敗として扱うので、ここで求め忘れると公開が必ず落ちる。
const String _uploadFields = 'id,md5Checksum,size';

class RestDriveClient implements DriveClient {
  final AccessTokenProvider tokens;
  final http.Client httpClient;
  final Uri apiBase;
  final Uri uploadBase;
  final int pageSize;
  final int chunkBytes;

  RestDriveClient({
    required this.tokens,
    http.Client? httpClient,
    Uri? apiBase,
    Uri? uploadBase,
    this.pageSize = defaultPageSize,
    this.chunkBytes = defaultChunkBytes,
  }) : httpClient = httpClient ?? http.Client(),
       apiBase = apiBase ?? driveApiBase,
       uploadBase = uploadBase ?? driveUploadBase;

  void close() => httpClient.close();

  // --- 封筒（文字列） -------------------------------------------------------

  @override
  Future<String> create(
    String name,
    Map<String, String> appProperties,
    String text,
  ) async {
    // multipart/related。数 KB の JSON なので一度に載せる。
    const boundary = 'karita-boundary-4f2a1c';
    final metadata = jsonEncode({
      'name': name,
      'parents': [appDataSpace],
      'appProperties': appProperties,
    });
    final body = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$metadata\r\n'
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$text\r\n'
      '--$boundary--\r\n',
    );

    final response = await _send(
      label: 'アップロード',
      writing: true,
      build: (token) =>
          http.Request(
              'POST',
              uploadBase.replace(
                path: '${uploadBase.path}/files',
                queryParameters: {'uploadType': 'multipart', 'fields': 'id'},
              ),
            )
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'Content-Type': 'multipart/related; boundary=$boundary',
            })
            ..bodyBytes = body,
    );
    return '${_json(response, 'アップロード')['id']}';
  }

  @override
  Future<DrivePage> listPage({String? pageToken, String? query}) async {
    final response = await _send(
      label: '一覧',
      writing: false,
      build: (token) => http.Request(
        'GET',
        apiBase.replace(
          path: '${apiBase.path}/files',
          queryParameters: {
            'spaces': appDataSpace,
            'pageSize': '$pageSize',
            'fields': _listFields,
            if (query != null) 'q': query,
            if (pageToken != null) 'pageToken': pageToken,
          },
        ),
      )..headers['Authorization'] = 'Bearer $token',
    );

    final payload = _json(response, '一覧');
    final files = payload['files'];
    return DrivePage([
      for (final item in (files is List ? files : const []))
        if (item is Map)
          FileRef(
            fileId: '${item['id']}',
            name: '${item['name'] ?? ''}',
            appProperties: {
              for (final entry
                  in (item['appProperties'] as Map? ?? const {}).entries)
                '${entry.key}': '${entry.value}',
            },
            // **`size` は文字列で返る。** 数値として読むと 0 に落ち、baseline の大きさが
            // すべて 0 になる。
            sizeBytes: int.tryParse('${item['size'] ?? 0}') ?? 0,
          ),
    ], payload['nextPageToken'] as String?);
  }

  @override
  Future<String> getText(String fileId) async {
    final response = await _send(
      label: '取得',
      writing: false,
      build: (token) => http.Request(
        'GET',
        apiBase.replace(
          path: '${apiBase.path}/files/$fileId',
          queryParameters: {'alt': 'media'},
        ),
      )..headers['Authorization'] = 'Bearer $token',
    );
    return utf8.decode(response.bodyBytes);
  }

  @override
  Future<void> delete(String fileId) async {
    // **読み取り扱いにする。** 削除が届いたか不明でも、outbox の行を `uploading` に落とす
    // 理由にはならない。削除は封筒の送信経路にいない。
    await _send(
      label: '削除',
      writing: false,
      build: (token) => http.Request(
        'DELETE',
        apiBase.replace(path: '${apiBase.path}/files/$fileId'),
      )..headers['Authorization'] = 'Bearer $token',
    );
  }

  @override
  Future<DriveAccountInfo> about() async {
    final response = await _send(
      label: 'アカウントの確認',
      writing: false,
      build: (token) => http.Request(
        'GET',
        apiBase.replace(
          path: '${apiBase.path}/about',
          queryParameters: {
            'fields': 'user(emailAddress,permissionId,displayName)',
          },
        ),
      )..headers['Authorization'] = 'Bearer $token',
    );
    final payload = _json(response, 'アカウントの確認');
    final user = payload['user'];
    final map = user is Map ? user : const {};
    return DriveAccountInfo(
      permissionId: '${map['permissionId'] ?? ''}',
      emailAddress: map['emailAddress'] as String?,
      displayName: map['displayName'] as String?,
    );
  }

  @override
  Future<void> rename(String fileId, String name) async {
    await _send(
      label: 'バックアップの公開',
      writing: true,
      build: (token) =>
          http.Request(
              'PATCH',
              apiBase.replace(
                path: '${apiBase.path}/files/$fileId',
                queryParameters: {'fields': 'id'},
              ),
            )
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=UTF-8',
            })
            ..body = jsonEncode({'name': name}),
    );
  }

  // --- `.blib`（二値） ------------------------------------------------------

  /// resumable upload。**メモリへ全部載せない。**
  ///
  /// 手順は「セッションを開く → `Content-Range` を付けて刻んで PUT → 最後の応答が本体」で
  /// ある。**308 は失敗ではない**（続きを求めている）。刻むのは、`.blib` が MB 級になりうる
  /// うえ、Android では回線が切れる前提で考える必要があるからである。
  @override
  Future<Uploaded> createBinary(
    String name,
    Map<String, String> appProperties,
    String path,
  ) async {
    final file = File(path);
    final total = file.lengthSync();

    final opened = await _send(
      label: 'バックアップのアップロード',
      writing: true,
      build: (token) =>
          http.Request(
              'POST',
              uploadBase.replace(
                path: '${uploadBase.path}/files',
                queryParameters: {
                  'uploadType': 'resumable',
                  'fields': _uploadFields,
                },
              ),
            )
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=UTF-8',
              'X-Upload-Content-Type': 'application/zip',
              'X-Upload-Content-Length': '$total',
            })
            ..body = jsonEncode({
              'name': name,
              'parents': [appDataSpace],
              'appProperties': appProperties,
            }),
    );

    final location = opened.headers['location'];
    if (location == null || location.isEmpty) {
      // セッションの URI が無ければ、載せる先が無い。**黙って0件成功にしない。**
      throw translateDriveFailure(
        label: 'バックアップのアップロード',
        writing: true,
        kind: 'セッションが開けませんでした',
      );
    }
    final session = Uri.parse(location);

    final handle = file.openSync();
    try {
      var offset = 0;
      while (true) {
        final remaining = total - offset;
        final take = remaining < chunkBytes ? remaining : chunkBytes;
        handle.setPositionSync(offset);
        final chunk = handle.readSync(take);
        final start = offset;
        final end = offset + chunk.length - 1;

        final response = await _send(
          label: 'バックアップのアップロード',
          writing: true,
          // 308 は「続きを寄こせ」であって失敗ではない。
          accept: (status) => status == 200 || status == 201 || status == 308,
          build: (token) => http.Request('PUT', session)
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/zip',
              'Content-Range': total == 0
                  ? 'bytes */0'
                  : 'bytes $start-$end/$total',
            })
            ..bodyBytes = chunk,
        );

        if (response.statusCode != 308) {
          final payload = _json(response, 'バックアップのアップロード');
          return Uploaded(
            fileId: '${payload['id']}',
            md5: '${payload['md5Checksum'] ?? ''}',
            // 大きさも md5 も文字列で返る。
            sizeBytes: int.tryParse('${payload['size'] ?? 0}') ?? 0,
          );
        }

        // **次の起点はサーバが決める。** `Range: bytes=0-x` が受理済みの末尾を返すので、
        // こちらの数え方ではなくそちらに合わせる。取りこぼした分を送り直せる唯一の根拠である。
        final accepted = _rangeEnd(response.headers['range']);
        offset = accepted != null ? accepted + 1 : offset + chunk.length;
        if (offset >= total) {
          throw translateDriveFailure(
            label: 'バックアップのアップロード',
            writing: true,
            kind: '全部送ったのに完了の応答がありません',
          );
        }
      }
    } finally {
      handle.closeSync();
    }
  }

  /// `.blib` を落とす。**一時ファイルへ書いてから置く。**
  ///
  /// 中断した download が完成品の名前で残ると、次の復元がそれを選ぶ。hash 検査で止まるので
  /// 壊れたまま復元はされないが、利用者から見れば「壊れたバックアップがある」になる。
  ///
  /// 本文は流したまま書く。MB 級のものを一度メモリへ載せない。
  @override
  Future<void> download(String fileId, String destPath) async {
    final partial = File('$destPath.part');
    partial.parent.createSync(recursive: true);
    try {
      final response = await _sendStreamed(
        label: 'バックアップの取得',
        writing: false,
        build: (token) => http.Request(
          'GET',
          apiBase.replace(
            path: '${apiBase.path}/files/$fileId',
            queryParameters: {'alt': 'media'},
          ),
        )..headers['Authorization'] = 'Bearer $token',
      );
      final sink = partial.openWrite();
      try {
        await response.stream.pipe(sink);
      } finally {
        await sink.close();
      }
    } on SyncDataError {
      if (partial.existsSync()) partial.deleteSync();
      rethrow;
    }
    partial.renameSync(destPath);
  }

  // --- 送信 -----------------------------------------------------------------

  /// 要求を1つ送る。**401 なら一度だけトークンを取り直して送り直す。**
  ///
  /// 期限切れの access token は日常的に起こる。1回の 401 で「認可を失った」と決めると、
  /// 使っている端末が毎日サインインを求められる。**本当に失われていれば、取り直しの側が
  /// [TransportAuthError] で落ちる。**
  ///
  /// **書き込みでも送り直してよい。** 401 で拒否された要求は処理されておらず、重複を作らない。
  ///
  /// [build] を関数で受けるのは、送り直しに新しいトークンを埋めた要求が要るためである。
  /// `http.Request` は一度送ると再利用できない。
  Future<http.Response> _send({
    required String label,
    required bool writing,
    required http.Request Function(String token) build,
    bool Function(int status)? accept,
  }) async {
    final streamed = await _sendStreamed(
      label: label,
      writing: writing,
      build: build,
      accept: accept,
    );
    return http.Response.fromStream(streamed);
  }

  Future<http.StreamedResponse> _sendStreamed({
    required String label,
    required bool writing,
    required http.Request Function(String token) build,
    bool Function(int status)? accept,
  }) async {
    final ok = accept ?? (status) => status >= 200 && status < 300;

    Future<http.StreamedResponse> once({required bool forceRefresh}) async {
      // **トークンは要求ごとに、送る直前に取る。** 構築時に取ると、認可が切れたときに転送を
      // 組む段階で落ち、outbox の行が `blocked_auth` にならない。
      final token = await tokens.accessToken(forceRefresh: forceRefresh);
      try {
        return await httpClient.send(build(token));
      } on SyncDataError {
        rethrow;
      } on Object catch (exc) {
        // 通信そのものが落ちた。**status を持たない。**
        throw translateDriveFailure(
          label: label,
          writing: writing,
          kind: exc.runtimeType.toString(),
        );
      }
    }

    var response = await once(forceRefresh: false);
    if (response.statusCode == 401) {
      // 本文は読み捨てる。開いたままにすると接続が返らない。
      await response.stream.drain<void>();
      response = await once(forceRefresh: true);
    }
    if (!ok(response.statusCode)) {
      await response.stream.drain<void>();
      throw translateDriveFailure(
        label: label,
        writing: writing,
        status: response.statusCode,
      );
    }
    return response;
  }

  Map<String, Object?> _json(http.Response response, String label) {
    final Object? payload;
    try {
      payload = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw translateDriveFailure(
        label: label,
        writing: false,
        kind: '応答を読めませんでした',
      );
    }
    if (payload is! Map<String, Object?>) {
      throw translateDriveFailure(
        label: label,
        writing: false,
        kind: '応答の形が違います',
      );
    }
    return payload;
  }
}

/// `bytes=0-x` の `x`。読めなければ null。
int? _rangeEnd(String? header) {
  if (header == null) return null;
  final match = RegExp(r'bytes=\d+-(\d+)').firstMatch(header);
  return match == null ? null : int.tryParse(match.group(1)!);
}
