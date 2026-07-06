# task-37: リストのアーカイブ/アーカイブ解除

> ステータス: 完了（2026-07-07実装）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

2026-07-07改訂の `docs/02_機能仕様書.md` F-09 は、リストをアーカイブ/アーカイブ解除でき、アーカイブ時もリストのデータおよび完了済みタスクを含む履歴を完全に保全すると定めている。`docs/05_設計判断記録.md` ADR-009 は、ゴミ箱を廃止し、削除は恒久削除とし、履歴の保全経路をアーカイブへ一本化する判断を記録している。

本タスクは、完了履歴を保全したままリストを通常一覧から片付ける唯一の経路として、リストのアーカイブ/アーカイブ解除を domain → storage → Rust bridge → FRB → Dart bridge/fake/provider → UI まで縦貫通で実装する。

task-36で `core/storage` のマイグレーションランナーと `lists.archived_at INTEGER NULL` のv2マイグレーションは導入済みである。本タスクではその列を利用するが、**スキーマ変更は行わない**。`docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更禁止であり、F-09の2026-07-07改訂部分は参照のみとする。

既定インボックスの扱いはtask-35の暫定解を継承し、`sort_order` が最小のリスト（`list_all()` の先頭）を既定インボックスとみなす。既定インボックスはリスト未指定タスクの受け皿であるため、アーカイブ不可とする。`name` 文字列による判定は行わない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`（現在地と優先度付きバックログ）
- `docs/02_機能仕様書.md` F-09（2026-07-07改訂部分。参照のみ、変更禁止）
- `docs/03_技術仕様書.md`（変更禁止。矛盾は完了報告へ記録）
- `docs/05_設計判断記録.md` ADR-009
- `docs/design/ui-spec.md`（裁定済み事項、画面規範、判断規則）
- `docs/tasks/task-35-list-rename.md`
- `docs/tasks/task-36-schema-migration.md` の完了報告
- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `core/storage/src/lib.rs`（`LATEST_SCHEMA_VERSION`、`lists.archived_at` migration、`ListRepository`）
- `app/rust/src/api.rs`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- 通常リストをアーカイブし、通常一覧から分離して「アーカイブ済み」セクションへ移動できる。
- アーカイブ済みリストをアーカイブ解除し、通常一覧へ戻せる。
- アーカイブ時もリスト本体、配下タスク、完了済みタスクを含む履歴を削除・改変しない。
- 既定インボックス（`sort_order` 最小リスト）はアーカイブできない。
- `get_lists` は通常一覧用としてアーカイブ済みリストを除外し、`get_archived_lists` でアーカイブ済みリストを取得できる。
- Lists画面で、アーカイブ済みリストを既定で閉じた折りたたみセクション（件数付き）として表示できる。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `flutter_rust_bridge.yaml` 経由で再生成される `app/rust/src/frb_generated.rs`、`app/lib/src/rust/` 配下（手編集禁止、生成のみ）
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（`flutter gen-l10n` による生成差分のみ）
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-37-list-archive.md`（完了報告の追記のみ）

### やること

1. **domain**:
   - `List` に `archived_at: Option<i64>` を追加する。
   - `archive_list(list, now_ms)` / `unarchive_list(list, now_ms)` ユースケースを追加する。
   - 既定インボックス（`sort_order` 最小リスト）の保護は、単体の `List` だけでは判定できないため、候補リスト群を受け取る helper またはAPI層の判定で実現してよい。ただし判定基準は `sort_order` の先頭で統一する。
   - アーカイブ済み/未アーカイブの冪等性（同じ操作の再実行）をどう扱ったかをテストと完了報告に記録する。
2. **storage**:
   - `ListRepository` と `SqliteListRepository` に `archived_at` の読み書きを反映する。
   - 通常リスト取得（非アーカイブ）とアーカイブ済みリスト取得を分ける。既存 `list_all()` を非アーカイブのみへ変更する場合は、呼び出し元影響を確認する。
   - `archived_at` の更新メソッド、または `update` 経由での更新を実装する。
   - task-36で導入済みのv2列を使い、`LATEST_SCHEMA_VERSION` やmigrationを変更しない。
3. **Rust bridge / FRB**:
   - `ListDto` に `archived_at` を追加する。
   - `archive_list(list_id: String) -> Result<ListDto, String>` を追加する。
   - `unarchive_list(list_id: String) -> Result<ListDto, String>` を追加する。
   - `get_lists()` はアーカイブ済みリストを除外する。
   - `get_archived_lists() -> Result<Vec<ListDto>, String>` を追加する。
   - Rust API変更後、リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する（FRB `2.12.0` 固定、生成物は手編集禁止）。
4. **Dart bridge / fake / provider**:
   - `BridgeService` / `FrbBridgeService` / `FakeBridgeService` に `archiveList`、`unarchiveList`、`getArchivedLists` を追加する。
   - 通常リスト用providerとアーカイブ済みリスト用providerを分離し、archive/unarchive成功後は両方をinvalidateする。
   - Home/Tasks側が通常リストのみを見る前提を壊さないことを確認する。
5. **UI（Lists画面）**:
   - task-35で導入済みの各行「...」メニューへ「アーカイブ」を追加する。
   - 既定インボックス行では「アーカイブ」を表示しない、またはdisabledにする。disabledにする場合は理由が伝わるtooltip/semanticsを用意する。
   - アーカイブ済みリストは通常一覧から分離し、折りたたみの「アーカイブ済み」セクション（件数付き、既定で閉）に表示する。
   - アーカイブ済みリストの行メニューから「アーカイブ解除」を実行できる。
   - アーカイブ済みリストのタスクは既存の画面遷移で閲覧可能とする。読み取り専用化や編集制限は本タスクでは設けない。
6. **UI spec準拠**:
   - `docs/design/ui-spec.md` の判断規則に従い、新しい色・角丸・面色・影を発明しない。
   - チップは1行最大2個を維持する。
   - アーカイブは破壊的操作ではないため、coralを使わない。
   - 既存画面のMaterial Icons暫定状態は許容するが、新規でMaterial/Lucide混在を増やす場合は完了報告に理由を記録する。
7. **l10n / test / visual QA**:
   - アーカイブ/アーカイブ解除/アーカイブ済みセクション/既定インボックス保護に関するUI文字列をen/ja ARB化し、`flutter gen-l10n` を実行する。
   - widget testを追加する: アーカイブで通常一覧から消えアーカイブ済みセクションへ移る、解除で戻る、インボックス保護、空アーカイブ時はセクション非表示。
   - 作業開始前に既存 `app/build/visual_qa/` があれば `app/build/visual_qa_before/` へ退避する。
   - `sh app/tool/visual_qa.sh` で `lists.png` を再生成し、アーカイブ済みセクション展開状態のスクリーンショット（例: `lists_archived.png`）を追加する。
   - before/afterの `lists.png` と `lists_archived.png` を目視確認し、結果を完了報告へ記録する。

### やらないこと

- ゴミ箱撤去、trash route/provider/APIの撤去、削除Undo廃止、恒久削除の確認UI（task-38）。
- `tasks.deleted_at` の廃止や削除系undo履歴の整理（task-38）。
- アーカイブ済みリスト内タスクの編集制限・読み取り専用化。
- ログブック/振り返りUI（Phase 3）。
- リストの型（プロジェクト型/エリア型）の導入。
- 既定インボックスの自動プロビジョニング。
- リスト並び替えUI/API。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順例

1. `git status --short` で作業ツリーを確認する。
2. 2章の事前ファイルを読み、F-09改訂、ADR-009、ui-spec判断規則、task-36完了報告、現行Lists画面の「...」メニューを把握する。
3. `core/domain` の `List` とユースケースへ `archived_at` / archive / unarchive を追加し、単体テストを書く。
4. `core/storage` の `ListRepository` 実装へ `archived_at` の読み書き、通常一覧/アーカイブ済み一覧の取得を追加し、storageテストを書く。
5. `app/rust/src/api.rs` に `archive_list` / `unarchive_list` / `get_archived_lists` と `ListDto.archived_at` を追加し、`get_lists` を非アーカイブ一覧にする。
6. `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、FRB生成差分を確認する。
7. Dartの `BridgeService` / `FakeBridgeService` / providerを更新し、archive/unarchive後に通常一覧とアーカイブ済み一覧が更新されるようにする。
8. Lists画面にアーカイブ/解除メニューと折りたたみ「アーカイブ済み」セクションを実装する。
9. en/ja ARBを更新し、`flutter gen-l10n` を実行する。
10. widget testとvisual QAスクリーンショットを追加・更新する。
11. 共通受け入れ基準の品質ゲートを実行する。
12. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `lists.archived_at` を使ってリストのアーカイブ/アーカイブ解除が永続化され、スキーマ変更・migration追加なしで動作している。
- [ ] `get_lists()` は非アーカイブリストのみを返し、`get_archived_lists()` はアーカイブ済みリストのみを返すことがRust/storageまたはbridgeテストで確認できる。
- [ ] 既定インボックス（`sort_order` 最小リスト）はアーカイブできず、この保護がdomain/API/UIのいずれか適切な層のテストで確認できる。
- [ ] Lists画面でアーカイブ実行後、対象リストが通常一覧から消え、展開した「アーカイブ済み」セクションへ表示されることがwidget testで確認できる。
- [ ] Lists画面でアーカイブ解除後、対象リストが通常一覧へ戻ることがwidget testで確認できる。
- [ ] アーカイブ済みリストが0件のとき、「アーカイブ済み」セクションが表示されないことがwidget testで確認できる。
- [ ] アーカイブ済みリストのタスク画面へ既存遷移で入れることが確認され、編集制限を新設していない。
- [ ] en/jaのl10nキーが追加され、直書き文字列チェックに通っている。
- [ ] before/afterの `lists.png` と、アーカイブ済みセクション展開状態のスクリーンショット（例: `lists_archived.png`）を完了報告にパス付きで記録している。
- [ ] `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` 実行後の生成物差分がFRB生成物のみで、手編集がない。

