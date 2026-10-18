/// OpenBD から ISBN 1件ぶんの書誌と書影 URL を取る。
///
/// **検索は持たない。** 書名・著者での横断検索を足さないのは、OpenBD が本の紹介のための
/// 書誌データベースであり、こちらの用途が「利用者が手にした1冊を確かめる」ことだからである。
/// 探す操作はブラウザー側（カーリル・各館のサイト）にあり、戻ってくるのは ISBN である。
///
/// **採用するかどうかは決めない。** ここが返すのは候補であって、台帳に載る書誌ではない。
/// 利用者が採ると決めたものだけが業務の入口へ行く。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'defaults.dart';
import 'failures.dart';
import 'fetch.dart';

/// ISBN 照会の結末。
enum OpenBdOutcome {
  /// 書誌が返った。
  found,

  /// **相手は答えたが、その ISBN を収録していない。** 失敗ではない。
  ///
  /// 通信の失敗と分けるのは、再確認の間隔が違うからである。未収録はしばらく変わらないが、
  /// 通信の失敗は次の瞬間に直りうる。
  notListed,

  /// 取れなかった。[OpenBdResult.failure] に理由が入る。
  failed,
}

/// 書誌1件。**提供された表記のままで、解釈しない。**
class BookRecord {
  final String isbn13;

  /// 書名。**空でありうる** — 取れなかった項目が在っても照会そのものは成立する。
  final String title;

  /// 著者の表示文字列。`山田太郎／著` のような1本の文字列で来る。
  ///
  /// **記号で切って人物を数えない。** 区切りは出版社ごとに揺れ、役割（著・編・訳・監修）も
  /// 混ざる。推測して分けると、台帳に居ない人が現れる。分け方を決めるのは合成層の仕事で、
  /// それはまだ決まっていない。
  final String? authorLine;

  final String? publisher;

  /// 出版日。`20240115` や `2024` のような、桁数の揃わない文字列で来る。**日付に変えない。**
  final String? pubdate;

  /// 書影の URL。**HTTPS だけを通す。**
  final Uri? coverUrl;

  const BookRecord({
    required this.isbn13,
    required this.title,
    this.authorLine,
    this.publisher,
    this.pubdate,
    this.coverUrl,
  });
}

class OpenBdResult {
  final OpenBdOutcome outcome;
  final BookRecord? record;
  final ApiFailure? failure;

  const OpenBdResult._(this.outcome, {this.record, this.failure});

  const OpenBdResult.found(BookRecord record)
      : this._(OpenBdOutcome.found, record: record);

  const OpenBdResult.notListed() : this._(OpenBdOutcome.notListed);

  const OpenBdResult.failed(ApiFailure failure)
      : this._(OpenBdOutcome.failed, failure: failure);
}

/// 書影画像の取得の結末。
enum CoverImageOutcome {
  /// バイトが取れた。**画像として読めるかどうかは見ていない** — 復号は Flutter の側にある。
  fetched,

  /// 404。**URL は在るのに画像が無い。** 書誌の失敗ではない。
  notFound,

  failed,
}

class CoverImageResult {
  final CoverImageOutcome outcome;
  final List<int>? bytes;
  final ApiFailure? failure;

  const CoverImageResult._(this.outcome, {this.bytes, this.failure});

  const CoverImageResult.fetched(List<int> bytes)
      : this._(CoverImageOutcome.fetched, bytes: bytes);

  const CoverImageResult.notFound() : this._(CoverImageOutcome.notFound);

  const CoverImageResult.failed(ApiFailure failure)
      : this._(CoverImageOutcome.failed, failure: failure);
}

class OpenBdClient {
  final http.Client _httpClient;
  final Uri apiBase;

  /// 書誌1件を待つ長さ。
  final Duration recordTimeout;

  /// 書影1枚を待つ長さ。**書誌より長い**（理由は [defaultImageTimeout]）。
  final Duration imageTimeout;

  /// 書誌の応答に許す大きさ。
  final int maxRecordBytes;

  /// 書影1枚に許す大きさ。**超えたら読むのをやめる。**
  final int maxImageBytes;

