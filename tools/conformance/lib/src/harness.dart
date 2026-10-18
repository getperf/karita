/// 試験用の組み立て。**製品の組み立てと同じ手順を通る。**
///
/// `bsync init db` → `config set transport.dir` に相当する。プロファイルごとに SQLite を作って
/// マイグレーションを適用し、共有の転送先・保管先（`dir`）へ向ける。
///
/// **裏口を作らない。** ここが持つのは組み立てだけで、適用も世代も復元も `karita_sync` が行う。
library;

import 'dart:io';

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_sync/karita_sync.dart';

import 'dir_backup_store.dart';
import 'dir_transport.dart';

/// 端末種別の接頭辞。二端末シミュレーションは1台の上で `windows-a` と `android-b` を並べる
/// ため、実行ホストの種別をそのまま使うと両方が同じ接頭辞になる。**LWW の第2キーが deviceId で
/// ある以上、ここが揃うと決定キーの意味が変わる。**
const List<String> platformPrefixes = [
  'windows',
  'android',
  'linux',
  'darwin',
  'ios',
];

String platformForProfile(String name) {
  final head = name.split('-').first.toLowerCase();
  return platformPrefixes.contains(head) ? head : 'linux';
}

/// 1台ぶんの組み立て。DB・転送・保管先・素性を束ねる。
///
/// **業務（`karita_domain`）と同期（`karita_sync`）が同じ台帳を見る。** 製品でも1端末1台帳で
/// あり、`bops` と `bsync` が同じ SQLite を触る形をそのまま写している。業務が書いた outbox を
/// 同期がそのまま押すのは、この同居があって初めて測れる。
class Device {
  final String profile;
  final String deviceId;
  final DbSession session;
  final SyncEngine engine;

  /// この端末の業務層。**同期エンジンとは独立に組む** — 業務は同期に依存しない。
  final DomainContext domain;

  /// この端末の転送に注入する故障。**空なら素の `dir` と同じである。**
  ///
  /// 駆動側が動作ごとに入れ替える。転送はこの集合**そのもの**を握っているので、中身を書き
  /// 換えれば次の呼び出しから効く。集合を差し替えると繋がりが切れる。
  final Set<String> faults;

  Device({
    required this.profile,
    required this.deviceId,
    required this.session,
    required this.engine,
    required this.domain,
    required this.faults,
  });

  Db get db => session.db;

  /// 業務の各サービス。**組み立てだけをここに置く。** 規則はサービスが持つ。
  Books get books => Books(domain);
  Loans get loans => Loans(domain);
  Memberships get memberships => Memberships(domain);
  LibrarySystems get librarySystems => LibrarySystems(domain);
  LibrarySettings get librarySettings => LibrarySettings(domain);
  LoanReporting get reporting => LoanReporting(db);

  void close() => session.close();
}

/// 転送先と保管先を共有する1つの世界。ケース1本ぶん、あるいは試験1本ぶん。
class Harness {
  final Contracts contracts;
  final Directory root;
  final Directory appData;

  /// 差し替えられた保管先。**実 Drive の相互運用だけが使う。**
  final BackupStorePort? _storeOverride;

  /// 差し替えられた転送。**実 Drive の相互運用だけが使う。**
  final TransportPort Function(String generationId)? _transportOverride;

  /// **保管先は転送先と同じ場所である。** 別に選べるようにしない。
  ///
  /// 唯一の例外が実 Drive で、そこでは「同じ場所」が `appDataFolder` になる。転送も保管先も
  /// 揃って差し替わるので、**この不変条件は破れていない** — 差し替えるのは場所であって、
  /// 転送と保管先が別々になるわけではない。
  late final BackupStorePort store = _storeOverride ?? DirBackupStore(appData);

  final List<Device> _devices = [];
  int _uuidCounter = 0;
  int _deviceCounter = 0;

  Harness._(this.contracts, this.root, this.appData,
      this._storeOverride, this._transportOverride);

  factory Harness.create(
    Contracts contracts, {
    String prefix = 'karita-',
    BackupStorePort? store,
    TransportPort Function(String generationId)? transportFor,
  }) {
    // **どちらか片方だけの差し替えを許さない。** 転送先と保管先が別の場所を指すと、世代の
    // 起点と封筒が別々の空間に置かれ、有効世代の決定が意味を失う。
    if ((store == null) != (transportFor == null)) {
      throw ArgumentError('転送先と保管先は揃えて差し替える。片方だけは受けない。');
    }
    final root = Directory.systemTemp.createTempSync(prefix);
    final appData = Directory('${root.path}${Platform.pathSeparator}appdata')
      ..createSync(recursive: true);
    return Harness._(contracts, root, appData, store, transportFor);
  }

