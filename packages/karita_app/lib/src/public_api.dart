/// 外部 API（OpenBD・カーリル）の合成。**キーを決めるのはここだけである。**
///
/// `karita_public_api_client` はキーを引数で受け取るだけで、どこから来た値かを知らない。
/// 保管の場所を知っているのは `karita_platform`（`device.json`）で、ビルドに焼き込まれた値を
/// 知っているのはこの層だけである。**3つが別々なのは意図である** — クライアントが保管先を
/// 知ると、試験のたびに端末の設定を要る。
///
/// **キーの値をログにも所見にも出さない。** 出すのは「どちらを採ったか」だけである。
/// → `非公開資料:settings-and-parameters.md#appkey-の置き場と項目名2026-09-15決定`
library;

/// ビルドに焼き込まれたカーリルの appkey。**空が既定である。**
///
/// 渡すのは `tools/run-dev.ps1`（`.env` を `--dart-define-from-file` でビルドへ）。
/// **配布物からこの値を取り出せる前提で置いている** — 秘匿の手段ではなく、利用者に個人キーの
/// 取得を求めないための同梱値である。
const String defineCalilAppkey = String.fromEnvironment('KARITA_CALIL_APPKEY');

/// キーをどこから採ったか。**値そのものの代わりにログへ出す。**
enum CalilKeySource {
  /// `device.json` の `calil.appkey`。**同梱値より優先する。**
  deviceOverride,

  /// ビルドに焼き込まれた同梱値。
  bundled,

  /// どちらも無い。
  none,
}

/// 採ったキーと、その出どころ。
class CalilKeyChoice {
  /// 採った値。**[usable] が `false` なら空文字である。**
  final String key;

  final CalilKeySource source;

  const CalilKeyChoice(this.key, this.source);

  /// 照会に使えるか。
  ///
  /// **使えないことは、蔵書が無いことではない。** 使えないときに閉じるのは蔵書照会と図書館
  /// 候補の取得だけで、本棚の閲覧も書誌の登録も予約の記録も続けられる。
  bool get usable => key.isNotEmpty;

  /// ログの1行へ載せる分。**値を載せない。**
  Map<String, Object?> toLogFields() => {'calil_key': source.name};
}

/// 端末上書きと同梱値から、使うキーを決める。
///
/// 優先順位は**端末上書き、同梱値、無しの順**である。端末で差した人はその端末で差した理由が
/// あり、同梱値がそれを覆すと差した意味が消える。
///
/// 空白だけの値は「無い」と同じに扱う。**書き損じを「設定してある」と数えない** — 数えると、
/// 照会が 401 で落ち続ける理由が「キーが無い」ではなく「キーが違う」に見える。
CalilKeyChoice resolveCalilAppkey({
  String? deviceOverride,
  String bundled = defineCalilAppkey,
}) {
  final override = deviceOverride?.trim() ?? '';
  if (override.isNotEmpty) {
    return CalilKeyChoice(override, CalilKeySource.deviceOverride);
  }
  final embedded = bundled.trim();
  if (embedded.isNotEmpty) {
    return CalilKeyChoice(embedded, CalilKeySource.bundled);
  }
  return const CalilKeyChoice('', CalilKeySource.none);
}
