# task-51: Home画面のセクション再構成

> ステータス: 完了（worker実装）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

2026-07-07 Home改善サイクル第1回で、`assets/brand/explorations/home-20260707/` の3案から、A案（TickTick方向）の構造とC案の行表現を組み合わせたハイブリッドを採用することが人間裁定された。あわせて、横幅の外マージン/内paddingを圧縮し、トップ部分を圧縮し、Tomorrow/Upcomingセクションを含める方針が決まった。

これにより、ルート画面は「Today」ではなく「Home」と再定義する。現状の `get_today_tasks` / `todayTasksProvider` / `TasksScreen.today` は、期日今日+期日超過を1つのTodayスマートビューとして扱っている。本タスクではこの構造を、Overdue / Today / Tomorrow / Upcoming のHomeセクション構造へ拡張する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション2〜3、裁定済み事項
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `assets/brand/explorations/home-20260707/README.md`
- `docs/tasks/task-47-today-smart-list.md`
- `docs/tasks/task-50-drag-drop-reorder.md`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/rust/src/api.rs` の `get_today_tasks` / `TodayTaskDto`
- `core/storage/src/lib.rs` の `list_today`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- HomeをOverdue / Today / Tomorrow / Upcomingの4セクション構造にする。
- セクション対象は、アーカイブ済みリストを除外し、期日ありタスクのみに限定する。期日なしタスクはHome対象外のままにする。
- ヘッダーを大型Today見出し+日付サブ行から、セリフの日付1行へ圧縮する。
- パネル/セクション外側マージンを8px級、行の左右paddingを12〜16px級へ圧縮する。
- 行表現を、枠線なし色付き日付pill、右寄せpriority dot+日付pill、タイトル下の小さなリスト名ラベルへ変更する。
- Lists画面の最上部スマートリンクを「Today」から「Home」へ改名する。
- widget testとvisual QA before/afterで、Home構造とLists導線を検証する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- FRB生成物（Rust APIを変更した場合のみ）
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/home_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARB変更時の生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/core_usecases_test.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-51-home-restructure.md`（完了報告の追記のみ）

### やること

1. Home取得をOverdue / Today / Tomorrow / Upcomingへ拡張する。
   - 既存 `get_today_tasks` / `list_today` を拡張しても、複数クエリを追加してDart側で束ねてもよい。
   - 端末ローカル日の `[todayStart, tomorrowStart, dayAfterTomorrowStart)` をDart側で計算し、Rust側でローカルタイムゾーンを推測しない。
   - Overdueは `due_at < todayStart`、Todayは `[todayStart, tomorrowStart)`、Tomorrowは `[tomorrowStart, dayAfterTomorrowStart)`、Upcomingは `due_at >= dayAfterTomorrowStart` とする。
   - `due_at IS NULL` とアーカイブ済みリスト由来タスクは返さない。
   - Closed行の扱いは既存Todayスマートビューの方針を踏襲し、完了/やらないことにした行の表示条件を変更した場合は完了報告に明記する。
2. Home UIを4セクションへ再構成する。
   - 各セクションは見出し、件数バッジ、折りたたみchevronを持つ。
   - Overdue見出しはcoral、Today/Tomorrow/Upcomingは既存トークン内の控えめな色を使う。
   - 単一パネル構造は維持してよいが、外側余白と内側paddingを圧縮し、スマホ横幅を優先する。
3. Homeヘッダーを圧縮する。
   - 大型の「Today」見出しと日付サブ行を廃止する。
   - Home上部にはセリフの日付1行だけを表示する。例: `July 7` / `7月7日(火)`。
   - 日付表記は固定パターンにせず、可能な範囲でロケールに自然な表示へ寄せる。
4. Home行を再スタイルする。
   - 日付pillは枠線なしの淡色塗りにする。期日超過=淡coral、今日=淡sage、明日以降=淡amberを基本とする。
   - priority dot + 日付pillを右寄せにする。
   - リスト名はタイトル下の小さなラベル（アイコン + リスト名）にし、従来のリスト名pillを置き換える。
   - 通常リスト画面の既存行表現は、必要な共通部品整理を除き退行させない。
5. Lists画面の最上部リンクをHomeへ改名する。
   - 表示名、tooltip、semantics、l10nキーを「Home」へ揃える。
   - タップ先は既存どおりルート `/` とする。
