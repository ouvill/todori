# task-62: FTS5全文検索の配線

> ステータス: 完了（2026-07-08）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

task-02ではSQLCipher上でFTS5が動作することをPoCとして確認したが、`tasks` 本体と `tasks_fts` の同期、およびアプリ/bridgeから呼び出せる検索APIは未実装のまま残っていた。Phase 3で検索UIを設計する前に、M1-02残課題としてローカルDB上の全文検索インデックスを実データ更新へ追従させる必要がある。

`docs/03_技術仕様書.md` §5.4は、FTS5インデックスもSQLCipher暗号化DBファイル内に閉じる前提を正としている。本タスクではその方針に従い、形態素解析などの追加依存は導入せず、SQLite標準のFTS5 tokenizerで実装する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/03_技術仕様書.md` §5.4、§8.2、§8.3 の検索/FTS5関連記述
- `docs/tasks/task-02-sqlcipher-poc.md` の `## 9. 完了報告`
- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `flutter_rust_bridge.yaml`

## 3. ゴール

- `tasks` の作成・更新・削除が `tasks_fts` に自動反映される。
- `title` / `note` を対象に、storage層から `search_tasks(query)` で全文検索できる。
- bridge層 `api.rs` から `search_tasks(query)` を公開し、FRB生成物へ反映する。
- SQLCipher暗号化DB上でFTS5検索が動作することをテストで確認する。
- 日本語検索について、`unicode61` tokenizerでの挙動と限界を本指示書の完了報告に記録し、Phase 3検索UI設計の入力にする。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/rust/frb_generated.h`
- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `app/lib/src/rust/frb_generated.io.dart`
- `docs/03_技術仕様書.md`（実装と食い違う場合のみ外科的に更新）
- `docs/tasks/task-62-fts5-wiring.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. `tasks_fts` と `tasks` の同期方式を確認し、`docs/03_技術仕様書.md` に明記がなければトリガー方式を採用する。
2. v4マイグレーションでFTS5テーブルを実検索用構造へ再構築し、既存 `tasks` からバックフィルする。
3. `tasks` の `INSERT` / `UPDATE` / `DELETE` に追従するFTS5同期トリガーを作成する。
4. `title` / `note` の変更、`deleted_at` 付き旧論理削除、物理削除、リスト削除に伴うタスク削除で検索結果が更新されることをテストする。
5. storage層に `search_tasks(query)` を追加し、`Task` の一覧を返す。
6. bridge層に `search_tasks(query)` を公開し、`flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
7. 英語・日本語クエリの挙動をテストし、`unicode61` tokenizerの部分一致制約を完了報告へ記録する。
8. 完了時に `docs/tasks/README.md` と `docs/tasks/BACKLOG.md` を更新し、本指示書へ `## 9. 完了報告` を追記する。

### やらないこと

- Flutter検索UIの追加。
- 検索画面、ルーティング、状態管理、ARB文言の追加。
- MeCab等の形態素解析器や外部検索エンジンの導入。
- サーバー同期・MCP・CLIへの検索配線。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. `core/storage/src/lib.rs` の `LATEST_SCHEMA_VERSION` をv4へ上げ、migration配列にFTS5再構築migrationを追加する。
3. migration内で旧 `tasks_fts` をdropし、`task_id UNINDEXED` / `title` / `note` を持つFTS5 tableを作成する。
4. migration内で既存 `tasks` のうち `deleted_at IS NULL` の行を `tasks_fts` へバックフィルする。
5. `tasks` の作成・更新・削除に追従するトリガーを作成する。更新時は古いFTS行を削除してから、`deleted_at IS NULL` の新状態だけを再投入する。
6. `TaskRepository` と `SqliteTaskRepository` に `search_tasks(&self, query: &str)` を追加する。
7. ユーザー入力をそのまま `MATCH` に渡さず、空白区切り語をFTS5 prefix queryへ変換するヘルパーを追加する。空クエリは空配列を返す。
8. `app/rust/src/api.rs` に `pub fn search_tasks(query: String) -> Result<Vec<TaskDto>, String>` を追加する。
9. FRB再生成を実行し、生成物以外を手編集しない。
10. storageテストを追加・更新し、品質ゲートを実行する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `tasks_fts` はv4マイグレーションで実検索用に再構築され、既存 `tasks` からバックフィルされる。
- [ ] `tasks` の作成・`title` / `note` 更新・旧論理削除（`deleted_at`）・物理削除・リスト削除に伴うタスク削除がFTS5検索結果へ反映される。
- [ ] storage層の `search_tasks(query)` が英語クエリと日本語クエリで期待する `Task` を返す。
- [ ] bridge層に `search_tasks(query)` が公開され、FRB生成物が更新されている。
- [ ] SQLCipher暗号化DBを再オープンした後もFTS5検索が動作することをテストで確認している。
- [ ] 日本語検索について、`unicode61` tokenizerで前方一致は可能だが任意部分一致・形態素単位分割はできない等の制約を完了報告に記録している。
- [ ] 検索UI、ARB、画面遷移、状態管理には変更が入っていない。
- [ ] 完了報告に、採用した同期方式、追加したmigration、追加・更新したテスト名、品質ゲート結果、未解決事項を記録している。

## 7. 制約・注意事項

