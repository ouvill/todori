# task-02: SQLCipherビルド検証PoC

## 1. 背景とコンテキスト

Cotoriのローカルストレージは「素のSQLite + SQLCipher」を採用する設計になっている（`docs/03_技術仕様書.md` §5）。SQLCipherの鍵は常にDevice Key (DK) からHKDFで導出した値を使う。しかし、Rustから SQLCipher を利用する `rusqlite` の `bundled-sqlcipher` 系featureが実際に各プラットフォーム（特にAndroid/iOS）でビルドできるかどうかは、`docs/03_技術仕様書.md` §12「未決事項リスト」の筆頭に挙げられている未検証事項である。

このタスクは、まずホストLinux環境で「SQLCipherで暗号化されたSQLite DBがRustから読み書きできる」ことを実証し、あわせて `TaskRepository`（`core/storage` に既にスタブとして定義済み）の最小実装をSQLite上に構築する。加えて、Androidクロスビルドの可否を調査する（調査が失敗してもタスク自体の失敗とはしない。詳細は4章）。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` §3（データモデル。特に §3.6 tasksテーブルのフィールド定義）
- `docs/03_技術仕様書.md` §5（ローカルストレージ。§5.1 採用技術、§5.2 暗号化の2レイヤー構造、§5.3 ローカルDB鍵、§5.4 全文検索）
- `docs/03_技術仕様書.md` §12（未決事項リスト。SQLCipher統合方式の検証が筆頭項目）
- `core/storage/src/lib.rs`（現状のスタブ実装。`TaskRepository` trait、`StorageError`）
- `core/domain/src/entities.rs`（`Task` / `TaskStatus` の構造。SQLiteスキーマはこのフィールド構成に対応させる）
- `core/storage/Cargo.toml`、リポジトリルート `Cargo.toml` の `[workspace.dependencies]`

## 3. ゴール

`cotori-storage` crateに `rusqlite`（SQLCipher有効化feature）を導入し、暗号化DBに対する読み書き・誤り鍵での失敗・FTS5全文検索が動作することをテストで実証する。あわせて `TaskRepository` の最小実装（insert/get）をSQLite上に構築する。

## 4. スコープ

### やること

1. **依存追加**: `rusqlite` をリポジトリルート `Cargo.toml` の `[workspace.dependencies]` に追加する。feature選定は次の優先順位で試すこと。
   - 第一候補: `bundled-sqlcipher-vendored-openssl`（SQLCipher本体・OpenSSL双方をベンダリングし、システム依存を最小化する）
   - 上記でビルドが通らない場合: `bundled-sqlcipher`（OpenSSLはシステムのものを利用）
   - あわせて全文検索用に `fts5` featureが必要か確認し、必要であれば有効化する（`bundled-sqlcipher` 系featureとの併用可否を実機で確認すること）。
   - どちらを採用したか、ビルド時に何が起きたかを完了報告に必ず記載する。
2. **スキーマ定義**: `core/storage/src/schema.sql`（新規ファイル）に `tasks` テーブルのDDLを書く。フィールドは `docs/03_技術仕様書.md` §3.6 に準拠すること（`id`, `list_id`, `parent_task_id`, `title`, `note`, `status`, `priority`, `due_at`, `scheduled_at`, `estimated_minutes`, `sort_order`, `completed_at`, `closed_reason`, `deleted_at`, `assignee`, `created_at`, `updated_at`）。型はSQLiteの型親和性に従い、`id`/`list_id`/`parent_task_id`/`assignee` は `TEXT`（UUID文字列）、`status` は `TEXT`、時刻系は `INTEGER`（epoch milliseconds）とする。
3. **暗号化オープン関数**: `core/storage/src/lib.rs`（または新規 `db.rs` を切り出してよい）に以下のシグネチャの関数を実装する。

   ```rust
   pub fn open_encrypted(path: &std::path::Path, key: &[u8; 32]) -> Result<rusqlite::Connection, StorageError>;
   ```

   実装内では `PRAGMA key = "x'<64桁hex>'";` の形式（SQLCipherのraw key指定構文）でクエリ発行し、鍵をhex文字列化して適用すること。鍵適用後、`schema.sql` を実行してテーブルが存在しなければ作成する。
4. **`TaskRepository` のSQLite実装**: `core/storage/src/lib.rs` の `TaskRepository` traitに対する実装型（例: `SqliteTaskRepository`）を追加し、`insert` と `get` を実装する（`update` は本PoCでは `StorageError::NotImplemented` を返す最小実装でよい）。
5. **テスト実装**（`tempfile` crateを `[dev-dependencies]` に追加してテスト用の一時ファイルパスを得ること）。以下をすべて実装する。
   - (1) 暗号化DBを新規作成し、レコードを書き込み、接続を閉じてから正しい鍵で再オープンし、書き込んだデータが読めることを確認するテスト
   - (2) 同じDBファイルを**誤った鍵**で再オープンした場合、クエリ実行（例えば `SELECT count(*) FROM tasks`）がエラーになることを確認するテスト（SQLCipherは鍵不一致でもファイルを開けてしまうことがあるため、`PRAGMA key` 適用後に何らかのクエリを実行して初めて失敗が判明する点に注意し、その挙動をテストで正しく捉えること）
   - (3) 同じDBファイルを**鍵を適用せず**（`PRAGMA key` を実行せずに）通常のSQLiteとしてオープンした場合、テーブル一覧やデータが読めない（暗号化されたバイナリとして扱われる）ことを確認するテスト
   - (4) FTS5仮想テーブル（例: `tasks_fts`。`title`/`note` を対象列とする）を作成し、データ投入後に全文検索クエリ（`MATCH`）が期待通りヒットすることを確認するテスト。rusqliteでFTS5を使うために必要なfeatureが有効化されていることも合わせて確認する
   - (5) `SqliteTaskRepository::insert` → `get` のラウンドトリップテスト（`core/domain::Task` の値を挿入し、同じ内容が取得できることを確認）
6. **Androidクロスビルド調査**: `cargo-ndk` の導入（`cargo install cargo-ndk`）を試み、Android NDKが利用可能な場合は `cargo ndk -t arm64-v8a -o <out-dir> build -p cotori-storage` を実行してビルド可否を確認する。NDKが環境に存在しない、あるいはツールチェーンの制約でビルドが完了しない場合は、**その旨と必要な準備手順（NDKバージョン、環境変数、`.cargo/config.toml`設定例など）を調査し文書化するだけでよい**。この調査自体が失敗してもタスク全体の受け入れ基準には影響しない（6章参照）。

### やらないこと

- iOS/macOS向けのビルド検証（macOSホストが必要なため、必要な手順の文書化のみ行い実機検証はしない）。
- libSQL/Tursoとの統合（サーバー側のみの技術であり、このタスクの対象外）。
- スキーママイグレーション機構の実装。
- `tasks_fts` と `tasks` 本体を同期させるトリガー（`INSERT`/`UPDATE`/`DELETE` 時に自動でFTSインデックスを更新する仕組み）の実装。本PoCでは手動でFTSテーブルにも投入するテストで十分。
- `core/domain` の変更。

## 5. 実装手順（例）

1. リポジトリルート `Cargo.toml` に以下を追記する。

   ```toml
   rusqlite = { version = "<最新安定版>", features = ["bundled-sqlcipher-vendored-openssl"] }
   tempfile = "<最新安定版>"
   ```

2. `core/storage/Cargo.toml` に `rusqlite.workspace = true` を追記し、`[dev-dependencies]` に `tempfile.workspace = true` を追記する。
3. `cargo build -p cotori-storage` を実行し、ビルドが通ることを確認する（初回はOpenSSLのビルドがあるため数分かかる可能性がある。所要時間を記録する）。ビルドに失敗した場合はfeatureを `bundled-sqlcipher` に変更して再試行し、結果を報告に記載する。
4. `core/storage/src/schema.sql` を作成する。
5. `core/storage/src/lib.rs` に `open_encrypted` と `SqliteTaskRepository` を実装する。
6. テストを実装し、`cargo test -p cotori-storage` で繰り返し検証する。
7. Androidクロスビルドを調査する。
8. 最後に `cargo fmt --all`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace` を実行する。

