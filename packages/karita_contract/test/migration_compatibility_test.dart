import 'dart:convert';

import 'package:karita_contract/karita_contract.dart';
import 'package:test/test.dart';

// Frozen checksums from the pre-migration release lineage. SQL comments are
// part of the persisted contract. Extend migrations; never rewrite these.
const baselineJson = r'''
{
  "0001_init.sql": "sha256:56ffa889697d016ebdd107181e4981f2366abd892d00015b5ee7584fc2ad2183",
  "0002_aggregates_and_sync.sql": "sha256:55ce433170d41ceabc78724c84bd0180cef773de0db121713c0a1a93ece0138b",
  "0003_sync_runs.sql": "sha256:50339c18a22d19f90bc5a6443cb4f7fc639b1224642387054c426a3fb9f8f6fa",
  "0004_loan_operations.sql": "sha256:9b1c337c78db0a12987613a81b2448d267af8061e4da1c243ffebf09a9d03b84",
  "0005_library_membership_sync.sql": "sha256:cce1b9645a419d8cf49a29f27a08036a2f441ea69b3ab9a0379cb277fb6eb1fc",
  "0006_envelope_v2.sql": "sha256:d11baf00996aebe1d3532c6c3f0e6413b1f651374417d974e72b2f82aa816a9d",
  "0007_synced_file.sql": "sha256:acd6165c2aa6131b08a1085788a0ca00d405a4834291427c3c8602dbfc64414f",
  "0008_library_system_sync.sql": "sha256:8a8c35aa3494dc0aae7df7f531e7d81f23e628fd4ddf64a0c794d7bb91a12a68",
  "0009_drop_synced_file.sql": "sha256:850681695bbbd33139c8dc067f1183d43338aaa157741aa773e8aa503692c2d6",
  "0010_preferred_branch.sql": "sha256:d2dda396194f118bbf20c132df289ed26fd795778a0799a8349b9cc158ac7702",
  "0011_library_setting.sql": "sha256:82f7723fbe724d581f36045b14ed319397c3b30475575fddf537df46fefcc4a3",
  "0012_book_preferences.sql": "sha256:8285f6ed21ba5a20f584e11ecf57af6a34cc8bde71c5442b08524ade0008cc28",
  "0013_bookshelf.sql": "sha256:72a126d3e68b076ec371018ffc18e1a72329756cb676b8558416c732c2781ecf"
}
''';

void main() {
  test(
    'existing migration SQL remains compatible with pre-migration databases',
    () {
      final baseline = (jsonDecode(baselineJson) as Map<String, dynamic>)
          .cast<String, String>();
      final current = {
        for (final migration in discover())
          migration.filename: migration.checksum,
      };
      for (final entry in baseline.entries) {
        expect(
          current[entry.key],
          entry.value,
          reason: '${entry.key}: applied SQL (including comments) is immutable',
        );
      }
    },
  );
}