6. テストとvisual QAを更新する。
   - widget testで4セクションの振り分け、期日なし除外、アーカイブ済みリスト除外、折りたたみ、Lists画面Homeリンクを確認する。
   - visual QA実行前に `app/build/visual_qa/` を `app/build/visual_qa_before/` へ退避し、実装後に `sh app/tool/visual_qa.sh` を実行する。
   - `home_tasks` 系とLists画面のbefore/after PNGを完了報告に記録する。

### やらないこと

- 下部常設クイック追加バーの実装（task-52）。
- スワイプ操作、期日変更シート、モーション実装（task-53）。
- 自然言語日付解析。
- 横断Homeビューでの手動並び替え。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認し、既存の未追跡/未コミット差分を把握する。
2. 2章のファイルを読み、既存のToday取得、`todayTasksProvider`、`TasksScreen.today`、Lists画面Today行、visual QA seedを把握する。
3. Home取得DTO/APIを設計する。Rust APIを変更する場合はFRB再生成が必要であることを先に確認する。
4. storage/API/provider/fakeを更新し、Overdue / Today / Tomorrow / Upcomingへ分類できるデータをDartへ渡す。
5. `TasksScreen.today` 相当の命名/構造をHomeに合わせて整理し、HomeヘッダーとセクションUIを実装する。
6. Home行のmetadata配置を、通常リスト行と破綻なく共存する形で分岐または共通化する。
7. Lists画面のToday行をHomeへ改名し、l10nとtestを更新する。
8. widget test、core/API test、visual QAを更新する。
9. 品質ゲートを実行し、指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] Home取得は、期日超過/今日/明日/明後日以降を正しく分類し、期日なしタスクとアーカイブ済みリスト由来タスクを除外することがテストで確認されている。
- [ ] HomeにはOverdue / Today / Tomorrow / Upcomingの4セクションが表示され、各セクションに件数バッジと折りたたみ操作があることがwidget testで確認されている。
- [ ] Homeヘッダーはセリフの日付1行になり、大型Today見出しと日付サブ行が表示されないことがwidget testまたはvisual QAで確認されている。
- [ ] Homeの外側マージン/内側paddingが圧縮され、`home_tasks` 系visual QA before/afterで横幅利用の変化が確認できる。
- [ ] Home行の日付pillは枠線なしの淡色塗りで、priority dot + 日付pillが右寄せになり、タイトル下に小さなリスト名ラベルが表示されることがvisual QAで確認されている。
- [ ] 通常リスト画面では期日なしタスク、既存の並び替え、Closed、詳細遷移が退行していないことがwidget testで確認されている。
- [ ] Lists画面の最上部スマートリンクが「Home」へ改名され、タップで `/` へ遷移することがwidget testで確認されている。
- [ ] ARBのen/ja、生成l10n、tooltip/semanticsがHome表記へ揃っている。
- [ ] Rust APIを変更した場合、FRB生成物が再生成され、手編集されていない。
- [ ] 完了報告に、Home抽出条件、DTO/API方針、visual QA before/afterパス、品質ゲート結果が記録されている。

## 7. 制約・注意事項

- Homeは横断ビューであり、通常リストではない。Home上で `sort_order` を変更しない。
- 「今日」「明日」の境界は端末ローカル日付でDart側が計算し、Rust側にタイムゾーン推測を持ち込まない。
- `docs/design/ui-spec.md` の2026-07-07 Home裁定を優先する。既存Today仕様と矛盾する場合はHome裁定へ合わせ、完了報告に差分を記録する。
- セクションや行をカード化しすぎない。borderは外側パネルへ寄せ、行ごとの重い枠線を増やさない。
- UI文字列はARB化する。Home/Overdue/Tomorrow/Upcoming、tooltip、semanticsをDartへ直書きしない。
- visual QAはライトモードを必須証拠とする。ダークモード正式対応は直近スコープ外である。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- Home取得API/DTOまたは複数クエリの実装箇所、分類条件、アーカイブ/期日なし除外条件
- Dart provider / BridgeService / FakeBridgeService の変更内容
- Homeヘッダー、4セクション、折りたたみ、件数バッジの実装箇所
- Home行のmetadata配置、日付pill色、リスト名ラベルの実装箇所
- Lists画面のHomeリンク改名内容
- 追加・更新したl10nキー
- 追加・更新したテスト名と検証対象
- visual QA before/afterスクリーンショットの保存パス
- FRB再生成の有無と結果
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

### 作業日

2026-07-07

