# task-08: ブリッジAPIのユースケース単位公開（M2-02）

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` のマイルストーンM2「ブリッジとUI骨格」は、M2-02「Rust APIをユースケース単位に公開する」を定義している（完了条件: Dartテストからリスト作成、タスク作成、取得が呼べること）。このタスクは同項目に対応する。

task-03で `flutter_rust_bridge` によるFlutter⇔Rustの最小垂直貫通（`greet` / `create_draft_task`）が確立済みであり、task-05で `core/domain` にリスト/タスク操作ユースケース、task-06で `core/storage` に `ListRepository` / `TaskRepository::update` を含むSQLite(SQLCipher)実装、task-07で `core/crypto` にDevice Key (DK) 生成・OSキーチェーン抽象・SQLCipher用ローカルDB鍵導出が完成している。本タスクはこれらを `todori-app-bridge`（`app/rust/`）経由でDart側へユースケース単位で公開し、実際にFlutterアプリからリスト作成・タスク作成・タスク取得ができる状態にする。

iOS Simulator上で `todori-crypto` / `todori-storage` の全テストが成功済みであることは `docs/07_Phase1計画書.md` §3補足に記録されている。本タスクはiOSプラットフォームへのビルド組み込みまでは行わず、macOSデスクトップ（開発ホスト）上での動作確認までを範囲とする。

## 2. 事前に読むべきファイル

- `docs/tasks/task-03-flutter-rust-bridge.md`（本タスクの前提となるFRB垂直貫通の指示書と完了報告）
- `docs/tasks/task-07-device-key.md`（Device Key抽象・SQLCipher鍵導出の指示書と完了報告）
- `app/rust/src/api.rs`（既存の公開API `greet` / `create_draft_task`）
- `app/rust/Cargo.toml`（現在の依存関係、`crate-type` 設定）
- `flutter_rust_bridge.yaml`（codegen設定。`rust_input: crate::api` を確認）
- `app/test/rust_bridge_test.dart`（既存Dartテストの流儀。`RustLib.init()` の呼び出し方）
- `core/storage/src/lib.rs` の公開API（`open_encrypted` / `ListRepository` / `TaskRepository` トレイトとSQLite実装）
- `core/crypto/src/device_key.rs`（`DeviceKeyStore` トレイト、`ensure_device_key`、`derive_local_db_key`、`KeyStoreError`）
- `docs/07_Phase1計画書.md` M2セクション（M2-01〜M2-04の完了条件）
- `docs/03_技術仕様書.md` §1.3（FFI境界でのエラーハンドリング方針: Rustコア関数は `Result` 型で返却し、panicはDart側に構造化エラーとして通知する）

## 3. ゴール

`todori-app-bridge` に `core/domain` のユースケース・`core/storage` のリポジトリ・`core/crypto` のDevice Key抽象を接続したリスト/タスク操作APIを実装し、Dartテストから「初期化 → リスト作成 → タスク作成 → 取得 → ステータス変更 → 削除/復元」までの一連の操作が呼べることを実証する。`cargo test --workspace` と `cd app && flutter test` の双方が緑になること。

## 4. スコープ

### やること

1. **依存追加**: `app/rust/Cargo.toml` に `todori-storage.workspace = true`、`todori-crypto.workspace = true` を追加する（workspace path依存のためネットワーク不要）。
2. **開発用DeviceKeyStore**: `app/rust/src/dev_key_store.rs`（新規、FRB公開対象外）に `FileDeviceKeyStore` を実装する。`todori_crypto::DeviceKeyStore` トレイトを実装し、DK 32byteを指定ディレクトリ内の `device.key` ファイルに**生バイナリで**読み書きする（std::fsのみ使用）。ドキュメントコメントに「開発用の暫定実装。平文ファイル保存のため本番使用禁止。iOS Keychain等のOSキーチェーン実装が後続タスクで置き換える」と明記する。ファイル読み書きエラーは `KeyStoreError::Backend(文字列)` に変換する。
3. **ブリッジ状態管理**: `app/rust/src/api.rs` に `OnceLock` ベースのグローバル状態（DBファイルパス + 導出済みDB鍵32byte）を持たせる。
   - `pub fn init_core(db_dir: String) -> Result<(), String>`: `FileDeviceKeyStore` で `ensure_device_key` → `derive_local_db_key` → `<db_dir>/todori.db` を `open_encrypted` で一度開いてスキーマ初期化 → パスと鍵を `OnceLock` に保存する。既に初期化済みの場合の挙動（成功として返すのか、エラーにするのか）をdocコメントに明記する。
   - 各ユースケース関数は呼び出しごとに保存済みパス+鍵で `open_encrypted` して接続を作る（rusqliteの `Connection` は `!Sync` でありFRBのスレッドプールと相性が悪いため）。接続の使い回しは行わず、後続タスクでの最適化課題としてdocコメントに技術負債として明記する。未初期化状態での呼び出しは `Err("core not initialized...")` 相当のエラーを返す。
4. **DTO定義**: `TaskDto` / `ListDto` structを定義する（フィールドは `core/domain` の `Task` / `List` に対応させる）。ID系フィールドは `String`（UUID文字列）、`status` は `String`（"todo"等のsnake_case）、時刻は `i64` / `Option<i64>` とする。domain型からDTOへの変換関数を実装する。FRBがこれらのstructから自動でDartクラスを生成する。
5. **ユースケースAPI**（すべて `Result<_, String>` を返す。エラーは `DomainError` / `StorageError` の `to_string()` をそのまま渡す）:
   - `create_list(name: String, sort_order: String) -> Result<ListDto, String>`（`core::domain::new_list` + `ListRepository::insert`。`now_ms` は `std::time::SystemTime` から取得してよい。ブリッジ層はI/O境界であるため時刻取得を許容する）
   - `get_lists() -> Result<Vec<ListDto>, String>`
   - `create_task(list_id: String, title: String, sort_order: String) -> Result<TaskDto, String>`
   - `get_tasks(list_id: String) -> Result<Vec<TaskDto>, String>`（active一覧）
   - `set_task_status(task_id: String, status: String, closed_reason: Option<String>) -> Result<TaskDto, String>`（statusは "todo" / "in_progress" / "done" / "wont_do"。`get` → `core::domain::transition_task` → `update` の順で実装する）
   - `trash_task(task_id: String) -> Result<TaskDto, String>` / `restore_task(task_id: String) -> Result<TaskDto, String>`（`core::domain::delete_task` / `restore_task` → `update`）
   - `get_trashed_tasks() -> Result<Vec<TaskDto>, String>`
   - 既存の `greet` / `create_draft_task` は変更せず残す（既存Dartテストを維持する）。
   - `sort_order` は呼び出し側指定とする（fractional index自動生成はM3の範囲であり本タスクでは行わないことをdocコメントに明記する）。
6. **codegen再実行**: リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する（`~/.cargo/bin` にインストール済みのv2.12.0を使用）。生成物はコミット対象とする。**生成ファイル（`frb_generated.*`）を手編集しないこと。**
7. **ネイティブライブラリ再ビルド**: `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` を実行する（task-03で確立したDartテスト用ロードパスに合わせる）。
8. **Dartテスト追加**: `app/test/core_usecases_test.dart`（新規）を作成する。`Directory.systemTemp.createTemp` で一時ディレクトリを作り、`initCore` → `createList` → `createTask` → `getTasks` に含まれる → `setTaskStatus`（doneへ遷移し `completedAt` が非null になる）→ `trashTask` で `getTasks` から消え `getTrashedTasks` に現れる → `restoreTask` で戻る、という一連の流れを検証する。異常系として、不正な遷移（done→wont_do）でエラーがthrowされること、空titleの `createTask` がエラーになることを検証する。既存 `rust_bridge_test.dart` / `widget_test.dart` は変更不要とし、全テストが通過することを確認する。

### やらないこと

- UI（画面）の変更（`app/lib/main.dart` は触らない。M2-03の範囲）。
- iOS/Android向けビルド組み込み。
- OSキーチェーンの本実装（`FileDeviceKeyStore` は開発用の暫定実装に留める）。
- fractional index生成。
- `core/` 配下の変更（`core/domain` / `core/storage` / `core/crypto` のAPIをそのまま利用する。不足がある場合は独断で追加・変更せず、完了報告の未解決事項に記録し、本タスクのスコープ内で合理的な回避策を取る）。
- 非同期Stream API（`flutter_rust_bridge` のasync/Stream機能）の導入。
- 新規外部crateの追加（本タスクの実行環境はネットワークアクセス不可であるため、crates.ioからの新規取得が発生する変更を行ってはならない）。

## 5. 実装手順（例）

1. `app/rust/src/api.rs`、`app/rust/Cargo.toml`、`flutter_rust_bridge.yaml`、`core/storage/src/lib.rs`、`core/crypto/src/device_key.rs`、`core/domain/src/usecases.rs` を再読し、既存のAPI・トレイト・エラー型の形を把握する。
2. `app/rust/Cargo.toml` に `todori-storage.workspace = true` / `todori-crypto.workspace = true` を追加する。
3. `app/rust/src/dev_key_store.rs` を新規作成し、`FileDeviceKeyStore` を実装する（`todori_crypto::DeviceKeyStore` トレイトを実装）。
4. `app/rust/src/lib.rs`（または該当のモジュール宣言箇所）に `mod dev_key_store;` を追加する（FRB公開対象外のため `pub` にはしない）。
5. `app/rust/src/api.rs` に `OnceLock` ベースの状態、`init_core`、DTO（`TaskDto` / `ListDto`）と変換関数、各ユースケース関数を実装する。
6. `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` をリポジトリルートで実行し、生成物を確認する。
7. `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` でネイティブライブラリを再ビルドする。
8. `app/test/core_usecases_test.dart` を実装し `cd app && flutter test` で確認する。
9. 最後に `cargo fmt --all`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`、`cd app && flutter analyze` を実行し全体の品質ゲートを確認する。

