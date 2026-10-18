/// 操作タブ。**CLI と一対一の操作、初回起動の2択、サインイン、業務操作。**
///
/// **確認ダイアログを持たない**（`--yes` 相当である）。不可逆性を伝える文言は本番 GUI の
/// 仕事であり、ここに置いたものは本番 GUI の断片になる。
///
/// **順序をここで組まない。** 初回起動の裏の「サインイン → 一覧 → 選択 → 検証 → 起点を公開 →
/// 置換」はエンジンの `setupFromBackup()` が閉じている。ここが持つのは2択の提示だけである。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_sync/karita_sync.dart';

import '../raw.dart';

class OperationsTab extends StatefulWidget {
  final Composition composition;

  const OperationsTab(this.composition, {super.key});

  @override
  State<OperationsTab> createState() => _OperationsTabState();
}

class _OperationsTabState extends State<OperationsTab> {
  final _backupId = TextEditingController();
  final _isbn13 = TextEditingController();
  final _title = TextEditingController();
  final _authors = TextEditingController();
  final _systemId = TextEditingController();
  final _loanId = TextEditingController();
  final _bookId = TextEditingController();

  /// 直近の結果。**生値である。** 成功も失敗も同じ場所に出す。
  Object? _result;
  bool _busy = false;

  Composition get c => widget.composition;

