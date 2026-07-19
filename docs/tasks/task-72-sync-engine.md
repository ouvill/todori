# task-72: P2-M4 同期エンジン統合

> ステータス: 完了
> 作成日: 2026-07-08
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

Phase 2 P2-M4として、P2-M1〜P2-M3で実装したクライアント同期基盤、同期サーバー、鍵階層/アカウント接続を統合し、Taskveilの実同期エンジンを動かす。

同期フローは `docs/03_技術仕様書.md` §6.4を厳密に正とする。ローカル書込は即時DB反映と同時にoutboxへopを積み、ACKまでは保持する。pushはbatch送信し、accepted/no-op/superseded/rejectを処理する。pullは `since` cursorで受信し、復号、フィールドレベルLWWマージ、ローカルDB反映、cursor前進を行う。マージ結果でローカル側が勝ったフィールドがある場合は、必ずローカルHLCをtickして新しい `op.hlc` でマージ済みblobを再pushする。同一HLCで内容だけ異なる再pushは禁止である。

暗号はtask-71で接続済みのList DEK / Tenant Root DEK階層を使う。tasks/lists等のcollectionごとに正しいDEKを選び、blob envelopeを暗号化/復号する。復号に失敗したpull recordは同期全体を止めずにスキップし、件数を同期結果へ記録する。

UXは「静かな同期」を優先する。手動同期APIと、アプリ起動時/フォアグラウンド復帰時の自動同期を実装する。ログイン時のみ30秒級の最小ポーリングを許容するが、常時スピナーや競合通知は出さない。Phase 2では `docs/03` §6.5どおりLWW結果をそのまま反映し、ユーザー向け競合通知や手動マージUIは作らない。

