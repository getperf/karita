/// 1ケースぶんの世界。`Harness` にプロファイルを作らせ、driver へ渡す。
///
/// 組み立ての実体は `harness.dart` にある。**二つ持たない** — ケースを回す組み立てと、
/// 単体試験の組み立てが別々にずれると、片方でだけ再現する不具合ができる。
library;

import 'package:karita_contract/karita_contract.dart';
import 'package:karita_sync/karita_sync.dart';

import 'harness.dart';

class CaseWorld {
  final Harness harness;
  final FixtureDriver driver;

  CaseWorld._(this.harness, this.driver);

  factory CaseWorld.create(Contracts contracts) {
    late final CaseWorld world;
    final harness = Harness.create(contracts, prefix: 'karita-d3-');
    world = CaseWorld._(
      harness,
      FixtureDriver(contracts, (name) => world._build(name)),
    );
    return world;
  }

  DriverProfile _build(String name) {
    // **検証は手動競合モードで始める。** 製品の既定は `lww` 固定だが、手動競合モードを
    // 検証側に残すことも同じ決定の一部である。ケース03・04 は人手の解決を測るため、
    // 自動解決が働くとそもそも競合が残らない。自動解決を測るケース（13・14）は
    // fixture の `config` が明示的に切り替える。
    final device = harness.device(name, autoResolve: AutoResolvePolicy.manual);
    return DriverProfile(
      name,
      device.engine,
      // **端末が持つ集合をそのまま渡す。** 転送が握っているのと同じものでなければ、`fault` を
      // 書いたケースが故障の入らないまま緑になる。
      faults: device.faults,
      // `remote` の表明は転送先そのものを見る。port の `list` は畳んだ後を返す。
      remoteContents: harness.appDataEnvelopes,
    );
  }

  void dispose() => harness.dispose();
}
