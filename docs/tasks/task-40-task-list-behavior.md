# task-40: タスク一覧の再オープンとClosedサブタスク同伴

> ステータス: 完了（2026-07-07親レビュー合格）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

2026-07-07のドッグフーディングで、タスク一覧のClosed挙動について2点の実機フィードバックが出た。

1. 完了タスクのチェックをタップしたら、チェックが外れて `todo` へ再オープンしてほしい。
2. サブタスクが完了したとき、Closedセクションへ個別に移動せず、親タスクの下にぶら下がったままにしてほしい。

task-39で `done` / `wont_do` から `todo` への再オープンは詳細画面に配線済みである。一方、現行の一覧ではClosedセクション内の行の先頭コントロールは操作不可で、Closedセクション抽出もタスク単体の状態で分かれるため、完了サブタスクが親から離れて見える。

本タスクでは `docs/design/ui-spec.md` セクション3の新規則に従い、一覧上のClosedルートタスクは先頭コントロールから即時再オープンできるようにし、Closedセクションへ移す対象はルートタスクのみに限定する。閉じたサブタスクは親の下に残し、muted + 取り消し線で状態を示す。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/design/ui-spec.md` セクション3
- `docs/tasks/task-39-wont-do-reopen.md` の完了報告
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/visual_qa/design_lab_mocks.dart`（Lab task_listの構成確認）
- `app/tool/visual_qa.sh`

## 3. ゴール

