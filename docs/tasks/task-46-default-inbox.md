# task-46: 既定Inboxの自動プロビジョニングと永続識別

## 1. 背景とコンテキスト

`docs/02_機能仕様書.md` F-09は、初期状態で「インボックス」リストがデフォルトとして用意され、リスト未指定タスクの受け皿になることを要求している。

現状のTodoriは、起動直後のHomeで `lists.first` を開き、既定リスト保護も `sort_order` の先頭リストを「default inbox」と見なしている。これはドッグフーディング2026-07-07#2 項目3で確認された設計負債であり、リスト並び順や将来のTodayスマートリスト化と衝突する。

本タスクでは、既定リストの暫定識別（`sort_order` 先頭）を永続識別（`lists.is_default`）へ置き換える。あわせて、空DBまたは既定リスト欠損DBを開いたとき、UIロケールに応じた名前のInboxを自動作成する。

`docs/03_技術仕様書.md` は技術的な唯一の真実源だが、現時点のスキーマ表には `lists.is_default` がない。本タスクでは `docs/03_技術仕様書.md` を変更しない。完了報告の未解決事項に、`docs/03` への `is_default` 追記が必要であることを記録する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/02_機能仕様書.md` F-09
- `docs/03_技術仕様書.md`（変更禁止。特にlists/tasks schema、SQLCipher、Device Key関連）
- `docs/tasks/task-36-schema-migration.md`
- `core/storage/src/lib.rs`（`LATEST_SCHEMA_VERSION`、migration runner、`ListRepository`）
- `core/storage/src/schema.sql`
- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `app/rust/src/api.rs`（`init_core` / `create_list` / `get_lists` / `archive_list` / `delete_list` / `undo_task_operation`）
- `app/lib/main.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/home_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/core_usecases_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`

## 3. ゴール

- v3マイグレーションで `lists.is_default INTEGER NOT NULL DEFAULT 0` を追加する。
- 既存DBでは、`sort_order` 最小の非アーカイブリストを1件だけ `is_default = 1` へ昇格する。リストが0件、または非アーカイブリストが0件ならデータマイグレーションは何もしない。
- DB初期化時に `is_default = 1` のリストが存在しない場合、UIロケール由来の名前でInboxを `is_default = 1` として自動作成する。
- 既定リストの削除・アーカイブ不可、Homeの対象リスト、復元/Undo/remap先など、これまで `sort_order` 先頭を既定扱いしていた箇所をすべて `is_default` 参照へ置き換える。
- 既定リストの改名は引き続き許可する。
- `ListDto` に `isDefault` を追加し、FRB生成物、Dart bridge、FakeBridgeService、widget/visual QAを追随させる。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/rust/src/api.rs`
- `flutter_rust_bridge.yaml` は原則変更しない
- FRB生成物（`app/lib/src/rust/`、`app/rust/src/frb_generated.*` 等）
- `app/lib/main.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（`flutter gen-l10n` 生成差分のみ）
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/home_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/core_usecases_test.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-46-default-inbox.md`（完了報告の追記のみ）

### やること

1. **v3マイグレーションを追加する**
   - `LATEST_SCHEMA_VERSION` を3へ上げ、task-36のmigration runnerへ `target_version = 3` を追加する。
   - `lists.is_default INTEGER NOT NULL DEFAULT 0` を追加する。
   - 同一トランザクション内で、既存DBの `sort_order` 最小の非アーカイブリスト1件を `is_default = 1` にする。順序のtie-breakerは `sort_order ASC, created_at ASC, id ASC` のように決定的にする。
   - `is_default = 1` が複数作れないよう、storage層で不変条件を持たせる。SQLiteのpartial unique indexを使う場合は、migrationとschema到達点の整合をテストする。
2. **domain/storageへ `is_default` を通す**
   - `todori_domain::List` に `is_default: bool` を追加する。
   - 通常の `new_list` は `is_default = false` とし、既定リスト作成用は専用helperまたは明示引数で `true` を設定する。
   - `SqliteListRepository` のSELECT/INSERT/UPDATE/row mappingを更新する。
   - 必要に応じて `ListRepository` に `get_default` / `ensure_default_list` 相当の最小APIを追加する。
