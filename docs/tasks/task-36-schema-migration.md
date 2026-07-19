# task-36: DBスキーママイグレーション機構の整備

> ステータス: 完了（user_version migration runner + v2 archived_at）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

TaskveilのローカルDBはSQLCipherで暗号化されたSQLiteであり、`core/storage/src/schema.sql` を `open_encrypted` 時に `execute_batch` してスキーマを用意している。現状は `PRAGMA user_version` によるスキーマバージョン管理がなく、今後の列追加・削除・データ移行を安全に積み重ねるためのマイグレーション実行機構がない。

2026-07-06人間裁定でDBスキーママイグレーション機構の整備が確定し、2026-07-07の削除モデル裁定（`docs/05_設計判断記録.md` ADR-009、`docs/02_機能仕様書.md` F-07/F-09改訂）により、Phase 1でリストのアーカイブ機能を導入することが決まった。task-37（リストのアーカイブ/解除）は `lists.archived_at` を前提とするため、本タスクでマイグレーション基盤と最初の実マイグレーションを用意する。

本タスクでは現状の `core/storage/src/schema.sql` をbaseline（v1）として扱い、最初の実マイグレーション v2 として `lists` テーブルへ `archived_at INTEGER NULL` を追加する。`docs/03_技術仕様書.md` は技術的な唯一の真実源だが、本タスクでは変更禁止である。実装中に `docs/03_技術仕様書.md` と矛盾する事実や、仕様書へ反映すべき差分を見つけた場合は、仕様書を書き換えず、完了報告の「未解決事項」に記録すること。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`（優先度付きバックログのtask-36/task-37/task-38）
- `docs/02_機能仕様書.md` F-07 / F-09
- `docs/03_技術仕様書.md`（変更禁止。特にローカルDB/SQLCipher/Device Key関連）
- `docs/05_設計判断記録.md` ADR-009
- `docs/design/ui-spec.md` の「裁定済み事項」
- `docs/tasks/task-02-sqlcipher-poc.md`
- `docs/tasks/task-06-storage-repositories.md`
- `docs/tasks/task-07-device-key.md`
- `docs/tasks/task-23-trash-restore-ui.md`
- `docs/tasks/task-35-list-rename.md`
- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`（`init_core` / DB open経路の確認用。原則変更しない）

## 3. ゴール

- `core/storage` に `PRAGMA user_version` ベースのスキーマバージョニングとマイグレーションランナーを整備する。
- 新規DBも既存DBも、DB open時に同じ `v1 -> 最新版` の経路で構築・昇格されるようにする。
- 最初の実マイグレーション v2 として `lists.archived_at INTEGER NULL` を追加し、task-37のアーカイブ実装の前提を作る。
- 誤鍵（SQLCipher鍵不一致）とスキーマ旧版・未対応新版を区別してエラー報告できるようにする。
- 将来の破壊的変更、特にADR-009で予定される `tasks.deleted_at` 廃止に耐える枠組みを用意する。

## 4. スコープ

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- 必要に応じて `core/storage/src/` 配下の新規migration用モジュール/SQLファイル
- `core/storage` のテスト
- `docs/tasks/task-36-schema-migration.md`（完了報告の追記のみ）

`app/rust/src/api.rs`、FRB生成物、Flutter層は原則変更しない。`open_encrypted` のシグネチャやエラー型の変更が `init_core` 経由で自然に伝播せず、FRB/Flutter層の修正が必要になった場合は、実装可否と理由を完了報告の「未解決事項」に記録する。必要最小限の変更を行った場合も、なぜ透過にできなかったかを記録すること。

### やること

1. **スキーマバージョンの定義**:
   - 現状の `schema.sql` をbaseline v1として扱う。
   - 最新スキーマバージョンを定数（例: `LATEST_SCHEMA_VERSION = 2`）として定義する。
   - DBのバージョン判定には `PRAGMA user_version` を使う。
2. **マイグレーションランナー**:
   - `open_encrypted` でSQLCipher鍵を設定した後、DBを読めることを確認し、`user_version` を取得する。
   - `user_version` が最新より古い場合、トランザクション内でマイグレーションを順次適用する。
   - 各バージョン適用後に `PRAGMA user_version = <version>` を同一トランザクション内で更新する。
   - 適用失敗時はロールバックし、DBを途中状態で壊さない。
