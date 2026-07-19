# task-75: 同期オーケストレーションとKeychainのcore移設

> ステータス: 完了（挙動変更なしのcore抽出リファクタ）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

`app/rust/src/api.rs` はFRB公開関数、DTO変換、同期オーケストレーション、HLC tick、pull適用、outbox登録、List DEK補完を同居させており、ブリッジ層が肥大化している。また、Device Key / account secret のKeychain実装は `app/rust/src/dev_key_store.rs` にあり、暗号・鍵管理の責務が `core/crypto` ではなくブリッジ側へ残っている。

`docs/03_技術仕様書.md` の「コアに知能、ブリッジは薄い皮」原則へ戻すため、挙動変更なしで責務をcore crateへ移す。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/03_技術仕様書.md` §2、§4、§5、§6
- `docs/08_Phase2計画書.md`
- `docs/tasks/task-64-keychain-device-key.md`
- `docs/tasks/task-72-sync-engine.md`
- `docs/tasks/task-73-adr010-and-dek-alignment.md`
- `app/rust/src/api.rs`
- `app/rust/src/dev_key_store.rs`
- `core/sync/src/`
- `core/crypto/src/`
- `core/storage/src/lib.rs`

## 3. ゴール

- 同期オーケストレーション本体を `core/sync` へ移し、`app/rust/src/api.rs` はFRB公開関数、DTO変換、小さな入力変換に絞る。
- Device Key / Keychain / account secret store を `core/crypto` へ移す。
- API、DB schema、同期wire format、暗号文/平文フィールド、UI挙動を変更しない。
- 既存テストを弱めず、品質ゲートを全通過させる。

## 4. スコープ

### やること

- `core/sync` に同期オーケストレーションを移す。
- storage access はtraitで注入し、`core/sync` が `rusqlite` / `Sqlite*Repository` 具象へ直接依存しない形にする。
- `app/rust` 側にはSQLite repository adapterとFRB公開関数だけを残す。
- `app/rust/src/dev_key_store.rs` を `core/crypto` へ移し、Apple実装は `cfg(any(target_os = "ios", target_os = "macos"))` のまま維持する。
- Rust API変更後は `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
- `README.md` / `docs/tasks/README.md` / `docs/tasks/BACKLOG.md` を更新する。

### やらないこと

- FRB公開APIの追加・削除・引数/戻り値変更。
- SQLite schema / migration / sync table 変更。
- 同期プロトコル、暗号方式、List DEK設計、HLC規約の変更。
- テスト削除、skip化、期待値の弱体化。
- UI変更、文言変更、ARB変更。
- git commit。

## 5. 実装手順（例）

1. `api.rs` のprivate同期ロジックを分類する: sync run、pull apply、enqueue、key補完、plaintext変換、HLC tick。
2. `core/sync` に `apply.rs` / `enqueue.rs` / `keys.rs` などを追加し、分類したロジックを移す。
3. `core/sync` に最小traitを定義し、outbox、cursor、record state、settings、task/list upsert/delete をtrait経由にする。
4. `app/rust` に trait adapter を追加し、既存 `taskveil-storage` のSQLite repositoryへ委譲する。
5. `dev_key_store.rs` を `core/crypto` へ移し、`security-framework` 依存も `core/crypto` のApple target依存へ移す。
6. `api.rs` の公開関数から core/sync / core/crypto の関数を呼び、DTO変換以外の大きなprivate処理を別モジュールへ出す。
7. FRB生成を実行し、生成物の手編集をしない。
8. 品質ゲートとDocker統合テストを実行し、完了報告へ行数表・移設対応表・検証結果を記録する。

## 6. 受け入れ基準

共通受け入れ基準は `docs/tasks/README.md` の「共通受け入れ基準」を満たすこと。

- [ ] `app/rust/src/api.rs` が900行以下であることを `wc -l` で確認している。
- [ ] 同期run / pull適用 / outbox enqueue / HLC tick / plaintext変換 / List DEK補完の実体が `core/sync` 側へ移っている。
- [ ] `core/sync` が `rusqlite` や `Sqlite*Repository` 具象へ直接依存していない。
- [ ] Device Key / Keychain / account secret store 実装が `core/crypto` 側へ移り、Apple target cfg とFlutter test fallbackが維持されている。
- [ ] FRB公開API、SQLite schema、sync wire format、暗号化blob形式、UI文字列に差分がない。
- [ ] `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` が実行済みで、生成差分がある場合は生成物のみである。
- [ ] server/sync統合テストを含むRust全スイートとFlutter testが既存数を弱めず成功している。
- [ ] 完了報告に before/after の行数表と移設対応表がある。

