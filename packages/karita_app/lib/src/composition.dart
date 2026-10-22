/// **合成層。** どの実装を使うかを決めるのはここだけである。
///
/// `karita_platform`（純 Dart・Windows）と `karita_platform_flutter`（Android）は、どちらも
/// **自分が何に使われるかを知らない。** 両者を選び、繋ぎ、`SyncEngine` と `DomainContext` を
/// 組み立てるのがこの層の仕事である。
///
/// **合成は1つだけである。** harness も本番 GUI もこの利用側に立つ。2つあると、本番で通って
/// いない経路を harness が緑にする（`非公開資料:production-app-composition.md` 決定 B）。
///
/// **provider gateway が来るときも、接ぐのはここである。** `karita_provider_gateway_client` が
/// 宣言する `GoogleIdTokenSource` を implement するのは合成層だけで、`karita_platform` にも
/// `karita_platform_flutter` にもその辺を作らない
/// （`非公開資料:provider-gateway-client-migration.md` 決定 A）。
/// いまは gateway を持ち込まないので、受け皿だけを想定しておく。
///
/// **条件付き import を使わない。** `karita_platform` は純 Dart（`dart:io` しか使わない）ので
/// Android のビルドにも入る。違うのは**振る舞いだけ**なので、実行時に分ければ足りる。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_platform/karita_platform.dart';
import 'package:karita_platform_flutter/karita_platform_flutter.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:karita_sync/karita_sync.dart';
import 'package:logging/logging.dart';

import 'background.dart';
import 'bookshelf_export/models.dart';
import 'bookshelf_export/mapper.dart';
import 'bookshelf_export/csv_encoder.dart';
import 'bookshelf_export/json_encoder.dart';
import 'book_lookup.dart';
import 'demo.dart';
import 'demo_fixture.dart';
import 'handoff.dart';
import 'holdings_lookup.dart';
import 'libraries.dart';
import 'mypage_defaults.dart';
import 'public_api.dart';
import 'refresh.dart';
import 'settings.dart';
import 'settings_adapter.dart';
import 'composition/authorization.dart';
import 'composition/clock.dart';
import 'composition/environment.dart';
import 'composition/handoff_triage.dart';
import 'composition/ids.dart';

export 'composition/authorization.dart' show Authorization;
export 'composition/boot.dart';
export 'composition/clock.dart';
export 'composition/environment.dart'
    show appPaths, seedHome, refuseSeedOnProductionHome;
export 'composition/handoff_triage.dart';
export 'composition/ids.dart' show defaultProfile;

part 'composition/compose.dart';
part 'composition/settings_part.dart';
part 'composition/sync_part.dart';
part 'composition/diagnostics_part.dart';
part 'composition/account_part.dart';
part 'composition/backup_part.dart';
part 'composition/records_part.dart';
part 'composition/bookshelf_export_part.dart';
part 'composition/libraries_part.dart';
part 'composition/handoff_part.dart';
part 'composition/library_settings_part.dart';

final Logger _log = Logger('karita.app');

/// 組み上がった1端末。
class Composition {
  final AppPaths paths;

  /// 端末設定。**復元で運ばれない側である。**
  DeviceSettings _settings;
  DeviceSettings get settings => _settings;

  final _settingsChanges = StreamController<String>.broadcast();
  final _statusChanges = StreamController<void>.broadcast();
  final _syncStatusChanges = StreamController<void>.broadcast();
  final _browserLinkChanges = StreamController<void>.broadcast();
  StreamSubscription<Handoff>? _linkChecks;
  String get theme => _settings.theme;
  Stream<String> get settingsChanges => _settingsChanges.stream;

  /// 台帳が変わったかもしれない。**一覧を読む側が見る。**
  Stream<void> get statusChanges => _statusChanges.stream;

  /// 同期の状態が変わった（未送信件数・最終同期・実行中）。**[statusChanges] のときも必ず
  /// 出る。** 設定の同期行とバックアップの行が見る（2026-10-08。
  /// `非公開資料:ui-state-model.md` §2「更新の共通契約」）。
  ///
  /// 分けたのは、30 秒周期の何も無い回ごとに一覧を読み直さないためである。
  Stream<void> get syncStatusChanges => _syncStatusChanges.stream;

  /// 同期世代が変わって止まっている旗。**7状態に混ぜない**（[AppSyncStatus.generationChanged]）。
  ///
  /// 立てるのは周期リフレッシュの `run` を包んだ合成層のクロージャで、`RefreshLoop` は触らない
  /// （`非公開資料:production-wiring-auth-backup-sync.md`「`refresh.dart` は触らない」）。
  AppIssue? _generationChanged;

  /// 記録済みの Google アカウントと違うアカウントに接続している旗。**7状態に混ぜない**
  /// （[AppSyncStatus.accountMismatch]）。
  ///
  /// 立てる／下ろすのは [_checkAccountIdentity] だけである（`about.get` を読んで比べる）。
  AppIssue? _accountMismatch;

