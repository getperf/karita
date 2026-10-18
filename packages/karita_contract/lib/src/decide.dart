/// 受信イベントの適用判定。**純関数である。**
///
/// **この層は SQLite も転送も知らない。** 封筒から読める値と、ローカルの状態を写した
/// `LocalState` だけを受け取り、判定表の6行を上から順に評価して最初に一致した行の動作を返す。
/// とくに `baseVersion` > 現在版（gap）と `baseVersion` < 現在版（conflict）は入力の形が同じで
/// 結果が逆であり、取り違えると正常な更新が競合として滞留するか、競合が黙って適用される。
///
/// 移送元: book-sync-model の `src/bsync_core/decide.py`。
library;

const String pendingSchema = 'pending_schema';
const String ignore = 'ignore';
const String applyResolution = 'apply_resolution';
const String pendingGap = 'pending_gap';
const String apply = 'apply';
const String conflict = 'conflict';

const Map<String, String> reasonByAction = {
  pendingSchema: 'schema',
  pendingGap: 'gap',
};

class LocalState {
  final int currentVersion;
  final Set<String> appliedEventIds;
  final Set<String> openConflictRemoteEventIds;
  final Set<String> localEventIds;

  const LocalState({
    required this.currentVersion,
    this.appliedEventIds = const {},
    this.openConflictRemoteEventIds = const {},
    this.localEventIds = const {},
  });
}

class Decision {
  final String action;
  final String reason;
  final int row;

  const Decision(this.action, this.reason, this.row);

  String? get pendingReason => reasonByAction[action];
}

Decision decide({
  required int schemaVersion,
  required String eventId,
  required int baseVersion,
  required Set<int> supportedSchemaVersions,
  Iterable<String> resolvesEventIds = const [],
  required LocalState state,
}) {
  // **受理する版は集合である。** 発行版との一致で判定すると、版を上げた瞬間に転送先へ残る
  // 旧版の封筒がすべてこの行へ落ち、恒久滞留する。
  if (!supportedSchemaVersions.contains(schemaVersion)) {
    final accepted = (supportedSchemaVersions.toList()..sort()).join('・');
    return Decision(
      pendingSchema,
      '未対応の schemaVersion $schemaVersion（この実装が受理するのは $accepted）。破棄せず、適用済みにもしない。',
      1,
    );
  }

  if (state.appliedEventIds.contains(eventId)) {
    return Decision(ignore, 'applied_events にあるため無視する（冪等）。', 2);
  }

  final resolves = resolvesEventIds.toSet();
  // 版判定を迂回する唯一の行。条件を「resolvesEventIds が空でない」に緩めると、第三の端末が
  // 別の競合を決着させたイベントが、無関係なローカルの更新を無検査で上書きする。
  final settled = resolves
      .intersection(state.openConflictRemoteEventIds.union(state.localEventIds));
  if (settled.isNotEmpty) {
    return Decision(
      applyResolution,
      '自端末の未解決conflictまたは自端末発行イベントを決着させるため、版判定を迂回して適用する。',
      3,
    );
  }

  if (baseVersion > state.currentVersion) {
    return Decision(
      pendingGap,
      'baseVersion $baseVersion が現在版 ${state.currentVersion} より大きい。先行イベントが未着なだけであり競合ではない。',
      4,
    );
  }

  if (baseVersion == state.currentVersion) {
    return Decision(apply, 'baseVersion が現在版 ${state.currentVersion} と一致する。', 5);
  }

  return Decision(
    conflict,
    'baseVersion $baseVersion が現在版 ${state.currentVersion} より小さい。自動適用しない。',
    6,
  );
}

// --- 自動解決（LWW）------------------------------------------------------------
// **純関数であることが要である。** 二端末は同じ競合について同じ二つの決定キーを比較するため、
// 独立に解いても同じ勝者を選ぶ。

const String autoLocal = 'local';
const String autoRemote = 'remote';

/// LWW の決定キー。競合した2イベントそれぞれの (業務時刻, 端末, payloadHash)。
class Side {
  final String occurredAtUtc;
  final String deviceId;
  final String payloadHash;

  const Side(this.occurredAtUtc, this.deviceId, this.payloadHash);
}

/// 決定的 last-writer-wins。キー `(occurredAtUtc, deviceId, payloadHash)` の大きい側を採る。
///
/// 第3キーに eventId でなく payloadHash を使う理由の正本は設計文書にある。要点は、
/// payloadHash は封筒にもローカル集約にも同値であり、どちらの端末から見ても必ず一致するため、
/// 二端末が同じ勝者を選べること。同一キー（内容一致）は remote を採って停止させる。
String autoTake({required Side local, required Side remote}) {
  return _keyGreater(local, remote) ? autoLocal : autoRemote;
}

bool _keyGreater(Side a, Side b) {
  // ASCII の時刻・deviceId・sha256hex なので compareTo（UTF-16）は Python のコードポイント比較と一致する。
  final byTime = a.occurredAtUtc.compareTo(b.occurredAtUtc);
  if (byTime != 0) return byTime > 0;
  final byDevice = a.deviceId.compareTo(b.deviceId);
  if (byDevice != 0) return byDevice > 0;
  return a.payloadHash.compareTo(b.payloadHash) > 0;
}