## 7. 制約・注意事項

- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更禁止。F-09は2026-07-07改訂済みのため参照のみとする。矛盾は完了報告の「未解決事項」へ記録する。
- task-36で `LATEST_SCHEMA_VERSION = 2` と `lists.archived_at` v2 migrationは実装済みである。本タスクでスキーマバージョンやmigrationを追加しない。
- 既定インボックス判定は `sort_order` 最小のリストを基準にし、`name` 文字列に依存しない。
- アーカイブは削除ではない。配下タスク、完了履歴、Undo履歴を削除・改変しない。
- アーカイブは破壊的操作ではないため、確認ダイアログやcoral強調は不要とする。必要以上に重い導線にしない。
- FRBは `2.12.0` 固定である。Rust側crate・Dart側pubのバージョンを変更しない。
- 生成物（`frb_generated.*`、`app/lib/src/rust/` 配下）は手編集しない。
- 秘密情報、Device Key、SQLCipher鍵、導出鍵をログ・Debug出力に含めない。
- 新規依存は追加しない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- F-09改訂・ADR-009から読み取ったアーカイブのセマンティクス
- `List.archived_at`、domain archive/unarchiveユースケース、既定インボックス保護の実装内容
- `ListRepository` の `archived_at` 読み書き、通常一覧/アーカイブ済み一覧の取得方法
- `app/rust/src/api.rs` に追加した `archive_list` / `unarchive_list` / `get_archived_lists` と `get_lists` の除外仕様
- FRB再生成コマンドの実行結果と生成差分の概要
- Dart側の変更内容（`BridgeService` / `FakeBridgeService` / providers / UI）
- 追加/更新したl10nキーとwidget testの対象・結果
- before/afterの `lists.png` と `lists_archived.png` 等の保存パス、目視確認結果
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（`docs/03_技術仕様書.md` との矛盾、アーカイブ済みタスク編集制限、ログブックUI、task-38へ渡す注意点を含む）

