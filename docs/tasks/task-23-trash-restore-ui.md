# task-23: ゴミ箱画面・復元UI

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-05

## 1. 背景とコンテキスト

task-18でタスク詳細画面からの `title` / `note` / `priority` / `due_at` 編集が実装され、task-19でサブタスク表示・作成・進捗・親完了確認が追加された。task-20ではUI foundation、task-21では視覚方向性、task-22では `docs/design/visual-direction.md` とゴミ箱/復元UIのデザイン方針が整理された。

次に残っているのは、MVPのタスク操作として、論理削除済みタスクをユーザーが見つけて復元できる導線である。`docs/tasks/BACKLOG.md` では「ゴミ箱画面・復元UI」は M3-04相当として先頭に積まれている。一方、`docs/07_Phase1計画書.md` では M3-02「タスクCRUD UI」の完了条件に「画面からタスク作成/編集/削除/復元ができ、DBに反映されること」とあり、削除/復元はM3-02にも対応する。このタスクでは、その表記上の齟齬を「BACKLOG上はM3-04相当だが、計画書上はM3-02の削除/復元残りにも対応する作業」として扱う。

既に `get_trashed_tasks` / `restore_task` / `trash_task` は Rust API、flutter_rust_bridge生成物、Dart wrapper、`BridgeService` に公開済みである。`TaskDetailScreen` からの `trash_task` 呼び出しも存在するため、このタスクは原則としてFlutter側の画面、ルート、Riverpod provider/notifier、復元操作、状態表示、i18n、widget testに限定する。Rust API、FRB再生成、DB schema、domain usecaseの変更は原則不要である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` M3-02 / M3-04 / M3-05
- `docs/tasks/task-18-task-editing-ui.md`
- `docs/tasks/task-19-subtasks-ui.md`
- `docs/tasks/task-20-ui-foundation.md`
- `docs/tasks/task-21-visual-direction.md`
- `docs/tasks/task-22-design-direction-sketch.md`
- `docs/design/visual-direction.md` の `Trash And Restore` と関連するcomponent rules
- `app/lib/src/router.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/core_usecases_test.dart`
- `app/tool/check_hardcoded_strings.sh`

## 3. ゴール

論理削除済みタスクを確認し、復元できるゴミ箱画面をFlutter UIとして追加する。

- `get_trashed_tasks` を使う `trashed tasks provider/notifier` を追加する。
- ゴミ箱画面用のrouteとscreenを追加する。
- Tasks画面、または既存情報設計に照らして自然な場所からゴミ箱画面へ移動できる導線を追加する。
- ゴミ箱画面で削除済みタスクの一覧、削除metadata、明確なrestore actionを表示する。
- `restore_task` を呼び、復元後にゴミ箱一覧と該当リストのactive task一覧が更新されるようにする。
- empty / loading / error状態を既存UI foundationに合わせて表示する。
- 追加UI文字列をen/ja ARBへ追加し、直書き検出を通す。
- widget testで導線、一覧、復元、状態表示を検証する。

## 4. スコープ

### やること

1. **ゴミ箱画面routeの追加**:
   - `app/lib/src/router.dart` にゴミ箱画面へのrouteを追加する。
   - route名とpathは既存のgo_router構成に馴染むものにする。例: `/trash` または `/lists/:listId/tasks/trash`。
   - ゴミ箱は全削除済みタスクを返す既存APIに合わせ、最初は全体ゴミ箱として扱ってよい。list単位に見せる場合も、`get_trashed_tasks` の現在の挙動と矛盾しないこと。
   - 既存の `/lists`、`/lists/:listId/tasks`、`/lists/:listId/tasks/:taskId` の導線を壊さない。
2. **導線の追加**:
   - Tasks画面、Lists画面、または既存の情報設計上もっとも自然な場所にゴミ箱への導線を追加する。
   - 可能ならAppBar actionなどのコンパクトな導線を優先し、通常タスク操作の邪魔にならないようにする。
   - icon-only controlにする場合はtooltip/semanticsを必ず付ける。
3. **trashed tasks provider/notifierの追加**:
   - `app/lib/src/core/providers.dart` に `getTrashedTasks()` を読む `AsyncNotifier` または既存方針に合うproviderを追加する。
   - `restoreTask(taskId)` をnotifier actionとして実装し、bridge call後にゴミ箱一覧をrefreshする。
   - 復元後、該当タスクの元リストの `tasksProvider(listId)` も更新されるようにする。タスクの `listId` は復元前の `TaskDto` から取れるため、必要なlist providerだけをinvalidateする。
   - `trashTask` 実行後に、必要ならゴミ箱providerも古いままにならないようinvalidate方針を整理する。
4. **ゴミ箱画面の実装**:
   - `app/lib/src/screens/` 配下にゴミ箱画面を追加する。
   - 既存の `AppTaskRow`、`TaskMetadata`、`AppEmptyState`、`AppLoadingState`、`AppErrorState`、`AppSpacing`、ThemeDataを優先して使う。
   - 削除済み行は `docs/design/visual-direction.md` の `Trash And Restore` 方針に従い、危険ゾーンではなく「戻せる一覧」として扱う。
   - 行はmuted title、削除metadata、明確なrestore actionを持つ。
   - 削除metadataには少なくとも `deleted_at` 相当があることを表示する。表示形式は既存の日付metadata方針に合わせ、必要なら最小限のformat helperを使う。
   - restore actionは各行から実行できるようにする。icon buttonまたは明確なボタンを使い、tooltip/semanticsを付ける。
5. **状態表示**:
   - loadingは既存 `AppLoadingState` などに揃える。
   - errorはbridge error textを画面に出し、再読み込み導線が必要なら既存文法に沿って追加する。
   - emptyは「ゴミ箱は空」の状態として、安心できるが説明過多でない文言にする。
6. **i18n**:
   - 追加UI文字列は `app/lib/l10n/app_en.arb` と `app_ja.arb` に追加する。
   - `flutter gen-l10n` を実行し、生成済みlocalizationsを更新する。
   - `sh app/tool/check_hardcoded_strings.sh` を通す。
7. **widget test**:
   - `app/test/widget_test.dart` の fake bridgeは既に `trashTask` / `restoreTask` / `getTrashedTasks` を持つため、それを活かす。
   - ゴミ箱導線が表示され、tapでゴミ箱画面へ遷移できることを検証する。
   - タスクをtrashした後、active task一覧から消え、ゴミ箱画面に表示されることを検証する。
   - restore action後、ゴミ箱一覧から消え、元リストのactive task一覧へ戻ることを検証する。
   - empty / loading / errorは、少なくともemptyをwidget testで確認する。loading/errorは既存テスト構造に無理なく足せる範囲で確認する。

### やらないこと

- permanent deleteは実装しない。
- Undoは実装しない。
- fractional index、sort_order本実装、ドラッグ&ドロップ並び替え、手動/条件ソートUIは実装しない。
- ローカル通知、スヌーズ、通知登録/取消は実装しない。
- 検索UI、FTS配線、タグUI、設定画面、高機能UIモードは実装しない。
- Rust API、flutter_rust_bridge定義/生成物、DB schema、storage repository、domain usecaseは原則変更しない。
- 新規pub依存、UIフレームワーク、icon packageは追加しない。
- ゴミ箱画面を危険ゾーンとして演出しない。
- 復元成功時に派手なcelebration、mascot演出、confettiなどを追加しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `todori-private/` 配下を読んだり変更したりしない。private側の詳細をpublic repoへ転記しない。

## 5. 実装手順（例）

1. `git -C todori status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、既存route、provider、BridgeService、UI foundation、widget test fakeを確認する。
3. route設計を決め、`app/lib/src/router.dart` にゴミ箱画面routeを追加する。
4. `app/lib/src/core/providers.dart` に trashed tasks 用provider/notifierを追加し、`getTrashedTasks()` と `restoreTask()` をつなぐ。
5. `app/lib/src/screens/trash_screen.dart` などの画面を追加し、empty/loading/error/list/restore actionを実装する。
6. Tasks画面または適切な既存画面にゴミ箱導線を追加する。
7. 追加UI文字列を `app/lib/l10n/app_en.arb` / `app_ja.arb` に追加し、`cd app && flutter gen-l10n` を実行する。
8. `app/test/widget_test.dart` を更新し、導線、trash後の表示、restore後の復帰、empty stateを検証する。
9. 品質ゲートを実行する。
10. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] ゴミ箱画面routeが追加され、既存routeが壊れていない。
- [ ] Tasks画面または適切な既存画面からゴミ箱画面へ移動できる導線がある。
- [ ] 導線とrestore actionのicon-only controlにはtooltip/semanticsがある。
- [ ] `getTrashedTasks()` を読む trashed tasks provider/notifier が追加されている。
- [ ] provider/notifierに `restoreTask(taskId)` 相当のactionがあり、bridge call後にゴミ箱一覧が更新される。
- [ ] 復元後、該当タスクの元リストのactive task一覧も更新される。
- [ ] `trashTask` 実行後にゴミ箱一覧が古いまま残る問題がない、または画面遷移時に確実に再取得される。
- [ ] ゴミ箱画面に削除済みタスクの一覧が表示され、各行にmuted title、削除metadata、明確なrestore actionがある。
- [ ] ゴミ箱画面は `docs/design/visual-direction.md` の `Trash And Restore` 方針に従い、危険ゾーンではなく戻せる一覧として設計されている。
- [ ] permanent delete、Undo、fractional index、並び替え、通知、検索、タグは実装されていない。
- [ ] Rust API、FRB生成物、DB schema、storage repository、domain usecaseに不要な変更が入っていない。
- [ ] 新規pub依存、UIフレームワーク、icon packageが追加されていない。
- [ ] empty / loading / error状態が既存UI foundationに沿って表示される。
- [ ] 追加・変更UI文字列がen/ja ARB化され、生成済みlocalizationsが更新されている。
- [ ] UI文字列の直書き検出が通る。
- [ ] widget testでゴミ箱導線、削除済み一覧、restore action、復元後のactive task復帰、empty stateが検証されている。
- [ ] 既存widget testのタスク作成、編集、サブタスク表示/作成、親完了確認が引き続き通る。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `docs/tasks/task-23-trash-restore-ui.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクはゴミ箱画面・復元UIの実装であり、タスク管理機能全体の拡張ではない。
- BACKLOG上はM3-04相当だが、計画書上はM3-02の削除/復元残りにも対応する。完了報告ではこの対応関係を明記する。
- 既存の `get_trashed_tasks` / `restore_task` / `trash_task` を使う。Rust/FRB/DB/domain変更が必要に見える場合は、まず既存APIで実現できない理由を切り分け、不要な拡張を避ける。
- `restore_task` の復元先は元の `list_id` を保持する既存TaskDto/DB挙動に従う。UI側でlistを選び直す機能は追加しない。
- ゴミ箱は「戻せる一覧」であり、danger colorや強い警告文を主役にしない。
- permanent deleteは入れない。将来追加する場合も、別タスクで明示確認つきの二次操作として扱う。
- UI文字列は必ずARB化する。新しい `Text('...')` などの直書きを残さない。
- Dynamic Type、長いタスク名、狭い画面でrestore actionやmetadataが潰れないようにする。
- 秘密情報、Device Key、DB鍵、SQLCipher鍵をログやDebug出力に含めない。
- `docs/01〜03` は変更禁止である。仕様と実装の矛盾を見つけた場合は、仕様書を書き換えず完了報告の未解決事項に記録する。
- public repoにprivate repoの詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- M3-02 / BACKLOG上M3-04相当の対応関係
- 追加/変更したrouteと画面
- ゴミ箱導線の配置と理由
- 追加/変更したprovider/notifierとinvalidate方針
- `getTrashedTasks` / `restoreTask` / `trashTask` の使い方
- 復元後に更新されるproviderと、元リストのactive task一覧が更新されることの確認
- ゴミ箱行の表示方針（muted title、削除metadata、restore action）
- empty / loading / error状態の表示内容
- 追加/変更したi18nキー
- アクセシビリティ上維持・改善した点（tooltip/semantics、色以外の情報）
- 追加/更新したwidget test
- 品質ゲート6点と `check_hardcoded_strings.sh` の実行結果
- やらなかったことが守られていること（permanent delete、Undo、fractional index、並び替え、通知、検索、タグ、新規依存、Rust/FRB/DB/domain変更なし）
- public/private境界の確認結果
- 未解決事項・要人間判断

## 9. 完了報告

### 作業日

2026-07-05

### 読んだファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` の M3-02 / M3-04 / M3-05 周辺
- `docs/tasks/task-18-task-editing-ui.md`
- `docs/tasks/task-19-subtasks-ui.md`
- `docs/tasks/task-20-ui-foundation.md`
- `docs/tasks/task-21-visual-direction.md`
- `docs/tasks/task-22-design-direction-sketch.md`
- `docs/design/visual-direction.md` の `Trash And Restore` とcomponent rules
- `app/lib/src/router.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/core_usecases_test.dart`
- `app/tool/check_hardcoded_strings.sh`

