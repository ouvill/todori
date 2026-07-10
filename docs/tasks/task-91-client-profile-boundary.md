# task-91: frontend共通client境界の基礎固定

> ステータス: 完了（共通sync adapter・依存境界・CI guard実装、独立検証合格）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

ADR-011はFlutter desktop、CLI、将来のMCP serverが共通application service crate `todori-client`を呼ぶ構成を採用した。しかし`app/rust`にはprocess-global profile/account/sync state、Device KeyとSQLCipher初期化、SQLite sync adapter、anonymous CRUD、query/settings/reminderが残っている。このままFuzzy-scanを実装すると、SQLite mark-and-sweep等がFlutter bridgeへ増えるおそれがある。

まず本taskで、独立して安全に移せるSQLite sync adapterを`core/client`へ移し、server testのFlutter bridge逆依存を除去する。同時にCLI/MCPの依存入口、crate命名規則、CI境界checkを固定する。残る`api.rs` / `support.rs`は既知の移行対象として隔離し、次taskで`ClientProfile`へ移す。Fuzzy-scanはその完了後に着手する。

`core/`はworkspace内の配置ディレクトリでありcrate名ではない。実packageは`todori-client`等、Rust crate名は`todori_client`等で、Rust標準の`::core`との競合はない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/03_技術仕様書.md` §2、§6、§8
- `docs/05_設計判断記録.md` ADR-011〜ADR-014
- `docs/tasks/task-75-core-extraction-refactor.md`
- `docs/tasks/task-81-cli-shared-profile-architecture.md`
- `docs/tasks/task-90-offline-list-key-bundle-queue.md`
- `core/client/src/`
- `app/rust/src/{api,support,sync_store}.rs`
- `cli/src/main.rs`
- `mcp-server/src/main.rs`
- `server/tests/sync_v2.rs`

## 3. ゴール

- SQLite sync adapterをFlutter bridgeから`todori-client`へ移し、Fuzzy-scanのSQLite実装先を共通clientへ固定する。
- server integration testからFlutter bridgeへの逆依存をなくす。
- CLI/MCPのTodori workspace内依存入口を`todori-client`へ統一する。
- crate命名とfrontend依存境界を文書および機械的checkで固定し、既知のbridge負債以外へ下位実装が増えることを防ぐ。
- 残る`ClientProfile`移設をFuzzy-scanより前の最優先候補として明示する。

## 4. スコープ

### やること

- `BridgeSyncStore`実装を`SqliteSyncStore`として`core/client`へ移す。
- server integration testを共通client型へ切り替え、`todori_app_bridge` dev-dependencyを除去する。
- app側の既存support参照は、実装を持たない一時compat aliasだけに縮小する。
- CLI/MCPのdomain/storage直接依存を`todori-client`へ置き換える。
- architecture boundary check、技術仕様、ADR-011、AGENTS、architecture文書を更新する。
- bare `core` package/lib/dependency aliasを禁止し、package `todori-<role>` / crate `todori_<role>`を規約化する。
- `api.rs` / `support.rs`だけを期限付きlegacy exceptionとし、その他のbridge sourceへ下位実装を追加できないCI checkを入れる。

### やらないこと

- `api.rs` / `support.rs`の`ClientProfile`への全面移設。次の最優先taskで行う。
- Fuzzy-scan full resync / GC horizonそのものの実装。
- sync wire protocol、暗号blob、DB schema、server schemaの変更。
- FRB公開関数、生成Dart API、Flutter UIの変更。
- Windows DPAPI、Linux Secret Service、DB-backed multiprocess sync leaseの完成。

## 5. 実装手順

1. current dependency、public API、runtime state、repository access、crate名を監査する。
2. SQLite sync adapterを共通clientへ移し、server testを切り替える。
3. CLI/MCP manifestを共通client入口へ切り替える。
4. architecture/命名規則と段階移行境界を文書化する。
5. manifest/source boundary checkをCIへ追加する。
6. workspace/Flutter品質ゲートを確認し、独立verifierが統合HEADを検証する。

## 6. 受け入れ基準

- [x] `app/rust/src/sync_store.rs`が実装を持たず、`SqliteSyncStore`の実体が`core/client`にある。
- [x] server integration testの`todori_app_bridge` dev-dependencyがなくなり、共通clientの`SqliteSyncStore`を利用する。
- [x] CLI/MCPがdomain/storage/sync/cryptoへ直接依存せず、`todori-client`を通常依存に持つ。
- [x] `api.rs` / `support.rs`以外のbridge非生成sourceへ下位crate import、SQLCipher repository、sync coordinatorを追加するとboundary checkが失敗する。
- [x] FRB公開API、生成Dart API、DB schema、wire protocol、暗号blob、UI文字列に変更がない。
- [x] task-84〜task-90のtransaction、key queue、sync ordering、2-client復号testが継続成功する。
- [x] `core/`がディレクトリであり、bare `core` crate/aliasを作らない命名規則と最終frontend境界が文書化される。
- [x] `ClientProfile`全面移設がFuzzy-scanより前のNextに置かれる。
- [x] architecture boundary checkと全品質ゲートが成功する。
- [x] 独立verifierがP1/P2なしと判定する。

## 7. 制約・注意事項

- SQLite adapterの移設は型名と所有crateだけを変え、同期挙動、transaction、errorを変更しない。
- `api.rs` / `support.rs`のlegacy exceptionへ新しい責務を追加しない。変更が必要なら先に`core/client`へ実装する。
- DB key、Device Key、MK、List DEK、session tokenをDebug、error、log、DTOへ露出しない。
- `[package] name = "core"`、`[lib] name = "core"`、dependency alias `core = {...}`、曖昧なumbrella `todori-core` crateを追加しない。
- `todori_app_bridge`はCargo package / lib target / FRB stem / pod名の固定契約として例外的にunderscore名を維持する。
- public/private境界を守り、private repoは変更しない。

## 8. 完了報告に含めるべき内容

- 移設前後の行数、manifest依存、source boundary check結果。
- SQLite sync adapterとserver integration testの依存変更。
- CLI/MCPの依存入口。
- legacy exceptionと次の`ClientProfile`移設範囲。
- crate命名規則とFuzzy-scanの実装境界。
- FRB差分、全品質ゲート、独立検証、未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-10
- 結果: `app/rust/src/sync_store.rs`にあったSQLite同期adapter 694行を、型名だけ`SqliteSyncStore` / `SqliteSyncWriteTx`へ変更して`core/client/src/sqlite_sync_store.rs`へ移した。app側は既存`support.rs`を壊さない2行の一時compat re-exportだけとなり、実装の重複はない。旧HEADを型名置換した内容と新ファイルの`diff`は0だった。
- Server依存: `server/tests/sync_v2.rs`は`todori_client::SqliteSyncStore`を使用し、`server/Cargo.toml`と`Cargo.lock`から`todori_app_bridge` dev-dependencyを削除した。real Axum HTTP + Docker/Postgresを通るsync v2 9件は継続成功した。
- CLI / MCP: `todori-cli`と`todori-mcp-server`のdomain/storage直接依存を外し、通常依存を`todori-client`へ統一した。両binaryはまだ機能stubであり、実profile openは後続taskとした。
- 境界固定: `app/tool/check_client_boundaries.sh`をCIと共通品質ゲートへ追加した。CLI/MCPの`todori-client`以外のTodori crate依存、`api.rs` / `support.rs`以外のbridge sourceにおける下位import/SQLCipher/sync実装、legacy 2ファイルの下位参照数が現状94件から増える変更、sync store compat aliasの肥大化、bare `core` package/lib/dependency aliasを検出する。
- 命名: `core/`はディレクトリ、Cargo packageは`todori-<role>`、Rust crateは`todori_<role>`と文書化した。`cargo metadata`上もbare `core` targetは存在しない。`todori_app_bridge`はCargo / pod / FRB stem契約の例外として維持する。
- Architecture: `docs/dev/client-profile-architecture.md`へ目標依存、層別責務、Fuzzy-scanの配置、段階移行を記録した。`STATUS.md`では`ClientProfile`全面移設をFuzzy-scanより前のNext 1へ置き、押し出したSQLCipher cross-build CIを`BACKLOG.md`へ移した。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`、bridge release build、`flutter analyze`、`flutter test`（130 passed / visual QA harness 1 skipped）、hardcoded-string check、client boundary check、FRB生成物diff check、`git diff --check`が成功した。通常sandboxではDocker socketとFlutter SDK cacheが権限制約で失敗したため、承認付き実行で再確認した。
- Commit: `5b91daf`。
- 未解決: `app/rust/src/api.rs` 1,148行と`support.rs` 1,243行にはprofile open、account/session、CRUD/query、settings/reminder、sync coordinatorと下位crate直接依存が残る。次taskでfrontend-neutralな`ClientProfile`へ移し、legacy exceptionとapp manifestのcrypto/domain/storage/sync依存を0にする。監査で見つかったdelete + outboxの別transactionと同一tenant再login時のinitial-backfill cursor削除も、そのtaskで挙動testとともに解消する。Fuzzy-scanはその後に実装する。

### 独立検証

- 判定: 合格（P1 / P2 / P3なし）
- 根拠: 旧bridge実装と新`SqliteSyncStore`を型名正規化してdiff 0、serverからapp bridge依存なし、CLI/MCPの下位crate直接依存なし、FRB/schema/wire/crypto/UI差分なしを確認した。boundary checkへ禁止source import、CLIの`todori-storage`依存、bare `core`名、sync store再肥大化を一時fixtureとして個別注入し、すべて期待どおり非0終了、復元後に成功した。`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`、bridge release build、`flutter analyze`、`flutter test`（130 passed / visual QA harness 1 skipped）、hardcoded-string check、client boundary check、`git diff --check`を独立再実行して成功した。秘密情報露出とpublic/private境界違反はなかった。
- 検証者: 実装を担当していない独立verifier agent
