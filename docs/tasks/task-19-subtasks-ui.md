# task-19: サブタスク表示・作成

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

`docs/tasks/BACKLOG.md` の優先度1は「サブタスク表示・作成」であり、`docs/07_Phase1計画書.md` のM3-03「サブタスク無制限階層と進捗表示を実装する」に相当する。完了条件は「3階層以上のサブタスク作成、親完了時の確認、進捗率表示のwidget testが通ること」である。

現時点では `core/domain` に `validate_parent` / `validate_parent_for` が実装済みであり、自己参照、存在しない親、別リストの親、削除済み親、循環参照を拒否できる。`new_task` も `parent_task_id: Option<Uuid>` を受け取れる。一方、`app/rust/src/api.rs` の `create_task` は `parent_task_id: None` 固定で、Dart側の `BridgeService.createTask` / `TasksNotifier.createTask` / タスク作成UIも親タスクIDを受け取らない。したがって、このタスクでは既存domain実装を前提に、サブタスク作成に必要なbridge公開とFlutter UI導線を追加する。

既存の `TaskDto` には `parent_task_id` が含まれており、`core/storage` の `TaskRepository` は `parent_task_id` の保存・更新・取得に対応している。`list_active_by_list` は指定リストのactiveタスクをまとめて返すため、Flutter側で親子関係を組み立てて表示できる。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/02_機能仕様書.md` F-05 / F-06 / F-07
- `docs/07_Phase1計画書.md` M3-02 / M3-03 / M3-04 / M3-05
- `docs/tasks/task-08-bridge-usecases.md`
- `docs/tasks/task-09-ui-skeleton.md`
- `docs/tasks/task-10-i18n.md`
- `docs/tasks/task-18-task-editing-ui.md`
- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/rust/src/api.rs`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/core_usecases_test.dart`
- `flutter_rust_bridge.yaml`

## 3. ゴール

タスク詳細画面からサブタスクを作成でき、タスク一覧・詳細画面で親子関係と進捗が確認できる状態にする。

- Rust bridgeのタスク作成APIで任意の `parent_task_id` を受け取れるようにする。
- 親指定時は `core/domain` の `validate_parent_for` で検証してから保存する。
- FRB生成物を再生成し、Dart側からサブタスク作成を呼べるようにする。
- `BridgeService` / `TasksNotifier` / `FakeBridgeService` を親ID付き作成に対応させる。
- タスク一覧とタスク詳細でサブタスク階層を表示する。
- タスク詳細から子タスクを作成する導線を追加する。
- 子タスクの完了状況から親タスクの進捗率を表示する。
- 親タスクを完了しようとしたとき、未完了の子孫タスクがある場合は確認ダイアログを出す。
- 追加UI文字列をen/ja ARBへ追加し、直書き検出を通す。
- widget testとDart bridge統合テストで、3階層以上の作成・表示・進捗・親完了確認を検証する。

## 4. スコープ

### やること

1. **Rust bridge API更新**:
   - `app/rust/src/api.rs` の `create_task` を `parent_task_id: Option<String>` 相当の引数に対応させる。
   - 既存のトップレベルタスク作成は `parent_task_id: None` で従来どおり動くようにする。
   - `parent_task_id` が指定された場合は `parse_uuid` で親IDを検証し、`new_task(list_id, Some(parent_id), ...)` で未保存の新規タスクを作った後、insert前に `validate_parent(&task, parent_id, &tasks)` または `validate_parent_for(task.id, list_id, parent_id, &tasks)` を通す。
   - `tasks` には循環検出に必要な同一リストの既存タスクを含める。削除済み親を `ParentDeleted` として拒否できるよう、候補親がactive一覧に含まれない場合も `TaskRepository::get(parent_id)` などで候補親を取得して検証対象へ含めることを検討する。
   - 親が存在しない、別リスト、削除済み、循環参照になる場合はdomain errorをDartへ返す。
   - `TaskDto.parent_task_id` に保存済み親IDが返ることを確認する。
2. **FRB再生成**:
   - リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
   - `flutter_rust_bridge` / `flutter_rust_bridge_codegen` は `2.12.0` 固定を維持する。
   - 生成物（`app/rust/src/frb_generated.rs`、`app/rust/frb_generated.h`、`app/lib/src/rust/` 配下）はコミット対象とし、手編集しない。
3. **Dart bridge抽象更新**:
   - `BridgeService.createTask` / `FrbBridgeService.createTask` に `String? parentTaskId` を追加する。
   - `app/test/widget_test.dart` の `FakeBridgeService.createTask` も同じシグネチャに更新し、作成した `TaskDto.parentTaskId` に反映する。
   - 既存のトップレベルタスク作成テストが壊れないよう、呼び出し側では `parentTaskId` を省略可能にする。
4. **Riverpod更新**:
   - `TasksNotifier.createTask` に任意の `parentTaskId` を追加する。
   - サブタスク作成成功後は `ref.invalidateSelf()` で `tasksProvider(listId)` を再取得する。
   - `taskDetailProvider` は `tasksProvider` 由来のため、詳細画面の子タスク表示も更新に追随することを確認する。
   - 必要なら、`tasksProvider` の取得結果から親子関係・子孫数・完了数を計算する純粋なDartヘルパーを追加する。画面内に複雑な再帰処理を散らさない。
5. **タスク一覧UI更新**:
   - `TasksScreen` で `parentTaskId == null` のタスクをトップレベルとして表示し、子タスクは親の下へインデントして表示する。
   - 3階層以上を表示できる再帰またはスタックベースの組み立てにする。
   - 同一親配下の並び順は既存の `sort_order` 昇順を維持する。
   - サブタスク行からも既存どおり詳細画面へ遷移できるようにする。
   - 親子関係が壊れたデータが返った場合はアプリがクラッシュしないよう、孤立タスクをトップレベル扱いにするなど防御的に表示する。採用した方針を完了報告に記録する。
6. **タスク詳細UI更新**:
   - `TaskDetailScreen` に、そのタスクの直下サブタスク一覧を表示する。
   - 詳細画面から「サブタスク追加」ボタンまたは同等の導線で、現在のタスクを親にしたタスクを作成できるようにする。
   - サブタスク作成ダイアログは既存の新規タスク作成ダイアログと同等のtitle入力でよい。空titleは保存しない。
   - 子タスク行から該当サブタスクの詳細画面へ遷移できるようにする。
7. **進捗表示**:
   - 各親タスクに対して、子孫タスク全体のうち `status == 'done'` の割合を表示する。
   - 子孫が0件の場合は進捗率を表示しない、または `0/0` ではない自然な表示にする。
   - 進捗計算は直下の子だけでなく子孫全体を対象にする。3階層以上で計算が正しいことをテストする。
   - `wont_do` 等の未完了扱いは、既存UIで作成・選択できないため、ひとまず `done` 以外は未完了として扱う。別方針を取る場合は完了報告に記録する。
8. **親完了時の確認**:
   - `TasksScreen` または `TaskDetailScreen` で親タスクを `done` にしようとしたとき、未完了の子孫タスクがある場合は確認ダイアログを表示する。
   - 確認で続行した場合のみ既存の `setStatus(task.id, 'done')` を呼ぶ。
   - 未完了の子孫がない場合は確認なしで従来どおり完了できる。
   - このタスクでは子孫タスクを自動完了にしない。
9. **i18n**:
   - 追加UI文字列は `app/lib/l10n/app_en.arb` と `app/lib/l10n/app_ja.arb` に追加する。
   - `cd app && flutter gen-l10n` で生成済みlocalizationsを更新する。
   - `sh app/tool/check_hardcoded_strings.sh` を通す。
10. **テスト**:
    - `app/test/widget_test.dart` に、トップレベル→子→孫の3階層を作成し、一覧/詳細で階層表示されることを検証するwidget testを追加する。
    - 詳細画面からサブタスクを作成し、FakeBridgeServiceの `parentTaskId` と画面表示に反映されることを検証する。
    - 子孫タスクのdone状態から進捗表示が更新されることを検証する。
    - 未完了子孫を持つ親をdoneにすると確認ダイアログが出ること、キャンセルでは状態変更されず、続行では `setTaskStatus` が呼ばれることを検証する。
    - `app/test/core_usecases_test.dart` など実DBを使うDart bridge統合テストで、親ID付き `createTask` が永続化され、`getTasks` で `parentTaskId` が返ることを検証する。
    - bridge統合テストで、存在しない親ID、別リスト親ID、削除済み親IDの拒否を少なくとも1件以上検証する。循環参照は新規作成UIだけでは起こしづらいため、Rust側で検証済みであることを確認し、必要ならbridge側単体に近いテストを追加する。

### やらないこと

- `validate_parent` / `validate_parent_for` の全面再実装はしない。既存domain実装を使う。
- サブタスクの親変更UI、ドラッグ&ドロップでの階層変更、親からの切り離しは実装しない。
- サブタスク削除時に子孫を一括削除・一括復元する仕様は扱わない。
- 子孫タスクの自動完了、自動再オープン、親子ステータス同期は実装しない。
- `wont_do` / `in_progress` / 再オープンのUI拡張は、このタスクでは必須にしない。
- ゴミ箱画面・復元UIは実装しない。
- Undoは実装しない。
- fractional index本実装、ドラッグ&ドロップ並び替え、手動/条件ソートUIは実装しない。
- 通知、予定時刻（`scheduled_at`）、見積時間（`estimated_minutes`）、担当者、タグ、コメントは扱わない。
- UIデザインの大幅な磨き込み、テーマ変更、高機能UIモードは行わない。
- 新規pubパッケージやRust crateは追加しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `taskveil-private/` 配下を読んだり変更したりしない。private側の詳細をpublic repoへ転記しない。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、既存の `create_task`、`TaskDto.parent_task_id`、`validate_parent_for`、`TasksNotifier`、画面構成、テストの流儀を把握する。
3. `app/rust/src/api.rs` の `create_task` を親ID付きに更新し、親指定時に `validate_parent_for` を呼ぶ。
4. 必要最小限のRustテストまたは既存Dart bridge統合テストの準備を行う。
5. `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
6. `BridgeService` / `FrbBridgeService` / `FakeBridgeService` / `TasksNotifier.createTask` を `parentTaskId` 対応に更新する。
7. 親子関係と進捗を計算するDartヘルパーを実装する。
8. `TasksScreen` と `TaskDetailScreen` に階層表示、サブタスク作成導線、進捗表示、親完了確認を追加する。
9. ARBへ追加文字列を入れ、`flutter gen-l10n` を実行する。
10. widget testとDart bridge統合テストを追加・更新する。
11. 品質ゲート6点と直書き検出を実行する。
12. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] `app/rust/src/api.rs` の `create_task` が `parent_task_id` / `parentTaskId` 相当を受け取れる。
- [ ] `parent_task_id` 未指定のトップレベルタスク作成が従来どおり動く。
- [ ] 親指定時に `core/domain` の `validate_parent_for` または同等の既存domain検証が使われている。
- [ ] 存在しない親、別リストの親、削除済み親がbridge経由で拒否される。
- [ ] 作成されたサブタスクの `parentTaskId` がDBへ永続化され、`getTasks` でDartへ返る。
- [ ] FRB生成物が再生成され、手編集されていない。
- [ ] `BridgeService` / `FrbBridgeService` / `FakeBridgeService` / `TasksNotifier` が親ID付き作成に対応している。
- [ ] タスク一覧画面で3階層以上のサブタスクが親の下に表示される。
- [ ] タスク詳細画面で直下サブタスクが表示され、子タスク詳細へ遷移できる。
- [ ] タスク詳細画面から現在のタスクを親にしたサブタスクを作成できる。
- [ ] 子孫タスク全体を対象にした進捗表示があり、done数/総子孫数または割合がユーザーに見える。
- [ ] 未完了子孫を持つ親タスクをdoneにしようとすると確認ダイアログが表示される。
- [ ] 確認ダイアログでキャンセルした場合は親タスクの状態が変わらない。
- [ ] 確認ダイアログで続行した場合のみ親タスクがdoneになる。
- [ ] 子孫を自動完了にしない。
- [ ] 追加UI文字列がen/ja ARB化され、直書き検出が通る。
- [ ] widget testで3階層以上の作成・表示、進捗表示、親完了確認を検証している。
- [ ] 実DBを使うDart bridge統合テストで親ID付き作成と永続化を検証している。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `docs/tasks/task-19-subtasks-ui.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- Rust APIを変更するため、FRB再生成は必須である。
- `flutter_rust_bridge` / `flutter_rust_bridge_codegen` は `2.12.0` 固定であり、Rust側crateとDart側pubのバージョン一致を崩さない。
- FRB生成物は手編集しない。
- `parent_task_id` はDBスキーマ、repository、DTOに既に存在する。新しいカラム追加やmigrationを行う前に、既存実装で足りるか確認する。
- `list_active_by_list` は削除済みタスクを返さない。削除済み親を既存domainの `ParentDeleted` として拒否するには、候補親を `TaskRepository::get` で個別取得して検証対象へ含めるなど、repositoryの取得方法を確認する。採用した方法を完了報告に記録する。
- 子孫計算は循環しない前提だが、表示側でも無限ループを避ける防御を入れる。
- サブタスク階層は無制限を前提にするが、UIはMVPとして深すぎる階層でもクラッシュせず、インデントが破綻しない程度でよい。
- `sort_order` は既存の暫定連番（`a0`, `a1`, ...）のままでよい。fractional index本実装は別タスクで扱う。
- UI文字列は必ずARB化する。新しい `Text('...')` などの直書きを残さない。
- 秘密情報、Device Key、DB鍵、SQLCipher鍵をログやDebug出力に含めない。
- `docs/01〜03` は変更禁止である。仕様と実装の矛盾を見つけた場合は、仕様書を書き換えず完了報告の未解決事項に記録する。
- public repoにprivate repoの詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- 変更したRust bridge APIと `parent_task_id` の扱い
- `validate_parent_for` / `validate_parent` の利用箇所と、拒否できる親候補エラー
- FRB再生成の結果
- 追加/変更したDart provider / service / FakeBridgeService
- 階層表示の仕様（トップレベル判定、子の並び順、孤立タスクの扱い、深い階層の表示方針）
- サブタスク作成UIの仕様
- 進捗表示の計算方針（子孫範囲、`done` 以外の扱い、子孫0件時の表示）
- 親完了時の確認ダイアログ仕様
- 追加したi18nキー
- 追加/更新したテスト
- 品質ゲート6点と `check_hardcoded_strings.sh` の実行結果
- 未解決事項・要人間判断

## 9. 完了報告

- 作業日: 2026-07-04
- 読んだファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/PLAYBOOK.md`
  - `docs/tasks/BACKLOG.md`
  - `docs/02_機能仕様書.md` F-05 / F-06 / F-07
  - `docs/07_Phase1計画書.md` M3-02 / M3-03 / M3-04 / M3-05
  - `docs/tasks/task-08-bridge-usecases.md`
  - `docs/tasks/task-09-ui-skeleton.md`
  - `docs/tasks/task-10-i18n.md`
  - `docs/tasks/task-18-task-editing-ui.md`
  - `core/domain/src/entities.rs`
  - `core/domain/src/usecases.rs`
  - `core/storage/src/lib.rs`
  - `core/storage/src/schema.sql`
  - `app/rust/src/api.rs`
  - `app/lib/src/core/bridge_service.dart`
  - `app/lib/src/core/providers.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/screens/task_detail_screen.dart`
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/test/widget_test.dart`
  - `app/test/core_usecases_test.dart`
  - `flutter_rust_bridge.yaml`
- 変更したRust bridge APIと `parent_task_id` の扱い:
  - `app/rust/src/api.rs` の `create_task` を `parent_task_id: Option<String>` 付きに変更した。
  - `parent_task_id` 未指定時は `new_task(list_id, None, ...)` として従来どおりトップレベルタスクを作成する。
  - `parent_task_id` 指定時はUUID文字列を `parse_uuid` で検証し、`new_task(list_id, Some(parent_id), ...)` で未保存タスクを作成してからinsert前に親検証を行う。
- `validate_parent_for` の利用箇所と拒否できる親候補エラー:
  - `create_task` 内で同一リストの `list_active_by_list(list_id)` 結果を取得し、候補親がactive一覧に無い場合は `TaskRepository::get(parent_id)` で個別取得して検証対象に追加した。
  - これにより、存在しない親は `ParentNotFound`、別リスト親は `ParentInDifferentList`、削除済み親は `ParentDeleted` としてdomain検証経由で拒否できる。
  - 循環参照は新規作成UIでは通常発生しないが、bridge側は既存domainの `validate_parent_for(task.id, list_id, parent_id, &tasks)` を使うためdomain実装の循環検出に従う。
- FRB再生成の結果:
  - `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、`app/lib/src/rust/api.dart`、`app/lib/src/rust/frb_generated.dart`、`app/rust/src/frb_generated.rs` を再生成した。
  - `flutter_rust_bridge` / `flutter_rust_bridge_codegen` は `2.12.0` 固定を維持した。
  - 生成物は手編集していない。
