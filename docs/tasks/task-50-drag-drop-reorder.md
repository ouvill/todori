# task-50: タスク一覧の手動並び替えD&D化

> ステータス: 完了（長押しドラッグ&ドロップ並び替え）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

task-24でタスク一覧の同一階層内手動並び替えが実装された。現状のUIは、手動ソートモード時に行右端へ上下移動ボタンを表示し、既存 `reorder_task(task_id, previous_task_id, next_task_id)` APIへ境界IDを渡している。

2026-07-07ドッグフーディング第3回で、この上下ボタン方式は実操作として重く、タスク一覧の並び替えはドラッグ&ドロップにしたいことが確認された。本タスクでは、既存のfractional indexと `reorder_task` APIを維持しつつ、入力UIを長押しドラッグ&ドロップへ置き換える。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（タスク行、タスク一覧構造、手動並び替え規則）
- `docs/tasks/task-24-fractional-index.md`（既存並び替えAPI/境界IDの前提）
- `app/lib/src/screens/tasks_screen.dart`（手動並び替えの現実装）
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/rust/src/api.rs` の `reorder_task`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- 手動ソートモード時の並び替え操作を、行右端の上下ボタンから長押しドラッグ&ドロップへ置き換える。
- ドロップ可能な位置は同一親の兄弟間だけに限定する。
- ドロップ時は既存 `reorder_task` APIへ `previous_task_id` / `next_task_id` を渡し、既存の楽観的更新/失敗時挙動に合わせる。
- 上下移動ボタンは画面から撤去する。
- 支援技術からは reorder semantics action（Move up / Move down 相当）で並び替えできる状態を維持する。
- 通常表示、Todayスマートビュー、非手動ソートモードではドラッグ並び替えを有効にしない。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`（行のdrag proxy/semantics/キー調整が必要な場合のみ）
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARB変更時の生成差分のみ）
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-50-drag-drop-reorder.md`（完了報告の追記のみ）

### やること

1. **手動ソートモードで長押しドラッグを開始できるようにする**
   - 通常リストかつ `TaskSortMode.manual` のときだけ、タスク行の長押しでドラッグを開始する。
   - `ReorderableListView` 相当を使うか、`LongPressDraggable` / `DragTarget` で実装するかは、既存の単一Tasksパネル構造・階層ツリー・Closedセクションと共存しやすい方を選ぶ。
   - Todayスマートビュー、期日/優先度/作成順ソート、Closedセクションではドラッグ不可にする。
2. **ドロップ先を同一親の兄弟間だけに制限する**
   - 同じ `parent_task_id` を持つ兄弟同士の前後だけを有効なドロップ位置にする。
   - 別親の間、親子階層をまたぐ位置、Closedセクションとの境界、Today横断ビューではドロップを受け付けない。
   - 無効なドロップ先は吸着しない、または無効表示にする。どちらの表現を選んだかを完了報告に記録する。
3. **既存 `reorder_task` APIを呼ぶ**
   - ドロップ完了時、移動後の同一親兄弟配列から `previous_task_id` / `next_task_id` を計算する。
   - 既存の `_TaskReorderControls` が行っている境界ID計算と意味を揃える。
   - 呼び出しは `TasksNotifier.reorderTask` / `reorder_task` の既存経路を使う。Rust APIやFRB生成物は変更しない想定で進める。
   - 楽観的更新と失敗時の巻き戻し/エラー表示は、既存挙動に合わせる。既存挙動に巻き戻しがない場合は、その事実とリスクを完了報告へ記録する。
4. **上下移動ボタンを撤去し、アクセシビリティを維持する**
   - `_TaskReorderControls` 相当の可視ボタンを撤去する。
   - 支援技術ではreorder semantics action（Move up / Move down相当）で同一親内の前後移動ができるようにする。Flutter標準のreorder semanticsを使える場合はそれを優先する。
   - 標準semanticsが使えない構造を選んだ場合は、`CustomSemanticsAction` 等で同等のMove up / Move down操作を提供する。
   - 既存の `moveTaskUpTooltip` / `moveTaskDownTooltip` 文言を流用できる場合は流用し、追加文言が必要ならen/ja ARBへ追加する。
5. **ドラッグ中の視覚表現を整える**
   - 掴んだ行を軽く持ち上げる表現は許容する。ただしui-specの影規則の例外として、elevationは1〜2dp程度までに留める。
   - ドロップ位置インジケータは1pxライン等の静かな表現にする。
   - 単一Tasksパネル内で行が大きく跳ねたり、階層ガイドが誤った親子関係を示したりしないようにする。
6. **テストとvisual QAを追加・更新する**
   - widget testで、同一親内のドラッグ並び替えが `reorder_task` 相当を正しい `previous_task_id` / `next_task_id` で呼ぶことを確認する。
   - widget testで、別親へのドロップが無効であることを確認する。
   - widget testで、非手動ソート時とTodayスマートビューではドラッグできないことを確認する。
   - widget testで、reorder semantics action（Move up / Move down相当）が存在し、同一親内の移動を呼び出せることを確認する。
   - visual QAで通常表示のリグレッションがないことを確認する。必要なら手動ソートモードの静止状態スクリーンショットも追加する。

### やらないこと

- リスト自体の並び替え。
- 階層間移動、親付け替え、インデント/アウトデント。
- Todayスマートビューでの並び替え。横断ビューは対象外のままにする。
- `sort_order` / fractional indexアルゴリズム、Rust/domain/storage/FRB APIの変更。
- タスク詳細画面の親リンク・全幅タップ・タイトル横チェック（task-49で扱う）。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、`_TasksBody._buildTaskRow`、`_siblingsOf`、`_TaskReorderControls`、`TasksNotifier.reorderTask`、`reorder_task` の境界ID仕様を把握する。
3. 既存の `activeNodes` / `completedNodes` / `_TasksPanel` 構造を崩さずにD&Dを入れる方式を決める。`ReorderableListView` を使う場合は、単一Tasksパネルと階層ガイドの表示が崩れないことを先に小さく確認する。
4. 手動ソートモード時だけ、active行へドラッグ開始処理と有効ドロップ位置を追加する。Closed行、Today、非手動ソートでは無効にする。
5. 同一親の兄弟配列を基準に、移動先slotから `previous_task_id` / `next_task_id` を計算する。先頭移動ではprevious=null、末尾移動ではnext=nullになることを確認する。
6. ドロップ完了時に既存 `widget.onMoveTask` を呼び、失敗時の表示/巻き戻しが既存実装と同等か確認する。
7. `_TaskReorderControls` と可視の上下ボタン表示を撤去する。不要になったl10nキーは、他で使っていなければ削除してよい。ただしsemanticsで流用する場合は残す。
8. reorder semantics actionを確認し、widget testでMove up / Move down相当のactionが存在することと、実行時に正しい境界IDが渡ることを検証する。
9. ドラッグ中proxyとドロップインジケータをui-specの影/線規則に合わせる。
10. widget testとvisual QAを更新し、通常表示のリグレッション、D&D、無効ドロップ、非手動ソート無効、semanticsを確認する。
11. 共通受け入れ基準の品質ゲートを実行する。
12. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 手動ソートモードの通常リストで、タスク行の長押しドラッグにより同一親内の順序を変更できることがwidget testで確認されている。
- [ ] 同一親内の並び替えで、先頭/中間/末尾への移動時に `reorder_task` 相当へ正しい `previous_task_id` / `next_task_id` が渡ることがwidget testで確認されている。
- [ ] 別親の兄弟間、親子階層をまたぐ位置、Closedセクション境界へのドロップが無効であることがwidget testで確認されている。
- [ ] 期日/優先度/作成順ソート時、Todayスマートビュー、Closedセクションではドラッグ並び替えができないことがwidget testで確認されている。
- [ ] 可視の上下移動ボタン（`_TaskReorderControls` 相当）が画面に表示されないことがwidget testで確認されている。
- [ ] 支援技術向けのreorder semantics action（Move up / Move down相当）が存在し、同一親内の前後移動を呼び出せることがwidget testで確認されている。
- [ ] ドラッグ中proxyとドロップ位置インジケータは、ui-specの影/線規則に従い、通常表示の行密度と階層ガイドを崩していないことがvisual QAで確認されている。
- [ ] 通常表示のvisual QAスクリーンショットに、上下移動ボタン撤去以外の意図しない見た目の退行がないことが確認されている。
- [ ] Rust/domain/storage/FRB API、DB schema、生成FRBファイルに変更がない。
- [ ] 完了報告に、採用したD&D実装方式、有効/無効ドロップ判定、境界ID計算、semantics対応、visual QA証拠、品質ゲート結果が記録されている。

## 7. 制約・注意事項

- 並び替えは同一親内だけに限定する。D&D導入を理由に、親付け替えや階層移動を暗黙に実装しない。
- Todayスマートビューは横断ビューであり、手動並び替え対象外である。Todayで `sort_order` を変更しない。
- `reorder_task` APIの `previous_task_id` / `next_task_id` は、移動後の同一親兄弟における隣接境界を表す。別親のIDや移動対象自身のIDを渡してはならない。
- `ReorderableListView` を使う場合でも、Closedセクション、Subtasks階層ガイド、単一Tasksパネルの見た目が崩れるなら、より局所的な `LongPressDraggable` / `DragTarget` 実装を選ぶ。
- 上下移動ボタンは可視UIから撤去するが、アクセシビリティ上のMove up / Move down相当操作は残す。
- ドラッグ中の影はui-specの例外として最小限（1〜2dp程度）に留める。強いカード化、派手な色、装飾的なdrop zoneを追加しない。
- 新規依存は追加しない。必要に見える場合は完了報告の未解決事項に記録する。
- UI文字列はARB化する。semantics/custom actionラベルをDartへ直書きしない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 採用したD&D実装方式（`ReorderableListView` / `LongPressDraggable` 等）と、その選定理由
- 手動ソートモードだけでドラッグを有効化した実装箇所
- 同一親兄弟判定、有効/無効ドロップ判定、無効表示または吸着抑止の実装箇所
- `previous_task_id` / `next_task_id` の計算方法と、既存 `reorder_task` 呼び出し経路
- 楽観的更新と失敗時挙動を既存挙動へ合わせた内容
- 上下移動ボタン撤去箇所、reorder semantics action対応箇所
- ドラッグ中proxyとドロップインジケータの視覚仕様
- 追加・更新したl10nキー
- 追加・更新したwidget test名と検証対象
- visual QAスクリーンショットの保存パス
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
- `docs/tasks/task-24-fractional-index.md`
- `docs/tasks/task-50-drag-drop-reorder.md`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/rust/src/api.rs`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

