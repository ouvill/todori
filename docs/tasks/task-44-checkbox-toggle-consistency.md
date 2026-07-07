# task-44: チェックボックストグル一貫性とUndoスナックバー調整

> ステータス: 完了（2026-07-07実装）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

2026-07-07ドッグフーディング第2回で、同じ見た目のチェックボックスが場所によって操作できたりできなかったりする問題が見つかった。具体的には、一覧のClosedセクション、ネストされたサブタスク、詳細画面のSubtasks、アーカイブ済みリストを開いた画面で、チェックボックスが閲覧専用に見える箇所がある。

Todoriでは、チェックボックスはタスク状態を直接切り替える主要操作である。表示されている以上は常にトグル可能でなければならない。未完了タスクは `done` へ、`done` / `wont_do` は `todo` へ戻す。未完了子孫がある親を完了する場合の確認ダイアログは、既存どおり維持する。

同じドッグフーディングで、Undoスナックバーが残り続ける挙動も指摘された。本タスクではチェック操作の一貫性と、Undoスナックバーの自動消滅/重複抑制だけを直す。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（タスク行、タスク一覧構造、Task detail、Undoスナックバー）
- `app/lib/src/ui/task_components.dart`（チェックボックス表示、階層ガイド描画）
- `app/lib/src/screens/tasks_screen.dart`（一覧、Closedセクション、アーカイブ済みリスト表示）
- `app/lib/src/screens/task_detail_screen.dart`（インライン編集、Subtasks一覧、Undoスナックバー）
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`

## 3. ゴール

- すべてのタスクチェックボックスを常時トグル可能にする。
- 未完了タスクのチェックは `done`、Closedタスク（`done` / `wont_do`）のチェック解除は `todo` に統一する。
- ルート行だけでなく、ネストされたサブタスク行と詳細画面のSubtasks行でも同じ挙動にする。
- アーカイブ済みリストを開いた画面でも、チェックボックスが通常リストと同様に反応するようにする。
- Undoスナックバーを4秒程度で自動消滅させ、Undo実行後・新しいスナックバー表示時に既存スナックバーを隠す。
- 上記をwidget testで退行検出できるようにする。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`（必要な場合のみ）
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`（テストデータ追加が必要な場合）
- `docs/tasks/task-44-checkbox-toggle-consistency.md`（完了報告の追記のみ）

### やること

1. **すべてのタスクチェックボックスを常時トグル化する**
   - 未完了（`todo` / `in_progress`）タップは `done` へ遷移させる。
   - Closed（`done` / `wont_do`）タップは `todo` へ遷移させる。
   - 既存の「未完了子孫がある親タスクを完了する確認ダイアログ」は維持する。
   - Closedを `todo` に戻す場合は確認ダイアログを出さない。
2. **一覧のルート行・ネスト行の両方を対象にする**
   - Activeセクション、Closedセクション、親がClosedで配下に表示されるサブタスクを含め、`AppTaskRow` が表示するチェックボックスを閲覧専用にしない。
   - `done -> todo -> done` の往復が同じ行でできることを確認する。
3. **詳細画面のSubtasks行もトグル動作にする**
   - 詳細画面のSubtasks行のチェックボックスから状態を切り替えられるようにする。
   - 行タップでサブタスク詳細へ遷移する挙動は維持する。
   - チェック操作と行タップが競合しないよう、タップ領域とイベント伝播を確認する。
4. **アーカイブ済みリストを開いた画面でも操作可能にする**
   - task-37の「編集制限を新設しない」方針どおり、アーカイブ済みリスト内のタスクも通常リストと同じ状態変更を許可する。
   - リストのアーカイブ状態を理由にチェックボックスを無効化しない。
5. **Undoスナックバーを調整する**
   - 完了・編集など既存Undo対象操作で表示されるスナックバーに `duration` を明示し、4秒程度で自動消滅させる。
   - 新しいUndoスナックバーを出す前に既存スナックバーを隠す。
   - Undo action実行後は、既存のUndoスナックバーを隠してから成功/失敗メッセージを表示する。
6. **widget testを追加・更新する**
   - 一覧ルート、一覧ネスト、詳細画面Subtasks、アーカイブ済みリストでのトグルを検証する。
   - `done -> todo -> done` の往復を検証する。
   - スナックバーが `pump` による時間経過で消えることを検証する。

### やらないこと

- 階層ガイドの描画修正（task-45で扱う）。
- 詳細画面Subtasksの子孫ツリー全体表示（task-45で扱う）。
- 詳細画面タイトル/ノート編集開始時のレイアウトがたつき解消（task-45で扱う）。
- Rust/domain/storage/FRB APIの変更。既存の `set_task_status` / `TasksNotifier.setStatus` で足りる想定で進める。
- スマートリスト、Inbox自動プロビジョニング、リスト一覧Todayリンク。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、現在どこで `onToggleDone: null` やClosed/アーカイブ条件による無効化が発生しているかを特定する。
3. `TasksScreen` 側に、タスク状態から次状態を決める小さな関数または既存メソッドの整理を行う。未完了は完了処理、Closedは再オープン処理へ通す。
4. Active/Closedのセクション差やroot/subtask差でチェックボックスが無効にならないよう、`_buildTaskRow` から渡す `onToggleDone` を見直す。
5. `TaskDetailScreen` のSubtasks行にも、一覧と同じ状態遷移を配線する。行タップ遷移は維持する。
6. アーカイブ済みリストを開いた画面のデータ経路を確認し、アーカイブ状態を理由に状態変更を止めている条件があれば取り除く。
7. `_showLatestUndoSnackBar` / `_applyUndo` 周辺で、既存スナックバーの非表示、`duration`、Undo実行後の表示順を整える。
8. `FakeBridgeService` のシードやhelperを必要最小限で追加し、widget testで一覧ルート/ネスト/詳細/アーカイブ済み/往復/スナックバー消滅を検証する。
9. 共通受け入れ基準の品質ゲートを実行する。
10. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 一覧の未完了ルートタスクのチェックボックスをタップすると `done` になり、未完了子孫がある場合は既存確認ダイアログが表示される。
- [ ] 一覧のClosedルートタスク（`done` / `wont_do`）のチェックボックスをタップすると、確認ダイアログなしで `todo` に戻る。
- [ ] ネストされたサブタスク行でも、未完了→`done`、Closed→`todo` のトグルが動作する。
- [ ] 詳細画面のSubtasks行のチェックボックスで状態をトグルでき、行タップによる詳細遷移は維持されている。
- [ ] アーカイブ済みリストを開いた画面でも、表示されているタスクチェックボックスが通常リストと同じようにトグルできる。
- [ ] `done -> todo -> done` の往復操作がwidget testで検証されている。
- [ ] Undoスナックバーは4秒程度の時間経過を `pump` した後に消え、Undo実行後・新しいスナックバー表示時に既存スナックバーが残らないことがwidget testで検証されている。
- [ ] Rust/domain/storage/FRB API、DB schema、生成FRBファイルに変更がない。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` セクション3のチェックボックス規則を正とする。
- 「見た目はチェックボックスだが操作できない」状態を残さない。どうしても操作不可にする必要がある条件を見つけた場合は、実装を止めず最小の暫定解を取り、完了報告の未解決事項に理由を書く。
- 未完了子孫を持つ親の完了確認は、既存のプロダクト仕様として維持する。
- Closedから `todo` へ戻す操作は、Undoスナックバーの新規仕様を増やさなくてよい。既存のUndo対象が `done` / `wont_do` への遷移と編集である前提を維持する。
- `AppTaskRow` のチェックボックスは48×48級タップ領域、tooltip/semantics、円形表示を維持する。
- 詳細画面Subtasksでチェックボックスをタップしたとき、親 `InkWell` の行タップ遷移が同時に発火しないようにする。
- i18n文言の追加が必要な場合はen/ja ARBへ追加し、生成物は `flutter gen-l10n` の生成差分のみとする。
- アーカイブ済みリストに編集制限を新設しない。task-37の方針と矛盾させない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- チェックボックス常時トグル化の実装箇所
- 一覧ルート、一覧ネスト、詳細画面Subtasks、アーカイブ済みリストでの挙動確認内容
- 未完了子孫を持つ親完了確認ダイアログを維持した実装箇所
- Undoスナックバーの `duration`、既存スナックバー非表示、Undo実行後表示の修正内容
- 追加・更新したwidget test名と検証対象
- l10nキーを追加・更新した場合はその一覧
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-07

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/task-44-checkbox-toggle-consistency.md`
- `docs/design/ui-spec.md`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`