  /// 台帳が変わったかもしれないことを画面へ伝える。
  ///
  /// **`FINE` で毎回出す。** 購読側（`karita_ui` の `ledgerRevisionProvider`）はこの1本で
  /// 一覧・詳細・常用館・マイページをまとめて読み直すので、**再読込が起きたかどうかは
  /// この行の有無で決まる。**
  void _notifyStatus() {
    if (_closed) return;
    _log.fine('ledger.changed');
    _statusChanges.add(null);
    _syncStatusChanges.add(null);
  }

  /// 同期の状態だけが変わったことを伝える。**台帳は読み直させない。**
  ///
  /// 同期 run の開始と終了がこれを打つ。業務データを書いた run は、終わった後に合成層の
  /// クロージャが [_notifyStatus] を打つ（[RunResult.ledgerChanged]）。
  void _notifySyncStatus() {
    if (_closed) return;
    _syncStatusChanges.add(null);
  }

  /// この起動の性格（本番かデモか）。**画面と業務へは配らない。**
  final AppMode mode;

  final Authorization auth;
  final RestDriveClient client;
  final DbSession session;
  final SyncEngine engine;
  final DomainContext domain;
  final String deviceId;

  /// 環境の自己診断。**端末ごとに実装が違う。**
  final EnvironmentDoctor environmentDoctor;

  /// 周期リフレッシュ。**デモでは `null`** — 「自動処理を登録しない」を旗ではなく不在で表す。
  final RefreshLoop? refresh;

  /// 背面の口。**実装は持たない。**
  final BackgroundScheduler background;

  /// 受け渡しの排出と一時保持。**デモでも本番と同じ配送先を使う。**
  ///
  /// デモ専用の scheme も受信部も作らない（`非公開資料:demo-mode.md`）。違うのは
  /// リセットで旧い共有待ちを捨てることだけである。
  final HandoffQueue handoff;

  /// マイページ URL の既定値表（5区）。**焼き込まず、実行時に引く。**
  final MypageDefaults mypageDefaults;

  /// カーリルの appkey と、その出どころ。**値を画面へ配らない。**
  ///
  /// 画面が知るのは [CalilKeyChoice.usable] だけである。使えないときに閉じるのは蔵書照会と
  /// 図書館候補の取得だけで、他の作業は続く。
  final CalilKeyChoice calilKey;

  /// 書誌と書影の取得口。**キーが要らないので、どの端末でも在る。**
  ///
  /// **業務の [books] とは別物である。** あちらは台帳に載る本の入口で、こちらは外から取って
  /// くる候補の入口である。**候補は台帳ではない** — 利用者が採ると決めたものだけが業務の側へ
  /// 渡る。名前を分けてあるのはそのためで、混ぜると「取得したら登録される」に見える。
  ///
  /// OpenBD は appkey を要らない。**カーリルが使えない端末でも書誌は引ける** — 2つを1つの
  /// 「外部データが使えるか」に畳むと、キーの無い端末で書名まで出なくなる。
  final BookLookup bookInfo;

  /// ブラウザを開く口。**`rundll32.exe` を合成層の外へ出さない。**
  ///
  /// `LoopbackLogin` へ渡しているのと同じ関数である。**Windows 専用の実装のまま残す** —
  /// 端末を足すときに触る4箇所の1つで、要るかどうかは各端末の認可の実装で決まる。
  final Future<void> Function(Uri url) openBrowser;

  /// 利用者が選んだブラウザーで開く口（2026-10-16）。**Windows の本番だけが実物を持つ。**
  ///
  /// [openBrowser] は OS の既定のまま残す — サインインがそれを使う。こちらを通すのは
  /// 図書館サイト・Amazon・アカウント管理を開く操作だけである（[openSite]）。
  final BrowserLauncher browsers;

  /// 対象外の操作を、始まる前に止める口。**本番では素通りする。**
  OperationGate get gate => mode.gate;

  /// 起動準備が済んでいるか。**外殻のゲートはこれ1つで開く。**
  ///
  /// **デモは常に開く。** デモが省略する「起動準備」がこれである
  /// （`非公開資料:demo-mode.md`）。`compose()` は `setupFresh` を呼ばないので、
  /// **台帳に fixture が載っていても [localGeneration] は `null` のままである。** 本番の
  /// 述語をそのまま画面が書くと、デモが図書館管理へ到達できない。
  ///
  /// **種入りの本番（検証モード）では閉じたままである。** 種は台帳の出発点を変えるだけで、
  /// 初回起動の2択を済ませはしない — 検証で押したいのがその2択なので、そこから入る形が
  /// 正しい（`非公開資料:p5b-verification-mode.md`）。
  ///
  /// **`bool` しか出さない。** [localGeneration] は `karita_sync` の関数で、返す
  /// `({String id, int seq})?` も同期の語彙である。画面がそれを受け取ると、`karita_ui` が
  /// `karita_sync` を import しないという境界が型の側から崩れる
  /// （`非公開資料:ui-state-model.md` §3）。
  ///
  /// **[RefreshLoop] の `ready:` と同じ述語である**（[_setupComplete]）。回し始める条件と
  /// 画面を開く条件は同じもので、2箇所に書くと片方だけが動く。
  bool get bootReady => mode.isDemo || _setupComplete(session.db);