  OpenBdClient({
    http.Client? httpClient,
    Uri? apiBase,
    this.recordTimeout = defaultRecordTimeout,
    this.imageTimeout = defaultImageTimeout,
    this.maxRecordBytes = defaultMaxRecordBytes,
    this.maxImageBytes = defaultMaxImageBytes,
  })  : _httpClient = httpClient ?? http.Client(),
        apiBase = apiBase ?? openBdApiBase;

  void close() => _httpClient.close();

  /// ISBN-13 で書誌を引く。
  Future<OpenBdResult> fetchBook(String isbn13) async {
    requireIsbn13(isbn13);
    final uri = apiBase.replace(
      path: '${apiBase.path}/get',
      queryParameters: {'isbn': isbn13},
    );
    try {
      final response = await fetchBytes(_httpClient, uri,
          maxBytes: maxRecordBytes,
          timeout: recordTimeout,
          provider: 'openbd',
          operation: 'book');
      throwForStatus(response.statusCode);
      return _readRecord(isbn13, response.bodyBytes);
    } on ApiFailureException catch (error) {
      return OpenBdResult.failed(error.failure);
    }
  }

  /// 書影を取る。
  ///
  /// **URL は [BookRecord.coverUrl] が返したものだけを渡す。** 応答から来た URL の検めは
  /// 読むときに済ませてあり（[_coverUrl]）、そこを通っていない URL をここへ持ち込むと、
  /// 検めの無い経路ができる。
  ///
  /// `userInfo` 付きだけはここでも拒む。**資格情報を載せた要求を、こちらの都合で送り出さない。**
  Future<CoverImageResult> fetchCoverImage(Uri coverUrl) async {
    if (coverUrl.userInfo.isNotEmpty) {
      throw ArgumentError.value(
          coverUrl.toString(), 'coverUrl', '資格情報つきの URL は叩かない');
    }
    try {
      final response = await fetchBytes(_httpClient, coverUrl,
          maxBytes: maxImageBytes,
          timeout: imageTimeout,
          provider: 'openbd',
          operation: 'cover');
      if (response.statusCode == 404) return const CoverImageResult.notFound();
      throwForStatus(response.statusCode);
      return CoverImageResult.fetched(response.bodyBytes);
    } on ApiFailureException catch (error) {
      return CoverImageResult.failed(error.failure);
    }
  }

  /// 応答は**必ず1件の配列**で、中身が `null` なら未収録である。
  OpenBdResult _readRecord(String isbn13, List<int> bodyBytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes));
    } catch (error) {
      throw ApiFailureException(ApiFailure.invalidData, '$error');
    }
    if (decoded is! List || decoded.length != 1) {
      throw const ApiFailureException(ApiFailure.invalidData, '1件の配列ではない');
    }
    final first = decoded.first;
    if (first == null) return const OpenBdResult.notListed();
    if (first is! Map) {
      throw const ApiFailureException(ApiFailure.invalidData, 'レコードが object ではない');
    }
    final summary = first['summary'];
    if (summary is! Map) {
      throw const ApiFailureException(ApiFailure.invalidData, 'summary が無い');
    }
    return OpenBdResult.found(BookRecord(
      isbn13: isbn13,
      title: _text(summary['title']) ?? '',
      authorLine: _text(summary['author']),
      publisher: _text(summary['publisher']),
      pubdate: _text(summary['pubdate']),
      coverUrl: _coverUrl(summary['cover']),
    ));
  }

  /// 空文字は「無い」と同じに扱う。**OpenBD は欠損を空文字で返す。**
  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 書影 URL を検める。**通らなければ「書影なし」にする。**
  ///
  /// 応答の中の URL をそのまま取りに行くと、相手の書き間違い1つで端末が別のホストを叩く。
  /// `http` を弾くのは、そこから来た画像を本の表紙として見せたくないからである。`userInfo`
  /// 付きの URL も弾く — 資格情報を載せた要求を、こちらの都合で送り出すことになる。
  ///
  /// **URL が読めないことは、書誌の失敗ではない。** 書名と著者は取れている。
  static Uri? _coverUrl(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }
}
