/// 図書館システムごとの利用者値（[LibrarySetting]）の設定・解除と読み出し。
///
/// **鍵ごとに別の集約である。** `entityId` は `uuid5(namespace, "<systemId>/<key>")` で導く。
/// 同じ集約に入れると LWW が payload 全体を差し替えるので、二端末が常用館とマイページ URL を
/// 別々に変えたとき**後勝ちで片方が消える。** ローカルのトランザクションを分けても直らない —
/// 行が同じだからである。**直し方は行を分けることだけである**
/// （`非公開資料:libraries-in-sqlite.md` 2c）。
///
/// **カタログ（[LibrarySystem]）とは寿命が違う。** カタログはカーリル由来で再登録のたびに
/// 洗い替えるが、ここはその対象ではない。`prepareRegistration` が常用館を手で運んでいたのは、
/// 寿命の違うものを同じ集約へ押し込んだ結果の逃げであり、出したことで消えた。
///
/// **設定と解除を別の口にする。** `null` を渡して解除する形にすると、「変更なし」と「外す」が
/// 同じ値で表されて区別できなくなる（`copyWith` が常用館を外せなかったのと同じ形である）。
///
/// **それぞれ独立したトランザクションである。** 画面は同じ（図書館管理のシステム詳細）だが、
/// 合わせて更新にはしない — 片方だけを設定した状態が正常であり、相手の値を要求しない。
library;

import 'package:karita_contract/karita_contract.dart';

import 'context.dart';
import 'errors.dart';
import 'library_systems.dart';

/// 常用館。**受取館の既定として引く分館の `Branch.id` である。**
///
/// `calilLibkey` ではない — `loans.pickup_library_id` と同じ識別子空間でなければ既定として
/// 引けない。libkey は蔵書照会に要る外部のキーで、表記ゆれで動きうる。
const String settingPreferredBranch = 'preferred_branch';

/// マイページ（ログイン入口）の URL。
///
/// **同梱の既定値表があるのはこちらだけである。** 常用館は利用者の生活圏で決まり作者が決め
/// られないので、解決順序を持たず、利用者値か未設定かの二択である。
const String settingMypageUrl = 'mypage_url';

const List<String> librarySettingKeys = [
  settingPreferredBranch,
  settingMypageUrl,
];

/// 監査記録の型。**鍵ごとに分ける。**
///
/// payload にも `key` は入っているが、`event_type` だけで「登録し直したのか、常用館だけ
/// 変えたのか」が読めるほうがよい。**型を増やしても契約は変わらない** — `domainEventType` は
/// 封筒に入らず、`recordDomainEvent` にだけ渡る端末ローカルの語彙である。
const Map<String, String> librarySettingSetEventTypes = {
  settingPreferredBranch: 'LibrarySettingPreferredBranchSet',
  settingMypageUrl: 'LibrarySettingMypageUrlSet',
};

const Map<String, String> librarySettingClearedEventTypes = {
  settingPreferredBranch: 'LibrarySettingPreferredBranchCleared',
  settingMypageUrl: 'LibrarySettingMypageUrlCleared',
};

/// 設定1件。
class LibrarySetting {
  final String systemId;
  final String key;
  final String value;

  /// 確認した日。**出典によって意味が変わる** — 既定値なら作者の採取日、取り込み値なら利用者の
  /// 取り込み日である。常用館では使わない。
  final String? checkedOn;

  const LibrarySetting({
    required this.systemId,
    required this.key,
    required this.value,
    this.checkedOn,
  });

  @override
  bool operator ==(Object other) =>
      other is LibrarySetting &&
      other.systemId == systemId &&
      other.key == key &&
      other.value == value &&
      other.checkedOn == checkedOn;

  @override
  int get hashCode => Object.hash(systemId, key, value, checkedOn);

  @override
  String toString() => 'LibrarySetting($systemId/$key)';
}

class LibrarySettings {
  final DomainContext context;

  const LibrarySettings(this.context);

  /// 集約の種。**区切りは `/` で、`system_id` に `/` を含めない**（カーリルの `systemid` は
  /// 英数字と `_` である）。
  static String seedFor(String systemId, String key) => '$systemId/$key';

  String entityIdFor(String systemId, String key) =>
      deterministicId(entityLibrarySetting, seedFor(systemId, key));

  /// 常用館を設定する。**分館一覧に在ることをここで要求する。**
  ///
  /// 以前は `LibrarySystem.validate` が持っていた不変条件である。値が別集約へ出たので、担保
  /// するのは設定の登録経路になった。**同期で届いた行は通らない** — 分館を1件消した端末と
  /// 常用館を設定した端末が独立に書けば、参照の切れた設定は正常に適用されうる。報告するのは
  /// `doctor` である（[danglingPreferredBranches]）。
  Envelope setPreferredBranch({
    required String systemId,
    required String branchId,
    required String now,
  }) {
    if (branchId.isEmpty) {
      throw const DomainError('常用館の分館IDが空です。', code: 'library-setting');
    }
    final system = LibrarySystems(context).read(systemId);
    if (system == null) {
      throw DomainError('図書館システム $systemId は登録されていません。',
          code: 'library-setting');
    }
    if (!system.hasBranch(branchId)) {
      throw DomainError('常用館 $branchId は図書館システム $systemId の分館にありません。',
          code: 'library-setting');
    }
    return _set(systemId: systemId, key: settingPreferredBranch,
        value: branchId, now: now);
  }