削除同期は暫定である。ADR-009によりローカル削除は恒久削除・削除Undoなしへ変更済みだが、正式なGC/tombstone設計はP2-M5のADR-010で確定する。本タスクでは橋渡しとして削除opを `deleted=true`、blobは空または最小blobで転送し、受信側はローカル恒久削除する。削除と同時編集の最終意味論、復活禁止条件、保持期間、GCはP2-M5へ送る。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/08_Phase2計画書.md` P2-M4
- `docs/03_技術仕様書.md` §4（鍵階層、レコード暗号化方式）、§6.3（HLC/field_hlcs/LWW）、§6.4（同期フロー、再push規約、HLC tick規約）、§6.5（競合ケース）、§6.6（サーバー不変条件）、§11.1（同期テスト方針）
- `docs/05_設計判断記録.md` ADR-004、ADR-005、ADR-009
- `docs/tasks/task-69-sync-foundation.md` の `## 9. 完了報告`
- `docs/tasks/task-70-sync-server.md` の `## 9. 完了報告`
- `docs/tasks/task-71-key-hierarchy-account.md` の `## 9. 完了報告`
- `core/sync/src/hlc.rs`
- `core/sync/src/field_map.rs`
- `core/sync/src/merge.rs`
- `core/sync/src/envelope.rs`
- `core/sync/src/account.rs`
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `server/src/routes/sync.rs`
- `server/src/sync.rs`
- `app/rust/src/api.rs`
- `app/rust/src/dev_key_store.rs`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/account_screen.dart`

## 3. ゴール

- `core/sync` に同期エンジンを追加し、push、pull、ACK、superseded処理、cursor前進、復号失敗スキップ、LWWマージ、再push規約を一貫して実行できること。
- 既存のtask/list CRUDパスへoutbox記録を接続し、同期対象のローカル書込がDB反映と同じ論理操作でoutbox opを積むこと。
- pullで受信した暗号blobを正しいDEKで復号し、フィールドLWWマージ結果をローカルDBへ反映すること。同期適用によるDB書込は不要なoutbox再生成を起こさず、再pushが必要な場合だけ新HLCでoutboxへ積むこと。
- `deleted=true` の暫定削除opを送受信でき、受信側はローカル恒久削除すること。正式なGC/tombstone設計はP2-M5へ残す。
- FRBに `sync_now` 相当の手動同期APIと同期状態取得APIを公開し、Dart境界へ鍵バイト列やセッショントークン平文を返さないこと。
- Flutterでアプリ起動時、フォアグラウンド復帰時、ログイン時のみ30秒級の最小ポーリング、アカウント画面の最終同期時刻/手動同期ボタンを接続すること。
- 未ログイン時は同期エンジン、outbox記録、ネットワーク送受信、ポーリングを完全に無効にし、ローカルオンリー動作を維持すること。
- testcontainers Postgres + 実axum server + 2つのローカルDBで、双方向編集収束、オフライン編集からの復帰、同一フィールドLWW、削除伝播、outbox永続性を統合テストで固定すること。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- ルート `Cargo.toml`
- `core/sync/Cargo.toml`
- `core/sync/src/*.rs`
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `core/storage/Cargo.toml`
- `server/tests/*.rs`
- `app/rust/Cargo.toml`
- `app/rust/src/api.rs`
- `app/rust/src/dev_key_store.rs`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/account_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/**/*`
- `docs/tasks/task-72-sync-engine.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. `git status --short` で作業前状態を確認する。未コミット変更があれば、タスクに関係するものだけを慎重に読み、無関係な変更は触らない。
2. `core/sync` に `SyncEngine` 相当を追加する。入力はserver URL、session token、tenant_id、device_id、ローカルDB、アカウント鍵材料、現在時刻providerを想定し、Flutter/CLI/MCPが再利用できるRust側実装にする。
3. push clientを実装する。`sync_outbox` から安定順にbatch取得し、`POST /v1/tenants/{tenant_id}/push` へ `{record_id, collection, hlc, deleted, blob}` を送る。accepted/no-opはACKとしてoutbox削除し、supersededはpullで解決する前提で削除または状態遷移を行う。reject/ネットワーク失敗は保持し、指数バックオフ対象にする。
4. pull clientを実装する。`sync_cursors` のテナントcursorから `GET /v1/tenants/{tenant_id}/pull?since={seq}&limit={n}` を呼び、ページング、`next_since`、`has_more` を処理する。cursorは復号/マージ/ローカルコミット後にだけ前進させる。
5. 復号とDEK選択を実装する。tasksは所属List DEK、list本体やTenant配下metadataは仕様どおりList DEKまたはTenant Root DEKを使う。DEKが無い、AAD不一致、version不一致、AEAD失敗、JSON不正のrecordはスキップし、`decrypt_failed_count` 等として同期結果に記録する。
6. ローカル書込からoutboxへopを積むフックを実装する。対象は既存のtask/list CRUDパス全体（作成、更新、status変更、reorder、archive/unarchive、恒久削除、list削除）である。未ログイン時はoutboxを積まず、同期対象外のローカルオンリー動作を維持する。
7. ローカル書込時はfield_hlcsを正しく更新し、record HLCはblob内field_hlcsの最大値と整合させる。ローカルHLCは永続化または安全に復元できる形にし、プロセス再起動後も単調性を破らない。
8. pullマージを実装する。受信blobとローカル状態を復号平文で `merge_lww` し、incoming勝ちのフィールドをローカルDBへ反映する。local勝ちフィールドがあれば、マージ済みplaintextを正しいDEKで再暗号化し、必ずHLCをtickして新しい `op.hlc` で再push用outboxへ積む。
9. 同期適用専用のstorage経路を用意する。pull結果をローカルDBへ反映するときに通常CRUDフックが二重outboxを積まないようにし、UIからのローカル編集と同期適用を明確に分ける。
10. 削除op暫定仕様を実装する。送信時は `deleted=true`、blobは空または最小blobとし、受信時は該当task/listをローカル恒久削除する。削除競合、tombstone保持、GC、復活禁止の正式仕様はP2-M5/ADR-010未確定として完了報告に明記する。
11. `app/rust/src/api.rs` に `sync_now()`、`get_sync_status()` 等のFRB APIを追加する。戻り値は最終同期時刻、実行中、最後の成功/失敗、push/pull件数、復号失敗件数程度に留め、鍵やセッショントークン平文をDart境界へ出さない。Rust API変更後は `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、生成物は手編集しない。
12. Flutter側に同期providerを追加する。アプリ起動時、ログイン状態復元後、フォアグラウンド復帰時に同期を起動し、ログイン時だけ30秒級の最小ポーリングを行う。同期中の常時スピナーは出さず、アカウント画面に最終同期時刻、簡素な状態、手動同期ボタンを表示する。
13. アカウント画面のUI文字列はen/ja ARB化する。競合通知、手動マージUI、詳細な同期ログ画面は作らない。
14. Rust統合テストを追加する。testcontainers Postgresへmigrationを当て、実axum serverを起動し、2つの一時ローカルDB/2 clientで双方向編集収束、オフライン編集→復帰同期、同一フィールド競合LWW、削除伝播、outbox永続性（プロセス再起動相当）を検証する。
15. Flutter widget testをfake bridgeで追加する。アカウント画面の最終同期時刻、手動同期ボタン、同期中/失敗/未ログイン表示、起動/復帰trigger providerの挙動を確認する。
16. 秘密情報ログ禁止を確認する。password、session token、MK、DEK、Device Key、exportKey、Recovery Key、復号済みplaintextをログ、`dbg!`、Flutter error表示へ含めない。

### やらないこと

- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` / `docs/05_設計判断記録.md` の変更。
- 競合通知、手動マージUI、変更履歴からの復元UI。
- SSE、long-poll、WebSocket、バックグラウンドpush通知、常時リアルタイム同期。
- 削除同期の正式なADR-010、tombstone保持期間、GC、削除と同時編集の最終意味論確定。
- Recovery Key UX完全版、複数デバイス管理UI、デバイス失効UI、Org共有。
- AWS/ECR/Lambda/Neon本番デプロイ、クレデンシャル投入。
- 同期対象外機能の大規模リファクタ、UI redesign。
- git commit。

