/// pass/fail の集計と、バイト差分・コード差分の表示。
///
/// 「両方とも例外を投げた」で通さない。期待と実際を必ず並べ、どこがどう食い違ったかを出す。
/// バイト列の差はエスケープして見せ、目視の「同じに見える」を排除する。
library;

class CaseResult {
  final String id;
  final bool passed;
  final String? detail;

  CaseResult(this.id, this.passed, [this.detail]);
}

class Report {
  final String title;
  final List<CaseResult> results = [];

  Report(this.title);

  void pass(String id) => results.add(CaseResult(id, true));

  void fail(String id, String detail) => results.add(CaseResult(id, false, detail));

  int get passed => results.where((r) => r.passed).length;

  int get failed => results.where((r) => !r.passed).length;

  bool get ok => failed == 0 && results.isNotEmpty;

  String render() {
    final buffer = StringBuffer();
    buffer.writeln('== $title ==');
    for (final r in results) {
      if (r.passed) {
        buffer.writeln('  ok   ${r.id}');
      } else {
        buffer.writeln('  FAIL ${r.id}');
        for (final line in (r.detail ?? '').split('\n')) {
          buffer.writeln('         $line');
        }
      }
    }
    buffer.writeln('  ${results.length} 件中 $passed 件一致、$failed 件不一致');
    return buffer.toString();
  }
}

/// バイト列を、差が目に見える形の文字列にする。ASCII 印字可能はそのまま、他は \xNN。
String showBytes(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    if (b >= 0x20 && b < 0x7F) {
      sb.writeCharCode(b);
    } else {
      sb.write('\\x${b.toRadixString(16).padLeft(2, '0')}');
    }
  }
  return sb.toString();
}

/// 2つのバイト列が最初に食い違う位置を返す。一致すれば -1。
int firstDiff(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return i;
  }
  if (a.length != b.length) return n;
  return -1;
}