  Envelope clearPreferredBranch({
    required String systemId,
    required String now,
  }) =>
      _clear(systemId: systemId, key: settingPreferredBranch, now: now);

  /// マイページ URL を設定する。
  ///
  /// **セッション ID を含む URL を弾くのはここではない。** 入力経路（`karita_handoff` の
  /// `checkSaveableUrl`）が持つ — ISBN のチェック桁を `karita_handoff` に置き、`Books.adopt`
  /// には最低限しか置かないのと同じ構図である。集約側に置くと、同期で届いた行に同じ検査を
  /// 課すことになり、適用経路が止まる。
  Envelope setMypageUrl({
    required String systemId,
    required String url,
    required String checkedOn,
    required String now,
  }) {
    if (url.isEmpty) {
      throw const DomainError('マイページURLが空です。', code: 'library-setting');
    }
    return _set(systemId: systemId, key: settingMypageUrl, value: url,
        checkedOn: checkedOn, now: now);
  }

  /// 取り込み値を捨てる。**既定値表があるので、解除は「未設定」ではなく既定値へ戻ることを
  /// 意味する**（解決は `resolveMypageUrl` が行う）。
  Envelope clearMypageUrl({required String systemId, required String now}) =>
      _clear(systemId: systemId, key: settingMypageUrl, now: now);

  Envelope _set({
    required String systemId,
    required String key,
    required String value,
    String? checkedOn,
    required String now,
  }) {
    final payload = <String, Object?>{
      'system_id': systemId,
      'key': key,
      'value': value,
      if (checkedOn != null && checkedOn.isNotEmpty) 'checked_on': checkedOn,
    };
    return transaction(
      context.db,
      () => context.emit(
        entityType: entityLibrarySetting,
        entityId: entityIdFor(systemId, key),
        payload: payload,
        domainEventType: librarySettingSetEventTypes[key]!,
        aggregateType: 'library_setting',
        now: now,
      ),
    );
  }

  /// 解除は tombstone で表す。**payload は `system_id` と `key` だけである** — 消えたことを
  /// 知るのに値は要らない（`entityId` は uuid であり逆算できないので、鍵だけは運ぶ）。
  Envelope _clear({
    required String systemId,
    required String key,
    required String now,
  }) =>
      transaction(
        context.db,
        () => context.emit(
          entityType: entityLibrarySetting,
          entityId: entityIdFor(systemId, key),
          payload: <String, Object?>{'system_id': systemId, 'key': key},
          domainEventType: librarySettingClearedEventTypes[key]!,
          aggregateType: 'library_setting',
          now: now,
          operation: operationTombstone,
          isDeleted: true,
        ),
      );

  /// 1件を引く。**解除されていれば `null`。**
  LibrarySetting? read(String systemId, String key) {
    final row = context.aggregates
        .read(context.db, entityLibrarySetting, entityIdFor(systemId, key));
    if (row == null || (row['is_deleted'] as int? ?? 0) != 0) return null;
    return _rowToSetting(row);
  }

  String? valueOf(String systemId, String key) => read(systemId, key)?.value;

  /// 登録済みの設定を読む。tombstone は含めない。
  ///
  /// **`validate` に当たるものを呼ばない**（`LibrarySystems.load` と同じ）。名前空間のずれた
  /// 実装から同じ種の別 id が届くと重複が立ちうるが、そこで例外にすると業務のコマンドが全部
  /// 止まる。報告するのは `doctor` である。
  List<LibrarySetting> load() {
    final settings = <LibrarySetting>[];
    for (final row in context.db.select(
        'SELECT * FROM library_settings WHERE is_deleted = 0 '
        'ORDER BY system_id, key')) {
      final setting = _rowToSetting(row);
      if (setting != null) settings.add(setting);
    }
    return settings;
  }

  /// 参照の切れた常用館。**`doctor` が報告する。**
  ///
  /// 「まだ届いていない」と「分館が消えた」を区別しない — どちらも「参照先が今は無い」で
  /// あり、行を消さずに人へ上げるという扱いは同じである（`dangling-membership-system` と
  /// 同じ判断）。
  List<LibrarySetting> danglingPreferredBranches() {
    final systems = {
      for (final system in LibrarySystems(context).load().librarySystems)
        system.id: system,
    };
    return [
      for (final setting in load())
        if (setting.key == settingPreferredBranch &&
            !(systems[setting.systemId]?.hasBranch(setting.value) ?? false))
          setting,
    ];
  }

  /// 読めない行は `null` を返す。**その1行で業務のコマンド全体を止めない。**
  LibrarySetting? _rowToSetting(Map<String, Object?> row) {
    final payload = context.mapping.rowToPayload(entityLibrarySetting, row);
    final systemId = payload['system_id'];
    final key = payload['key'];
    final value = payload['value'];
    if (systemId is! String || key is! String || value is! String) return null;
    if (!librarySettingKeys.contains(key)) return null;
    return LibrarySetting(
      systemId: systemId,
      key: key,
      value: value,
      checkedOn: payload['checked_on'] as String?,
    );
  }
}