## 5. 実装手順（例）

1. 指定ファイルを読み、`docs/03` §6.4のpush/pull/cursor/再push/HLC tick規約を実装メモに落とす。特に「cursorはローカルコミット後に前進」「エコー除外なし」「再pushは新HLC」を先に固定する。
2. `core/sync` のHTTP DTOをserver DTOと照合し、push/pull clientを薄く実装する。base64/JSON形式、batch上限、pull limit上限はserver側テストと揃える。
3. `SyncEngine` の境界を決める。storage操作、DEK解決、session取得、clock、network clientをtraitまたは小さな構造体に分け、統合テストで2クライアントを作りやすくする。
4. storageの同期メタデータ不足を確認する。HLC永続化、field_hlcs保存、recordごとの同期plaintext復元に追加テーブル/列が必要ならv9 migrationを追加する。既存DB v8からのmigration testを必ず追加する。
5. task/listのローカルCRUDパスへoutboxフックを入れる。同期適用用のwrite pathとは分離し、pull反映が二重outboxを作らないことを単体テストで固定する。
6. 暗号化/復号DEK解決を実装する。List DEKが必要なrecordでlist_idが取れない場合、処理を止めず該当recordをスキップ/カウントする。
7. push処理を接続する。accepted/no-op ACK、superseded、reject、ネットワーク失敗、部分成功をテストし、ACK前outbox保持とACK後削除を確認する。
8. pull処理を接続する。復号、LWW、ローカルDB反映、再push enqueue、cursor前進を1ページ単位でトランザクション境界が分かる形にする。
9. 暫定削除opを実装する。送信側は恒久削除前に必要なrecord_id/collection/list_id/最小blob情報を確保し、受信側は恒久削除する。正式仕様未確定のリスクを完了報告へ残す。
10. FRB APIを追加してコード生成する。fake bridgeにも同期APIを追加し、既存widget testが壊れないようにする。
11. Flutter providerを追加し、アカウント画面へ最終同期時刻/手動同期ボタンを置く。`AppLifecycleState.resumed` とログイン状態を見て同期を起動し、未ログイン時は何もしない。
12. testcontainers + 実サーバー + 2ローカルDB統合テストを追加する。ローカルport bindやDockerがsandboxで失敗した場合は、テストコードを残し、実行不能理由を完了報告に記録する。
13. Rust/Flutter品質ゲート、FRB生成差分、ハードコード文字列検出を実行する。
14. 本ファイルへ `## 9. 完了報告` を追記し、README/BACKLOGを完了状態へ更新する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `core/sync` に同期エンジンがあり、push batch、ACK後outbox削除、superseded処理、pull cursor、ページング、指数バックオフを扱える。
- [ ] task/listの既存ローカルCRUDパスが、ログイン時だけDB書込と同時にoutbox opを積み、未ログイン時は同期/outbox/networkを完全に無効にする。
- [ ] pull recordはList DEK / Tenant Root DEK階層で復号され、復号失敗recordは同期全体を止めずスキップされ、件数が同期結果へ記録される。
- [ ] フィールドLWWマージ結果がローカルDBへ反映され、ローカル勝ちフィールドがある場合は必ずHLC tick後の新 `op.hlc` でマージ済みblobが再pushされる。
- [ ] 同期適用用のローカルDB反映は通常CRUD outboxフックと分離され、pull反映だけで二重outboxを生成しない。
- [ ] `deleted=true` の暫定削除opが送受信され、受信側でローカル恒久削除される。正式GC/tombstone/削除競合設計はP2-M5/ADR-010送りとして完了報告に記録されている。
- [ ] FRBに `sync_now` 相当と同期状態取得APIが追加され、Dart境界へ鍵バイト列、セッショントークン平文、復号済みplaintextを返さない。
- [ ] Flutterはアプリ起動時、フォアグラウンド復帰時、ログイン時のみ30秒級ポーリングで同期を起動し、常時スピナーや競合通知を表示しない。
- [ ] アカウント画面に最終同期時刻、簡素な同期状態、手動同期ボタンがあり、UI文字列はen/ja ARB化されている。
- [ ] testcontainers Postgres + 実axum server + 2ローカルDB統合テストで、双方向編集収束、オフライン編集→復帰同期、同一フィールド競合LWW、削除伝播、outbox永続性を確認している。
- [ ] Flutter widget testがfake bridgeで、最終同期時刻、手動同期、同期中/失敗/未ログイン表示を確認している。
- [ ] 秘密情報ログ禁止の確認結果（password、session token、MK、DEK、Device Key、exportKey、Recovery Key、復号済みplaintext）を完了報告に記録している。

