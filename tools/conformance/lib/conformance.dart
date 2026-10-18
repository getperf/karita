/// runCanonical / runEnvelope / runSync を公開するバレル。
///
/// D1〜D3 の各段は、Python の contracts パッケージの検証に効く層だけを薄く写す。転送・適用
/// ループ・lease・SQLite は写さない。写した時点で第二の製品実装になり、言語差の検出器では
/// なくなる（非公開資料:dart-adversarial-validation.md 注意点10）。
library;

export 'src/repo.dart' show Repo;
export 'src/report.dart' show Report;
export 'src/run_canonical.dart' show runCanonical;
export 'src/run_envelope.dart' show runEnvelope;
export 'src/run_sync.dart' show runSync;
export 'src/update_goldens.dart' show GoldenUpdate, updateGoldens;
