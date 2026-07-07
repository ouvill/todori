# task-48: Lucideアイコン統一

> ステータス: 完了（worker実装）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

2026-07-06人間裁定により、本番UIのアイコンセットは `lucide_icons_flutter` に統一することが決定済みである。`docs/design/ui-spec.md` は、全画面でLucideへ統一し、Material Iconsと同一画面で混在させず、tooltip/semanticsを維持することを拘束規則としている。

task-43以降の本番UIには一部Lucideが導入済みだが、既存Material Icons由来の `Icons.*` が残っている。本タスクでは本番画面から参照される全Material IconsをLucide相当へ置換し、画面単位の混在を解消する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション2〜4、裁定済み事項（Lucide統一）
- `app/pubspec.yaml`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- 本番UIから参照される `Icons.*` を `LucideIcons.*` へ置換する。
- Home / Lists / Task list / Task detail / 作成シートなど、本番画面内でMaterial IconsとLucideが混在しない状態にする。
- icon-only controlのtooltip/semantics、48px級タップ領域、既存の色・サイズ・レイアウト意図を維持する。
- widget testのicon finderをLucide相当へ追従させる。
- visual QAスクリーンショットを目視し、Materialアイコン残存と視覚バランスを確認する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-48-lucide-icons.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. `app/lib/` 配下の本番コードで `Icons.*` を検索し、すべてLucide相当へ置換する。
2. Materialアイコンの意味・役割に近いLucideアイコンを選ぶ。対応表は本指示書の「Material→Lucide対応表」を正とする。
3. 既存のtooltip/semantics、ボタンのヒット領域、色、状態分岐、l10n文言を維持する。
4. Lucideの線画で細く/小さく見える箇所は、`docs/design/ui-spec.md` のサイズ・間隔・色トークン内で `size` を微調整してよい。
5. widget testの `find.byIcon(...)` をLucide相当へ追従させる。
6. `grep` で本番 `app/lib/` のMaterial `Icons.` 残存ゼロを確認する。`LucideIcons.` は残存扱いしない。
7. `visual_qa.sh` 実行前に既存スクリーンショットを退避し、出力された全スクリーンショットを目視する。
8. 完了時に `docs/tasks/README.md` と `docs/tasks/BACKLOG.md` を更新し、本指示書へ `## 9. 完了報告` を追記する。

### やらないこと

- Design Lab / visual QA test harness専用モック内のMaterial Icons置換。ただし本番画面から参照されるアイコンは対象に含める。
- 新規pub/crate依存の追加。`lucide_icons_flutter` は導入済みのものを使う。
- アイコン統一に関係しないレイアウト刷新、色変更、文言変更。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。
- FRB/Rust API変更。

### Material→Lucide対応表

| Material Icons | Lucide |
|---|---|
| `Icons.arrow_back` | `LucideIcons.arrowLeft300` |
| `Icons.home_outlined` | `LucideIcons.house300` |
| `Icons.add` | `LucideIcons.plus300` |
| `Icons.more_horiz` | `LucideIcons.moreHorizontal300` |
| `Icons.menu` | `LucideIcons.menu300` |
| `Icons.sort` | `LucideIcons.arrowDownUp300` |
| `Icons.keyboard_arrow_up` | `LucideIcons.chevronUp300` |
| `Icons.keyboard_arrow_down` | `LucideIcons.chevronDown300` |
| `Icons.chevron_right` | `LucideIcons.chevronRight300`（finder追従用） |
| `Icons.edit_outlined` | `LucideIcons.squarePen300`（finder追従用） |
| `Icons.event_outlined` / `Icons.calendar_month_outlined` | `LucideIcons.calendarDays300` |
| `Icons.today_outlined` | `LucideIcons.calendarCheck300` |
| `Icons.event_available_outlined` | `LucideIcons.calendarPlus300` |
| `Icons.clear` | `LucideIcons.x300` |
| `Icons.flag_outlined` | `LucideIcons.flag300` |
| `Icons.account_tree_outlined` | `LucideIcons.gitBranch300` |
| `Icons.subdirectory_arrow_left_outlined` | `LucideIcons.cornerUpLeft300` |
| `Icons.list_alt_outlined` | `LucideIcons.listTodo300` |
| `Icons.checklist_outlined` | `LucideIcons.listChecks300` |
| `Icons.archive_outlined` | `LucideIcons.archive300` |
| `Icons.circle_outlined` / `Icons.radio_button_unchecked` | `LucideIcons.circle300` |
| `Icons.check_circle_outline` | `LucideIcons.circleCheck300` |
| `Icons.do_not_disturb_on_outlined` | `LucideIcons.ban300` |
| `Icons.timelapse_outlined` | `LucideIcons.clock300` |
| `Icons.search_off_outlined` | `LucideIcons.searchX300` |
| `Icons.error_outline` | `LucideIcons.alertCircle300` |

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、既存のLucide importと `LucideIcons.*300` の使い方を把握する。
3. `app/lib/` の `Icons.*` を検索し、本番UIから参照される箇所を対応表に従って置換する。
4. 必要なファイルへ `package:lucide_icons_flutter/lucide_icons.dart` importを追加する。
5. `SlidableAction.icon`、`PopupMenuButton.icon`、`AppEmptyState.icon`、metadata pillなど、`IconData` を受ける箇所でもLucideの `IconData` を渡す。
6. widget testの `find.byIcon` をLucide相当へ追従させる。
7. `dart format` を実行し、`grep` で本番 `Icons.` 残存ゼロを確認する。
8. 品質ゲートとvisual QAを実行し、スクリーンショットを目視する。
9. README/BACKLOGを更新し、本指示書末尾に完了報告を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `app/lib/` の本番UIにMaterial `Icons.*` が残っていないことがgrep結果で確認されている（`LucideIcons.*` は除外）。
- [ ] Home / Lists / Task list / Task detail / タスク作成シートでLucideへ統一され、同一画面内にMaterial Iconsが混在していない。
- [ ] icon-only controlのtooltip/semanticsと48px級タップ領域が維持されている。
- [ ] widget testのicon finderがLucide相当へ追従している。
- [ ] `home_tasks` / `lists` / `task_detail` / `task_create_sheet_home` を含むvisual QA全スクリーンショットを目視し、Materialアイコン残存なし・視覚バランスに破綻なしを確認している。
- [ ] 完了報告にMaterial→Lucide対応表の要約、grep証拠、visual QAスクリーンショット目視結果、品質ゲート結果が記録されている。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` のLucide統一裁定を正とする。
- 本番UIから参照されるアイコンはすべて対象に含める。Design Lab / test harness専用モックは対象外でよい。
- 置換で操作意味を変えない。tooltip、semantics、l10nキー、タップ領域、状態遷移を維持する。
- アイコンのサイズ調整は既存トークン内に留める。新しい色・角丸・面・影を追加しない。
- `lucide_icons_flutter` の既存導入を使い、新規依存は追加しない。
- UI文字列を追加しない。必要になった場合はARB化する。
- Rust API変更は行わない。FRB再生成は不要の想定である。
- コミットは本タスク実行者の指示に従う。本統合runではコミットしない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 変更ファイル一覧
- Material→Lucide対応表の要約
- 置換した主な画面/部品
- tooltip/semantics/タップ領域維持の確認内容
- widget testで追従したicon finder
- `app/lib/` 本番Material `Icons.` 残存ゼロのgrepコマンドと結果
- visual QAの作業前退避先、出力先、目視したスクリーンショット名、Material残存なし・視覚バランス確認結果
- 品質ゲートの実行結果
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-08

読んだファイル:

- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md`
- `app/pubspec.yaml`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

