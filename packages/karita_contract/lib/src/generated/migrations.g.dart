// **正本である。** 2026-09-02 の凍結まで book-sync-model から取り込む生成物だったが、
// 凍結で正本がここへ移り、生成器（tools/contract_sync）と出所検査は消えた。
//
// **直すときは規則を先に決めること。** ここは Python と Dart が同じ内容を読むという性質を
// 失っており、ハッシュで縛るものが無い。ずれを捕まえるのは相互運用の試験だけである
// （tools/conformance の blib_interop_test と drive_interop_test）。
//
// ignore_for_file: lines_longer_than_80_chars
library;

/// `src/contracts/migrations/` のファイル名 → SQL の生テキスト（改行は LF）。
///
/// 番号順に適用し、sha256 を `schema_migrations` へ記録する。同じ SQL を同じ順で
/// 実行すれば、Python が作った DB と Dart が作った DB は台帳まで含めて同一になる。
const Map<String, String> migrationSources = {
  '0001_init.sql': r'''
-- 0001 基盤。マイグレーション台帳と、DB自身の素性を持つ key/value。
--
-- 業務集約（books, loans）と同期テーブル（outbox, applied_events, pending_events,
-- conflicts）は S1 が 0002 で追加する。残り5集約は O1 が bops として追加する。
-- 番号は追記のみとし、CLIごとに別系列を持たない。二系列にすると版番号が衝突する。

CREATE TABLE schema_migrations (
  version        INTEGER PRIMARY KEY,
  name           TEXT    NOT NULL,
  applied_at_utc TEXT    NOT NULL,
  checksum       TEXT    NOT NULL
);

CREATE TABLE sync_state (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''',
  '0002_aggregates_and_sync.sql': r'''
-- 0002 業務集約（Book / Loan）と同期テーブル。
--
-- bsync が扱う集約は Book と Loan に限る。bops の集約定義はこれから変わるため、共有DB上で
-- bsync を守るための制約である。残り5集約は O1 で bops が 0003 以降に追加する。
--
-- 集約間参照に外部キー制約を張らない。イベントが順不同で到着する間、参照先が一時的に
-- 存在しないのは異常ではなく正常な途中状態である（architecture/static-model.md）。
--
-- 同期対象の全集約は version / updated_at_utc / updated_by_device_id を持つ。version だけでは
-- 実体を識別できない。版の同一性は (version, updated_by_device_id)、内容の同一性は payload_hash
-- で判定する。

CREATE TABLE books (
  id                   TEXT    PRIMARY KEY,
  title                TEXT,
  authors              TEXT    NOT NULL DEFAULT '[]',
  isbn13               TEXT,
  publisher            TEXT,
  published_on         TEXT,
  memo                 TEXT,
  book_references      TEXT    NOT NULL DEFAULT '[]',
  -- tombstone を許すのは Book だけである。同期済みの業務データを物理削除しない。
  is_deleted           INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
  version              INTEGER NOT NULL,
  updated_at_utc       TEXT    NOT NULL,
  updated_by_device_id TEXT    NOT NULL
);

CREATE TABLE loans (
  id                   TEXT    PRIMARY KEY,
  book_id              TEXT    NOT NULL,
  system_id            TEXT,
  -- 受取館・借出館。館を分館単位で区別しない場合は空でよい。
  library_id           TEXT,
  status               TEXT    NOT NULL CHECK (
                         status IN ('reserved', 'ready_for_pickup', 'borrowed',
                                    'returned', 'cancelled', 'expired')),
  reserved_on          TEXT,
  pickup_available_on  TEXT,
  pickup_due_on        TEXT,
  borrowed_on          TEXT,
  due_on               TEXT,
  returned_on          TEXT,
  cancelled_on         TEXT,
  note                 TEXT,
  version              INTEGER NOT NULL,
  updated_at_utc       TEXT    NOT NULL,
  updated_by_device_id TEXT    NOT NULL
);

CREATE INDEX idx_loans_book ON loans (book_id);

-- 同期テーブル。
--
-- written_by_app は所有違反の検査に使う。DBを共有すると bops から conflicts へSQLで書くことが
-- 物理的に可能になり、import lint では検出できない。contracts の書込みヘルパだけがこの列を
-- 押印し、admin doctor が違反行を報告する。生SQLで直接書かれた行は空文字になるため同じ検査に
-- 掛かる（validation/project-structure.md のテーブル所有）。

CREATE TABLE outbox_events (
  event_id             TEXT    PRIMARY KEY,
  device_id            TEXT    NOT NULL,
  created_at_utc       TEXT    NOT NULL,
  entity_type          TEXT    NOT NULL,
  entity_id            TEXT    NOT NULL,
  operation            TEXT    NOT NULL CHECK (operation IN ('upsert', 'tombstone')),
  base_version         INTEGER NOT NULL,
  result_version       INTEGER NOT NULL,
  payload_hash         TEXT    NOT NULL,
  resolves_event_ids   TEXT    NOT NULL DEFAULT '[]',
  -- 正準化後のバイト列そのもの。再送時のハッシュ照合はこれを使う。
  payload              TEXT    NOT NULL,
  state                TEXT    NOT NULL CHECK (
                         state IN ('pending', 'uploading', 'uploaded', 'retry_wait',
                                   'blocked_auth', 'blocked_conflict')),
  attempts             INTEGER NOT NULL DEFAULT 0,
  -- uploading の lease。失効した場合は pending に回復する（S4）。
  lease_owner          TEXT,
  lease_expires_at_utc TEXT,
  remote_file_id       TEXT,
  last_error           TEXT,
  updated_at_utc       TEXT    NOT NULL,
  written_by_app       TEXT    NOT NULL DEFAULT ''
);

CREATE INDEX idx_outbox_state ON outbox_events (state);

-- event_id の一意制約と業務反映を同一トランザクションにする。受信イベントの冪等はこの
-- 主キーが担保する。origin='local' は自端末が発行したイベントで、Drive から自分のイベントを
-- 引き戻したときに再適用しないために記録する。
CREATE TABLE applied_events (
  event_id             TEXT    PRIMARY KEY,
  entity_type          TEXT    NOT NULL,
  entity_id            TEXT    NOT NULL,
  result_version       INTEGER NOT NULL,
  payload_hash         TEXT    NOT NULL,
  origin               TEXT    NOT NULL CHECK (origin IN ('local', 'remote')),
  applied_at_utc       TEXT    NOT NULL,
  written_by_app       TEXT    NOT NULL DEFAULT ''
);

CREATE INDEX idx_applied_entity ON applied_events (entity_type, entity_id);

-- 取り込めないイベントを破棄しない。reason='schema' では封筒の形自体が未知でありうるため、
-- 受信した封筒の生文字列を正本とし、解析済みの列は NULL 可にする。
CREATE TABLE pending_events (
  event_id             TEXT    PRIMARY KEY,
  reason               TEXT    NOT NULL CHECK (reason IN ('gap', 'schema')),
  entity_type          TEXT,
  entity_id            TEXT,
  base_version         INTEGER,
  envelope             TEXT    NOT NULL,
  received_at_utc      TEXT    NOT NULL,
  written_by_app       TEXT    NOT NULL DEFAULT ''
);

CREATE INDEX idx_pending_reason ON pending_events (reason);

-- 競合を黙って上書きしない。解決結果は必ず新しいイベントとして確定し、resolution_event_id に
-- 記録する。
CREATE TABLE conflicts (
  conflict_id           TEXT    PRIMARY KEY,
  entity_type           TEXT    NOT NULL,
  entity_id             TEXT    NOT NULL,
  local_version         INTEGER NOT NULL,
  local_payload_hash    TEXT,
  remote_event_id       TEXT    NOT NULL,
  remote_base_version   INTEGER NOT NULL,
  remote_result_version INTEGER NOT NULL,
  remote_envelope       TEXT    NOT NULL,
  state                 TEXT    NOT NULL CHECK (state IN ('open', 'resolved')),
  detected_at_utc       TEXT    NOT NULL,
  resolved_at_utc       TEXT,
  resolution_event_id   TEXT,
  written_by_app        TEXT    NOT NULL DEFAULT ''
);

CREATE INDEX idx_conflicts_state ON conflicts (state);
''',
  '0003_sync_runs.sql': r'''
-- 0003 転送の観測（sync_runs / sync_event_attempts）と、競合のローカル側 eventId。
--
-- S1 の時点では転送が無く、run という単位が存在しなかった。S3 で push / pull が入るため足す。
--
-- sync_runs は**観測用であって原子性の単位ではない**。1受信イベント = 1トランザクションであり、
-- run の途中でプロセスが落ちても、そこまでに適用された分は確定している。run 全体を一つの
-- トランザクションにすると、受入ケース11 の「再生途中のプロセス終了からの再開」が成立しない
-- （validation/s3-sync-validation.md）。

CREATE TABLE sync_runs (
  run_id           TEXT    PRIMARY KEY,
  started_at_utc   TEXT    NOT NULL,
  finished_at_utc  TEXT,
  transport        TEXT    NOT NULL,
  -- push / pull / run のどれとして起動したか。
  mode             TEXT    NOT NULL CHECK (mode IN ('push', 'pull', 'run')),
  pushed           INTEGER NOT NULL DEFAULT 0,
  fetched          INTEGER NOT NULL DEFAULT 0,
  applied          INTEGER NOT NULL DEFAULT 0,
  ignored          INTEGER NOT NULL DEFAULT 0,
  pending          INTEGER NOT NULL DEFAULT 0,
  conflicted       INTEGER NOT NULL DEFAULT 0,
  invalid          INTEGER NOT NULL DEFAULT 0,
  outcome          TEXT    NOT NULL DEFAULT 'running'
                     CHECK (outcome IN ('running', 'ok', 'error')),
  written_by_app   TEXT    NOT NULL DEFAULT ''
);

CREATE INDEX idx_sync_runs_started ON sync_runs (started_at_utc);

-- 1イベントを1回扱った記録。判定表のどの行に落ちたかを残す。gap と conflict は入力の形が
-- 同じで結果が逆であるため、どちらに落ちたかを後から追えないと切り分けができない。
--
-- 同じ run で同じイベントを二度扱うことはない（pending の再走査は run 内で複数回起こりうるが、
-- 進んだものは applied_events に入り再走査の対象から外れる）。複合主キーで重複を止める。
CREATE TABLE sync_event_attempts (
  run_id           TEXT    NOT NULL,
  event_id         TEXT    NOT NULL,
  direction        TEXT    NOT NULL CHECK (direction IN ('push', 'pull')),
  -- 判定表の行に対応する。invalid は封筒が壊れていた場合で、その1件だけを弾き run は止めない。
  outcome          TEXT    NOT NULL CHECK (
                     outcome IN ('uploaded', 'applied', 'ignored', 'pending_gap',
                                 'pending_schema', 'conflict', 'invalid', 'error')),
  detail           TEXT,
  at_utc           TEXT    NOT NULL,
  written_by_app   TEXT    NOT NULL DEFAULT '',
  PRIMARY KEY (run_id, event_id, direction)
);

CREATE INDEX idx_attempts_event ON sync_event_attempts (event_id);

-- 解決イベントの resolvesEventIds は「決着させた双方の eventId」である。リモート側は
-- conflicts.remote_event_id にあるが、ローカル側は無かった。
--
-- 解決時に applied_events から result_version で引き直す方法は取らない。版の同一性は
-- (version, updated_by_device_id) であって version だけではなく、同じ result_version を持つ
-- 他端末の行と取り違える。検出した時点で確定させておく。
ALTER TABLE conflicts ADD COLUMN local_event_id TEXT;
''',
  '0004_loan_operations.sql': r'''
-- bops の Loan 操作。旧 library_id は読み取り互換のため残す。
ALTER TABLE loans ADD COLUMN pickup_library_id TEXT;
ALTER TABLE loans ADD COLUMN loan_library_id TEXT;

-- DomainEvent は監査用の業務記録で、同期用の outbox とは別物である。
CREATE TABLE domain_events (
  event_id        TEXT PRIMARY KEY,
  event_type      TEXT NOT NULL,
  aggregate_type  TEXT NOT NULL,
  aggregate_id    TEXT NOT NULL,
  occurred_at_utc TEXT NOT NULL,
  device_id       TEXT NOT NULL,
  payload_json    TEXT NOT NULL
);

-- 図書館システム単位の巡回完了記録。Loan の更新とは独立した事実である。
CREATE TABLE library_memberships (
  system_id              TEXT PRIMARY KEY,
  last_reconciled_at_utc TEXT
);
''',
  '0005_library_membership_sync.sql': r'''
-- 0005 LibraryMembership を同期集約へ昇格させる（O6）。
--
-- 棚卸完了（last_reconciled_at_utc）は端末ごとの事実ではなく、その図書館システムを確認し
-- 終えたという一つの事実である。0004 の表は system_id を主キーに持つローカル表で、版列も
-- outbox も無いため、完了が端末をまたがず同じシステムを二度巡回する。
--
-- 集約IDは uuid5(namespace, system_id) である。entityId は uuid でなければならず、system_id を
-- そのまま使えない。決定的に導くことで、二端末が別々に完了しても同じ id を指して競合として
-- 立ち、LWW が解決する（architecture/bops-sync-alignment.md）。
--
-- **uuid5 は SQL で計算できないため、旧行をここで運べない。** 旧表は改名して残す。復元は
-- `bops patrol complete --system-id <id> --now <保存されていた時刻>` で行う。SQL で行だけ作ると
-- outbox イベントの無い集約になり、相手端末に永久に届かない。
ALTER TABLE library_memberships RENAME TO library_memberships_local_v1;

-- system_id に UNIQUE を張らない。名前空間のずれた実装から別 id の行が届いたとき、UNIQUE 違反は
-- 適用経路を SQLite のエラーで止め、「取り込めないイベントを破棄しない」と収束の両方を壊す。
-- 重複は admin doctor が報告する。
CREATE TABLE library_memberships (
  id                     TEXT    PRIMARY KEY,
  system_id              TEXT    NOT NULL,
  last_reconciled_at_utc TEXT    NOT NULL,
  version                INTEGER NOT NULL,
  updated_at_utc         TEXT    NOT NULL,
  updated_by_device_id   TEXT    NOT NULL
);

CREATE INDEX idx_library_memberships_system ON library_memberships (system_id);
''',
  '0006_envelope_v2.sql': r'''
-- 0006 封筒の版2を受理する（S7-1）。
--
-- 版2で増えるのは entityType の synced_file と、任意項目 domainEventType である。前者は
-- 集約の表を要するため 0007 に置く。ここで足すのは outbox 側の一列だけである。
--
-- **発行と送信の間で落とさない。** domainEventType を outbox に持たせないと、封筒に載せたつもりの
-- 値が発行から送信までの間に静かに消える。同期層はこの値を解釈しないが、運ぶ責任はある
-- （docs/architecture/bops-sync-alignment.md の「DomainEvent は端末ローカルである」）。
--
-- schemaVersion の列は足さない。outbox に入るのは自端末が発行した封筒だけで、発行版は常に一つ
-- である。発行版を上げた後に未送信の行が残れば新しい版として送られるが、eventId も payloadHash も
-- 変わらないため受信側の判定は同じである。

ALTER TABLE outbox_events ADD COLUMN domain_event_type TEXT;
''',
  '0007_synced_file.sql': r'''
-- 0007 ファイルを同期集約にする（S7-2）。
--
-- 設定ファイルのように丸ごとが共有物であるファイルを、専用の転送ではなく封筒の経路で運ぶ。
-- 判定表・正準化・LWW は一行も変わらない（docs/architecture/bops-sync-alignment.md）。
--
-- logical_name に UNIQUE を張らない。名前空間のずれた実装から別 id の行が届いたとき、UNIQUE
-- 違反は適用経路を SQLite のエラーで止め、「取り込めないイベントを破棄しない」と収束の両方を
-- 壊す。重複は admin doctor が報告する（library_memberships と同じ判断）。
CREATE TABLE synced_files (
  id                   TEXT    PRIMARY KEY,
  logical_name         TEXT    NOT NULL,
  content_text         TEXT    NOT NULL,
  version              INTEGER NOT NULL,
  updated_at_utc       TEXT    NOT NULL,
  updated_by_device_id TEXT    NOT NULL
);

CREATE INDEX idx_synced_files_logical_name ON synced_files (logical_name);

-- **端末ローカルの表であり、同期しない。** ディスクへ最後に実体化した内容のハッシュを持つ。
--
-- 集約行と同じトランザクションで書いてはならない。コミット後・ファイル置換前に落ちたとき、
-- 「DBは新版、ファイルは旧内容、ハッシュは新内容」になり、次の読み込みが旧内容を手編集と判定
-- する。旧内容が +1 されて発行され、相手が適用したはずの更新を静かに巻き戻す。
--
-- 置換の後に別のトランザクションで書けば、落ちたときハッシュは古いままなので「手編集なし」と
-- 読め、再実体化して自己修復する。**この表の書く時点が S7 の設計の要である。**
CREATE TABLE synced_file_materialized (
  logical_name         TEXT PRIMARY KEY,
  content_hash         TEXT NOT NULL,
  materialized_at_utc  TEXT NOT NULL
);
''',
  '0008_library_system_sync.sql': r'''
-- 0008 LibrarySystem を同期集約にする（L1）。
--
-- 図書館システムと分館を libraries.toml から SQLite の同期集約へ移す
-- （docs/architecture/libraries-in-sqlite.md）。識別子の定義がファイル側にあり、参照が DB 側に
-- あるという二重管理を解く。library_memberships.system_id が指す先が、同じ判定表・正準化・LWW の
-- 下に入る。
--
-- **library_branches を作らない。** 分館は payload の branches 配列として1列に入る（正準化 JSON
-- 文字列。列は contracts/mapping.py が payload スキーマから導出する）。分館を独立集約にすると、
-- システムと分館が別々に競合して別々に LWW され、libraries.toml が持っていた「設定全体の
-- 洗い替え」という粒度が変わる。分館だけを引く問い合わせが要るようになったら、集約ではなく
-- payload から導出する派生表を足す。派生表は同期の対象にしない。
--
-- **is_deleted を置く。** synced_file と違い、図書館システムの削除は利用者の業務操作であり、
-- 相手端末へ伝わるのは事故ではなく期待した動作である。Book と同じ扱いにする
-- （constants.TOMBSTONE_ENTITY_TYPES）。削除した図書館システムを参照する library_memberships の
-- 行は残す。参照整合性を同期層で強制しない — 片方の端末で削除、もう片方で棚卸完了、という
-- 並行更新は正常に起こりうる。
--
-- 集約IDは uuid5(namespace, system_id) である。entityId は uuid でなければならず、`Tokyo_Minato`
-- のような system_id をそのまま使えない。決定的に導くことで、二端末が同じ図書館システムを独立に
-- 登録しても同じ id を指して競合として立ち、LWW が一件へ収束させる。
--
-- **uuid5 は SQL で計算できないため、既存の libraries.toml をここで運べない。** 移行は
-- migration ではなく、TOML を読んで通常の登録経路へ流す一度きりのコマンドである（L3）。SQL で
-- 行だけ作ると outbox イベントの無い集約になり、相手端末へ永久に届かない（0005 と同じ制約）。
--
-- system_id に UNIQUE を張らない。名前空間のずれた実装から別 id の行が届いたとき、UNIQUE 違反は
-- 適用経路を SQLite のエラーで止め、「取り込めないイベントを破棄しない」と収束の両方を壊す。
-- 重複は admin doctor が報告する（library_memberships・synced_files と同じ判断）。
--
-- **payload 由来の列に NOT NULL を置かない。** 同じ理由が NOT NULL にもかかる。tombstone の
-- payload は最小限でよく（validate.payload が required を外す）、相手端末が system_id すら
-- 持たない tombstone を送ってきたとき、NOT NULL 違反が sqlite3.IntegrityError として適用経路を
-- 止める。tombstone を持つもう一つの集約である books も、payload 由来の列は全て NULL 可である。
-- 業務上の不変条件（都道府県・市区町村・分館が少なくとも一つ）は bops_domain の
-- LibrariesConfig.validate が持つ。branches だけは既定値 '[]' を持つため NOT NULL でよい。
CREATE TABLE library_systems (
  id                       TEXT    PRIMARY KEY,
  system_id                TEXT,
  pref                     TEXT,
  city                     TEXT,
  name                     TEXT,
  opac_search_url_template TEXT,
  homepage_url             TEXT,
  branches                 TEXT    NOT NULL DEFAULT '[]',
  is_deleted               INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
  version                  INTEGER NOT NULL,
  updated_at_utc           TEXT    NOT NULL,
  updated_by_device_id     TEXT    NOT NULL
);

CREATE INDEX idx_library_systems_system ON library_systems (system_id);
''',
  '0009_drop_synced_file.sql': r'''
-- 0009 ファイルの同期をやめる（L4）。
--
-- 図書館システムが library_systems の同期集約になり（L1〜L3）、丸ごと共有できるファイルが1件も
-- 無くなった。synced_file は allowlist に libraries.toml しか持たず、唯一の利用者のために汎用の
-- 仕組みを維持していた（docs/architecture/libraries-in-sqlite.md）。
--
-- **これは「集約の実体が二つある唯一の集約」を消す段である。** SQLite のトランザクションは
-- ファイルの置換を含められないため、synced_file だけは適用の原子性を諦め、「集約行を正本、
-- ファイルはその実体化」として自己修復で埋めていた。実体化ハッシュを置換の前に書くか後に書くかで
-- 正しさが決まる、という繊細さもここから来ていた。難しい部分を上手に実装するのではなく、難しい
-- 部分が存在しない置き方を選んだ結果、この2表が要らなくなる。
--
-- 互換性は保たない。0007 は残すが（migration は追記のみで、適用済みの台帳と突き合わせる）、
-- そこで作った表はここで落とす。libraries.toml をこの DB から復元する手段は無くなる — 図書館
-- システムは既に library_systems へ移っており、ファイル側は正本ではない。
--
-- **転送先を空にするのは、この migration ではなく切替手順の側である。** 旧 enum で書かれた
-- synced_file の封筒が appDataFolder や dir に残っていると、封筒検証が envelope-enum で落ちて
-- invalid として記録される。pending ではない。invalid になった封筒は applied_events に入らず、
-- transport.list() は毎回全件を引くため、一度きりの滞留ではなく毎 run の再計上になる。
--
-- synced_file_materialized は端末ローカルの表であり、同期もバックアップもされていない。落として
-- 失うのは「最後に実体化した内容のハッシュ」だけで、その判定を使う経路がもう無い。

DROP INDEX IF EXISTS idx_synced_files_logical_name;

DROP TABLE IF EXISTS synced_file_materialized;

DROP TABLE IF EXISTS synced_files;
''',
  '0010_preferred_branch.sql': r'''
-- 0010 常用館（受取の既定館）を LibrarySystem へ足す。
--
-- 受取館を WIP ごとに持たせず、図書館システムごとの常用館を既定として引く。常用館以外を
-- 指定した Loan だけが自分で受取館を保持する（UI 仕様 karita-ui-probe の screens/lending.md）。
--
-- **値は branches[].id である。** calil_libkey ではない。loans.pickup_library_id と同じ識別子
-- 空間でなければ「常用館を受取館の既定として引く」が成立しない。libkey は蔵書照会に要る外部の
-- キーで、館名の表記ゆれで動きうる — それを台帳の外部キーにすると、分館の対応が壊れたときに
-- Loan の行を書き換えることになる。
--
-- **同梱既定値を持たない。** マイページ URL と違い、常用館は利用者の生活圏で決まり作者が
-- 決められない。したがって解決順序（取り込み値 → 既定値 → 公式サイト）は無く、利用者値か
-- 未設定かの二択である。未設定から始まるので NOT NULL も既定値も置かない。
--
-- **NOT NULL を置けないのは tombstone のためでもある。** library_system は削除を tombstone で
-- 運び、その payload は system_id だけである。payload 由来の列に NOT NULL を置くと、相手端末
-- からの tombstone が制約違反で適用経路を止める（0008 が他の列に NOT NULL を置かないのと
-- 同じ理由）。
--
-- **指定された値が branches に在ることは、ここでは担保しない。** 業務上の不変条件は
-- bops_domain の LibrarySystem.validate が持ち、登録経路（LibrarySystems.register）だけに
-- 効く。同期で届いた集約行は検査を通らない — 参照が切れたことを報告するのは doctor の側で
-- ある（0005 が system_id に UNIQUE を張らないのと同じ線である）。
--
-- **ALTER TABLE ADD COLUMN なので、列は表の末尾（version 列より後ろ）に付く。** payload
-- スキーマの properties の並びとテーブルの列位置はここで対応が切れるが、列は名前で読み書き
-- する（aggregates.upsert が列名を明示した INSERT を組む）ので位置は効かない。表を作り直して
-- まで位置を揃えない。

ALTER TABLE library_systems ADD COLUMN preferred_branch_id TEXT;
''',
  '0011_library_setting.sql': r'''
-- 0011 利用者値をカタログから出す（L6）。
--
-- 常用館とマイページ URL を library_systems から library_settings の行へ移す。集約IDは
-- uuid5(namespace, "<system_id>/<key>") で、**鍵ごとに別の集約**になる。
--
-- **これが要点である。** LWW は集約1件の payload 全体を差し替える。同じ集約に居る限り、端末Aが
-- 常用館を、端末Bがマイページ URL を変えると、どちらの payload にも相手の古い値が入ったまま
-- 後勝ちになり、片方の変更が消える。ローカルのトランザクションを分けても直らない — 行が同じ
-- だからである。項目ごとのマージは「payload は全体スナップショットである」という契約の根幹を
-- 変えることになるので採らない。**直し方は行を分けることだけである。**
--
-- **カタログと利用者値は寿命が違う。** pref / city / name / branches / homepage_url はカーリル
-- 由来で、再登録のたびに洗い替える。常用館とマイページ URL は利用者が決めた値で、洗い替えの
-- 対象ではない。prepareRegistration が利用者値を手で運んでいた（_carryPreferred）のは、寿命の
-- 違うものを同じ集約へ押し込んだ結果の逃げであり、出せばその逃げごと消える。
--
-- **uuid5 は SQL で計算できないため、旧行をここで運べない**（0005・0008 と同じ制約）。SQL で
-- 行だけ作ると outbox イベントの無い集約になり、相手端末へ永久に届かない。したがって
-- preferred_branch_id の値は下の退避表へ写すだけで、**常用館は未設定に戻る。** 設定し直す経路は
-- 通常の業務入口（LibrarySettings.setPreferredBranch）である。
--
-- **payload スキーマから preferred_branch_id を落とすので、列も落とす。** 残すと、Dart が読める
-- 定義と実際の表が二本になる。旧版が書いた preferred_branch_id 付きの library_system payload は
-- additionalProperties: false で弾かれるが、**製品を配る前なので守る対象の端末が存在しない**
-- （0010 で .blib の往復は既に片方向になっている）。
--
-- **key は enum で縛る**（payload/library_setting.schema.json）。汎用の key/value にすると綴りの
-- ずれが端末間で静かに壊れる。SQLite では key を識別子として使える（sync_state が同じ形である）。
--
-- **payload 由来の列に NOT NULL を置かない。** tombstone の payload は最小限でよく、相手端末が
-- system_id すら持たない tombstone を送ってきたときに NOT NULL 違反が適用経路を止める（0008 と
-- 同じ理由）。解除は tombstone で表し、payload は system_id と key だけになる。
--
-- **system_id に UNIQUE を張らない**（0005・0008 と同じ）。(system_id, key) の組にも張らない —
-- 名前空間のずれた実装から別 id の行が届いたとき、UNIQUE 違反が適用経路を SQLite のエラーで
-- 止める。重複は doctor が報告する。

CREATE TABLE library_settings (
  id                   TEXT    PRIMARY KEY,
  system_id            TEXT,
  key                  TEXT,
  value                TEXT,
  checked_on           TEXT,
  is_deleted           INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
  version              INTEGER NOT NULL,
  updated_at_utc       TEXT    NOT NULL,
  updated_by_device_id TEXT    NOT NULL
);

CREATE INDEX idx_library_settings_system ON library_settings (system_id, key);

-- 退避。**業務の行ではない** — outbox も版列も持たないので、同期にも復元にも出ない。
-- 設定し直すときに「何が入っていたか」を人が見るためだけに残す（0005 が
-- library_memberships_local_v1 を残したのと同じ扱いである）。
CREATE TABLE library_systems_preferred_v1 AS
  SELECT system_id, preferred_branch_id
    FROM library_systems
   WHERE preferred_branch_id IS NOT NULL AND preferred_branch_id <> '';

ALTER TABLE library_systems DROP COLUMN preferred_branch_id;
''',
  '0012_book_preferences.sql': r'''
CREATE TABLE book_preferences (
  id TEXT PRIMARY KEY,
  book_id TEXT,
  want_to_read INTEGER CHECK (want_to_read IN (0, 1)),
  priority INTEGER,
  tags TEXT NOT NULL DEFAULT '[]',
  memo TEXT,
  is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
  version INTEGER NOT NULL,
  updated_at_utc TEXT NOT NULL,
  updated_by_device_id TEXT NOT NULL
);
CREATE INDEX idx_book_preferences_book ON book_preferences(book_id);
''',
  '0013_bookshelf.sql': r'''
ALTER TABLE book_preferences ADD COLUMN shelf_state TEXT CHECK (shelf_state IN ('wanted','read','removed','none'));
ALTER TABLE book_preferences ADD COLUMN shelf_token TEXT;
ALTER TABLE book_preferences ADD COLUMN shelf_changed_at_utc TEXT;
ALTER TABLE book_preferences ADD COLUMN manual_reads TEXT NOT NULL DEFAULT '[]';
ALTER TABLE loans ADD COLUMN first_return_basis TEXT;
ALTER TABLE loans ADD COLUMN first_return_at_utc TEXT;
CREATE TABLE book_reviews (
  id TEXT PRIMARY KEY,
  book_id TEXT NOT NULL,
  rating INTEGER CHECK (rating BETWEEN 1 AND 5),
  review TEXT,
  version INTEGER NOT NULL,
  updated_at_utc TEXT NOT NULL,
  updated_by_device_id TEXT NOT NULL
);
CREATE INDEX idx_book_reviews_book ON book_reviews(book_id);
''',
  '0014_bookshelf_registration.sql': r'''
ALTER TABLE book_preferences ADD COLUMN wanted_registered_at_utc TEXT;
ALTER TABLE book_preferences ADD COLUMN read_registered_at_utc TEXT;
''',
};
