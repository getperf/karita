/// 実 Drive の手動確認に要る最小の道具。
///
/// **手動が残るのは初回の同意だけである。** それ以外は `dart test -P drive` で回る。ここが
/// あるのは、ブラウザでの同意という一点を通すためだけで、**製品の入口ではない。**
///
/// 既定のデータ領域をそのまま使う（`KARITA_HOME` があればそちら）。**差し替えを常用しない** —
/// 既定を解決する経路が本番の経路であり、ここで別の場所を使うと、その解決が一度も通らないまま
/// 実 Drive の確認だけが緑になる。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:karita_contract/errors.dart';
import 'package:karita_platform/karita_platform.dart';

Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'status' : args.first;
  final noBrowser = args.contains('--no-browser');

  final AppPaths paths;
  try {
    paths = WindowsAppPaths.resolve();
  } on SyncDataError catch (exc) {
    stderr.writeln(exc.message);
    exit(2);
  }

  switch (command) {
    case 'login':
      await _login(paths, noBrowser: noBrowser);
    case 'status':
      _status(paths);
    case 'logout':
      final removed = TokenStore(paths.tokenPath).clear();
      stdout.writeln(removed ? 'トークンを消しました。' : 'トークンはありません。');
    case 'whoami':
      await _whoami(paths);
    case 'purge':
      await _purge(paths, args);
    case 'damage':
      _damage(paths, refresh: args.contains('--refresh'));
    case 'restore':
      _restore(paths);
    case 'where':
      // どこを見ているかを出す。**値は出さない。**
      stdout.writeln('home:        ${paths.home}');
      stdout.writeln('token:       ${paths.tokenPath}');
      stdout.writeln('credentials: ${paths.credentialsPath}');
    default:
      stderr.writeln(
        '未知のサブコマンド: $command'
        '（login|status|logout|whoami|purge|damage|restore|where）',
      );
      exit(2);
  }
}

Future<void> _login(AppPaths paths, {required bool noBrowser}) async {
  paths.ensure();
  final GoogleOAuth oauth;
  try {
    oauth = GoogleOAuth(loadDesktopClient(paths.credentialsPath));
  } on SyncDataError catch (exc) {
    stderr.writeln(exc.message);
    exit(2);
  }

  final login = LoopbackLogin(
    oauth: oauth,
    store: TokenStore(paths.tokenPath),
    now: _nowUtc,
    randomToken: _randomToken,
    openBrowser: (url) async {
      // **URL は必ず出す。** 開けても開けなくても、利用者が自分で開ける形を残す。同意が
      // 進まないときに、何が起きなかったのかを見られるようにするためである。
      stdout.writeln('ブラウザで同意してください:');
      stdout.writeln(url);
      if (noBrowser) return;
      try {
        // 引数を1つとして渡せる経路を使う。`start` はクエリの `&` で切れる。
        await Process.start('rundll32.exe', [
          'url.dll,FileProtocolHandler',
          '$url',
        ]);
      } on ProcessException {
        stdout.writeln('（ブラウザを開けませんでした。上の URL を開いてください）');
      }
    },
  );

  try {
    final token = await login.login();
    // **値は出さない。** 有無と期限だけである。
    stdout.writeln('認可しました。expiry=${token.expiryUtc ?? '(不明)'}');
    stdout.writeln('scopes=${token.scopes.join(' ')}');
    stdout.writeln('refresh token=${token.refreshToken == null ? 'なし' : 'あり'}');
  } on SyncDataError catch (exc) {
    stderr.writeln(exc.message);
    exit(1);
  } finally {
    oauth.close();
  }
}

void _status(AppPaths paths) {
  final store = TokenStore(paths.tokenPath);
  final credentials = File(paths.credentialsPath).existsSync();
  stdout.writeln('credentials: ${credentials ? 'あり' : 'なし'}');

  final load = store.read();
  final token = load.token;
  if (token == null) {
    stdout.writeln(switch (load.state) {
      TokenLoadState.unreadable =>
        'token:       開けない（${load.detail}）。`drive_probe login` で認可し直してください',
      TokenLoadState.ioFailed => 'token:       読めない（${load.detail}）',
      _ => 'token:       なし（`drive_probe login` で認可してください）',
    });
    return;
  }
  // **access token も refresh token も出さない。** 診断に要るのは有無と期限だけである。
  stdout.writeln('token:       あり（${load.state.name}）');
  stdout.writeln('expiry:      ${token.expiryUtc ?? '(不明)'}');
  stdout.writeln('expired:     ${token.expired(_nowUtc())}');
  stdout.writeln('refresh:     ${token.refreshToken == null ? 'なし' : 'あり'}');
  stdout.writeln('scopes:      ${token.scopes.join(' ')}');
}