## 7. 制約・注意事項

- 挙動変更ゼロの純リファクタである。バグ修正に見える変更も本タスクでは行わない。
- `flutter_rust_bridge` はRust crate / Dart pub / codegenすべて `2.12.0` 固定を維持する。
- 秘密情報、Device Key、session token、MK/DEK、復号済みplaintextをDart境界やログへ出してはならない。
- `FileDeviceKeyStore` は非Apple開発・Flutter test fallbackとして残すが、本番用primary storeへ戻してはならない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `.github/` と `taskveil-private/` は変更しない。
- git commit はしない。

## 8. 完了報告に含めるべき内容

- 作業日。
- 実装結果の要約。
- before/after の行数表（`app/rust/src/api.rs`、`core/sync/src/*.rs`、`core/crypto/src/*.rs`）。
- 移設対応表（旧配置、移設先、責務）。
- FRB再生成結果。
- 検証結果（実行コマンド、成功/失敗、失敗時は環境要因かコード要因か）。
- 未解決事項。ない場合は「なし」と明記する。

## 9. 完了報告

作業日: 2026-07-08

### 実装結果

- `app/rust/src/api.rs` から同期run、pull適用、outbox enqueue、HLC tick、plaintext変換、List DEK補完を `core/sync` へ移設した。
- `core/sync` に `apply.rs` / `enqueue.rs` / `keys.rs` を追加し、ローカルDBアクセスは `LocalSyncStore` traitで注入する形にした。`core/sync` 内に `rusqlite` / `Sqlite*Repository` 参照はない。
- `app/rust/src/sync_store.rs` を追加し、`taskveil-storage` のSQLite repositoryを `LocalSyncStore` へ接続するadapterにした。
- `app/rust/src/dev_key_store.rs` を `core/crypto/src/dev_key_store.rs` へ移設し、`security-framework` 依存を `core/crypto` のApple target依存へ移した。
- `app/rust/src/support.rs` を追加し、FRB公開関数ではないランタイム状態・account helper・repository openerを `api.rs` から分離した。
- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行した。公開APIは変更なし。生成差分は `app/lib/src/rust/api.dart` の非公開関数コメント更新のみ。
- `README.md` / `docs/tasks/README.md` / `docs/tasks/BACKLOG.md` を更新した。

### 行数表

| 対象 | before | after | 備考 |
|---|---:|---:|---|
| `app/rust/src/api.rs` | 1930 | 745 | 900行以下を確認 |
| `core/sync/src/*.rs` | 1834 | 2698 | 同期オーケストレーションを追加 |
| `core/crypto/src/*.rs` | 860 | 1618 | `dev_key_store.rs` を移設 |

計測コマンド:

- before: `git show HEAD:app/rust/src/api.rs | wc -l`、`git ls-tree -r --name-only HEAD core/sync/src` / `core/crypto/src` と `git show` の合計
- after: `wc -l app/rust/src/api.rs $(find core/sync/src -name '*.rs' | sort) $(find core/crypto/src -name '*.rs' | sort)`

### 移設対応表

| 旧配置 | 移設先 | 責務 |
|---|---|---|
| `app/rust/src/api.rs` `run_sync_now` / `apply_pull_*` | `core/sync/src/apply.rs` | push/pull、ACK、cursor更新、pull復号、LWW merge、再push判定 |
| `app/rust/src/api.rs` `enqueue_*` / `tick_local_hlc` | `core/sync/src/enqueue.rs` | outbox登録、record state更新、HLC tick、task/list plaintext生成 |
| `app/rust/src/api.rs` `ensure_list_dek_for_list` の中核 | `core/sync/src/keys.rs` | List DEK生成、bundle wrap、server upsert、local key material返却 |
| `app/rust/src/api.rs` storage具象呼び出し | `app/rust/src/sync_store.rs` | `LocalSyncStore` adapter。SQLite具象はブリッジ側に限定 |
| `app/rust/src/dev_key_store.rs` | `core/crypto/src/dev_key_store.rs` | Device Key、Apple Keychain、File fallback、account secret store |
| `app/rust/src/api.rs` account/runtime helper | `app/rust/src/support.rs` | FRB非公開のランタイム状態、account auth/logout、repository opener |

### 検証結果

- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`: 成功。
- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功。server/sync統合テスト `server/tests/sync_server.rs` は5件成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter analyze`: 成功。
- `cd app && flutter test`: 成功（123 passed、1 skippedは既存visual QA harness）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git diff --check`: 成功。
- `git grep -n "rusqlite\\|Sqlite" core/sync || true`: 該当なし。

### 未解決事項

なし。
