# task-18: タスク編集UI

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` のM3-02は「タスクCRUD UIを実装する」を定義しており、完了条件は「画面からタスク作成/編集/削除/復元ができ、DBに反映されること」である。task-09までに、リスト一覧→タスク一覧→タスク詳細の画面骨格、タスク作成、done遷移、論理削除（ゴミ箱へ移動）は実装済みである。一方、タスク詳細画面で既存タスクの `title` / `note` / `priority` / `due_at` を編集するUIと、Dart/FRB経由でそれをDBへ永続化するAPIは未実装である。

`core/domain` には `update_title` / `update_note` / `update_priority` / `update_due_at` が実装済みであり、`core/storage` の `TaskRepository::update` も永続化に対応している。したがって、このタスクでは `app/rust` のブリッジAPIへ更新系APIを追加し、FRB生成物を再生成した上で、Flutterのタスク詳細画面から編集できるようにする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/02_機能仕様書.md` F-05 / F-06 / F-07
- `docs/07_Phase1計画書.md` M3-02 / M3-04 / M3-05
- `docs/tasks/task-08-bridge-usecases.md`
- `docs/tasks/task-09-ui-skeleton.md`
- `docs/tasks/task-10-i18n.md`
- `core/domain/src/usecases.rs`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `flutter_rust_bridge.yaml`

## 3. ゴール

タスク詳細画面から既存タスクの主要フィールドを編集し、DBへ反映できる状態にする。

- Rust bridgeにタスク更新APIを追加する。
- FRB生成物を再生成し、Dart側から更新APIを呼べるようにする。
- `BridgeService` と `TasksNotifier` に更新操作を追加し、更新後にタスク一覧/詳細が再取得されるようにする。
- タスク詳細画面に編集フォームを追加する。
- UI文字列をen/ja ARBへ追加し、直書き検出を通す。
- widget testで「詳細画面から編集して一覧/詳細に反映される」ことを検証する。

## 4. スコープ

### やること

1. **Rust bridge API追加**:
   - `app/rust/src/api.rs` に `update_task(...) -> Result<TaskDto, String>` 相当のAPIを追加する。
   - 引数は少なくとも `task_id: String` / `title: String` / `note: String` / `priority: i32` / `due_at: Option<i64>` を受け取る。
   - `TaskRepository::get` で既存タスクを取得し、`core/domain` の `update_title` / `update_note` / `update_priority` / `update_due_at` を使って更新し、`TaskRepository::update` で永続化する。
   - `core/domain::update_priority` は範囲検証を持たないため、bridge層またはUI層で `priority` を `0..=3` に制限する。bridge層でも範囲外を拒否すると安全である。
   - `updated_at` は各domain usecaseの `now_ms` により更新される。複数フィールド更新時の `updated_at` は最後に適用した更新時刻でよいが、完了報告に実装方針を記録する。
   - 削除済みタスクを編集しようとした場合のdomain errorをそのままDartへ返す。
2. **FRB再生成**:
   - リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
   - 生成物（`app/rust/src/frb_generated.*`、`app/lib/src/rust/` 配下）はコミット対象とし、手編集しない。
3. **Dart bridge抽象更新**:
   - `app/lib/src/core/bridge_service.dart` の `BridgeService` / `FrbBridgeService` に更新APIを追加する。
   - `app/test/widget_test.dart` の `FakeBridgeService` にも同じAPIを追加する。
4. **Riverpod更新**:
   - `TasksNotifier` に `updateTask(...)` メソッドを追加する。
   - 更新成功後は `ref.invalidateSelf()` で `tasksProvider(listId)` を再取得する。
   - `taskDetailProvider` は `tasksProvider` から導出されるため、詳細画面も更新に追随することを確認する。
5. **タスク詳細UI更新**:
   - `TaskDetailScreen` で `title` / `note` / `priority` / `due_at` を編集できるようにする。
   - 実装方式は、詳細画面内に「Edit」ボタンを置いて編集ダイアログまたは編集画面を開く形でよい。
   - `title` は空白のみを保存できないようにし、domain errorをユーザーに見える形で表示する。
   - `note` は空文字を許可する。
   - `priority` は「なし/低/中/高」に対応する `0..3` をUIから選べるようにし、範囲外を送らない。
   - `due_at` は設定とクリアの両方を扱えるようにする。日付選択UIを使う場合は、epoch millisecondsへの変換方針を完了報告に記録する。
