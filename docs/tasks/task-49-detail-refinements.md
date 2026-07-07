# task-49: 詳細画面の親リンク・全幅タップ・タイトル横チェック

> ステータス: 完了（2026-07-07実装）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

2026-07-07ドッグフーディング第3回で、タスク詳細画面について次の3点が見つかった。

- サブタスク詳細を開いたとき、どの親タスク配下のタスクなのかが画面上で分かりにくい。
- タイトル/ノートのインライン編集は、表示テキストそのものをタップしたときだけ起動し、右側の余白をタップしても反応しない。
- 詳細画面のタイトル横に、一覧と同じチェック操作がないため、完了/再オープンの主要操作が詳細画面で見つけにくい。

本タスクでは詳細画面だけを対象に、親リンク、インライン編集の全幅タップ領域、タイトル行チェックボックスの3改善を行う。タスク一覧の手動並び替えD&D化はtask-50で扱う。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（タスク行、Task detail、チェックボックス規則）
- `docs/tasks/task-44-checkbox-toggle-consistency.md`（チェック常時トグル規則）
- `docs/tasks/task-45-tree-guides-and-detail.md`（詳細画面Subtasksの文脈）
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- 詳細画面のタイトル行先頭に、一覧と同じ円形チェックボックスを表示し、同じ状態遷移でトグルできる。
- 未完了子孫を持つ親タスクを詳細画面のタイトル横チェックから完了する場合も、一覧/既存詳細操作と同じ確認ダイアログを表示する。
- Closed状態の詳細タイトルは、既存のClosed行表現と整合する muted + 取り消し線になる。
- 親タスクを持つタスクの詳細では、タイトルの上に直近の親タスク名へのリンク行を表示し、タップで親タスク詳細へ遷移できる。
- タイトル/ノートのインライン編集は、表示テキスト幅ではなく画面コンテンツ幅の行タップで開始できる。
- 追加文言はen/ja ARBへ外部化し、semantics/tooltipを維持する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`（詳細タイトルチェックで一覧部品を再利用/公開する場合のみ）
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARB変更時の生成差分のみ）
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`（テストデータ追加が必要な場合）
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-49-detail-refinements.md`（完了報告の追記のみ）

### やること

1. **タイトル行の先頭に円形チェックボックスを置く**
   - 詳細タイトルの左に、一覧と同じ見た目の円形チェックボックスを置く。
   - 未完了（`todo` / `in_progress`）タップは `done` へ、Closed（`done` / `wont_do`）タップは `todo` へ遷移させる。
   - 未完了子孫を持つタスクを完了する場合は、既存の確認ダイアログを表示する。詳細画面overflowの `mark done` / `wont_do` と矛盾させない。
   - 完了時はタイトルを muted + 取り消し線にし、一覧のClosed表現と整合させる。
   - チェックボックスの48px級タップ領域、tooltip、semanticsを維持する。
2. **親タスクへのリンク行を追加する**
   - `parent_task_id` を持つタスクの詳細では、タイトル上に小さな親リンク行を表示する。
   - 表示は控えめなリンク表現とし、例として上向き階層アイコン + 親タイトル1行省略を用いる。新しい面/カードを増やさない。
   - タップで直近の親タスクのTaskDetailへ遷移する。親も祖父母もいる場合は直近の親のみ表示する。
   - 親タスクが現在の `tasksProvider(listId)` の結果に存在しない場合は、壊れたリンクを出さず、完了報告に観測結果を書く。
   - 親リンクのtooltip/semanticsラベルをen/ja ARBへ追加する。
3. **タイトル/ノートのインライン編集起動領域を全幅化する**
   - 読み取り表示のInkWell/Gesture領域を、Text自体の幅ではなく行のコンテンツ幅いっぱいに広げる。
   - 既存の編集開始時のがたつき防止（同一TextStyle、padding、strut/line-height）を壊さない。
   - タイトルはチェックボックス右側の編集領域全幅、ノートはノート行全幅をタップ対象にする。
   - widget testで、読み取り表示テキストの右側余白をタップしても編集フィールドへ切り替わることを検証する。
4. **テストとvisual QAを追加・更新する**
   - widget testで、タイトル横チェックの未完了→完了、Closed→`todo`、未完了子孫あり親の確認ダイアログを検証する。
   - widget testで、親リンク表示と親詳細への遷移を検証する。
   - widget testで、タイトル/ノートの全幅右端タップによる編集開始を検証する。
   - visual QAで `task_detail.png` にチェック + 親リンク付きの状態を含め、目視確認できるようにする。

### やらないこと

- タスク一覧のドラッグ&ドロップ並び替え（task-50で扱う）。
- パンくず全階層表示。祖父母以上は表示せず、直近の親だけを扱う。
- 詳細画面の期日/優先度/created/Subtasks/actionsなど、上記3改善以外の構造変更。
- Rust/domain/storage/FRB API、DB schema、生成FRBファイルの変更。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、詳細画面の `_InlineTitleEditor` / `_InlineNoteEditor`、`_setTaskStatus`、一覧の `AppTaskRow` / チェックボックス表現を把握する。
3. 詳細画面の現在タスクから `parentTaskId` を読み、同じ `tasks` 一覧内で直近の親タスクを探す。
4. 親タスクが存在する場合だけ、タイトル行より上に親リンク行を表示する。リンク行は1行省略、控えめな色、48px級タップ領域、tooltip/semanticsを持たせる。
5. タイトル表示を「チェックボックス + インラインタイトル編集領域」のRowへ組み替える。チェックボックスは一覧と同じ見た目/サイズ/semanticsに寄せ、状態遷移は既存 `_setTaskStatus` を通す。
6. ClosedタイトルのTextStyleに `TextDecoration.lineThrough` と `onSurfaceVariant` を適用し、編集状態へ入ったときのTextField styleとの関係を確認する。
7. `_InlineTitleEditor` / `_InlineNoteEditor` の読み取りInkWellを `SizedBox(width: double.infinity)`、`ConstrainedBox`、`Row/Expanded` 等で全幅化する。TextField表示時のpadding/strutは維持する。
8. 親リンクsemantics等のl10nキーをen/ja ARBへ追加し、`flutter gen-l10n` を実行する。
9. widget testとvisual QA seedを更新し、チェック、確認ダイアログ、親リンク遷移、全幅右端タップ、`task_detail.png` を確認する。
10. 共通受け入れ基準の品質ゲートを実行する。
11. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 詳細画面タイトル行の先頭に一覧と同じ円形チェックボックスが表示され、未完了タスクを `done` にできることがwidget testで確認されている。
- [ ] 詳細画面タイトル行のチェックボックスでClosedタスク（`done` / `wont_do`）を確認ダイアログなしで `todo` に戻せることがwidget testで確認されている。
- [ ] 未完了子孫を持つ親タスクをタイトル行チェックで完了しようとすると、既存の確認ダイアログが表示されることがwidget testで確認されている。
- [ ] Closed状態の詳細タイトルが muted + 取り消し線で表示され、編集開始時にタイトル位置が不自然にずれないことがwidget testまたはvisual QAで確認されている。
- [ ] 親タスクを持つタスクの詳細に直近の親タスク名リンクが表示され、タップで親TaskDetailへ遷移することがwidget testで確認されている。
- [ ] 親リンクは祖父母を表示せず直近の親のみを表示し、親タイトルが長い場合は1行省略される。
- [ ] タイトル/ノートの読み取り行は、表示テキスト右側の余白タップでも編集状態へ入ることがwidget testで確認されている。
- [ ] 追加/更新したUI文字列はen/ja ARB化され、tooltip/semanticsが直書きされていない。
- [ ] `task_detail.png` のvisual QAスクリーンショットで、タイトル横チェックと親リンク付きの詳細画面が確認できる。
- [ ] Rust/domain/storage/FRB API、DB schema、生成FRBファイルに変更がない。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` セクション3のTask detail規則とチェック常時トグル規則を正とする。
- 詳細タイトル横チェックは、一覧と別の意味を持たせない。未完了は `done`、Closedは `todo`、未完了子孫あり親の確認ダイアログあり、という既存規則へ揃える。
- 親リンクはナビゲーション補助であり、パンくずや階層ツリーではない。祖父母以上を増やして画面密度を上げない。
- 親リンクとタイトル行に新しいカード、強い背景、強い影を追加しない。既存の背景直置き文法を維持する。
- タイトル/ノート編集領域の全幅化で、Subtasks行やmetadata pillのタップ領域と重ならないようにする。
- 既存のoverflowメニュー（mark done / wont_do / reopen / delete）は本タスクで撤去しない。
- UI文字列は必ずARB化する。Material IconsからLucideへの全面置換はtask-48予定の範囲であり、本タスクでは新規追加分だけ既存画面の文法に合わせる。
- visual QAはライトモードを必須証拠とする。ダークモード正式対応は直近スコープ外である。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- タイトル行チェックボックスの実装箇所、再利用/抽出した部品、状態遷移の経路
- 未完了子孫を持つ親完了確認ダイアログを維持した実装箇所
- Closedタイトルのmuted + 取り消し線表現の実装箇所
- 親リンク行の表示条件、親解決方法、遷移先、親が見つからない場合の扱い
- タイトル/ノートの全幅タップ領域化の実装箇所
- 追加・更新したl10nキー
- 追加・更新したwidget test名と検証対象
- visual QAスクリーンショットの保存パス（必須: `task_detail.png`）
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-07

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md`
- `docs/tasks/task-44-checkbox-toggle-consistency.md`
- `docs/tasks/task-45-tree-guides-and-detail.md`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

実装結果:

- `app/lib/src/ui/task_components.dart` の `_TaskRowLeading` を `AppTaskCheckbox` として公開し、`AppTaskRow` と詳細画面タイトル行で同じ円形チェックボックスを使うようにした。
- `app/lib/src/screens/task_detail_screen.dart` の詳細タイトル行を `AppTaskCheckbox` + `_InlineTitleEditor` の横並びにし、未完了は `_setTaskStatus(..., 'done')`、Closedは `_setTaskStatus(..., 'todo')` へ渡すようにした。
- 未完了子孫を持つ親完了確認ダイアログは `TaskDetailScreen._setTaskStatus` の既存分岐を通す実装のまま維持した。
- Closedタイトルの muted + 取り消し線表現は `_InlineTitleEditor` に `isClosed` を渡し、読み取り/編集共通の `headlineSmall` style に `TextDecoration.lineThrough` と `colorScheme.onSurfaceVariant` を適用した。
- 親リンク行は `task.parentTaskId` があり、同じ `tasksProvider(listId)` の結果から直近親が見つかる場合だけ `_ParentTaskLink` を表示する。リンクは親タイトル1行省略、tooltip/semantics付きで、タップ時に `/lists/$listId/tasks/${parentTask.id}` へ遷移する。
- 親が `tasksProvider(listId)` の結果に存在しない場合は `parentTask == null` としてリンクを表示しない分岐にした。visual QA / widget test のseedでは親欠落ケースは観測していない。
- `_InlineTitleEditor` と `_InlineNoteEditor` の読み取り/編集Widgetを `SizedBox(width: double.infinity)` で包み、タイトルはチェックボックス右側の編集領域、ノートは行幅全体をタップ対象にした。
- `app/test/visual_qa/visual_qa_screenshots_test.dart` の `task_detail.png` は、親を持つ `Draft the launch checklist` 詳細を開くようにした。
- Rust/domain/storage/FRB API、DB schema、生成FRBファイルの変更はなし。

追加・更新したl10nキー:

- `parentTaskLinkTooltip`
- `parentTaskLinkSemantics`

追加・更新したwidget test:

- `detail title checkbox marks an open task done`: 詳細タイトル横チェックで未完了タスクを `done` にし、Closedタイトルの取り消し線と `onSurfaceVariant` 色を検証した。
- `detail title checkbox reopens done and wont_do tasks`: 詳細タイトル横チェックで `done` / `wont_do` を確認ダイアログなしで `todo` に戻すことを検証した。
- `detail title checkbox confirms before completing parent with open descendants`: 未完了子孫を持つ親を詳細タイトル横チェックで完了しようとしたとき、確認ダイアログが表示されることを検証した。
- `detail parent link opens the immediate parent task`: 子タスク詳細で直近親リンクだけを表示し、親詳細へ遷移すること、リンクTextが1行省略設定であることを検証した。
- `detail title and note right padding starts inline editing`: タイトル/ノートの右側余白タップでインライン編集に入ることを検証した。
- `detail subtask checkbox toggles without triggering row navigation`: 子タスク詳細遷移後に親リンクが表示される仕様へ期待値を更新した。

visual QAスクリーンショット:

- before退避先: `app/build/visual_qa_before/`
- after: `app/build/visual_qa/task_detail.png`
- `app/build/visual_qa/task_detail.png` を目視し、タイトル上の親リンク行とタイトル横チェックボックスが表示されていることを確認した。

検証結果:

- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功
- `cd app && flutter analyze`: 成功
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter test`: 成功（75件、skip 1件）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `sh app/tool/visual_qa.sh`: 成功（29 PNG生成）
- `git diff --check`: 成功

変更ファイル一覧:

- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/app_localizations.dart`
- `app/lib/src/generated/l10n/app_localizations_en.dart`
- `app/lib/src/generated/l10n/app_localizations_ja.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-49-detail-refinements.md`

未解決事項:

- なし
