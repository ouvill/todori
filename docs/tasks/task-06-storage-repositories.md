# task-06: `core/storage` のリストテーブル追加とリポジトリ実装

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` のマイルストーンM1「コア層完成」は、M1-02「SQLCipherスキーマをPhase 1対象テーブルへ拡張する」とM1-03「リスト/タスク/ゴミ箱/Undo用repositoryを実装する」を定義している。このタスクは両方に対応する。

task-02のSQLCipher PoCにより、`core/storage` には `open_encrypted`（SQLCipherで暗号化されたSQLite接続を開く）、`tasks` テーブルと `tasks_fts`（FTS5仮想テーブル）のスキーマ、`TaskRepository` trait と `SqliteTaskRepository::insert` / `get` が実装済みである。ただし `TaskRepository::update` は `StorageError::NotImplemented` を返すのみで未実装であり、`lists` テーブルおよび `ListRepository` はまだ存在しない。

task-05では `core/domain` に、DBにもファイルシステムにも依存しない純粋なユースケース関数（`new_task` / `new_list` / `update_title` / `transition_task` / `delete_task` / `restore_task` / `rename_list` / `validate_parent` 等）が実装済みである。しかし、これらのユースケースが返す `Task` / `List` の値を実際にDBへ永続化する経路は未接続のままである。

本タスクは、`core/storage` のスキーマとリポジトリ実装を拡張し、`core/domain` のユースケースとSQLCipher暗号化DBを接続することがゴールである。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` §3.5（lists）/ §3.6（tasks。特に `parent_task_id` による自己参照と `deleted_at` の論理削除・tombstoneの意味論）、§5（ローカルストレージ）
- `core/storage/src/lib.rs`（`open_encrypted` / `StorageError` / `TaskRepository` trait / `SqliteTaskRepository` の `insert` / `get` 実装済み部分、`row_to_task` 等の既存ヘルパー）
- `core/storage/src/schema.sql`（現行の `tasks` テーブルと `tasks_fts` 仮想テーブルの定義）
- `core/domain/src/usecases.rs`（`new_list` / `new_task` / `update_title` / `transition_task` / `delete_task` / `restore_task` 等の実装済みユースケース。論理削除は `deleted_at` フィールドの更新のみで表現され、物理削除は行わない）
- `docs/07_Phase1計画書.md` M1（本タスクが対応するM1-02・M1-03と、他マイルストーンとの切り分け）

## 3. ゴール

`core/storage` に `lists` テーブルを追加し、`ListRepository` trait とSQLite実装を新規作成する。あわせて `TaskRepository::update` を本実装し、ゴミ箱・アクティブ一覧取得用のクエリメソッドを追加する。`core/domain` のユースケースが返す値をSQLCipher暗号化DBへ実際に永続化できることを、統合テストで実証する。`cargo test --workspace` で緑になること。

## 4. スコープ

### やること

1. **スキーマ拡張**: `core/storage/src/schema.sql` に `lists` テーブルを追加する。§3.5準拠で、`id` / `name` / `color` / `icon` はTEXT、`org_id` はTEXT nullable、`sort_order` はTEXT、`created_at` / `updated_at` はINTEGERとする（既存 `tasks` テーブルの型親和性の流儀に合わせる）。あわせて基本インデックスを追加する: `tasks(list_id)`、`tasks(parent_task_id)`、`tasks(deleted_at)`、`lists(sort_order)`（いずれも `CREATE INDEX IF NOT EXISTS`）。既存の `tasks` / `tasks_fts` 定義は変更しないこと。

2. **`ListRepository` trait とSQLite実装**: `core/storage/src/lib.rs` に `ListRepository` trait を新規定義し、`insert` / `get` / `update`（全フィールドUPDATE。対象0行の場合は `StorageError::NotFound` を返す。現行の `NotFound(Uuid)` バリアントを流用してよい）/ `list_all`（`sort_order` 昇順ですべてのリストを返す）を実装する。SQLite実装型は `SqliteListRepository` とし、`SqliteTaskRepository` の構造（`Connection` を保持し `new` / `connection` を持つ）に倣うこと。

3. **`TaskRepository::update` の本実装**: 現在 `StorageError::NotImplemented` を返すのみの `update` を、全フィールドを対象とするUPDATE文として実装する。対象行が存在しない（affected row数が0）場合は `StorageError::NotFound` を返す。これにより、`core/domain` のユースケース（編集・ステータス遷移・論理削除・復元）が返す `Task` の値をそのまま永続化できるようにする。

