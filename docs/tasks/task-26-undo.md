# task-26: 削除/完了/編集のUndo

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-05

## 1. 背景とコンテキスト

`docs/tasks/BACKLOG.md` の優先度付きバックログ先頭は「Undo」であり、内容は削除/完了/編集のUndoである。`docs/07_Phase1計画書.md` のM3-05は「Undoと手動/条件並び替えを実装する」を定義し、完了条件に「削除/完了/編集のUndo」と「手動/締切/優先度/作成順ソート」を含めている。

task-24ではM3-05のうちfractional index生成とタスク一覧の同一階層内手動並び替えUIを実装済みである。一方、Undoは履歴データ構造、操作単位、復元時の競合方針が必要になるため、task-24から分離された。task-25では、Undoや条件ソートUIへ進む前に既存実画面の密度、i18n、Dynamic Type、tooltip/semanticsなどを較正済みである。

現状の操作面では、編集は `updateTask`、完了は `setTaskStatus(taskId, 'done')`、削除は `trashTask` に集約されている。復元UIとしてはゴミ箱画面の `restoreTask` があるが、これは明示的にゴミ箱から戻す操作であり、「直前操作をすばやく取り消す」Undoとは別の体験として扱う。このタスクでは、ローカル専用Phase 1の範囲で、同一端末のSQLCipher DB内にUndo履歴を保持し、削除/完了/編集の直後にユーザーが元の状態へ戻せるようにする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` M3-05
- `docs/tasks/task-18-task-editing-ui.md`
- `docs/tasks/task-19-subtasks-ui.md`
- `docs/tasks/task-23-trash-restore-ui.md`
- `docs/tasks/task-24-fractional-index.md`
- `docs/tasks/task-25-design-calibration-ui-pass.md`
- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `flutter_rust_bridge.yaml`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/core_usecases_test.dart`
- `app/test/widget_test.dart`
- `app/tool/check_hardcoded_strings.sh`

必要に応じて、FRB生成物の差分確認対象として `app/rust/src/frb_generated.rs` と `app/lib/src/rust/` 配下も読む。ただし生成物は手編集しない。

## 3. ゴール

削除/完了/編集の直前状態を履歴として保存し、ユーザーが直後にUndoできる状態にする。

- Undo履歴のデータ構造と永続化先を定義する。
- 操作単位を、削除1件、完了1件、編集保存1回として扱う。
- `trashTask` / `setTaskStatus(..., 'done')` / `updateTask` の成功時にUndo履歴を作成する。
- Undo実行時は保存済みsnapshotを使い、対象タスクを元の状態へ戻す。
- 復元時の競合方針を実装し、テストで検証する。
- Flutter UIでは、対象操作の成功直後にUndo actionを出し、必要に応じてタスク一覧/詳細/ゴミ箱一覧を再取得する。
- i18n、tooltip/semantics、長い文言/狭い画面での表示破綻を避ける。
- Rust/domain/storage/FRB/Dart provider/widget testでUndoの主要経路を検証する。

## 4. スコープ

### 想定変更ファイル

後続workerは、実装に必要な場合に限り、以下を中心に変更する。実際の差分は受け入れ基準を満たす最小範囲に留める。

- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/lib/src/rust/` 配下のFRB生成物
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- 必要な場合のみ `app/lib/src/screens/trash_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/` 配下のl10n生成物
- `app/test/core_usecases_test.dart`
- `app/test/widget_test.dart`
- 必要な場合のみ `core/storage` / `app/rust` の既存テストファイル
- `docs/tasks/task-26-undo.md`（実装完了時の `## 9. 完了報告` 追記のみ）

### やること