### 読んだファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `assets/brand/explorations/home-20260707/README.md`
- `docs/tasks/task-47-today-smart-list.md`
- `docs/tasks/task-50-drag-drop-reorder.md`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/rust/src/api.rs`
- `core/storage/src/lib.rs`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/core_usecases_test.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

### 作業前退避

- `app/build/visual_qa/*.png` を `app/build/visual_qa_before/` へコピーした。
- 退避先: `app/build/visual_qa_before/`

### Home取得API/DTO

- `core/storage/src/lib.rs` に `HomeTask { task, list_name }` と `TaskRepository::list_home(today_start_ms, tomorrow_start_ms)` を追加した。
- `list_home` は `tasks` と `lists` をJOINし、`lists.archived_at IS NULL`、`tasks.due_at IS NOT NULL` を条件にする。
- active行は `tasks.status IN ('todo', 'in_progress')` を返す。
- closed行は `tasks.status IN ('done', 'wont_do') AND tasks.completed_at >= today_start_ms AND tasks.completed_at < tomorrow_start_ms` を返す。
- `app/rust/src/api.rs` に `HomeTaskDto { task: TaskDto, list_name: String }` と `get_home_tasks(today_start_ms, tomorrow_start_ms)` を追加した。
- Dart側 `homeLocalRangesMs()` で端末ローカル日の `todayStartMs` / `tomorrowStartMs` / `dayAfterTomorrowStartMs` を計算した。
- UI分類条件は、Overdue=`due_at < todayStartMs`、Today=`[todayStartMs, tomorrowStartMs)`、Tomorrow=`[tomorrowStartMs, dayAfterTomorrowStartMs)`、Upcoming=`due_at >= dayAfterTomorrowStartMs`。
- 期日なしタスクとアーカイブ済みリスト由来タスクはHome取得対象外。
- Closed行はHomeの各期日セクション内に表示し、別のClosedセクションには分けていない。

### Dart provider / BridgeService / FakeBridgeService

- `BridgeService` / `FrbBridgeService` に `getHomeTasks(todayStartMs, tomorrowStartMs)` を追加した。
- `TodayTasksNotifier` / `todayTasksProvider` を `HomeTasksNotifier` / `homeTasksProvider` へ置換した。
- `HomeTasksNotifier.createTask` は既定Inboxを `isDefault == true` で解決し、`dueAt = todayStartMs` で作成する。
- `FakeBridgeService.getHomeTasks` は実装と同じ抽出条件、list名付き `HomeTaskDto`、Home作成時の `dueAt` を扱う。
- `task_detail_screen.dart` の更新/削除/ステータス変更後の無効化先を `homeTasksProvider` に変更した。

### Home UI

- `app/lib/src/screens/tasks_screen.dart` でHomeをOverdue / Today / Tomorrow / Upcomingの4セクションへ変更した。
- 各セクションは見出し、件数バッジ、開閉chevronを持つ。
- Homeヘッダーは `DateFormat.MMMEd(locale)` によるセリフの日付1行へ変更した。
- 大型 `Today` 見出しと日付サブ行はHomeヘッダーから削除した。
- Homeの外側paddingは `AppSpacing.sm`、パネル内paddingは `AppSpacing.sm` に変更した。
- Home行は `AppHomeTaskRow` を追加し、左からチェック、タイトル+リスト名ラベル、右寄せpriority dot+日付pillの構成にした。
- Home行の日付pillはborderなしで、Overdue=淡coral、Today=淡sage、Tomorrow/Upcoming=淡amberを使う。
- リスト名はタイトル下の小さなアイコン+リスト名ラベルとして表示する。
- 通常リスト画面は既存 `AppTaskRow`、階層ガイド、Closedセクション、D&D経路を維持した。

### Lists画面

- `app/lib/src/screens/lists_screen.dart` の最上部スマートリンクを `Today` から `Home` へ改名した。
- 表示名は `l10n.homeTitle`、tooltip/semanticsは `l10n.homeSmartListTooltip` にした。
- タップ先は `/` のまま。

### l10n

- 追加キー:
  - `homeTitle`
  - `homeOverdueSectionTitle`
  - `homeTomorrowSectionTitle`
  - `homeUpcomingSectionTitle`
  - `homeSmartListTooltip`
  - `showHomeSectionTooltip`
  - `hideHomeSectionTooltip`
- `flutter gen-l10n` を実行し、`app/lib/src/generated/l10n/` を更新した。

### テスト

- `core/storage/src/lib.rs`
  - `list_home_filters_due_active_and_closed_tasks_across_active_lists`: 期日超過/今日/明日/Upcoming、期日なし除外、アーカイブ済み除外、当日Closed表示、前日Closed除外を検証。
- `app/test/core_usecases_test.dart`
  - `home smart view is exposed through Rust bridge`: FRB経由のHome取得、list名DTO、Tomorrow/Upcoming返却、期日なし/アーカイブ済み除外を検証。
- `app/test/widget_test.dart`
  - `home shows four due sections across active lists with list labels`: 4セクション、件数バッジ、折りたたみ、期日なし除外、アーカイブ済み除外、HomeではD&Dなしを検証。
  - `home add task creates in default inbox with today due date`: Home追加時の既定Inbox作成と今日期日を検証。
  - `lists screen puts Home first and Home row returns home`: Lists画面Homeリンクの表示順と `/` 遷移を検証。
  - `home shows due subtask without parent context and normal list omits list label`: Home行のlist名ラベルと通常リストでの非表示を検証。
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - Home seedをOverdue / Today / Tomorrow / Upcomingが写る期日分布に変更した。
  - `wont_do_row` は通常リスト画面のClosedセクションを撮影するよう変更した。

### visual QA

- before:
  - `app/build/visual_qa_before/home_tasks.png`
  - `app/build/visual_qa_before/home_tasks_ja.png`
  - `app/build/visual_qa_before/home_tasks_dark.png`
  - `app/build/visual_qa_before/home_tasks_empty.png`
  - `app/build/visual_qa_before/lists.png`
- after:
  - `app/build/visual_qa/home_tasks.png`
  - `app/build/visual_qa/home_tasks_ja.png`
  - `app/build/visual_qa/home_tasks_dark.png`
  - `app/build/visual_qa/home_tasks_empty.png`
  - `app/build/visual_qa/lists.png`
- 目視比較対象:
  - `app/build/visual_qa/home_tasks.png`
  - `assets/brand/explorations/home-20260707/home_a_ticktick.png`
  - `assets/brand/explorations/home-20260707/home_c_polish.png`
- 目視比較で確認した採用ポイント:
  - A案のOverdue / Today / Tomorrow / Upcomingセクション構造に合わせ、`home_tasks.png` に4セクション見出しと件数バッジが表示されている。
  - C案の行表現に合わせ、タイトル下に小さなリスト名ラベル、右側にpriority dot+日付pillが表示されている。
  - Homeヘッダーは大型Today見出し+日付サブ行ではなく、日付1行になっている。
  - 横幅は外側padding `AppSpacing.sm`、パネル内padding `AppSpacing.sm`、Home行左右12pxで表示されている。

### FRB再生成

- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`: 成功
- 変更された生成物:
  - `app/lib/src/rust/api.dart`
  - `app/lib/src/rust/frb_generated.dart`
  - `app/lib/src/rust/frb_generated.io.dart`
  - `app/rust/src/frb_generated.rs`

### 品質ゲート

- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功
- `cd app && flutter analyze`: 成功
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter test`: 成功（76件成功、visual QA harness 1件skip）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `sh app/tool/visual_qa.sh`: 成功（30件成功）
- `git diff --check`: 成功

### 変更ファイル一覧

- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/generated/l10n/app_localizations.dart`
- `app/lib/src/generated/l10n/app_localizations_en.dart`
- `app/lib/src/generated/l10n/app_localizations_ja.dart`
- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `app/lib/src/rust/frb_generated.io.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/test/core_usecases_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/widget_test.dart`
- `core/storage/src/lib.rs`
- `docs/tasks/task-51-home-restructure.md`

### 未解決事項

なし

### 親レビュー指摘対応（2026-07-07）

- 指摘: Homeの日付見出しが `displaySmall` 派生になっており、NewsreaderセリフではなくInterで描画されていた。
- 修正: `app/lib/src/screens/tasks_screen.dart` の `_HomeTasksHeader` で、日付見出しを `theme.textTheme.displayMedium` 派生に変更し、テーマ定義済みのNewsreader + `Hiragino Mincho ProN` フォールバックを維持したまま `fontSize: 30`、`FontWeight.w600`、`colorScheme.primary`、`height: 0.95` を適用した。日付フォーマットは `DateFormat.MMMEd(locale)` のまま変更していない。
- 確認:
  - `cd app && flutter analyze && flutter test`: 成功（76件成功、visual QA harness 1件skip）
  - `sh app/tool/visual_qa.sh`: 成功（30件成功）
  - `app/build/visual_qa/home_tasks.png`: `Tue, Jul 7` がNewsreaderセリフで描画されることを目視確認した。
  - `app/build/visual_qa/home_tasks_ja.png`: `7月7日(火)` が明朝系フォールバックで描画されることを目視確認した。
