/// 観測タブ。**台帳と転送先の生値を並べるだけ。**
///
/// 出すのは outbox・pending・conflicts の件数と行、転送先の封筒一覧、世代の seq、device_id、
/// 所有検査の違反である。**判定も要約もしない** — 何が起きているかを読むのは人間の側で、
/// ここで言い換えると、その言い換えが本番 GUI と食い違う。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:karita_app/karita_app.dart';
// **`setState` を隠す。** `karita_contract` の `setState(Db, key, value)` と Flutter の
// `State.setState` が同じ名前で衝突する。台帳へ書くのは合成層と業務層の仕事で、観測タブは
// 読むだけなので、隠して困らない。
import 'package:karita_contract/karita_contract.dart' hide setState;
import 'package:karita_sync/karita_sync.dart';

import '../raw.dart';

class ObservationTab extends StatefulWidget {
  final Composition composition;

  const ObservationTab(this.composition, {super.key});

  @override
  State<ObservationTab> createState() => _ObservationTabState();
}

class _ObservationTabState extends State<ObservationTab> {
  /// 転送先の一覧。**取りに行くのは押されたときだけである。**
  ///
  /// 画面を開くたびに一覧すると、実 Drive に対して勝手に要求が飛ぶ。何回叩いたかを数えられる
  /// 状態を保つ。
  List<Map<String, Object?>>? _remote;
  String? _remoteError;
  bool _busy = false;

  Composition get c => widget.composition;