## 6. 受け入れ基準

- [ ] `cargo fmt --all -- --check` が差分なしで通過する
- [ ] `cargo clippy --workspace -- -D warnings` が警告ゼロで通過する
- [ ] `cargo test --workspace` が全テスト成功する
- [ ] `cargo test -p cotori-storage` で上記5.の(1)〜(5)のテストがすべて成功する
- [ ] Androidクロスビルドの調査結果（成功/失敗いずれでも可）が完了報告に記載されている

## 7. 制約・注意事項

- SQLCipherの鍵は本PoCでは固定のテスト用32byte値（例えば `[0x11; 32]` 等）で構わない。DKからのHKDF導出は `cotori-crypto::kdf::derive_key` を用いる想定だが、`core/storage` から `core/crypto` への依存追加は本タスクのスコープ外とする（テストでは鍵をその場で用意してよい）。
- OpenSSLのvendoredビルドはビルド時間・ディスク使用量が大きい。CI環境での実行時間が問題になりうる点を完了報告に記載すること。
- `PRAGMA key` に渡す鍵はSQLインジェクションを避けるため、文字列フォーマットではなくrusqliteの `execute` にhex文字列を安全に埋め込む方法（`format!("PRAGMA key = \"x'{}'\";", hex::encode(key))` 等）を用いること。`hex` crateの追加が必要であれば `[workspace.dependencies]` に追加してよい。
- テストは並列実行されるため、DBファイルパスは `tempfile::NamedTempFile` 等で必ずテストごとに独立させること。

## 8. 完了報告に含めるべき内容

- 採用した `rusqlite` のバージョンとfeature名（`bundled-sqlcipher-vendored-openssl` か `bundled-sqlcipher` か、その判断理由）
- 初回ビルド（OpenSSL vendoredビルドを含む）の所要時間の実測値
- ビルド後のバイナリ/rlibサイズの増分（`cargo build -p cotori-storage` 前後での比較）
- Androidクロスビルド調査の結果（成功した場合はビルドコマンドと出力先、失敗した場合は原因と必要な準備手順）
- `docs/03_技術仕様書.md` §12「SQLCipher統合方式の検証」への回答案（今回の検証結果を踏まえ、この未決事項をどう解消すべきかの所見）
- 未解決事項（あれば）