4. **クエリメソッド追加**: `TaskRepository` trait に以下の2つのメソッドを追加し、`SqliteTaskRepository` に実装する。
   - `list_active_by_list(&self, list_id: Uuid) -> Result<Vec<Task>, StorageError>`: 指定リスト内の `deleted_at IS NULL` なタスクを `sort_order` 昇順で返す。
   - `list_trashed(&self) -> Result<Vec<Task>, StorageError>`: `deleted_at IS NOT NULL` なタスクを全リスト横断で `deleted_at` 降順で返す（ゴミ箱一覧を想定）。

5. **統合テスト**（`core/storage` 内、`#[cfg(test)]` モジュールに追加。暗号化DBは `open_encrypted` を使用し、`tempfile::NamedTempFile` で分離すること。`tempfile` は既存の dev-dependency である）。少なくとも以下を含めること。
   - (1) `SqliteListRepository` の `insert` → `get` → `update` → `get` のroundtripが成立すること。`list_all` が複数リストを `sort_order` 昇順で返すこと。
   - (2) `todori_domain::usecases` と接続した一気通貫テスト: `new_list` で作成したリストを `ListRepository::insert`、`new_task` で作成したタスクを `TaskRepository::insert` し、`update_title` / `transition_task`（`Done` への遷移）の結果を `TaskRepository::update` で永続化したのち、DBを再オープンしてもその変更が反映されていること。
   - (3) ゴミ箱・Undo: `delete_task` の結果を `update` で永続化したタスクが `list_trashed` に現れ、かつ `list_active_by_list` から消えること。続けて `restore_task` の結果を `update` で永続化すると、`list_active_by_list` に戻り `list_trashed` から消えること。
   - (4) 存在しないIDに対する `update` が、task・list双方について `StorageError::NotFound` を返すこと。
   - (5) 既存テスト（誤鍵での再オープン失敗、平文SQLiteとしての読み取り不可、FTS5マッチ、`SqliteTaskRepository` のinsert/getラウンドトリップ）が変更後も引き続きすべて成功すること。

6. `StorageError::NotImplemented` バリアントについて、`update` の本実装後に使用箇所がなくなる場合は削除する。他の箇所で使用が残る場合はそのまま残す（削除するか残すかを完了報告に明記すること）。

### やらないこと

- FTS5と `tasks` 本体の同期トリガー（`tasks` へのinsert/update時に `tasks_fts` を自動更新する仕組み）の実装。これは検索機能を扱う別タスクの範囲とする。
- スキーママイグレーション機構（バージョン管理、`ALTER TABLE` による段階的移行等）の実装。本タスクは `CREATE TABLE IF NOT EXISTS` による初期スキーマの拡張のみを行う。
- `core/crypto` とのDK（Device Key）接続、SQLCipher鍵導出の実装（Phase1計画書M1-04の範囲）。
- `app/` およびFlutterブリッジ（`flutter_rust_bridge`）まわりの変更。
- 新規依存クレートの追加。特に**ネットワークアクセスを要する新規クレートの追加は禁止**する。`rusqlite` / `hex` / `tempfile` / `todori-domain` は既存依存を再利用すること。本タスクの実行環境はネットワークアクセス不可であるため、crates.ioからの新規取得が発生する変更を行ってはならない。
- `docs/01〜04` および `docs/07_Phase1計画書.md` の変更。

## 5. 実装手順（例）

