/// DB ファイルへの接続を**開き直せる**形で持つ。
///
/// 復元は DB ファイルを丸ごと置換する。置換の前に開いていた接続は、置換の後は別のファイル
/// （消えた古い実体）を指したままになる。**復元を持つ以上、接続を握りっぱなしにできない。**
///
/// メモリ DB も扱えるようにしてあるのは、適用や判定の単体試験がファイルを要らないためである。
/// メモリ DB は置換できないので [reopen] は落とす — 黙って何もしないと、復元したつもりの試験が
/// 古い内容のまま緑になる。
library;

import 'package:karita_contract/karita_contract.dart';

import 'sqlite_db.dart';

class DbSession {
  /// DB ファイルの場所。メモリ DB では null。
  final String? path;
  SqliteDb _db;

  DbSession._(this.path, this._db);

  /// ファイルの DB を開き、マイグレーションは呼び出し側に任せる。
  factory DbSession.open(String path) => DbSession._(path, SqliteDb.open(path));

  /// メモリ上の DB。単体試験用。**復元はできない。**
  factory DbSession.memory() => DbSession._(null, SqliteDb.memory());

  Db get db => _db;

  SqliteDb get sqlite => _db;

  /// 置換されたファイルを開き直す。**復元の直後に必ず呼ぶ。**
  void reopen() {
    final target = path;
    if (target == null) {
      throw SyncDataError(
        'メモリ DB は置換できません。復元にはファイルの DB が要ります。',
        code: 'db-memory',
      );
    }
    _db.close();
    _db = SqliteDb.open(target);
  }

  /// 復元がファイルを置換する前に接続を手放す。Windows では開いたままのファイルを置換できない。
  void detach() {
    if (path == null) return;
    _db.close();
  }

  void close() => _db.close();
}
