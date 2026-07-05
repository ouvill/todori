# task-32: task list interaction refinement ── left list transition / completed section / row quieting

> ステータス: 完了（2026-07-05）
> 作業日: 2026-07-05

## 1. 背景とコンテキスト

task-30〜31でタスク行の密度・Trash表現・visual QA基盤は整ったが、実際のタスク一覧体験には次の違和感が残っている。

- リスト画面が右側からpushされ、メニュー/リスト切替の「左から出る」期待と逆に感じる。
- 完了済みタスクが通常タスクと同じ流れに混ざり、現在やることの視線を散らす。
- サブタスクがあるタスクに `1/3` バッジが出ており、一覧上では情報量が多い。
- priority dotがタイトル上端に寄って見え、行の中央に落ち着いていない。

このタスクは機能追加ではなく、タスク一覧の読み順・遷移方向・情報量を調整するUI/UX改修である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/visual-direction.md`
- `docs/tasks/task-30-design-mood-alignment.md`
- `docs/tasks/task-31-trash-visual-refinement.md`
- `app/lib/src/router.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`
- `app/tool/check_hardcoded_strings.sh`

## 3. ゴール

- `/lists` 画面を左から入る遷移にする。
- 完了済みタスクを通常タスク一覧の下部に `Completed` セクションとして表示する。
- `Completed` セクションは初期状態で折りたたみ、タップで展開する。
- タスク一覧ではサブタスク進捗バッジを表示しない。
- priority dotをタスク行の垂直方向中央に揃える。
- 長文、日本語、狭幅、Dynamic Type、tooltip/semantics、Undo、並び替え、条件ソートを壊さない。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/router.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/` 配下（ARB変更時のみ生成差分）
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`（必要に応じて）
- `docs/tasks/task-32-task-list-interaction-refinement.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

**A. リスト画面の左方向遷移**

- `/lists` ルートを、画面が左から入るcustom transitionにする。
- `/lists/:listId/tasks` や task detail など通常の詳細遷移まで不用意に変えない。

**B. 完了済みタスクの下部折りたたみ**

- `status == 'done'` のタスクを通常のactive task一覧から分離する。
- 完了済みタスクがある場合だけ、下部に `Completed` セクションを表示する。
- `Completed` セクションは初期状態で折りたたみ、タップで展開/折りたたみできる。
- 展開時は完了済みタスクを下部に表示し、既存のタップでdetailへ遷移できることを維持する。
- 完了済みタスクでは完了チェックボックスを再操作不可にしてよい。Undoは既存snackbarで維持する。
- pending countは未完了タスク数を示し、完了済みタスクを含めない。

**C. サブタスク進捗バッジの非表示**

- タスク一覧（Home Tasks / List Tasks / サブタスク行）では `1/3` 等のサブタスク進捗バッジを表示しない。
- Task detailの主タスクヘッダーでは、既存のサブタスク進捗表示を残してよい。

**D. priority dotの垂直中央揃え**

- タスク行とTrash行のpriority dotを、タイトルブロックの垂直方向中央に揃える。
- 複数行タイトルでも、dotが上端に貼り付いて見えないようにする。
- priority noneは引き続きdotなしにする。

**E. 検証と記録**

- 作業前に `app/build/visual_qa/` を `app/build/visual_qa_before_task_32/` へ退避する。
- 作業後に `sh app/tool/visual_qa.sh` を実行し、before/afterを目視する。
- widget testを追加/更新し、Completed折りたたみ、サブタスクバッジ非表示、priority dot配置の回帰を確認する。

### やらないこと

- Rust API / FRB / DB schema / domain / storage / core配下 / cli / mcp-server / server は変更しない。
- task statusの意味、Undo履歴、削除/復元、並び替え永続仕様を変更しない。
- 完了済みタスク専用画面、検索、通知、Focus timer、設定画面、bottom navigationを追加しない。
- 新規pub依存や新規画像アセットを追加しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `todori-private/` と `.github/` は変更しない。

## 5. 実装手順例

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読む。
3. `app/build/visual_qa/` があれば `app/build/visual_qa_before_task_32/` へ退避する。
4. `router.dart` で `/lists` に左から入るtransitionを設定する。
5. `tasks_screen.dart` でactive/completedを分離し、Completed折りたたみセクションを追加する。
6. `task_components.dart` でサブタスク進捗バッジを一覧では出さない制御とpriority dot中央揃えを実装する。
7. ARBに必要なキーを追加し、`cd app && flutter gen-l10n` を実行する。
8. `widget_test.dart` を更新し、Completed折りたたみ、サブタスクバッジ非表示、既存並び替え/Undoの維持を確認する。
9. `sh app/tool/visual_qa.sh` を実行し、主要PNGを目視する。
10. 品質ゲートを実行し、完了報告を追記する。

## 6. 受け入れ基準

- [x] `/lists` 画面が左から入るtransitionになっている。
- [x] タスク一覧で完了済みタスクが通常タスクに混ざらず、下部の `Completed` セクションに移動する。
- [x] `Completed` セクションは初期状態で折りたたまれている。
- [x] `Completed` セクションをタップすると完了済みタスクが表示され、再タップで閉じる。
- [x] 完了済みタスクが存在しない場合、`Completed` セクションは表示されない。
- [x] タスク一覧にサブタスク進捗バッジ（例: `1/3`）が表示されない。
- [x] Task detailの主タスクヘッダーで必要なメタデータは破綻しない。
- [x] priority dotがタスク行/Trash行の垂直方向中央に見える。
- [x] `home_tasks.png` / `task_detail.png` / `trash.png` のbefore/afterを目視し、表示崩れがない。
- [x] 長いタイトル、日本語、狭幅、Dynamic Typeで破綻しない。
- [x] 追加・変更UI文字列がen/ja ARB化され、生成済みlocalizationsが更新されている。
- [x] `cd app && flutter analyze` が成功している。
- [x] `cd app && flutter test` が成功している。
- [x] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [x] `git diff --check` が成功している。
- [x] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [x] `todori-private/` と `.github/` が変更されていない。

