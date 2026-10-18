/// 端末と台帳の素性、推測できない乱数。**`Random()` を使わない。**
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:karita_contract/karita_contract.dart';

/// **本番に profile は無い。** 1端末1台帳である。台帳の欄を埋めるためだけに1つ持つ。
const String defaultProfile = 'default';

/// 推測できない乱数の供給元。**`Random()` ではない。**
///
/// PKCE の verifier と `state` に渡る。**`state` を当てられると、他所で始めた認可の結果を
/// 受け取らせる経路ができる。** `tools/drive_probe` が同じ理由で同じ形を採っている。
final Random _secure = Random.secure();

String ensureDeviceId(Db db, {required String at}) {
  final existing = getState(db, stateDeviceId);
  if (existing != null) return existing;
  // **`<platform>-<uuid4>`。** `platformOf` が先頭の `-` までを切って版の別に使う。
  final id = '${Platform.operatingSystem}-${newUuid()}';
  transaction(db, () {
    setState(db, stateDeviceId, id);
    setState(db, stateProfileName, defaultProfile);
    if (getState(db, stateCreatedAtUtc) == null) {
      setState(db, stateCreatedAtUtc, at);
    }
  });
  return id;
}

/// uuid4。**UUID でないと、転送先に置いたものが一覧に出ない。**
///
/// `backup-<backupId>.blib` と `baseline-<seq>-<generationId>.blib` は、一覧が**本文を取る前に
/// 名前で切る**（`karita_contract` の `parseBackupName` / `parseBaselineName` が UUID を要求する）。
/// 落ちたものは `BackupListing.skipped` にも数えられない — あれは「索引を読めなかった `.blib`」で
/// あって、名前で落ちたものはそこへ来ない。**`n: 0` として静かに消える。**
///
/// 2026-09-04 に実 Drive でそれを踏んだ。`export` は成功して 7355 バイトが載ったのに
/// `backup list` が `{n: 0, skipped: 0}` を返した。**`generationId` にも同じ検査が掛かるので、
/// 宣言した世代が誰にも見えない**という形でキャンペーンが1段目から成立しなかった。
String newUuid() {
  final bytes = List<int>.generate(16, (_) => _secure.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = [
    for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// PKCE の verifier と `state`。**推測できてはならない。**
///
/// 48 バイトを base64url にすると 64 文字で、Google が許す 43〜128 の範囲に収まる。
String randomToken() => base64Url
    .encode(List<int>.generate(48, (_) => _secure.nextInt(256)))
    .replaceAll('=', '');