## 6. 受け入れ基準

- [ ] `cargo fmt --all -- --check` が差分なしで通過する
- [ ] `cargo clippy --workspace -- -D warnings` が警告ゼロで通過する
- [ ] `cargo test --workspace` が全テスト成功する
- [ ] `cd app && flutter analyze` が警告・エラーなしで完了する
- [ ] `cd app && flutter test` が全テスト成功する（新規 `core_usecases_test.dart` を含む）
- [ ] codegen再実行後の生成物の差分がコミットに含まれている

## 7. 制約・注意事項

- FRB生成マクロ由来のclippy警告は既存の `#![allow(clippy::not_unsafe_ptr_arg_deref)]`（`app/rust/src/lib.rs`）で吸収済みであり、新たなallowを安易に追加しないこと。
- DartテストはFRBの `RustLib.init()` を1回だけ行うこと（既存 `rust_bridge_test.dart` の流儀に倣う）。
- DK・DB鍵をログ出力しないこと（`Debug`/`Display`/println等に鍵バイト列を渡さない）。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` / `docs/04_課金設計書.md` / `docs/07_Phase1計画書.md` は変更しないこと。
- 仕様書の記述だけでは一意に決まらない実装判断が生じた場合は、独断で仕様書側を変更せず、完了報告の「未解決事項」に記録すること（`docs/tasks/README.md` 共通規約6.）。

## 8. 完了報告に含めるべき内容

- 公開したAPI関数とDTOの一覧
- `init_core` の初期化セマンティクス（再初期化時の挙動を含む）
- 接続管理方式（毎回 `open_encrypted` する方式）の性能面の所見
- 追加したDartテストの総数
- 未解決事項（あれば）

## 9. 完了報告

作業日: 2026-07-04

### 実装結果

- `app/rust/Cargo.toml` に `todori-storage.workspace = true` / `todori-crypto.workspace = true` を追加し、`todori-app-bridge` から storage / crypto / domain を接続した。
- `app/rust/src/dev_key_store.rs` を追加し、開発用の `FileDeviceKeyStore` を実装した。DKは指定ディレクトリ配下の `device.key` に32byte生バイナリで保存する。本実装は平文ファイル保存のため本番使用禁止であり、後続タスクでiOS Keychain等のOSキーチェーン実装に置き換える前提である。
- `app/rust/src/api.rs` に `OnceLock` ベースのブリッジ状態、DTO、リスト/タスク操作APIを追加した。
- `flutter_rust_bridge_codegen 2.12.0` で生成物を再生成した。
- Dartテスト用ネイティブライブラリを `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` で再ビルドした。
- `app/test/core_usecases_test.dart` を追加し、リスト作成、タスク作成、取得、完了遷移、削除、ゴミ箱取得、復元、不正遷移、空タイトル検証をDart側から呼ぶテストを実装した。

### 公開したAPI関数

- 既存維持: `greet(name: String) -> String`
- 既存維持: `create_draft_task(title: String) -> String`
- 追加: `init_core(db_dir: String) -> Result<(), String>`
- 追加: `create_list(name: String, sort_order: String) -> Result<ListDto, String>`
- 追加: `get_lists() -> Result<Vec<ListDto>, String>`
- 追加: `create_task(list_id: String, title: String, sort_order: String) -> Result<TaskDto, String>`
- 追加: `get_tasks(list_id: String) -> Result<Vec<TaskDto>, String>`
- 追加: `set_task_status(task_id: String, status: String, closed_reason: Option<String>) -> Result<TaskDto, String>`
- 追加: `trash_task(task_id: String) -> Result<TaskDto, String>`
- 追加: `restore_task(task_id: String) -> Result<TaskDto, String>`
- 追加: `get_trashed_tasks() -> Result<Vec<TaskDto>, String>`

### 公開したDTO

- `ListDto`: `id` / `name` / `color` / `icon` / `org_id` / `sort_order` / `created_at` / `updated_at`
- `TaskDto`: `id` / `list_id` / `parent_task_id` / `title` / `note` / `status` / `priority` / `due_at` / `scheduled_at` / `estimated_minutes` / `sort_order` / `completed_at` / `closed_reason` / `deleted_at` / `assignee` / `created_at` / `updated_at`
- ID系フィールドはUUID文字列、`status` は `todo` / `in_progress` / `done` / `wont_do` のsnake_case文字列、時刻はepoch millisecondsとして公開する。

### `init_core` の初期化セマンティクス

- `db_dir` を作成し、`FileDeviceKeyStore` でDKを `ensure_device_key` する。
- DKから `derive_local_db_key` でSQLCipher鍵を導出し、`<db_dir>/todori.db` を `open_encrypted` で一度開いてスキーマを初期化する。
- グローバル状態にはDBファイルパスと導出済みDB鍵32byteのみ保存する。
- 同じDBパスでの再初期化は冪等に成功する。
- 異なるDBパスでの再初期化は `OnceLock` の状態を安全に差し替えられないためエラーにする。
- 未初期化状態で各ユースケースAPIを呼ぶと `core not initialized; call init_core first` を返す。

### 接続管理方式

- 各ユースケースAPIの呼び出しごとに、保存済みDBパスとDB鍵で `open_encrypted` し、新しい `rusqlite::Connection` と repository を作る。
- `rusqlite::Connection` は `!Sync` であり、FRBのスレッドプール上で共有接続をグローバル保持しないための保守的な実装である。
- 性能面では、API呼び出しごとにDB openとSQLCipher `PRAGMA key` のオーバーヘッドが発生する。MVP初期の正しさ優先として許容し、後続タスクで接続プールや実行スレッド固定を検討する。

### テスト

- `app/test/core_usecases_test.dart` にDartテストを3件追加した。
  - 正常系: `initCore` → `createList` → `getLists` → `createTask` → `getTasks` → `setTaskStatus(done)` → `trashTask` → `getTrashedTasks` → `restoreTask`
  - 異常系: `done` → `wont_do` の不正遷移がthrowされること
  - 異常系: 空白のみtitleの `createTask` がthrowされること

### 検証

- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` 成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` 成功。
- `cargo fmt --all -- --check` 成功。
- `cargo clippy --workspace -- -D warnings` 成功。
- `cargo test --workspace` 成功。
- `cd app && flutter analyze` 成功。
- `cd app && flutter test` は未通過。この環境のサンドボックス制約により、Flutter testerがテストハーネス用に `127.0.0.1:0` へ `HttpServer.bind` する段階で `Operation not permitted` となり、テストファイル読み込み前に失敗した。`--no-dds` でも同じ箇所で失敗したため、コード由来のテスト失敗ではなくローカルソケット作成権限の問題である。

### 未解決事項

- `cd app && flutter test` は、ローカルサーバーソケット作成が許可される環境で再実行する必要がある。
- `FileDeviceKeyStore` は開発用の暫定実装であり、本番向けにはOSキーチェーン実装への置き換えが必要である。
- 現在の接続管理はAPI呼び出しごとにDBを開くため、UI実装後に性能計測し、必要に応じて接続管理方式を見直す必要がある。