  /// 決定的な UUID。run_id・conflict_id・backup_id・世代 id・解決イベントの eventId に使う。
  ///
  /// **決定性は LWW の結果に効かない** — 決定キーの第3要素は `eventId` ではなく `payloadHash`
  /// である。ここを決めるのは、落ちたときに同じ id で再現できるようにするためだけである。
  String uuid() {
    _uuidCounter++;
    return 'dddddddd-0000-4000-8000-'
        '${_uuidCounter.toRadixString(16).padLeft(12, '0')}';
  }

  String dbPathFor(String profile) =>
      '${root.path}${Platform.pathSeparator}profiles'
      '${Platform.pathSeparator}$profile${Platform.pathSeparator}library.db';

  /// `bsync init db` と同じ順序。マイグレーションを適用してから素性を書く。
  ///
  /// **世代は書かない** — 最初の転送が `bootstrap` として起点を置き、二台目は `adopt` でその
  /// 世代に乗る。ここで書くと、世代の解決そのものを飛ばした状態で試験が回る。
  Device device(String profile, {AutoResolvePolicy? autoResolve, String? now}) {
    _deviceCounter++;
    final deviceId = '${platformForProfile(profile)}-00000000-0000-4000-8000-'
        '${_deviceCounter.toRadixString(16).padLeft(12, '0')}';
    final path = dbPathFor(profile);
    File(path).parent.createSync(recursive: true);

    final session = DbSession.open(path);
    final db = session.db;
    final at = now ?? '2026-08-04T09:00:00Z';
    migrate(db, now: at);
    transaction(db, () {
      setState(db, stateDeviceId, deviceId);
      setState(db, stateProfileName, profile);
      if (getState(db, stateCreatedAtUtc) == null) {
        setState(db, stateCreatedAtUtc, at);
      }
    });

    // **故障の集合は端末が持ち、転送はそれを読む。** 端末より先に転送を作ると、故障を
    // 切り替えるたびに転送を組み直すことになり、`delayed-visibility` が覚えている
    // 「自分が書いたもの」が毎回消える。
    final faults = <String>{};
    final built = Device(
      profile: profile,
      deviceId: deviceId,
      session: session,
      faults: faults,
      // **業務は同期を知らない。** 同じ台帳と同じ素性を渡すだけで、繋がりは outbox の一点
      // である。ここで engine を渡すと、依存の向きが組み立ての側から反転する。
      domain: DomainContext(
        // **接続を値で渡さない。** 完全復元は DB を開き直すので、値で渡すと業務だけが
        // 復元前の接続を握り続ける。
        db: () => session.db,
        contracts: contracts,
        deviceId: deviceId,
        uuid: uuid,
      ),
      engine: SyncEngine(
        session: session,
        profile: profile,
        transportFor: (generationId) => _transportFor(generationId, faults),
        store: store,
        deviceId: deviceId,
        contracts: contracts,
        uuid: uuid,
        autoResolve: autoResolve ?? AutoResolvePolicy.lww,
      ),
    );
    _devices.add(built);
    return built;
  }

  /// 故障が無ければ素の `dir`、あればそれを包んだもの。
  ///
  /// **包む側にする。** 故障ごとに転送を作り分けると、「故障の無い fault 転送」と `dir` が
  /// 別物になり、比較の基準が失われる。
  TransportPort _transportFor(String generationId, Set<String> faults) {
    final base = _transportOverride?.call(generationId) ??
        DirTransport(appData, generationId);
    return faults.isEmpty ? base : FaultTransport(base, faults);
  }

  /// 転送先にある封筒の生の中身。**`remote` の表明が使う。**
  ///
  /// 世代で絞らない。**転送先そのものを数えるのが表明の意味である** — 旧世代の残骸も、
  /// 「重複を作っていないか」を見る上では転送先に置かれたファイルである。
  Future<List<String>> appDataEnvelopes() async {
    if (!appData.existsSync()) return const [];
    final files = appData.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return [
      for (final entry in files)
        if (entry.uri.pathSegments.last.startsWith(filenamePrefix) &&
            entry.uri.pathSegments.last.endsWith(filenameSuffix))
          entry.readAsStringSync(),
    ];
  }

  List<String> appDataNames() {
    if (!appData.existsSync()) return const [];
    final names = [
      for (final entry in appData.listSync().whereType<File>())
        entry.uri.pathSegments.last,
    ]..sort();
    return names;
  }

  void dispose() {
    for (final device in _devices) {
      device.close();
    }
    if (root.existsSync()) {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows では WAL のハンドルが残って消せないことがある。判定には関わらない。
      }
    }
  }
}
