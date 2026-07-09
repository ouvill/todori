# task-39: wont_do / 再オープンのUIステータス遷移

> ステータス: 完了（wont_do / 再オープンUI）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

`docs/02_機能仕様書.md` F-06 は、タスクの終端状態として `done` と `wont_do` を定義している。`wont_do` は GitHub Issue の "Close as not planned" に相当し、完了とは区別して「やらないことにする」と判断したタスクを削除せず保存するための状態である。`done` と `wont_do` はどちらも再オープンにより `todo` へ戻せる。

domain/Rust層には `TaskStatus::WontDo`、`transition_task`、`set_task_status` がすでに存在する。現状の残りは主にFlutter UIへの配線であり、M3-04完了条件の残りとして、ユーザーが詳細画面から `wont_do` と再オープンを実行でき、一覧上でも `done` と `wont_do` を色だけに頼らず区別できるようにする。

事前調査で確認済みの遷移ルールは以下である。

- 許可: `todo` / `in_progress` -> `done` / `wont_do`
- 許可: `done` / `wont_do` -> `todo`（再オープン）
- 禁止: `done` <-> `wont_do`
- 禁止: `done` / `wont_do` -> `in_progress`
- 禁止遷移は、APIで弾くだけでなく、UI上で選べないこと。

`app/rust/src/api.rs` の `set_task_status` は、Undo履歴作成条件が現状 `status == TaskStatus::Done` に限定されている。`wont_do` も「閉じる」操作としてUndo対象にする必要があるため、この条件を `TaskStatus::Done` / `TaskStatus::WontDo` の両方へ広げる。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/02_機能仕様書.md` F-06（参照のみ、変更禁止）
- `docs/design/ui-spec.md`（裁定済み事項、画面規範、判断規則）
- `docs/tasks/task-38-trash-removal.md` の完了報告
- `core/domain/src/entities.rs`（`TaskStatus::can_transition_to`）
- `core/domain/src/usecases.rs`（`transition_task`）
- `app/rust/src/api.rs`（`set_task_status`、Undo履歴作成条件）
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/core_usecases_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- タスク詳細画面から、現在ステータスに応じた有効なステータス操作だけを実行できる。
- `todo` / `in_progress` のタスクを `wont_do` にできる。
- `done` / `wont_do` のタスクを `todo` へ再オープンできる。
- `done` と `wont_do` の相互遷移、および `done` / `wont_do` から `in_progress` への遷移は、UI上に表示しない。
- 一覧の `wont_do` 行は muted + 取り消し線に加えて、色だけに依存しない小ラベル等で `done` と区別できる。
- `wont_do` への遷移がUndo対象になり、Undoで元ステータスへ戻る。
- 未完了サブタスクを持つ親を `wont_do` にする際、既存の親完了確認ダイアログと整合した確認を出す。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/rust/src/api.rs`
- 必要に応じて `app/rust/src/frb_generated.rs`、`app/lib/src/rust/` 配下（Rust APIシグネチャを変えた場合のみ。生成物は手編集禁止）
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（`flutter gen-l10n` による生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/core_usecases_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-39-wont-do-reopen.md`（完了報告の追記のみ）

### やること

1. **Rust bridge / Undo**:
   - `app/rust/src/api.rs` の `set_task_status` で、Undo履歴を作る条件を `TaskStatus::Done` だけでなく `TaskStatus::WontDo` にも広げる。
   - 既存の `TaskUndoOperation::Complete` を使う場合は、完了報告に「done/wont_doの閉じる操作を同じUndo operationで扱った」と明記する。新しいoperation typeを追加する場合は、storage/API/Dart/fake/testまで一貫させ、既存Undoとの互換性を確認する。
   - `wont_do` 遷移後に `get_latest_task_undo` でUndo履歴が取得でき、`undo_task_operation` で元ステータスへ戻ることをテストする。
2. **Dart provider / fake**:
   - `tasksProvider(...).setStatus` は `done` / `wont_do` のどちらでも `latestTaskUndoProvider` をinvalidateする。
   - `FakeBridgeService.setTaskStatus` はdomainの遷移ルールと整合させ、禁止遷移を成功させない。少なくともwidget testで禁止遷移が表示されないことを確認できる状態にする。
   - fake側でも `wont_do` 遷移時にUndo履歴を記録する。
3. **タスク詳細画面のステータス操作**:
   - `task_detail_screen.dart` のoverflow menuにステータス操作を追加する。
   - `todo` / `in_progress` では `done` と `wont_do` への操作を表示する。
   - `done` / `wont_do` では `todo` へ戻す再オープン操作だけを表示する。
   - `done` <-> `wont_do` と `done` / `wont_do` -> `in_progress` は表示しない。
   - task-38で追加された削除操作と同居するため、ステータス操作を上、削除操作を下に置き、必要なら区切りを入れる。削除だけが破壊的操作であり、`wont_do` にはcoralを使わない。
4. **未完了サブタスク確認**:
   - 未完了サブタスクを持つ親を `wont_do` にする場合、既存の親完了確認ダイアログと同じ文法・重さの確認を出す。
   - `done` 用の既存文言を無理に流用して意味が崩れる場合は、`wont_do` 用のen/ja l10nキーを追加する。
5. **一覧表示**:
   - `AppTaskRow` または呼び出し側を拡張し、`wont_do` 行を `done` と同じく muted + 取り消し線にする。
   - それに加え、`wont_do` は小ラベル等のテキスト/形状で `done` と区別する。色だけに依存しないこと。
   - `docs/design/ui-spec.md` のチップ最大2個、既存トークン、行密度を守る。ラベル追加でメタデータが3個になる場合は、表示優先順位を調整して最大2個を維持する。
6. **l10n**:
   - `wont_do` 操作、再オープン、確認ダイアログ、一覧ラベル、Undo/SnackBarに必要な文言を `app_en.arb` / `app_ja.arb` に追加する。
   - ARB変更後は `flutter gen-l10n` を実行する。
7. **test / visual QA**:
   - widget testを追加・更新し、`wont_do` 遷移、再オープン、禁止遷移非表示、一覧表示、Undoを確認する。
   - `core_usecases_test` またはRust側テストで、`wont_do` 遷移がUndo対象になることを確認する。
   - visual QA seedに `wont_do` 行を含め、`sh app/tool/visual_qa.sh` でスクリーンショットを生成して目視確認する。

### やらないこと

- 新しいステータスの追加。
- domainの遷移ルール変更。ただし実装と仕様の矛盾を見つけた場合は、仕様書を変更せず完了報告の未解決事項へ記録する。
- 一覧からのスワイプ操作、行上の即時 `wont_do` 操作。
- ログブック/振り返りUI。
- 削除モデル、ゴミ箱廃止、恒久削除確認UIの再設計。
- タグ、検索、通知、同期、サーバー、MCP、CLIの実装。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` / `docs/design/ui-spec.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章の事前ファイルを読み、F-06、ui-spec、task-38後の削除メニュー、現行の `setStatus` / Undo経路を把握する。
3. `app/rust/src/api.rs` の `set_task_status` で `TaskStatus::WontDo` もUndo履歴作成対象にする。
4. `app/test/core_usecases_test.dart` またはRust/APIテストで、`wont_do` 遷移後のUndo取得・適用を確認する。
5. Dart providerと `FakeBridgeService` を更新し、`wont_do` のUndo invalidationとfake Undoを実装する。
6. `task_detail_screen.dart` に現在ステータス別の有効なステータス操作を追加し、削除操作との順序を整える。
7. 未完了サブタスクを持つ親の `wont_do` 確認ダイアログを追加する。
8. `task_components.dart` または呼び出し側を更新し、一覧の `wont_do` 行に色以外の小ラベル等を追加する。
9. en/ja ARBを更新し、`flutter gen-l10n` を実行する。
10. widget testとvisual QAを追加・更新する。
11. 共通受け入れ基準の品質ゲートを実行する。
12. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 詳細画面で `todo` / `in_progress` から `wont_do` を実行でき、ステータスが永続化されることがwidget testまたはbridge testで確認できる。
- [ ] 詳細画面で `done` / `wont_do` から `todo` へ再オープンできることがwidget testで確認できる。
- [ ] `done` <-> `wont_do`、および `done` / `wont_do` -> `in_progress` の禁止遷移が詳細画面の操作として表示されないことがwidget testで確認できる。
- [ ] 未完了サブタスクを持つ親を `wont_do` にすると、既存の親完了確認と整合した確認ダイアログが表示されることがwidget testで確認できる。
- [ ] 一覧の `wont_do` 行が muted + 取り消し線に加えて、色だけに依存しない小ラベル等で `done` と区別できることがwidget testとvisual QAスクリーンショットで確認できる。
- [ ] `wont_do` 遷移がUndo履歴を作成し、Undoで元ステータスへ戻ることがテストで確認できる。
- [ ] `wont_do` は破壊的操作として扱われず、coralが削除確認以外の通常操作に使われていない。
- [ ] en/jaのl10nキーが追加され、直書き文字列チェックに通っている。
- [ ] visual QAで `wont_do` 行を含むスクリーンショットを生成し、完了報告にパス付きで記録している。
- [ ] Rust APIシグネチャを変更した場合は、`flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` 実行後の生成物差分がFRB生成物のみで、手編集がない。

## 7. 制約・注意事項

- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更禁止。F-06は参照のみとする。
- `docs/design/ui-spec.md` は変更しない。新しい色・角丸・面色・影を発明しない。
- `wont_do` は削除ではない。タスク、サブタスク、完了履歴、Undo履歴を削除しない。
- `wont_do` は破壊的操作ではないため、coralを使わない。coralはtask-38後の削除確認など破壊的操作に限定する。
- 禁止遷移はdomain/APIで弾けるとしても、UIに表示しない。
- `done` と `wont_do` はどちらも閉じた状態だが、意味は異なる。一覧・詳細・l10nで「完了」と「やらないことにする」を混同しない。
- `TaskUndoOperation::Complete` を `wont_do` にも使う場合、UI文言が「完了しました」だけにならないようにする。必要なら閉じる操作向けの文言へ調整する。
- FRBは `2.12.0` 固定である。Rust APIシグネチャを変えた場合は再生成し、生成物を手編集しない。
- 新規依存は追加しない。
- 秘密情報、Device Key、SQLCipher鍵、導出鍵をログ・Debug出力に含めない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- F-06から読み取ったステータス遷移ルールと、UI上で非表示にした禁止遷移
- `app/rust/src/api.rs` のUndo履歴作成条件の変更内容
- `TaskUndoOperation` の扱い（既存 `Complete` を使ったか、新operationを追加したか）
- Dart provider / FakeBridgeService / TaskDetail / Task row表示の変更内容
- 追加・更新したl10nキー
- 追加・更新したwidget test、bridge/Rust/API testの対象と結果
- `wont_do` 行を含むvisual QAスクリーンショットの保存パスと目視確認結果
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

- 作業日: 2026-07-07
- 読んだファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/BACKLOG.md`
  - `docs/02_機能仕様書.md` F-06
  - `docs/design/ui-spec.md`
  - `docs/tasks/task-38-trash-removal.md` 完了報告
  - `core/domain/src/entities.rs`
  - `core/domain/src/usecases.rs`
  - `app/rust/src/api.rs`
  - `app/lib/src/core/bridge_service.dart`
  - `app/lib/src/core/providers.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/screens/task_detail_screen.dart`
  - `app/lib/src/ui/task_components.dart`
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/test/support/fake_bridge_service.dart`
  - `app/test/widget_test.dart`
  - `app/test/core_usecases_test.dart`
  - `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - `app/tool/visual_qa.sh`
