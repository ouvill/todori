# task-58: Home完了タスクの単独表示抑止と同伴表示

> ステータス: 完了（worker実装）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

2026-07-08のドッグフーディングで、完了済みなのに期日超過のサブサブタスクがHomeのOverdueに単独表示されたままになる問題が見つかった。プロダクトオーナー裁定は「期限つきでもタスクが完了したら親ツリーの下に移動する」である。

task-57でHomeは1タスク1表示へ改訂されたが、現行のHomeセクション構成ロジックは、期日でOverdue / Today / Tomorrow / Upcomingに該当するタスクを単独表示候補へ入れる際に、完了状態を十分に分離できていない。件数バッジは未完了だけを数えていても、完了タスクが日付セクションへ単独行として残ると、Homeの構造規範とユーザー期待に反する。

以後、Homeの日付セクションに単独表示されるのは未完了タスクのみとする。完了（`done` / `wont_do`）タスクは期日に関わらず日付セクションへ単独表示しない。Homeに表示される直近の祖先がいれば、その祖先の下にmuted + 取り消し線の既存表現で同伴する。表示中の祖先がいない完了ルートタスクはClosedセクションへ入り、表示中の祖先がいない完了サブタスクはHomeでは表示しない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（タスク一覧構造、Homeセクション、Closedセクション）
- `docs/tasks/task-57-home-dedupe.md`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/ui/task_components.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- Homeの日付セクション（Overdue / Today / Tomorrow / Upcoming）への単独表示を未完了タスクだけに限定する。
- 完了した期日ありサブタスク/孫タスクは、表示中の直近祖先の下へ同伴表示されるようにする。
- 表示中の祖先がいない完了サブタスクはHomeに表示しない。
- 表示中の祖先がいない完了ルートタスクはClosedセクションに表示する。
- セクション件数は未完了の該当タスクのみを数える既存方針を維持する。
- task-57の1タスク1表示、同伴サブツリー剪定、サブタスク単独行の親ラベル規則を壊さない。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`（Closed/Home行表現に追加調整が必要な場合のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-58-home-closed-nesting.md`（完了報告の追記のみ）

### やること

1. Homeセクション構成ロジックで、日付セクションの単独表示候補を未完了タスクだけに限定する。
   - `isHomeTarget` かつ期日ありでも、`done` / `wont_do` は `standaloneTaskIds` / `targetSectionByTaskId` の単独表示対象から外す。
   - 件数バッジは未完了該当タスクのみを数える既存方針を維持する。
2. 完了タスクの同伴表示規則を実装する。
   - 完了した子孫は、Homeに表示される直近祖先がいる場合、その祖先の同伴サブツリー内に残す。
   - 完了した子孫は、期日がOverdue / Today / Tomorrow / Upcomingに該当しても、日付セクションへ単独表示しない。
   - 同伴表示時は既存のmuted + 取り消し線表現、チェックトグル、詳細遷移を維持する。
3. 祖先非表示の完了タスクを整理する。
   - 完了ルートタスクはClosedセクションへ表示する。HomeにClosedセクションが不足している場合は、既存のCompleted/Closed表現に沿って追加する。
   - 表示中の祖先がいない完了サブタスクはHomeの日付セクションにもClosedセクションにも出さない。
4. task-57の1タスク1表示規則と両立させる。
   - 未完了で単独表示される子孫は、祖先の同伴サブツリーから引き続き剪定する。
   - 完了した子孫は、単独表示候補ではないため、表示中祖先の下に同伴される。
5. widget testを追加・更新する。
   - ユーザー報告シナリオ: Todayに未完了の親サブタスクが単独表示され、その配下の完了済み期日超過孫がOverdueに出ず、Todayの親サブタスク下にmuted + 取り消し線で表示されることを検証する。
   - 完了ルートタスクが日付セクションではなくClosedセクションへ入ることを検証する。
   - 表示中祖先がいない完了サブタスクがHomeに表示されないことを検証する。
6. visual QAを更新する。
   - `home_tasks` seedにユーザー報告シナリオを含める。
   - 目視で、完了済み期日超過孫がOverdueに単独表示されず、Todayの親サブタスク配下にmuted + 取り消し線で同伴表示されることを確認できるスクリーンショットを生成する。

### やらないこと