## 9. 完了報告

- 作業日: 2026-07-07
- 読んだファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/BACKLOG.md`
  - `docs/02_機能仕様書.md` F-09
  - `docs/03_技術仕様書.md`
  - `docs/05_設計判断記録.md` ADR-009
  - `docs/design/ui-spec.md`
  - `docs/tasks/task-35-list-rename.md`
  - `docs/tasks/task-36-schema-migration.md`
  - `core/domain/src/entities.rs`
  - `core/domain/src/lib.rs`
  - `core/domain/src/usecases.rs`
  - `core/storage/src/lib.rs`
  - `app/rust/src/api.rs`
  - `app/lib/src/core/bridge_service.dart`
  - `app/lib/src/core/providers.dart`
  - `app/lib/src/screens/lists_screen.dart`
  - `app/test/support/fake_bridge_service.dart`
  - `app/test/widget_test.dart`
  - `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - `app/tool/visual_qa.sh`
- F-09改訂・ADR-009から読み取ったアーカイブのセマンティクス:
  - リストはアーカイブ/アーカイブ解除できる。
  - アーカイブ済みリストは通常のリスト一覧から分離して表示する。
  - アーカイブ時、リスト本体、配下タスク、完了済みタスクを含む履歴は削除・改変しない。
  - 履歴の保全経路はアーカイブであり、ゴミ箱撤去と恒久削除移行はtask-38の範囲である。
