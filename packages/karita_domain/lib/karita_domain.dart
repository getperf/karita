/// 業務ドメイン。**移送は済んだ。**
///
/// 移送元は book-sync-model の `bops_domain` と `bops_application`。**一方通行の移送**であり、
/// Python 側で保守を続けない — ② ③ と業務ドメインには照合オラクルが無く、複製すればどちらが
/// 正しいかを決める根拠が消える。
///
/// **集約は4つに固定する** — `Book` / `Loan` / `LibrarySystem` / `LibraryMembership`。
/// `entityType` の追加は `schemaVersion` の二段階版上げを伴う重い操作として扱う。
///
/// **外部 API adapter を持たない。** [BooksProvider] 等のインタフェースだけを持ち、検証用の
/// 実装は [FixtureBooksProvider] 一つにする。実 API を叩く実装は `karita-provider-gateway` の
/// クライアントとして karita-core の外に置く。実 API の可用性を CI の条件にしないためである。
///
/// **`karita_sync` に依存しない。** 業務更新と outbox 追記は同一 SQLite トランザクションで
/// 行い、その入口は `karita_contract` の `appendLocalEmission` の一点だけである。
///
/// ## 同一性
///
/// 業務キーを持つ3つの集約は `entityId` を `uuid5(namespace, 業務キー)` で決定的に導く
/// （`karita_contract` の `deterministicId`）。
///
/// | 集約 | 種 | なぜ決定的か |
/// |---|---|---|
/// | `Book` | ISBN13 | 二端末が同じ本を独立に採用しても同じ id になり、二重登録が競合として立つ |
/// | `LibrarySystem` | `system_id` | 同じ図書館システムの独立登録が競合として立つ |
/// | `LibraryMembership` | `system_id` | 棚卸完了は端末ごとの事実ではなく、一つの事実である |
///
/// `Loan` だけは業務キーを持たない — 同じ本の同じ館での予約が本当に二件なのか、一件を二端末で
/// 記録しただけなのかは、館の予約番号を持たないアプリには判定できない。**畳むのは表示だけ**で
/// （[LoanReporting]）、データは両方そのまま残す。
///
/// ## 書込みの形
///
/// 書込みはすべて [DomainContext.emit] を通り、**集約更新・outbox 追記・`applied_events`
/// 追記・業務記録が同一トランザクションで確定する。** `written_by_app` に `bops` が押印され、
/// `ownershipViolations` がその押印を見る。
library;

export 'src/books.dart';
export 'src/candidates.dart';
export 'src/context.dart';
export 'src/errors.dart';
export 'src/fixture_provider.dart';
export 'src/library_areas.dart';
export 'src/library_settings.dart';
export 'src/mypage_url.dart';
export 'src/library_systems.dart';
export 'src/loan_reporting.dart';
export 'src/loans.dart';
export 'src/memberships.dart';
export 'src/provider_ports.dart';
export 'src/registration.dart';
export 'src/reservations.dart';

export 'src/bookshelf.dart';