- F-06から読み取ったステータス遷移ルール:
  - 許可: `todo` / `in_progress` -> `done` / `wont_do`
  - 許可: `done` / `wont_do` -> `todo`
  - 非表示にした禁止遷移: `done` <-> `wont_do`
  - 非表示にした禁止遷移: `done` / `wont_do` -> `in_progress`
- `app/rust/src/api.rs` のUndo履歴作成条件:
  - `set_task_status` で `status == TaskStatus::Done` の場合だけ `update_with_undo(..., TaskUndoOperation::Complete, ...)` を使っていた条件を、`TaskStatus::Done` または `TaskStatus::WontDo` の場合へ変更した。
- `TaskUndoOperation` の扱い:
  - 新operationは追加していない。
  - `done` / `wont_do` の閉じる操作を既存 `TaskUndoOperation::Complete` で扱った。
- Dart provider / FakeBridgeService / TaskDetail / Task row表示の変更内容:
  - `TasksNotifier.setStatus` に任意の `closedReason` 引数を追加し、`done` / `wont_do` で `latestTaskUndoProvider` をinvalidateするようにした。
  - `FakeBridgeService.setTaskStatus` にdomainと同じ遷移可否判定を追加し、`wont_do` 遷移時もUndo履歴を `complete` operationとして記録するようにした。
  - `FakeBridgeService` の `TaskDto` copy helperに `completedAt` / `closedReason` をnullへ戻すフラグを追加した。
  - Task detailのoverflow menuに、`todo` / `in_progress` 向けの `Mark done` / `Mark won't do`、`done` / `wont_do` 向けの `Reopen` を追加した。
  - Task detailのoverflow menuではステータス操作を上、区切りを挟んで削除操作を下に置いた。
  - 未完了サブタスクを持つ親を `wont_do` にする場合、確認ダイアログを表示するようにした。
  - `done` / `wont_do` を閉じたタスクとして一覧の折りたたみセクションへ入れ、セクション表示を `Closed` / `closed` に変更した。
  - `wont_do` 行は閉じた行の表示（muted + 取り消し線）に加え、`Won't do` / `対応しない` のpillを表示するようにした。
  - `isTaskOverdue` は `done` / `wont_do` を期限超過表示対象外にした。