- 追加/変更したDart provider / service / FakeBridgeService:
  - `BridgeService.createTask` / `FrbBridgeService.createTask` に省略可能な `String? parentTaskId` を追加した。
  - `TasksNotifier.createTask(String title, {String? parentTaskId})` を追加し、同一親配下の既存兄弟数から暫定 `sortOrder` を生成してからbridgeへ渡す。
  - `FakeBridgeService.createTask` も `parentTaskId` を受け取り、作成した `TaskDto.parentTaskId` に保存するよう更新した。
  - `app/lib/src/core/task_tree.dart` を追加し、階層構築、flatten、直下子取得、子孫進捗、未完了子孫判定を画面外へ切り出した。
- 階層表示の仕様:
  - `parentTaskId == null` のタスクをトップレベルとして扱う。
  - 親IDが存在しない孤立タスクはトップレベル扱いで表示し、アプリがクラッシュしないようにした。
  - 同一親配下の並び順は `sortOrder` 昇順、同値の場合は `id` 昇順とした。
  - 3階層以上は再帰的に表示する。表示インデントは深すぎる階層で破綻しないよう、一覧画面では4段階分までに抑制した。
  - 表示側でも重複/循環風データに対して `visited` / `emitted` を使い、無限再帰しないよう防御した。
- サブタスク作成UIの仕様:
  - `TaskDetailScreen` に直下サブタスク一覧と `Add subtask` ボタンを追加した。
  - 追加ボタンからtitle入力ダイアログを開き、空titleまたは空白のみtitleは保存しない。
  - 保存時は現在表示中のタスクIDを `parentTaskId` として `TasksNotifier.createTask` へ渡す。
  - 子タスク行をタップすると既存ルート `/lists/:listId/tasks/:taskId` で該当サブタスク詳細へ遷移する。
