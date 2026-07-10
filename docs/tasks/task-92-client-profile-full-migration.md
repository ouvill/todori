# task-92: ClientProfile全面移設

> ステータス: 完了（ClientProfile全面移設・zero-exception境界・独立検証合格）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

task-91はSQLite sync adapterを`todori-client`へ移し、frontend境界のCI guardを追加した。一方、`app/rust/src/api.rs`と`support.rs`にはprofile open、Device Key / SQLCipher初期化、account/session/local crypto runtime、CRUD/query/settings/reminder、sync coordinatorが残る。この2ファイルをlegacy exceptionとして残したままFuzzy-scanを実装すると、Flutter bridgeとCLI/MCPの挙動差、同期責務の逆流、transaction境界の重複が続く。

2026-07-10のプロダクトオーナー指示により、未リリースであることを前提に内部の破壊的変更を許可し、互換shimや二重実装を残さず目標architectureへ全面移設する。本task完了後の`app/rust`はFRB公開関数、process内`ClientProfile` handle、typed input/DTO変換だけとする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/03_技術仕様書.md` §2、§4.3、§6、§8
- `docs/05_設計判断記録.md` ADR-011〜ADR-015
- `docs/dev/client-profile-architecture.md`
- `docs/tasks/task-75-core-extraction-refactor.md`
- `docs/tasks/task-81-cli-shared-profile-architecture.md`
- `docs/tasks/task-84-local-crypto-context.md`
- `docs/tasks/task-85-transactional-crud-migration.md`
- `docs/tasks/task-90-offline-list-key-bundle-queue.md`
- `docs/tasks/task-91-client-profile-boundary.md`
- `core/client/src/`
- `app/rust/src/{api,support,sync_store}.rs`
- `app/rust/Cargo.toml`
- `cli/`、`mcp-server/`

## 3. ゴール

- frontend-neutralな`ClientProfile`を`todori-client`へ実装し、profile openからCRUD、account、syncまでの唯一の高水準入口にする。
- `app/rust`をFRB公開関数、process内profile handle、入力/DTO変換だけへ縮小する。
- Flutter bridgeからcrypto/domain/storage/sync/zeroizeへの直接依存を除去し、Tokioは既存同期FRB署名用の`profile_handle` executorだけに限定する。
- anonymous / account-boundのapplication serviceを1つのprofile APIへ統合し、frontendへDB key、MK、tenant、repository、`LocalMutationContext`、clockを渡さない。
- 既知のdelete + outbox非atomicと同一tenant再login時initial-backfill cursor削除を、設計に沿う挙動へ修正する。
- CLI/MCPが同じClientProfile公開APIをcompile時に利用でき、Fuzzy-scan実装時にFlutter bridge変更が不要な状態にする。

## 4. スコープ

### やること

- `ClientProfile`、`ProfileOptions`、frontend-neutral input/output/error、account/session/sync status型を追加する。
- Device Key取得、DB key導出、SQLCipher open/migration/default Inbox、profile path/state所有をclientへ移す。
- account register/login/logout、session restore、local crypto restore/refresh、pending local key reconciliationをclientへ移す。
- sync status/run、preflight、bundle upload、initial backfill、push/pull coordinatorをclientへ移す。
- list/task CRUD、query、count、undo、settings、reminderをprofile methodへ移す。
- anonymous/account-bound mutationをprofile内で分岐し、同期対象mutationのdomain/state/HLC/outbox/key queueを必要な単一transactionへ統合する。
- delete task/listのdomain deleteとtombstone enqueueをatomicにする。現行aggregate削除scope/epoch外の意味論は増やさない。
- 同一tenant再loginでinitial-backfill cursorを削除しない。異なるtenant/userはprofile identity mismatchで拒否し、同じprofile内でcursorをresetしない。
- bridge DTO mapperと現行FRB署名を維持しつつ、`support.rs` / `sync_store.rs`とcompat aliasを削除する。
- app manifestのworkspace内依存を`todori-client`だけにし、boundary checkからlegacy例外/count baselineを削除する。
- CLI/MCPへClientProfile APIのcompile contractを置き、architecture/ADR/技術仕様を最終状態へ更新する。

### やらないこと

- Fuzzy-scan full resync / GC horizon本体。
- sync wire protocol、暗号blob、server schema、local DB schemaの互換目的変更。
- Windows DPAPI / Linux Secret Service、multiprocess sync leaseの完成。
- Flutter UI・文言・provider設計の変更。
- List DEK rotation、sharing、aggregate削除scope/epoch。
- 旧internal API、旧module layout、開発データとの互換shim。

## 5. 実装手順

1. profile/account/sync、CRUD/query、bridge/FRBの契約を独立監査し、公開型と依存順を確定する。
2. `ClientProfile`のstate、open、account/session/local crypto、sync coordinatorを実装する。
3. CRUD/query/settings/reminderをprofile methodへ統合し、atomic deleteとrelogin cursor testを追加する。
4. bridgeをprofile呼出とDTO mapperへ置換し、下位crate依存とlegacy moduleを削除する。
5. CLI/MCP compile contract、boundary check、architecture文書を最終形へ更新する。
6. FRB regenerate/diff、task-84〜task-91回帰、全品質ゲートを実行する。
7. 実装担当外のverifierが統合HEADを独立検証し、不合格なら修正・再検証する。

## 6. 受け入れ基準

- [x] `ClientProfile`がprofile open、account/session、CRUD/query/settings/reminder、syncの高水準APIを持つ。
- [x] frontendからDB key、Device Key、MK、List DEK、tenant ID、repository、sync store、`LocalMutationContext`、`now_ms`を渡さない。
- [x] `app/rust`非生成sourceに`todori_(crypto|domain|storage|sync)`、`open_encrypted`、`Sqlite*`、`AccountClient`、`LocalSyncStore`、`LocalMutationContext`が0件。
- [x] `app/rust/Cargo.toml`のTodori workspace内依存が`todori-client`だけで、`support.rs` / `sync_store.rs`が削除される。
- [x] 現行FRB公開関数の名前・引数・戻り値とDart APIが維持される。
- [x] anonymous、account-bound online、logout後offline、account-bound key unavailableのoperation matrixがclient testで固定される。
- [x] delete task/listのdomain更新と同期tombstone enqueueがatomicで、failure injection時に部分commitしない。
- [x] 同一tenant再loginはinitial-backfill cursorを保持する。異なるtenant/userはprofile identity mismatchで拒否するためcursorをresetしない。
- [x] logout後offline key保持、pending bundle reconciliation、preflight→bundle→backfill→push→pull順序が継続する。
- [x] CLI/MCPが`todori-client`以外の下位crateへ依存せずClientProfile APIをcompile時に参照する。
- [x] legacy exceptionなしのboundary check、FRB生成物check、全品質ゲートが成功する。
- [x] task-84〜task-91のsecurity/correctness回帰と2-client production gateが成功する。
- [x] 独立verifierがP1/P2なしと判定する。

## 7. 制約・注意事項

- `todori-client`はFlutter、Dart、FRB、clap、MCP transportへ依存しない。
- network APIはclient側でasyncを正本とし、frontend adapterがruntime/blocking方法を選ぶ。既存FRB同期署名維持のための薄いexecutorはbridgeに残してよい。
- secretを`Debug`、error、log、DTOへ露出しない。key所有型はzeroize/drop境界を維持する。
- `ClientProfile`は同一processで同一pathの再openを安全に扱い、異なるpathとのglobal handle競合を明示errorにする。
- 破壊的internal変更は許可するが、暗号/wire/schemaを無関係に変えない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md`とprivate repoは変更しない。

