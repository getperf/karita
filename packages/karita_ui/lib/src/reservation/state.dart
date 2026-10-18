library;

import 'dart:async';
import 'package:karita_app/karita_app.dart';
import 'package:karita_domain/karita_domain.dart';
import 'package:karita_handoff/karita_handoff.dart';
import 'package:karita_public_api_client/karita_public_api_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../composition.dart';
import '../libraries/state.dart';
import '../shell/navigation.dart';

part 'state.g.dart';

@riverpod
Future<OpenBdResult> reservationLookup(Ref ref, String isbn) =>
    ref.watch(compositionProvider).bookInfo.book(isbn);

@riverpod
Future<CoverImageResult> reservationCover(Ref ref, String url) =>
    ref.watch(compositionProvider).bookInfo.cover(Uri.parse(url));

/// 貼り付けた書名を1行にする。**改行・連続する空白（全角を含む）を1つの空白に詰める。**
/// 図書館サイトから写すと、書名の途中の改行や前後の空白が付いてくる。「書名 / 著者」のような
/// 区切りは分けない — 館ごとに形が違い、誤って割ると書名を壊す。
String normalizeTitle(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

class ReservationDraft {
  final String operationId;
  final String bookId;
  final String? isbn;
  final String title;
  final String author;
  final String provider;
  final bool manual;
  final bool savedBook;
  final bool edited;
  final bool invalidIsbn;

  /// 届いた本の書名を利用者が入れる欄を出すか。**書誌が取れなかったとき**（未収録・失敗）と、
  /// **保存済み Book の書名が空のとき**に立ち、以後は下ろさない（入力中に欄が消えないように）。
  final bool titleEditable;
  final String? sourceUrl;
  final Uri? coverUrl;
  final Set<String> systems;
  final bool loading;
  final String? lookupNotice;
  const ReservationDraft({
    required this.operationId,
    required this.bookId,
    this.isbn,
    this.title = '',
    this.author = '',
    this.provider = 'manual',
    this.manual = false,
    this.savedBook = false,
    this.edited = false,
    this.invalidIsbn = false,
    this.titleEditable = false,
    this.sourceUrl,
    this.coverUrl,
    this.systems = const {},
    this.loading = false,
    this.lookupNotice,
  });

  ReservationDraft copy({
    String? title,
    String? author,
    Set<String>? systems,
    bool? edited,
    bool? loading,
    bool? titleEditable,
    String? provider,
    OpenBdResult? result,
  }) => ReservationDraft(
    operationId: operationId,
    bookId: bookId,
    isbn: isbn,
    title: title ?? this.title,
    author: author ?? this.author,
    provider: result?.record != null && !savedBook && !this.edited
        ? 'openbd'
        : provider ?? this.provider,
    manual: manual,
    savedBook: savedBook,
    edited: edited ?? this.edited,
    invalidIsbn: invalidIsbn,
    titleEditable:
        titleEditable ??
        (this.titleEditable || (result != null && result.record == null)),
    sourceUrl: sourceUrl,
    coverUrl: result == null ? coverUrl : result.record?.coverUrl,
    systems: systems ?? this.systems,
    loading: loading ?? this.loading,
    lookupNotice: result == null
        ? lookupNotice
        : switch (result.outcome) {
            OpenBdOutcome.found => null,
            OpenBdOutcome.notListed => 'openBDに書誌がありません。図書館サイトなどから書名を写してください。',
            OpenBdOutcome.failed => '書誌を取得できませんでした。書名を入力するか、再取得してください。',
          },
  );
}

class ReservationState {
  final ReservationDraft? draft;
  final List<BookDelivery> waiting;
  final bool formVisible;
  final bool saving;
  final String message;
  const ReservationState({
    this.draft,
    this.waiting = const [],
    this.formVisible = false,
    this.saving = false,
    this.message = '',
  });
}

/// Amazon から ISBN を取れなかったときの案内（`非公開資料:amazon-share-handoff.md` §3）。
/// 電子版でも同じ文言で、追加へは案内しない。
const String amazonNoIsbnMessage =
    'Amazon のこのページからは ISBN を取得できませんでした。紙の本の商品ページから送ってください。';

@Riverpod(keepAlive: true)
class Reservation extends _$Reservation {
  int _lookupGeneration = 0;
  int _pasteId = 0;
  bool _returnToBookshelf = false;
  void openFromBookshelf() {
    _returnToBookshelf = true;
  }

  // 区の貸出し一覧から始めた予約の文脈。**保存か破棄までの一時状態**で、この操作の後に
  // 最初に届いた1冊にだけ効く。期限を過ぎたら捨て、後から共有で届いた本へ漏らさない。
  static const _originLife = Duration(minutes: 30);
  String? _originSystem;
  DateTime? _originAt;
  String? _originOperation;

  /// 貸出し一覧の［カーリルで予約］。区を初期選択として持たせ、カーリルを開く。
  Future<void> startFromLending(String systemId) {
    _originSystem = systemId;
    _originAt = DateTime.now();
    // 本はまだ決まっていない。画面に前の下書きが残っていても、その本へは飛ばさない。
    return _openCalil(_calilHome);
  }

  String? _takeOriginSystem() {
    final system = _originSystem;
    final at = _originAt;
    _originSystem = null;
    _originAt = null;
    if (system == null || at == null) return null;
    return DateTime.now().difference(at) <= _originLife ? system : null;
  }

  @override
  ReservationState build() {
    final app = ref.watch(compositionProvider);
    // **復元で台帳が替わったら下書きを捨てる**（`ledgerSessionProvider`）。
    ref.watch(ledgerSessionProvider);
    _returnToBookshelf = false;
    _originSystem = null;
    _originAt = null;
    _originOperation = null;
    final subscription = app.handoff.bookChanges.listen(
      (_) => _receivePending(),
    );
    ref.onDispose(() => unawaited(subscription.cancel()));
    final notices = app.handoff.deliveries.listen((event) {
      if (event is HandoffNotice) {
        _set(message: 'このURLは取り込めません。カーリルの書籍ページから送ってください。');
      }
    });
    ref.onDispose(() => unawaited(notices.cancel()));
    scheduleMicrotask(() {
      if (ref.mounted) _receivePending();
    });
    return const ReservationState();
  }

  void _set({
    ReservationDraft? draft,
    List<BookDelivery>? waiting,
    bool? visible,
    bool? saving,
    String? message,
    bool clear = false,
  }) {
    state = ReservationState(
      draft: clear ? null : draft ?? state.draft,
      waiting: List.unmodifiable(waiting ?? state.waiting),
      formVisible: visible ?? state.formVisible,
      saving: saving ?? state.saving,
      message: message ?? state.message,
    );
  }

  void _receivePending() {
    final queue = ref.read(compositionProvider).handoff;
    for (final delivery in queue.takeBooks()) {
      receive(delivery);
    }
    if (queue.overflowBooks > 0) {
      _set(message: '受信待ちが上限に達しました。取り込めなかった本を送り直してください。');
      queue.overflowBooks = 0;
    }
  }

  void receive(BookDelivery delivery) {
    final isbn = delivery.book.isbn13;
    final draft = state.draft;
    // **手動入力は待ち行列へ入れない。** 本が届いたということは、利用者はブラウザー側の
    // 経路に戻っている。届いた本を待たせて手入力を続けさせる意味が無いので、入力を
    // 取り消して届いた本へ移る。**確認は出さない** — 取り消すのは利用者自身が始めた
    // 代替手段であり、届いた本のほうが確かな入力である。
    final replacingManual = draft != null && draft.manual && !state.saving;
    if ((!replacingManual && draft?.isbn == isbn) ||
        state.waiting.any((d) => d.book.isbn13 == isbn)) {
      _set(message: 'この本は編集中、または受信待ちです。');
      return;
    }
    final origin = _takeOriginSystem();
    if (draft == null && !state.saving) {
      _activate(delivery, originSystem: origin);
      ref.read(currentTabProvider.notifier).select(ShellTab.reserve);
    } else if (replacingManual) {
      ++_lookupGeneration;
      _set(message: '手動入力を取り消して、届いた本を表示しています。');
      _activate(delivery, originSystem: origin);
      ref.read(currentTabProvider.notifier).select(ShellTab.reserve);
    } else if (state.waiting.length < 20) {
      _set(
        waiting: [...state.waiting, delivery],
        message: '本を受信しました。あとで登録できます。',
      );
    } else {
      _set(message: '受信待ちは20冊までです。この本をあとで送り直してください。');
    }
  }

  /// 受信の判定が予約画面へ出す案内。**下書きも受信待ちも変えない。**
  void notice(String message) => _set(visible: true, message: message);

  void paste(String text) {
    final parsed = parseHandoff(text);
    if (parsed is HandoffBook) {
      receive(BookDelivery(--_pasteId, parsed));
    } else {
      _set(message: 'カーリルの書籍ページのURLを貼り付けてください。');
    }
  }

  void _activate(BookDelivery delivery, {String? originSystem}) {
    final app = ref.read(compositionProvider);
    final isbn = delivery.book.isbn13;
    ReservationBook? existing;
    try {
      existing = app.findReservationBook(isbn);
    } on ReservationIssue {
      // Save repeats this check under the transaction lock; never picks arbitrarily.
      _set(message: '同じISBNの本が複数あります。保存前に書誌の重複を確認してください。');
    }
    final operationId = app.newReservationId();
    _originOperation = originSystem == null ? null : operationId;
    _set(
      draft: ReservationDraft(
        operationId: operationId,
        systems: originSystem == null ? const {} : {originSystem},
        bookId: existing?.id ?? app.reservationBookId(isbn),
        isbn: isbn,
        title: existing?.title ?? '',
        author: existing?.authors.join(' ') ?? '',
        savedBook: existing != null,
        titleEditable: existing != null && existing.title.isEmpty,
        // 届いた経路を残す。Amazon 由来の `source` はホストだけである。
        provider: existing != null
            ? 'saved'
            : delivery.book.source.host == 'calil.jp'
            ? 'calil'
            : 'amazon',
        sourceUrl: delivery.book.source.toString(),
        loading: true,
      ),
      visible: true,
    );
    unawaited(_lookup());
  }

  Future<void> _lookup() async {
    final draft = state.draft;
    if (draft?.isbn == null) return;
    final generation = ++_lookupGeneration;
    try {
      final result = await ref.read(
        reservationLookupProvider(draft!.isbn!).future,
      );
      if (!ref.mounted ||
          generation != _lookupGeneration ||
          state.draft?.operationId != draft.operationId) {
        return;
      }
      final current = state.draft!;
      // 保存済みでも書名が空なら、取れた書誌で埋める（保存で空の書名だけを補う）。
      final replace =
          (!current.savedBook ||
              current.titleEditable && current.title.isEmpty) &&
          !current.edited;
      _set(
        draft: current.copy(
          loading: false,
          result: result,
          title: replace ? result.record?.title : null,
          author: replace ? result.record?.authorLine : null,
        ),
      );
    } catch (_) {
      if (ref.mounted &&
          generation == _lookupGeneration &&
          state.draft != null) {
        _set(
          draft: state.draft!.copy(loading: false, titleEditable: true),
          message: '書誌を取得できませんでした。入力内容は保持しています。',
        );
      }
    }
  }

  void manual() {
    if (state.draft != null || state.saving) return;
    final app = ref.read(compositionProvider);
    _set(
      draft: ReservationDraft(
        operationId: app.newReservationId(),
        bookId: app.reservationBookId(null),
        manual: true,
      ),
      visible: true,
      message: '',
    );
  }

  Future<OpenBdResult?> manualLookup() async {
    final operation = state.draft?.operationId;
    try {
      return await _manualLookup();
    } catch (_) {
      if (ref.mounted &&
          state.draft != null &&
          state.draft!.operationId == operation) {
        _set(
          draft: state.draft!.copy(loading: false),
          message: '書誌を取得できませんでした。入力内容は保持しています。',
        );
      }
      return null;
    }
  }

  Future<OpenBdResult?> _manualLookup() async {
    final draft = state.draft;
    if (draft == null ||
        draft.isbn == null ||
        draft.invalidIsbn ||
        state.saving) {
      return null;
    }
    final existing = ref
        .read(compositionProvider)
        .findReservationBook(draft.isbn!);
    if (existing != null) {
      _set(message: '登録済みの「${existing.title}」を使います。保存済み書誌は変更しません。');
      return null;
    }
    final generation = ++_lookupGeneration;
    _set(draft: draft.copy(loading: true));
    ref.read(compositionProvider).bookInfo.invalidateBook(draft.isbn!);
    ref.invalidate(reservationLookupProvider(draft.isbn!));
    final result = await ref.read(
      reservationLookupProvider(draft.isbn!).future,
    );
    if (!ref.mounted ||
        generation != _lookupGeneration ||
        state.draft?.operationId != draft.operationId ||
        state.draft?.isbn != draft.isbn) {
      return null;
    }
    _set(draft: state.draft!.copy(loading: false, result: result));
    return result;
  }

  void retryLookup() {
    final draft = state.draft;
    if (draft?.isbn == null || state.saving || draft!.loading) return;
    ref.read(compositionProvider).bookInfo.invalidateBook(draft.isbn!);
    ref.invalidate(reservationLookupProvider(draft.isbn!));
    _set(draft: draft.copy(loading: true));
    unawaited(_lookup());
  }

  void applyManualLookup(OpenBdResult result) {
    final draft = state.draft;
    if (draft == null ||
        !draft.manual ||
        result.record == null ||
        state.saving) {
      return;
    }
    final record = result.record!;
    if (record.isbn13 != draft.isbn) return;
    _set(
      draft: ReservationDraft(
        operationId: draft.operationId,
        bookId: draft.bookId,
        isbn: draft.isbn,
        title: record.title,
        author: record.authorLine ?? '',
        provider: 'openbd',
        manual: true,
        edited: true,
        systems: draft.systems,
        coverUrl: record.coverUrl,
      ),
    );
  }

  void edit(String title, String author, String rawIsbn) {
    final draft = state.draft;
    if (draft == null || !draft.manual || state.saving) return;
    ++_lookupGeneration;
    final isbn = rawIsbn.trim().isEmpty ? null : normalizeIsbn13(rawIsbn);
    final app = ref.read(compositionProvider);
    _set(
      draft: ReservationDraft(
        operationId: draft.operationId,
        bookId: isbn == draft.isbn ? draft.bookId : app.reservationBookId(isbn),
        title: title,
        author: author,
        isbn: isbn,
        manual: true,
        edited: true,
        invalidIsbn: rawIsbn.trim().isNotEmpty && isbn == null,
        systems: draft.systems,
      ),
      message: rawIsbn.trim().isNotEmpty && isbn == null
          ? 'ISBNが正しくありません。修正するか空欄にしてください。'
          : '',
    );
  }

  /// 届いた本の書名・著者の入力。**ISBN は届いたものに固定する。** 入れた書名は利用者の
  /// 入力なので、出典は手動にする（届いた URL は残す）。
  void editShared(String title, String author) {
    final draft = state.draft;
    if (draft == null || draft.manual || !draft.titleEditable || state.saving) {
      return;
    }
    _set(
      draft: draft.copy(
        title: title,
        author: author,
        edited: true,
        provider: 'manual',
      ),
    );
  }

  void select(String id) {
    final draft = state.draft;
    if (draft == null || state.saving) return;
    final systems = {...draft.systems};
    if (!systems.add(id)) systems.remove(id);
    _set(draft: draft.copy(systems: Set.unmodifiable(systems)));
  }

  void removeWaiting(int id) =>
      _set(waiting: state.waiting.where((d) => d.id != id).toList());

  void discard() {
    if (state.saving) return;
    _advance('この本の取り込みを取り消しました。');
  }

  void _advance(String message) {
    ++_lookupGeneration;
    _originOperation = null;
    final waiting = state.waiting;
    _set(
      clear: true,
      visible: false,
      saving: false,
      message: message,
      waiting: waiting.isEmpty ? [] : waiting.skip(1).toList(),
    );
    if (waiting.isNotEmpty) _activate(waiting.first);
  }

  Future<void> save({required bool wanted}) async {
    final draft = state.draft;
    if (draft == null || state.saving) return;
    if (normalizeTitle(draft.title).isEmpty) {
      _set(message: 'タイトルを入力してください。');
      return;
    }
    if (draft.invalidIsbn) {
      _set(message: 'ISBNが正しくありません。修正するか空欄にしてください。');
      return;
    }
    _set(saving: true);
    // Yield once so rapid repeated taps see saving, without awaiting any external I/O.
    await Future<void>.delayed(Duration.zero);
    if (!ref.mounted) return;
    final app = ref.read(compositionProvider);
    try {
      app.saveReservation(
        book: ReservationBook(
          id: draft.bookId,
          title: normalizeTitle(draft.title),
          authors: draft.author.trim().isEmpty ? [] : [draft.author.trim()],
          isbn13: draft.isbn,
          provider: draft.provider,
          sourceUrl: draft.provider == 'openbd'
              ? 'https://api.openbd.jp/v1/get?isbn=${draft.isbn}'
              : draft.sourceUrl,
        ),
        operationId: draft.operationId,
        systems: draft.systems.toList(),
        wanted: wanted,
      );
      final fromLending = _originOperation == draft.operationId;
      final returnToShelf = _returnToBookshelf && state.waiting.isEmpty;
      final returnToLending = fromLending && state.waiting.isEmpty;
      _advance(
        wanted ? '本棚の「読みたい」に登録しました。' : '${draft.systems.length}館に予約中として登録しました。',
      );
      if (returnToShelf) {
        _returnToBookshelf = false;
        ref.read(currentTabProvider.notifier).select(ShellTab.bookshelf);
      } else if (returnToLending) {
        // 「予約した」は貸出し一覧、「読みたい」は貸出し一覧に載らないので本棚へ。
        ref
            .read(currentTabProvider.notifier)
            .select(wanted ? ShellTab.bookshelf : ShellTab.lending);
      }
    } on ReservationIssue catch (error) {
      final names = {for (final s in app.loadLibraries()) s.id: s.name};
      final systems = error.systems.map((id) => names[id] ?? id).join('・');
      _set(
        saving: false,
        message: switch (error.code) {
          'active-wip' => '$systemsには予約中・取置中・貸出中の記録があります。今回は登録していません。',
          'preferred-branch' =>
            '$systemsの常用館が決まっていません。上の［常用館を選ぶ］から選んでください。今回は登録していません。',
          'no-system' => '予約した館を選んでください。',
          'book-title' => 'タイトルを入力してください。',
          'ambiguous-book' => '同じISBNの本が複数あります。書誌の重複を確認してください。',
          _ => '登録できませんでした（${error.code}）。入力内容は保持しています。',
        },
      );
    } catch (_) {
      _set(saving: false, message: '登録できませんでした。入力内容は保持しています。');
    }
  }

  static final Uri _calilHome = Uri.parse('https://calil.jp/');

  /// 予約画面の［カーリルで探す］。**届いた本があればその書籍ページを開く**（2026-10-13）。
  /// `isbn` は正規化済みの13桁で、カーリルは13桁の `/book/` も開ける（利用者が確認）。
  /// 書籍ページから拡張で送り返すと、同じ ISBN の `kind=book` として戻る。
  Future<void> openCalil() {
    final isbn = state.draft?.isbn;
    return _openCalil(
      isbn == null ? _calilHome : Uri.parse('https://calil.jp/book/$isbn'),
    );
  }

  Future<void> _openCalil(Uri url) async {
    _set(visible: true, message: '');
    try {
      await ref.read(compositionProvider).openSite(url);
    } catch (_) {
      if (ref.mounted) _set(message: 'ブラウザーを開けませんでした。');
    }
  }
}
