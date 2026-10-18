/// マイグレーションの読み取り。**DB を要さない部分だけをここで測る。**
///
/// 適用（台帳・冪等・改竄検出）は `karita_sync` 側の試験にある。`karita_contract` は
/// `dart:ffi` を持たないので、この層の試験も SQLite を要求しない。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_contract/src/generated/migrations.g.dart';
import 'package:test/test.dart';

void main() {
  test('番号順に読め、名前が規則に合う', () {
    final found = discover();
    expect(found, isNotEmpty);
    expect(found.map((m) => m.version).toList(),
        equals(List.generate(found.length, (i) => i + 1)),
        reason: '版番号は 1 から連番の追記のみである');
    for (final m in found) {
      expect(m.filename, equals('${m.version.toString().padLeft(4, '0')}_${m.name}.sql'));
      expect(m.sql, isNotEmpty);
    }
  });

  test('チェックサムは LF 正規化後の内容の sha256 である', () {
    // **正本側（migrate._checksum）と同じ取り方でなければならない。** ここがずれると、
    // Python が作った DB を Dart が移行できなくなる（台帳のチェックサム不一致）。
    for (final m in discover()) {
      expect(m.checksum, equals('sha256:${sha256.convert(utf8.encode(m.sql))}'));
      expect(m.sql.contains('\r'), isFalse, reason: '取り込み時に LF へ正規化されている');
    }
  });

  test('名前が規則に合わなければ落とす', () {
    expect(() => discover({'init.sql': 'SELECT 1;'}), throwsA(isA<SyncDataError>()));
    expect(() => discover({'1_init.sql': 'SELECT 1;'}), throwsA(isA<SyncDataError>()));
  });

  test('版番号の重複を落とす', () {
    expect(
      () => discover({'0001_a.sql': 'SELECT 1;', '0001_b.sql': 'SELECT 2;'}),
      throwsA(isA<SyncDataError>()),
    );
  });

  test('生成物の版が最新版と一致する', () {
    expect(latestVersion(), equals(migrationSources.length));
  });
}