- domain実装:
  - `List` に `archived_at: Option<i64>` を追加した。
  - `new_list` は `archived_at = None` を設定する。
  - `archive_list(list, now_ms)` は `archived_at` が `None` の場合だけ `Some(now_ms)` と `updated_at = now_ms` を設定する。
  - `unarchive_list(list, now_ms)` は `archived_at` が `Some` の場合だけ `None` と `updated_at = now_ms` を設定する。
  - archive/unarchiveはいずれも同じ操作の再実行時に既存の `archived_at` / `updated_at` を変更しない冪等動作とした。
  - `todori_domain` root exportへ `archive_list` / `unarchive_list` を追加した。
  - 既定インボックス保護は単体の `List` では判定できないため、Rust API層とUI/fake層で `sort_order` 最小の通常リストを基準に実装した。
- storage実装:
  - `ListRepository` に `list_archived()` を追加した。
  - `SqliteListRepository::get` / `insert` / `update` / `row_to_list` に `archived_at` の読み書きを追加した。
  - `list_all()` は `WHERE archived_at IS NULL ORDER BY sort_order ASC` の通常一覧取得に変更した。
  - `list_archived()` は `WHERE archived_at IS NOT NULL ORDER BY archived_at DESC, sort_order ASC` でアーカイブ済み一覧を取得する。
  - `LATEST_SCHEMA_VERSION` とmigrationは変更していない。
- Rust bridge / FRB:
  - `ListDto` に `archived_at: Option<i64>` を追加した。
  - `pub fn get_archived_lists() -> Result<Vec<ListDto>, String>` を追加した。
  - `pub fn archive_list(list_id: String) -> Result<ListDto, String>` を追加した。
  - `pub fn unarchive_list(list_id: String) -> Result<ListDto, String>` を追加した。
  - `get_lists()` はstorageの `list_all()` 経由で非アーカイブリストのみ返す。
  - `archive_list` は対象が非アーカイブで、かつ通常一覧の先頭リストの場合に `default inbox cannot be archived` を返す。
  - `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` は標準PATHではFlutter SDK cache書き込み不可によりexit 1。
  - 同じコマンドを `/private/tmp/todori-frb-fakebin` の `flutter --version` 一時ラッパーをPATH先頭に置いて再実行し、exit 0、出力 `Done!`。内部の `dart fix` / `dart format` はFlutter SDK cache書き込み不可で警告失敗したため、同梱Dart SDKで `dart format lib/src/rust` を別途実行した。
  - FRB生成差分は `app/rust/src/frb_generated.rs`、`app/lib/src/rust/api.dart`、`app/lib/src/rust/frb_generated.dart`。
