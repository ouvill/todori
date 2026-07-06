# task-38: ゴミ箱廃止と恒久削除への移行

> ステータス: 完了（worker実装）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

2026-07-07改訂の `docs/02_機能仕様書.md` F-07 は、タスク削除を恒久削除とし、ゴミ箱を設けず、削除Undoも設けないと定めている。`docs/05_設計判断記録.md` ADR-009 は、E2EEプロダクトとして「削除＝本当に消える」という原則を優先し、履歴の保全経路をリストのアーカイブへ一本化する判断を記録している。`docs/03_技術仕様書.md` も2026-07-07改訂により、`lists.archived_at`、`PRAGMA user_version` ベースのスキーマバージョニング、ローカル削除の恒久削除モデルを反映済みである。

task-23で導入した `/trash` route、`TrashScreen`、`get_trashed_tasks` / `restore_task` / `trash_task`、削除Undoは、この改訂後の仕様と矛盾する。task-37でリストのアーカイブ/解除が実装済みのため、本タスクではゴミ箱を撤去し、タスク・リスト削除を物理DELETE + 不可逆警告の追加確認へ移行する。

`tasks.deleted_at` 列は移行互換のため残置する非推奨列であり、本タスクでDROPしない。将来のv3マイグレーションで廃止する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/02_機能仕様書.md` F-07 / F-09（2026-07-07改訂）
- `docs/03_技術仕様書.md`（特に `lists.archived_at`、schema version、削除/tombstone関連）
- `docs/05_設計判断記録.md` ADR-009
- `docs/design/ui-spec.md`（画面規範、Dialog、coral、Trash撤去予告）
- `docs/tasks/task-23-trash-restore-ui.md`
- `docs/tasks/task-26-undo.md`
- `docs/tasks/task-35-list-rename.md`
- `docs/tasks/task-37-list-archive.md` の完了報告
- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/lib/src/router.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- ゴミ箱画面、ゴミ箱導線、trash/restore系API/provider/test/visual QAを撤去する。
- タスク削除は詳細画面のサブメニュー（overflow menu）からのみ起動し、不可逆警告の追加確認後に物理削除する。
- サブタスクを持つ親タスクの削除時は、子孫も恒久削除されることを件数付きで警告する。
- リスト削除はLists画面の既存「...」メニューから実行し、配下タスク（完了済み含む）ごと物理削除する。
- リスト削除確認では影響件数を明示し、履歴を残す場合はアーカイブを使うよう誘導する。
- 既定インボックス（`sort_order` 最小の通常リスト）は削除不可とする。
- 削除操作のUndo履歴は作らず、完了/編集Undoは引き続き動作する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- FRB生成物（`app/rust/src/frb_generated.rs`、`app/lib/src/rust/` 配下。手編集禁止）
- `app/lib/src/router.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/trash_screen.dart`（削除）
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/design/ui-spec.md`
- `docs/tasks/task-38-trash-removal.md`（完了報告の追記のみ）

### やること

1. **UI route / screen撤去**:
   - `/trash` route、`TrashScreen` import、`trash_screen.dart`、Tasks画面のゴミ箱導線を撤去する。
   - visual QAから `trash.png` 撮影を除去する。
   - `docs/design/ui-spec.md` の「画面規範」Trash項を削除する。
2. **タスク削除UI**:
   - タスク詳細画面の `Move to trash` を「削除」に変更し、詳細画面のサブメニュー（overflow menu）からのみ起動する。
   - 削除実行前に「このタスクは完全に削除され、元に戻せません」という不可逆警告の追加確認ダイアログを表示する。
   - destructive actionは既存themeのcoralを使い、装飾や通常状態には使わない。
   - サブタスクを持つ親タスクでは、子孫も恒久削除されることを件数付きで警告する。
3. **リスト削除UI**:
   - task-35で入れたLists画面の「...」メニューへ「削除」を追加する。配置はアーカイブより下とする。
   - 確認ダイアログでは、完了済みを含む全タスク数を影響件数として明示する。
   - ダイアログ文言に「履歴を残す場合はアーカイブ」へ誘導する文を含める。
   - 既定インボックスは削除不可とし、`name` 文字列ではなく `sort_order` 最小の通常リストを基準にする。
