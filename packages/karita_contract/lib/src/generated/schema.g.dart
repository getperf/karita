// **正本である。** 2026-09-02 の凍結まで book-sync-model から取り込む生成物だったが、
// 凍結で正本がここへ移り、生成器（tools/contract_sync）と出所検査は消えた。
//
// **直すときは規則を先に決めること。** ここは Python と Dart が同じ内容を読むという性質を
// 失っており、ハッシュで縛るものが無い。ずれを捕まえるのは相互運用の試験だけである
// （tools/conformance の blib_interop_test と drive_interop_test）。
//
// ignore_for_file: lines_longer_than_80_chars
library;

/// `src/contracts/schema/` からの相対パス → ファイルの生テキスト。
const Map<String, String> schemaSources = {
  'payload/book_review.schema.json': r'''
{
  "type": "object",
  "additionalProperties": false,
  "required": [
    "book_id"
  ],
  "properties": {
    "book_id": {
      "type": "string"
    },
    "rating": {
      "type": [
        "integer",
        "null"
      ],
      "minimum": 1,
      "maximum": 5
    },
    "review": {
      "type": [
        "string",
        "null"
      ]
    }
  }
}
''',
  'sync-event-v3.schema.json': r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://frsw3.invalid/book-sync-model/schema/sync-event-v3.schema.json",
  "title": "SyncEvent envelope v3",
  "description": "Version 3 adds book_review and bookshelf causal metadata. Upgrade all devices before bookshelf operations.",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schemaVersion",
    "eventId",
    "deviceId",
    "createdAtUtc",
    "entityType",
    "entityId",
    "operation",
    "baseVersion",
    "resultVersion",
    "payloadHash",
    "payload"
  ],
  "properties": {
    "schemaVersion": {
      "const": 3,
      "description": "Version 3 only. Supported versions are defined in envelope-versions.json."
    },
    "eventId": {
      "$ref": "#/$defs/uuid"
    },
    "deviceId": {
      "type": "string",
      "minLength": 1,
      "maxLength": 64,
      "description": "端末ごとに一意。例: windows-<UUID>"
    },
    "createdAtUtc": {
      "$ref": "#/$defs/utcTimestamp"
    },
    "entityType": {
      "enum": [
        "book",
        "book_preference",
        "library_system",
        "library",
        "library_membership",
        "library_setting",
        "loan",
        "reading_record",
        "book_review"
      ],
      "description": "Version 2 entity types plus book_review."
    },
    "entityId": {
      "$ref": "#/$defs/uuid"
    },
    "operation": {
      "enum": [
        "upsert",
        "tombstone"
      ]
    },
    "baseVersion": {
      "$ref": "#/$defs/version",
      "description": "編集開始時点で端末が認識していた版。新規作成は 0。"
    },
    "resultVersion": {
      "$ref": "#/$defs/version",
      "minimum": 1,
      "description": "更新後の版。常に baseVersion より大きい。この関係はJSON Schemaで表現できないため実装側で検査する。"
    },
    "payloadHash": {
      "type": "string",
      "pattern": "^sha256:[0-9a-f]{64}$",
      "description": "正準化した payload のSHA-256。正準化規則は docs/architecture/sqlite-drive-sync-protocol.md を正本とする。"
    },
    "resolvesEventIds": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/uuid"
      },
      "uniqueItems": true,
      "default": [],
      "description": "競合解決イベントが決着させた eventId の一覧。受信側はこれに自端末の未解決conflictを含む場合、版判定を迂回して適用する。空でも省略せず [] を書く。省略できると、封筒のバイト列が実装ごとに変わる。"
    },
    "domainEventType": {
      "$ref": "#/$defs/domainEventType"
    },
    "payload": {
      "type": "object",
      "description": "更新後の集約スナップショット。部分更新ではない。tombstone では最小限でよい。集約ごとの形は payload/<entityType>.schema.json が定める。この封筒スキーマでは拘束しない — entityType の enum は7集約すべてを許すが、payloadスキーマがあるのは実装済みの集約だけである。"
    }
  },
  "$defs": {
    "domainEventType": {
      "type": "string",
      "minLength": 1,
      "maxLength": 64,
      "pattern": "^[A-Za-z][A-Za-z0-9]*$",
      "description": "受信側でも同じ DomainEvent を書けるようにするための語彙（例 PatrolCompleted）。**同期層はこの値を解釈しない。** 語彙は bops の持ち物であり、封筒は運ぶだけである。ここに enum を書くと、業務イベントを増やすたびに封筒の版が上がる。値が無いときはキーを出さない — null を書くか省くかで正準化のバイト列が変わるため、規則を「値があるときだけ」の一本にする。"
    },
    "uuid": {
      "type": "string",
      "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    },
    "utcTimestamp": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
      "description": "RFC3339秒精度・Z終端のみ。オフセット表記を許さない。"
    },
    "localDate": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
      "description": "図書館のローカル暦日。payload 内の *_on 列が従う。集約ごとのpayloadスキーマを追加する際に参照する。"
    },
    "nullableLocalDate": {
      "anyOf": [
        {
          "$ref": "#/$defs/localDate"
        },
        {
          "type": "null"
        }
      ],
      "description": "payload はスナップショットであり、空の項目は省略しても null で書いてもよい。"
    },
    "version": {
      "type": "integer",
      "minimum": 0,
      "maximum": 9007199254740991,
      "description": "上限は 2^53-1 とする。Dart の int は 64bit だが Web では double であり、2^53 を超えると値が変わる。上限を宣言しないと Python でだけ通る封筒ができる。"
    }
  }
}
''',
  'sync-event-v4.schema.json': r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://frsw3.invalid/book-sync-model/schema/sync-event-v4.schema.json",
  "title": "SyncEvent envelope v4",
  "description": "Version 4 adds latest bookshelf registration timestamps. Upgrade all devices before bookshelf operations.",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schemaVersion",
    "eventId",
    "deviceId",
    "createdAtUtc",
    "entityType",
    "entityId",
    "operation",
    "baseVersion",
    "resultVersion",
    "payloadHash",
    "payload"
  ],
  "properties": {
    "schemaVersion": {
      "const": 4,
      "description": "Version 4 only. Supported versions are defined in envelope-versions.json."
    },
    "eventId": {
      "$ref": "#/$defs/uuid"
    },
    "deviceId": {
      "type": "string",
      "minLength": 1,
      "maxLength": 64,
      "description": "端末ごとに一意。例: windows-<UUID>"
    },
    "createdAtUtc": {
      "$ref": "#/$defs/utcTimestamp"
    },
    "entityType": {
      "enum": [
        "book",
        "book_preference",
        "library_system",
        "library",
        "library_membership",
        "library_setting",
        "loan",
        "reading_record",
        "book_review"
      ],
      "description": "Version 2 entity types plus book_review."
    },
    "entityId": {
      "$ref": "#/$defs/uuid"
    },
    "operation": {
      "enum": [
        "upsert",
        "tombstone"
      ]
    },
    "baseVersion": {
      "$ref": "#/$defs/version",
      "description": "編集開始時点で端末が認識していた版。新規作成は 0。"
    },
    "resultVersion": {
      "$ref": "#/$defs/version",
      "minimum": 1,
      "description": "更新後の版。常に baseVersion より大きい。この関係はJSON Schemaで表現できないため実装側で検査する。"
    },
    "payloadHash": {
      "type": "string",
      "pattern": "^sha256:[0-9a-f]{64}$",
      "description": "正準化した payload のSHA-256。正準化規則は docs/architecture/sqlite-drive-sync-protocol.md を正本とする。"
    },
    "resolvesEventIds": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/uuid"
      },
      "uniqueItems": true,
      "default": [],
      "description": "競合解決イベントが決着させた eventId の一覧。受信側はこれに自端末の未解決conflictを含む場合、版判定を迂回して適用する。空でも省略せず [] を書く。省略できると、封筒のバイト列が実装ごとに変わる。"
    },
    "domainEventType": {
      "$ref": "#/$defs/domainEventType"
    },
    "payload": {
      "type": "object",
      "description": "更新後の集約スナップショット。部分更新ではない。tombstone では最小限でよい。集約ごとの形は payload/<entityType>.schema.json が定める。この封筒スキーマでは拘束しない — entityType の enum は7集約すべてを許すが、payloadスキーマがあるのは実装済みの集約だけである。"
    }
  },
  "$defs": {
    "domainEventType": {
      "type": "string",
      "minLength": 1,
      "maxLength": 64,
      "pattern": "^[A-Za-z][A-Za-z0-9]*$",
      "description": "受信側でも同じ DomainEvent を書けるようにするための語彙（例 PatrolCompleted）。**同期層はこの値を解釈しない。** 語彙は bops の持ち物であり、封筒は運ぶだけである。ここに enum を書くと、業務イベントを増やすたびに封筒の版が上がる。値が無いときはキーを出さない — null を書くか省くかで正準化のバイト列が変わるため、規則を「値があるときだけ」の一本にする。"
    },
    "uuid": {
      "type": "string",
      "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    },
    "utcTimestamp": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
      "description": "RFC3339秒精度・Z終端のみ。オフセット表記を許さない。"
    },
    "localDate": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
      "description": "図書館のローカル暦日。payload 内の *_on 列が従う。集約ごとのpayloadスキーマを追加する際に参照する。"
    },
    "nullableLocalDate": {
      "anyOf": [
        {
          "$ref": "#/$defs/localDate"
        },
        {
          "type": "null"
        }
      ],
      "description": "payload はスナップショットであり、空の項目は省略しても null で書いてもよい。"
    },
    "version": {
      "type": "integer",
      "minimum": 0,
      "maximum": 9007199254740991,
      "description": "上限は 2^53-1 とする。Dart の int は 64bit だが Web では double であり、2^53 を超えると値が変わる。上限を宣言しないと Python でだけ通る封筒ができる。"
    }
  }
}
''',
  'envelope-versions.json': r'''
{
  "description": "封筒の版の宣言。受理する版の集合と、発行する版を分けて持つ。PythonとDartがこの同じファイルを読む。受理集合はスキーマを持っている版の集合であり、形を検証できることと受理できることが同義になる。発行版を max(supported) にしないのは、新しい版のスキーマを置いても発行が上がってはならないためである。全端末が新版を受理できるようになってから発行を上げる、という二段階が要る。ファイル名を .schema.json で終わらせないのは、これがスキーマではなく宣言であり、スキーマ登録の走査に拾わせないためである。",
  "supported": [
    1,
    2,
    3,
    4
  ],
  "emit": 4,
  "schemaByVersion": {
    "1": "sync-event.schema.json",
    "2": "sync-event-v2.schema.json",
    "3": "sync-event-v3.schema.json",
    "4": "sync-event-v4.schema.json"
  }
}
''',
  'identity.json': r'''
{
  "description": "集約の同一性の種。業務キーから entityId を決定的に導くための名前空間である。entityId は uuid でなければならないため（sync-event.schema.json の $defs/uuid）、ISBN や system_id をそのまま id にはできず、uuid5 で決定的に写す。二端末が同じ実体を独立に登録したとき、同じ id になって初めて競合として立ち、LWW が一件へ収束させる。namespace が実装ごとにずれると id が食い違い、重複が競合にすらならず両方が正常に適用される — 静かに壊れるため、PythonとDartとFlutterがこの同じファイルを読む。namespace は一度決めたら変えない。変えると既に配った entityId と一致しなくなる。kinds は種別ごとの名前空間を分けるための名前であり、entityType の値と一致させる。したがって封筒の enum に無い種別は宣言できない。照合先は受理する全ての版の合併である — 発行版だけを見ると、ある版でだけ宣言された種別を受理できるようになっても発行を上げるまで宣言に書けず、受理と発行を二段階に分ける手順と噛み合わない。ファイル名を .schema.json で終わらせないのは、これがスキーマではなく宣言であり、スキーマ登録の走査に拾わせないためである。",
  "namespace": "c036a129-14eb-400c-adfa-e836f9c7a214",
  "kinds": [
    "book",
    "book_preference",
    "loan",
    "library_membership",
    "library_setting",
    "library_system",
    "book_review"
  ]
}
''',
  'payload/book_preference.schema.json': r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "book_id": {
      "type": [
        "string",
        "null"
      ]
    },
    "want_to_read": {
      "type": [
        "boolean",
        "null"
      ]
    },
    "priority": {
      "type": [
        "integer",
        "null"
      ]
    },
    "tags": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "memo": {
      "type": [
        "string",
        "null"
      ]
    },
    "shelf_state": {
      "type": [
        "string",
        "null"
      ],
      "enum": [
        "wanted",
        "read",
        "removed",
        "none",
        null
      ]
    },
    "shelf_token": {
      "type": [
        "string",
        "null"
      ]
    },
    "shelf_changed_at_utc": {
      "type": [
        "string",
        "null"
      ]
    },
    "wanted_registered_at_utc": {
      "anyOf": [{"$ref": "../sync-event.schema.json#/$defs/utcTimestamp"}, {"type": "null"}]
    },
    "read_registered_at_utc": {
      "anyOf": [{"$ref": "../sync-event.schema.json#/$defs/utcTimestamp"}, {"type": "null"}]
    },
    "manual_reads": {
      "type": "array",
      "items": {
        "type": "object",
        "required": [
          "id",
          "on"
        ],
        "additionalProperties": false,
        "properties": {
          "id": {
            "type": "string"
          },
          "on": {
            "type": "string"
          }
        }
      }
    }
  }
}
''',
  'payload/book.schema.json': r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://frsw3.invalid/book-sync-model/schema/payload/book.schema.json",
  "title": "book payload v1",
  "description": "Book 集約のスナップショット。部分更新ではないため、ここに無い項目は「変更なし」ではなく「空」である。properties の並びが books テーブルの列順に対応する（contracts/mapping.py が導出する）。",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "title": {
      "type": ["string", "null"]
    },
    "authors": {
      "type": "array",
      "items": {
        "type": "string",
        "minLength": 1
      },
      "description": "著者名の配列。空文字の要素を許さない。"
    },
    "isbn13": {
      "type": ["string", "null"],
      "pattern": "^[0-9]{13}$",
      "description": "13桁のISBN。ハイフンを含めない。"
    },
    "publisher": {
      "type": ["string", "null"]
    },
    "memo": {
      "type": ["string", "null"]
    },
    "published_on": {
      "$ref": "../sync-event.schema.json#/$defs/nullableLocalDate"
    },
    "book_references": {
      "type": "array",
      "items": {
        "type": "object"
      },
      "description": "Bookの出典（BookReference）。項目は bops の集約定義であり O1 で確定するため、版1では形を拘束しない。"
    }
  }
}
''',
  'payload/library_membership.schema.json': r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://frsw3.invalid/book-sync-model/schema/payload/library_membership.schema.json",
  "title": "library_membership payload v1",
  "description": "LibraryMembership 集約のスナップショット。「その図書館システムを確認し終えた」という一つの事実であり、端末ごとの事実ではない。entityId は uuid5(namespace, system_id) で決定的に導くため、二端末が別々に棚卸を完了しても同じ id を指して競合として立ち、LWW が解決する。properties の並びが library_memberships テーブルの列順に対応する（contracts/mapping.py が導出する）。",
  "type": "object",
  "additionalProperties": false,
  "required": ["system_id", "last_reconciled_at_utc"],
  "properties": {
    "system_id": {
      "type": "string",
      "minLength": 1,
      "description": "図書館システムID。entityId から逆算できないため payload に持たせる。受信側はこれでどのシステムの事実かを知る。"
    },
    "last_reconciled_at_utc": {
      "$ref": "../sync-event.schema.json#/$defs/utcTimestamp",
      "description": "棚卸を完了した時刻。LWW の決定キー（記録時刻）と一致するため、自動解決の結果は実質 max() になり、後から棚卸した側が残る。"
    }
  }
}
''',
  'payload/library_setting.schema.json': r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://frsw3.invalid/book-sync-model/schema/payload/library_setting.schema.json",
  "title": "library_setting payload v1",
  "description": "図書館システムごとの利用者値。常用館とマイページ URL を、カタログ（library_system）から出してここへ置く。entityId は uuid5(namespace, \"<system_id>/<key>\") で導くため、鍵ごとに別の集約になる。これが要点である — 同じ集約に入れると LWW が payload 全体を差し替えるので、二端末が常用館とマイページ URL を別々に変えたとき後勝ちで片方が消える。ローカルのトランザクションを分けても直らない（行が同じだからである）。項目ごとのマージは「payload は全体スナップショットである」という契約の根幹を変えるので採らない。カタログと利用者値は寿命も違う — カタログはカーリル由来で再登録のたびに洗い替えるが、利用者値は洗い替えの対象ではない（docs/architecture/libraries-in-sqlite.md 2c）。properties の並びが library_settings テーブルの列順に対応する。required を置かない — tombstone の payload は最小限でよく（validate.payload が required を外す）、required を置くと相手端末からの tombstone が NOT NULL 違反になって適用経路を SQLite のエラーで止める。解除は tombstone で表し、payload は system_id と key だけになる。",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "system_id": {
      "type": ["string", "null"],
      "minLength": 1,
      "description": "図書館システムID。entityId は uuid であり逆算できないため payload に持たせる。library_systems.system_id が指す先と同じ文字列である。参照先が消えていることは doctor が報告し、同期層は見ない。"
    },
    "key": {
      "enum": ["preferred_branch", "mypage_url"],
      "description": "どの設定か。汎用の key/value にせず enum で縛る — 綴りが実装間でずれると、同じ設定が別の集約になって静かに壊れる（identity.json が kinds を enum で縛っているのと同じ理由）。増やすときは受理する全ての版で足りる形かを先に決めること。"
    },
    "value": {
      "type": ["string", "null"],
      "description": "設定の値。preferred_branch では常用館の分館 id（branches[].id であり calil_libkey ではない — pickup_library_id と同じ識別子空間でなければ受取館の既定として引けない）。mypage_url ではマイページ（ログイン入口）の URL である。指定された分館が branches に在ることは登録経路が担保し、同期層は見ない。セッション ID を含む URL を弾くのは入力経路（karita_handoff の checkSaveableUrl）であって、ここではない。"
    },
    "checked_on": {
      "$ref": "../sync-event.schema.json#/$defs/nullableLocalDate",
      "description": "確認した日。出典によって意味が変わる — 既定値なら作者が採取した日、取り込み値なら利用者が取り込んだ日である。出典そのものは持たない（保存値があるかどうかだけで決まる。karita-ui-probe の library-site-url.md §3）。preferred_branch では使わない。"
    }
  }
}
''',
  'payload/library_system.schema.json': r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://frsw3.invalid/book-sync-model/schema/payload/library_system.schema.json",
  "title": "library_system payload v1",
  "description": "LibrarySystem 集約のスナップショット。部分更新ではないため、ここに無い項目は「変更なし」ではなく「空」である。分館は独立集約にせず branches 配列として持つ — 別集約にすると、システムと分館が別々に競合して別々に LWW され、libraries.toml が持っていた「設定全体の洗い替え」という粒度が変わる（docs/architecture/libraries-in-sqlite.md）。entityId は uuid5(namespace, system_id) で決定的に導くため、二端末が同じ図書館システムを独立に登録しても同じ id を指して競合として立ち、LWW が一件へ収束させる。properties の並びは library_systems テーブルの列の追加順である（contracts/mapping.py が導出する）。0010 で足した preferred_branch_id は ALTER TABLE ADD COLUMN なので version 列より後ろに付き、位置の対応はそこで切れる。列は名前で読み書きする（aggregates.upsert が列名を明示した INSERT を組む）ので位置は効かない。**required を置かない。** tombstone の payload は最小限でよく（validate.payload が required を外す）、required を置くと相手端末からの tombstone が NOT NULL 違反になって適用経路を SQLite のエラーで止める。「取り込めないイベントを破棄しない」と収束の両方が壊れるのは、0005 が system_id に UNIQUE を張らない理由と同じである。tombstone を持つもう一つの集約である Book も同じ形をしている。業務上の不変条件（都道府県・市区町村・分館が少なくとも一つ）は bops_domain の LibrariesConfig.validate が持つ。",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "system_id": {
      "type": ["string", "null"],
      "minLength": 1,
      "description": "図書館システムID（`Tokyo_Minato` のような文字列）。entityId は uuid でなければならず逆算できないため payload に持たせる。library_memberships.system_id と loans.system_id が指す先である。"
    },
    "pref": {
      "type": ["string", "null"],
      "minLength": 1,
      "description": "都道府県。"
    },
    "city": {
      "type": ["string", "null"],
      "minLength": 1,
      "description": "市区町村。"
    },
    "name": {
      "type": ["string", "null"],
      "minLength": 1,
      "description": "図書館システムの表示名。"
    },
    "opac_search_url_template": {
      "type": ["string", "null"],
      "description": "OPAC の検索URLの雛形。"
    },
    "homepage_url": {
      "type": ["string", "null"],
      "description": "巡回時に開く公式サイト。手入力で上書きできる。"
    },
    "branches": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "calil_libkey", "name"],
        "properties": {
          "id": {"type": "string", "minLength": 1},
          "calil_libkey": {"type": "string", "minLength": 1},
          "name": {"type": "string", "minLength": 1}
        }
      },
      "description": "分館（Branch）の配列。row_to_payload は空の配列を落とすため、分館0件の集約は往復のたびに branches を欠いた payload になる。additionalProperties を閉じないのは、分館の項目が bops の集約定義であり、増えたときの代償を payload スキーマの版上げにしないためである（book_references が版1で形を拘束しないのと同じ理由）。"
    }
  }
}
''',
  'payload/loan.schema.json': r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://frsw3.invalid/book-sync-model/schema/payload/loan.schema.json",
  "title": "loan payload v1",
  "description": "Loan 集約のスナップショット。部分更新ではないため、ここに無い項目は「変更なし」ではなく「空」である。properties の並びが loans テーブルの列順に対応する（contracts/mapping.py が導出する）。required は DDL の NOT NULL に対応する。",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "book_id",
    "status"
  ],
  "properties": {
    "book_id": {
      "type": "string",
      "minLength": 1
    },
    "system_id": {
      "type": [
        "string",
        "null"
      ]
    },
    "library_id": {
      "type": [
        "string",
        "null"
      ],
      "description": "廃止予定の旧館ID。読み取り互換のためだけに残す。新規書込みは pickup_library_id / loan_library_id を使う。"
    },
    "pickup_library_id": {
      "type": [
        "string",
        "null"
      ]
    },
    "loan_library_id": {
      "type": [
        "string",
        "null"
      ],
      "description": "廃止予定の貸出館。読み取り互換のためだけに残す。館は受取館の1つだけとし（受取も返却も同じ窓口で行う）、新規書込みは pickup_library_id を使う。library_id と同じ扱いである。列を落とさないのは、旧版が書いたこの項目を持つ封筒が転送先に残っており、additionalProperties: false で弾くと取り込めないイベントになるためである。"
    },
    "status": {
      "enum": [
        "reserved",
        "ready_for_pickup",
        "borrowed",
        "returned",
        "cancelled",
        "expired"
      ],
      "description": "docs/architecture/loan-lifecycle.md の6状態。"
    },
    "reserved_on": {
      "$ref": "../sync-event.schema.json#/$defs/nullableLocalDate"
    },
    "pickup_available_on": {
      "$ref": "../sync-event.schema.json#/$defs/nullableLocalDate"
    },
    "pickup_due_on": {
      "$ref": "../sync-event.schema.json#/$defs/nullableLocalDate"
    },
    "borrowed_on": {
      "$ref": "../sync-event.schema.json#/$defs/nullableLocalDate"
    },
    "due_on": {
      "$ref": "../sync-event.schema.json#/$defs/nullableLocalDate"
    },
    "returned_on": {
      "$ref": "../sync-event.schema.json#/$defs/nullableLocalDate"
    },
    "cancelled_on": {
      "$ref": "../sync-event.schema.json#/$defs/nullableLocalDate"
    },
    "note": {
      "type": [
        "string",
        "null"
      ]
    },
    "first_return_basis": {
      "type": [
        "string",
        "null"
      ]
    },
    "first_return_at_utc": {
      "type": [
        "string",
        "null"
      ]
    }
  }
}
''',
  'sync-event-v2.schema.json': r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://frsw3.invalid/book-sync-model/schema/sync-event-v2.schema.json",
  "title": "SyncEvent envelope v2",
  "description": "端末間で受け渡す不変イベントの封筒の版2。版1との差は任意項目 domainEventType だけである。**版2に積むものは一度にまとめてある。** 版上げは受理集合を先に広げて配り、全端末が追いついてから発行を上げるという二段階を要するため高くつく。後からこの版へ項目を足してはならない — 同じ版番号が二つの形を持ち、版で形を固定する仕組み自体が壊れる。**L4 でこの規則を意図的に一度だけ外れた。** entityType の enum から synced_file を落とし、版番号は2のままとした（docs/architecture/libraries-in-sqlite.md）。規則が守っているのは「古い版を持つ端末が、同じ版番号の新しい封筒を読み違えないこと」であり、互換性を保たないと決めた以上、守る対象の端末が存在しない。版3を足すと受理集合・分岐・二段階の配布手順が増えるだけで誰も得をしない。**切替の前に転送先を空にする。** 旧 enum で書かれた synced_file の封筒が残っていると envelope-enum で落ち、pending ではなく invalid として毎 run 数え直される。schemaVersion はこの検証より先に読み、未対応であれば pending_events(reason='schema') に保持する。スキーマ検証の失敗として扱わない。",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schemaVersion",
    "eventId",
    "deviceId",
    "createdAtUtc",
    "entityType",
    "entityId",
    "operation",
    "baseVersion",
    "resultVersion",
    "payloadHash",
    "payload"
  ],
  "properties": {
    "schemaVersion": {
      "const": 2,
      "description": "この文書は版2の定義である。他の値はこの文書では扱わない。受理するかどうかは envelope-versions.json の supported が決める。"
    },
    "eventId": {
      "$ref": "#/$defs/uuid"
    },
    "deviceId": {
      "type": "string",
      "minLength": 1,
      "maxLength": 64,
      "description": "端末ごとに一意。例: windows-<UUID>"
    },
    "createdAtUtc": {
      "$ref": "#/$defs/utcTimestamp"
    },
    "entityType": {
      "enum": [
        "book",
        "book_preference",
        "library_system",
        "library",
        "library_membership",
        "library_setting",
        "loan",
        "reading_record"
      ],
      "description": "版1に library_setting を足した一覧である。**版3を作らずに版2を書き換えた** — 規則が守っているのは「古い版を持つ端末が、同じ版番号の新しい封筒を読み違えないこと」であり、製品を配っていない今、守る対象の端末が存在しない。L4 で synced_file を落としたときと同じ判断である（docs/architecture/libraries-in-sqlite.md 2c）。配ってからでは取れない選択なので、本番 GUI より先に入れた。版差として残るのは任意項目 domainEventType だけである。"
    },
    "entityId": {
      "$ref": "#/$defs/uuid"
    },
    "operation": {
      "enum": ["upsert", "tombstone"]
    },
    "baseVersion": {
      "$ref": "#/$defs/version",
      "description": "編集開始時点で端末が認識していた版。新規作成は 0。"
    },
    "resultVersion": {
      "$ref": "#/$defs/version",
      "minimum": 1,
      "description": "更新後の版。常に baseVersion より大きい。この関係はJSON Schemaで表現できないため実装側で検査する。"
    },
    "payloadHash": {
      "type": "string",
      "pattern": "^sha256:[0-9a-f]{64}$",
      "description": "正準化した payload のSHA-256。正準化規則は docs/architecture/sqlite-drive-sync-protocol.md を正本とする。"
    },
    "resolvesEventIds": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/uuid"
      },
      "uniqueItems": true,
      "default": [],
      "description": "競合解決イベントが決着させた eventId の一覧。受信側はこれに自端末の未解決conflictを含む場合、版判定を迂回して適用する。空でも省略せず [] を書く。省略できると、封筒のバイト列が実装ごとに変わる。"
    },
    "domainEventType": {
      "$ref": "#/$defs/domainEventType"
    },
    "payload": {
      "type": "object",
      "description": "更新後の集約スナップショット。部分更新ではない。tombstone では最小限でよい。集約ごとの形は payload/<entityType>.schema.json が定める。この封筒スキーマでは拘束しない — entityType の enum は7集約すべてを許すが、payloadスキーマがあるのは実装済みの集約だけである。"
    }
  },
  "$defs": {
    "domainEventType": {
      "type": "string",
      "minLength": 1,
      "maxLength": 64,
      "pattern": "^[A-Za-z][A-Za-z0-9]*$",
      "description": "受信側でも同じ DomainEvent を書けるようにするための語彙（例 PatrolCompleted）。**同期層はこの値を解釈しない。** 語彙は bops の持ち物であり、封筒は運ぶだけである。ここに enum を書くと、業務イベントを増やすたびに封筒の版が上がる。値が無いときはキーを出さない — null を書くか省くかで正準化のバイト列が変わるため、規則を「値があるときだけ」の一本にする。"
    },
    "uuid": {
      "type": "string",
      "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    },
    "utcTimestamp": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
      "description": "RFC3339秒精度・Z終端のみ。オフセット表記を許さない。"
    },
    "localDate": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
      "description": "図書館のローカル暦日。payload 内の *_on 列が従う。集約ごとのpayloadスキーマを追加する際に参照する。"
    },
    "nullableLocalDate": {
      "anyOf": [{ "$ref": "#/$defs/localDate" }, { "type": "null" }],
      "description": "payload はスナップショットであり、空の項目は省略しても null で書いてもよい。"
    },
    "version": {
      "type": "integer",
      "minimum": 0,
      "maximum": 9007199254740991,
      "description": "上限は 2^53-1 とする。Dart の int は 64bit だが Web では double であり、2^53 を超えると値が変わる。上限を宣言しないと Python でだけ通る封筒ができる。"
    }
  }
}
''',
  'sync-event.schema.json': r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://frsw3.invalid/book-sync-model/schema/sync-event.schema.json",
  "title": "SyncEvent envelope v1",
  "description": "端末間で受け渡す不変イベントの封筒。schemaVersion はこの検証より先に読み、未対応であれば pending_events(reason='schema') に保持する。スキーマ検証の失敗として扱わない。",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schemaVersion",
    "eventId",
    "deviceId",
    "createdAtUtc",
    "entityType",
    "entityId",
    "operation",
    "baseVersion",
    "resultVersion",
    "payloadHash",
    "payload"
  ],
  "properties": {
    "schemaVersion": {
      "const": 1,
      "description": "この文書は版1の定義である。他の値は未対応として扱う。"
    },
    "eventId": {
      "$ref": "#/$defs/uuid"
    },
    "deviceId": {
      "type": "string",
      "minLength": 1,
      "maxLength": 64,
      "description": "端末ごとに一意。例: windows-<UUID>"
    },
    "createdAtUtc": {
      "$ref": "#/$defs/utcTimestamp"
    },
    "entityType": {
      "enum": [
        "book",
        "book_preference",
        "library_system",
        "library",
        "library_membership",
        "loan",
        "reading_record"
      ]
    },
    "entityId": {
      "$ref": "#/$defs/uuid"
    },
    "operation": {
      "enum": ["upsert", "tombstone"]
    },
    "baseVersion": {
      "$ref": "#/$defs/version",
      "description": "編集開始時点で端末が認識していた版。新規作成は 0。"
    },
    "resultVersion": {
      "$ref": "#/$defs/version",
      "minimum": 1,
      "description": "更新後の版。常に baseVersion より大きい。この関係はJSON Schemaで表現できないため実装側で検査する。"
    },
    "payloadHash": {
      "type": "string",
      "pattern": "^sha256:[0-9a-f]{64}$",
      "description": "正準化した payload のSHA-256。正準化規則は docs/architecture/sqlite-drive-sync-protocol.md を正本とする。"
    },
    "resolvesEventIds": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/uuid"
      },
      "uniqueItems": true,
      "default": [],
      "description": "競合解決イベントが決着させた eventId の一覧。受信側はこれに自端末の未解決conflictを含む場合、版判定を迂回して適用する。空でも省略せず [] を書く。省略できると、封筒のバイト列が実装ごとに変わる。"
    },
    "payload": {
      "type": "object",
      "description": "更新後の集約スナップショット。部分更新ではない。tombstone では最小限でよい。集約ごとの形は payload/<entityType>.schema.json が定める。この封筒スキーマでは拘束しない — entityType の enum は7集約すべてを許すが、payloadスキーマがあるのは実装済みの集約だけである。"
    }
  },
  "$defs": {
    "uuid": {
      "type": "string",
      "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    },
    "utcTimestamp": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
      "description": "RFC3339秒精度・Z終端のみ。オフセット表記を許さない。"
    },
    "localDate": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
      "description": "図書館のローカル暦日。payload 内の *_on 列が従う。集約ごとのpayloadスキーマを追加する際に参照する。"
    },
    "nullableLocalDate": {
      "anyOf": [{ "$ref": "#/$defs/localDate" }, { "type": "null" }],
      "description": "payload はスナップショットであり、空の項目は省略しても null で書いてもよい。"
    },
    "version": {
      "type": "integer",
      "minimum": 0,
      "maximum": 9007199254740991,
      "description": "上限は 2^53-1 とする。Dart の int は 64bit だが Web では double であり、2^53 を超えると値が変わる。上限を宣言しないと Python でだけ通る封筒ができる。"
    }
  }
}
''',
};