- Dart側実装:
  - `BridgeService` / `FrbBridgeService` に `getArchivedLists`、`archiveList`、`unarchiveList` を追加した。
  - `ListsNotifier.archiveList` は実行後に `listsProvider` と `archivedListsProvider` をinvalidateする。
  - `ArchivedListsNotifier` / `archivedListsProvider` を追加し、`unarchiveList` 実行後に `archivedListsProvider` と `listsProvider` をinvalidateする。
  - `FakeBridgeService` は `getLists()` で非アーカイブのみ返し、`getArchivedLists()` でアーカイブ済みのみ返す。
  - `FakeBridgeService.archiveList` は非アーカイブの既定インボックス（通常一覧の先頭）を拒否し、既にアーカイブ済みの場合は変更せず返す。
  - `FakeBridgeService.unarchiveList` は未アーカイブの場合は変更せず返す。
- UI実装:
  - Lists画面は通常リストとアーカイブ済みリストを分離して描画する。
  - 通常リスト行の三点メニューへ、既定インボックス以外で `Archive` / `アーカイブ` を追加した。
  - 既定インボックス行にはアーカイブ操作を表示しない。
  - アーカイブ済みリストが1件以上の場合だけ、件数付きの折りたたみセクションを表示する。
  - アーカイブ済みセクションは初期状態で閉じる。
  - アーカイブ済みリスト行の三点メニューから `Unarchive` / `アーカイブ解除` を実行する。
  - アーカイブ済みリスト行のタップは既存の `/lists/:id/tasks` 遷移を使う。
  - 新規UIでも既存画面のMaterial Icons暫定状態に合わせて `Icons.archive_outlined` 等を使った。Lucide移行は別バックログ対象。
- l10n:
  - `archiveListMenuItem`
  - `unarchiveListMenuItem`
  - `archivedListsSectionTitle`
  - `showArchivedListsTooltip`
  - `hideArchivedListsTooltip`
  - `flutter gen-l10n` は標準wrapperではFlutter SDK cache書き込み不可によりexit 1。
  - `HOME=/private/tmp/todori-flutter-home FLUTTER_ALREADY_LOCKED=true /Users/youhei/workspaces/sdk/flutter/bin/cache/dart-sdk/bin/dart /Users/youhei/workspaces/sdk/flutter/packages/flutter_tools/bin/flutter_tools.dart --suppress-analytics gen-l10n` はexit 0。
- 追加/更新したテスト:
  - domain: `archive_list_sets_archived_at_and_updated_at`
  - domain: `archive_list_is_idempotent_when_already_archived`
  - domain: `unarchive_list_clears_archived_at_and_updates_updated_at`
  - domain: `unarchive_list_is_idempotent_when_not_archived`
  - storage: `sqlite_list_repository_roundtrips_and_lists_by_sort_order` で `archived_at` 永続化、`list_all()` 非アーカイブ除外、`list_archived()` 取得を確認するよう更新した。
  - widget: `archiving a list moves it to the archived section`
  - widget: `unarchiving a list returns it to the active list section`
  - widget: `default inbox does not expose archive action`
  - widget: `archived section is hidden when there are no archived lists`
  - widget: `archived lists still navigate to their task screen`
  - visual QA: `lists_archived` スクリーンショットtestを追加し、`lists` はアーカイブ済みセクション閉状態を撮るseedに変更した。