  /// 閉じるときに片付けるもの（デモの一時領域など）。
  final void Function() _disposeLedger;

  AppLifecycleListener? _lifecycle;
  bool _closed = false;
  DemoFixture? _fixture;
  DemoFixtureReport? fixtureReport;

  /// 直近の自己診断。**まだ走らせていなければ `null`。**
  ///
  /// 状態タブが `doctorFailed` に渡す値である。**「異常が無い」と「まだ走らせていない」を
  /// 混ぜない** — `null` を `false` に潰すと、一度も診断していない端末が「健全」を名乗る。
  DoctorReport? lastDoctor;

  final ExportDelivery _exportDelivery;

  Composition({
    required this.paths,
    required DeviceSettings settings,
    required this.mode,
    required this.auth,
    required this.client,
    required this.session,
    required this.engine,
    required this.domain,
    required this.deviceId,
    required this.environmentDoctor,
    required this.background,
    required this.handoff,
    required this.openBrowser,
    this.browsers = const NoBrowserLauncher(),
    this.mypageDefaults = const MypageDefaults.empty(),
    this.calilKey = const CalilKeyChoice('', CalilKeySource.none),
    BookLookup? bookInfo,
    CalilLibraryClient? libraryClient,
    this.refresh,
    ExportDelivery? exportDelivery,
    void Function()? disposeLedger,
  }) : _exportDelivery =
           exportDelivery ??
           // iOS も共有シートで渡す。`file_selector` の保存ダイアログは iOS に無い。
           (Platform.isAndroid || Platform.isIOS
               ? const AndroidExportDelivery()
               : const WindowsExportDelivery()),
       _settings = settings,
       _disposeLedger = disposeLedger ?? _nothing,
       bookInfo = bookInfo ?? BookLookup(OpenBdClient()),
       _libraryClient = libraryClient;

  static void _nothing() {}

  Db get db => session.db;

  Db? _ledgerDb;
  Object _ledgerSessionToken = Object();

  /// 台帳の接続が入れ替わると別の値になる。**通常の更新では変わらない。**
  ///
  /// 復元は `session.detach()` → 置換 → `session.reopen()` を通り、`Db` が替わる。**画面の
  /// 保持（本棚の編集中入力・貸出しの詳細・予約の下書き）はこれを見て捨てる。**
  /// `Composition` 自体は替わらないので、`compositionProvider` を見ているだけでは捨てられない
  /// （`非公開資料:production-wiring-auth-backup-sync.md`「復元後の再接続」）。
  ///
  /// 段階4 の `bookshelfSessionToken` を昇格させたものである。
  Object get ledgerSessionToken {
    if (!identical(_ledgerDb, session.db)) {
      _ledgerDb = session.db;
      _ledgerSessionToken = Object();
    }
    return _ledgerSessionToken;
  }

  /// 図書館候補の取得口。**キーが空の端末では作らない。**
  ///
  /// `CalilLibraryClient` の構築子は空キーで `ArgumentError` を投げる。**そこへ行かせない** —
  /// 画面が知るのは [CalilKeyChoice.usable] だけで、キーの値は配らない。
  CalilLibraryClient? _libraryClient;

  /// 蔵書の取得口。**キーが空の端末では `null` である。**
  ///
  /// **[_requireLibraryClient] と違って投げない。** 図書館候補は利用者が押した操作の結果だが、
  /// 蔵書は**一覧を描くたびに引かれる口**である。例外を1行ぶんの表示へ変換させると、画面側が
  /// `try` で埋まる。`null` は「蔵書照会を利用できません」という表示の1つで、失敗ではない。
  ///
  /// **遅延して作る。** 本棚を開かない端末で `http.Client` を1本増やさない。
  HoldingsLookup? _holdings;

  /// 閉じたセッションへ書かない。**[saveTheme] と同じ関門である。**
  void _requireOpen() {
    if (_closed) throw const AppIssue('session-closed', 'Session is closed.');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_settingsChanges.close());
    unawaited(_statusChanges.close());
    unawaited(_syncStatusChanges.close());
    unawaited(_linkChecks?.cancel());
    unawaited(_browserLinkChanges.close());
    _lifecycle?.dispose();
    _lifecycle = null;
    handoff.dispose();
    refresh?.stop();
    bookInfo.close();
    // **キーが空の端末では作られていない。** 作っていないものを閉じない。
    _libraryClient?.close();
    _holdings?.close();
    client.close();
    session.close();
    _disposeLedger();
  }
}

/// 初回起動の2択（新規／復元）が済んだか。**述語はここ1本だけである。**
///
/// 読み手は2つある — 周期リフレッシュの `ready:` と、外殻のゲート（[Composition.bootReady]）。
/// **回し始める条件と画面を開く条件は同じもの**なので、片方だけが動く形にしない。
bool _setupComplete(Db db) => localGeneration(db) != null;