/// 認可喪失の枝を作る。**実物を退避してから、保存されている方を壊す。**
///
/// token は保護されていて手では書き換えられない（2026-10-18）。`access_token` だけを壊し
/// `expiry_utc` を未来のままにすると、refresh を挟まずに Drive が 401 を返す。`--refresh` は
/// refresh token も壊し、認可層の枝に入る。戻すのは `restore` である。
void _damage(AppPaths paths, {required bool refresh}) {
  final store = TokenStore(paths.tokenPath);
  final backup = TokenStore('${paths.tokenPath}.orig');
  final token = store.load();
  if (token == null) {
    stderr.writeln('token がありません。');
    exit(1);
  }
  if (backup.load() != null) {
    stderr.writeln('退避済みの token があります。先に `drive_probe restore` で戻してください。');
    exit(1);
  }
  backup.save(token);
  store.save(
    Token(
      accessToken: 'damaged-access-token',
      refreshToken: refresh ? 'damaged-refresh-token' : token.refreshToken,
      expiryUtc: '2099-01-01T00:00:00Z',
      scopes: token.scopes,
    ),
  );
  stdout.writeln(refresh ? 'access と refresh を壊しました。' : 'access だけを壊しました。');
}

void _restore(AppPaths paths) {
  final backup = File('${paths.tokenPath}.orig');
  if (!backup.existsSync()) {
    stderr.writeln('退避した token がありません。');
    exit(1);
  }
  backup.renameSync(paths.tokenPath);
  stdout.writeln('退避した token に戻しました。');
}

/// 接続先のアカウント。**掃除の前に、どのアカウントの `appDataFolder` かを見るためにある。**
Future<void> _whoami(AppPaths paths) async {
  final client = _client(paths);
  try {
    final info = await client.about();
    stdout.writeln('account: ${info.emailAddress ?? '(不明)'}');
  } on SyncDataError catch (exc) {
    stderr.writeln(exc.message);
    exit(1);
  } finally {
    client.close();
  }
}

/// 検証用アカウントの `appDataFolder` を空にする。**「karita をはじめる」を再現するためだけにある。**
///
/// `appDataFolder` はアカウントに1つで、`KARITA_HOME` はローカルしか分けない。本番の
/// アカウントで走ると、全端末の世代の起点とイベントが消える
/// （`非公開資料:p5b-verification-mode.md`「注意」）。だから二重に止める。
///
/// - `KARITA_HOME` が明示されていること。既定の領域のトークンでは走らない
/// - `--account` で名指したアカウントと、`about.get` の接続先が一致すること
///
/// `--yes` が無ければ数えるだけで消さない。
Future<void> _purge(AppPaths paths, List<String> args) async {
  final explicitHome = Platform.environment[homeEnvVar];
  if (explicitHome == null || explicitHome.trim().isEmpty) {
    stderr.writeln('$homeEnvVar を明示した使い捨ての領域でだけ実行できます。');
    exit(2);
  }
  final at = args.indexOf('--account');
  final expected = at >= 0 && at + 1 < args.length ? args[at + 1].trim() : '';
  if (expected.isEmpty) {
    stderr.writeln('--account <検証用アカウント> を指定してください。');
    exit(2);
  }
  final apply = args.contains('--yes');

  final client = _client(paths);
  try {
    final actual = (await client.about()).emailAddress ?? '';
    if (actual.toLowerCase() != expected.toLowerCase()) {
      stderr.writeln(
        '接続先が $expected ではありません（${actual.isEmpty ? '不明' : actual}）。'
        '何も消していません。',
      );
      exit(3);
    }

    final files = <FileRef>[];
    String? pageToken;
    do {
      final page = await client.listPage(pageToken: pageToken);
      files.addAll(page.files);
      pageToken = page.nextPageToken;
    } while (pageToken != null);

    // 種類ごとの数だけ出す。名前の先頭（`baseline` / `backup` / 世代の接頭辞）で分ける。
    final kinds = <String, int>{};
    for (final file in files) {
      final kind = file.name.split('-').first;
      kinds[kind] = (kinds[kind] ?? 0) + 1;
    }
    stdout.writeln('account: $actual');
    stdout.writeln('files:   ${files.length}');
    for (final entry in kinds.entries) {
      stdout.writeln('  ${entry.key}: ${entry.value}');
    }
    if (!apply) {
      stdout.writeln('数えただけです。消すには --yes を付けます。');
      return;
    }
    for (final file in files) {
      await client.delete(file.fileId);
    }
    stdout.writeln('消しました: ${files.length}');
  } on SyncDataError catch (exc) {
    stderr.writeln(exc.message);
    exit(1);
  } finally {
    client.close();
  }
}

/// 保存済みトークンで Drive を読む口。**認可は始めない** — 無ければ `login` を案内して落ちる。
RestDriveClient _client(AppPaths paths) {
  final GoogleOAuth oauth;
  try {
    oauth = GoogleOAuth(
      loadDesktopClient(resolveDesktopCredentialsPath(paths.credentialsPath)),
    );
  } on SyncDataError catch (exc) {
    stderr.writeln(exc.message);
    exit(2);
  }
  return RestDriveClient(
    tokens: GoogleAccessTokenProvider(
      store: TokenStore(paths.tokenPath),
      oauth: oauth,
      now: _nowUtc,
    ),
  );
}

/// RFC3339 秒精度・Z 終端。封筒の `createdAtUtc` と同じ規約である。
String _nowUtc() =>
    '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

/// PKCE の verifier と state に使う乱数。
///
/// **推測できてはならない。** state を当てられると、他所で始めた認可の結果を受け取らせる経路が
/// できる。48 バイトを base64url にすると 64 文字で、Google が許す 43〜128 の範囲に収まる。
final Random _secure = Random.secure();

String _randomToken() => base64Url
    .encode(List<int>.generate(48, (_) => _secure.nextInt(256)))
    .replaceAll('=', '');