### M3-02 / BACKLOG上M3-04相当の対応関係

- `docs/07_Phase1計画書.md` 上は M3-02「タスクCRUD UI」の削除/復元残りに対応する。
- `docs/tasks/BACKLOG.md` 上は「ゴミ箱画面・復元UI」として M3-04相当の先頭タスクに対応する。

### 追加/変更したrouteと画面

- `app/lib/src/router.dart` に top-level route `/trash`（name: `trash`）を追加した。
- `app/lib/src/screens/trash_screen.dart` を追加し、削除済みタスク一覧、empty / loading / error、行ごとのrestore actionを実装した。
- 既存 `/lists`、`/lists/:listId/tasks`、`/lists/:listId/tasks/:taskId` は維持した。

### ゴミ箱導線の配置と理由

- `app/lib/src/screens/tasks_screen.dart` の AppBar action に `Icons.restore_from_trash_outlined` のicon-only導線を追加した。
- 既存の通常タスク操作やFABを邪魔せず、削除操作がTaskDetailから行われる現在の情報設計でも、タスク一覧から復元先へ戻れるため。

### provider/notifierとinvalidate方針

- `app/lib/src/core/providers.dart` に `trashedTasksProvider` / `TrashedTasksNotifier` を追加した。
- `build()` は `BridgeService.getTrashedTasks()` を読む。
- `restoreTask(taskId)` は復元前の `TaskDto` から元 `listId` を取り、`BridgeService.restoreTask()` 後に `trashedTasksProvider` 自身と `tasksProvider(listId)` を更新する。
- 復元後に戻ったTasks画面で古いactive一覧が残らないよう、`tasksProvider(listId).future` も読み直している。
- `TasksNotifier.trashTask()` は `BridgeService.trashTask()` 後に当該active task一覧と `trashedTasksProvider` をinvalidateする。

