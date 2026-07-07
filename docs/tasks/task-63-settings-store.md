# task-63: 設定値の永続化機構とF-01 UIモード保存口

> ステータス: 完了（2026-07-08）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

Phase 1計画書では、F-01「初回起動時のUIモード選択」について、切替UIやオンボーディング本体は後続フェーズへ送りつつ、設定値の保存口だけを先に用意する方針としている。通知設定、テーマ設定、UIモードなど、今後のアプリ設定はSQLCipherで暗号化されたローカルDB内へ一貫して保存できる必要がある。

本タスクでは汎用的な設定key/valueテーブルをstorage層へ追加し、bridge/Dart providerから読み書きできる最小の永続化口を実装する。F-01用には `ui_mode` キーを予約し、未設定時に `simple` を返すDart側helperを提供する。UIモード選択画面・切替UIは作らない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/02_機能仕様書.md` F-01
- `docs/03_技術仕様書.md` のデータモデル/ローカルDBスキーマ節
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`

## 3. ゴール

- SQLCipher暗号化DB内に `settings` テーブルをv5マイグレーションで追加する。
- storage層に `get_setting` / `set_setting` を追加し、未設定・保存・上書き・migration昇格をテストする。
- bridge層に `get_setting` / `set_setting` を公開し、FRB生成物へ反映する。
- Dart側に今後の設定の共通口となる薄い `SettingsRepository` providerを追加する。
- F-01用の `ui_mode` キーを予約し、未設定時に `simple` を返すDart helperを追加する。
- `docs/03_技術仕様書.md` のスキーマ節へ `settings` とv5を日付注記付きで追記する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/` 配下の関連テスト
- `docs/03_技術仕様書.md`
- `docs/tasks/task-63-settings-store.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. `core/storage` の `LATEST_SCHEMA_VERSION` を5へ上げ、v5 migrationで `settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)` を作成する。
2. storage層に設定値用repositoryを追加し、`get_setting(key)` と `set_setting(key, value, updated_at)` を実装する。
3. storageテストでroundtrip、上書き、未設定時None、v4からv5へのmigration昇格を確認する。
4. `app/rust/src/api.rs` から `get_setting(key)` / `set_setting(key, value)` を公開する。`updated_at` はbridge側で現在時刻を入れる。
5. `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、生成物を更新する。
6. `BridgeService` / `FrbBridgeService` / `FakeBridgeService` へsettings APIを追加する。
7. `SettingsRepository` providerと `ui_mode` helper/providerをDart側へ追加する。未設定時の既定値は `simple` とする。
8. `docs/03_技術仕様書.md`、`docs/tasks/README.md`、`docs/tasks/BACKLOG.md` を更新し、本指示書へ完了報告を追記する。

### やらないこと

- UIモード選択画面、初回オンボーディング、設定画面の追加。
- UIモードに応じた画面分岐やルーティング変更。
- 通知設定、テーマ設定、アカウント設定の具体キー追加。
- サーバー同期、MCP、CLIへのsettings配線。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. `core/storage/src/lib.rs` のmigration配列へv5 `add_settings` を追加する。
3. `SettingsRepository` traitと `SqliteSettingsRepository` を追加し、`settings` tableへupsertする。
4. 既存migrationテストヘルパーにv4 DB作成関数を追加し、v5昇格テストを書く。
5. `app/rust/src/api.rs` にsettings APIと `with_settings_repository` を追加する。
6. FRB再生成を実行し、生成物を手編集しない。
7. Dartの `BridgeService` 抽象とFakeにsettings APIを追加する。
8. `providers.dart` に `SettingsRepository`、`uiModeProvider`、`uiModeSettingKey`、`defaultUiMode` を追加する。
9. Rust/Flutterのテストを追加し、品質ゲートを実行する。
10. 完了時にREADME/BACKLOG/本指示書の完了報告を更新する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] v5 migrationで `settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)` が作成される。
- [ ] storage層の `get_setting` / `set_setting` がroundtrip、上書き、未設定時Noneをテストで確認されている。
- [ ] v4 DBを開いたときにv5へ昇格し、`settings` テーブルが利用可能になることをテストで確認している。
- [ ] bridge層に `get_setting` / `set_setting` が公開され、FRB生成物が更新されている。
- [ ] Dart側に今後の設定共通口として使える薄い `SettingsRepository` providerがある。
- [ ] `ui_mode` キーが予約され、未設定時に `simple` を返すDart helper/providerがある。
- [ ] UIモード選択画面・切替UI・ルーティング変更は追加されていない。
- [ ] 完了報告に、スキーマ、API、追加テスト、品質ゲート結果、未解決事項を記録している。

## 7. 制約・注意事項

- `settings` はローカルDBファイル内の平文カラムだが、SQLCipherページ暗号化によりファイル全体として保護される。秘密情報そのものをログやDebug出力へ出してはならない。
- 設定値の同期設計はPhase 2以降で扱う。本タスクではローカル永続化のみを対象にする。
- `ui_mode` の有効値はDart helper側で `simple` / `advanced` として扱う。storage層は汎用key/valueとして、キー固有の意味論を持たない。
- Rust APIを変更したら、必ずFRB再生成を実行する。
- 生成物（`frb_generated.*`、`app/lib/src/rust/` 配下）は手編集しない。
- UI文字列を追加しないためARB変更は不要である。
- `docs/03_技術仕様書.md` の変更は、2026-07-08の編集承認に基づく外科的差分に限る。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- v5スキーマとmigration内容
- storage/bridge/Dart APIの追加内容
- `ui_mode` helperの既定値と有効値
- 追加・更新したテスト名と検証対象
- FRB再生成コマンドと生成物
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-08

### 読んだファイル

- `docs/02_機能仕様書.md` F-01
- `docs/03_技術仕様書.md` のデータモデル/ローカルDBスキーマ節
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### 実装結果

- `core/storage/src/lib.rs` の `LATEST_SCHEMA_VERSION` を5へ上げ、v5 migration `add_settings` を追加した。
- `SettingsRepository` traitと `SqliteSettingsRepository` を追加し、`get_setting` / `set_setting` を実装した。
- `app/rust/src/api.rs` に `get_setting(key)` / `set_setting(key, value)` を公開し、`set_setting` の `updated_at` はbridge側の現在時刻で記録する形にした。
- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、`app/rust/src/frb_generated.rs`、`app/lib/src/rust/api.dart`、`app/lib/src/rust/frb_generated.dart` を更新した。
- Dart側の `BridgeService` / `FrbBridgeService` / `FakeBridgeService` にsettings APIを追加した。
- `app/lib/src/core/providers.dart` に `SettingsRepository`、`settingsRepositoryProvider`、`uiModeProvider`、`uiModeSettingKey`、`defaultUiMode` を追加した。
- `docs/03_技術仕様書.md` のスキーマ節へ `settings` テーブル、v5、`ui_mode` 予約キーを2026-07-08注記付きで追記した。
- `docs/tasks/README.md` と `docs/tasks/BACKLOG.md` を更新し、task-63を完了扱いにした。

### v5スキーマ

```sql
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
```

`settings` はSQLCipher暗号化DB内のローカルkey/valueストアであり、storage層はキー固有の意味論を持たない。`set_setting` は同一キーを `ON CONFLICT(key) DO UPDATE` で上書きする。

### API

- storage: `SettingsRepository::get_setting(&self, key) -> Result<Option<String>, StorageError>`
- storage: `SettingsRepository::set_setting(&mut self, key, value, updated_at) -> Result<(), StorageError>`
- bridge/FRB: `getSetting({required String key}) -> Future<String?>`
- bridge/FRB: `setSetting({required String key, required String value}) -> Future<void>`
- Dart provider: `SettingsRepository.getSetting` / `setSetting` / `getUiMode` / `setUiMode`

### ui_mode helper

- 予約キー: `ui_mode`
- 既定値: `simple`
- 有効値: `simple` / `advanced`
- 未設定時または未知値保存時は `getUiMode()` が `simple` を返す。
- UIモード選択画面、切替UI、ルーティング分岐は追加していない。

### 追加・更新したテスト

- `sqlite_settings_repository_returns_none_for_missing_key`: 未設定時に `None` を返すことを確認。
- `sqlite_settings_repository_roundtrips_setting`: `set_setting` 後に同じ値を取得できることを確認。
- `sqlite_settings_repository_overwrites_existing_setting`: 同一キーの上書きと `updated_at` 更新を確認。
- `v4_database_migrates_to_v5_and_adds_settings_table`: v4 DBを開くとv5へ昇格し、`settings` テーブルが追加されることを確認。
- `settings roundtrip through Rust bridge`: FRB経由の `setSetting` / `getSetting` 往復、上書き、未設定時nullを確認。
- `uiModeProvider defaults to simple when unset`: Dart providerが未設定時 `simple` を返すことを確認。
- `uiModeProvider persists and reloads reserved ui_mode setting`: `ui_mode` 保存とprovider再読込を確認。
- `SettingsRepository rejects unsupported UI modes`: 未対応UIモード値の拒否を確認。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter analyze`: 成功。
- `cd app && flutter test`: 成功（105 passed、visual QA harness 1件skip）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git diff --check`: 成功。

### 変更ファイル

- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/test/core_usecases_test.dart`
- `app/test/settings_provider_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `docs/03_技術仕様書.md`
- `docs/tasks/task-63-settings-store.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### 未解決事項

なし。