### 実装結果

- 作業前に `app/build/visual_qa/*.png` を `app/build/visual_qa_before/` へコピーした。
- `app/lib/src/screens/tasks_screen.dart` で、手動ソートモードの通常リストだけ `LongPressDraggable` + `DragTarget` による行ドラッグを有効化した。
- Todayスマートビュー、非手動ソート、Closedセクション、closed task は D&D 対象外のままにした。
- `_TaskReorderControls` と可視の上下移動ボタンを撤去した。
- `DragTarget.onWillAcceptWithDetails` で、同一 `listId` かつ同一 `parentTaskId` のactive兄弟だけを受け付けるようにした。別親、親子階層またぎ、Closed行は `DragTarget` 不在またはaccept falseにより吸着せず、drop indicatorも表示しない。
- ドロップ先は同一親兄弟配列上の source/target index で判定した。source が target より前なら target 後、source が target より後なら target 前へ挿入する。
- `previousTaskId` / `nextTaskId` は、移動対象を除いた兄弟配列に挿入位置を適用して算出した。先頭は `previousTaskId=null`、末尾は `nextTaskId=null`。
- 既存の `TasksNotifier.reorderTask` から `BridgeService.reorderTask` / Rust `reorder_task` へ渡す経路を使用した。Rust API、FRB生成物、DB schema は変更していない。
- 既存経路は bridge call 後に `ref.invalidateSelf()` する方式で、今回のD&Dでも同じ方式を使用した。Dart側の楽観的並び替えと失敗時巻き戻しは追加していない。
- `CustomSemanticsAction` で `Move task up` / `Move task down` 相当のreorder semantics actionを追加し、既存 `moveTaskUpTooltip` / `moveTaskDownTooltip` を流用した。
- ドラッグ中proxyは `Material(elevation: 1)`、drop indicatorは1px lineにした。
- ARBキーの追加・削除はない。

