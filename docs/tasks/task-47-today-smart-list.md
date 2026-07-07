# task-47: Todayスマートリスト化とリスト一覧Todayリンク

## 1. 背景とコンテキスト

TodoriのHomeはtask-29以降、起動直後にTodayヘッダーを表示する task-first 体験へ寄せている。一方で実装上は、task-46で永続識別された既定Inboxを通常リストとして開き、そのリストのタスクだけを表示している。

2026-07-07ドッグフーディング第2回では、Todayは通常リストではなく、全リスト横断のスマートビューであるべきことが確認された。人間確認済みのセマンティクスは次の通りである。

- Todayは、全リスト横断（アーカイブ済みリストを除く）のスマートビューである。
- 対象は、期日が今日のタスクと期日超過のタスクである。期日なしタスクは対象外である。
- Todayでの完了済み / wont_do タスクは、当日分をClosedセクションに表示する。Closedの開閉・再オープン規則は既存のClosed規則に従う。
- TodayでAdd taskした場合は、既定Inboxにタスクを作成し、期日を今日に自動設定する。
- Todayはリストではないため、リスト操作メニュー（改名 / アーカイブ / 削除）を表示しない。ソート切替は維持してよい。
- 対象タスクがサブタスクの場合もTodayに表示する。ただし親子関係の文脈が失われるため、Todayビュー限定で所属リスト名の小さなpillを行に表示する。ui-specのチップ最大2規則の範囲内で、日付pill + リストpillの2個構成にする。

本タスクでは、Homeの「Todayヘッダー + 既定Inboxのタスク」構成を「Todayヘッダー + Todayスマートビュー」へ変更し、Lists画面の最上部にToday行を追加する。既定Inboxそのものは通常のリストとしてリスト一覧から開ける状態を維持する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/03_技術仕様書.md`（特に `lists` schema、`tasks` schema、スキーマバージョニング記述）
- `docs/tasks/task-46-default-inbox.md` の完了報告
- `docs/design/ui-spec.md` セクション3（Today / Task row / chip規則）
- `app/lib/src/screens/home_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/rust/src/api.rs`
- `core/storage/src/lib.rs`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/core_usecases_test.dart`
- `app/test/visual_qa/design_lab_mocks.dart`（Lab `listOverview` のスマートリスト構成）
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- Rust/FRB/Dartに、Todayスマートビュー用のタスク取得口を追加する。
- Today取得では、アーカイブ済みリストを除き、`due_at` が今日または過去のタスクだけを返す。`due_at IS NULL` は返さない。
- Closedセクションには、Today対象タスクのうち、`done` / `wont_do` かつ `completed_at` が今日のローカル日付範囲内にあるものを表示する。
- Homeは既定Inboxの通常Tasks表示ではなく、Todayスマートビューを表示する。
- TodayでAdd taskした場合、既定Inboxへ作成し、`due_at` を今日のローカル日付に自動設定する。
- Today行をLists画面の最上部にスマートセクションとして追加し、タップでHomeへ戻る。
- Todayビューではリスト操作メニューと手動並び替えを表示しない。期日 / 優先度 / 作成順の表示ソートは維持してよい。
- Todayビューのタスク行には、日付pillと所属リスト名pillを表示する。通常リスト画面にはリスト名pillを出さない。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- FRB生成物（`app/lib/src/rust/`、`app/rust/src/frb_generated.*` 等）
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/home_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/ui/task_components.dart`（Today限定リストpillに必要な場合）
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARBを変更した場合の生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/core_usecases_test.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-47-today-smart-list.md`（完了報告の追記のみ）

### やること

1. **Today取得APIを追加する**
   - `get_today_tasks(today_start_ms, today_end_ms)` 相当のRust APIを追加する。
   - `today_start_ms` / `today_end_ms` はDart側で端末ローカル日付から算出し、Rustへ渡す。Rust側でローカルタイムゾーンを推測しない。
   - 抽出条件は、アーカイブ済みリストを除外し、`tasks.due_at IS NOT NULL` かつ `tasks.due_at < today_end_ms` とする。これにより、期日超過と今日が対象になり、明日以降と期日なしは対象外になる。
   - activeセクション用には `status` が `todo` / `in_progress` のToday対象タスクを返す。
   - Closedセクション用には `status` が `done` / `wont_do` で、`completed_at >= today_start_ms AND completed_at < today_end_ms` のToday対象タスクを返す。
   - 1万件性能を考慮し、storage層でJOINクエリを実装することを推奨する。bridge側で全リスト取得 + 全タスク取得 + フィルタにする場合は、完了報告に性能上の理由とリスクを記録する。
   - Today行に所属リスト名pillを出すため、返却DTOには少なくとも `TaskDto` 相当のタスク情報と `list_name` を含める。必要なら `TodayTaskDto` を新設する。
