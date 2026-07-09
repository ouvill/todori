# task-53: タスク行スワイプと軽量モーション

> ステータス: 完了（スワイプ操作・モーション実装、人間体感受入済み）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

2026-07-07 Home改善裁定では、A案（TickTick方向）の操作密度を採用し、タスク行にスワイプ操作と軽いモーションを導入する方針が決まった。`flutter_slidable` と `flutter_animate` の追加は人間承認済みである。

本タスクでは、タスク行のleading swipeを完了、trailing swipeを期日変更に割り当てる。モーションはチェック、完了行の移動、行挿入、セクション開閉に限定し、150〜250ms級の控えめなものにする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（Homeスワイプ/モーション）
- `docs/tasks/DESIGN_PLAYBOOK.md` セクション4（モーションは静止画で検証不能）
- `docs/tasks/task-50-drag-drop-reorder.md`
- `docs/tasks/task-51-home-restructure.md`
- `docs/tasks/task-52-quick-add-bar.md`
- `app/pubspec.yaml`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- `flutter_slidable` と `flutter_animate` を追加する。
- タスク行leading swipeで完了できるようにし、既存チェックボックス/未完了子孫確認/Undo挙動と整合させる。
- タスク行trailing swipeで期日変更シートを開き、Today / Tomorrow / 日付選択を設定できるようにする。
- 長押しD&D並び替えとスワイプ操作が共存することを確認する。
- チェック、完了行がClosedへ移る時、行挿入、セクション開閉に軽量モーションを追加する。
- モーションは静止画で最終判定できないため、人間ドッグフーディングを最終受け入れとすることを完了報告へ明記する。

## 4. スコープ（やること・やらないこと）

### 新規依存（人間承認済み2026-07-07）

- `flutter_slidable`
- `flutter_animate`

追加時は `app/pubspec.yaml` / `app/pubspec.lock` を更新し、依存追加がこの指示書に基づくものであることを完了報告に記録する。

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `app/pubspec.yaml`
- `app/pubspec.lock`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`（期日更新経路が不足する場合のみ）
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARB変更時の生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-53-swipe-and-motion.md`（完了報告の追記のみ）

### やること

1. 依存を追加する。
   - `flutter_slidable` と `flutter_animate` を追加する。
   - 既存Flutter SDK/lockfileと解決できるバージョンを選ぶ。
2. leading swipeで完了する。
   - 未完了行のleading swipeは既存チェック操作と同じ完了処理を呼ぶ。
   - 未完了子孫がある親タスクでは、既存の確認ダイアログと整合させる。
   - 完了後のUndoスナックバー挙動は既存規則を維持する。
   - Closed行のleading swipeを再オープンにするか無効にするかは、既存チェックボックスの再オープン規則との整合を優先し、採用内容を完了報告に記録する。
3. trailing swipeで期日変更する。
   - trailing swipeは軽いbottom sheetまたは同等のシートを開く。
   - 選択肢はToday、Tomorrow、日付選択を含める。
   - 日付選択は既存のdate picker文法があれば流用する。
   - Homeでは期日変更後にセクション移動が起きることを想定し、provider invalidation/再取得を正しく行う。
4. D&Dと共存させる。
   - 通常リストの手動ソートモードでは、長押しD&Dが引き続き使える。
   - スワイプと長押しが競合して、ドラッグ開始やタップ詳細遷移が壊れないことを確認する。
5. 軽量モーションを追加する。
   - チェック時のマイクロアニメーションを追加する。
   - 完了行がClosedへ移る際にフェード/スライドを入れる。
   - 行挿入時に軽いfade/slideを入れる。
   - セクション開閉に150〜250ms級のアニメーションを入れる。
   - easingはFlutter標準または `flutter_animate` の標準的なものを使い、過剰演出、celebration、confettiを入れない。
6. テストと検証を追加・更新する。
   - widget testでleading swipeが完了処理を呼ぶこと、trailing swipeが期日変更シートを開くこと、Today/Tomorrow/日付選択がdue_at更新を呼ぶことを確認する。
   - widget testで、手動ソートモードのD&Dが引き続き可能なことを確認する。
   - visual QA実行前に `app/build/visual_qa/` を `app/build/visual_qa_before/` へ退避し、実装後に `sh app/tool/visual_qa.sh` を実行する。
   - モーションは静止画で検証不能のため、人間ドッグフーディングを最終受け入れとする旨を完了報告に記録する。

### やらないこと