### `getTrashedTasks` / `restoreTask` / `trashTask` の使い方

- ゴミ箱画面表示時に `getTrashedTasks()` を呼び、全体ゴミ箱として削除済みタスクを表示する。
- 行ごとのrestore actionから `restoreTask(taskId)` を呼ぶ。
- 既存TaskDetailの削除導線は `trashTask(taskId)` のまま使い、provider側でゴミ箱一覧のstale化を防ぐ。

### 復元後のactive task一覧確認

- widget testで、TaskDetailから `Move to trash` したタスクがactive一覧から消え、ゴミ箱に表示され、restore後にゴミ箱から消えて元リストのactive task一覧へ戻ることを確認した。

### ゴミ箱行の表示方針

- 行は白いsurfaceと薄いborderで既存task rowの視覚文法に寄せた。
- タイトルは `onSurfaceVariant` でmuted表示にした。
- metadataは `TaskMetadata` のpillを使い、少なくとも `deletedAt` を `taskDeletedAt` として表示する。priority / due dateがある場合も既存metadata方針で併記する。
- restore actionは右端の `Icons.restore_outlined` icon buttonとして配置した。

### empty / loading / error状態

- loading: 既存 `AppLoadingState`。
- error: 既存 `AppErrorState` で `failedToLoadTrash(error)` を表示。
- empty: 既存 `AppEmptyState` で「Trash is empty. / Deleted tasks will appear here.」相当の短い文言を表示。