- 一覧のClosed（`done` / `wont_do`）ルートタスク行の先頭コントロールをタップすると、確認ダイアログなしで `set_task_status(todo)` が実行される。
- 再オープン操作は既存の「完了時Undoスナックバー」と独立させ、再オープン後にUndoスナックバーを出さない。
- Closedセクションへ移動するのは閉じたルートタスクだけにする。
- 閉じたサブタスクは、親タスクが開いている限り親の下に表示し続ける。
- 親タスク自身がClosedになった場合は、その親配下のツリー全体をClosedセクションへ移す。
- `done` と `wont_do` の既存表示差分（wont_doラベル等）とアクセシビリティを維持する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARBを変更した場合の生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-40-task-list-behavior.md`（完了報告の追記のみ）

### やること

1. **一覧チェック解除の配線**:
   - `TasksScreen` の一覧行で、Closedルートタスクの先頭コントロールタップ時に `tasksProvider(listId).notifier.setStatus(task.id, 'todo')` を呼ぶ。
   - `done` / `wont_do` のどちらも対象にする。
   - 再オープンに確認ダイアログとUndoスナックバーは出さない。
   - `AppTaskRow` / 先頭コントロールのtooltip・semanticsを、Closed行では「再オープン」相当の意味に更新する。UI文字列が必要ならen/ja ARBへ追加する。
2. **Closedセクション抽出の見直し**:
   - タスクツリー構築/フラット化ロジックを、ルートタスクの状態で active / Closed を分ける構造へ変更する。
   - 開いているルートタスク配下のサブタスクは、状態に関わらず同じツリーへ含める。
   - 閉じたサブタスクは `isDone: true` 相当のmuted + 取り消し線表示を維持する。
   - 親ルートがClosedなら、その子孫は状態に関わらず親ごとClosedセクションへ表示する。
3. **並び替えとの整合**:
   - 手動並び替えUIは、従来どおり開いているタスクの同一階層でのみ出す。
   - Closedサブタスクが親の下へ残ることで、同階層の移動対象や上下移動判定が破綻しないことを確認する。
4. **widget test**:
   - 完了行の先頭コントロールタップで `todo` へ再オープンするケースを追加する。
   - `wont_do` 行の先頭コントロールタップで `todo` へ再オープンするケースを追加する。
   - 完了サブタスクがClosedセクションへ移動せず、親の下に残るケースを追加する。
   - 親完了時にツリーごとClosedセクションへ移動するケースを追加する。
5. **visual QA**:
   - `home_tasks` 系スクリーンショットで、完了サブタスクが親の下に残る状態を確認できるseedへ更新する。
   - `sh app/tool/visual_qa.sh` を実行し、完了報告に対象PNGのパスと確認内容を記録する。

### やらないこと

- リスト一覧の「…」メニュー/chevron撤去やリスト操作移設（task-41）。
- タスク詳細画面のインライン編集（task-42予定）。
- Design Lab準拠の全面ビジュアル刷新、遷移動線整理、Lucide統一、dot整列修正（task-43予定）。
- Rust/domain変更。既存の `set_task_status` で足りる想定。足りない場合は実装を広げず、完了報告の未解決事項へ記録する。
- 新しいステータス、削除モデル、ログブック、検索、通知、同期の変更。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章の事前ファイルを読み、現行のClosed抽出、`isTaskClosed`、`buildTaskTree` / `flattenTaskTree`、`AppTaskRow` の先頭コントロールを把握する。
3. `tasks_screen.dart` のactive/Closed分割を、タスク単体ではなく「ルートタスク単位」に変更する。
4. 必要なら `task_tree.dart` に「ルート状態でツリーを分ける」ための小さなhelperを追加する。既存helperで十分なら無理に増やさない。
5. Closedルート行の先頭コントロールに再オープン操作を渡し、`done` / `wont_do` のどちらも `todo` に戻す。
6. tooltip/semanticsとl10nを更新する。ARB変更時は `flutter gen-l10n` を実行する。
7. fakeとwidget testを更新し、4つの必須ケースを確認する。
8. visual QA seedとスクリーンショットを更新し、完了サブタスクが親の下に残ることをPNGで確認する。
9. 共通受け入れ基準の品質ゲートを実行する。
10. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 一覧の `done` ルートタスク行の先頭コントロールをタップすると、確認なしで `todo` へ再オープンすることがwidget testで確認できる。
- [ ] 一覧の `wont_do` ルートタスク行の先頭コントロールをタップすると、確認なしで `todo` へ再オープンすることがwidget testで確認できる。
- [ ] 一覧の再オープン操作では、完了時Undoスナックバーが表示されないことがwidget testで確認できる。
- [ ] 完了サブタスクはClosedセクションへ個別移動せず、親の下にmuted + 取り消し線で残ることがwidget testで確認できる。
- [ ] `wont_do` サブタスクも親の下に残り、`done` と区別できる既存ラベル/表現が維持されていることがwidget testで確認できる。
- [ ] 親タスク自身がClosedになった場合、子孫を含むツリー全体がClosedセクションへ移動することがwidget testで確認できる。
- [ ] Closedセクションの件数表示がルートタスク基準になり、完了サブタスクを個別件数として数えないことがwidget testで確認できる。
- [ ] 先頭コントロールのtooltip/semanticsが、未完了行では完了操作、Closed行では再オープン操作として読める。
- [ ] `home_tasks` 系visual QAスクリーンショットで、完了サブタスクが親の下に残る状態を確認でき、完了報告にPNGパスが記録されている。
- [ ] Rust/domain/APIシグネチャ変更が発生していない。必要になった場合は実装せず、未解決事項へ記録されている。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` セクション3の新規則を正とする。
- サブタスクを親から離す表示は、ユーザーが階層関係を見失うため避ける。
- `done` / `wont_do` はどちらもClosedだが意味が異なる。`wont_do` の色だけに依存しない区別はtask-39の成果を維持する。
- 再オープンは破壊的操作ではない。確認ダイアログ、coral、削除系文言を使わない。
- 既存の完了時Undoは維持するが、一覧Closed行の再オープンには新しいUndo導線を足さない。
- UI文字列は直書きせず、必要な文言はen/ja ARBへ追加する。
- visual QAは `TASKVEIL_VISUAL_QA=1` ゲート下の既存ハーネスを使う。スクリーンショットを見ずに完了扱いにしない。
- 新規依存は追加しない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 一覧再オープンの実装箇所と、`done` / `wont_do` の扱い
- 再オープン時に確認ダイアログ/Undoスナックバーを出していないことの確認結果
- Closedセクション抽出をルートタスク基準へ変更した内容
- 閉じたサブタスク表示（muted + 取り消し線、wont_do区別）の確認結果
- 追加・更新したl10nキー
- 追加・更新したwidget testの対象と結果
- visual QAスクリーンショットの保存パスと目視確認結果
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

- 作業日: 2026-07-07
- 読んだファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/BACKLOG.md`
  - `docs/tasks/DESIGN_PLAYBOOK.md`
  - `docs/design/ui-spec.md` セクション3
  - `docs/tasks/task-39-wont-do-reopen.md` 完了報告
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/ui/task_components.dart`
  - `app/lib/src/core/task_tree.dart`
  - `app/lib/src/core/providers.dart`
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/test/support/fake_bridge_service.dart`
  - `app/test/widget_test.dart`
  - `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - `app/test/visual_qa/design_lab_mocks.dart`
  - `app/tool/visual_qa.sh`
- 作業前退避:
  - `rsync -a --include='*/' --include='*.png' --exclude='*' app/build/visual_qa/ app/build/visual_qa_before/`: exit 0
  - 退避先: `app/build/visual_qa_before/`
- 一覧再オープンの実装箇所:
  - `app/lib/src/screens/tasks_screen.dart` で `TasksScreen._reopenTask` を追加し、一覧行の先頭コントロールから `tasksProvider(listId).notifier.setStatus(task.id, 'todo')` を呼ぶようにした。
  - `done` / `wont_do` はどちらも `isTaskClosed(task)` 経由で再オープン対象にした。
  - 再オープン処理では `showAppConfirmDialog` と `_showLatestUndoSnackBar` を呼んでいない。
