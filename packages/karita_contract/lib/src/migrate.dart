/// マイグレーション。
///
/// **単一系列**とし、CLI や層ごとに分けない。番号は追記のみである。二系列にすると版番号が
/// 衝突する。
///
/// 各マイグレーションは、DDL と `schema_migrations` への記録を**同一トランザクション**で
/// 確定する。途中で例外が起きれば DDL も台帳も残らない。
///
/// **DDL も契約である。** 読むのは `migrations.g.dart`（凍結までは book-sync-model の
/// `src/contracts/migrations/*.sql` から取り込んだ生成物、いまは正本）で、素の SQL を番号順に
/// 適用して sha256 を台帳へ記録する。実行される SQL であると同時に同一性を
/// 持つデータである。
///
/// **同じ SQL を同じ順で実行すれば、Python が作った DB と Dart が作った DB は台帳まで含めて
/// 同一になる。** Python と Dart が同じ `.blib` を読み書きできるのは、この一致が土台である。
///
/// チェックサムは**改行を LF に正規化した内容**に対して取る。正本側（`migrate._checksum`）が
/// 同じ正規化をしており、取り込みも LF 正規化を通していたので、`migrationSources` の
/// テキストをそのままハッシュすれば両実装で同値になる。**SQL を足すときは LF で書くこと。**
///
/// 移送元: book-sync-model の `src/contracts/migrate.py`。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'db.dart';
import 'errors.dart';
import 'generated/migrations.g.dart';

/// 正本（book-sync-model）での位置。`migrationSources` のキーはここからのファイル名である。
const String migrationsDir = 'src/contracts/migrations';

final RegExp _filenameRe = RegExp(r'^(\d{4})_([A-Za-z0-9_-]+)\.sql$');

class Migration {
  final int version;
  final String name;
  final String filename;
  final String sql;
  final String checksum;

  const Migration({
    required this.version,
    required this.name,
    required this.filename,
    required this.sql,
    required this.checksum,
  });
}

class AppliedRow {
  final int version;
  final String name;
  final String appliedAtUtc;
  final String checksum;

  const AppliedRow(this.version, this.name, this.appliedAtUtc, this.checksum);
}

String migrationChecksum(String sql) =>
    'sha256:${sha256.convert(utf8.encode(sql))}';

/// 同梱のマイグレーションを番号順に読む。
List<Migration> discover([Map<String, String>? sources]) {
  final source = sources ?? migrationSources;
  final found = <Migration>[];
  final seen = <int, String>{};
  for (final filename in source.keys.toList()..sort()) {
    final match = _filenameRe.firstMatch(filename);
    if (match == null) {
      throw SyncDataError('マイグレーション名が不正です: $filename（NNNN_name.sql）',
          code: 'migration');
    }
    final version = int.parse(match.group(1)!);
    final duplicate = seen[version];
    if (duplicate != null) {
      throw SyncDataError('版番号が重複しています: $version（$duplicate と $filename）',
          code: 'migration');
    }
    seen[version] = filename;
    final sql = source[filename]!;
    found.add(Migration(
      version: version,
      name: match.group(2)!,
      filename: filename,
      sql: sql,
      checksum: migrationChecksum(sql),
    ));
  }
  found.sort((a, b) => a.version.compareTo(b.version));
  return found;
}

int latestVersion([Map<String, String>? sources]) {
  final found = discover(sources);
  return found.isEmpty ? 0 : found.last.version;
}

/// 適用済みの台帳。**台帳自体が 0001 で作られる**ため、無ければ空とみなす。
Map<int, AppliedRow> applied(Db db) {
  if (!tableExists(db, 'schema_migrations')) return const {};
  final rows = db.select(
      'SELECT version, name, applied_at_utc, checksum FROM schema_migrations ORDER BY version');
  return {
    for (final row in rows)
      row['version'] as int: AppliedRow(
        row['version'] as int,
        row['name'] as String,
        row['applied_at_utc'] as String,
        row['checksum'] as String,
      ),
  };
}

int currentVersion(Db db) {
  final rows = applied(db);
  return rows.isEmpty ? 0 : rows.keys.reduce((a, b) => a > b ? a : b);
}

/// 適用後に SQL を書き換えた事故を検出する。
List<String> checksumMismatches(Db db, [Map<String, String>? sources]) {
  final known = {for (final m in discover(sources)) m.version: m};
  final problems = <String>[];
  final rows = applied(db);
  for (final version in rows.keys.toList()..sort()) {
    final migration = known[version];
    if (migration == null) {
      problems.add('適用済みの ${_pad(version)} に対応する SQL が同梱にありません');
    } else if (migration.checksum != rows[version]!.checksum) {
      problems.add('${migration.filename} が適用後に変更されています（チェックサム不一致）');
    }
  }
  return problems;
}

/// 未適用のものだけを順に適用する。再実行は冪等。
List<Migration> migrate(Db db, {required String now, Map<String, String>? sources}) {
  for (final problem in checksumMismatches(db, sources)) {
    throw SyncDataError(problem, code: 'migration');
  }

  final done = applied(db);
  final pending = [for (final m in discover(sources)) if (!done.containsKey(m.version)) m];
  for (final migration in pending) {
    _applyOne(db, migration, now: now);
  }
  return pending;
}

/// DDL と台帳の記録を同一トランザクションで確定する。
void _applyOne(Db db, Migration migration, {required String now}) {
  transaction(db, () {
    db.executeScript(migration.sql);
    db.execute(
      'INSERT INTO schema_migrations (version, name, applied_at_utc, checksum) '
      'VALUES (?, ?, ?, ?)',
      [migration.version, migration.name, now, migration.checksum],
    );
  });
}

String _pad(int version) => version.toString().padLeft(4, '0');