3. **新規DBと既存DBの同一経路化**:
   - 新規DBも特別分岐で最新スキーマを一括作成せず、baseline v1作成後に v2 以降のマイグレーションを順次適用する。
   - 既存のtask-35以前のDBは `user_version = 0` の可能性がある。空DBならv1を構築してからv2へ進める。既存テーブルがある `user_version = 0` DBは、v1互換スキーマとして扱えるかを確認してからv1相当へ昇格し、その後v2へ進める。
   - 新規/既存でスキーマ定義の到達点が分岐しないようにする。
4. **v2マイグレーション**:
   - v2で `lists` テーブルへ `archived_at INTEGER NULL` を追加する。
   - v2適用後、新規DB・既存v1 DBのどちらでも `PRAGMA table_info(lists)` で `archived_at` が確認できること。
   - 本タスクでは `List` エンティティ、`ListRepository` の読み書き、アーカイブUI/APIは実装しない。列追加のみを行う。
5. **エラー分類**:
   - 誤鍵（SQLCipher鍵不一致または暗号化DBとして読めない状態）と、スキーマ旧版の通常マイグレーション、想定より新しい `user_version` を区別する。
   - `user_version > LATEST_SCHEMA_VERSION` は自動ダウングレードせず、未対応新版として明示的にエラーにする。
   - 秘密情報、SQLCipher鍵、Device Key、導出鍵をエラーメッセージやログへ含めない。
6. **将来変更への枠組み**:
   - v3以降を追加しやすい形で、マイグレーション番号、適用SQL/処理、テスト用の失敗注入を整理する。
   - 将来の `tasks.deleted_at` 廃止のような `DROP COLUMN` 相当の変更に備え、単純な `ALTER TABLE ADD COLUMN` だけに閉じない構造にする（SQLiteのテーブル再作成・データコピー型マイグレーションを追加できる形）。
7. **テスト**:
   - v1 DBからv2へ自動昇格するテストを追加する。
   - 最新版DBを再オープンしても追加変更が走らないことを検証する。
   - 適用途中失敗の擬似ケースでロールバックされ、`user_version` とテーブル定義が途中状態に残らないことを検証する。
   - 新規作成DBがv1 baseline経由で最新版へ到達することを検証する。
   - `user_version` が想定より大きい場合に未対応新版としてエラーになることを検証する。

### やらないこと

- リストのアーカイブ/解除UI、アーカイブ済みリストの分離表示、アーカイブ解除操作（task-37）。
- ゴミ箱撤去、恒久削除導線、削除Undo廃止、`tasks.deleted_at` の廃止実施（task-38）。
- `List` / `ListDto` への `archived_at` 反映、FRB API、Dart provider、Flutter UIの変更。
- `init_core` などFRB/Flutter層の変更。ただし透過にできない技術的理由が判明した場合は、完了報告の「未解決事項」に記録する。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。
- 新規Rust crate / pub packageの追加。
- 同期、サーバー、MCP、CLI、iOS Keychain、通知、設定永続化の実装。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章の事前ファイルを読み、現在の `open_encrypted`、`schema.sql`、storageテストの構造を把握する。
3. `core/storage` 内に、baseline v1とv2以降のマイグレーションを表現する最小構造を設計する。
4. `open_encrypted` で `PRAGMA key` 後にDB可読性確認、`user_version` 取得、マイグレーション実行を行うようにする。
5. 新規DB・legacy `user_version = 0` DB・既存v1 DBの扱いを実装する。
6. v2マイグレーションとして `lists.archived_at INTEGER NULL` 追加を実装する。
7. 誤鍵、未対応新版、マイグレーション失敗、SQLite errorを区別できる `StorageError` を整える。
8. 4章のテスト要件を `core/storage` のテストとして追加する。失敗注入はproduction APIを汚しすぎない範囲で、test-only helperや内部関数のテストで実現してよい。
9. 品質ゲートを実行する。Flutter層を変更していない場合も、共通受け入れ基準に従いRust系ゲートと `git diff --check` は必ず実行する。
10. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `open_encrypted` でDB open時に `PRAGMA user_version` が検査され、古いDBはトランザクション内で最新版まで順次マイグレーションされる。
- [ ] 新規DBもv1 baseline作成後にv2マイグレーションを通り、`user_version = 2` と `lists.archived_at INTEGER NULL` が確認できる。
- [ ] 既存v1 DB相当からの再オープンで自動的にv2へ昇格し、既存のlists/tasksデータが保持される。
- [ ] 最新版DBの再オープンではスキーマ変更が再適用されず、`user_version` とテーブル定義が変化しない。
- [ ] マイグレーション適用途中失敗の擬似ケースでロールバックされ、途中追加カラムや途中更新された `user_version` が残らないことをテストで確認できる。
- [ ] 誤鍵（SQLCipher鍵不一致）と未対応新版（`user_version > LATEST_SCHEMA_VERSION`）が別のエラーとして観測でき、秘密情報をエラーメッセージに含めない。
- [ ] `user_version` が想定より大きいDBを自動ダウングレードせず、明示的なエラーにするテストがある。
- [ ] 将来の `tasks.deleted_at` 廃止のようなテーブル再作成型マイグレーションを追加できる構造になっている。
- [ ] `core/storage` のテストで、v1 DB→v2、自動再オープン、新規作成、途中失敗ロールバック、未対応新版の5ケースが観測可能な証拠として残っている。