- haptics。
- 自然言語日付解析。
- Homeセクション再構成（task-51）。
- 下部常設クイック追加バー（task-52）。
- タスク削除のスワイプ導線。削除は詳細画面の明示操作+不可逆警告に限定する。
- 派手な演出、celebration、confetti。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、既存の完了処理、再オープン、Undo、期日更新、D&D実装を把握する。
3. `flutter_slidable` / `flutter_animate` を追加し、`flutter pub get` を実行する。
4. `AppTaskRow` または呼び出し側をSlidableで包む方針を決める。D&Dとの競合が少ない構造を優先する。
5. leading actionを既存完了処理へ接続し、確認ダイアログ/Undoと整合させる。
6. trailing actionで期日変更シートを開き、Today/Tomorrow/日付選択を既存update経路へ接続する。
7. チェック/行出入り/行挿入/セクション開閉に150〜250msの軽量モーションを入れる。
8. widget testとvisual QAを更新する。
9. 実機またはSimulatorで短時間操作し、スワイプ、D&D、タップ詳細遷移、キーボード/quick addとの干渉を確認する。
10. 品質ゲートを実行し、指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `flutter_slidable` と `flutter_animate` が `app/pubspec.yaml` / `app/pubspec.lock` に追加され、追加理由が完了報告に記録されている。
- [ ] 未完了タスク行のleading swipeで、既存チェック操作と同じ完了処理、未完了子孫確認、Undo挙動が使われることがwidget testで確認されている。
- [ ] trailing swipeで期日変更シートが開き、Today / Tomorrow / 日付選択からdue_atを更新できることがwidget testで確認されている。
- [ ] Homeで期日変更後、タスクが該当セクションへ移動することがwidget testで確認されている。
- [ ] 通常リストの手動ソートモードで、長押しD&Dとスワイプが共存することがwidget testまたは手動検証で確認されている。
- [ ] タップによる詳細遷移、チェックボックス操作、quick add入力がスワイプ導入で退行していないことがwidget testで確認されている。
- [ ] チェック、完了行移動、行挿入、セクション開閉のモーションが150〜250ms級で、過剰演出がないことを実機/Simulator操作で確認している。
- [ ] visual QA before/afterで静止状態のレイアウト退行がないことが確認されている。
- [ ] モーションは静止画で検証不能のため、人間ドッグフーディングを最終受け入れとする旨が完了報告に明記されている。
- [ ] 完了報告に、スワイプaction、期日変更シート、D&D共存、モーション対象、品質ゲート結果が記録されている。

## 7. 制約・注意事項

- 削除のスワイプ導線を追加しない。2026-07-07削除モデル裁定では、削除は詳細画面の明示操作+不可逆警告に限定されている。
- スワイプ完了は既存チェック操作と同じ安全装置を使う。未完了子孫確認やUndoを迂回しない。
- D&Dは長押し、スワイプは水平ジェスチャであり、同一行に共存する。どちらかを壊す実装を避ける。
- 依存追加は本指示書に明記された2パッケージだけに限定する。
- モーションは150〜250ms級に留める。操作速度を落とす演出、視線を奪う演出、celebration/confettiは禁止する。
- UI文字列はARB化する。スワイプaction、期日変更シート、tooltip/semanticsをDartへ直書きしない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 追加した依存名/バージョン、`flutter pub get` 結果
- leading swipeの実装箇所、既存完了処理/確認/Undoとの接続
- trailing swipeの実装箇所、期日変更シート、Today/Tomorrow/日付選択のdue_at更新内容
- D&Dとの共存確認内容
- 追加したモーション対象、duration、easing
- 追加・更新したl10nキー
- 追加・更新したテスト名と検証対象
- visual QA before/afterスクリーンショットの保存パス
- 実機/Simulatorの手動確認結果
- モーションは静止画で検証不能のため、人間ドッグフーディングを最終受け入れとする旨
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

### 作業日

- 2026-07-07

### 読んだファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/tasks/task-50-drag-drop-reorder.md`
- `docs/tasks/task-51-home-restructure.md`
- `docs/tasks/task-52-quick-add-bar.md`
- `app/pubspec.yaml`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

### 依存追加

- `flutter_slidable: ^4.0.3` を `app/pubspec.yaml` に追加し、`app/pubspec.lock` では `4.0.3` が解決された。
- `flutter_animate: ^4.5.2` を `app/pubspec.yaml` に追加し、`app/pubspec.lock` では `4.5.2` が解決された。
- `flutter_animate` の transitive dependency として `flutter_shaders 0.1.3` が `app/pubspec.lock` に追加された。
- 実行コマンド: `cd app && flutter pub add flutter_slidable:^4.0.3 flutter_animate:^4.5.2`
- 結果: exit 0
- 追加理由: task-53 指示書で人間承認済み依存として指定されているため。

### 実装結果

- `app/lib/src/screens/tasks_screen.dart`
  - `flutter_slidable` の `Slidable` / `ActionPane` / `SlidableAction` でタスク行を包んだ。
  - leading swipeは未完了行で既存 `onCompleteTask` を呼び、未完了子孫確認ダイアログと完了Undoスナックバーの既存経路に接続した。
  - Closed行のleading swipeは既存チェックボックス規則に合わせて `onReopenTask` を呼ぶ再オープンにした。
  - trailing swipeは期日変更シートを開き、Today / Tomorrow / 日付選択を表示する。
  - Todayは `homeLocalRangesMs().todayStartMs`、Tomorrowは `homeLocalRangesMs().tomorrowStartMs`、日付選択は `showDatePicker` の選択日ローカル0時を `due_at` に設定する。
  - 削除のスワイプ導線は追加していない。
