/// 管理区設定を生成・更新するユースケース。**純関数だけを置く。**
///
/// 移送元: book-sync-model の `src/bops_application/library_areas.py`。
library;

import 'errors.dart';
import 'library_areas.dart';

/// カタログの候補を、**書き込む集約だけ**の一覧へ整える。
///
/// 1図書館システムが1集約なので、返すのは「選ばれたものをどう書くか」だけでよい。**選ばれて
/// いない図書館システムを保つ処理が要らない** — 触らない集約は触らないだけである。
///
/// **版を上げない。** 版を +1 して封筒を積むのは [LibrarySystems.register] である。ここは
/// 外部データと手入力の合成だけを持つ純関数に保つ。
///
/// **常用館を運ばない**（`0011`）。以前はここが利用者の常用館を手で引き継ぎ、新しい分館一覧に
/// 無ければ外して「外した」を返していた。**それは寿命の違うものを同じ集約へ押し込んだ結果の
/// 逃げである。** 利用者値が `LibrarySetting` の行へ出たので、カタログの洗い替えは利用者値に
/// 触れなくなった。**分館が消えて参照の切れた設定は、`doctor` が報告する**
/// （`LibrarySettings.danglingPreferredBranches`）。
List<LibrarySystem> prepareRegistration(
  LibrariesConfig current, {
  required String pref,
  required String city,
  required List<LibrarySystem> selectedSystems,
}) {
  if (selectedSystems.isEmpty) {
    throw const DomainError('少なくとも一つの図書館システムを選択してください。',
        code: 'library-system');
  }
  if (pref.trim().isEmpty || city.trim().isEmpty) {
    throw const DomainError('都道府県と市区町村は必須です。', code: 'library-system');
  }
  final currentById = {
    for (final system in current.librarySystems) system.id: system,
  };
  final sorted = [...selectedSystems]..sort((a, b) => a.id.compareTo(b.id));
  // **`copyWith` を使わない。** null を「変更なし」と読む形だと、登録済みの側でリンクが空に
  // なっているときにカタログの値が生き残る。ここが要るのは「登録済みの側で決まる」であって
  // 「登録済みの側に値があれば決まる」ではない。
  final systems = [
    for (final system in sorted)
      LibrarySystem(
        id: system.id,
        pref: pref.trim(),
        city: city.trim(),
        name: system.name,
        branches: system.branches,
        // 再登録・更新時にも、**利用者が設定した外部リンクをカタログの値で上書きしない。**
        opacSearchUrlTemplate: currentById.containsKey(system.id)
            ? currentById[system.id]!.opacSearchUrlTemplate
            : system.opacSearchUrlTemplate,
        // homepage だけは登録済みが空ならカタログの値を採る（Python の `or` と同じ）。
        homepageUrl: currentById.containsKey(system.id)
            ? (currentById[system.id]!.homepageUrl ?? system.homepageUrl)
            : system.homepageUrl,
      ),
  ];
  for (final system in systems) {
    system.validate();
  }
  return systems;
}
