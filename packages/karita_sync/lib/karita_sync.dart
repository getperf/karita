/// ② 同期エンジン。SQLite、outbox、適用判定、LWW、バックアップ、同期世代、転送 port。
///
/// **転送と認可は port として定義するだけで実装を持たない**（実装は `karita_platform`、
/// `dir` 相当は試験側）。純 Dart に保つ — Flutter に依存すると conformance runner と単体試験が
/// Dart VM で回らなくなる。
///
/// **`karita_domain` に依存しない。** 業務から同期への経路は outbox 追記の一点だけであり、
/// それは `karita_contract` にある。
library;

export 'src/apply.dart';
export 'src/backup_archive.dart';
export 'src/backup_store.dart';
export 'src/db_session.dart';
export 'src/doctor.dart';
export 'src/driver.dart';
export 'src/engine.dart';
export 'src/faults.dart';
export 'src/fixtures.dart';
export 'src/generation.dart';
export 'src/plan.dart';
export 'src/push.dart';
export 'src/sqlite_db.dart';
export 'src/status.dart';
export 'src/store.dart';
export 'src/transport.dart';