### 追加・更新したテスト

- `app/test/widget_test.dart`
  - `task list drag and drop reorders root tasks with boundaries`: root taskのD&Dで先頭・中間・末尾境界の `previousTaskId` / `nextTaskId` を検証。
  - `task drag and drop rejects different parent and closed targets`: 別親へのdrop拒否、Closed行にdrop targetがないことを検証。
  - `task sort menu switches root order and drag targets`: 非手動ソート時にdrop targetがないことを検証。
  - `subtask semantics reorder keeps the same parent and depth`: Move up / Move down semantics actionの存在と、同一親内の境界ID呼び出しを検証。
  - 既存の上下移動ボタン前提の期待値を、drop target / semantics / 可視ボタン不存在の期待値へ更新。
- `app/test/support/fake_bridge_service.dart`
  - `reorderCalls` と `FakeReorderCall` を追加し、UIから渡された `taskId` / `previousTaskId` / `nextTaskId` を検証可能にした。
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - `task_list_reorder_dragging: manual reorder drag state` を追加。

### visual QA証拠

- 生成先: `app/build/visual_qa/`
- 追加スクリーンショット: `app/build/visual_qa/task_list_reorder_dragging.png`
- 作業前退避先: `app/build/visual_qa_before/`

### 品質ゲート結果

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

- `app/lib/src/screens/tasks_screen.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-50-drag-drop-reorder.md`

### 未解決事項

なし