### i18nキー

- `openTrashTooltip`
- `trashTitle`
- `trashEmptyTitle`
- `trashEmptyBody`
- `failedToLoadTrash`
- `restoreTaskTooltip`
- `taskDeletedAt`

`app/lib/l10n/app_en.arb` / `app_ja.arb` を更新し、`flutter gen-l10n` で `app/lib/src/generated/l10n/*` を更新した。

### アクセシビリティ

- Tasks画面のゴミ箱導線はicon-only controlとしてtooltipを持つ。
- ゴミ箱行のrestore actionはtooltipと `Semantics(button: true, label: ...)` を持つ。
- 削除状態は色だけに頼らず、`Deleted: ...` / `削除日時: ...` のmetadataで明示する。

### 追加/更新したwidget test

- Tasks画面にゴミ箱導線が表示されることを既存ナビゲーションテストへ追加した。
- ゴミ箱導線からempty trash screenへ遷移できるテストを追加した。
- TaskDetailからtrashしたタスクがactive一覧から消え、ゴミ箱に表示され、restore後に元リストへ戻るテストを追加した。
- 既存のタスク作成、編集、サブタスク表示/作成、親完了確認テストは継続して通過した。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（Rust 62 tests）。
- `cd app && flutter analyze`: 成功。初回はFlutter SDK cache書き込みがサンドボックスで拒否されたため、承認付きで再実行して成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test`: 成功（Flutter 22 tests）。初回の対象widget testでprovider invalidate timingを修正し、最終的に全件成功。Flutter SDK cache制約のため承認付きで実行。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。

### やらなかったこと

- permanent delete、Undo、fractional index、並び替え、通知、検索、タグは実装していない。
- 新規pub依存、UIフレームワーク、icon packageは追加していない。
- Rust API、FRB生成物、DB schema、storage repository、domain usecaseは変更していない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。

### public/private境界

- `todori-private/` は読んでおらず、変更していない。
- public repoへprivate側の課金、収益、法務、監査、公開前ロードマップ等の詳細は転記していない。

### 未解決事項・要人間判断

- なし。