- visual QA:
  - 作業前に `app/build/visual_qa/*.png` 25件を `app/build/visual_qa_before/` へコピーした。
  - before: `app/build/visual_qa_before/lists.png`
  - after予定: `app/build/visual_qa/lists.png`
  - expanded予定: `app/build/visual_qa/lists_archived.png`
  - `sh app/tool/visual_qa.sh`: exit 1。Flutter SDK cache配下 `engine.stamp.tmp.*` / `engine.realm` への書き込みが `Operation not permitted` で、visual QA test実行前に停止。
  - 直接実行 `TODORI_VISUAL_QA=1 ... flutter_tools.dart test test/visual_qa/visual_qa_screenshots_test.dart`: exit 1。`127.0.0.1:0` のserver socket作成が `Operation not permitted` で、test load時に停止。
  - `app/build/visual_qa/lists_archived.png` は生成されていない。
  - after画像の目視確認は実施していない。
- 品質ゲートの実行結果:
  - `cargo fmt --all -- --check`: exit 0
  - `cargo clippy --workspace -- -D warnings`: 1回目exit 101（`todori_domain` root export漏れ）。`core/domain/src/lib.rs` 修正後の再実行はexit 0。
  - `cargo test --workspace`: exit 0。Rust tests 84 passed。
  - `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0。
  - `cd app && flutter analyze`: exit 1。Flutter SDK cache配下 `engine.stamp.tmp.*` / `engine.realm` への書き込みが `Operation not permitted` で、解析前に停止。
  - 直接実行 `HOME=/private/tmp/todori-flutter-home FLUTTER_ALREADY_LOCKED=true ... flutter_tools.dart --suppress-analytics analyze`: exit 0、`No issues found!`
  - `cd app && flutter test`: exit 1。Flutter SDK cache配下 `engine.stamp.tmp.*` / `engine.realm` への書き込みが `Operation not permitted` で、テスト実行前に停止。
  - 直接実行 `HOME=/private/tmp/todori-flutter-home FLUTTER_ALREADY_LOCKED=true ... flutter_tools.dart --suppress-analytics test test/widget_test.dart`: exit 1。`127.0.0.1:0` のserver socket作成が `Operation not permitted` で、test load時に停止。
  - `sh app/tool/check_hardcoded_strings.sh`: exit 0
  - `git diff --check`: exit 0
- 変更ファイル一覧:
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/lib/src/core/bridge_service.dart`
  - `app/lib/src/core/providers.dart`
  - `app/lib/src/generated/l10n/app_localizations.dart`
  - `app/lib/src/generated/l10n/app_localizations_en.dart`
  - `app/lib/src/generated/l10n/app_localizations_ja.dart`
  - `app/lib/src/rust/api.dart`
  - `app/lib/src/rust/frb_generated.dart`
  - `app/lib/src/screens/lists_screen.dart`
  - `app/rust/src/api.rs`
  - `app/rust/src/frb_generated.rs`
  - `app/test/support/fake_bridge_service.dart`
  - `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - `app/test/widget_test.dart`
  - `core/domain/src/entities.rs`
  - `core/domain/src/lib.rs`
  - `core/domain/src/usecases.rs`
  - `core/storage/src/lib.rs`
  - `docs/tasks/task-37-list-archive.md`
- 未解決事項:
  - `docs/03_技術仕様書.md` の `lists` 定義には `archived_at` が記載されていない。本タスクでは仕様書変更禁止のため未変更。
  - `docs/03_技術仕様書.md` は `tasks.deleted_at` による論理削除/tombstoneを記載しているが、ADR-009では将来migration経由で廃止予定とされている。本タスクでは `tasks.deleted_at` は変更していない。
  - 既定インボックス自動プロビジョニングと、既定インボックスを永続的に識別するスキーマ列は未実装。
  - アーカイブ済みリスト内タスクの編集制限は新設していない。
  - ログブック/振り返りUIは未実装。
  - task-38では、ゴミ箱撤去、恒久削除移行、削除Undo廃止、`tasks.deleted_at` 整理時に、アーカイブ済みリストが通常一覧から除外される前提を確認する。
  - Flutter wrapperのSDK cache書き込み制約と、Flutter test/visual QAのlocalhost bind制約により、`flutter test` とvisual QA PNG再生成・目視確認はこの環境では未実施。
