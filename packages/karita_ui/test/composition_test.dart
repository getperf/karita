/// 合成層への継ぎ目。**差し込み忘れと、失敗の受け取り方を測る。**
///
/// `appIssueOf` は 2026-09-17 に入った。**Riverpod 3 が Provider の失敗を包む**ことを実測で
/// 確かめてから足したもので、包み方が変わればここが落ちる。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karita_app/karita_app.dart';
import 'package:karita_ui/karita_ui.dart';

final _throwing = Provider<int>(
  (ref) => throw const AppIssue('sample-code', 'Sample message.'),
);
final _dependent = Provider<int>((ref) => ref.watch(_throwing) + 1);
final _other = Provider<int>((ref) => throw StateError('not an AppIssue'));

void main() {
  test('差し込まれていなければ落ちる。黙って空の合成を返さない', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Object? error;
    try {
      container.read(compositionProvider);
    } catch (thrown) {
      error = thrown;
    }
    expect(error, isNotNull, reason: '空の合成を返さない');
    // **Riverpod が包むので型では受けられない。** 掘れば差し込み忘れだと分かる。
    expect(appIssueOf(error!).message, contains('UnimplementedError'));
  });

  group('失敗の受け取り', () {
    late ProviderContainer container;
    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    Object caught(Provider<int> provider) {
      try {
        container.read(provider);
      } catch (error) {
        return error;
      }
      fail('投げられなかった');
    }

    test('Riverpod は直接読んでも包む。型では受けられない', () {
      final error = caught(_throwing);
      // **`on AppIssue` は一度も当たらない。** これがこの関数が在る理由である。
      expect(error, isNot(isA<AppIssue>()));
      expect(error.runtimeType.toString(), 'ProviderException');
    });

    test('依存を1段またぐたびに1枚重なる。掘って取り出す', () {
      final issue = appIssueOf(caught(_dependent));
      expect(issue.code, 'sample-code');
      expect(issue.message, 'Sample message.');
    });

    test('包まれていない AppIssue はそのまま返る', () {
      const issue = AppIssue('direct', 'Direct.');
      expect(identical(appIssueOf(issue), issue), isTrue);
    });

    test('AppIssue でないものは型名だけの1件にする。生の例外を配らない', () {
      final issue = appIssueOf(caught(_other));
      expect(issue.code, 'unexpected');
      // **包みの型ではなく、一番奥の型名を出す。**
      expect(issue.message, contains('StateError'));
      expect(
        issue.message,
        isNot(contains('not an AppIssue')),
        reason: '本文を配らない',
      );
    });

    test('`exception` を持たないものでも落ちない', () {
      final issue = appIssueOf(StateError('bare'));
      expect(issue.code, 'unexpected');
      expect(issue.message, contains('StateError'));
    });
  });
}