- 進捗表示の計算方針:
  - 進捗は直下子だけでなく子孫タスク全体を対象にし、`status == 'done'` の件数 / 総子孫数を `Progress: done/total` として表示する。
  - `done` 以外（`todo`, `in_progress`, `wont_do` など）は未完了扱いとした。
  - 子孫0件のタスクでは進捗を表示しないため、`0/0` は表示しない。
- 親完了時の確認ダイアログ仕様:
  - `TasksScreen` のcheckboxで `done` にしようとしたとき、未完了の子孫がある場合だけ確認ダイアログを表示する。
  - キャンセルでは `setStatus` を呼ばず、親タスクの状態は変わらない。
  - 続行時のみ `setStatus(task.id, 'done')` を呼ぶ。
  - 子孫タスクは自動完了しない。
- 追加したi18nキー:
  - `subtasksTitle`
  - `subtasksEmpty`
  - `addSubtaskButton`
  - `newSubtaskTitle`
  - `subtaskProgress`
  - `completeTaskDialogTitle`
  - `completeTaskDialogMessage`
  - `continueButton`
- 追加/更新したテスト:
  - `app/test/widget_test.dart`
    - `FakeBridgeService.createTask` を `parentTaskId` 対応に更新。
    - トップレベル→子→孫の3階層表示と子孫進捗を検証するwidget testを追加。
    - 詳細画面からサブタスクを作成し、FakeBridgeServiceの `parentTaskId` と画面表示に反映されることを検証するwidget testを追加。
    - 未完了子孫を持つ親完了時に確認ダイアログが出て、キャンセルでは状態変更されず、続行では親のみdoneになることを検証するwidget testを追加。
  - `app/test/core_usecases_test.dart`
    - 親ID付き `createTask` が実DBへ永続化され、`getTasks` で `parentTaskId` が返ることを検証するテストを追加。
    - 存在しない親、別リスト親、削除済み親がbridge経由で拒否されることを検証するテストを追加。
- 品質ゲートの実行結果:
  - `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`: 成功
  - `cargo fmt --all -- --check`: 成功
  - `cargo clippy --workspace -- -D warnings`: 成功
  - `cargo test --workspace`: 成功（Rust 62件）
  - `cd app && flutter gen-l10n`: 成功
  - `cd app && flutter analyze`: 成功（No issues found）
  - `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
  - `cd app && flutter test`: 成功（Flutter 20件）
  - `cd app && flutter test test/core_usecases_test.dart`: 成功（7件、bridge統合テストの明示確認）
  - `sh app/tool/check_hardcoded_strings.sh`: 成功
  - `git -C taskveil diff --check`: 成功
- 補足:
  - Flutter/Dartツールはサンドボックス内ではSDK cacheへの書き込み権限で失敗したため、承認付き実行で `flutter_rust_bridge_codegen generate` / `flutter gen-l10n` / `dart format` / `flutter analyze` / `flutter test` を実行した。
- 未解決事項・要人間判断:
  - なし。