1. **Undo履歴データ構造の定義**:
   - ローカルSQLCipher DB内にUndo履歴を保存する。例: `task_undo_entries` テーブルを `core/storage/src/schema.sql` に追加する。
   - 履歴は少なくとも以下を表現できること:
     - `id`
     - `operation_type`（例: `delete` / `complete` / `edit`）
     - `task_id`
     - `list_id`
     - 操作前snapshot
     - 操作後snapshot、または操作後の `updated_at` / `deleted_at` / `completed_at` 等の競合検出に必要な値
     - `created_at`
     - `consumed_at` または同等の「使用済み」状態
   - snapshotは `Task` 全体をJSONとして保持する、または同等の構造化カラムとして保持する。JSONを使う場合は既存workspace依存の `serde` / `serde_json` を優先し、新規依存は追加しない。
   - 履歴はローカル専用の一時的なユーザー操作履歴であり、同期プロトコル、監査ログ、永続的な変更履歴として扱わない。
2. **操作単位の明確化**:
   - 削除Undoは、1回の `trashTask(taskId)` 成功につき1件のUndo履歴を作る。Undo時は `deleted_at` を操作前snapshotへ戻し、タイトル、note、status、priority、due_at、sort_order、親子関係なども操作前snapshotと整合するように戻す。
   - 完了Undoは、Tasks画面のチェック操作などで `setTaskStatus(taskId, 'done')` が成功したときに1件のUndo履歴を作る。Undo時は直前の `status`、`completed_at`、`closed_reason`、`updated_at` を戻す。直前statusが `todo` 以外でもsnapshotに従って戻せる形にする。
   - 編集Undoは、タスク詳細の編集保存1回につき1件のUndo履歴を作る。Undo対象は task-18で編集済みの `title` / `note` / `priority` / `due_at` を中心にし、保存前snapshotへ戻す。
   - 新規タスク作成、サブタスク作成、手動並び替え、ゴミ箱画面からの明示的restore、リスト操作はこのタスクのUndo対象にしない。
3. **履歴作成の実装境界**:
   - 履歴作成は、Flutter UIだけではなくRust bridge/storage側でDB更新と同じ成功経路に置く。
   - `app/rust/src/api.rs` の `update_task` / `set_task_status` / `trash_task` で、更新前taskを取得し、更新成功後にUndo履歴を保存する。
   - `set_task_status` は `status == 'done'` のときだけUndo履歴を作る。`todo` への再オープン、`in_progress`、`wont_do` はこのタスクではUndo履歴作成対象外でよい。
   - 対象操作がdomain/storage errorで失敗した場合、Undo履歴を作らない。
   - DB更新と履歴保存の失敗時の扱いを明確にする。可能なら同一SQLite transactionで「タスク更新と履歴作成」をまとめ、片方だけ成功する状態を避ける。
4. **Undo API追加**:
   - Rust bridgeに、少なくとも「最新の未使用Undo履歴を取得するAPI」と「指定Undo履歴を適用するAPI」を追加する。例:
     - `get_latest_task_undo() -> Result<Option<TaskUndoDto>, String>`
     - `undo_task_operation(undo_id: String) -> Result<TaskDto, String>`
   - `TaskUndoDto` には、Flutter UIが文言を出せる程度の `id`、`operationType`、`taskId`、`listId`、`taskTitle`、`createdAt` を含める。
   - API名は既存の `snake_case` Rust / `camelCase` Dart生成規則に合わせる。
   - Rust APIを変更した場合はFRB生成物を再生成する。
5. **復元時の競合方針**:
   - Undo対象taskが存在しない場合はエラーにする。
   - Undo履歴がすでに使用済みの場合はエラー、またはno-opとして明確に扱い、採用した方針を完了報告に記録する。
   - Undo履歴作成後に対象taskが別操作で更新されている場合は、原則として競合としてUndoを拒否する。判定は `updated_at`、`deleted_at`、`completed_at`、または操作後snapshotとの比較など、実装しやすく説明可能な方法を使う。
   - ただし、削除Undoについては「削除直後にゴミ箱画面を開いただけ」のような読み取り操作は競合扱いにしない。
   - 完了Undoで、対象taskが削除済みになっている場合は競合として拒否する。
   - 編集Undoで、Undo履歴作成後に再編集されている場合は競合として拒否する。
   - 競合エラーはFlutter UIに表示できる文言へ変換し、秘密情報やDB内部情報を含めない。