- 通常リスト画面のClosed/Completed構造変更。
- 詳細画面のSubtasks表示変更。
- Homeセクション定義（Overdue / Today / Tomorrow / Upcoming）の追加・削除。
- セクション件数に同伴子孫や完了タスクを含める変更。
- task-57の親ラベル、1タスク1表示、未完了単独表示子孫の剪定規則の巻き戻し。
- クイック追加シート、期日変更シート、スワイプaction、D&Dの変更。
- Rust API / storage query の変更（既存DTOで実現できないと判明した場合のみ、完了報告の未解決事項へ記録して止める）。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、現行の `_buildHomeSections`、`targetSectionByTaskId`、`standaloneTaskIds`、`buildHomeNode`、Closed/Completedセクション描画を把握する。
3. 日付セクションの単独表示対象集合を「期日あり、`isHomeTarget == true`、未完了」のみにする。
4. `countBySection` が同じ未完了対象だけを数えていることを確認し、完了タスクが件数へ入らない状態を維持する。
5. `buildHomeNode` の剪定条件を確認し、未完了の単独表示子孫は剪定しつつ、完了子孫は表示中祖先の同伴サブツリーへ残るようにする。
6. HomeにClosedセクションが必要な場合は、完了ルートタスクだけを対象に、既存の `_CompletedSectionHeader` / `AppTaskRow` 文法を再利用して追加する。
7. 表示中祖先がいない完了サブタスクが、日付セクションにもClosedセクションにも含まれないことをテストで固定する。
8. widget testとvisual QA seedを追加・更新する。
9. 品質ゲートを実行し、指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 日付セクション（Overdue / Today / Tomorrow / Upcoming）に単独表示されるタスクが未完了タスクだけであることがwidget testで確認されている。
- [ ] ユーザー報告シナリオとして、完了済み期日超過孫がOverdueに出ず、Todayの親サブタスク下にmuted + 取り消し線で表示されることがwidget testで確認されている。
- [ ] 完了ルートタスクが期日に関わらず日付セクションへ出ず、Closedセクションへ表示されることがwidget testで確認されている。
- [ ] 表示中祖先がいない完了サブタスクがHomeに表示されないことがwidget testで確認されている。
- [ ] セクション件数が未完了の該当タスクのみを数え、完了同伴子孫とClosedタスクを含まないことがwidget testで確認されている。
- [ ] task-57の1タスク1表示、未完了単独表示子孫の剪定、サブタスク単独行の親ラベルが維持されていることが既存または追加widget testで確認されている。
- [ ] visual QAの `home_tasks` にユーザー報告シナリオseedが含まれ、該当表示を確認できるスクリーンショットが保存されている。
- [ ] 完了報告に、単独表示候補の判定方法、完了タスクの同伴/Closed/非表示分岐、追加・更新したテスト名、visual QAパス、品質ゲート結果が記録されている。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` の2026-07-08人間裁定（Home完了タスクの単独表示抑止）を正とする。
- 完了状態は `done` と `wont_do` の両方を対象にする。片方だけを特別扱いしない。
- 日付セクションの単独表示対象と件数対象は同じ「未完了かつ期日該当」の集合に揃える。
- 完了子孫は、表示中祖先がいる場合だけHomeへ同伴表示する。祖先がHome上にいない完了サブタスクをClosedへ昇格しない。
- 完了ルートタスクだけがClosedセクションへ入る。サブタスク関係をHome上で失わないため、サブタスクをClosedの独立行にしない。
- 同伴表示は表示上の構成であり、タスクの親子関係やDB上のデータは変更しない。
- UI文字列を追加する場合はARB化する。`app/tool/check_hardcoded_strings.sh` に検出される直書きを追加しない。
- 既存の階層ガイド、チェックボックス幾何、Home横幅圧縮、48px級タップ領域を崩さない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- Home日付セクションの単独表示候補を未完了へ限定した実装箇所
- 完了タスクの分岐（表示中祖先あり=同伴、完了ルート=Closed、祖先非表示サブタスク=Home非表示）
- セクション件数が未完了該当タスクのみであることの確認内容
- task-57の1タスク1表示/剪定/親ラベル維持の確認内容
- 追加・更新したwidget test名と検証対象
- visual QAスクリーンショットの保存パス
- Rust API/FRB生成物の変更有無
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-08

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md`
- `docs/tasks/task-57-home-dedupe.md`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/ui/task_components.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