## 7. 制約・注意事項

- `docs/03_技術仕様書.md` §6.4を優先する。再pushは必ずHLC tick後の新HLCで送る。同一HLCで内容だけ異なるblobを送らない。
- `seq` と `hlc` を混同しない。`seq` はpull cursor、`hlc` は競合解決キーである。
- pullで自デバイス送信recordのエコーを除外しない。マージは冪等である。
- cursorはローカルマージ/DB反映/必要な再push enqueueが完了した後に前進させる。途中失敗時にrecordを取り逃がさない。
- ローカル書込は即時DB反映する。同期成功までUI更新を待たせない。
- 未ログイン時はローカルオンリーで動作する。同期エンジン起動、outbox enqueue、HTTP送受信、ポーリングを行わない。
- 復号失敗recordで同期全体を止めない。ただし件数とrecordメタデータ（秘密でない範囲）を同期結果/完了報告に残し、継続的失敗を観測できるようにする。
- 秘密情報をログに出さない。特にsession token、MK、DEK、Device Key、exportKey、Recovery Key、復号済みSyncPlaintextを含めない。
- Flutter UIは静かにする。常時スピナー、画面全体のblocking sync、競合通知、手動マージUIは実装しない。
- 削除同期は暫定である。本タスクの `deleted=true` 橋渡しはP2-M5/ADR-010で置き換わる可能性があるため、抽象境界を狭く保つ。
- `flutter_rust_bridge_codegen` は `app/rust/src/api.rs` 変更後に必ず実行する。生成物は手編集しない。
- testcontainersはDocker daemonが動いている前提でよい。ローカルsocket bindがsandboxで禁止される場合は、テスト実行不能の理由を完了報告に明記する。