- `app/lib/src/core/providers.dart`
  - `TasksNotifier.updateDueDate` を追加し、既存 `updateTask` 経路で期日だけを更新して `homeTasksProvider` を invalidate する。
  - `HomeTasksNotifier.updateDueDate` を追加し、既存 bridge `updateTask` 経路で期日だけを更新して該当 `tasksProvider` と `homeTasksProvider` を invalidate する。
- `app/lib/src/ui/task_components.dart`
  - `AppTaskCheckbox` に `AnimatedSwitcher` による scale/fade を追加した。
- l10n
  - 新規キーは追加していない。
  - 既存キー `markTaskDoneMenuItem` / `reopenTaskMenuItem` / `changeDueDateTooltip` / `dueDateLabel` / `dueToday` / `dueTomorrow` / `setDueDateButton` を使用した。

### D&D共存

- 通常リストの手動ソートモードでは既存 `_TaskDragReorderTarget` / `LongPressDraggable` を維持し、その child として Slidable 行を渡す構造にした。
- `task list drag and drop reorders root tasks with boundaries` で、Slidable key の存在と既存 reorder 境界ID呼び出しを確認した。

### モーション一覧

| 対象 | 実装箇所 | duration | curve | 内容 |
|---|---|---:|---|---|
| チェック状態表示 | `AppTaskCheckbox` | 160ms | `Curves.easeOutCubic` | `AnimatedSwitcher` で scale 0.88→1 と fade |
| 通常タスク行挿入 | `_TaskEntryMotion` | 180ms | `Curves.easeOutCubic` | fade 0→1 と slideY 0.04→0 |
| Homeタスク行挿入 | `_TaskEntryMotion(slide: false)` | 180ms | `Curves.easeOutCubic` | fade 0→1 |
| 完了行がClosedへ移る時のClosed領域開閉 | `_TasksBodyState` Closed section | 200ms | `Curves.easeOutCubic` | `AnimatedSize` |
| Homeセクション開閉 | `_HomeSection` | 200ms | `Curves.easeOutCubic` | `AnimatedSize` |

### テスト

- 追加: `leading swipe completes through confirmation and undo flow`
  - leading swipe actionが未完了子孫確認を表示し、Continue後に完了し、Undoで戻ることを確認。
- 追加: `trailing swipe opens due sheet and updates today tomorrow and picked date`
  - trailing swipeで期日変更シートが開き、Today / Tomorrow / 日付選択から `due_at` が更新されることを確認。
- 追加: `home due swipe moves a task into the tomorrow section`
  - Homeで期日をTomorrowへ変更し、更新後にタスクがTomorrowセクション位置へ移ることを確認。
- 更新: `task list drag and drop reorders root tasks with boundaries`
  - Slidable key が存在する状態でD&D境界ID呼び出しが維持されることを確認。
- 既存: タップ詳細遷移、チェックボックス操作、Quick Add入力は `flutter test` 全体で実行。

### visual QA

- 作業前退避先: `app/build/visual_qa_before/`
- 退避PNG数: 35
- 実装後出力先: `app/build/visual_qa/`
- 実装後PNG数: 37
- 追加スクリーンショット:
  - `app/build/visual_qa/task_swipe_complete_leading.png`
  - `app/build/visual_qa/task_swipe_due_trailing.png`
- 上記2枚を `view_image` で目視確認した。

### 実機/Simulator確認

- 実機/Simulatorでの短時間操作は未実施。
- スワイプ露出は `app/build/visual_qa/task_swipe_complete_leading.png` と `app/build/visual_qa/task_swipe_due_trailing.png` で確認した。
- スワイプ操作、期日更新、D&D共存は `app/test/widget_test.dart` の widget test で確認した。

### モーション最終受け入れ

- モーションは静止画で検証不能のため、最終受け入れは人間ドッグフーディングで行う。

### 品質ゲート

- `cargo fmt --all -- --check`: exit 0
- `cargo clippy --workspace -- -D warnings`: exit 0
- `cargo test --workspace`: exit 0
- `cd app && flutter analyze`: exit 0
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
- `cd app && flutter test`: exit 0（82 passed, 1 skipped）
- `sh app/tool/check_hardcoded_strings.sh`: exit 0
- `sh app/tool/visual_qa.sh`: exit 0（36 passed）
- `git diff --check`: exit 0

### 変更ファイル一覧

- `app/pubspec.yaml`
- `app/pubspec.lock`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-53-swipe-and-motion.md`

### 未解決事項

- 実機/Simulatorでの短時間操作は未実施。モーションの最終受け入れは人間ドッグフーディングで確認する。