実装結果:

- `app/build/visual_qa/` のPNGを作業前に `app/build/visual_qa_before/` へコピーした。
- `app/lib/src/screens/tasks_screen.dart` の `_buildHomeSections` で、Home日付セクションの単独表示候補を `entry.isHomeTarget` かつ `!isTaskClosed(entry.task)` かつ `dueAt != null` のタスクへ限定した。
- `app/lib/src/screens/tasks_screen.dart` の `countBySection` は同じ未完了単独表示候補だけを加算する実装にした。
- `app/lib/src/screens/tasks_screen.dart` に `_buildHomeClosedRows` を追加し、`parentTaskId == null` かつ `isTaskClosed(task)` のHome entriesをHomeのClosed折りたたみ行へ表示した。
- 完了子孫は `standaloneTaskIds` に含まれないため、表示中祖先の `buildHomeNode` 配下に残る。
- 表示中祖先がいない完了サブタスクは日付セクションにもClosedセクションにも追加しない。
- `app/test/visual_qa/visual_qa_screenshots_test.dart` の `home_tasks` seedで、`Confirm final copy in the hero panel` を昨日期日かつ完了状態にした。
- Rust API、storage query、FRB生成物は変更していない。

セクション件数の確認:

- `home nests closed due descendants under visible ancestors only` で、Overdue件数が0、Today件数が1であることを確認した。
- `home routes closed roots to Closed instead of date sections` で、完了ルートのOverdue件数が0であることを確認した。
- `home hides closed subtasks without a visible ancestor` で、祖先非表示の完了サブタスクがHomeに表示されず、Overdue件数が0であることを確認した。

task-57規則の確認:

- 既存 `home shows target subtrees with dedupe and interaction rules` を更新せず成功させ、1タスク1表示、未完了単独表示子孫の剪定、サブタスク単独行の親ラベルを確認した。
- `home nests closed due descendants under visible ancestors only` で、完了済み孫が親サブタスク配下の階層ガイド付き同伴行として表示されることを確認した。

追加・更新したwidget test:

- 追加: `home nests closed due descendants under visible ancestors only`。完了済み期日超過孫がOverdueに出ず、Todayの親サブタスク配下に取り消し線付きで表示され、Today折りたたみで一緒に隠れることを検証した。
- 追加: `home routes closed roots to Closed instead of date sections`。完了ルートが日付セクションへ出ず、Closed折りたたみ内に表示されることを検証した。
- 追加: `home hides closed subtasks without a visible ancestor`。表示中祖先がいない完了サブタスクがHomeに表示されないことを検証した。
- 更新: `checking a task marks it done through the bridge service`。Homeで完了したルートタスクがClosed折りたたみへ移ることを検証した。
- 更新: `done root row leading control reopens without undo`。HomeのClosed折りたたみ内から再オープンできることを検証した。
- 更新: `wont_do root row leading control reopens without undo`。HomeのClosed折りたたみ内から再オープンできることを検証した。
- 更新: `detail menu hides done to wont_do transition`。HomeのClosed折りたたみ内の完了ルートから詳細へ遷移して検証した。
- 更新: `detail title checkbox reopens done and wont_do tasks`。HomeのClosed折りたたみ内の完了ルートから詳細へ遷移して検証した。

visual QA:

- 作業前退避先: `app/build/visual_qa_before/`
- スクリーンショット: `app/build/visual_qa/home_tasks.png`
- `app/build/visual_qa/home_tasks.png` を目視し、`Confirm final copy in the hero panel` がOverdueに単独表示されず、Todayの `Draft the launch checklist` の下にチェック済み、muted、取り消し線付きで表示されることを確認した。

品質ゲート:

- `cargo fmt --all -- --check`: exit 0
- `cargo clippy --workspace -- -D warnings`: exit 0
- `cargo test --workspace`: exit 0
- `cd app && flutter analyze`: exit 0
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
- `cd app && flutter test`: exit 0（88件成功、visual QA harness 1件skip）
- `sh app/tool/check_hardcoded_strings.sh`: exit 0
- `sh app/tool/visual_qa.sh`: exit 0（36件成功）
- `git diff --check`: exit 0

変更ファイル一覧:

- `app/lib/src/screens/tasks_screen.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-58-home-closed-nesting.md`

未解決事項: なし