実装結果:

- `app/lib/src/screens/tasks_screen.dart` の `_buildTaskRow` で、Completedセクション内の未完了タスクに `onToggleDone: null` を渡す条件を削除した。
- 一覧の `AppTaskRow` は、`done` / `wont_do` では `todo` へ、未完了では既存の `_completeTask` 経由で `done` へ遷移する。
- 未完了子孫を持つ親完了確認ダイアログは、`TasksScreen._completeTask` と `TaskDetailScreen._setTaskStatus` の既存処理を維持した。
- `app/lib/src/screens/task_detail_screen.dart` のSubtasks行に `checkboxKey`、`toggleDoneTooltip`、`onToggleDone` を追加し、行タップの詳細遷移は `onTap` のまま維持した。
- `app/lib/src/screens/tasks_screen.dart` と `app/lib/src/screens/task_detail_screen.dart` のUndoスナックバーで、表示前に `hideCurrentSnackBar()` を呼び、`duration: Duration(seconds: 4)` と `persist: false` を指定した。
- Undo action実行時は、Undo適用前に既存スナックバーを隠してから成功/失敗メッセージを表示するようにした。
- l10nキーの追加・更新はなし。
- Rust/domain/storage/FRB API、DB schema、生成FRBファイルの変更はなし。

挙動確認:

- `nested task row checkbox toggles done todo done`: 一覧ネスト行で `todo -> done -> todo -> done` の往復を検証した。
- `open child under a closed parent remains toggleable`: Closed root配下に表示される未完了子タスクのチェックボックスが有効で、タップにより `done` へ遷移することを検証した。
- `detail subtask checkbox toggles without triggering row navigation`: 詳細画面Subtasks行のチェックボックスで `todo -> done -> todo` を検証し、行タイトルタップによる詳細遷移を検証した。
- `archived list task checkbox toggles like an active list`: アーカイブ済みリストを開いた画面で、タスクチェックボックスにより `todo -> done -> todo` を検証した。
- `undo snackbar disappears after four seconds`: 時間経過pump後にUndoスナックバーが消えることを検証した。
- `undo action hides the undo snackbar before success`: Undo実行後に元のUndoスナックバーが残らず、成功メッセージが表示されることを検証した。

検証結果:

- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功
- `cd app && flutter analyze`: 成功
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter test`: 成功（62件、skip 1件）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `sh app/tool/visual_qa.sh`: 成功（30 PNG生成）
- `git diff --check`: 成功
- `app/build/visual_qa/` のPNGを作業前に `app/build/visual_qa_before/` へコピーした。`app/build/visual_qa_before/` には、コピー対象30枚に加えて既存の `trash.png` が残っている。`rm -f app/build/visual_qa_before/trash.png` は実行ポリシーにより拒否された。

変更ファイル一覧:

- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-44-checkbox-toggle-consistency.md`

未解決事項:

- なし
