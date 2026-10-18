/// fixture と golden の唯一の入口。
///
/// 読むのは `tools/conformance/data/` である。**2026-09-02 の凍結でここが正本になった** —
/// それまでは book-sync-model から取り込む生成物で、`PROVENANCE.json` の sha256 が手編集を
/// 赤にしていた。生成器も出所検査も凍結と同時に消えている。
///
/// **golden を書き換えるときは `conformance update-goldens --write` を通すこと。** 手で直すと、
/// manifest の sha256 と本体が食い違ったまま D1 だけが緑になる経路ができる。
///
/// schema はここから読まない。実行時 schema は `karita_contract` が生成定数として持つ
/// （AOT では `package:` URI をファイルパスへ解決できないため）。
///
/// 実行時のカレントに依存しないよう、data のルートを `--repo-root`（既定はパッケージ内の
/// `data/`）で受け、そこからの相対で開く。
library;

import 'dart:io';
import 'dart:typed_data';

class Repo {
  final Directory root;

  Repo(this.root);

  /// パッケージ内の `data/` を既定のルートにする。実行時のカレントに依存しない。
  ///
  /// **親を数えない。** `dart run` はスナップショットを `.dart_tool/pub/bin/` の下に置き、
  /// `dart test` はテストランナーを指すため、階層の数が実行方法で変わる。workspace の
  /// `pubspec.yaml` を目印に上へ辿る。
  factory Repo.fromDefault(Uri scriptUri) => Repo(dataRoot(scriptUri));

  /// 生成物の置き場。`<core>/tools/conformance/data`。
  static Directory dataRoot([Uri? from]) {
    final core = coreRoot(from);
    final sep = Platform.pathSeparator;
    return Directory('${core.path}${sep}tools${sep}conformance${sep}data');
  }

  /// karita-core のルート。workspace の `pubspec.yaml` を目印に上へ辿る。
  static Directory coreRoot([Uri? from]) {
    var dir = from != null
        ? File.fromUri(from).parent
        : Directory.current;
    for (var i = 0; i < 10; i++) {
      final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
      if (pubspec.existsSync() &&
          pubspec.readAsStringSync().contains('karita_core_workspace')) {
        return dir;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    throw StateError('karita-core のルートが見つかりません'
        '（workspace の pubspec.yaml を探しました）。');
  }

  File file(String relative) => File('${root.path}${Platform.pathSeparator}${_native(relative)}');

  String readString(String relative) => file(relative).readAsStringSync();

  Uint8List readBytes(String relative) => file(relative).readAsBytesSync();

  bool exists(String relative) => file(relative).existsSync();

  List<String> listJson(String relativeDir) {
    final dir = Directory('${root.path}${Platform.pathSeparator}${_native(relativeDir)}');
    if (!dir.existsSync()) return const [];
    final names = <String>[];
    for (final entry in dir.listSync()) {
      if (entry is File && entry.path.endsWith('.schema.json')) {
        names.add(entry.uri.pathSegments.last);
      }
    }
    names.sort();
    return names;
  }

  static String _native(String relative) =>
      relative.replaceAll('/', Platform.pathSeparator);
}
