/// ① 契約。正準化・封筒・検証・適用判定表と、**テーブル定義・マイグレーション・
/// outbox 追記ヘルパ**。
///
/// schema と migrations は `lib/src/generated/` にある。**2026-09-02 の凍結でここが正本に
/// なった** — それまでは book-sync-model から取り込む生成物で、`PROVENANCE.json` の sha256 が
/// 手編集を赤にしていた。**いま内容を縛るものは無い。** ずれを捕まえるのは相互運用の試験
/// （`blib_interop_test` と `drive_interop_test`）だけである。
///
/// **業務（`karita_domain`）と同期（`karita_sync`）の両方がここに依存する。** Python の
/// `contracts` に対応する形をそのまま写したものであり、接合点は outbox の一点
/// （[appendLocalEmission]）である。
///
/// このパッケージは `dart:io` も `dart:ffi` も持たず、Flutter にも依存しない。SQLite への口は
/// [Db] という最小のインタフェースとして宣言するだけで、`package:sqlite3` に触るのは
/// `karita_sync` の `SqliteDb` である。conformance runner と単体試験が Dart VM で回る状態を
/// 保つためである。
///
/// 接頭辞を付けて使いたい場合は、`package:karita_contract/canonical.dart` のように
/// モジュール単位の口がある。
library;

export 'src/aggregates.dart';
export 'src/backup.dart';
export 'src/canonical.dart';
export 'src/constants.dart';
export 'src/db.dart';
export 'src/decide.dart';
export 'src/envelope.dart';
export 'src/errors.dart';
export 'src/identity.dart';
export 'src/ids.dart';
export 'src/json_reader.dart';
export 'src/mapping.dart';
export 'src/migrate.dart';
export 'src/schema.dart';
export 'src/sync_tables.dart';