6. **i18n**:
   - 追加するUI文字列は `app/lib/l10n/app_en.arb` と `app_ja.arb` に追加する。
   - `cd app && flutter gen-l10n` で生成済みlocalizationsを更新する。
   - `sh app/tool/check_hardcoded_strings.sh` を通す。
7. **テスト**:
   - `app/test/widget_test.dart` に、タスク詳細画面から編集し、一覧/詳細に新しい値が表示され、FakeBridgeServiceにも反映されるテストを追加する。
   - 空title保存が拒否される、またはbridge/domain errorとして表示されるテストも追加する。
   - Rust bridge更新APIについて、既存の `app/test/core_usecases_test.dart` へDart側統合テストを追加するか、別テストを追加し、実DBへ永続化されることを検証する。

### やらないこと

- サブタスク表示・作成は実装しない。
- ゴミ箱画面・復元UIは実装しない。
- Undoは実装しない。
- ステータス遷移UIの拡張（`in_progress` / `wont_do` / 再オープン）は、このタスクでは必須にしない。
- 並び替えUIやfractional index本実装は行わない。
- 通知、予定時刻（`scheduled_at`）、見積時間（`estimated_minutes`）、担当者、タグ、コメントは扱わない。
- UIデザインの大幅な磨き込みやテーマ変更は行わない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- private repoの詳細をpublic repoへ転記しない。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. `core/domain/src/usecases.rs` と `app/rust/src/api.rs` を読み、更新APIの形を決める。
3. `app/rust/src/api.rs` に `update_task` を追加する。
4. `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
5. `app/lib/src/core/bridge_service.dart` と `app/lib/src/core/providers.dart` を更新する。
6. `TaskDetailScreen` に編集UIを追加する。
7. ARBへ文字列を追加し、必要なlocalization生成を行う。
   - `cd app && flutter gen-l10n`
8. widget testとDart/Rust bridge統合テストを追加する。
9. 品質ゲート6点を実行する。
10. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] Rust bridgeにタスク更新APIが追加され、`title` / `note` / `priority` / `due_at` を更新できる。
- [ ] FRB生成物が再生成され、手編集されていない。
- [ ] `BridgeService` / `FrbBridgeService` / `FakeBridgeService` が更新APIに対応している。
- [ ] `TasksNotifier` 経由で更新後に `tasksProvider` と `taskDetailProvider` が更新される。
- [ ] タスク詳細画面から `title` / `note` / `priority` / `due_at` を編集できる。
- [ ] `priority` はUIから `0..3` の範囲外を送らず、bridge層でも範囲外を拒否する方針が実装または記録されている。
- [ ] `due_at` は設定とクリアの両方ができる。
- [ ] 空titleなどdomain errorがユーザーに見える形で表示される。
- [ ] 追加UI文字列がen/ja ARB化され、直書き検出が通る。
- [ ] widget testで編集内容が一覧/詳細/フェイクserviceへ反映されることを検証している。
- [ ] 実DBを使うDart bridge統合テストで更新APIの永続化が検証されている。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `docs/tasks/task-18-task-editing-ui.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- Rust APIを変更するため、FRB再生成は必須である。
- `flutter_rust_bridge` のバージョンは `2.12.0` 固定であり、Rust側crateとDart側pubのバージョン一致を崩さない。
- FRB生成物は手編集しない。
- DK、SQLCipher鍵、DB鍵、Device KeyをログやDebug出力に含めない。
- `FileDeviceKeyStore` は開発用の暫定実装であり、本番向けKeychain実装は別タスクで扱う。
- 日付/時刻UIはロケールやタイムゾーンで複雑化しやすい。MVPとしての変換方針を明記し、通知やカレンダー機能へスコープを広げない。
- このタスクは「編集UI」に集中する。ゴミ箱画面、復元UI、Undo、サブタスク、並び替えは後続タスクで扱う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- 追加/変更したRust bridge API
- FRB再生成の結果
- 追加/変更したDart provider / service
- 編集UIの仕様（title / note / priority / due_at）
- due_atのepoch milliseconds変換方針
- priorityの扱い（`0..3` の意味と範囲外入力の扱い）
- 追加したi18nキー
- 追加/更新したテスト
- 品質ゲート6点の実行結果
- 未解決事項・要人間判断

## 9. 完了報告