## 7. 制約・注意事項

- UI文字列は必ずARB化する。
- visual QAは必ずbefore/afterで見る。実装者の自己申告だけで合格扱いにしない。
- Completed折りたたみ状態はUI状態であり、DB永続化しない。
- 完了済みタスクをactive一覧から外しても、Undoで未完了へ戻したときにactive一覧へ戻ることを確認する。
- public repoにprivate repoの課金、収益、法務、監査、公開前ロードマップ詳細を転記しない。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- `/lists` 左方向transitionの実装内容
- Completedセクションの実装内容
- サブタスク進捗バッジ非表示の実装内容
- priority dot中央揃えの実装内容
- 追加/変更したi18nキーと `flutter gen-l10n` の実行結果
- before/afterスクリーンショットの保存パスと目視比較結果
- 追加/更新したwidget testの対象と結果
- 品質ゲートの実行結果
- やらなかったことが守られていること
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` を変更していないこと
- `todori-private/` と `.github/` を変更していないこと
- 未解決事項（なければ「なし」）

## 9. 完了報告

### 作業日

2026-07-05

### 読んだファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/visual-direction.md`
- `docs/tasks/task-30-design-mood-alignment.md`
- `docs/tasks/task-31-trash-visual-refinement.md`
- `app/lib/src/router.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`
- `app/tool/check_hardcoded_strings.sh`

### 実装結果

- `/lists` ルートを `CustomTransitionPage` 化し、`SlideTransition` を `Offset(-1, 0)` から `Offset.zero` へ入る設定にした。詳細遷移（`/lists/:listId/tasks` / task detail）は変更していない。
- `tasks_screen.dart` で `status == 'done'` をactive一覧から分離し、下部に `Completed` セクションを追加した。初期状態は折りたたみ、`ValueKey('completed-section-toggle')` のヘッダーをタップすると展開/折りたたみできる。完了済みタスクはdetail遷移を維持しつつ、一覧上の完了チェックボックスは非表示にした。
- `taskMetadataItemsFor` に `includeSubtaskProgress` を追加し、Home/List TasksおよびTask detail内のサブタスク行では `1/3` などのサブタスク進捗バッジを非表示にした。Task detailの主タスクヘッダーでは既存の進捗メタデータを維持した。
- task row / trash row / task detail headerのpriority dotをタイトル行中央へ揃えた。
- 追加i18nキー: `completedTasksTitle`, `completedTasksCount`, `showCompletedTasksTooltip`, `hideCompletedTasksTooltip`。`cd app && flutter gen-l10n` を実行し、`app/lib/src/generated/l10n/` を更新した。

### Visual QA

- 作業前スクリーンショット退避: `app/build/visual_qa_before_task_32/`
- 作業後スクリーンショット: `app/build/visual_qa/`
- `sh app/tool/visual_qa.sh` は8スクリーンショット生成で成功した。
- `home_tasks.png`: 完了済みタスクがactive一覧から外れ、サブタスク進捗バッジが表示されないことを確認した。
- `task_detail.png`: 主タスクヘッダーの進捗メタデータは維持され、サブタスク行の進捗バッジは表示されないこと、priority dotがタイトル行中央へ寄ったことを確認した。
- `trash.png`: priority dotがタイトル行中央に見えることを確認した。

### テスト更新

- `widget_test.dart` に `/lists` がleading edge（左）から入ることを確認する `SlideTransition` テストを追加した。
- 完了チェック後、タスクがactive一覧から消えて `Completed` セクションに入り、展開時だけ表示され、Undoでactive一覧へ戻ることを確認する既存テストを更新した。
- サブタスク進捗バッジがタスク一覧に出ないことを確認する既存テストを更新した。
- 長文・狭幅・Dynamic Typeのdetail画面でpriority dotがタイトル中央付近に来ることを確認する幾何テストを追加した。

### 検証結果

- `cd app && dart format lib test`: 成功
- `cd app && flutter gen-l10n`: 成功
- `cd app && flutter analyze`: 成功（No issues found）
- `cd app && flutter test`: 成功（38 passed / visual QA harness 1 skipped）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `git diff --check`: 成功
- `cd core && cargo fmt --all -- --check`: 成功
- `cd core && cargo clippy --workspace -- -D warnings`: 成功
- `cd core && cargo test --workspace`: 成功（Rust 74 tests passed）
- `sh app/tool/visual_qa.sh`: 成功（8 screenshots）

### スコープ確認

- Rust API / FRB / DB schema / domain / storage / cli / mcp-server / server は変更していない。
- task statusの意味、Undo履歴、削除/復元、並び替え永続仕様は変更していない。
- 完了済みタスク専用画面、検索、通知、Focus timer、設定画面、bottom navigationは追加していない。
- 新規pub依存や新規画像アセットは追加していない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。
- `todori-private/` と `.github/` は変更していない。

### 独立レビュー

- subagent `Raman` が未コミット差分をレビューし、Task detail headerのpriority dotが上寄りである点をP2として指摘した。`task_detail_screen.dart` の該当Rowを中央揃えへ修正し、widget testとvisual QAで確認した。
- `/lists` 遷移方向の自動テスト不足も指摘されたため、`lists screen enters from the leading edge` を追加した。

### 未解決事項

なし。