- 追加・更新したl10nキー:
  - `wontDoTaskDialogTitle`
  - `wontDoTaskDialogMessage`
  - `markTaskDoneMenuItem`
  - `markTaskWontDoMenuItem`
  - `reopenTaskMenuItem`
  - `undoCloseMessage`
  - `completedTasksTitle`
  - `completedTasksCount`
  - `showCompletedTasksTooltip`
  - `hideCompletedTasksTooltip`
- 追加・更新したtest:
  - `app/test/widget_test.dart`
    - `detail menu marks wont_do, reopens it, and hides invalid transitions`
    - `detail menu hides done to wont_do transition`
    - `wont_do row is closed, struck through, and labeled`
    - `incomplete descendants require confirmation before parent wont_do`
    - 既存の完了Undo/閉じたセクション文言期待値を `Task closed.` / `Closed` / `{count} closed` へ更新
  - `app/test/core_usecases_test.dart`
    - `complete and edit undo roundtrip through Rust bridge` に `wont_do` 遷移後の `getLatestTaskUndo` と `undoTaskOperation` の確認を追加
  - `app/test/visual_qa/visual_qa_screenshots_test.dart`
    - `wont_do_row` スクリーンショットを追加
    - realistic seedに `wont_do` タスクを追加
- 個別実行したtest結果:
  - `cd app && flutter test test/widget_test.dart`: 34 tests passed
  - `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
  - `cd app && flutter test test/core_usecases_test.dart`: 14 tests passed
- visual QAスクリーンショット:
  - 保存パス: `app/build/visual_qa/wont_do_row.png`
  - 目視確認結果: `Closed` セクション内に `Replace the planning spreadsheet` の取り消し線表示、`Won't do` pill、`Send weekly notes` の取り消し線表示がある。
  - 退避済みbefore PNG: `app/build/visual_qa_before/`
