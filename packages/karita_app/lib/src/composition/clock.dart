/// 時刻。**業務の日付と記録の時刻で、暦を分ける。**
library;

String nowUtc() =>
    '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

/// 端末のローカル日付。**業務の日付欄は現地の暦で決まる。**
///
/// `nowUtc()` の日付部分ではない — 日本時間の朝9時までに操作すると、UTC ではまだ前日で
/// ある。予約日・貸出日・返却日・期限はどれも館の窓口の日付なので、ローカルで採る。
String localToday() => DateTime.now().toIso8601String().substring(0, 10);