- Closedセクション抽出:
  - `buildTaskTree(widget.tasks, sortMode: widget.sortMode)` のルートノードを、ルートタスクの `done` / `wont_do` 状態で active / Closed に分けるようにした。
  - 開いているルートタスク配下のサブタスクは、状態に関わらず active 側のツリーへ残すようにした。
  - 親ルートがClosedの場合は、子孫を含むツリーをClosedセクションへ表示するようにした。
  - Closedセクション件数は `completedRoots.length` を使うようにした。
  - Homeのpending数は activeルート配下に表示される未完了タスクを数えるようにした。
- 閉じたサブタスク表示:
  - `AppTaskRow` の `isDone` は `done` / `wont_do` に対して引き続きtrueになり、muted + 取り消し線表示を使う。
  - `wont_do` は既存の `Won't do` / `対応しない` metadata pill で `done` と区別する。
- 並び替え:
  - 手動並び替えコントロールは `!isTaskClosed(task)` の行だけに表示するようにした。
  - sibling判定は activeツリー内の開いているタスクだけを対象にした。
- 追加・更新したl10nキー:
  - `completeTaskTooltip`
  - `reopenTaskTooltip`
  - `flutter gen-l10n`: exit 0
- 追加・更新したwidget test:
  - `checking a task marks it done through the bridge service`: Closed行の先頭コントロールが再オープン操作として有効である確認を追加。
  - `done root row leading control reopens without undo`: `done` ルート行の先頭コントロールで `todo` へ戻り、確認ダイアログ/Undoスナックバーが表示されないことを確認。
  - `wont_do root row leading control reopens without undo`: `wont_do` ルート行の先頭コントロールで `todo` へ戻り、確認ダイアログ/Undoスナックバーが表示されないことを確認。
  - `wont_do row is closed, struck through, and labeled`: Closed行の再オープンtooltip確認を追加。
  - `task list keeps closed subtasks under their open parent`: `done` / `wont_do` サブタスクが親配下に残り、取り消し線と `Won't do` pill が表示されることを確認。
  - `closed parent moves its whole tree to root-based closed count`: Closed親のツリー全体がClosedセクションへ移り、件数がルート基準になることを確認。
  - `flutter test test/widget_test.dart`: exit 0（37 passed）
- visual QA:
  - `app/test/visual_qa/visual_qa_screenshots_test.dart` の realistic seed で `Plan the product launch event` と完了済み `Draft the launch checklist` が `home_tasks` 系のファーストビューに入る順序へ変更した。
  - `sh app/tool/visual_qa.sh`: exit 0（28 passed）
  - `app/build/visual_qa/home_tasks.png`: `Draft the launch checklist` が `Plan the product launch event` の直下に取り消し線付きで表示されていることを目視確認した。
  - `app/build/visual_qa/home_tasks_ja.png`: 同じ親子関係と取り消し線表示を目視確認した。
  - `app/build/visual_qa/home_tasks_dark.png`: 同じ親子関係と取り消し線表示を目視確認した。
  - `app/build/visual_qa/wont_do_row.png`: Closedセクションに `2 closed`、`Replace the planning spreadsheet` の取り消し線、`Won't do` pill、`Send weekly notes` の取り消し線が表示されていることを目視確認した。
- 品質ゲートの実行結果:
  - `cargo fmt --all -- --check`: exit 0
  - `cargo clippy --workspace -- -D warnings`: exit 0
  - `cargo test --workspace`: exit 0
  - `cd app && flutter analyze`: exit 0
  - `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
  - `cd app && flutter test`: exit 0（54 passed、visual QA harness 1 skipped）
  - `sh app/tool/check_hardcoded_strings.sh`: exit 0
  - `sh app/tool/visual_qa.sh`: exit 0（28 passed）
  - `git diff --check`: exit 0
- 変更ファイル一覧:
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/lib/src/generated/l10n/app_localizations.dart`
  - `app/lib/src/generated/l10n/app_localizations_en.dart`
  - `app/lib/src/generated/l10n/app_localizations_ja.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/ui/task_components.dart`
  - `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - `app/test/widget_test.dart`
  - `docs/tasks/task-40-task-list-behavior.md`
- Rust/domain/APIシグネチャ:
  - Rust/domain/APIシグネチャは変更していない。
  - `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` は実行していない。
- 未解決事項:
  - `app/build/visual_qa/home_tasks.png` / `home_tasks_ja.png` / `home_tasks_dark.png` / `wont_do_row.png` の右上に赤いoverflow indicatorが写っている。同じ位置のindicatorは作業前に退避した `app/build/visual_qa_before/home_tasks.png` にも写っている。