6. **Dart bridge / provider更新**:
   - `app/lib/src/core/bridge_service.dart` の `BridgeService` / `FrbBridgeService` にUndo関連APIを追加する。
   - `app/test/widget_test.dart` の `FakeBridgeService` にも同等のUndo履歴作成/取得/適用挙動を追加する。
   - `app/lib/src/core/providers.dart` に最新Undo履歴を扱うprovider/notifierを追加する。名前は既存のprovider命名に揃える。
   - `TasksNotifier.updateTask` / `setStatus` / `trashTask` の成功後、最新Undo履歴をUIで見せられるようにする。
   - Undo適用後は、対象 `tasksProvider(listId)`、`taskDetailProvider` 由来の表示、必要に応じて `trashedTasksProvider` を再取得する。
7. **Flutter UI**:
   - 削除/完了/編集の成功直後、Undo actionをユーザーが実行できるようにする。
   - 最小実装は `ScaffoldMessenger` の `SnackBar` actionでよい。既存UI foundationやtask-25の較正方針に合わせ、画面の主操作を邪魔しない位置と文言にする。
   - SnackBar等の一時UIだけに履歴を閉じ込めず、Undo適用はRust bridge API経由で行う。
   - 編集成功後に詳細画面でUndoできること、削除後に一覧または遷移先画面からUndoできること、完了直後に一覧でUndoできることを確認する。
   - Undo成功時は該当画面の表示を更新する。Undo失敗/競合時は、ユーザーに短いエラーを表示する。
   - 追加UI文字列はen/ja ARBへ追加し、直書き検出を通す。
   - icon-only controlを追加する場合はtooltip/semanticsを付ける。SnackBar actionの文言は短く、Dynamic Typeと狭い画面で破綻しないようにする。
8. **テスト**:
   - `core/storage` または `app/rust` 経由のテストで、削除/完了/編集それぞれの履歴作成とUndo適用を検証する。
   - 競合方針のテストを少なくとも以下で追加する:
     - Undo履歴作成後に対象taskが再編集された編集Undoは拒否される。
     - 完了Undo対象が削除済みになっている場合は拒否される。
     - 使用済みUndo履歴の再適用は拒否またはno-opとして方針どおりに扱われる。
   - `app/test/core_usecases_test.dart` などのDart/FRB統合テストで、実DB経由で削除/完了/編集のUndoが永続化込みで動くことを検証する。
   - `app/test/widget_test.dart` で、削除/完了/編集後にUndo actionが表示され、tapで画面表示とFakeBridgeService状態が戻ることを検証する。
   - i18nや直書き検出に必要なテスト/生成物更新を行う。

### やらないこと

- 条件ソートUI、締切/優先度/作成順ソート切替、設定保存は実装しない。
- 手動並び替えのUndo、リスト並び替え、別親/別リスト移動、階層変更のUndoは実装しない。
- 新規タスク作成、サブタスク作成、ゴミ箱画面からの明示的restore、リスト作成/編集/削除のUndoは実装しない。
- 永続的な監査ログ、全履歴タイムライン、複数段Undo/Redo、履歴一覧画面は実装しない。
- 同期、アカウント、Organization共有、サーバー側競合解決、別端末とのUndo整合性は扱わない。
- permanent deleteは実装しない。
- 通知、検索UI、FTS5配線、タグ、Keychain、オンボーディング、タイマー、設定画面は実装しない。
- UIデザインの大幅な磨き込み、画像モック追加、常設マスコット、bottom navigationは実装しない。
- 新規Rust crate / pub package / UI frameworkは原則追加しない。どうしても必要な場合は、人間の事前承認を得て、理由・代替案・追加versionを完了報告へ記録する。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `taskveil-private/` 配下を読んだり変更したりしない。private側の詳細をpublic repoへ転記しない。

## 5. 実装手順（例）