2. **FRB/Dart bridge/providerを追随させる**
   - `app/rust/src/api.rs` の公開APIを変更したら、リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
   - `BridgeService` / `FrbBridgeService` / `FakeBridgeService` にToday取得とToday作成に必要なメソッドを追加する。
   - `todayTasksProvider` 相当を追加し、端末ローカル日の `[start, end)` を計算してToday APIへ渡す。
   - TodayでのAdd taskは、既定Inbox（`ListDto.isDefault == true`）を取得して作成先にし、作成直後に `due_at = today_start_ms` を設定する。実装は `createTask` に `dueAt` optional引数を追加しても、Today専用作成APIを追加してもよいが、通常リストでのAdd taskに期日が勝手に付かないこと。
3. **HomeをTodayスマートビューへ変更する**
   - `home_screen.dart` は既定Inboxを探して `TasksScreen(listId: defaultList.id)` を開く構成をやめ、Todayスマートビューを表示する。
   - Todayヘッダーは維持し、ヘッダー内の「Inbox」pillは廃止するか、「スマートビュー」文脈に合う表示へ整理する。Todayはリストではないため、既定Inbox名を現在の表示対象として見せない。
   - Todayビューでは `_ListActionsMenu` を表示しない。
   - Todayビューでは手動並び替えUIを表示しない。ソートメニューを維持する場合、選択肢は期日 / 優先度 / 作成順に限定する。
4. **Lists画面にToday行を追加する**
   - `lists_screen.dart` の最上部にスマートセクションを追加し、Lab `listOverview` の並びに準拠して `Today -> 通常リスト -> New list -> Archived` の順にする。
   - Today行をタップするとHome（`/`）へ戻る。
   - 既定Inboxは通常リストとして通常リストセクション内に表示し続ける。
   - Upcoming / Someday / Logbook 等の他スマートリストは追加しない。
5. **Today行の表示文法を整える**
   - Todayビューのタスク行には、日付pillと所属リスト名pillを表示する。リスト名pillはTodayビュー限定であり、通常リスト画面には出さない。
   - 対象タスクがサブタスクでもTodayに表示する。Todayは横断ビューであるため、親タスクがToday対象外でも対象サブタスク自体は表示する。
   - Todayビューでサブタスクを表示する場合、既存の階層ガイドを無理に親なし表示へ流用して破綻させない。親子文脈が取れない行は深さ0の単独行として扱い、所属リストpillで文脈を補う。
   - priority dotは既存のmetadata文法を維持する。pill数の上限は日付pill + リストpillの2個を守る。
6. **テストとvisual QAを追加・更新する**
   - storage/APIテストで、今日期日、期日超過、明日以降、期日なし、アーカイブ済みリスト由来、当日Closed、前日Closedの抽出/除外を確認する。
   - widget testで、HomeがTodayスマートビューを表示し、既定Inbox以外のリスト由来タスクが表示され、期日なしタスクとアーカイブ済みリスト由来タスクが表示されないことを確認する。
   - widget testで、TodayのAdd taskが既定Inboxに作成され、`due_at` が今日のローカル日付に設定されることを確認する。
   - widget testで、Todayビューにリスト操作メニューと手動並び替えUIが出ないこと、通常リスト画面では既存挙動が維持されることを確認する。
   - widget testまたはvisual QAで、Todayビューの行に日付pill + リスト名pillが表示されることを確認する。
   - visual QAで、`home_tasks` 系スクリーンショットがTodayスマートビューになったこと、既定Inbox以外のリスト由来行とリストpillが確認できることを記録する。

### やらないこと

