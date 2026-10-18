/// ドメイン定数。**スキーマから読めないものだけ**を置く。
///
/// 封筒スキーマに書いてある値（受理する版・発行する版・`entityType` / `operation` の enum）は
/// ここに写さない。写すと Dart が読む定義と Python が使う定義が二本になり、ずれても両方の
/// テストが自分の正本に対して緑になる。それらは `Contracts` が schema から読む。
///
/// これらは業務上の決定であり、環境ごとに変わる値ではない。設定で上書きできるようにすると、
/// 同じコマンド列が実行環境によって違う結果を出し、ゴールデンが成立しなくなる。
///
/// 移送元: book-sync-model の `src/contracts/constants.py`（スキーマから読めない分だけ）。
library;

const String entityBook = 'book';
const String entityBookPreference = 'book_preference';
const String entityBookReview = 'book_review';
const String entityLoan = 'loan';
const String entityLibraryMembership = 'library_membership';
const String entityLibrarySetting = 'library_setting';
const String entityLibrarySystem = 'library_system';

/// ② が扱う集約。業務側の集約定義の変更から同期を守るための制約である。
///
/// **7つである**（0012でBookPreference、0013でBookReviewを追加）。4つだったところへ `0011` で
/// [entityLibrarySetting] を足した — 常用館とマイページ URL をカタログの集約から出すためで
/// ある（`非公開資料:libraries-in-sqlite.md` 2c）。**数を増やすのは取り決めの変更で
/// あり、封筒の enum を書き換える。**
const List<String> syncedEntityTypes = [
  entityBook,
  entityBookPreference,
  entityBookReview,
  entityLoan,
  entityLibraryMembership,
  entityLibrarySetting,
  entityLibrarySystem,
];

/// 削除は tombstone イベントで表し、同期済みの業務データを物理削除しない。
/// Loan から参照される Book の tombstone は適用するが、Loan は残す。
const List<String> tombstoneEntityTypes = [
  'book',
  'book_preference',
  // 設定の解除は tombstone で表す。payload は system_id と key だけになる。
  'library_setting',
  'library_system',
  'reading_record',
];

/// 同期テーブルへの書込み元。所有違反の検査に使う（検査そのものは業務モデルの移送と同時に
/// 入れる）。
const String appBsync = 'bsync';
const String appBops = 'bops';

const String operationUpsert = 'upsert';
const String operationTombstone = 'tombstone';

const String outboxPending = 'pending';
const String outboxUploading = 'uploading';
const String outboxUploaded = 'uploaded';
const String outboxRetryWait = 'retry_wait';
const String outboxBlockedAuth = 'blocked_auth';
const String outboxBlockedConflict = 'blocked_conflict';
const List<String> outboxStates = [
  outboxPending,
  outboxUploading,
  outboxUploaded,
  outboxRetryWait,
  outboxBlockedAuth,
  outboxBlockedConflict,
];

/// 送信中の outbox 行を押さえる lease の長さ。**設定にしない。**
/// 短すぎると遅い回線で送信中の行を別プロセスが奪い、長すぎると落ちたプロセスの後始末が遅れる。
/// 守るのは「同じ DB を触る別プロセス」であって端末ではないため、保持者は run_id である。
const int leaseSeconds = 900;

const String originLocal = 'local';
const String originRemote = 'remote';

const List<String> pendingReasons = ['gap', 'schema'];

const String conflictOpen = 'open';
const String conflictResolved = 'resolved';