  @override
  void dispose() {
    for (final field in [
      _backupId,
      _isbn13,
      _title,
      _authors,
      _systemId,
      _loanId,
      _bookId,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  /// **例外も結果である。** 握り潰すと、赤が出たときに何が起きなかったのか分からない。
  Future<void> _run(Future<Object?> Function() body) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    Object? outcome;
    try {
      outcome = await body();
    } on Object catch (error) {
      outcome = '$error';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = outcome;
    });
  }

  /// [gated] は**転送・認可・ファイルへ触る操作**に立てる。
  ///
  /// デモでは合成層の口が本体を呼ぶ前に飛ばすので、**通信もファイル操作も始まらない。**
  /// 業務の操作には立てない — デモで動かすのはそちらである。
  void _call(Future<Object?> Function() body, {bool gated = false}) {
    if (_busy) return;
    unawaited(_run(gated ? () => _gated(body) : body));
  }

  /// 飛ばしたときは**識別子だけを出す。** 規則1（文言を書かない）のままである。
  Future<Object?> _gated(Future<Object?> Function() body) async {
    final attempt = await c.gate.run(body);
    return attempt.wasSkipped
        ? {'skipped': attempt.skipped!.name, 'mode': c.mode.demo.name}
        : attempt.value;
  }

  @override
  Widget build(BuildContext context) {
    final engine = c.engine;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const RawHeading('auth'),
        Wrap(children: [
          RawAction('signIn', _busy ? null : () => _call(_signIn, gated: true)),
          RawAction('signOut', _busy ? null : () => _call(_signOut, gated: true)),
        ]),
        const RawHeading('first-run'),
        Wrap(children: [
          RawAction(
            'setupFresh()',
            _busy ? null : () => _call(_setupFresh, gated: true),
          ),
          RawField('backupId', _backupId, width: 320),
          RawAction(
            'setupFromBackup(backupId)',
            _busy ? null : () => _call(_setupFromBackup, gated: true),
          ),
        ]),
        const RawHeading('sync'),
        Wrap(children: [
          // **モードは `karita_sync` の定数から出す。** ここに文字列を書くと、`sync_runs` の
          // `CHECK (mode IN ('push','pull','run'))` に載っていない値を渡しうる。
          for (final mode in [modeRun, modePush, modePull])
            RawAction(
              'run($mode)',
              _busy ? null : () => _call(() => _runMode(mode), gated: true),
            ),
        ]),
        // **読むだけの操作を先に置く。** 実機確認（P4a）はこの2つで閉じ、転送先へ何も書かない。
        const RawHeading('read-only'),
        Wrap(children: [
          RawAction('backup list', _busy ? null : () => _call(_listBackups, gated: true)),
          RawAction('baseline list', _busy ? null : () => _call(_listBaselines, gated: true)),
        ]),
        const RawHeading('backup (writes)'),
        Wrap(children: [
          RawAction('export', _busy ? null : () => _call(_export, gated: true)),
          RawAction(
            'backup delete --id',
            _busy
                ? null
                : () => _call(
                      () => engine.deleteBackup(_backupId.text.trim()),
                      gated: true,
                    ),
          ),
          RawAction('import --id', _busy ? null : () => _call(_importById, gated: true)),
          RawAction(
            'import --baseline',
            _busy ? null : () => _call(_importBaseline, gated: true),
          ),
          RawAction(
            'reset empty',
            _busy ? null : () => _call(_resetEmpty, gated: true),
          ),
        ]),
        const RawHeading('domain'),
        Wrap(children: [
          RawField('isbn13', _isbn13),
          RawField('title', _title),
          RawField('authors', _authors),
          RawAction('book adopt', _busy ? null : () => _call(_adopt)),
        ]),
        Wrap(children: [
          RawField('systemId', _systemId),
          RawAction(
            'system register',
            _busy ? null : () => _call(_registerSystem),
          ),
          RawAction(
            'system remove',
            _busy
                ? null
                : () => _call(() => Future.value(c.librarySystems.remove(
                      systemId: _systemId.text.trim(),
                      now: nowUtc(),
                    ))),
          ),
        ]),
        Wrap(children: [
          RawField('loanId', _loanId),
          RawField('bookId', _bookId),
          for (final status in ['reserved', 'borrowed'])
            RawAction(
              'loan start($status)',
              _busy ? null : () => _call(() => _startLoan(status)),
            ),
          // **遷移の名前は `loanTransitions` のキーそのものである。** 言い換えない。
          for (final action in ['ready-for-pickup', 'borrow', 'return', 'cancel'])
            RawAction(
              'loan update($action)',
              _busy ? null : () => _call(() => _updateLoan(action)),
            ),
        ]),
        const RawHeading('result'),
        SelectableText(
          _busy ? 'running' : '${_result ?? 'null'}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    );
  }

  Future<Object?> _signIn() async {
    await c.auth.signIn();
    return c.auth.kind;
  }

  Future<Object?> _signOut() async {
    await c.auth.signOut();
    return c.auth.kind;
  }

  Future<Object?> _runMode(String mode) async {
    final result = await c.engine.run(mode, now: nowUtc());
    return {
      'runId': result.runId,
      'mode': result.mode,
      'generationId': result.generation.generationId,
      'seq': result.generation.seq,
      'counts': result.counts,
      'pushed': result.pushed.length,
      'stopped': result.stopped.length,
      'pullError': result.pullError,
    };
  }

  Future<Object?> _export() async {
    final outcome = await c.engine.exportBackup(now: nowUtc());
    return {
      'backupId': outcome.backupId,
      'storedIn': outcome.storedIn,
      'location': outcome.location,
      'bytes': outcome.bytes,
      'manifest': outcome.manifest,
    };
  }

  /// **読むだけである。** 転送先へ何も書かない。実機確認はここで閉じる。
  Future<Object?> _listBackups() async {
    final listing = await c.engine.listBackups();
    return {
      'n': listing.refs.length,
      'skipped': listing.skipped,
      'refs': [
        for (final ref in listing.refs)
          {
            'backupId': ref.backupId,
            'createdAtUtc': ref.createdAtUtc,
            'bytes': ref.sizeBytes,
            'summary': ref.summary,
            'duplicates': ref.duplicateRemoteIds.length,
          },
      ],
    };
  }

  /// 起点の一覧。**読むだけである。** `seq` の最大が有効世代である。
  ///
  /// **Windows と Android がここで同じものを見ることが、P4a の主張そのものである** —
  /// 別々に登録した OAuth クライアントが同じ `appDataFolder` を共有している、ということ。
  Future<Object?> _listBaselines() async {
    final baselines = await c.engine.store.listBaselines();
    return {
      'n': baselines.length,
      'baselines': [
        for (final ref in baselines)
          {
            'seq': ref.seq,
            'generationId': ref.generationId,
            'bytes': ref.sizeBytes,
          },
      ],
    };
  }

  /// 復元の結果。**4つの口が同じ形で出ることが要る。**
  ///
  /// `RestoreOutcome` を表示へそのまま渡すと `toString()` の既定が働き、`Instance of
  /// 'RestoreOutcome'` になる。**押した記録が型名しか残らない。**
  ///
  /// **`declared` が本体である。** 宣言（新しい世代を始めた）なら true、参加（有効世代の
  /// 起点へ戻った）なら false。`_restore()` が起点を公開したかと一対一なので、
  /// `import --baseline` が世代を進めていないことは、これでしか直接には読めない —
  /// 一覧の差からは「起点が増えなかった」という*起きなかったこと*しか取れない。
  ///
  /// `source` は `<store.kind> / baseline 0002` か `<store.kind> / <backupId>` で、
  /// **`declared` とは別の経路で**どちらから戻したかを答える。
  Map<String, Object?> _restored(RestoreOutcome outcome) => {
        'source': outcome.source,
        'backupId': outcome.backupId,
        'generationId': outcome.generationId,
        'seq': outcome.seq,
        'declared': outcome.declared,
        'counts': outcome.counts,
      };

  /// **これは宣言にならない。** 起点が既にあれば `adopt` で `seq` は進まない。
  /// `state` がそれを名前で答える — `bootstrap` なら起点を置き、`adopt` なら乗るだけである。
  Future<Object?> _setupFresh() async {
    // **合成層の窓口を通す。** 種モードの転送先の掃除がその中に挟まる。
    final resolution = await c.setupFresh();
    return {
      'state': resolution.state,
      'generationId': resolution.generationId,
      'seq': resolution.seq,
      'needsBaseline': resolution.needsBaseline,
    };
  }

  /// **合成層の窓口を通す**（2026-09-23。単位C）。本番 GUI の2択が通る経路と同じにする。
  Future<Object?> _setupFromBackup() async =>
      _restored(await c.setupFromBackup(_backupId.text.trim()));

  Future<Object?> _importById() async => _restored(
        await c.engine.restoreFromBackup(
          backupId: _backupId.text.trim(),
          now: nowUtc(),
        ),
      );

  Future<Object?> _importBaseline() async =>
      _restored(await c.engine.restoreFromBaseline(now: nowUtc()));

  /// 空の台帳を新しい正本として宣言する。手順は `import --id` と同じで、**空DBをその場で
  /// 作ってから渡すだけの違い**である（[SyncEngine.restoreEmpty]）。
  Future<Object?> _resetEmpty() async =>
      _restored(await c.engine.restoreEmpty(now: nowUtc()));

  Future<Object?> _adopt() async {
    final envelope = c.books.adopt(
      title: _title.text.trim(),
      authors:
          _authors.text.trim().split(',').where((a) => a.isNotEmpty).toList(),
      isbn13: _isbn13.text.trim(),
      provider: 'harness',
      now: nowUtc(),
    );
    return {'eventId': envelope.eventId, 'entityId': envelope.entityId};
  }

  /// 分館の id を `systemId` から導く。**入力欄を増やさないためである。**
  ///
  /// 分館は2か所で要る — `system register` の不変条件（1つ以上）と、`loan start` の受取館で
  /// ある。**同じ値でなければならない**わけではない（`loans` は実在を検査しない）が、揃えて
  /// おかないと、登録した分館と Loan が指す館が別物になり、記録を読むときに突き合わせられない。
  ///
  /// 2026-09-13 に貸出館が消え、館は受取館の1つだけになった。
  String _branchId() => '${_systemId.text.trim()}-1';

  Future<Object?> _registerSystem() async {
    // **値は systemId の1つだけを受ける。** 管理区の中身を harness で編集できるようにすると、
    // 入力フォームの設計が始まり、それは本番 GUI の仕事になる。同期に要るのは実体が1つ立つ
    // ことだけである。
    final id = _systemId.text.trim();
    // **分館を1つ持たせる。** `LibrarySystem.validate()` が1つ以上を要求するので、空の配列では
    // どんな systemId でも `library-system` で落ちる。`calilLibkey` は外部照会に使わないので
    // id と同じ値でよい — ここが要るのは実体が1つ立つことだけである。
    final branch = _branchId();
    final envelope = c.librarySystems.register(
      system: LibrarySystem(
        id: id,
        pref: id,
        city: id,
        name: id,
        branches: [Branch(id: branch, calilLibkey: branch, name: branch)],
      ),
      now: nowUtc(),
    );
    return {'eventId': envelope.eventId, 'entityId': envelope.entityId};
  }

  Future<Object?> _startLoan(String status) async {
    // **受取館を渡す。** `reserved` も `borrowed` も受取館を要求する — 渡さないと
    // どちらの状態でも `pickup-library` で必ず落ちる。
    final envelope = c.loans.start(
      loanId: _loanId.text.trim(),
      bookId: _bookId.text.trim(),
      status: status,
      systemId: _systemId.text.trim(),
      pickupLibraryId: _branchId(),
      now: nowUtc(),
    );
    return {'eventId': envelope.eventId, 'entityId': envelope.entityId};
  }

  Future<Object?> _updateLoan(String action) async {
    // **館を渡さない。** `borrow` は行に入っている受取館を引き継ぐ。渡す口はもう無い。
    final envelope = c.loans.update(
      loanId: _loanId.text.trim(),
      action: action,
      now: nowUtc(),
    );
    return {'eventId': envelope.eventId, 'entityId': envelope.entityId};
  }
}
