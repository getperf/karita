/// Desktop クライアントの資格情報を読む。
///
/// JSON の実値は Git に入れない。手動配置を優先し、なければ Windows 配布物に同梱した
/// Desktop OAuth JSON を読む。Desktop クライアントの secret は配布先で秘匿できない。
///
/// **読むのは Windows の経路だけである。** Android は Play services が認可を持ち、この JSON を
/// 要らない（`AccessTokenProvider` が共通なのはそこまでである）。だから口を広げず、ここに閉じる。
///
/// 移送元: book-sync-model の `src/bsync_core/gauth.py`（`client_from_credentials_json`）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:karita_sync/karita_sync.dart';

import 'oauth.dart';

/// 認証と診断で共用する。存在する手動配置ファイルが壊れていても同梱版へ黙って切り替えない。
String resolveDesktopCredentialsPath(
  String localPath, {
  String? executablePath,
}) {
  if (File(localPath).existsSync()) return localPath;
  final executable = File(executablePath ?? Platform.resolvedExecutable);
  final bundled =
      '${executable.parent.path}${Platform.pathSeparator}data'
      '${Platform.pathSeparator}credentials'
      '${Platform.pathSeparator}karita-core-desktop.json';
  return File(bundled).existsSync() ? bundled : localPath;
}

/// Google Cloud Console が出す Desktop クライアントの JSON を読む。
///
/// 形は `{"installed": {...}}` である。`web` ではない — **Desktop クライアントは client secret を
/// 秘密として扱えない前提で、loopback + PKCE を使う。** 取り違えると、認可は
/// 通るのに redirect_uri の登録が合わずに落ちる。
DesktopClient loadDesktopClient(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw TransportAuthError(
      '資格情報がありません: $path。Desktop クライアントの JSON を置いてください。',
    );
  }

  final Object? raw;
  try {
    raw = jsonDecode(file.readAsStringSync());
  } on FormatException {
    throw TransportAuthError('資格情報を読めません: $path');
  }
  if (raw is! Map) throw TransportAuthError('資格情報の形が違います: $path');

  final installed = raw['installed'];
  if (installed is! Map) {
    throw TransportAuthError(
      '資格情報に installed がありません（Desktop クライアントの JSON ですか）: $path',
    );
  }

  String required(String key) {
    final value = installed[key];
    if (value is! String || value.isEmpty) {
      // **黙って空で進めない。** 空の client_id で認可 URL を組むと、ブラウザまで行ってから
      // Google の画面で落ちる。手元で止める。
      throw TransportAuthError('資格情報に $key がありません: $path');
    }
    return value;
  }

  String optional(String key, String fallback) {
    final value = installed[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  return DesktopClient(
    clientId: required('client_id'),
    clientSecret: required('client_secret'),
    authUri: optional('auth_uri', defaultAuthUri),
    tokenUri: optional('token_uri', defaultTokenUri),
  );
}