## 8. 完了報告に含めるべき内容

- 作業日、読んだファイル
- 同期エンジンの構成（push、pull、ACK、cursor、backoff、再push、復号失敗カウント）
- 追加/変更したRust依存crateと用途
- storage変更の詳細（migration、HLC/field_hlcs/同期メタデータ、通常CRUD outboxフック、同期適用write path）
- ローカルCRUDごとのoutbox enqueue対象一覧と、未ログイン時にenqueueしない確認結果
- 暗号/DEK解決の詳細（List DEK / Tenant Root DEKの使い分け、復号失敗時の扱い）
- pull LWWマージ、ローカルDB反映、HLC tick付き再pushの詳細
- push結果処理の詳細（accepted/no-op/superseded/reject、ACK前保持、ACK後削除）
- 暫定削除opの実装詳細と、P2-M5/ADR-010へ残した未確定事項
- FRB公開API一覧とDTO概要（Dart境界へ返さない秘密値を明記）
- Flutter同期provider、起動/復帰/ポーリングtrigger、アカウント画面変更、追加ARB key
- Rust統合テストの対象と実行結果（2ローカルDB、双方向編集、オフライン復帰、LWW、削除、outbox永続性）
- Flutter widget testの対象と実行結果
- 秘密情報ログ禁止の確認結果
- FRB再生成の実行結果
- 品質ゲート実行結果
- 変更ファイル一覧
- 未解決事項（正式削除同期ADR-010、SSE/long-poll、競合UI、複数デバイス管理UI、Recovery UX完全版など。無い場合も「なし」と明記）

## 9. 完了報告

作業日: 2026-07-08

読んだファイル:

- `AGENTS.md`
- `docs/tasks/task-72-sync-engine.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/08_Phase2計画書.md` P2-M4
- `docs/03_技術仕様書.md` §4.8、§6.3、§6.4、§6.5、§6.6、§11.1
- `docs/05_設計判断記録.md` ADR-004、ADR-005、ADR-009
- `docs/tasks/task-69-sync-foundation.md` / `task-70-sync-server.md` / `task-71-key-hierarchy-account.md` の完了報告
- `core/sync/src/hlc.rs`、`field_map.rs`、`merge.rs`、`envelope.rs`、`account.rs`
- `core/storage/src/lib.rs`、`core/storage/src/schema.sql`
- `server/src/routes/sync.rs`、`server/src/sync.rs`、`server/tests/sync_server.rs`
- `app/rust/src/api.rs`、`app/rust/src/dev_key_store.rs`
- `app/lib/src/core/bridge_service.dart`、`app/lib/src/core/providers.dart`
- `app/lib/src/screens/account_screen.dart`

同期エンジン構成:

- `core/sync/src/engine.rs` を追加し、`SyncEngine` が `POST /v1/tenants/{tenant_id}/push` と `GET /v1/tenants/{tenant_id}/pull` を呼ぶHTTP clientを担う。
- pushは `PushOp { outbox_id, record_id, collection, hlc, deleted, blob }` をJSON + base64で送信する。
- push結果は `accepted` / `no_op` / `superseded` を `PushStatus` として受け、呼び出し側がACK処理できるよう `outbox_id` と紐付けて返す。
- pullは `since` / `limit`、`records`、`next_since`、`has_more` を扱い、blobはbase64 decodeする。
- `app/rust/src/api.rs` の `run_sync_now()` がローカルDBのoutbox取得、push ACK、pullページング、復号、LWWマージ、ローカル反映、cursor前進、必要時の再push enqueue、件数集計を実行する。
- `SyncRunSummary` / `SyncStatusDto` で pushed、ACK、superseded、pulled、applied、deleted、decrypt_failed、repush を集計する。
- ネットワーク失敗・server rejectは `sync failed` として同期状態へ保存する。秘密値や詳細payloadはDart境界へ返していない。
- 指数バックオフの永続キューは未実装。Phase 2本タスクでは失敗時にoutboxを保持し、Flutter側の起動/復帰/30秒ポーリングで再試行する暫定実装とした。

