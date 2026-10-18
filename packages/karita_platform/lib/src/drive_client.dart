/// Drive API のうち、**転送と保管が要るものだけ**を切り出した口。
///
/// **狭く保つことが、偽クライアントで adapter の分岐を全部通せる条件である。** ここが広がると、
/// 判定・整列・重複排除・二段名・検算のどれかが、偽クライアントでは踏めない経路へ落ちる。
///
/// 二値の3つ（[DriveClient.createBinary] / [DriveClient.download] / [DriveClient.rename]）を
/// 文字列の2つと別にしてある。封筒は数 KB の JSON なので一度に全部メモリへ載せてよいが、
/// `.blib` は zip で MB 級になりうる。同じメソッドで兼ねると、封筒のために選んだ実装が
/// バックアップにも効いてしまう。
///
/// **口はすべて非同期である。** ここが待つのはネットワークで、Dart に同期 HTTP は無い。同期の
/// 口にすると、実装が isolate と遮断 socket で非同期を隠すことになり、その機構をすべての実装が
/// 抱える。`TransportPort` と `BackupStorePort` を非同期にしたのと同じ判断である。
///
/// 移送元: book-sync-model の `src/bsync_core/drive.py`（`DriveClient` と索引の部分）。
library;

import 'package:karita_contract/errors.dart';
import 'package:karita_contract/json_reader.dart';

/// 書き込む空間。**「アプリ × ユーザ」単位**で、利用者のドライブ画面には現れない。
const String appDataSpace = 'appDataFolder';

/// 一覧の1ページの既定の大きさ。**Drive の上限の 1000 にする**（2026-10-08）。
///
/// 一覧は名前だけを持ち帰るので、1ページを大きくしても本文は増えない。1世代の封筒が
/// 1000 件に届くまでは、受信の一覧が1往復で済む。
const int defaultPageSize = 1000;

/// 索引に載せるキー。**正しさは常に封筒本文から読む。**
const String propEventId = 'eventId';
const String propEntityType = 'entityType';
const String propCreatedAtUtc = 'createdAtUtc';

/// 一覧で返る1件。**本文は含まない。**
class FileRef {
  final String fileId;
  final String name;
  final Map<String, String> appProperties;
  final int sizeBytes;

  const FileRef({
    required this.fileId,
    required this.name,
    this.appProperties = const {},
    this.sizeBytes = 0,
  });
}

/// 一覧の1ページ。`nextPageToken` が null になるまで繰り返す。
class DrivePage {
  final List<FileRef> files;
  final String? nextPageToken;

  const DrivePage(this.files, this.nextPageToken);
}

/// 二値を載せた結果。**載ったものを検算するための値を必ず持ち帰る。**
///
/// [md5] は保管先が返さないことがある。[sizeBytes] は二値ファイルなら必ず返る。**両方とも
/// 無い応答は「検算できなかった」であって成功ではない**（`DriveBackupStore`）。
class Uploaded {
  final String fileId;
  final String md5;
  final int sizeBytes;

  const Uploaded({required this.fileId, this.md5 = '', this.sizeBytes = 0});
}

/// `about.get` が返す接続先アカウントの素性。
///
/// **判定に使ってよいのは [permissionId] だけである。** 安定 ID で、
/// `drive.appdata` の scope で取れる（P5 単位 E の決着）。[emailAddress] は表示専用 —
/// 公式に「可視でない場合は返らない」と注記があるため null になりうる。
class DriveAccountInfo {
  final String permissionId;
  final String? emailAddress;
  final String? displayName;

  const DriveAccountInfo({
    required this.permissionId,
    this.emailAddress,
    this.displayName,
  });
}

abstract interface class DriveClient {
  /// 文字列を新しいファイルとして作る。**置き換えではない。**
  Future<String> create(
    String name,
    Map<String, String> appProperties,
    String text,
  );

  Future<DrivePage> listPage({String? pageToken, String? query});

  Future<String> getText(String fileId);

  Future<void> delete(String fileId);

  /// ローカルの [path] を二値として載せる。載ったものの検算に使う値を返す。
  Future<Uploaded> createBinary(
    String name,
    Map<String, String> appProperties,
    String path,
  );

  Future<void> download(String fileId, String destPath);

  Future<void> rename(String fileId, String name);

  /// 接続先アカウントの素性。**scope も OAuth クライアントも増やさない**
  /// （`drive.appdata` が受理する `about.get` の応答である）。
  Future<DriveAccountInfo> about();
}

/// `appProperties` に載せる索引を作る。
///
/// 載せるのは `eventId` / `entityType` / `createdAtUtc` の3つで、**サーバ側クエリと表示の
/// ためだけ**に使う。`schemaVersion` は載せない — 索引に置くと転送層が未対応版を弾く実装への
/// 誘惑が生まれ、受入ケース06（未対応版を捨てずに滞留させる）が成立しなくなる。
///
/// **本文が読めなくても送信は続ける。** 転送は封筒を解釈しないので、索引を作れないことは
/// 送らない理由にならない。
Map<String, String> indexProperties(String eventId, String text) {
  final properties = {propEventId: eventId};
  Object? obj;
  try {
    obj = loadsJson(text, label: '封筒');
  } on SyncDataError {
    return properties;
  }
  if (obj is! Map<String, Object?>) return properties;
  for (final key in const [propEntityType, propCreatedAtUtc]) {
    final value = obj[key];
    if (value is String && value.isNotEmpty) properties[key] = value;
  }
  return properties;
}

/// クエリ文字列に埋める値をエスケープする。
String escapeQueryValue(String value) =>
    value.replaceAll(r'\', r'\').replaceAll("'", r"\'");

/// 名前の前置でサーバ側から絞るクエリ。
///
/// **Drive の `contains` は名前に対して前方一致で働く**（2026-10-08 に実 Drive で確かめた。
/// 世代の前置 `event-<generationId>-` と `baseline-` で、余分なものを含まず1回で返る）。
/// 一覧のたびに `appDataFolder` の全ファイルを読まないためで、**呼び出し側は名前の判定を
/// 省かない** — 絞り込みは往復を減らすためのもので、正しさはこれに頼らない。
String namePrefixQuery(String prefix) =>
    "name contains '${escapeQueryValue(prefix)}'";

/// `eventId` でサーバ側から絞るクエリ。
String eventIdQuery(String eventId) =>
    "appProperties has { key='$propEventId' and value='${escapeQueryValue(eventId)}' }";
