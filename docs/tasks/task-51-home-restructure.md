# task-51: Home画面のセクション再構成

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