4. **domain / storage**:
   - タスク恒久削除を実装する。物理DELETEであり、対象タスクの子孫も削除する。
   - リスト恒久削除を実装する。物理DELETEであり、配下タスクも削除する。
   - `tasks.deleted_at` 列は残置するが、アクティブ/削除済み判定や削除フローの依存を除去する。
   - `task_undo_entries` の `delete` 型エントリは、既存データの掃除をv3マイグレーションへ委ねるか、本タスク内で読み取り/表示対象外へ整理するかを実装時に判断し、完了報告の未解決事項へ記録する。
5. **Rust bridge / FRB**:
   - `trash_task` / `restore_task` / `get_trashed_tasks` を削除する。
   - タスク恒久削除APIとリスト恒久削除APIを追加する。
   - リスト削除確認に必要な影響件数取得は、専用APIまたは既存取得APIの組み合わせで実現する。
   - Rust API変更後、`flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
6. **Dart bridge / fake / provider / l10n**:
   - `BridgeService` / `FrbBridgeService` / `FakeBridgeService` からtrash/restore系メソッドを削除し、恒久削除APIを追加する。
   - `trashedTasksProvider` を削除する。
   - 削除後は関係する `tasksProvider` / `listsProvider` / `archivedListsProvider` を適切にinvalidateする。
   - `moveToTrashButton`、trash screen系、restore系、削除Undo文言を削除または恒久削除向けキーへ置換し、en/ja ARBと生成localizationsを更新する。
7. **test / visual QA**:
   - trash系widget testを削除または恒久削除フローのテストへ置換する。
   - タスク削除確認、親タスク削除の子孫件数警告、リスト削除の影響件数警告、既定インボックス保護をwidget testで確認する。
   - 削除がUndo対象外であることをテストする。
   - 完了/編集Undoが引き続き動作することをテストする。
   - visual QAに削除確認ダイアログのスクリーンショット（例: `delete_task_confirm.png`、必要なら `delete_list_confirm.png`）を追加する。

### やらないこと

- `tasks.deleted_at` 列のDROP（v3マイグレーションとして別タスク）。
- リストアーカイブ機能の意味論変更、UI変更、読み取り専用化。
- 完了/編集Undo経路の仕様変更。
- 検索、通知、タグ、wont_do/再オープンUI、同期、サーバー、MCP、CLIの実装。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、ADR-009、F-07/F-09、docs/03改訂、task-37完了状態、現行trash/restore/undo経路を把握する。
3. `core/domain` にタスク/リスト恒久削除ユースケースとテストを追加する。
4. `core/storage` に物理DELETE実装を追加し、子孫削除、リスト配下タスク削除、件数取得、Undo履歴非作成をテストする。
5. `app/rust/src/api.rs` からtrash/restore APIを削除し、恒久削除APIと必要な件数取得APIを追加する。
6. FRBを再生成し、Dart bridge/fake/providerを更新する。
7. router、Tasks画面、Task detail、Lists画面、l10nを更新し、ゴミ箱導線と復元UIを撤去する。
8. `docs/design/ui-spec.md` のTrash画面規範を削除する。
9. widget testとvisual QAを更新する。
10. 共通受け入れ基準の品質ゲートを実行する。
11. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `/trash` route、`TrashScreen`、`trash_task`、`restore_task`、`get_trashed_tasks`、`trashedTasksProvider`、trash系l10nキーが存在しないことをgrep結果として完了報告に記録している。
- [ ] タスク削除は詳細画面のoverflow menuからのみ起動し、不可逆警告ダイアログを確認した後に物理DELETEされることがwidget testまたはbridge/storage testで確認できる。
- [ ] サブタスクを持つ親タスクの削除確認で、削除される子孫件数が表示されることがwidget testで確認できる。
- [ ] リスト削除はLists画面の「...」メニューでアーカイブより下に表示され、確認ダイアログに完了済みを含む影響件数と「履歴を残す場合はアーカイブ」への誘導が表示される。
- [ ] 既定インボックス（`sort_order` 最小の通常リスト）は削除できず、この保護がAPI/UIいずれか適切な層のテストで確認できる。
- [ ] 削除操作が `task_undo_entries` の新規Undo対象にならないことがテストで確認できる。
- [ ] 完了Undoと編集Undoが引き続き動作することがテストで確認できる。
- [ ] `tasks.deleted_at` 列はDROPしていないが、削除フロー・一覧取得・復元UIが `deleted_at` に依存していない。
- [ ] visual QAで `trash.png` が生成されず、削除確認ダイアログのスクリーンショット（例: `delete_task_confirm.png`）を完了報告にパス付きで記録している。
- [ ] `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` 実行後の生成物差分がFRB生成物のみで、手編集がない。

## 7. 制約・注意事項

- `docs/03_技術仕様書.md` は本タスク作成前に人間承認済みの外科的修正が入っている。本タスクの実装者は `docs/03` をさらに変更しない。
- `tasks.deleted_at` は非推奨列として残置する。DROP、テーブル再作成、v3マイグレーションは別タスクで行う。
- 削除はUndo対象外である。削除時に `TaskUndoOperation::Delete` 相当の新規履歴を作らない。
- 完了/編集Undoは維持する。Undo機構全体を削除しない。
- 既定インボックス判定は `sort_order` 最小の通常リストを基準にし、`name` 文字列へ依存しない。
- 破壊的操作のcoralは確認ダイアログのdestructive actionに限定し、通常画面の装飾色として使わない。
- FRBは `2.12.0` 固定である。生成物（`frb_generated.*`、`app/lib/src/rust/` 配下）は手編集しない。
- 秘密情報、Device Key、SQLCipher鍵、導出鍵をログ・Debug出力に含めない。
- 新規依存は追加しない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- ADR-009 / F-07改訂 / docs/03改訂から読み取った削除セマンティクス
- 撤去したroute、screen、provider、bridge/API、l10n、test、visual QA項目
- タスク恒久削除、子孫削除、リスト恒久削除、影響件数取得の実装内容
- `tasks.deleted_at` をDROPしていないことと、残した依存/除去した依存の整理
- `task_undo_entries` の `delete` 型エントリについて取った扱い、またはv3へ委ねた事項
- FRB再生成コマンドの実行結果と生成差分の概要
- Dart側の変更内容（BridgeService / FakeBridgeService / providers / UI）
- 追加/更新/削除したl10nキー
- 追加/更新したwidget testと確認対象
- `trash` / `restore` / `/trash` 等のgrep証拠
- visual QAスクリーンショットの保存パス（`delete_task_confirm.png` 等）と `trash.png` が生成されないこと
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（`tasks.deleted_at` v3マイグレーション、既存 `delete` undo履歴、同期導入時のtombstone再設計を含む）

## 9. 完了報告

- 作業日: 2026-07-07
- 読んだファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/BACKLOG.md`
  - `docs/02_機能仕様書.md` F-07 / F-09
  - `docs/03_技術仕様書.md` `lists.archived_at` / schema version / `tasks.deleted_at` / 削除・tombstone関連
  - `docs/05_設計判断記録.md` ADR-009
  - `docs/design/ui-spec.md`
  - `docs/tasks/task-23-trash-restore-ui.md`
  - `docs/tasks/task-26-undo.md`
  - `docs/tasks/task-35-list-rename.md`
  - `docs/tasks/task-37-list-archive.md` 完了報告
  - `core/domain/src/entities.rs`
  - `core/domain/src/usecases.rs`
  - `core/storage/src/schema.sql`
  - `core/storage/src/lib.rs`
  - `app/rust/src/api.rs`
  - `app/lib/src/router.dart`
  - `app/lib/src/core/bridge_service.dart`
  - `app/lib/src/core/providers.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/screens/task_detail_screen.dart`
  - `app/lib/src/screens/lists_screen.dart`
  - `app/lib/src/screens/trash_screen.dart`
  - `app/test/support/fake_bridge_service.dart`
  - `app/test/widget_test.dart`
  - `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - `app/tool/visual_qa.sh`
- ADR-009 / F-07改訂 / docs/03改訂から読み取った削除セマンティクス:
  - タスク削除はローカル物理削除であり、ゴミ箱、復元UI、削除Undoは設けない。
  - タスク削除は詳細画面のサブメニューから起動し、不可逆警告の追加確認を行う。
  - 親タスク削除時は子孫タスクも物理削除する。
  - リスト削除時は配下タスク（完了済みを含む）も物理削除し、履歴を残す場合はアーカイブを使う。
  - `tasks.deleted_at` は移行互換の非推奨列として残し、将来のv3マイグレーションで廃止予定とする。
- 撤去した項目:
  - `/trash` route
  - `TrashScreen` / `app/lib/src/screens/trash_screen.dart`
  - Tasks/home画面のゴミ箱導線
  - `trash_task` / `restore_task` / `get_trashed_tasks`
  - `BridgeService.trashTask` / `restoreTask` / `getTrashedTasks`
  - `trashedTasksProvider`
  - trash/restore系 widget test
  - visual QA `trash.png`
  - trash/restore系 l10n keys
  - 削除Undo snackbar文言
- domain実装:
  - `delete_task` / `restore_task` ユースケースを削除した。
  - `deleted_at` による編集・ステータス遷移・親検証の拒否を削除した。
  - `validate_parent_ignores_legacy_deleted_at_parent` を追加した。
- storage実装:
  - `TaskRepository::count_descendants` / `delete_subtree` を追加した。
  - `SqliteTaskRepository::delete_subtree` は recursive CTE で対象taskと子孫を特定し、同一transactionで対象taskの `task_undo_entries` を削除してから `tasks` を物理DELETEする。
  - `TaskRepository::list_trashed` を削除した。
  - `list_active_by_list` の `deleted_at IS NULL` 条件を削除した。
  - `ListRepository::count_tasks` / `delete_with_tasks` を追加した。
  - `SqliteListRepository::delete_with_tasks` は同一transactionで対象list配下taskのUndo履歴、配下tasks、list行を削除する。
  - `latest_unconsumed_undo` は `operation_type != 'delete'` で既存delete undo entryを表示対象外にした。
  - storage testsを追加/更新した:
    - `delete_subtree_removes_root_descendants_and_undo_entries`
    - `delete_list_removes_tasks_and_task_undo_entries`
    - `delete_undo_entries_are_not_returned_as_latest_undo`
    - `complete_undo_entry_restores_task_state`
    - `complete_undo_rejects_physically_deleted_current_task`
- `tasks.deleted_at` の扱い:
  - `core/storage/src/schema.sql` の `tasks.deleted_at` 列はDROPしていない。
  - `Task` / `TaskDto` / row mapping / update SQL / Undo snapshot互換のための読み書きは残した。
  - `deleted_at IS NULL` / `deleted_at IS NOT NULL` による一覧・削除済み判定は削除した。
- `task_undo_entries` の `delete` 型エントリの扱い:
  - 新規削除操作では `TaskUndoOperation::Delete` を作成しない。
  - 既存 `delete` 型entryは `latest_unconsumed_undo` の表示対象外にした。
  - 物理削除対象taskのUndo entryは削除時に消す。
  - 既存DB全体に残る `delete` 型entryのv3掃除は未実装事項に残した。
- Rust bridge / FRB:
  - 追加: `delete_task(task_id: String) -> Result<(), String>`
  - 追加: `count_task_descendants(task_id: String) -> Result<i32, String>`
  - 追加: `delete_list(list_id: String) -> Result<(), String>`
  - 追加: `count_tasks_in_list(list_id: String) -> Result<i32, String>`
  - 削除: `trash_task` / `restore_task` / `get_trashed_tasks`
  - `delete_list` は `list_all()` の先頭（`sort_order` 最小の通常リスト）を既定インボックスとして拒否する。
  - 実行: `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`
  - 結果: exit 0、出力 `Done!`
  - FRB生成差分: `app/rust/src/frb_generated.rs`、`app/lib/src/rust/api.dart`、`app/lib/src/rust/frb_generated.dart`
- Dart側変更:
  - `BridgeService` / `FrbBridgeService` に `deleteTask`、`countTaskDescendants`、`deleteList`、`countTasksInList` を追加した。
  - `TasksNotifier.deleteTask` は削除後に該当 `tasksProvider` をinvalidateする。`latestTaskUndoProvider` はinvalidateしない。
  - `ListsNotifier.deleteList` は削除後に `listsProvider` / `archivedListsProvider` をinvalidateする。
  - `FakeBridgeService` は物理削除時に対象task/子孫task/関連Undo entryを削除し、list削除時に配下tasks/関連Undo entry/listを削除する。
  - TaskDetailの削除導線をbodyボタンからAppBar overflow menuへ移動した。
  - Tasks/home画面のゴミ箱ボタンを削除した。
  - Lists画面の通常リスト行メニューに `Delete` / `削除` を追加した。既定インボックス行には表示しない。
  - `showAppConfirmDialog` に `isDestructive` を追加し、destructive confirm actionにcoralを適用した。
- l10n:
  - 追加: `deleteButton`
  - 追加: `taskActionsTooltip`
  - 追加: `deleteTaskMenuItem`
  - 追加: `deleteTaskDialogTitle`
  - 追加: `deleteTaskDialogMessage`
  - 追加: `deleteTaskDialogMessageWithDescendants`
  - 追加: `deleteListMenuItem`
  - 追加: `deleteListDialogTitle`
  - 追加: `deleteListDialogMessage`
  - 削除: `moveToTrashButton`
  - 削除: `openTrashTooltip`
  - 削除: `trashTitle`
  - 削除: `trashEmptyTitle`
  - 削除: `trashEmptyBody`
  - 削除: `failedToLoadTrash`
  - 削除: `restoreTaskTooltip`
  - 削除: `undoDeleteMessage`
  - 削除: `taskDeletedAt`
  - 実行: `flutter gen-l10n`
  - 結果: exit 0
- 追加/更新したwidget/FRB tests:
  - `task delete confirms irreversible deletion and removes task`
  - `parent task delete warning includes descendant count`
  - `delete action does not create undo while complete undo remains`
  - `list delete confirms impact count and removes non-default list`
  - `deleteTask permanently deletes descendants without undo`
  - `deleteList removes list and tasks but protects default inbox`
  - 既存の完了Undo・編集Undo testsは維持した。
- grep証拠:
  - 実行: `grep -RIn "trash\|Trash\|restore_task\|get_trashed_tasks\|trash_task\|trashedTasksProvider\|moveToTrash\|undoDeleteMessage\|taskDeletedAt" app/lib app/test app/rust/src core/domain/src core/storage/src docs/design/ui-spec.md | head -n 260`
  - 結果: 出力なし
  - 実行: `grep -RIn "'/trash'\|\"/trash\"\|TrashScreen\|getTrashedTasks\|restoreTask\|trashTask" app/lib app/test app/rust/src core/domain/src core/storage/src | head -n 220`
  - 結果: 出力なし
  - 実行: `grep -RIn "deleted_at IS NULL\|deleted_at IS NOT NULL" core/storage/src app/rust/src app/lib/src | head -n 100`
  - 結果: 出力なし
- visual QA:
  - 作業前に `app/build/visual_qa/*.png` を `app/build/visual_qa_before/` へコピーした。
  - 出力先の古いPNGを `find app/build/visual_qa -maxdepth 1 -type f -name '*.png' -delete` で削除してから再生成した。
  - 実行: `sh app/tool/visual_qa.sh`
  - 結果: exit 0、27 tests passed
  - 生成確認:
    - `app/build/visual_qa/delete_task_confirm.png`
    - `app/build/visual_qa/delete_list_confirm.png`
    - `app/build/visual_qa/confirm_dialog.png`
    - `app/build/visual_qa/home_tasks.png`
    - `app/build/visual_qa/home_tasks_ja.png`
    - `app/build/visual_qa/home_tasks_dark.png`
    - `app/build/visual_qa/home_tasks_empty.png`
    - `app/build/visual_qa/lists.png`
    - `app/build/visual_qa/lists_archived.png`
    - `app/build/visual_qa/task_detail.png`
    - `app/build/visual_qa/task_edit_dialog.png`
    - `app/build/visual_qa/design_lab_task_list.png`
    - `app/build/visual_qa/design_lab_list_overview.png`
    - `app/build/visual_qa/design_lab_focus_timer.png`
    - `app/build/visual_qa/design_lab_task_detail.png`
    - `app/build/visual_qa/design_lab_task_create_sheet.png`
    - `app/build/visual_qa/design_lab_search.png`
    - `app/build/visual_qa/design_lab_settings.png`
    - `app/build/visual_qa/design_lab_timer_setup.png`
    - `app/build/visual_qa/design_lab_typo_a_newsreader_today.png`
    - `app/build/visual_qa/design_lab_typo_a_newsreader_focus.png`
    - `app/build/visual_qa/design_lab_typo_b_lora_today.png`
    - `app/build/visual_qa/design_lab_typo_b_lora_focus.png`
    - `app/build/visual_qa/design_lab_typo_c_sans_only_today.png`
    - `app/build/visual_qa/design_lab_typo_c_sans_only_focus.png`
    - `app/build/visual_qa/design_lab_typo_d_ja_mincho_today.png`
    - `app/build/visual_qa/design_lab_typo_d_ja_mincho_focus.png`
  - 実行: `find app/build/visual_qa -maxdepth 1 -type f -name 'trash.png' -print`
  - 結果: 出力なし
  - `app/build/visual_qa_before/` の退避PNG数: 26
- 品質ゲート:
  - `cargo fmt --all -- --check`: exit 0
  - `cargo clippy --workspace -- -D warnings`: exit 0
  - `cargo test --workspace`: exit 0
  - `cd app && flutter analyze`: exit 0、`No issues found!`
  - `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
  - `cd app && flutter test`: exit 0、47 passed、1 skipped
  - `sh app/tool/check_hardcoded_strings.sh`: exit 0
  - `sh app/tool/visual_qa.sh`: exit 0、27 passed
  - `git diff --check`: exit 0
- 変更ファイル一覧:
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/lib/src/core/bridge_service.dart`
  - `app/lib/src/core/providers.dart`
  - `app/lib/src/generated/l10n/app_localizations.dart`
  - `app/lib/src/generated/l10n/app_localizations_en.dart`
  - `app/lib/src/generated/l10n/app_localizations_ja.dart`
  - `app/lib/src/router.dart`
  - `app/lib/src/rust/api.dart`
  - `app/lib/src/rust/frb_generated.dart`
  - `app/lib/src/screens/lists_screen.dart`
  - `app/lib/src/screens/task_detail_screen.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/screens/trash_screen.dart`（削除）
  - `app/lib/src/ui/dialogs.dart`
  - `app/rust/src/api.rs`
  - `app/rust/src/frb_generated.rs`
  - `app/test/core_usecases_test.dart`
  - `app/test/support/fake_bridge_service.dart`
  - `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - `app/test/widget_test.dart`
  - `core/domain/src/lib.rs`
  - `core/domain/src/usecases.rs`
  - `core/storage/src/lib.rs`
  - `docs/design/ui-spec.md`
  - `docs/tasks/README.md`
  - `docs/tasks/task-38-trash-removal.md`
- 未解決事項:
  - `tasks.deleted_at` 列のDROPは未実装。将来のv3マイグレーション対象。
  - 既存DB全体に残る `task_undo_entries.operation_type = 'delete'` の一括掃除は未実装。今回の実装では最新Undo表示対象外にし、物理削除対象taskのUndo entryだけ削除した。
  - 同期導入時のtombstone設計は未実装。docs/03の記載どおり同期導入時に再設計する。
  - 既定インボックスの永続識別列は未実装。今回も `sort_order` 最小の通常リストを基準にした。