3. **Inbox自動プロビジョニングを実装する**
   - `init_core` は `default_inbox_name` を引数として受け取る。Rust側に `"Inbox"` / `"インボックス"` をハードコードしない。
   - DB open後、`is_default = 1` のリストが存在しない場合、`default_inbox_name` で `is_default = 1` のリストを作成する。リストが0件の空DBでもHome表示前に作成されること。
   - 作成時の `sort_order` は既存の暫定規則と衝突しない値でよいが、既定判定には使わない。
   - 既に `is_default = 1` が存在する場合は、名前をロケールで上書きしない。ユーザーによる改名を尊重する。
4. **DartからUIロケール由来の名前を渡す**
   - ARBに `defaultInboxName` を追加する（en: `Inbox`、ja: `インボックス`）。
   - `main.dart` で起動時ロケールを解決し、`lookupAppLocalizations(locale).defaultInboxName` から得た文字列を `initCore(dbDir: ..., defaultInboxName: ...)` へ渡す。
   - `MaterialApp` 構築前なので、`BuildContext` 依存の `AppLocalizations.of(context)` は使えない。`PlatformDispatcher.instance.locale` と `AppLocalizations.supportedLocales` でサポート外localeをfallbackさせる。
   - Dart本体にUI文字列としての `"Inbox"` / `"インボックス"` を直書きしない。テストseedや期待値で必要な文字列は、テスト内のfixtureとして扱ってよい。
5. **既定リスト参照を `is_default` へ置き換える**
   - `ListDto` に `is_default` を追加し、FRB再生成後のDartでは `isDefault` を使う。
   - `home_screen.dart` は `lists.first` ではなく、active lists内の `isDefault` リストを開く。欠損時のfallbackはエラー/空状態ではなく、プロビジョニング漏れが分かる形にする。
   - `tasks_screen.dart` の `isDefaultInbox` 判定、`archive_list` / `delete_list` の保護、FakeBridgeServiceの保護をすべて `isDefault` 参照へ置き換える。
   - `grep -RIn "defaultInbox\\|default inbox\\|is_default_inbox\\|lists\\.first\\|first\\.id\\|list_all().*first" app/lib app/test app/rust core` 等で、既定リスト判定としての先頭ルールが残っていないことを確認する。単なる並び順処理やテストfixtureの `first` は理由を完了報告に書く。
6. **復元/Undo/remap先を確認する**
   - 現行コードで「復元時に元リストがない場合は先頭リストへ入れる」等のremap経路が残っている場合、`is_default = 1` のリストへ置き換える。
   - 現行仕様で該当経路が削除済みの場合も、`undo_task_operation`、FakeBridgeService、旧trash/restore由来の残存コードをgrepし、既定リストremapが存在しないことをテストまたは完了報告で説明する。
7. **テストとvisual QAを更新する**
   - `core/storage` に v2->v3昇格、空DBプロビジョニング、既定リスト保護、複数default防止のテストを追加する。
   - `app/test/core_usecases_test.dart` で `initCore` の新引数、`getLists()` の `isDefault`、既定リストの改名許可・アーカイブ/削除拒否を確認する。
   - en/ja名の自動作成は、FRBの `OnceLock` 制約で同一process内に複数 `initCore` を置けない場合、storage/helper単位のRustテストで2言語分を検証してよい。その場合は理由を完了報告に書く。
   - widget testとvisual QAで、初回起動相当でもHomeが空リスト状態ではなくInboxのTasks画面を表示することを確認する。既存の「リストなし空状態」テストは新挙動へ合わせて更新または削除する。

### やらないこと

