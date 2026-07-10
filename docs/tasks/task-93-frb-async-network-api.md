# task-93: FRB network APIのasync統一

> ステータス: 完了（FRB async統一・bridge runtime削除・独立検証合格）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

task-92は`ClientProfile`のaccount/sync network APIをasync正本にしたが、既存Rust FRB signatureを同期のまま維持するため、`app/rust/profile_handle.rs`が呼出ごとにTokio runtimeを生成してFutureをblockしている。Todoriは未リリースで内部互換を要求せず、Dart側はすでに`Future` APIであるため、このblocking adapterは不要な複雑性である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/dev/client-profile-architecture.md`
- `docs/tasks/task-92-client-profile-full-migration.md`
- `app/rust/src/api.rs`
- `app/rust/src/profile_handle.rs`
- `app/rust/Cargo.toml`
- `app/tool/check_client_boundaries.sh`

## 3. ゴール

- account register/login/logoutとsync nowをFRB側でもasync関数にする。
- bridge内Tokio runtime生成と`app/rust`のTokio依存を削除する。
- Dart公開APIの`Future` signatureと呼出側を維持する。
- Flutter/CLI/MCPが同じ`ClientProfile` async APIを自然に利用できる境界にする。

## 4. スコープ

### やること

- networkを伴う4つのFRB関数をasync化して`ClientProfile` Futureを直接awaitする。
- `profile_handle.rs`からblocking executorを削除する。
- app manifestとboundary allowlistからTokioを削除する。
- FRB生成物、architecture文書、task-92の最終記録を実装後の事実へ同期する。

### やらないこと

- `ClientProfile` account/sync protocolの変更。
- wire、crypto、DB schema、Flutter UIの変更。
- 低水準`test-support` featureの変更。

## 5. 実装手順

1. 4関数をasync化し、blocking executorとTokio依存を削除する。
2. Rust signature testとboundary negative fixtureを更新する。
3. FRB 2.12.0で再生成し、Dart公開面とcall siteを確認する。
4. 全品質ゲートと独立検証を行う。

## 6. 受け入れ基準

- [x] 4つのFRB関数が`pub async fn`で`ClientProfile` Futureを直接awaitする。
- [x] `app/rust`のTokio参照と依存が0件。
- [x] Dart側は従来どおり`Future` APIで、既存call siteが変更なく動く。
- [x] bridgeの下位crate参照0、通常依存はFRBと`todori-client`だけ。
- [x] FRB再生成、全品質ゲート、独立検証が成功する。

## 7. 制約・注意事項

- network Futureのerrorはbridgeで既存`String`へ変換し、secretや詳細crypto errorを露出しない。
- `profile_handle.rs`はprofile初期化/取得だけを所有する。
- public/private境界、crate命名、`test-support`隔離を維持する。

## 8. 完了報告に含めるべき内容

- async化した関数、削除したruntime/依存。
- FRB/Dart差分。
- boundary checkと全品質ゲート。
- 独立検証と未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-10
- 結果: `account_register`、`account_login`、`account_logout`、`sync_now`をFRB側でも`pub async fn`へ変更し、`ClientProfile` Futureを直接awaitする構成へ統一した。
- 削除: `profile_handle.rs`の`run_network`、Tokio runtime builder / `block_on`、`app/rust`のTokio直接依存、boundary allowlistのTokio例外を削除した。profile handleは初期化と取得だけを所有する。
- FRB / Dart: FRB 2.12.0で再生成し、生成Rustは対象4関数が`wrap_async` + `.await`へ変わった。Dart生成APIと既存call siteは差分なしで、従来どおり`Future`を返す。
- Boundary: handwritten bridgeの`tokio` / runtime / `block_on` / `run_network`は0件。app通常依存は`flutter_rust_bridge`と`todori-client`だけ。下位crate参照0と`test-support`隔離を維持した。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`（client 33、server auth 1/sync 9、storage 72 + ignored 1、sync 50、bridge 2、compile-fail doctest 2）、bridge release build、`flutter analyze`、`flutter test`（130 passed / visual QA harness 1 skipped）、hardcoded-string check、boundary check/negative fixture、`git diff --check`が成功した。
- Commit: `2ce0cea`。
- 未解決: なし。multiprocess lease、OS secret store、Fuzzy-scan等はtask-92から継続する別候補。

> 追補（task-94）: 本task当時の`ClientProfile`は`TodoriClient`へbreaking renameした。async direct-awaitという本taskの契約は不変。

### 独立検証

- 判定: 合格（P1 / P2 / P3なし）
- 根拠: 4 FRB関数のdirect await、bridge Tokio/runtime参照0、manifest exact allowlist、生成Rust`wrap_async`、Dart API/call site不変、test-support隔離、境界negative fixtureを確認した。FRB 2.12.0再生成一致と全品質ゲートを独立再実行して成功した。
- 検証者: 独立verifier agent