- Upcoming / Someday / Logbook / Search 等、Today以外のスマートリスト実装。
- 通知、リマインダー、ローカル通知。
- リスト一覧の件数バッジを正確に実装すること。Today行の件数表示が必要になった場合は、Today取得結果から導出する最小実装に留める。
- 既定Inbox自動プロビジョニングや `lists.is_default` v3マイグレーションの再設計。
- リストの型（プロジェクト型 / エリア型）導入。
- `sort_order` の仕様変更や横断ビューでの手動並び替え。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。
- 新規Rust crate / pub packageの追加。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章の事前ファイルを読み、task-46後の `ListDto.isDefault`、Homeの既定Inbox選択、TasksScreenのリスト操作/手動並び替え/Closedセクション、Lists画面の現行並びを把握する。
3. `core/storage` にToday横断クエリを追加する。JOIN対象は `tasks` と `lists` とし、`lists.archived_at IS NULL`、`tasks.due_at IS NOT NULL`、`tasks.due_at < today_end_ms` を基本条件にする。
4. Today返却DTOを設計し、`TaskDto` 相当のタスク情報と所属リスト名をDartへ渡す。Rust API変更後にFRBを再生成する。
5. Dart bridge/providerへToday取得を追加し、ローカル日の `today_start_ms` / `today_end_ms` をDart側で計算する。
6. Today用の画面/ウィジェットを追加するか、既存 `TasksScreen` を明確なmode付きで拡張する。どちらの場合も、Todayがリストではないこと、リスト操作メニューがないこと、手動並び替えがないことを構造で表す。
7. Today Add taskを実装する。既定Inboxを `isDefault` で解決し、作成タスクの `due_at` を `today_start_ms` に設定する。通常リストのAdd taskには影響させない。
8. Lists画面の最上部にTodayスマート行を追加し、通常リスト、New list、Archivedの順を維持する。
9. Todayビュー限定のリスト名pillを行metadataへ追加する。通常リスト画面にリスト名pillが出ていないことを確認する。
10. widget test、core/FRB test、visual QA seedを更新し、Today横断・Add task・アーカイブ除外・リストpill・操作メニュー非表示を確認する。
11. 共通受け入れ基準の品質ゲートを実行する。
12. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] Today取得は、アーカイブ済みリストを除外し、今日期日と期日超過のタスクを返し、期日なしと明日以降のタスクを返さないことがstorage/APIテストで確認されている。
- [ ] TodayのClosedセクションは、Today対象タスクのうち当日に `done` / `wont_do` になったタスクを表示し、前日以前に閉じたタスクを表示しないことがテストで確認されている。
- [ ] Homeは既定Inboxの通常リスト表示ではなくTodayスマートビューを表示し、既定Inbox以外の通常リスト由来タスクも表示できることがwidget testで確認されている。
- [ ] TodayでAdd taskすると、既定Inboxにタスクが作成され、`due_at` が今日のローカル日付に設定されることがwidget testまたはcore_usecases testで確認されている。
- [ ] Todayビューにはリスト操作メニュー（改名 / アーカイブ / 削除）と手動並び替えUIが表示されず、通常リスト画面の操作メニューと手動並び替えは退行していない。
- [ ] Lists画面は `Today -> 通常リスト -> New list -> Archived` の順で表示され、Today行タップでHomeへ遷移することがwidget testで確認されている。
- [ ] Todayビューのタスク行には日付pill + 所属リスト名pillが表示され、通常リスト画面には所属リスト名pillが表示されないことが確認されている。
- [ ] Today対象のサブタスクが、親タスクがToday対象外でも表示され、行表示が破綻しないことがwidget testまたはvisual QAで確認されている。
- [ ] `home_tasks` 系visual QAスクリーンショットで、Todayスマートビュー、既定Inbox以外のリスト由来行、リスト名pillが確認できる。
- [ ] 完了報告に、Today抽出条件、Closed条件、Add taskの作成先/`due_at`、FRB再生成有無、visual QA証拠、品質ゲート結果が記録されている。

## 7. 制約・注意事項

- Todayの「今日」は端末ローカル日付で判定する。Rust側にローカルタイムゾーン推測を持ち込まず、Dart側で `[today_start_ms, today_end_ms)` を計算して渡す。
- `due_at < today_end_ms` をToday対象の基本条件にすることで、今日と期限超過をまとめて扱う。`due_at IS NULL` は対象外である。
- Closedセクションは既存の開閉UI、再オープン挙動、`done` / `wont_do` 判定を維持する。ただしTodayでは「当日閉じたToday対象タスク」に限定する。
- Todayは横断ビューであり、永続リストではない。`ListDto` を偽造してTodayを通常リストとして扱う実装は避ける。
- Todayビューで手動並び替えを有効にしない。横断ビューでは同一リスト/同一親の `sort_order` を安全に編集できないためである。
- Today Add taskの作成先は、task-46で導入された `isDefault == true` の既定Inboxである。`lists.first` や `sort_order` 先頭を使わない。
- FRB生成物は手編集しない。Rust APIを変更した場合は必ずFRB再生成を行う。
- UI文字列はARB化する。`Today`、`Smart Lists`、リストpill用の見出し/tooltip等をDartへ直書きしない。
- visual QAはライトモードを必須証拠とする。ダークモード正式対応は直近スコープ外である。
- 新規依存は追加しない。必要に見える場合は完了報告の未解決事項に記録する。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- Today抽出API/DTOの実装箇所、`today_start_ms` / `today_end_ms` の計算方法、storageクエリ条件
- Closedセクションの条件（`done` / `wont_do`、`completed_at` の日付範囲、`due_at` 条件）
- FRB再生成の実行結果、生成物の変更範囲
- Dart provider / BridgeService / FakeBridgeService の追加内容
- HomeをTodayスマートビューへ変更した実装箇所、ヘッダーpillの扱い、リスト操作メニュー非表示の実装箇所
- Today Add taskの作成先、`due_at` 設定値、通常リストAdd taskへの影響がないこと
- Lists画面のToday行追加と表示順
- Todayビュー限定のリスト名pill実装、サブタスク表示の扱い
- 追加・更新したl10nキー
- 追加・更新したテスト名と検証対象
- visual QA before/afterスクリーンショットの保存パス（必須: `home_tasks` 系、Lists画面、リストpill付き行）
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）