## 7. 制約・注意事項

- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更禁止。特に `docs/03_技術仕様書.md` と実装上の事実が矛盾した場合は、仕様書を書き換えず完了報告の「未解決事項」に記録する。
- SQLCipher鍵はDevice Key由来のHKDF（`info=taskveil/local-db-key/v1`）である。この導出文脈文字列や鍵導出仕様を変更しない。
- 誤鍵判定のためにDBを開く際も、鍵・Device Key・導出鍵・DB内容をログやDebug出力に含めない。
- 新規DBと既存DBで別々の最終スキーマ定義を持たない。最終状態の一貫性をテストで確認する。
- `schema.sql` を最新スキーマの一括作成ファイルとして雑に更新するだけで終わらせない。baseline v1とv2以降の差分が実行順として追える形にする。
- FRB/Flutter層は原則変更しない。必要が生じた場合は、変更内容と理由を完了報告の「未解決事項」に記録する。
- アーカイブ列を追加しても、本タスクでは `List` 型やRepository APIの意味論を変更しない。task-37が利用する足場に留める。
- 新規依存は追加しない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 実装したスキーマバージョン定数、baseline v1、v2マイグレーションの内容
- 新規DB、legacy `user_version = 0` DB、既存v1 DB、最新版DB、未対応新版DBの扱い
- 誤鍵とスキーマバージョン系エラーの分類方法
- 途中失敗ロールバックのテスト方法と結果
- 追加/更新した `core/storage` テストの名前と結果
- `PRAGMA user_version` と `PRAGMA table_info(lists)` で確認した証拠
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（`docs/03_技術仕様書.md` との矛盾、FRB/Flutter層へ影響が出た場合の理由、task-37/task-38へ渡す注意点を含む）

## 9. 完了報告