- 品質ゲートの実行結果:
  - `cargo fmt --all -- --check`: exit 0
  - `cargo clippy --workspace -- -D warnings`: exit 0
  - `cargo test --workspace`: exit 0（Rust tests: crypto 17、domain 39、storage 22、sync 4）
  - `cd app && flutter analyze`: exit 0
  - `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
  - `cd app && flutter test`: exit 0（51 passed、visual QA harness 1 skipped）
  - `sh app/tool/check_hardcoded_strings.sh`: exit 0
  - `sh app/tool/visual_qa.sh`: exit 0（28 tests passed）
  - `git diff --check`: exit 0
- FRB再生成:
  - Rust APIシグネチャは変更していない。
  - `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` は実行していない。
- 変更ファイル一覧:
  - `app/rust/src/api.rs`
  - `app/lib/src/core/providers.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/screens/task_detail_screen.dart`
  - `app/lib/src/ui/task_components.dart`
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/lib/src/generated/l10n/app_localizations.dart`
  - `app/lib/src/generated/l10n/app_localizations_en.dart`
  - `app/lib/src/generated/l10n/app_localizations_ja.dart`
  - `app/test/support/fake_bridge_service.dart`
  - `app/test/widget_test.dart`
  - `app/test/core_usecases_test.dart`
  - `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - `docs/tasks/task-39-wont-do-reopen.md`
- 未解決事項:
  - `app/build/visual_qa/wont_do_row.png` の右上にFlutterの赤いoverflow indicatorが写っている。同じ位置のindicatorは作業前に退避した `app/build/visual_qa_before/home_tasks.png` にも写っている。