- 作業日: 2026-07-04
- 読んだファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/task-18-task-editing-ui.md`
  - `app/rust/src/api.rs`
  - `app/lib/src/core/bridge_service.dart`
  - `app/lib/src/core/providers.dart`
  - `app/lib/src/screens/task_detail_screen.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/test/widget_test.dart`
  - `app/test/core_usecases_test.dart`
  - `core/domain/src/usecases.rs`
  - `app/tool/check_hardcoded_strings.sh`
- 追加/変更したRust bridge API:
  - `app/rust/src/api.rs` に `update_task(task_id, title, note, priority, due_at) -> Result<TaskDto, String>` を追加済み。
  - `TaskRepository::get` で既存タスクを取得し、`update_title` / `update_note` / `update_priority` / `update_due_at` を順に適用して `TaskRepository::update` で永続化する。
  - `priority` は bridge 層で `0..=3` の範囲外を `task priority must be between 0 and 3` として拒否する。
  - `updated_at` は1回取得した `now_ms` を各 field update に渡すため、複数フィールド更新時は同一タイムスタンプになる。
- FRB再生成の結果:
  - `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、`app/lib/src/rust/**` と `app/rust/src/frb_generated.rs` を再生成した。
  - 生成物は手編集していない。
- 追加/変更したDart provider / service:
  - `BridgeService` / `FrbBridgeService` に `updateTask` を追加済み。
  - `TasksNotifier.updateTask` は bridge 呼び出し後に `ref.invalidateSelf()` で該当 list の `tasksProvider` を再取得する。`taskDetailProvider` は `tasksProvider` 由来のため更新に追随する。
- 編集UIの仕様:
  - `TaskDetailScreen` の AppBar に編集アイコンを追加し、編集ダイアログから保存する。
  - `title` は trim 後の空文字を保存不可とし、フォームエラーを表示する。
  - `note` は空文字を許可する。
  - `priority` は `None` / `Low` / `Medium` / `High` のドロップダウンで `0` / `1` / `2` / `3` を送る。
  - `due_at` は `Set date` で日付選択、`Clear date` で `null` クリアできる。
- due_atのepoch milliseconds変換方針:
  - `showDatePicker` の選択日をローカル日付の `DateTime(year, month, day)` として扱い、その日のローカル 00:00 の `millisecondsSinceEpoch` を bridge に渡す。
  - 表示時は保存済み epoch milliseconds をローカル日時へ戻し、`yyyy-MM-dd` 形式で表示する。
- priorityの扱い:
  - `0 = none`, `1 = low`, `2 = medium`, `3 = high` 相当。
  - UI はドロップダウンで範囲外入力を作らない。
  - bridge 層も `0..=3` 以外を拒否する。
- 追加したi18nキー:
  - `noteLabel`
  - `taskDueAt`
  - `editTaskTooltip`
  - `editTaskTitle`
  - `priorityLabel`
  - `priorityNone`
  - `priorityLow`
  - `priorityMedium`
  - `priorityHigh`
  - `dueDateLabel`
  - `setDueDateButton`
  - `clearDueDateButton`
  - `saveButton`
  - `titleRequiredError`
  - `failedToSaveTask`
- 追加/更新したテスト:
  - `app/test/widget_test.dart`
    - `FakeBridgeService.updateTask` を追加。
    - 詳細画面から title / note / priority を編集し、詳細・一覧・FakeBridgeService 状態へ反映されるテストを追加。
    - 空 title 保存でフォームエラーが表示されるテストを追加。
  - `app/test/core_usecases_test.dart`
    - 実DB/FRB経由で `updateTask` が title / note / priority / dueAt を永続化し、dueAt の `null` クリアも反映されるテストを追加。
    - priority 範囲外エラーのテストを追加。
- 品質ゲートの実行結果:
  - `cargo fmt --all -- --check`: 成功
  - `cargo clippy --workspace -- -D warnings`: 成功
  - `cargo test --workspace`: 成功
  - `cd app && flutter gen-l10n`: 成功
  - `cd app && flutter analyze`: 成功
  - `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
  - `cd app && flutter test`: 成功
  - `sh app/tool/check_hardcoded_strings.sh`: 成功
  - `git -C todori diff --check`: 成功
- 補足:
  - Flutter/Dart ツールはサンドボックス内では SDK cache への書き込み権限で失敗したため、承認付き実行で `dart format` / `flutter gen-l10n` / `flutter_rust_bridge_codegen generate` / `flutter analyze` / `flutter test` を実行した。
- 未解決事項・要人間判断:
  - なし。