## 8. 完了報告に含めるべき内容

- 移設前後のファイル/行数、module/manifest依存。
- `ClientProfile`公開API、state所有、async/error/secret境界。
- CRUD operation matrix、atomic delete、relogin cursor修正のtest結果。
- bridge/FRB差分とCLI/MCP compile contract。
- boundary check、task-84〜91回帰、全品質ゲート、独立検証。
- Fuzzy-scan着手可能性と本task外の未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-10
- 結果: `ClientProfile`をprofile DB、zeroizing DB key、account/session/local crypto、operation gate、sync status/coordinator、全application serviceの唯一の所有者として実装した。公開面はtyped UUID/TaskStatusとclient-owned viewで、frontendへ鍵、tenant、repository、sync context、clockを公開しない。
- Account / sync: register/login/logout/session restore、remote/pending List DEK reconciliation、initial backfill、preflight→bundle upload→backfill→push→pullをclientへ移した。network APIはasyncを正本とし、await中にstd mutex guardを保持せず、全network/local write共通のAtomicBool + RAII operation gateで競合/cancelを処理する。network guard中のlocal mutationはBusy、guard drop後は再開するtestを追加した。logoutはsession tokenだけを削除してoffline cryptoを保持し、同一profile再認証でinitial-backfill cursorを削除しないtestを追加した。`session_restored`をruntime stateで明示し、確定済みAnonymous/Readyのlocal mutationが毎回OS secret storeへ依存しないようにした。
- CRUD / query: list/task CRUD、search/home/count、undo、settings、reminderをprofile methodへ統合した。Anonymousはlocal transactionのみ、Readyはdomain/HLC/state/outboxをatomic確定、Unavailableはwrite前にfail closedする。priority 0..=3もclient入口で検証する。
- Delete correctness: `SqliteWriteTx`へsubtree/list snapshotとtransactional delete APIを追加した。task subtreeは既知の全task、list deleteは配下全task+listを同一transactionでtombstone化してから物理削除し、途中のlist tombstone failureでdomain/HLC/outboxが全rollbackするtestを追加した。
- Bridge: handwritten Rustを`api.rs` 606行、`profile_handle.rs`、`lib.rs`の薄いadapterへ縮小した（移設前`api.rs` 1,148 + `support.rs` 1,243 + `sync_store.rs` 2 = 2,393行）。`support.rs` / `sync_store.rs`を削除し、appのTodori workspace内依存を`todori-client`だけにした。既存同期FRB署名用Tokio executorは`profile_handle.rs`だけに限定する。39公開関数の正規化signature hashは移設前後で一致し、8 DTOとDart call surfaceを維持した。
- Public API: 通常の`todori-client`公開面を`ClientProfile`、frontend-neutral model/domain view、`ClientError`へ限定した。低水準Client/local crypto/SQLite sync storeは`test-support` featureへ隔離し、server integration testだけが明示的に有効化する。root import不可をcompile-fail doctestで固定した。
- Boundary: CI checkをlegacy exceptionなしへ更新し、下位crate/source参照0、manifest exact allowlist、dependency alias迂回、legacy module再作成、OnceLockの`profile_handle.rs`外配置を拒否する。negative fixture testでlower source、CLI lower dependency、hidden app alias、legacy source、bare `core`を個別注入し、すべて非0終了を確認する。
- FRB / Flutter: FRB 2.12.0で再生成し、公開Dart APIはdoc comment/ignored-private-function一覧以外不変。Flutter UI/provider変更なし。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`（最終追加後client 33 + compile-fail doctest 2、storage 72成功/1 ignored、sync 50、server sync v2 9、bridge 2）、bridge release build、`flutter analyze`、`flutter test`（130 passed / visual QA harness 1 skipped）、hardcoded-string check、client boundary checkとnegative fixture、`git diff --check`が成功した。
- Commit: `310e818`。
- 未解決: multiprocess DB-backed sync lease、Windows DPAPI / Linux Secret Service、Fuzzy-scan/GC horizon、aggregate削除scope/epochは別task。現在の境界のままFuzzy-scanへ着手可能。

> 追補（task-93）: 互換性優先で残した同期FRB signatureとbridge内Tokio executorは不要と判断し、4つのnetwork FRB関数をasyncへ統一して削除した。Dart側の`Future` APIは不変。

### 独立検証

- 判定: 合格（P1 / P2 / P3なし）
- 根拠: 39公開関数/8 DTO、下位crate参照0、async + Send network API、test-support隔離、Anonymous/online Ready/logout後offline Ready/Unavailable matrix、共通RAII operation gate、task/list delete atomic rollback、cursor保持/identity mismatch、pending key/2-client順序、CLI/MCP contract、boundary negative fixturesを確認した。`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`（client 33 + doctest 2、storage 72 + ignored 1、sync 50、server auth 1/sync 9、bridge 2）、bridge release build、`flutter analyze`、`flutter test`（130 passed / visual QA harness 1 skipped）、hardcoded-string check、boundary check/negative fixture、`git diff --check`を独立再実行して成功した。検証中に発見したsession restore、async canonical API、public surface、account/register race、Flutter Future matcherの問題は修正後に再検証した。
- 検証者: 独立verifier agent
