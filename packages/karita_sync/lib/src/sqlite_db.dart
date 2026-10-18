/// `karita_contract` の [Db] を `package:sqlite3`（FFI）で実装する。
///
/// **生 SQL を実行する。drift を採らない。** DDL の正本は外部（book-sync-model の
/// `migrations/*.sql`）にあり、DSL でテーブルを定義すると `0001_init.sql` と Dart 側の定義という
/// **第二のスキーマ定義**ができる。P0 で避けた「正本が二本になる」と同型の失敗である。
///
/// **`package:sqlite3` に触るのはここだけである。** `karita_contract` を `dart:ffi` から遠ざけ、
/// 業務層が SQLite の型に縛られないようにする。
///
/// **ネイティブライブラリの供給**: `package:sqlite3` 3.x は
/// [build hooks](https://dart.dev/tools/hooks) で SQLite をアプリへ同梱する。**出所を選ぶ口は
/// 無く、`dart:ffi` も要らない** — 2.x の `open.overrideFor`（と、それを包んでいた
/// `overrideWindowsLibrary()`）は上流で削除された。Windows が OS 同梱の `winsqlite3.dll` を
/// 読んでいたのも、Android に `sqlite3_flutter_libs` が要ったのも 2.x までで、**どちらの供給も
/// いまは hooks の側にある**（P5a で上げ替えた）。
library;

import 'package:karita_contract/db.dart';
import 'package:sqlite3/sqlite3.dart';

class SqliteDb implements Db {
  final Database raw;

  SqliteDb._(this.raw);

  /// ファイルの DB を開く。
  ///
  /// PRAGMA の方針は `karita_contract` の `db.dart` にある。`foreign_keys=OFF` は集約間参照に
  /// 外部キー制約を張らないためで、イベントが順不同で到着する間、参照先が一時的に存在しない
  /// のは異常ではなく正常な途中状態である。
  factory SqliteDb.open(String path) => SqliteDb._(_configure(sqlite3.open(path)));

  /// メモリ上の DB。単体試験用。**WAL は効かない**（`journal_mode` は memory のまま）。
  factory SqliteDb.memory() => SqliteDb._(_configure(sqlite3.openInMemory()));

  static Database _configure(Database db) {
    db.execute('PRAGMA busy_timeout = $busyTimeoutMs');
    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('PRAGMA journal_mode = WAL');
    return db;
  }

  @override
  void execute(String sql, [List<Object?> params = const []]) =>
      raw.execute(sql, params);

  @override
  void executeScript(String sql) => raw.execute(sql);

  @override
  List<Map<String, Object?>> select(String sql, [List<Object?> params = const []]) =>
      [for (final row in raw.select(sql, params)) Map<String, Object?>.from(row)];

  String get journalMode =>
      (raw.select('PRAGMA journal_mode').first.values.first as String).toLowerCase();

  void close() => raw.close();
}