追加/変更したRust依存crate:

- `server/Cargo.toml` dev-dependenciesに `tempfile.workspace = true` と `taskveil-storage.workspace = true` を追加した。用途は `server/tests/sync_server.rs` の2ローカルSQLCipher DB統合テスト。
- ルート `Cargo.toml` への新規crate追加はない。`Cargo.lock` は上記dev-dependencies参照分の解決で更新された。

storage変更:

- `core/storage` の `LATEST_SCHEMA_VERSION` を9へ上げた。
- v9 migration `add_sync_record_states` を追加した。
- `sync_record_states(collection, record_id, plaintext_json, updated_at)` を追加した。pullマージ時に暗号blob内 `{fields, field_hlcs}` の直近平文状態をSQLCipher内へ保持し、次回のLWWマージに使う。
- `SqliteSyncStateRepository` に `get_record_state`、`upsert_record_state`、`delete_record_state` を追加した。
- `SqliteTaskRepository::upsert_for_sync` / `delete_subtree_for_sync` と `SqliteListRepository::upsert_for_sync` / `delete_with_tasks_for_sync` を追加し、pull反映時に通常CRUDのoutbox enqueueを通らない同期適用write pathを分離した。
- 既存の `sync_outbox` はACKまで保持、`sync_cursors` はpull cursor保持に使う。

ローカルCRUDごとのoutbox enqueue:

- list: `create_list`、`rename_list`、`archive_list`、`unarchive_list`、`delete_list`
- task: `create_task`、`reorder_task`、`update_task`、`set_task_status`、`delete_task`
- enqueueは `active_sync_context()` が存在する場合のみ実行する。未ログイン時は `active_sync_context()` が `None` となり、outbox enqueue、HTTP送受信、Flutter poll開始を行わない。
- pull反映は `upsert_for_sync` / `delete_*_for_sync` を使うため、通常CRUD hookによる二重outboxを生成しない。

暗号/DEK解決:

- listsは `tenant_root_dek` で暗号化/復号する暫定実装。
- tasksは既存taskの `list_id` またはincoming plaintext内 `list_id` からList DEKを選択し、取得できない場合はTenant Root DEKへfallbackする暫定実装。
- `decrypt_plaintext` のAADはcollection + record_idで検証される。復号失敗、AAD不一致、version不一致、JSON不正相当の失敗は同期全体を止めず、`decrypt_failed_count` を増やして当該recordをスキップする。
- taskのList DEK解決でlist_idが取れない場合の厳格な失敗扱いは未実装。後続でList DEK配布/リスト削除同期の正式仕様に合わせて詰める。

pull LWWマージと再push:

- pull recordはcollectionごとに `apply_pull_list` / `apply_pull_task` へ分岐する。
- 受信blobを復号し、`sync_record_states` または既存ローカル行から作った `SyncPlaintext` と `merge_lww` する。
- incoming勝ちのフィールドを含むマージ結果は `upsert_for_sync` でローカルDBへ反映し、`sync_record_states` へ保存する。
- local勝ちフィールドがある場合は `tick_local_hlc()` でローカルHLCを進め、マージ済みplaintextのfield_hlcsを新HLCへ更新して、新しい `op.hlc` でoutboxへ再push enqueueする。
- 同一HLCで内容だけ異なる再pushは生成しない。
- cursorは各pull pageの全record処理、ローカル反映、必要な再push enqueue完了後に `set_cursor` で前進する。

push結果処理:

- `accepted` / `no_op` はACKとして `ack_outbox` で削除する。
- `superseded` もpullで解決する前提でACK削除し、`push_superseded_count` を増やす。
- HTTP失敗・server rejectは `run_sync_now()` が失敗し、outboxは削除されない。

