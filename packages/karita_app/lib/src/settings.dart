/// UI に公開する値だけ。設定ファイル・資格情報・同期の内部型を含めない。
library;

enum AppSyncState {
  appUpdateRequired,
  signInRequired,
  needsAttention,
  syncing,
  offline,
  unsent,
  synced,
}

class AppIssue implements Exception {
  final String code;
  final String message;
  const AppIssue(this.code, this.message);

  @override
  String toString() => '[$code] $message';
}

class AppSyncStatus {
  final AppSyncState state;
  final String? lastSuccessAt;
  final int autoResolved;
  final AppIssue? issue;

  /// 他の端末の復元で同期世代が変わった旗。**[state] とは別の事実である。**
  ///
  /// 7状態の enum を8にしない（`karita_sync` の `status.dart` の宣言）。保管先を読まないと
  /// 分からない事実で、立っていても [state] は `unsent` などのまま動く。
  final AppIssue? generationChanged;

  /// 記録済みの Google アカウントと違うアカウントに接続している旗。**[state] とは別の
  /// 事実である。**
  ///
  /// [generationChanged] と同じ理由で7状態には入れない — `about.get` を読まないと分からない
  /// 事実で、立っていても同期は「同期済み」を名乗ったまま止まる（P5 単位 E）。
  final AppIssue? accountMismatch;

  const AppSyncStatus({
    required this.state,
    this.lastSuccessAt,
    this.autoResolved = 0,
    this.issue,
    this.generationChanged,
    this.accountMismatch,
  });
}

/// ［アカウント］行の3状態。**7状態（[AppSyncState]）とは別のものである。**
///
/// あちらは「同期がいまどうなっているか」で、こちらは「この端末が接続を持っているか」で
/// ある。両方が同時に立つ場面がある — 認可を失って止まった端末は `signInRequired` かつ
/// [reauthRequired] である。**混ぜると、送るものが1件も無い新しい端末の「まだサインイン
/// していない」がどこにも出ない。**
enum AppAuthState {
  /// 接続を持っていない。**新しい端末の初期状態である。**
  signedOut,

  /// 接続を持っている。
  signedIn,

  /// 接続はあるが、認可を失って同期が止まっている（`blocked_auth`）。
  reauthRequired,
}

/// ［アカウント］行に出す事実。**トークンもメールも生では出さない。**
///
/// メールアドレス（接続先のアカウント）は `about.get` が要り、それは段5 の仕事である。
/// この段で出せるのは3状態と、何で認可しているかの素性だけである。
class AppAuthStatus {
  final AppAuthState state;

  /// 何で認可しているか。**enum ではなく素性の識別子**（`play-services-authorization-api`
  /// など）。画面はこれを出さない — 出すのは harness である。
  final String kind;

  /// 操作できるか。**デモでは `false`** である（[OperationGate] が先に止める）。
  ///
  /// **画面へ `isDemo` を配らないための形である**（`非公開資料:demo-mode.md`
  /// 「UI・domain に isDemo を配らず、合成層から操作結果・利用可否を供給する」）。
  final bool available;

  /// Google アカウントの切替導線（`myaccount.google.com/connections`）を出してよいか。
  ///
  /// **端末で決まる。** Windows はサインインのたびにブラウザでアカウント選択が出るので
  /// 要らない。**画面へ `Platform.isAndroid` を配らないための形である**（[available] と
  /// 同じ理由）。
  final bool canSwitchAccount;

  const AppAuthStatus({
    required this.state,
    required this.kind,
    this.available = true,
    this.canSwitchAccount = false,
  });
}

/// 一覧に出せるバックアップ1件。**同期の型を画面へ渡さないための写しである。**
///
/// `BackupRef` は `remoteId`・`duplicateRemoteIds`・`summary` の生の地図を持つ。保管先の
/// 識別子は画面の持ち物ではない — 選んだものを指すのは [backupId] だけである。
class AppBackup {
  final String backupId;

  /// 作成時刻。**作成端末の時計である**（表示順に使うが、正しさには関わらない）。
  final String createdAtUtc;

  /// 作成端末の素性（`windows` / `android`）。仕様の「日時・作成端末」の後半である。
  final String createdOn;

  final int sizeBytes;

  /// 本と貸出記録の件数。**索引から読む** — 影響確認を保管先から取らずに出すためである。
  /// 索引に無ければ `null`（表示だけの値で、正しさは取得後の manifest が決める）。
  final int? books;
  final int? loans;

  /// この版で復元できるか。**索引の版で先に見る**（受入ケース8）。`false` のものは一覧で
  /// 選べなくし、アプリの更新を求める。取得後の検査は別にエンジンが必ず行う。
  final bool readable;

  const AppBackup({
    required this.backupId,
    required this.createdAtUtc,
    this.createdOn = '',
    this.sizeBytes = 0,
    this.books,
    this.loans,
    this.readable = true,
  });
}

/// ［バックアップ］［復元］の2行に出す、この端末の事実。
///
/// **7状態（[AppSyncStatus]）に入れない。** あちらは「同期がいまどうなっているか」で、
/// こちらは端末が過去に何をしたかである（［アカウント］行を分けたのと同じ理由）。
///
/// どれも**端末ごとの事実で、復元では運ばれない**（`deviceStateKeys`）。
class AppBackupFacts {
  /// 最後に保管先へ入れた時刻。未作成なら `null`。
  final String? lastBackupAt;

  /// 最後に復元した時刻と、その対象（作成時刻・作成端末）。未実行なら `null`。
  final String? lastRestoreAt;
  final String? lastRestoreCreatedAt;
  final String lastRestorePlatform;

  /// この端末の未送信の変更。**復元で失われる件数**として影響確認に出す。
  final int unsent;

  /// 他の端末の復元で同期世代が変わり、この端末の同期が止まっているか。
  ///
  /// 立っているときだけ、［復元］の選択の先頭に「別の端末で復元されたデータに合わせる」が
  /// 出る（`非公開資料:production-wiring-auth-backup-sync.md`「止まった端末は
  /// ［復元］の選択から戻る」）。
  final bool generationChanged;

  /// 操作できるか。**デモでは `false`**（[AppAuthStatus.available] と同じ形）。
  final bool available;

  const AppBackupFacts({
    this.lastBackupAt,
    this.lastRestoreAt,
    this.lastRestoreCreatedAt,
    this.lastRestorePlatform = '',
    this.unsent = 0,
    this.generationChanged = false,
    this.available = true,
  });
}

/// 一覧の結果。
///
/// **[skipped] も画面へ出す。** 索引を読めなかった `.blib` を黙って落とすと、索引を書けて
/// いない不具合が「バックアップが1つも無い」という形でしか現れない。
class AppBackupListing {
  final List<AppBackup> items;
  final int skipped;

  const AppBackupListing({this.items = const [], this.skipped = 0});
}
