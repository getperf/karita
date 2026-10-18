/// 転送先をローカルディレクトリに見立てる `TransportPort` の実装。
///
/// **試験側が持つ。** 実 Drive の adapter は `karita_platform` が P2 で持ち、`karita_sync` は
/// port の定義しか持たない。`dir` は置き場をローカルディレクトリに見立てただけのもので、
/// 生成された JSON をそのまま読めるため gap と conflict の分岐を目で追える。
///
/// **転送は封筒を解釈しない。** 生の文字列を運ぶだけで、検証も適用も呼び出し側が行う。壊れた
/// 封筒を転送層で捨てると、受信側が「取り込めないイベントを破棄しない」を守れなくなる。
/// 名前で絞るのは封筒の解釈ではなく、転送先の中で自分の名前空間（世代）を決めているだけである。
library;

import 'dart:io';

import 'package:karita_contract/errors.dart';
import 'package:karita_sync/karita_sync.dart';

class DirTransport implements DuplicatingTransport {
  final Directory root;
  final String generationId;

  DirTransport(this.root, this.generationId);

  @override
  String get kind => transportDir;

  File _path(String eventId) =>
      File('${root.path}${Platform.pathSeparator}${eventName(generationId, eventId)}');

  /// 決定的なファイル名へ書く。
  ///
  /// 再送は同名への上書きになるため無害である。実 Drive は同名の重複作成を許すので、この一類は
  /// `dir` では現れない。重複排除は [list] に持たせ、検証は P2（受入ケース07・08）で行う。
  @override
  Future<String> put(String eventId, String text) async {
    root.createSync(recursive: true);
    final file = _path(eventId);
    // **改行変換をしない。** 正準化後のバイト列そのものが運ばれるものである。
    file.writeAsStringSync(text, flush: true);
    return file.uri.pathSegments.last;
  }

  /// 転送先の全件を整列し、`eventId` で重複を落として返す。
  ///
  /// ファイル名が違っても `eventId` が同じなら同一のイベントである。名前一致ではなく `eventId`
  /// で数える。**重複排除は整列の後で行う** — 順序に依存させないためである。
  @override
  Future<List<RemoteEvent>> list({KnownEvent? known}) async {
    if (!root.existsSync()) return const [];
    final found = <RemoteEvent>[];
    final entries = root.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in entries) {
      final name = file.uri.pathSegments.last;
      if (!isEventName(name, generationId)) continue;
      // **名前の ID で既知なら読まない**（Drive 転送と同じ規則）。
      final named = eventIdOfName(name, generationId);
      if (known != null && named != null && known(named)) continue;
      final String text;
      try {
        text = file.readAsStringSync();
      } on FileSystemException catch (exc) {
        throw SyncDataError('封筒を読めません: ${file.path} ($exc)', code: 'transport-io');
      }
      final ids = peekIds(text);
      found.add(RemoteEvent(
        remoteId: name,
        eventId: ids.eventId,
        text: text,
        createdAtUtc: ids.createdAtUtc,
      ));
    }
    found.sort(compareRemote);
    return dedupe(found);
  }

  /// `eventId` で1件を引く。
  ///
  /// ファイル名で絞らず一覧から探す。`dir` では全件走査の費用が問題にならず、**一覧と検索が
  /// 必ず同じ結果を返す**ことの方が重要である。ファイル名は決定的だが、名前と中身がずれた
  /// ファイルを名前で引くと、[list] が見つけるものを [find] が見落とす。
  @override
  Future<RemoteEvent?> find(String eventId) async =>
      firstMatching(await list(), eventId);
  /// 同じ `eventId` で、別の名前の実体をもう1つ作る。**故障注入だけが呼ぶ。**
  ///
  /// 置き換えの無い保管先では同名の実体が2つできるが、`dir` は名前が実体の識別子なので、
  /// 同じ状態を作るには名前を変えるしかない。**`event-<世代>-<eventId>--<n>.json`** にすると、
  /// 名前の規則（前置と拡張子）を満たしたまま別の実体になり、一覧には出て `eventId` で畳まれる。
  /// 連番は転送先にあるものを数えて決めるので、プロセスをまたいでも衝突しない。
  @override
  Future<String> putDuplicate(String eventId, String text) async {
    root.createSync(recursive: true);
    final stem = '${generationPrefix(generationId)}$eventId--';
    final existing = root
        .listSync()
        .whereType<File>()
        .where((entry) => entry.uri.pathSegments.last.startsWith(stem))
        .length;
    final name = '$stem${existing + 1}$filenameSuffix';
    File('${root.path}${Platform.pathSeparator}$name')
        .writeAsStringSync(text, flush: true);
    return name;
  }


  @override
  Future<void> delete(String remoteId) async {
    final file = File('${root.path}${Platform.pathSeparator}$remoteId');
    if (file.existsSync()) file.deleteSync();
  }
}
