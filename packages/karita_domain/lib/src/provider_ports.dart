/// 業務層が外部に要求する port。**adapter はここに入れない。**
///
/// 実 API を叩く実装は `karita-provider-gateway` のクライアントとして karita-core の外に置く。
/// 実 API の可用性を CI の条件にしないためである。検証用の実装は fixture reader 一つにする。
///
/// **適用範囲（2026-09-14）:** 上の「core の外」は gateway 経由の provider の話である。
/// OpenBD とカーリルは端末から直接つなぐと決めたので、その adapter は core 内の
/// `karita_public_api_client` に置く（2026-09-15に入った）。**業務層に adapter を入れないことは変わらない** —
/// 置き場が gateway client から専用パッケージに変わるだけで、ここは port のままである。
/// 実 API の可用性を CI の条件にしない縛りもそのまま効く。
/// → `非公開資料:external-data-access.md`
///
/// 移送元: book-sync-model の `src/bops_domain/provider_ports.py`。
library;

import 'candidates.dart';
import 'library_areas.dart';

abstract interface class BooksProvider {
  Future<List<BookCandidate>> searchKeyword(String keyword, {int limit = 10});

  Future<List<BookCandidate>> searchBooks({
    String? title,
    String? author,
    String? isbn,
    int limit = 10,
  });
}

/// 館情報を、設定登録に必要な粒度で提供する port。
abstract interface class LibraryCatalog {
  Future<List<String>> listCities(String pref);

  Future<List<LibrarySystem>> listSystems(String pref, String city);
}
