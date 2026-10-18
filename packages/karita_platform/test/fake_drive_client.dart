/// Drive の既定の挙動を模すインプロセスの偽クライアント。**ネットワークに触らない。**
///
/// **これは故障注入ではない。** 故障注入（`upload-timeout`・`auth-401` など）は fixture から
/// 名前で指定できる必要があるため製品側にあり、受入ケース07〜10 を再現する。ここが模すのは
/// 受入ケースではなく**保管先の既定の挙動**（同名の重複作成、ページ分割、書込み直後の不可視、
/// 検算値を返さない応答）なので、試験側に置く。
///
/// 区別の基準は「fixture から名前で指定できる必要があるか」である。
///
/// 移送元: book-sync-model の `tests/test_drive_transport.py`（`FakeDriveClient`）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_sync/karita_sync.dart';

/// 保管先にある1件。文字列で載ったものも二値で載ったものもバイト列で持つ。
class FakeFile {
  String name;
  Map<String, String> appProperties;
  List<int> body;

  /// 名乗った名前を、作られた順に持つ。**二段名は「先に何を名乗ったか」が要点**なので、
  /// 現在の名前だけを持つと、改名を経ずに最初から公開したものと区別が付かない。
  final List<String> names;

  FakeFile(this.name, this.appProperties, this.body) : names = [name];
}

/// 一覧のクエリから `value='...'` を取り出す。偽サーバではなく偽クライアントなので、
/// 解釈するのは絞り込みに要る一箇所だけでよい。
final RegExp _valuePattern = RegExp(r"value='([^']*)'");

/// 名前の前方一致（`namePrefixQuery`）。**実 Drive の `contains` と同じく前置で絞る。**
final RegExp _namePattern = RegExp(r"^name contains '([^']*)'$");

class FakeDriveClient implements DriveClient {
  /// `about()` が返す値。**試験が名乗るアカウントを差し替えるためにある。**
  DriveAccountInfo account;

  /// 1ページの件数。**既定を小さくしてある** — ページ跨ぎが例外ではなく通常の経路になる。
  final int pageSize;

  /// 書いた直後のものが一覧に出ない（遅延反映）。
  final bool hideNew;

  /// 二値の upload が、送ったものと違う md5 を返す。
  final bool corruptUpload;

  /// md5 は合っているのに大きさが足りない。**md5 だけでは捕まらない。**
  final bool truncatedUpload;

  /// 大きさも md5 も返さない。**検算が走っていない応答である。**
  final bool silentUpload;

  /// 一覧の途中で認可を失う。`find` の側で 401 を受ける経路を作る。
  bool failListWithAuth = false;

  final Map<String, FakeFile> files = {};
  final Set<String> hidden = {};
  final List<String?> queries = [];
  final List<String> fetched = [];

  /// 消えたものが名乗っていた名前。**捨てた実体が公開の名前を通っていないこと**を試験が
  /// 確かめるために要る — 消してしまえば、残っているものを見ても分からない。
  final List<String> deletedNames = [];

  int _sequence = 0;

  FakeDriveClient({
    this.pageSize = 3,
    this.hideNew = false,
    this.corruptUpload = false,
    this.truncatedUpload = false,
    this.silentUpload = false,
    this.account = const DriveAccountInfo(
      permissionId: 'fake-account-1',
      emailAddress: 'fake@example.com',
    ),
  });

  void reveal() => hidden.clear();

  @override
  Future<String> create(
    String name,
    Map<String, String> appProperties,
    String text,
  ) async {
    final fileId = _newId();
    files[fileId] = FakeFile(name, Map.of(appProperties), utf8.encode(text));
    if (hideNew) hidden.add(fileId);
    return fileId;
  }

  @override
  Future<DrivePage> listPage({String? pageToken, String? query}) async {
    if (failListWithAuth) {
      throw TransportAuthError('Drive の一覧で認可されませんでした（HTTP 401）。');
    }
    queries.add(query);
    final prefix = query == null
        ? null
        : _namePattern.firstMatch(query)?.group(1);
    final wanted = query == null || prefix != null
        ? null
        : _valuePattern.firstMatch(query)?.group(1);
    final visible = [
      for (final entry in files.entries)
        if (!hidden.contains(entry.key) &&
            (prefix == null || entry.value.name.startsWith(prefix)) &&
            (wanted == null ||
                entry.value.appProperties[propEventId] == wanted))
          FileRef(
            fileId: entry.key,
            name: entry.value.name,
            appProperties: entry.value.appProperties,
            sizeBytes: entry.value.body.length,
          ),
    ];
    final offset = pageToken == null ? 0 : int.parse(pageToken);
    final end = offset + pageSize;
    return DrivePage(
      visible.sublist(
        offset.clamp(0, visible.length),
        end.clamp(0, visible.length),
      ),
      end < visible.length ? '$end' : null,
    );
  }

  @override
  Future<String> getText(String fileId) async {
    fetched.add(fileId);
    return utf8.decode(_require(fileId).body);
  }

  @override
  Future<void> delete(String fileId) async {
    final removed = files.remove(fileId);
    if (removed != null) deletedNames.addAll(removed.names);
  }

  @override
  Future<Uploaded> createBinary(
    String name,
    Map<String, String> appProperties,
    String path,
  ) async {
    final payload = File(path).readAsBytesSync();
    final fileId = _newId();
    files[fileId] = FakeFile(name, Map.of(appProperties), payload);
    if (silentUpload) return Uploaded(fileId: fileId);
    final digest = '${md5.convert(payload)}';
    if (truncatedUpload) {
      return Uploaded(
        fileId: fileId,
        md5: digest,
        sizeBytes: payload.isEmpty ? 0 : payload.length - 1,
      );
    }
    return Uploaded(
      fileId: fileId,
      md5: corruptUpload ? '0' * 32 : digest,
      sizeBytes: payload.length,
    );
  }

  @override
  Future<void> download(String fileId, String destPath) async {
    fetched.add(fileId);
    File(destPath).writeAsBytesSync(_require(fileId).body, flush: true);
  }

  @override
  Future<void> rename(String fileId, String name) async {
    final file = _require(fileId);
    file.name = name;
    file.names.add(name);
  }

  @override
  Future<DriveAccountInfo> about() async => account;

  FakeFile _require(String fileId) {
    final file = files[fileId];
    if (file == null) throw StateError('偽の保管先に $fileId がありません');
    return file;
  }

  String _newId() => 'file${++_sequence}';
}