1. `core/storage/src/schema.sql` を再読し、既存 `tasks` / `tasks_fts` 定義の型親和性の流儀（TEXT/INTEGERの使い分け）を把握したうえで `lists` テーブルとインデックス群を追記する。
2. `core/storage/src/lib.rs` に `ListRepository` trait を定義し、`SqliteListRepository` の `insert` / `get` を `SqliteTaskRepository` の対応するメソッドと同じ書き方（`params!` マクロ、`query_row` + `OptionalExtension`）で実装する。
3. `list_all` を実装する（`sort_order` 昇順の `SELECT` と `query_map`）。
4. `SqliteListRepository::update` を実装し、対象0行時に `StorageError::NotFound` を返すことを `execute` の戻り値（affected row数）で判定する。
5. `TaskRepository::update` の本実装を、3.と同様の方針で行う。
6. `TaskRepository::list_active_by_list` / `list_trashed` を追加する。
7. `core/domain::usecases` を `dev-dependencies` からではなく通常の `todori-domain` 依存（既存）経由で使い、統合テストを書く。テストは `core/storage/src/lib.rs` の既存 `#[cfg(test)] mod tests` に追記する形でよい。
8. `cargo test -p todori-storage` を繰り返し実行しながら実装する。
9. `StorageError::NotImplemented` の使用箇所を確認し、不要なら削除する。
10. 最後に `cargo fmt --all`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace` を実行し全体の品質ゲートを確認する。

## 6. 受け入れ基準

- [ ] `cargo fmt --all -- --check` が差分なしで通過する
- [ ] `cargo clippy --workspace -- -D warnings` が警告ゼロで通過する
- [ ] `cargo test --workspace` が全テスト成功する（既存の `core/storage` / `core/domain` のテストも含めすべて成功すること）
- [ ] `cargo test -p todori-storage` で本タスクの新規テストがすべて実行され成功する
- [ ] 4.の5.に列挙した統合テスト(1)〜(5)がすべて実装され成功する

## 7. 制約・注意事項

- `open_encrypted` の公開シグネチャ、および既存の `SqliteTaskRepository::insert` / `get` の公開シグネチャを壊さないこと（`TaskRepository` traitへのメソッド追加は可）。
- `row_to_task` 等の既存ヘルパー関数は可能な限り再利用すること。
- テストごとに `tempfile::NamedTempFile` で新規DBファイルを用意し、他のテストと状態を共有しないこと。
- 仕様書（`docs/03_技術仕様書.md`）の記述だけでは一意に決まらない実装判断（インデックス設計の粒度、`update` のUPDATE対象カラムの取捨等）が生じた場合は、独断で仕様書側を変更せず、完了報告の「未解決事項」に記録すること（`docs/tasks/README.md` 共通規約6.）。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` / `docs/04_課金設計書.md` / `docs/07_Phase1計画書.md` は変更しないこと。

## 8. 完了報告に含めるべき内容

- 追加・変更した公開API（trait・メソッド・型）の一覧
- スキーマ変更内容（追加テーブル・インデックスの一覧）
- `StorageError::NotImplemented` バリアントを削除したか残したか、その理由
- 追加した統合テストの総数と、4.の5.に列挙した(1)〜(5)がすべて含まれていることの確認
- 未解決事項（あれば）

## 9. 完了報告

作業日: 2026-07-04

### 実装結果

- `core/storage/src/schema.sql` に `lists` tableと基本インデックスを追加した。既存の `tasks` / `tasks_fts` 定義は変更していない。
- `core/storage/src/lib.rs` に `ListRepository` traitと `SqliteListRepository` を追加した。
- `TaskRepository::update` を全フィールド更新のSQLite実装に置き換えた。
- `TaskRepository` にアクティブ一覧・ゴミ箱一覧のクエリメソッドを追加した。
- `StorageError::NotFound(Uuid)` はtask/list双方の0行更新・未検出に共通利用するため、表示文言を `record not found` に変更した。

### 追加・変更した公開API

- 追加した公開trait: `ListRepository`
- 追加した公開型: `SqliteListRepository`
- `ListRepository` の公開メソッド: `get` / `insert` / `update` / `list_all`
- `SqliteListRepository` の公開メソッド: `new` / `connection`
- `TaskRepository` に追加した公開メソッド: `list_active_by_list` / `list_trashed`
- 本実装化した公開メソッド: `TaskRepository::update`（`SqliteTaskRepository` 実装）

### スキーマ変更

- 追加テーブル: `lists`
  - `id` / `name` / `color` / `icon` / `sort_order` は `TEXT`
  - `org_id` は nullable `TEXT`
  - `created_at` / `updated_at` は `INTEGER`
- 追加インデックス:
  - `idx_tasks_list_id` on `tasks(list_id)`
  - `idx_tasks_parent_task_id` on `tasks(parent_task_id)`
  - `idx_tasks_deleted_at` on `tasks(deleted_at)`
  - `idx_lists_sort_order` on `lists(sort_order)`

### `StorageError::NotImplemented`

- `TaskRepository::update` の本実装後に使用箇所がなくなったため、`StorageError::NotImplemented` バリアントは削除した。

### テスト

- `core/storage/src/lib.rs` に統合テストを4件追加した。
- 4.の5.に列挙された(1)〜(4)は、`SqliteListRepository` roundtrip/list_all、domain usecases連携、ゴミ箱・Undo、task/list双方のNotFound更新として追加テストで網羅した。
- 4.の5.の(5)は、既存の誤鍵再オープン失敗、平文SQLite読み取り不可、FTS5マッチ、`SqliteTaskRepository` insert/get roundtripテストがすべて引き続き成功することを確認した。

### 検証

- `cargo test -p todori-storage` 成功（9 tests）。
- `cargo fmt --all -- --check` 成功。
- `cargo clippy --workspace -- -D warnings` 成功。
- `cargo test --workspace` 成功。

### 未解決事項

- なし。