1. `git -C taskveil status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、既存の `update_task`、`set_task_status`、`trash_task`、`TaskRepository::update`、`TasksNotifier`、Tasks/Detail/Trash画面、widget fakeの構造を確認する。
3. Undo履歴のDB schema、Rust型、repository API、競合判定方針を小さく決める。
4. `core/storage/src/schema.sql` にUndo履歴テーブルと必要なindexを追加する。
5. `core/storage/src/lib.rs` にUndo履歴の保存/取得/使用済み更新/適用に必要な最小repository実装を追加する。
6. `app/rust/src/api.rs` の `update_task` / `set_task_status` / `trash_task` を、更新前snapshotを保存してUndo履歴を作る形へ変更する。
7. `app/rust/src/api.rs` に最新Undo取得APIとUndo適用APIを追加する。
8. Rust API変更に合わせて `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
9. `app/lib/src/core/bridge_service.dart`、`app/lib/src/core/providers.dart`、`app/test/widget_test.dart` のFakeBridgeServiceをUndo対応に更新する。
10. `TasksScreen` / `TaskDetailScreen` / 必要なら `TrashScreen` に、操作成功後のUndo action表示とUndo失敗時の短いエラー表示を追加する。
11. ARBへ文字列を追加し、`cd app && flutter gen-l10n` を実行する。
12. Rust/storage/API、Dart/FRB統合、widget testを追加/更新する。
13. 品質ゲートを実行する。
14. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] `core/storage/src/schema.sql` にUndo履歴用テーブルまたは同等の永続構造が追加されている。
- [ ] Undo履歴は `delete` / `complete` / `edit` のoperation type、対象task/list、操作前snapshot、競合判定に必要な操作後情報、作成時刻、使用済み状態を持つ。
- [ ] Undo履歴はローカル専用の一時操作履歴として扱われ、同期・監査ログ・履歴一覧画面へスコープが広がっていない。
- [ ] `trash_task` 成功時に削除Undo履歴が作成され、Undoで削除前snapshotに戻る。
- [ ] `set_task_status(..., 'done')` 成功時に完了Undo履歴が作成され、Undoで直前status / completed_at / closed_reasonへ戻る。
- [ ] `update_task` 成功時に編集Undo履歴が作成され、Undoで `title` / `note` / `priority` / `due_at` を含む保存前状態へ戻る。
- [ ] 操作が失敗した場合はUndo履歴が作成されない。
- [ ] 可能な限りタスク更新とUndo履歴作成が同一SQLite transactionにまとまり、片方だけ成功する状態を避けている。別方針の場合は理由が完了報告に記録されている。
- [ ] 最新の未使用Undo履歴を取得するRust bridge APIが追加されている。
- [ ] 指定Undo履歴を適用するRust bridge APIが追加されている。
- [ ] Undo適用後、該当履歴は使用済みになり、同じ履歴の二重適用が方針どおり拒否またはno-opになる。
- [ ] Undo対象taskが存在しない場合はエラーになる。
- [ ] 編集Undoは、履歴作成後に対象taskが再編集されている場合に競合として拒否される。
- [ ] 完了Undoは、対象taskが削除済みになっている場合に競合として拒否される。
- [ ] 競合エラーはFlutter UIで短く表示され、秘密情報やDB内部情報を含まない。
- [ ] Rust API変更に対応してFRB生成物が再生成され、生成物は手編集されていない。
- [ ] `BridgeService` / `FrbBridgeService` / `FakeBridgeService` がUndo関連APIに対応している。
- [ ] provider/notifier経由でUndo適用後に対象 `tasksProvider(listId)` と必要な `trashedTasksProvider` が再取得される。
- [ ] 削除/完了/編集の成功直後にUndo actionが表示される。
- [ ] Undo action実行後、Tasks画面/TaskDetail画面/Trash画面の表示が操作前状態へ戻る、または該当画面が自然に更新される。
- [ ] 追加UI文字列がen/ja ARB化され、生成済みlocalizationsが更新されている。
- [ ] SnackBar action等の文言が短く、Dynamic Typeや狭い画面で破綻しにくい。
- [ ] widget testで削除/完了/編集それぞれのUndo action表示と状態復元を検証している。
- [ ] Dart/FRB統合テストで削除/完了/編集のUndoが実DB経由で検証されている。
- [ ] Rust/storage/APIテストで履歴作成、Undo適用、競合方針、二重適用方針を検証している。
- [ ] 条件ソートUI、手動並び替えUndo、リストUndo、複数段Undo/Redo、履歴一覧画面、新規依存追加がスコープ外として守られている。
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [ ] public repoにprivate詳細が転記されていない。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `git diff --check` が成功している。
- [ ] 変更ファイルは4章「想定変更ファイル」を中心とする最小範囲に収まり、スコープ外ファイルを変更していない。
- [ ] `docs/tasks/task-26-undo.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクはM3-05のうちUndoだけを扱う。条件ソートUIは別タスクとして残す。
- task-24で実装済みのfractional index / 手動並び替えを前提にする。Undo実装で `sort_order` や並び替えUIを作り直さない。
- 削除Undoはゴミ箱画面の明示的restoreとは別の直前操作取り消しとして扱う。ただし内部的に同じdomain/storage更新方針を再利用してよい。
- Undo履歴はPhase 1ローカル専用の操作補助であり、同期・監査・別端末競合解決へ広げない。
- 履歴snapshotに秘密情報、Device Key、SQLCipher鍵、DB鍵を含めない。Task entityに含まれる通常タスク情報以外を保存しない。
- `updated_at` を競合判定に使う場合、Undo適用自体では新しい `updated_at` を設定するのか、snapshotの `updated_at` を復元するのかを明確にする。ユーザー-visibleな復元と将来同期の分かりやすさを優先し、採用方針を完了報告に記録する。
- SQLite schema追加は既存DBへの影響を考える。`CREATE TABLE IF NOT EXISTS` / `CREATE INDEX IF NOT EXISTS` で既存開発DBを壊さない。
- Rust APIを変更したらFRB再生成が必須である。生成物（`app/rust/src/frb_generated.rs`、`app/lib/src/rust/` 配下）は手編集しない。
- `flutter_rust_bridge` は `2.12.0` 固定であり、Rust側crateとDart側pubのバージョン一致を崩さない。
- UI文字列は必ずARB化する。`Text('...')`、`SnackBar(content: Text('...'))`、`Tooltip(message: '...')` などの直書きを残さない。
- public repoにprivate repoの課金、収益、法務、監査、公開前ロードマップ詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- M3-05のうち実装した範囲と、条件ソートUIを分けた理由
- 追加したUndo履歴データ構造（table/index/型/operation type/snapshot形式）
- 操作単位の仕様（削除/完了/編集それぞれ）
- 履歴作成の実装境界（Rust bridge/storage側でどこに保存したか）
- タスク更新と履歴作成のtransaction方針
- 復元時の競合方針とエラー表示方針
- 追加/変更したRust bridge API
- FRB再生成の結果
- 追加/変更したDart provider / service / fake
- Undo UIの仕様（どの画面で、どの操作後に、どう表示されるか）
- Undo適用後のprovider invalidate / 画面更新方針
- 追加/変更したi18nキー
- 追加/更新したテスト（Rust/storage/API、Dart/FRB統合、widget）
- 品質ゲート6点、`check_hardcoded_strings.sh`、`git diff --check` の実行結果
- FRB生成物が手編集されていないことの確認
- やらなかったことが守られていること（条件ソートUI、手動並び替えUndo、リストUndo、複数段Undo/Redo、履歴一覧画面、新規依存なし）
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` を変更していないこと
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
- `docs/07_Phase1計画書.md` M3-05
- `docs/tasks/task-18-task-editing-ui.md`
- `docs/tasks/task-19-subtasks-ui.md`
- `docs/tasks/task-23-trash-restore-ui.md`
- `docs/tasks/task-24-fractional-index.md`
- `docs/tasks/task-25-design-calibration-ui-pass.md`
- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `core/storage/src/schema.sql`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `flutter_rust_bridge.yaml`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/core_usecases_test.dart`
- `app/test/widget_test.dart`
- `app/tool/check_hardcoded_strings.sh`

### M3-05のうち実装した範囲

- 実装した範囲は、削除/完了/編集の直前操作Undoに限定した。
- 条件ソートUIは、表示順の切替状態、設定保存、手動順との関係を別途決める必要があるため、このタスクでは扱っていない。
- 手動並び替えUndo、複数段Undo/Redo、履歴一覧画面、リストUndoはスコープ外として実装していない。

### Undo履歴データ構造

- `core/storage/src/schema.sql` に `task_undo_entries` を追加した。
- 主なカラム:
  - `id`
  - `operation_type` (`delete` / `complete` / `edit`)
  - `task_id`
  - `list_id`
  - `before_snapshot`
  - `after_updated_at`
  - `after_deleted_at`
  - `after_completed_at`
  - `created_at`
  - `consumed_at`
- index:
  - `idx_task_undo_entries_latest`
  - `idx_task_undo_entries_task_id`
- Rust型:
  - `TaskUndoOperation`
  - `TaskUndoEntry`
- snapshot形式:
  - `taskveil_domain::Task` 全体を `serde_json` で `before_snapshot` に保存する。
  - 新規依存は追加せず、workspace既存の `serde_json` を `taskveil-storage` から参照した。

### 操作単位

- 削除Undo:
  - `trash_task(task_id)` で未削除taskを削除した成功時に1件作成する。
  - Undo時は削除前snapshotへ戻す。
  - 既に削除済みのtaskへ `trash_task` が呼ばれた場合は新しいUndo履歴を作らない。
- 完了Undo:
  - `set_task_status(task_id, "done", ...)` 成功時に1件作成する。
  - Undo時は直前の `status` / `completed_at` / `closed_reason` を含むsnapshotへ戻す。
  - `todo` への再オープン、`in_progress`、`wont_do` は履歴作成対象外。
- 編集Undo:
  - `update_task(...)` の保存1回につき1件作成する。
  - Undo時は `title` / `note` / `priority` / `due_at` を含む保存前snapshotへ戻す。

### 履歴作成の実装境界

- 履歴作成は Flutter UI ではなく Rust bridge/storage 側に置いた。
- `app/rust/src/api.rs` の以下の成功経路から `SqliteTaskRepository::update_with_undo(...)` を呼ぶ:
  - `update_task`
  - `set_task_status` の `TaskStatus::Done`
  - `trash_task` の未削除task削除
- domain/storage errorで操作が失敗した場合、Undo履歴は作成されない。

### transaction方針

- `core/storage/src/lib.rs` に `SqliteTaskRepository::update_with_undo(...)` を追加し、task更新とUndo履歴insertを同一SQLite transactionで実行する。
- Undo適用も `undo_task_operation(...)` 内で、競合確認、task復元、`consumed_at` 更新を同一transactionで実行する。
- Undo適用時のtask本体は `before_snapshot` をそのまま復元するため、`updated_at` も操作前snapshotの値へ戻る。競合検出と使用済み状態はUndo履歴側に残す方針とした。

### 復元時の競合方針とエラー表示

- Undo対象taskが存在しない場合は `record not found` 系のエラーになる。
- 使用済みUndo履歴の再適用は `undo entry already used` として拒否する。
- Undo履歴作成後に対象taskの `updated_at` / `deleted_at` / `completed_at` が操作後値から変わっている場合は `task changed after undo was created` として拒否する。
- 編集Undo後の再編集、完了Undo対象の削除済み化は競合として拒否する。
- Flutter UIでは `Undo failed: {error}` / `元に戻せませんでした: {error}` の短いSnackBarへ変換する。秘密情報やDB鍵は含めていない。

### 追加/変更したRust bridge API

- `TaskUndoDto`
  - `id`
  - `operation_type`
  - `task_id`
  - `list_id`
  - `task_title`
  - `created_at`
- `get_latest_task_undo() -> Result<Option<TaskUndoDto>, String>`
- `undo_task_operation(undo_id: String) -> Result<TaskDto, String>`
- 既存の `update_task` / `set_task_status` / `trash_task` をUndo履歴作成対応に変更した。

### FRB再生成

- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行した。
- 初回はFlutter SDK cacheへのworkspace外書き込みがサンドボックスで拒否されたため、承認付きで再実行して成功した。
- `app/rust/src/frb_generated.rs` と `app/lib/src/rust/` 配下を生成更新した。
- 生成物は手編集していない。

### Dart provider / service / fake

- `BridgeService` / `FrbBridgeService` に以下を追加:
  - `getLatestTaskUndo`
  - `undoTaskOperation`
- `providers.dart` に `LatestTaskUndoNotifier` / `latestTaskUndoProvider` を追加した。
- `TasksNotifier.updateTask` / `setStatus(..., "done")` / `trashTask` 成功後に `latestTaskUndoProvider` をinvalidateする。
- `FakeBridgeService` にUndo履歴作成、最新取得、適用、使用済み拒否、競合拒否を追加した。

### Undo UI

- Tasks画面:
  - task完了成功後に `SnackBar` を表示し、`Undo` actionから完了前状態へ戻せる。
- TaskDetail画面:
  - 編集保存成功後に `SnackBar` を表示し、`Undo` actionから保存前状態へ戻せる。
  - 削除成功後に `SnackBar` を表示し、一覧へ戻った後も `Undo` actionから削除前状態へ戻せる。
- SnackBar文言は短い操作結果文 + actionにした。
- routeをpopした後もUndo actionが動くよう、actionでは画面の `WidgetRef` ではなく上位 `ProviderContainer` を使う。

### provider invalidate / 画面更新方針

- Undo適用後、復元されたtaskの `tasksProvider(restored.listId)` をinvalidateする。
- 削除Undoにも対応するため、`trashedTasksProvider` もinvalidateする。
- `taskDetailProvider` は `tasksProvider` 由来のため、該当listの再取得に追随する。
- `LatestTaskUndoNotifier.undo(...)` は適用後に自身もinvalidateし、使用済み履歴が再表示されないようにする。

### 追加/変更したi18nキー

- `undoActionLabel`
- `undoCompleteMessage`
- `undoDeleteMessage`
- `undoEditMessage`
- `undoSuccessMessage`
- `undoFailedMessage`

### 追加/更新したテスト

- Rust/storage:
  - `update_with_undo_records_edit_and_restores_previous_snapshot`
  - `delete_and_complete_undo_entries_restore_task_state`
  - `undo_rejects_edit_conflict_after_later_update`
  - `complete_undo_rejects_deleted_current_task`
  - 使用済みUndo履歴の再適用拒否も検証した。
- Dart/FRB統合:
  - `delete complete and edit undo roundtrip through Rust bridge`
  - `undo rejects conflicts and consumed entries`
- widget:
  - 完了後のUndo action表示と状態復元
  - 編集後のUndo action表示と状態復元
  - 削除後のUndo action表示と状態復元
- FakeBridgeServiceも同じ方針で履歴・競合・使用済み状態を扱う。

### 品質ゲート実行結果

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功。Rust 74 tests。
- `cd app && flutter analyze`: 成功。初回はSDK cache制約で失敗、承認付き再実行で成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test`: 成功。Flutter 34 tests。初回はSDK cache制約で失敗、承認付き再実行後に1件のcontext/ref生存期間問題を修正し、再実行で成功。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git diff --check`: 成功。

### スコープ確認

- 条件ソートUIは実装していない。
- 手動並び替えUndo、リストUndo、複数段Undo/Redo、履歴一覧画面は実装していない。
- 新規Rust crate / pub package / UI frameworkは追加していない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。
- `taskveil-private/` は読んでおらず、public repoにprivate詳細は転記していない。

### 未解決事項・要人間判断

- 最終合否判定は実装workerでは行わない。別セッションまたは親Codexで受け入れ基準・スコープ逸脱・品質ゲートの独立検証を行うこと。
- 条件ソートUIはBACKLOGの次タスクとして残る。
