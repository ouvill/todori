# task-69: P2-M1 クライアント同期基盤

> ステータス: 完了（2026-07-08）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

Phase 2の最初の実装タスクとして、E2EE同期のクライアント側基盤を作る。対象は `core/sync` のHLC・フィールドHLCマップ・LWWマージ・blob暗号エンベロープと、`core/storage` の送信待ちoutboxである。

Todoriの同期は「サーバー最新状態方式 + クライアント再push」を採る。サーバーは暗号blobの中身を解釈せず、競合解決に必要な `{fields, field_hlcs}` は暗号境界の内側に置く。pullカーソルはHLCではなくサーバー採番 `seq` であり、HLCはフィールド単位LWWとpush冪等性のためだけに使う。

本タスクは暗号・同期の中核であり、`docs/03_技術仕様書.md` を唯一の真実源として実装する。仕様に未定義の詳細がある場合、ADRドラフトや仕様書改訂をこのタスク内で作らず、完了報告の「未解決事項」に具体的に記録する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/08_Phase2計画書.md` P2-M1
- `docs/03_技術仕様書.md` §4（鍵階層）、§5（保存時暗号化）、§6（同期プロトコル）、§11.1（Rustコアproptest方針）
- `docs/05_設計判断記録.md` ADR-004、ADR-005、ADR-007、ADR-009
- `core/sync/Cargo.toml`
- `core/sync/src/lib.rs`
- `core/sync/src/hlc.rs`
- `core/crypto/Cargo.toml`
- `core/crypto/src/aead.rs`
- `core/crypto/src/kdf.rs`
- `core/crypto/src/lib.rs`
- `core/domain/src/entities.rs`
- `core/domain/src/sort_order.rs`
- `core/storage/Cargo.toml`
- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- ルート `Cargo.toml`

## 3. ゴール

- `core/sync` のHLCを、物理時刻ミリ秒・論理カウンタ・device idからなる仕様準拠の時計へ拡張すること。
- `{fields, field_hlcs}` の平文構造をserdeで定義し、タスク/リストのフィールド単位HLCを保持できること。
- フィールド単位LWWマージを、決定的かつ可換に実装すること。
- `{fields, field_hlcs}` をDEKでXChaCha20-Poly1305暗号化するblobエンベロープを実装すること。
- `core/storage` にv8 migrationとしてoutboxと必要最小限の同期ローカルメタデータを追加し、enqueue/list/ack APIを提供すること。
- 複数レプリカ・任意順序適用・再pushを含むproperty-based testで、全デバイスが同一状態へ収束する性質を検証すること。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- ルート `Cargo.toml`
- `core/sync/Cargo.toml`
- `core/sync/src/lib.rs`
- `core/sync/src/hlc.rs`
- `core/sync/src/*.rs`
- `core/storage/Cargo.toml`
- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- `docs/tasks/task-69-sync-foundation.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. `core/sync` のHLCに、固定幅ソート可能エンコード、decode、受信HLCとのmerge、未来HLC検出用の比較補助を追加する。
2. HLCの単調性、時計後退耐性、encode/decode roundtrip、文字列順とHLC順の一致、一意性を単体テストで固める。
3. `{fields, field_hlcs}` をserde可能な平文構造として定義する。`fields` は暗号化対象フィールド値、`field_hlcs` は同じフィールド名をキーにしたHLCマップとする。
4. タスク/リストのフィールド単位LWWマージを実装する。`sort_order` はfractional indexで競合回避するためLWWマージ対象外にする。
5. レコードHLCはADR-005どおり「全フィールドHLCの最大値」から求める。
6. blob暗号エンベロープを実装する。平文 `{fields, field_hlcs}` をserde JSON化し、`core/crypto` 既存AEADでDEK暗号化する。AADには `record_id` と `collection` を含める。
7. エンベロープはバージョンバイト付きフォーマットにする。既存AEADが `nonce(24byte) || ciphertext` を返すため、外側形式は `version || nonce || ciphertext` のように明示する。
8. blobサイズ上限64KBを検証する。少なくとも最終的な暗号blobが64KBを超える場合はエラーにする。
9. `core/storage` の `LATEST_SCHEMA_VERSION` を8へ上げ、v8 migrationでoutboxテーブルを追加する。最低限 `record_id`, `collection`, `hlc`, `deleted`, `blob`, `created_at` を保持し、ACKまで削除しない。
10. P2-M1-04に合わせ、必要最小限のpull cursorローカル状態も追加する。ローカルDBはテナントごとに分離する前提なので、テナントID列を追加する場合は理由を完了報告へ記録する。
11. outboxのenqueue/list/ack APIをstorage層に追加し、ACK前保持、ACK後削除、再起動後保持をrepository testで確認する。
12. `proptest` 等で、複数デバイスが任意のフィールド編集列を行い、任意順序でpush/pullされ、必要に応じて再pushするシミュレーションを作る。最終的に全レプリカが同一状態へ収束することを検証する。
13. 新規Rust依存が必要な場合は必ずルート `Cargo.toml` の `[workspace.dependencies]` に集約し、各crateから `*.workspace = true` で参照する。
14. 完了報告に、新規依存、HLCエンコードの暫定詳細、docs/03で未定義だった事項を列挙する。

### やらないこと

- サーバー、ネットワークAPI、HTTP client、Postgres、Lambda、OPAQUEログインAPIの実装。
- Flutter UI、FRB公開API、Dart provider、画面、ARBの変更。
- P2-M3の鍵階層接続。DEKの実体生成・保存・ラップは行わず、テストでは固定32byteキーを使う。
- 削除同期の最終セマンティクス決定。`deleted` カラムと型は同期プロトコル形状として用意するが、ADR-009後の削除競合・tombstone/GC方針はP2-M5へ送る。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` / `docs/05_設計判断記録.md` の変更。
- `app/rust/src/api.rs` の変更とFRB再生成。
- git commit。

## 5. 実装手順（例）

1. `git status --short` で作業前状態を確認する。
2. 事前に読むべきファイルを読み、HLC、field_hlcs、再push、outbox、64KB上限、保存時暗号化の境界を確認する。
3. `core/sync` のモジュール構成を決める。例: `hlc.rs`, `field_map.rs`, `merge.rs`, `envelope.rs`。
4. HLCを先に完成させる。既存 `Hlc` 型を壊す場合は影響範囲を最小化し、テストで単調性とエンコード順を固定する。
5. `{fields, field_hlcs}` とLWWマージを実装する。`serde_json::Value` を使う場合も、フィールド名の扱いをテストで固定する。
6. `todori-crypto` の `encrypt` / `decrypt` を呼び出してblobエンベロープを作る。AAD改ざん、誤DEK、record_id/collection入れ替え、version不一致、サイズ超過をテストする。
7. storage v8 migrationを追加し、baseline schemaにも新規テーブルを反映する。
8. outbox repository APIとcursor APIを追加し、既存DB v7からv8へmigrationされることをテストする。
9. 収束性proptest用に、サーバー最新状態ストアと複数ローカルレプリカの小さなテストダブルを作る。サーバー実装ではなく、ADR-005のlatest-state + seq + 再push規約だけを検証する。
10. 削除操作は、最終意味論が未決のためproperty testの主対象から外すか、`deleted` blob形状のroundtripに留める。扱いは完了報告の未解決事項へ記録する。
11. 品質ゲートを実行する。
12. 本ファイルへ `## 9. 完了報告` を追記し、README/BACKLOGを完了状態へ更新する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] HLCが物理時刻ミリ秒・論理カウンタ・device idを持ち、単調性、時計後退耐性、受信HLC merge、encode/decode roundtrip、文字列順とHLC順の一致をテストで確認している。
- [ ] HLCの固定幅ソート可能エンコードが実装され、docs/03で未定義だった桁数・基数・device id正規化等の暫定詳細が完了報告の未解決事項に記録されている。
- [ ] `{fields, field_hlcs}` のserde可能な平文構造があり、タスク/リストのフィールド単位HLCを保持できる。
- [ ] フィールド単位LWWマージが決定的・可換で、異なるフィールド同時編集は両方残り、同一フィールド競合はHLCが後の値を採用する。
- [ ] `sort_order` がLWWマージ対象外であり、fractional indexによる競合回避の前提がテストまたはコード上の型/APIで明示されている。
- [ ] blob暗号エンベロープがバージョンバイト、AAD（record_id/collection）、DEK固定テストキー、64KB上限を扱い、正常roundtrip・改ざん・誤DEK・AAD入れ替え・version不一致・サイズ超過のテストがある。
- [ ] `core/storage` にv8 migrationでoutboxと必要最小限のpull cursorローカル状態が追加され、既存v7 DBからのmigration testが成功している。
- [ ] outbox enqueue/list/ack APIがあり、ACK前保持、ACK後削除、再起動後保持、HLC順またはcreated_at順の安定取得をrepository testで確認している。
- [ ] proptestで複数レプリカ・任意編集順・任意pull順・再pushシミュレーションに対する収束性を検証している。
- [ ] 新規依存がある場合はworkspace.dependencies規約に従い、追加crate名と用途を完了報告に列挙している。

## 7. 制約・注意事項

- `docs/03_技術仕様書.md` に厳密準拠する。実装中に仕様の未定義・矛盾を見つけても、仕様書やADRをこのタスクで改訂しない。
- サーバーが知り得る情報を増やさない。サーバー相当の平文メタデータはrecord_id、collection、HLC、seq、deleted、blobサイズ、時刻系メタデータの範囲に留める。
- `sync_records` にdevice_idカラムを持たないADR-005の方針を崩さない。device idはHLCのノードID成分に含める。
- `seq` をHLCで代用しない。HLCは競合解決、seqはpullカーソルであり、役割を分離する。
- `{fields, field_hlcs}` は暗号化前の平文構造だが、サーバーへ平文で出してはならない。必ずblob内に内包する。
- DEKの実体生成・鍵階層接続はP2-M3で行う。本タスクの暗号テストは固定32byteテストキーで行う。
- outbox内のblobはSQLCipher DB内に保存される。これはdocs/03 §5.2の設計どおりであり、冗長な二重暗号化ではない。
- 削除同期の最終意味論は未決である。`deleted` を実装上必要な型・保存カラムとして扱ってよいが、削除と同時編集の競合解決を本タスクで確定しない。
- `flutter_rust_bridge_codegen` は実行しない。Rust APIを `app/rust/src/api.rs` へ公開しない。
- 追加依存は最小限にする。`proptest` 等が必要な場合もworkspace.dependenciesへ集約する。

## 8. 完了報告に含めるべき内容

- 作業日、読んだファイル
- HLC実装の詳細（保持要素、merge規則、固定幅エンコード、未来HLC検出補助）
- `{fields, field_hlcs}` の構造、対象フィールド、`sort_order` の扱い
- LWWマージの決定性・可換性を確認したテスト
- blob暗号エンベロープのバージョン、AAD、64KB上限、DEKテスト方針
- storage v8 migrationの内容、outbox/cursor API、migration test結果
- proptestのモデル（レプリカ数、操作種類、任意順序、再push条件）と実行結果
- 変更ファイル一覧
- 新規依存crate一覧と用途（なければ「なし」）
- 品質ゲート実行結果
- docs/03で未定義だった詳細、削除同期などP2-M5以降へ送る未解決事項

## 9. 完了報告

作業日: 2026-07-08

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/08_Phase2計画書.md` P2-M1
- `docs/03_技術仕様書.md` §4、§5、§6、§11.1
- `docs/05_設計判断記録.md` ADR-004、ADR-005、ADR-007、ADR-009
- `core/sync/Cargo.toml`
- `core/sync/src/lib.rs`
- `core/sync/src/hlc.rs`
- `core/crypto/Cargo.toml`
- `core/crypto/src/aead.rs`
- `core/crypto/src/kdf.rs`
- `core/crypto/src/lib.rs`
- `core/domain/src/entities.rs`
- `core/domain/src/sort_order.rs`
- `core/storage/Cargo.toml`
- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- ルート `Cargo.toml`

実装結果:

- `core/sync` に `field_map.rs`、`merge.rs`、`envelope.rs` を追加した。
- HLCは `wall_ms: i64`、`counter: u32`、`device_id: String` を保持し、`now`、受信HLCとの `merge`、`encode`、`decode`、`exceeds_future_skew` を実装した。
- HLC固定幅エンコードは `01 || biased_wall_ms(20桁10進) || counter(10桁10進) || device_id UTF-8 bytes(64byte NUL padding hex)` とした。`biased_wall_ms` は `i64::MIN` を0へ寄せたu64値。
- HLCテストで単調性、時計後退耐性、受信merge、encode/decode roundtrip、文字列順とHLC順の一致、固定幅、一意性の前提となるdevice idタイブレーク、未来HLC検出補助を確認した。
- `{fields, field_hlcs}` は `SyncPlaintext { fields: BTreeMap<String, serde_json::Value>, field_hlcs: BTreeMap<String, Hlc> }` とした。両mapのキー一致を検証する。
- タスクLWW対象フィールドは `list_id`、`parent_task_id`、`title`、`note`、`status`、`priority`、`due_at`、`scheduled_at`、`estimated_minutes`、`completed_at`、`closed_reason`、`deleted_at`、`assignee`、`created_at`、`updated_at` とした。
- リストLWW対象フィールドは `name`、`color`、`icon`、`org_id`、`is_default`、`archived_at`、`created_at`、`updated_at` とした。
- `sort_order` は `SyncPlaintext` の検証で拒否し、LWW対象外であることをテストした。
- レコードHLCは `field_hlcs` の最大値から求める `record_hlc()` とした。
- フィールドLWWマージはフィールドごとにHLC後勝ち。同一HLCで値が異なる場合はJSON文字列表現で決定的にタイブレークする。
- LWWテストで、異なるフィールドの同時編集が両方残ること、同一フィールド競合が後HLCを採用すること、フィールド値として可換に収束することを確認した。
- blob暗号エンベロープはversion byte `1` + 既存AEADの `nonce(24byte) || ciphertext` とした。
- envelope AADは `todori-sync-envelope/v1\ncollection:{collection}\nrecord_id:{record_id}` とし、`collection` と `record_id` を含めた。
- envelopeは固定32byteテストDEKで、正常roundtrip、誤DEK、AADのcollection差し替え、record_id差し替え、改ざん、version不一致、復号時64KB超過、暗号化後64KB超過をテストした。
- `core/storage` の `LATEST_SCHEMA_VERSION` を8へ上げ、v8 migration `add_sync_outbox_and_cursors` を追加した。
- `sync_outbox` は `id`、`record_id`、`collection`、`hlc`、`deleted`、`blob`、`created_at` を保持し、`created_at, id` indexを追加した。
- `sync_cursors` は `name`、`seq`、`updated_at` を保持する。ローカルDBはテナントごとに分離する前提のためtenant_id列は追加しなかった。
- `SyncStateRepository` / `SqliteSyncStateRepository` に `enqueue_outbox`、`list_outbox`、`ack_outbox`、`get_cursor`、`set_cursor` を追加した。
- storage testでv7→v8 migration、ACK前保持、ACK後削除、再起動後保持、`created_at, id` 順の安定取得、pull cursor前進を確認した。

proptest:

- `core/sync` に `replicas_converge_after_arbitrary_edits_pull_order_and_repush` を追加した。
- 実行ケース数: 64ケース（`Config::with_cases(64)`）。
- モデル: 3レプリカ、1レコード、対象フィールド `title` / `note` / `priority` / `status`。
- 操作: 任意デバイスによる1〜31件のフィールド編集、任意物理時刻、任意pull順1〜47件。
- 再push条件: `merge_lww` の結果、pullしたserver状態よりローカルが勝つフィールドがある場合。
- 検証内容: 任意編集順・任意pull順・再pushループ後、全レプリカとserver test doubleの `SyncPlaintext` が一致すること。

変更ファイル一覧:

- `Cargo.lock`
- `Cargo.toml`
- `core/sync/Cargo.toml`
- `core/sync/src/lib.rs`
- `core/sync/src/hlc.rs`
- `core/sync/src/field_map.rs`
- `core/sync/src/merge.rs`
- `core/sync/src/envelope.rs`
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `docs/tasks/task-69-sync-foundation.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

新規依存crate:

- `proptest`: `core/sync` の収束性property-based test用。

検証結果:

- `cargo test -p todori-sync`: 成功（25 passed、proptest 64ケース）。
- `cargo test -p todori-storage`: 成功（48 passed、1 ignored）。
- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（`todori-storage` task-67性能test ignored 1件、`todori_app_bridge` real Keychain test ignored 1件）。
- `cd app && flutter analyze`: 成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test`: 成功（116 passed、visual QA harness 1 skipped）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git diff --check`: 成功。

未解決事項:

- docs/03はHLC固定幅エンコードの桁数・基数・version prefix・device id正規化方式を未定義である。本タスクでは上記の暫定形式を採用した。
- docs/03はdevice idの最大長・文字種・生成元を未定義である。本タスクでは1〜64byteのprintable ASCIIを受け付ける暫定実装とした。
- docs/03は削除同期の最終意味論を同期導入時再設計としている。本タスクでは `deleted` outboxカラムと暗号対象フィールド形状のみを用意し、削除と同時編集の競合解決は実装していない。
- ADR-005/§6.4の「record HLC=全フィールドHLCの最大値」と「serverは `incoming.hlc > stored.hlc` の場合だけ採用」の組み合わせでは、server上の最大HLCフィールドとは別に、より低いHLCのローカル勝ちフィールドを含むmerge済みblobを再pushする場合、record HLCがserver stored HLCと同値になり得る。本タスクのproptestはmerge-awareなlatest-state test doubleで収束性を検証したが、E2EE serverが同一record HLC・異なるblobの再pushをどう扱うかは未定義である。
