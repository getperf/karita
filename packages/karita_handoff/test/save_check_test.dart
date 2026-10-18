import 'package:karita_handoff/karita_handoff.dart';
import 'package:test/test.dart';

final Uri _koto = Uri.parse(
  'https://www.koto-lib.tokyo.jp/opw/OPW/OPWLOGINTIME.CSP?DB=LIB',
);

void main() {
  test('実採取の既定値はそのまま保存できる', () {
    // **クエリがあること自体では拒否しない。** ?DB=LIB と ?smtFlg=0 はセッションではない。
    for (final url in [
      _koto,
      Uri.parse(
        'https://www.lib.city.minato.tokyo.jp/licsxp-opac/WOpacInitLoginActiontemp.do?smtFlg=0',
      ),
      Uri.parse('https://www.lib.city.katsushika.lg.jp/idcheck'),
    ]) {
      final check = checkSaveableUrl(url, compareTo: url);
      expect(check.saveable, isTrue, reason: '$url');
      expect(check.issues, isEmpty, reason: '$url');
    }
  });

  test('http(s) 以外と userinfo は拒否する', () {
    expect(
      checkSaveableUrl(
        Uri.parse('ftp://example.jp/login'),
        compareTo: _koto,
      ).issues,
      contains(UrlSaveIssue.notWeb),
    );
    expect(
      checkSaveableUrl(
        Uri.parse('https://user:pw@www.koto-lib.tokyo.jp/'),
        compareTo: _koto,
      ).issues,
      contains(UrlSaveIssue.hasUserInfo),
    );
    expect(
      checkSaveableUrl(
        Uri.parse('ftp://example.jp/login'),
        compareTo: _koto,
      ).saveable,
      isFalse,
    );
  });

  test('セッション ID の鍵はクエリでも path でも拒否する', () {
    final rejected = [
      // Wicket・TOSHOW は path に付ける。**クエリだけを見ると素通りする。**
      'https://www.library.sumida.tokyo.jp/idcheck;jsessionid=A1B2C3',
      'https://www.library.sumida.tokyo.jp/idcheck;JSESSIONID=A1B2C3',
      'https://example.jp/login?PHPSESSID=abc',
      'https://example.jp/login?sessionid=abc',
      'https://example.jp/mypage?token=abc',
      'https://example.jp/mypage?uid=123',
    ];
    for (final raw in rejected) {
      final check = checkSaveableUrl(Uri.parse(raw), compareTo: Uri.parse(raw));
      expect(check.issues, contains(UrlSaveIssue.sessionKey), reason: raw);
      expect(check.saveable, isFalse, reason: raw);
    }
  });

  test('鍵の名前で判定する。部分一致では拒否しない', () {
    final check = checkSaveableUrl(
      Uri.parse('https://www.koto-lib.tokyo.jp/opw?utm_uid=1&tokenizer=2'),
      compareTo: _koto,
    );
    expect(check.issues, isEmpty);
    expect(check.saveable, isTrue);
  });

  test('公式サイトとOPACが別ホストでも警告しない', () {
    final check = checkSaveableUrl(
      Uri.parse('https://opac.example.jp/login'),
      compareTo: _koto,
    );
    expect(check.issues, isEmpty);
    // 外部 OPAC への正常な遷移でも起こる。**一律拒否しない。**
    expect(check.saveable, isTrue);
  });

  test('比較先が無くても警告しない', () {
    final check = checkSaveableUrl(_koto);
    expect(check.issues, isEmpty);
    expect(check.saveable, isTrue);
  });

  test('足立区の公式サイトから図書館OPACへの遷移を警告しない', () {
    final check = checkSaveableUrl(
      Uri.parse(
        'https://www.lib.adachi.tokyo.jp/licsxp-opac/WOpacInitLoginActiontemp.do?smtFlg=0',
      ),
      compareTo: Uri.parse(
        'https://www.city.adachi.tokyo.jp/toshokan/shisetsu/toshokan/016.html',
      ),
    );
    expect(check.issues, isEmpty);
    expect(check.saveable, isTrue);
  });
}