変更ファイル:

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-48-lucide-icons.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

実装結果:

- 本番UIの `Icons.*` を `LucideIcons.*300` 系へ置換した。
- Home / Lists / Task list / Task detail / タスク作成シート / due date sheet / list actions / sort menu / empty/error state / metadata pill / swipe action でMaterial IconsとLucideの混在を解消した。
- 既存の `IconButton` / `PopupMenuButton` / `SlidableAction` / `OutlinedButton.icon` / `AppEmptyState` / metadata pill のtooltip、semantics、タップ領域、色指定、l10n文言は維持した。
- Lucideの線画は既存サイズ内に収め、追加の色・角丸・影・新規文言は入れていない。

Material→Lucide対応表の要約:

- navigation/menu/action: `arrow_back`→`arrowLeft300`, `menu`→`menu300`, `more_horiz`→`moreHorizontal300`, `sort`→`arrowDownUp300`, `add`→`plus300`, `clear`→`x300`
- list/home/archive: `home_outlined`→`house300`, `list_alt_outlined`→`listTodo300`, `checklist_outlined`→`listChecks300`, `archive_outlined`→`archive300`
- date/priority/tree: `event_outlined`/`calendar_month_outlined`→`calendarDays300`, `today_outlined`→`calendarCheck300`, `event_available_outlined`→`calendarPlus300`, `flag_outlined`→`flag300`, `account_tree_outlined`→`gitBranch300`, `subdirectory_arrow_left_outlined`→`cornerUpLeft300`
- status/state: `radio_button_unchecked`/`circle_outlined`→`circle300`, `check_circle_outline`→`circleCheck300`, `do_not_disturb_on_outlined`→`ban300`, `timelapse_outlined`→`clock300`, `search_off_outlined`→`searchX300`, `error_outline`→`alertCircle300`
- widget test finder: `chevron_right`→`chevronRight300`, `edit_outlined`→`squarePen300`, `keyboard_arrow_down/up`→`chevronDown300`/`chevronUp300`

grep証拠:

```sh
grep -RIn "[^A-Za-z]Icons\\." app/lib 2>/dev/null
```

結果: 出力なし（exit 1）。`app/lib/` の本番Material `Icons.` 残存ゼロを確認した。

visual QA:

- 実行前退避先: `app/build/visual_qa_before_task48/`（既存PNG 39枚を退避）
- 出力先: `app/build/visual_qa/`
- 実行コマンド: `sh app/tool/visual_qa.sh`
- 結果: 成功（`+37: All tests passed!`）
- 目視対象: `home_tasks`, `home_tasks_dark`, `home_tasks_empty`, `home_tasks_ja`, `lists`, `lists_archived`, `list_actions_menu`, `task_detail`, `task_detail_editing`, `task_create_sheet_home`, `task_create_sheet_list`, `quick_add_home_normal`, `quick_add_list_normal`, `task_list_reorder_dragging`, `task_swipe_complete_leading`, `task_swipe_due_trailing`, `wont_do_row`, `delete_task_confirm`, `delete_list_confirm`, `confirm_dialog`, `completion_motion_*`, `design_lab_*` を含む生成済みPNG 39枚。
- 目視結果: Materialアイコンの残存は見当たらず、Lucideの線幅・サイズは既存レイアウト内で破綻していないことを確認した。

品質ゲート:

- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功
- `cd app && flutter analyze`: 成功（No issues found）
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter test`: 成功（`+97 ~1: All tests passed!`）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `sh app/tool/visual_qa.sh`: 成功（`+37: All tests passed!`）
- `git diff --check`: 成功

未解決事項: なし
