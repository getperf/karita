/// token の保存保護と、旧版の平文からの移行。**実 token を使わない。**
///
/// Windows では本物の DPAPI を通す。失敗の注入には可逆な偽の保護を使う
/// （`非公開資料:2026-10-18-windows-token-protection-probe.md` の自己テストを移したもの）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:karita_platform/karita_platform.dart';
import 'package:test/test.dart';

const _token = Token(
  accessToken: 'secret-access-marker',
  refreshToken: 'secret-refresh-marker',
  expiryUtc: '2099-01-01T00:00:00Z',
);

const _magic = [0x4B, 0x52, 0x54, 0x4B];

void main() {
  late Directory work;
  late String path;

  setUp(() {
    work = Directory.systemTemp.createTempSync('karita-token-');
    path = '${work.path}${Platform.pathSeparator}token.json';
  });
  tearDown(() => work.deleteSync(recursive: true));

  Uint8List bytes() => File(path).readAsBytesSync();
  bool hasSecret(String p) =>
      File(p).existsSync() &&
      latin1.decode(File(p).readAsBytesSync()).contains('secret-');
  List<String> names() =>
      [for (final e in work.listSync()) e.uri.pathSegments.last]..sort();
  final legacy = utf8.encode(jsonEncode(_token.toJson()));

  group('DPAPI', () {
    late TokenStore store;
    setUp(() => store = TokenStore(path));

    test('保護して往復する。ファイルに平文が無い', () {
      store.save(_token);
      expect(String.fromCharCodes(bytes().sublist(0, 4)), 'KRTK');
      expect(bytes()[4], 1);
      expect(hasSecret(path), isFalse);
      final load = store.read();
      expect(load.state, TokenLoadState.protected);
      expect(load.token!.refreshToken, 'secret-refresh-marker');
    });

    test('別の store（再起動相当）でも開ける', () {
      store.save(_token);
      expect(TokenStore(path).load()!.accessToken, 'secret-access-marker');
    });

    test('1バイトの改変・末尾欠けは開けない。落とさず、ファイルも消さない', () {
      store.save(_token);
      final good = bytes();
      File(
        path,
      ).writeAsBytesSync(Uint8List.fromList(good)..[good.length ~/ 2] ^= 0xFF);
      expect(store.read().state, TokenLoadState.unreadable);
      File(path).writeAsBytesSync(good.sublist(0, good.length - 16));
      expect(store.read().state, TokenLoadState.unreadable);
      expect(File(path).existsSync(), isTrue);
    });

    test('旧版の平文を読み、保護形式へ置き換える', () {
      File(path).writeAsBytesSync(legacy);
      final load = store.read();
      expect(load.state, TokenLoadState.migrated);
      expect(load.token!.accessToken, 'secret-access-marker');
      expect(hasSecret(path), isFalse);
      expect(store.read().state, TokenLoadState.protected);
      expect(names(), ['token.json']);
    });
  }, testOn: 'windows');

  group('形式と失敗', () {
    late _XorProtector protector;
    late TokenStore store;
    setUp(() {
      protector = _XorProtector();
      store = TokenStore(path, protector: protector);
    });

    for (final (name, raw) in [
      ('識別子だけ', _magic),
      ('知らない版', [..._magic, 9, 1, 2, 3]),
      ('ごみ', [0, 1, 2, 3, 4, 5]),
      ('空', <int>[]),
      ('壊れた平文', utf8.encode('{ broken')),
      ('型の違う平文', utf8.encode('{"access_token":"a","refresh_token":1}')),
    ]) {
      test('$name は開けない（平文として誤読しない）', () {
        File(path).writeAsBytesSync(raw);
        final load = store.read();
        expect(load.state, TokenLoadState.unreadable);
        expect(load.token, isNull);
      });
    }

    test('保護の中身が token でなければ開けない', () {
      File(path).writeAsBytesSync([
        ..._magic,
        1,
        ...protector.protect(Uint8List.fromList(utf8.encode('{"x":1}'))),
      ]);
      expect(store.read().state, TokenLoadState.unreadable);
    });

    test('開けない理由を出す。値は出さない', () {
      store.save(_token);
      protector.failUnprotect = true;
      final load = store.read();
      expect(load.state, TokenLoadState.unreadable);
      expect(load.detail, 'win32=13');
    });

    test('新規保存で保護に失敗したら何も作らない', () {
      protector.failProtect = true;
      expect(
        () => store.save(_token),
        throwsA(isA<TokenProtectionException>()),
      );
      expect(names(), isEmpty);
    });

    test('移行の保護に失敗しても、認可は使え、平文は元のまま残る', () {
      File(path).writeAsBytesSync(legacy);
      protector.failProtect = true;
      final load = store.read();
      expect(load.state, TokenLoadState.legacyPlaintext);
      expect(load.token!.accessToken, 'secret-access-marker');
      expect(bytes(), legacy);
      expect(names(), ['token.json']);

      // 次の読込でやり直す。
      protector.failProtect = false;
      expect(store.read().state, TokenLoadState.migrated);
      expect(hasSecret(path), isFalse);
    });

    test('一時ファイルの確認に失敗したら、元を壊さず一時ファイルも残さない', () {
      File(path).writeAsBytesSync(legacy);
      protector.failUnprotect = true;
      expect(store.read().state, TokenLoadState.legacyPlaintext);
      expect(bytes(), legacy);
      expect(names(), ['token.json']);
    });

    test('旧版の固定名 .part（平文を含みうる）は保存で消える', () {
      File('$path.part').writeAsBytesSync(legacy);
      store.save(_token);
      expect(names(), ['token.json']);
    });

    test('他のプロセスの新しい一時ファイルは消さず、古いものは消す', () {
      final fresh = File('$path.99999.part')..writeAsBytesSync([1]);
      final stale = File('$path.99998.part')
        ..writeAsBytesSync([1])
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 1)),
        );
      store.save(_token);
      expect(fresh.existsSync(), isTrue);
      expect(stale.existsSync(), isFalse);
    });

    test('clear は token と旧版の .part を消す', () {
      store.save(_token);
      File('$path.part').writeAsBytesSync(legacy);
      expect(store.clear(), isTrue);
      expect(names(), isEmpty);
      expect(store.clear(), isFalse);
    });

    test('無いものは missing である', () {
      expect(store.read().state, TokenLoadState.missing);
    });
  });
}

/// 可逆な置換。**DPAPI の代わりに失敗を注入するためにある。**
class _XorProtector implements TokenProtector {
  bool failProtect = false;
  bool failUnprotect = false;

  @override
  Uint8List protect(Uint8List plain) {
    if (failProtect) throw const TokenProtectionException('protect');
    return Uint8List.fromList([for (final b in plain) b ^ 0x5A]);
  }

  @override
  Uint8List unprotect(Uint8List sealed) {
    if (failUnprotect) throw const TokenProtectionException('unprotect', 13);
    return Uint8List.fromList([for (final b in sealed) b ^ 0x5A]);
  }
}
