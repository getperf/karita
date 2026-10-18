/// 取得が成立しなかったときの区別。
///
/// **どれも「本が無い」「蔵書が無い」ではない。** 失敗と不在を1つの値に畳むと、画面が
/// 「蔵書なし」と言い切ってしまう — 利用者はそれを見て予約をやめる。区別はここで付け、
/// 表示の文言は UI が持つ（この層は文言を持たない）。
library;

/// 失敗の理由。**利用者向けの文言ではない。**
enum ApiFailure {
  /// 期限に達した。**部分結果が在るなら、それは捨てない。**
  timeout,

  /// つながらない。機内モード・圏外・DNS など。
  network,

  /// 2xx 以外が返った。相手は生きているが、この要求には応えていない。
  server,

  /// 呼びすぎ。カーリルは キー/IP あたりの上限を持つ。
  ///
  /// **時間を置けば直る。** `server` と混ぜると、再確認していい失敗かどうかが分からなくなる。
  rateLimited,

  /// キーを受け付けられなかった。未設定・失効・打ち間違い。
  unauthorized,

  /// 応答が大きすぎる。**読み切る前に切る** — 端末のメモリを相手に預けない。
  tooLarge,

  /// JSON として、あるいは約束した形として読めない。
  invalidData,
}

/// 取得の中で失敗が決まったときに投げるもの。**この層の外へは出さない。**
///
/// 公開している口はどれも結果の型に [ApiFailure] を載せて返す。例外で返さないのは、
/// 「失敗もまた普通の結果である」からで、呼ぶ側に try/catch を強いると握り潰されやすい。
class ApiFailureException implements Exception {
  final ApiFailure failure;

  /// 切り分けのための生の手掛かり。**利用者へは出さない。**
  final String? detail;

  const ApiFailureException(this.failure, [this.detail]);

  @override
  String toString() => 'ApiFailureException(${failure.name}${detail == null ? '' : ': $detail'})';
}