- 作業日: 2026-07-07
- 読んだ/確認したファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/BACKLOG.md`
  - `docs/tasks/task-36-schema-migration.md`
  - `docs/02_機能仕様書.md` F-07 / F-09
  - `docs/03_技術仕様書.md` ローカルDB / SQLCipher / Device Key関連
  - `docs/05_設計判断記録.md` ADR-009
  - `docs/design/ui-spec.md` 裁定済み事項
  - `docs/tasks/task-02-sqlcipher-poc.md`
  - `docs/tasks/task-06-storage-repositories.md`
  - `docs/tasks/task-07-device-key.md`
  - `docs/tasks/task-23-trash-restore-ui.md`
  - `docs/tasks/task-35-list-rename.md`
  - `core/storage/src/schema.sql`
  - `core/storage/src/lib.rs`
  - `app/rust/src/api.rs`
- 実装したスキーマバージョン:
  - `BASELINE_SCHEMA_VERSION = 1`
  - `pub const LATEST_SCHEMA_VERSION: i32 = 2`
  - `core/storage/src/schema.sql` はv1 baselineとして扱い、`archived_at` は追加していない。
  - v2 migration `add_lists_archived_at` で `ALTER TABLE lists ADD COLUMN archived_at INTEGER NULL;` を実行する。
- DB種別ごとの扱い:
  - 新規DB: SQLCipher鍵設定後、v1 baselineを作成し、`user_version = 1` 設定後にv2 migrationを適用して `user_version = 2` にする。
  - legacy `user_version = 0` DB: user tableがある場合はv1 baseline互換の必須table/columnを確認し、互換ならv1相当として `user_version = 1` に昇格後、v2へ進める。
  - 既存v1 DB: `user_version = 1` からv2 migrationを適用する。
  - 最新版DB: `user_version = 2` の場合はmigrationを適用しない。
  - 未対応新版DB: `user_version > LATEST_SCHEMA_VERSION` の場合は自動ダウングレードせず `StorageError::UnsupportedSchemaVersion` を返す。
- エラー分類:
  - 誤鍵またはSQLCipher DBとして読めない状態: `StorageError::InvalidDatabaseKey`
  - 未対応新版: `StorageError::UnsupportedSchemaVersion { found, latest }`
  - baseline v1互換でない `user_version = 0` DB: `StorageError::IncompatibleSchema`
  - migration適用失敗: `StorageError::MigrationFailed { target_version, migration, source }`
  - SQLCipher鍵、Device Key、導出鍵はエラーメッセージへ含めていない。
- 途中失敗ロールバックのテスト方法と結果:
  - `failed_migration_rolls_back_archived_at_and_user_version` で、v1 DBに対して `ALTER TABLE lists ADD COLUMN archived_at INTEGER NULL;` 後に存在しないtableを参照する失敗注入migrationを実行した。
  - 結果: `StorageError::MigrationFailed` を返し、`PRAGMA user_version` は `1` のまま、`PRAGMA table_info(lists)` に `archived_at` は残らなかった。
- 追加/更新した `core/storage` テスト:
  - 更新: `encrypted_database_rejects_wrong_key_on_query` で誤鍵が `StorageError::InvalidDatabaseKey` になることを確認。
  - 追加: `new_database_is_created_via_baseline_and_migrated_to_latest_schema`
  - 追加: `v1_database_migrates_to_v2_and_preserves_existing_data`
  - 追加: `legacy_user_version_zero_v1_database_is_promoted_and_migrated`
  - 追加: `latest_schema_reopen_does_not_reapply_migrations`
  - 追加: `failed_migration_rolls_back_archived_at_and_user_version`
  - 追加: `unsupported_newer_schema_version_is_rejected`
  - `cargo test -p taskveil-storage`: exit 0、20 tests passed
- `PRAGMA` で確認した証拠:
  - 新規DB / v1 DB / legacy `user_version = 0` DBのテストで `PRAGMA user_version = 2` を確認。
  - 新規DB / v1 DB / legacy `user_version = 0` DBのテストで `PRAGMA table_info(lists)` に `archived_at` が存在し、typeが `INTEGER`、notnullが `0` であることを確認。
  - 最新版DB再オープンテストで `PRAGMA schema_version`、`PRAGMA user_version`、`archived_at` column数が再オープン前後で変わらないことを確認。
- 品質ゲートの実行結果:
  - `cargo fmt --all -- --check`: exit 0
  - `cargo clippy --workspace -- -D warnings`: exit 0
  - `cargo test --workspace`: exit 0
  - `cd app && flutter analyze`: exit 1。Flutter SDK cache配下 `engine.stamp.tmp.*` / `engine.realm` への書き込みが `Operation not permitted` で、解析前に停止。
  - `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
  - `cd app && flutter test`: exit 1。Flutter SDK cache配下 `engine.stamp.tmp.*` / `engine.realm` への書き込みが `Operation not permitted` で、テスト実行前に停止。
  - `sh app/tool/check_hardcoded_strings.sh`: exit 0
  - `git diff --check`: exit 0
- 変更ファイル一覧:
  - `core/storage/src/lib.rs`
  - `docs/tasks/task-36-schema-migration.md`
- 未解決事項:
  - `docs/03_技術仕様書.md` の `lists` 定義には `archived_at` が記載されていない。本タスクでは仕様書変更禁止のため未変更。
  - `docs/03_技術仕様書.md` は `tasks.deleted_at` による論理削除/tombstoneを記載しているが、ADR-009では将来migration経由で廃止予定とされている。本タスクでは `tasks.deleted_at` は変更していない。
  - `List` / `ListDto` / `ListRepository` APIには `archived_at` を反映していない。task-37で扱う。
  - FRB/Flutter層は変更していない。`open_encrypted` の公開シグネチャは変更していない。
