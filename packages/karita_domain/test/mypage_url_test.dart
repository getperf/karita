import 'package:karita_domain/karita_domain.dart';
import 'package:test/test.dart';

const String _imported = 'https://example.invalid/imported';
const String _bundled = 'https://example.invalid/bundled';
const String _official = 'https://example.invalid/official';

void main() {
  test('取り込み値が最優先', () {
    final resolved = resolveMypageUrl(
      imported: _imported,
      importedCheckedOn: '2026-09-15',
      bundled: _bundled,
      bundledCheckedOn: '2026-08-15',
      homepageUrl: _official,
    );
    expect(resolved.source, MypageUrlSource.imported);
    expect(resolved.value, _imported);
    // **確認日の意味は出典で変わる。** 取り込み値なら利用者が取り込んだ日である。
    expect(resolved.checkedOn, '2026-09-15');
  });

  test('保存値が無ければ既定値を引く', () {
    final resolved = resolveMypageUrl(
      bundled: _bundled,
      bundledCheckedOn: '2026-08-15',
      homepageUrl: _official,
    );
    expect(resolved.source, MypageUrlSource.bundled);
    expect(resolved.checkedOn, '2026-08-15');
  });

  test('既定値が無ければ公式サイトへ落ちる。確認日は無い', () {
    final resolved = resolveMypageUrl(homepageUrl: _official);
    expect(resolved.source, MypageUrlSource.official);
    expect(resolved.value, _official);
    expect(resolved.checkedOn, isNull);
  });

  test('どれも無ければ未設定', () {
    final resolved = resolveMypageUrl();
    expect(resolved.source, MypageUrlSource.unset);
    expect(resolved.isSet, isFalse);
  });

  test('空文字は「無い」と同じに扱う', () {
    // **保存値の削除が `既定値に戻す` である。** 空文字が残って既定値を隠すと、戻す操作が
    // 効かなくなる。
    final resolved = resolveMypageUrl(imported: '', bundled: _bundled);
    expect(resolved.source, MypageUrlSource.bundled);
  });
}