  @override
  Widget build(BuildContext context) {
    final db = c.db;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const RawHeading('identity'),
        RawRow('deviceId', c.deviceId),
        RawRow('profile', defaultProfile),
        RawRow('home', c.paths.home),
        RawRow('dbPath', c.paths.dbPath),
        RawRow('auth.kind', c.auth.kind),
        const RawHeading('generation'),
        RawRow('localGeneration', _localGeneration(db)),
        const RawHeading('counts'),
        for (final state in ['pending', 'sent', 'failed', 'blocked_auth'])
          RawRow('outbox_events[$state]', _countOutbox(db, state)),
        RawRow('applied_events', _count(db, 'applied_events')),
        RawRow('domain_events', _count(db, 'domain_events')),
        RawRow('pending_events', _count(db, 'pending_events')),
        // **開いている件数と全件を並べる。** 開いている数だけでは「競合が立たなかった」と
        // 「立って決着した」が同じ 0 に見える。`run(run)` は適用フェーズの末尾で自動解決するので、
        // **競合行は同じ run の中で `resolved` になる** — 押した直後に開いているものは普通は無い。
        RawRow('conflicts[open]', _count(db, 'conflicts', "state = 'open'")),
        RawRow('conflicts', _count(db, 'conflicts')),
        RawRow('books', _count(db, 'books')),
        RawRow('loans', _count(db, 'loans')),
        RawRow('library_systems', _count(db, 'library_systems')),
        RawRow('ownershipViolations', _violations(db)),
        RawRows('pendingCountsByReason', _reasons(db)),
        RawRows('outbox_events', _rows(db, 'listOutbox')),
        // **決着したものも出す。** `local_payload_hash` と `remote_payload_hash` は
        // LWW の決定キーそのもので、**二端末が同じ勝者を選んだことはここでしか直接読めない。**
        // 開いているものだけを見せると、自動解決した直後は空になり、何も残らない。
        RawRows('conflicts', _rows(db, 'listConflicts')),
        RawRows('pending_events', _rows(db, 'listPending')),
        RawRows('sync_state', _select(db, 'SELECT * FROM sync_state')),
        RawRows(
          'sync_runs',
          _select(db, 'SELECT * FROM sync_runs ORDER BY started_at_utc DESC'),
        ),
        const RawHeading('doctor'),
        Wrap(children: [
          RawAction('doctor()', _busy ? null : _loadDoctor),
        ]),
        if (c.lastDoctor == null)
          // **「まだ走らせていない」を「異常が無い」と混ぜない。**
          const RawRow('doctor', 'not run')
        else ...[
          RawRow('failed', c.lastDoctor!.failed),
          RawRow('checked',
              [for (final v in c.lastDoctor!.checked) v.name].join(' ')),
          RawRow('not_checked',
              [for (final v in c.lastDoctor!.notChecked) v.name].join(' ')),
          RawRows('findings', [
            for (final finding in c.lastDoctor!.findings) finding.toMap(),
          ]),
        ],
        const RawHeading('remote'),
        Wrap(children: [
          RawAction('transport.list()', _busy ? null : _loadRemote),
        ]),
        if (_remoteError != null) RawRow('error', _remoteError),
        if (_remote != null) RawRows('envelopes', _remote!),
      ],
    );
  }

  void _loadDoctor() {
    setState(() => _busy = true);
    unawaited(_readDoctor());
  }

  Future<void> _readDoctor() async {
    try {
      await c.runDoctor();
    } on Object catch (error) {
      // **診断そのものが落ちたことを隠さない。** 落ちる診断は「異常が無い」ではない。
      c.lastDoctor = DoctorReport(
        checked: const {},
        findings: [DoctorFinding(DoctorCheck.deviceId, 1, '$error')],
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
  }

  void _loadRemote() {
    setState(() {
      _busy = true;
      _remoteError = null;
    });
    unawaited(_readRemote());
  }

  Future<void> _readRemote() async {
    List<Map<String, Object?>>? found;
    String? failure;
    try {
      final generation = localGeneration(c.db);
      if (generation == null) {
        failure = 'localGeneration == null';
      } else {
        // **`establish: false`。** 観測が世代を立ててはいけない — 一覧を見ただけで有効世代が
        // 進むと、同じ `appDataFolder` を見ている実端末が `generation-changed` で止まる。
        final transport = await c.engine.activeTransport(
          establish: false,
          now: nowUtc(),
        );
        found = [
          for (final event in await transport.list())
            {
              'eventId': event.eventId,
              'remoteId': event.remoteId,
              'duplicates': event.duplicateRemoteIds.length,
            },
        ];
      }
    } on Object catch (error) {
      failure = '$error';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _remote = found;
      _remoteError = failure;
    });
  }

  /// **読み取りで落ちない。** 台帳がまだ無い段でも観測タブは開ける必要がある。
  Object? _guard(Object? Function() read) {
    try {
      return read();
    } on Object catch (error) {
      return '$error';
    }
  }

  Object? _localGeneration(Db db) => _guard(() {
        final generation = localGeneration(db);
        return generation == null ? null : '$generation';
      });

  Object? _countOutbox(Db db, String state) =>
      _guard(() => countOutbox(db, state));

  Object? _violations(Db db) =>
      _guard(() => ownershipViolations(db).length);

  Object? _count(Db db, String table, [String? where]) => _guard(() {
        final clause = where == null ? '' : ' WHERE $where';
        return db.select('SELECT COUNT(*) AS n FROM $table$clause').first['n'];
      });

  List<Map<String, Object?>> _reasons(Db db) {
    try {
      return [
        for (final entry in pendingCountsByReason(db).entries)
          {'reason': entry.key, 'n': entry.value},
      ];
    } on Object catch (error) {
      return [
        {'error': '$error'},
      ];
    }
  }

  List<Map<String, Object?>> _rows(Db db, String which) {
    try {
      return switch (which) {
        'listOutbox' => listOutbox(db),
        // **state で絞らない。** 隣の `listOutbox` と `listPending` も全件である。
        'listConflicts' => listConflicts(db),
        'listPending' => listPending(db),
        _ => const [],
      };
    } on Object catch (error) {
      return [
        {'error': '$error'},
      ];
    }
  }

  List<Map<String, Object?>> _select(Db db, String sql) {
    try {
      return db.select(sql);
    } on Object catch (error) {
      return [
        {'error': '$error'},
      ];
    }
  }
}