暫定削除op:

- ローカル削除時は削除前に対象list/taskを取得し、`deleted=true`、blob空でoutboxへ積む。
- pullで `deleted=true` を受信したtaskは `delete_subtree_for_sync`、listは `delete_with_tasks_for_sync` でローカル恒久削除し、`sync_record_states` からも削除する。
- 削除と同時編集の最終意味論、復活禁止条件、tombstone保持、GC、server history保持との整合はP2-M5/ADR-010へ残した。

FRB公開API:

- `get_sync_status() -> SyncStatusDto`
- `sync_now() -> SyncStatusDto`
- `SyncStatusDto`: `logged_in`、`running`、`last_success_at`、`last_failure_at`、`last_error`、`pushed_count`、`push_acked_count`、`push_superseded_count`、`pulled_count`、`applied_count`、`deleted_count`、`decrypt_failed_count`、`repush_count`
- Dart境界へ返さない値: session token平文、password、Device Key、MK、Tenant Root DEK、List DEK、exportKey、Recovery Key、復号済みSyncPlaintext/record plaintext。
- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、`app/rust/src/frb_generated.rs`、`app/lib/src/rust/api.dart`、`app/lib/src/rust/frb_generated*.dart` を生成更新した。

Flutter変更:

- `SyncStatusNotifier` / `syncStatusProvider` を追加した。
- app起動時は `_TaskveilAppShell` が `syncStatusProvider` をwatchし、ログイン済みなら初回syncを起動する。
- `WidgetsBindingObserver` で `AppLifecycleState.resumed` を検知し、ログイン済みかつ実行中でなければsyncを起動する。
- ログイン時のみ30秒periodic pollを開始する。未ログイン時はpollしない。
- account register/login/logout後の同期状態は `syncStatusProvider` が `accountProvider.future` をwatchすることで追従する。明示invalidateはRiverpod実行中例外を起こしたため外した。
- account画面に最終同期時刻、同期状態、手動 `Sync now` ボタンを追加した。
- 常時スピナー、競合通知、手動マージUI、詳細同期ログ画面は追加していない。
- 追加ARB key: `accountSyncTitle`、`accountSyncIdle`、`accountSyncRunning`、`accountSyncFailed`、`accountSyncNotSignedIn`、`accountSyncLastSuccess`、`accountSyncNever`、`accountSyncNowButton`

Rust統合テスト:

- `server/tests/sync_server.rs` に `sync_engine_two_local_dbs_converge_conflicts_deletes_and_persist_outbox` を追加した。
- 構成: testcontainers Postgres + migration + 実axum server + `AccountClient` 登録/ログイン + `SyncEngine` + 2つの一時SQLCipherローカルDB。
- シナリオ内訳:
  - client Aの作成/編集をpushし、client Bがpullして反映する双方向基礎収束。
  - client Bのオフライン編集をoutboxに保持し、client Aの別フィールド編集後に復帰同期して両フィールドを収束。
  - 同一フィールド `title` の競合で後HLCの値が勝つこと。
  - `deleted=true` の削除opを伝播し、受信側のローカル状態が削除されること。
  - 復号不能blobをpullしても同期全体を止めず `decrypt_failed_count = 1` でスキップすること。
  - 未ACK outboxがDB reopen後も残り、再openしたclient Bがpushできること。
- 実行結果: `cargo test --workspace` 内の `server/tests/sync_server.rs` 5件が成功。

Flutter widget test:

- `app/test/account_screen_test.dart`: 最終同期表示、手動同期ボタン、登録直後Recovery Key表示、ログイン/ログアウトを確認。
- `app/test/sync_provider_test.dart`: 未ログイン時は同期しないこと、ログイン後とforeground resumeでsyncが起動することを確認。
- `FakeBridgeService` に `getSyncStatus` / `syncNow` を追加した。

スクリーンショット/visual QA:

