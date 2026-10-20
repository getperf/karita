/// ③ プラットフォーム適配の**純 Dart 分**。`karita_sync` が定義する port の実装側である。
///
/// この向き（`karita_platform → karita_sync`）を守ることで、Flutter への依存が
/// `karita_platform_flutter` と harness に閉じ、conformance runner と単体試験が Dart VM で
/// 回り続ける。
///
/// 持つのは **`appDataFolder` を転送先・保管先にする2つの実装、その下の狭い口、口の向こうの
/// REST adapter と認可、既定パスの解決と端末設定の読み書き**である。実 Drive の検証は3層に
/// 割ってあり、**3層とも閉じた。**
///
/// **端末設定（`device.json`）がここにあるのは、置き場所を決めているのが ③ だからである。**
/// 水準や書式の語彙は持たない — それを知っているのはログの側（`karita_app`）である。
///
/// - **層1**: 偽クライアントに対して、判定・整列・重複排除・二段名・検算・有効世代の決定を
///   全部通す。token もネットワークも要らない
/// - **層2**: 偽 Drive サーバに対する REST adapter。要求の組み立て、resumable upload、
///   `pageToken` のループ、`incoming-` から本名への改名、チャンク download、401 と
///   `invalid_grant` の分類。**口は非同期にした** — Dart に同期 HTTP が無いためである
/// - **層3**: 実 Drive。Google が実際にどう振る舞うかだけを測る（`dart test -P drive`）
///
/// Android の認可は Flutter プラグインを要るので `karita_platform_flutter` が持つ。
/// とくに「置き換えが無い」「401 が HTTP status として出てこないことがある」は実装に直接効く。
library;

export 'src/access_token.dart';
export 'src/app_paths.dart';
export 'src/browser_choice.dart';
export 'src/credentials.dart';
export 'src/device_settings.dart';
export 'src/drive_backup_store.dart';
export 'src/drive_client.dart';
export 'src/drive_errors.dart';
export 'src/drive_transport.dart';
export 'src/environment_doctor.dart';
export 'src/google_auth.dart';
export 'src/oauth.dart';
export 'src/rest_drive_client.dart';
export 'src/share_inbox.dart';
export 'src/token_protection.dart';

export 'src/export_delivery.dart';