- `docs/03_技術仕様書.md` に同期方式の明記がない場合は、アプリ層更新ではなくDBトリガー方式を採用する。
- `tasks.deleted_at` はADR-009以降のローカル削除では非推奨列だが、移行互換のため残っている。検索では `deleted_at IS NULL` の行だけを対象にする。
- 物理削除は現在のローカル削除の正である。`delete_task` / `delete_list` 経由で削除されたタスクは検索結果に残ってはならない。
- FTS5 tokenizerは追加依存なしの `unicode61` を使う。形態素解析器の導入はPhase 3検索UI設計以降へ送る。
- Rust APIを変更したら、必ず `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
- 生成物（`frb_generated.*`、`app/lib/src/rust/` 配下）は手編集しない。
- UI変更は行わないため、visual QAは退避不要で「UI変更なしのため実行対象外/確認のみ」と完了報告に記録する。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 採用した同期方式（トリガー方式/アプリ層更新）と理由
- v4マイグレーションの内容
- `search_tasks(query)` の検索式生成方針
- 日本語検索の実測挙動と制約（前方一致、任意部分一致、形態素単位検索の可否）
- 追加・更新したテスト名と検証対象
- FRB再生成コマンドと生成物
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-08

### 読んだファイル

- `docs/03_技術仕様書.md` §5.4、§8.2、§8.3
- `docs/tasks/task-02-sqlcipher-poc.md` の `## 9. 完了報告`
- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `flutter_rust_bridge.yaml`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### 実装結果

- `core/storage/src/lib.rs` の `LATEST_SCHEMA_VERSION` を4へ上げ、v4 migration `rebuild_tasks_fts_triggers` を追加した。
- `TaskRepository::search_tasks(&self, query: &str)` と `SqliteTaskRepository` 実装を追加した。
- `app/rust/src/api.rs` に `pub fn search_tasks(query: String) -> Result<Vec<TaskDto>, String>` を追加した。
- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、`app/rust/src/frb_generated.rs`、`app/lib/src/rust/api.dart`、`app/lib/src/rust/frb_generated.dart` を更新した。
- `docs/03_技術仕様書.md` §5.4へ、task-62日付注記付きで同期方式とtokenizer制約を追記した。

### 採用した同期方式

トリガー方式を採用した。`docs/03_技術仕様書.md` に同期方式の明記がなかったため、task指示に従いアプリ層更新ではなくDBトリガーへ寄せた。これにより、`SqliteTaskRepository::insert` / `update` / `delete_subtree` / `SqliteListRepository::delete_with_tasks` のどの経路でもFTS5索引が自動更新される。

### v4マイグレーション

- 旧PoC用 `tasks_fts` をdropし、`task_id UNINDEXED`、`title`、`note`、`tokenize = 'unicode61'` のFTS5 tableとして再作成した。
- 既存 `tasks` のうち `deleted_at IS NULL` の行を `tasks_fts` へバックフィルした。
- `tasks_fts_ai`: `tasks` INSERT時に `deleted_at IS NULL` の行だけを追加する。
- `tasks_fts_au`: `tasks` UPDATE時に旧FTS行を削除し、`deleted_at IS NULL` の新状態だけを再投入する。
- `tasks_fts_ad`: `tasks` DELETE時に対応FTS行を削除する。

### 検索式生成方針

`search_tasks(query)` は空白区切りの各語を `"<term>"*` へ変換し、複数語は `AND` で結合する。空または空白のみのqueryは空配列を返す。`MATCH` へユーザー入力をそのまま渡さないため、通常のクォート文字はエスケープされる。

### 日本語検索の挙動と制約

- `unicode61` tokenizerでは、`牛乳を買う` のような空白なし日本語文字列は概ね連続トークンとして扱われる。
- API側で前方一致queryへ変換するため、`牛乳` は `牛乳を買う` にヒットする。
- 任意部分一致はできないため、`乳` は `牛乳を買う` にヒットしない。
- 形態素解析は導入していないため、語境界を日本語の意味単位で分割する検索はできない。この制約はPhase 3検索UI設計時の入力とする。

### 追加・更新したテスト

- `fts5_search_matches_title_and_note`: insert後にtitle/note双方が検索でき、空queryが空結果になることを確認。
- `fts5_search_tracks_title_note_updates_and_deleted_at`: title/note更新、旧論理削除、復帰がFTS結果へ反映されることを確認。
- `fts5_search_tracks_physical_task_and_list_deletes`: `delete_subtree` と `delete_with_tasks` による物理削除がFTS結果へ反映されることを確認。
- `fts5_search_supports_english_and_japanese_prefix_queries`: 英語query、日本語前方一致、任意部分一致不可を確認。
- `v3_database_migrates_to_v4_and_backfills_tasks_fts`: v3 DBからv4へ移行し、既存taskがFTSへバックフィルされることを確認。
- `fts5_search_works_after_reopening_encrypted_database`: SQLCipher暗号化DBを再オープンした後も検索できることを確認。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter analyze`: 成功。
- `cd app && flutter test`: 成功（101 tests passed、visual QA harness 1件skip）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `cd app && sh tool/visual_qa.sh`: 成功（37 tests passed）。UI変更なしのため退避なしで確認した。
- `git diff --check`: 成功。

### 変更ファイル

- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `docs/03_技術仕様書.md`
- `docs/tasks/task-62-fts5-wiring.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### 未解決事項

なし。