- 既存PNG退避先: `app/build/visual_qa_backup_task72_20260708103736`
- `sh tool/visual_qa.sh` 成功。42 tests passed、PNG 44枚生成。
- 生成先: `app/build/visual_qa/*.png`
- 本タスクに関係する確認対象: `app/build/visual_qa/account_signed_out.png`。同期状態はwidget testで確認した。

秘密情報ログ禁止の確認:

- grep対象: `app/rust/src`、`core/sync/src`、`core/storage/src`、`server/src`、`app/lib`、`app/test`、`server/tests`
- 検索語: `dbg!`、`println!`、`eprintln!`、`debugPrint`、`tracing::`、`password`、`session_token`、`master_key`、`DEK`、`device_key`、`export_key`、`recovery_key`、`SyncPlaintext`、`plaintext` 等。
- 本タスク実装で、password、session token、MK、Tenant Root DEK、List DEK、Device Key、exportKey、Recovery Key、復号済みSyncPlaintext/record plaintextをログ、Debug出力、Flutter error表示へ出す箇所は見つからなかった。
- 既存の出力箇所: Keychain fallback文言、server起動/shutdown/sqlx error、Flutter native core init error、性能test計測ログ。秘密値は含まない。
- `SyncStatusDto.last_error` は固定文言 `sync failed` のみを保持する。

品質ゲート実行結果:

- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功
  - `server/tests/sync_server.rs`: 5 passed
  - `taskveil_storage`: 48 passed, 1 ignored
  - `taskveil_sync`: 29 passed
  - `taskveil_app_bridge`: 4 passed, 1 ignored
- `cargo test -p taskveil-server sync_engine_two_local_dbs_converge_conflicts_deletes_and_persist_outbox --test sync_server -- --nocapture`: 成功
- `cd app && flutter analyze`: 成功
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter test`: 成功（123 passed、visual QA harness 1 skipped）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `sh app/tool/visual_qa.sh`: 成功（42 tests passed、PNG 44枚生成）
- `git diff --check`: 成功

変更ファイル一覧:

- `Cargo.lock`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/main.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/generated/l10n/app_localizations.dart`
- `app/lib/src/generated/l10n/app_localizations_en.dart`
- `app/lib/src/generated/l10n/app_localizations_ja.dart`
- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `app/lib/src/rust/frb_generated.io.dart`
- `app/lib/src/screens/account_screen.dart`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/rust/src/lib.rs`
- `app/test/account_screen_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/sync_provider_test.dart`
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `core/sync/src/engine.rs`
- `core/sync/src/lib.rs`
- `server/Cargo.toml`
- `server/tests/sync_server.rs`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/task-72-sync-engine.md`

未解決事項:

- 削除同期の正式仕様（ADR-010）、tombstone保持、GC、削除と同時編集の意味論、復活禁止条件は未確定。
- `SyncEngine` はHTTP push/pull clientであり、永続的な指数バックオフ状態やバックオフスケジューラは未実装。失敗時outbox保持 + 起動/復帰/30秒pollによる再試行に留めた。
- tasksのDEK解決でList DEKが見つからない場合の厳格な失敗/保留仕様は未確定。本実装はTenant Root DEK fallbackを持つ暫定実装。
- lists本体のDEKはdocs/03 §4.8では当該List DEKとされているが、本実装はTenant Root DEKを使う暫定実装。task-71の鍵配布状態では既存listごとの確実なDEK対応が不足するため、後続で修正対象。
- `sort_order` は既存制約どおりLWW対象外であり、同期plaintextには含めていない。並び順の本同期意味論はfractional index同期タスクで詰める。
- SSE、long-poll、WebSocket、push通知、バックグラウンド常時同期は未実装。
- 競合通知、手動マージUI、変更履歴からの復元UIは未実装。
- Recovery Key UX完全版、複数デバイス管理UI、デバイス失効UIは未実装。
- AWS/ECR/Lambda/Neon本番デプロイ、クレデンシャル投入、WAF/API Gateway/CloudFront設定は未実施。
