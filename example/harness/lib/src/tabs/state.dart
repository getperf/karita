/// 状態タブ。**`SyncStatus` をそのまま出す。**
///
/// `SyncEngine.status()` が返すものを `toMap()` で平らにして並べるだけである。enum は
/// `state.name` の識別子のまま出す — 表示名・アイコン・色、「更新・再ログイン・完全復元・
/// 手修正」への言い換えは本番 GUI（`../karita-ui-probe`）が持つ。
///
/// **7状態の導出をここでやらない。** 内部状態から状態を決める規則をエンジンに置いたのは、
/// UI 側に置くと本番 GUI と別クライアントが別々の規則を書くからである。ここが規則を持てば、
/// harness がその「別のクライアント」になる。
library;

import 'package:flutter/material.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_sync/karita_sync.dart';

import '../raw.dart';

class StateTab extends StatefulWidget {
  final Composition composition;

  const StateTab(this.composition, {super.key});

  @override
  State<StateTab> createState() => _StateTabState();
}

class _StateTabState extends State<StateTab> {
  /// 導出の入力。**推測で埋めない** — 渡さなかった分は導出も見ない。
  bool _offline = false;

  /// 診断の結果を無視して立てる。**切り分けの道具である。**
  ///
  /// 本来の `doctorFailed` は観測タブで走らせた `doctor()` の結果から来る。導出の枝を
  /// 手で通したいときだけこちらを立てる。
  bool _forceDoctorFailed = false;

  /// 導出へ渡す値。**「まだ走らせていない」は `false` である** — 診断していない端末を
  /// 「要対応」にはしない。走らせていないこと自体は下に生値で出る。
  bool get _doctorFailed =>
      _forceDoctorFailed || (widget.composition.lastDoctor?.failed ?? false);

  @override
  Widget build(BuildContext context) {
    final SyncStatus? status = _status();
    final doctor = widget.composition.lastDoctor;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const RawHeading('inputs'),
        Row(children: [
          Switch(
            value: _offline,
            onChanged: (value) => setState(() => _offline = value),
          ),
          const RawRow('offline', null),
        ]),
        Row(children: [
          Switch(
            value: _forceDoctorFailed,
            onChanged: (value) => setState(() => _forceDoctorFailed = value),
          ),
          const RawRow('forceDoctorFailed', null),
        ]),
        RawRow('offline', _offline),
        RawRow('forceDoctorFailed', _forceDoctorFailed),
        RawRow('doctor.lastRun', doctor == null ? 'not run' : 'done'),
        RawRow('doctor.failed', doctor?.failed),
        RawRow('doctorFailed', _doctorFailed),
        const RawHeading('SyncStatus'),
        if (status == null)
          const RawRow('status', 'unavailable')
        else ...[
          RawRow('state', status.state.name),
          RawRow('lastSuccessAt', status.lastSuccessAt),
          RawRow('autoResolved', status.autoResolved),
          const RawHeading('facts'),
          RawMap(status.facts.toMap()),
        ],
        const RawHeading('SyncState declaration order'),
        // **宣言順が導出の順である。** 最初に当たったものが状態になる。並べ替えない。
        for (final value in SyncState.values) RawRow(value.name, value.index),
      ],
    );
  }

  SyncStatus? _status() {
    try {
      return widget.composition.engine.status(
        now: nowUtc(),
        offline: _offline,
        doctorFailed: _doctorFailed,
      );
    } on Object {
      return null;
    }
  }
}
