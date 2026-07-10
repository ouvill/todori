# task-94: Rust client境界の命名整理

> ステータス: 完了（TodoriClient命名統一・旧aliasなし・独立検証合格）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

task-92 / task-93でFlutter bridge、CLI、MCPから共有する高水準入口を`ClientProfile`へ集約した。しかし`Profile`は一般にユーザーの表示プロフィールを連想させ、実際にはローカル暗号化DB、Device Key参照、account binding、session、同期状態、application serviceを所有するruntime facadeであることが名前から伝わらない。

同時に、`todori-client`内部にはtransactional mutation専用の低水準`Client`が残り、高水準入口を`TodoriClient`へ改名した際に役割が衝突する。Todoriは未リリースで内部互換を要求しないため、旧名aliasを残さず、実行主体とローカル保存境界を分離した最終命名へ直接置き換える。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/task-92-client-profile-full-migration.md`
- `docs/tasks/task-93-frb-async-network-api.md`
- `docs/dev/client-profile-architecture.md`
- `core/client/src/lib.rs`
- `core/client/src/profile/`
- `core/client/src/task_service.rs`
- `app/rust/src/profile_handle.rs`
- `app/tool/check_client_boundaries.sh`

## 3. ゴール

- frontend共通の高水準runtime facadeを`TodoriClient`と呼ぶ。
- ローカル暗号化データ境界を開く設定を`LocalProfileConfig`と呼び、`LocalProfile`という概念をruntime facadeと区別する。
- bridgeのprocess-global handleを`client_handle` / `client()`として表現する。
- 内部のtransactional mutation専用`Client`を役割名へ改め、高水準clientとの衝突をなくす。
- Flutter、CLI、MCPが引き続き`todori-client`だけを入口とし、Fuzzy-scan実装前の境界を明瞭にする。

## 4. スコープ

### やること

- `ClientProfile` → `TodoriClient`、`ProfileConfig` → `LocalProfileConfig`へbreaking renameする。
- `core/client/src/profile/`をruntime facadeを表すmodule名へ変更する。
- `profile_handle.rs` → `client_handle.rs`、`init_profile` → `init_client`、`profile()` → `client()`へ変更する。
- 低水準`Client`をtransactional mutationの役割が分かる名前へ変更し、`test-support` exportとserver testを同期する。
- CLI/MCP compile contract、bridge boundary checkとnegative fixtureを更新する。
- architecture、開発規約、ADR/完了task追補の現在形を新命名へ同期する。
- 旧名が実装・現行設計文書へ残っていないことを機械的に検査する。

### やらないこと

- Flutter/Dart公開APIや画面の変更。
- sync wire protocol、暗号形式、DB schemaの変更。
- Fuzzy-scan、OS secret store、multiprocess leaseの実装。
- 完了済みtask本文の歴史的記録の全面改稿。必要な場合は追補で現在名を明記する。

## 5. 実装手順

1. 全参照とpublic surface、FRB生成物への影響を調査する。
2. client crateの高水準runtime facadeと設定型をbreaking renameし、module構成を整理する。
3. 低水準transactional mutation型を役割名へ変更する。
4. Flutter bridge、CLI、MCP、server test、boundary checkを新名へ移行する。
5. architecture / ADR / AGENTSを新しい語彙と責務分離へ同期する。
6. 旧名残存check、Rust/Flutter/境界の全品質ゲートを実行する。
7. 実装を担当していないエージェントが統合HEADを独立検証する。

## 6. 受け入れ基準

- [x] 通常public APIの唯一の高水準入口が`TodoriClient`で、`LocalProfileConfig`を受け取る。
- [x] `ClientProfile` / `ProfileConfig`の互換aliasが存在しない。
- [x] 低水準transactional mutation型が`Client`という曖昧名を使用しない。
- [x] bridgeのhandwritten Rustに`profile_handle` / `profile()`というruntime facade名が残らない。
- [x] CLI/MCPが`TodoriClient::open(LocalProfileConfig)`とasync APIをcompile時に固定する。
- [x] Flutter/Dart公開call surfaceとsync/crypto/DB形式に変更がない。
- [x] boundary checkが`client_handle.rs`だけにprocess-global handleを許し、negative fixtureが成功する。
- [x] 現行architecture文書が`TodoriClient`と`LocalProfile`の違いを明記する。
- [x] `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`が成功する。
- [x] Flutter変更時ゲート、hardcoded string check、client boundary check、`git diff --check`が成功する。
- [x] 独立検証でP1 / P2 / P3指摘がない。

## 7. 制約・注意事項

- 旧名alias、deprecated shim、dual APIは追加しない。
- crate名`todori-client` / `todori_client`とFRB固定名`todori_app_bridge`は変更しない。
- `LocalProfile`は永続化・security boundaryの概念名とし、公開runtime struct名には使わない。
- frontend adapterへrepository、鍵、tenant、sync coordinatorを露出しない。
- FRB生成物は手編集しない。Rust FRB公開signatureが変わる場合だけcodegenする。
- 完了済みtask-91〜93は当時の履歴を保持し、現在の正規名は追補で示す。

## 8. 完了報告に含めるべき内容

- 新旧命名対応と、各型/moduleの責務。
- 変更したpublic surface、bridge、CLI/MCP、test-supportの範囲。
- 旧名残存checkと全品質ゲートの結果。
- Flutter/Dart公開面、sync/crypto/DB形式が不変である根拠。
- 独立検証結果、commit hash、未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-10
- 結果: frontend共通runtime facadeを`ClientProfile`から`TodoriClient`へ、起動設定を`ProfileConfig`から`LocalProfileConfig`へbreaking renameした。旧名aliasは追加していない。
- 構成: `core/client/src/profile/`を`runtime/`へ、低水準`Client`と`task_service.rs`を`SqliteMutationService`と`mutation_service.rs`へ、bridgeの`profile_handle.rs` / `profile()`を`client_handle.rs` / `client()`へ変更した。
- Public API: 通常root公開面は`TodoriClient`、`LocalProfileConfig`、frontend-neutral model / command / domain型、`ClientError`に限定した。`SqliteMutationService`、`LocalMutationContext`、SQLite sync store、local crypto helperは引き続き`test-support`限定である。
- 契約: CLI/MCPは`TodoriClient::open(LocalProfileConfig)`とasync `sync_now`をcompile時に参照する。bridgeの39公開関数signature testは成功し、FRB 2.12.0再生成後のDart差分は`ClientProfile`を`TodoriClient`へ直すdoc comment 1行だけだった。
- 境界: boundary checkはprocess-global `OnceLock`を`client_handle.rs`だけに許可し、旧`profile_handle.rs`とhandle外`OnceLock`を拒否するnegative fixtureを追加した。
- Documentation: `LocalProfile`を端末内データ/security boundary、`TodoriClient`をruntime facade、`LocalProfileConfig`を起動設定、`LocalProfileBinding`を永続account identityとして区別し、AGENTS、技術仕様、ADR-011、architecture文書へ同期した。
- 検証: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker統合テストを含む`cargo test --workspace`、bridge release build、`flutter analyze`、`flutter test`（130成功、visual QA harness 1 skip）、hardcoded string check、boundary check / negative fixture、`git diff --check`が成功した。
- Commit: `5981d2a`（`refactor(client): Rust client境界の命名を整理`）
- 未解決: なし。Fuzzy-scan、OS secret store、multiprocess leaseは既存の別候補であり、本taskでは変更していない。

### 独立検証

- 判定: 合格（P1 / P2 / P3なし）
- 根拠: 通常root public、旧alias不在、`test-support`隔離、bridge handle、CLI/MCP compile contract、FRB/Dart差分、用語分離を確認した。`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker統合テストを含む`cargo test --workspace`、bridge release build、`flutter analyze`、`flutter test`（130成功、visual QA harness 1 skip）、hardcoded string check、boundary positive/negative、`git diff --check`を独立再実行してすべて成功した。
- 検証者: 実装を担当していないエージェント（verify_task93）