- Todayスマートリスト化（task-47）。
- リスト一覧の並び順変更。
- リストの型（プロジェクト型/エリア型）導入。
- `sort_order` のfractional index本実装やリスト並び替えUI。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。
- 新規Rust crate / pub packageの追加。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章の事前ファイルを読み、現在のmigration runner、`List` / `ListDto` / `FakeBridgeService`、Homeの `lists.first` 前提、`is_default_inbox` の先頭リスト判定を把握する。
3. `core/storage` にv3 migrationを追加し、`user_version = 3`、`lists.is_default`、既存非アーカイブ先頭リストの昇格をテストする。
4. `List` / `ListRepository` / `new_list` / 既定リスト作成helperを更新し、通常作成と既定作成の意味を分ける。
5. `init_core` に `default_inbox_name` 引数を追加し、DB open後に既定リストをensureする。
6. ARBに `defaultInboxName` を追加し、`flutter gen-l10n` を実行する。
7. `main.dart` で起動時localeから `defaultInboxName` を取得し、`initCore` へ渡す。
8. `app/rust/src/api.rs` の公開API変更後、リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
9. Dart bridge、providers、Home、Tasks、FakeBridgeService、テストを `isDefault` へ追随させる。
10. 先頭リスト既定ルールの残存grepを実行し、残る `first` / `sortOrder` が並び順やfixture用途だけであることを確認する。
11. 品質ゲートを実行する。Flutter変更があるため、FRB release build後の `flutter test` と直書き文字列チェックまで通す。
12. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] v3 migrationで `lists.is_default INTEGER NOT NULL DEFAULT 0` が追加され、`PRAGMA user_version = 3` と `PRAGMA table_info(lists)` で確認できる。
- [ ] v2相当DBでは、`sort_order` 最小の非アーカイブリスト1件だけが `is_default = 1` へ昇格し、リスト0件または非アーカイブ0件では昇格がno-opになる。
- [ ] 空DBまたは既定リスト欠損DBの初期化で、渡された `default_inbox_name` のリストが `is_default = 1` として自動作成され、en名 `Inbox` とja名 `インボックス` の両方がテストで観測できる。
- [ ] `List` / `ListDto` / FRB生成物 / Dart `BridgeService` / `FakeBridgeService` が `isDefault` を保持し、通常の `createList` は `isDefault = false` になる。
- [ ] Home対象リスト、Tasks画面の既定リスト判定、アーカイブ不可・削除不可保護が `sort_order` 先頭ではなく `isDefault` 参照で動く。
- [ ] 既定リストの改名は成功し、改名後も `isDefault = true` が維持される。
- [ ] 復元/Undo/remap経路に既定リスト参照が残る場合は `isDefault` を使い、該当経路が現行仕様で存在しない場合はgrep結果またはテストでその事実を説明できる。
- [ ] 既定リスト判定としての `lists.first` / `activeLists.first` / `is_default_inbox` / `sort_order` 先頭ルールが残っていないことをgrep結果で確認している。
- [ ] widget test / visual QAで、初回起動相当でもHomeが「リストなし空状態」ではなくInboxのTasks画面を表示する証拠が残っている。

## 7. 制約・注意事項

- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更禁止。`docs/03` の `lists` 定義に `is_default` がない点は完了報告の未解決事項へ記録する。
- SQLCipher鍵はDevice Key由来のHKDF（`info=todori/local-db-key/v1`）であり、本タスクで変更しない。
- Rust側にローカライズ済みUI文字列を持たせない。Inbox名はDB内ユーザーデータなので、作成時のUIロケールでDartから渡された文字列を保存する。
- 既に存在する既定リスト名を、次回起動時のロケールで上書きしない。改名済みユーザーデータを尊重する。
- `sort_order` はリスト表示順としては引き続き使ってよい。禁止するのは「`sort_order` 先頭を既定リストとみなす」ルールである。
- FRB生成物は手編集しない。`app/rust/src/api.rs` を変更したら、必ずFRB再生成を行う。
- `FileDeviceKeyStore` / `InMemoryDeviceKeyStore` は本タスクで本番キーチェーンへ置き換えない。
- 新規依存は追加しない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- v3 migrationの内容、`LATEST_SCHEMA_VERSION`、`lists.is_default` の型/default値、不変条件
- v2->v3昇格でどの既存リストがdefault化されるかのルール
- 空DB/既定欠損DBでのInbox自動プロビジョニングの実装箇所と、en/ja名の検証結果
- `init_core` / `initCore` の新引数、Dart側でUIロケールから `defaultInboxName` を解決する方法
- `List` / `ListDto` / FRB生成物 / FakeBridgeService の追随内容
- `sort_order` 先頭ルールの残存grep結果と、残存する `first` / `sortOrder` がある場合の用途説明
- 既定リストの削除不可・アーカイブ不可・改名可のテスト結果
- 復元/Undo/remap先の扱いとテストまたはgrep結果
- widget test / visual QAの証拠（初回起動相当でInbox Tasks画面が表示されること）
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項: `docs/03_技術仕様書.md` への `lists.is_default` 追記が必要（人間承認待ち）であることを必ず含める
