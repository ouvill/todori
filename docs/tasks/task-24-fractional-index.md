# task-24: fractional indexとタスク手動並び替えUI

> ステータス: 完了（`## 9. 完了報告` 追記済み・親/独立検証済み）
> 作業日: 2026-07-05

## 1. 背景とコンテキスト

`docs/tasks/BACKLOG.md` の優先度付きバックログ先頭は「fractional index」であり、内容は `sort_order` 生成の本実装（`core/domain`）と並び替えUIである。`AGENTS.md` でも、現在の `sort_order` は暫定連番（`'a0'`, `'a1'`, ...）であり、fractional index本実装はM3のタスクと明記されている。

現状のFlutter側では `app/lib/src/core/providers.dart` の `nextSortOrder()` が `a0`, `a1`, `a2` のような単調追加用の暫定値を作り、`BridgeService.createTask()` / Rust bridge の `create_task()` へ呼び出し側指定の `sortOrder` を渡している。Rust側の `Task` / `List` は `sort_order` を持ち、`core/storage` の `TaskRepository::list_active_by_list()` は `ORDER BY sort_order ASC` で取得しているが、「既存2項目の間へ挿入する」「並び替え時に既存項目の間の値を生成する」ための本実装はまだない。

`docs/07_Phase1計画書.md` の M3-05 は「Undoと手動/条件並び替えを実装する」であり、完了条件には削除/完了/編集のUndo、手動並び替え、締切/優先度/作成順ソートが含まれる。ただし、これらを1タスクでまとめると、履歴設計、表示順の切替、永続順の更新、UIテストが同時に膨らむ。この task-24 では M3-05 のうち、以降の性能検証や主要操作に必要な土台である **fractional index生成** と **タスク一覧の手動並び替えUI** に限定する。

リスト並び替えはこのタスクでは扱わない。理由は、現在のBACKLOGとM3-05の直近文脈がタスク操作の完成に寄っており、リスト並び替えまで同時に入れると `listsProvider`、リスト一覧UI、list CRUDの受け入れ基準まで広がるためである。まずタスクの同一階層内の順序を安定させ、リスト順序は後続タスクで同じfractional index実装を再利用できる状態にする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` M3-05
- `docs/tasks/task-18-task-editing-ui.md`
- `docs/tasks/task-19-subtasks-ui.md`
- `docs/tasks/task-23-trash-restore-ui.md`
- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/rust/src/api.rs`
- `flutter_rust_bridge.yaml`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/core_usecases_test.dart`
- `app/test/widget_test.dart`
- `app/tool/check_hardcoded_strings.sh`

必要に応じて、FRB生成物の差分確認対象として `app/lib/src/rust/` と `app/rust/src/frb_generated.rs` も読む。ただし生成物は手編集しない。

## 3. ゴール

タスクの `sort_order` を暫定連番からfractional indexベースへ移行し、タスク一覧で同一階層内の手動並び替えを最小UIとして実装する。

- `core/domain` にfractional index生成ロジックを追加する。
- 新規タスク作成時、Flutter側の暫定 `nextSortOrder()` ではなくRust/domain側で同一階層末尾に入る `sort_order` を生成する。
- 既存タスクを同一階層内で前後へ移動できるRust bridge APIを追加する。
- FRB生成物を再生成し、Dart側から並び替えAPIを呼べるようにする。
- `BridgeService` / `TasksNotifier` にタスク並び替え操作を追加し、成功後に該当リストのtask一覧を再取得する。
- `TasksScreen` に、同一階層内の手動並び替えUIを追加する。最小実装として、ドラッグ&ドロップではなく行ごとの上/下移動ボタンでもよい。
- サブタスクがある場合は、親子関係の変更や別階層への移動を行わず、同じ `parent_task_id` を持つ兄弟タスクの範囲だけを並び替える。
- UI文字列をen/ja ARBへ追加し、直書き検出を通す。
- Rust/domain/storage/FRB統合テストとFlutter widget testで、生成順と手動並び替えを検証する。

## 4. スコープ

### やること

1. **fractional index生成のdomain実装**:
   - `core/domain/src/usecases.rs` または適切なdomain moduleに、2つの既存 `sort_order` の間、先頭、末尾に入る文字列を生成する関数を追加する。
   - 値はSQLiteの `TEXT` とDart/Rustの通常文字列比較で安定して昇順比較できる形式にする。
   - 浮動小数点、現在時刻、乱数に依存しない決定的な生成にする。
   - 同一階層において `previous < generated < next`、先頭挿入、末尾追加、連続挿入が成立することをdomain unit testで検証する。
   - 不正な境界（例: `previous >= next`、空/不正文字を含む値など）を検出する方針を実装または明記する。
2. **新規タスク作成時の `sort_order` 生成をRust側へ移す**:
   - `app/rust/src/api.rs` の `create_task` で、対象リスト内のactive tasksを取得し、`parent_task_id` が一致する兄弟タスクの末尾に入るfractional indexを生成する。
   - Flutter側から渡された暫定 `sortOrder` に依存しない形にする。API signatureを変える場合は、FRB再生成とDart側呼び出し更新を必須とする。
   - `app/lib/src/core/providers.dart` の `TasksNotifier.createTask()` がタスク用の暫定 `nextSortOrder()` に依存しないことを確認する。`nextSortOrder()` はリスト作成用に残してよいが、タスク作成用に残す場合は理由を完了報告に書く。
   - サブタスク作成時も、親タスク直下の兄弟内で末尾に入るようにする。
3. **タスク並び替えAPI追加**:
   - `app/rust/src/api.rs` に `move_task` / `reorder_task` 相当のAPIを追加する。
   - 引数は対象 `task_id` と、新しい位置を表す `previous_task_id: Option<String>` / `next_task_id: Option<String>` など、同一階層内の前後関係を明確に表せる形にする。
   - 対象タスク、前後タスクがactiveであり、同じ `list_id` と同じ `parent_task_id` に属することを検証する。別リスト、別親、削除済み、対象自身を境界に指定するケースはエラーにする。
   - 生成した `sort_order` を `TaskRepository::update` で永続化し、`updated_at` も更新する。
   - 既存の `TaskRepository::update` が `sort_order` を更新できるため、不要なstorage trait拡張は避ける。必要になった場合だけ最小のAPI追加に留める。
4. **FRB再生成**:
   - Rust APIを変更した場合は、リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
   - `app/rust/src/frb_generated.rs` と `app/lib/src/rust/` 配下の生成物はコミット対象とし、手編集しない。
5. **Dart bridge / provider更新**:
   - `app/lib/src/core/bridge_service.dart` の `BridgeService` / `FrbBridgeService` に並び替えAPIを追加する。
   - `app/test/widget_test.dart` の `FakeBridgeService` にも同等の並び替え挙動を追加する。
   - `app/lib/src/core/providers.dart` の `TasksNotifier` に `moveTaskUp` / `moveTaskDown` / `reorderTask` 相当の操作を追加する。
   - 並び替え成功後は `ref.invalidateSelf()` で該当 `tasksProvider(listId)` を再取得し、`taskDetailProvider` と表示が古い順序を保持しないようにする。
6. **タスク一覧の手動並び替えUI**:
   - `app/lib/src/screens/tasks_screen.dart` または共通row componentに、同一階層内でタスクを上/下へ動かす最小UIを追加する。
   - 最小実装としては、各行に上/下のicon buttonを置き、同一 `parent_task_id` の兄弟内で前後移動する形でよい。ドラッグ&ドロップにする場合も、同一階層外への移動や親子関係変更は実装しない。
   - 先頭行の上移動、末尾行の下移動は無効化するか表示しない。
   - icon-only controlにはtooltip/semanticsを付ける。
   - サブタスクを含む階層表示では、同じ親を持つ兄弟だけを移動対象にし、親子関係や階層深度が変わらないことを保つ。
   - UI追加でタスク行のタイトル、metadata、checkbox、priority dot、階層線が狭い画面で破綻しないようにする。
7. **i18n**:
   - 追加UI文字列は `app/lib/l10n/app_en.arb` と `app_ja.arb` に追加する。
   - `cd app && flutter gen-l10n` を実行し、生成済みlocalizationsを更新する。
   - `sh app/tool/check_hardcoded_strings.sh` を通す。
8. **テスト**:
   - `core/domain` のunit testでfractional index生成の境界条件を検証する。
   - `app/test/core_usecases_test.dart` などのDart/FRB統合テストで、新規task作成時の `sort_order` がRust側生成になり、並び替えAPI後の `getTasks()` が新しい順序を返すことを検証する。
   - `app/test/widget_test.dart` で、Tasks画面の手動並び替えUIから順序が変わり、画面表示とFakeBridgeService状態に反映されることを検証する。
   - サブタスクがある場合、同一親の兄弟だけが並び替わり、親子関係が変わらないことを少なくともunit/widgetのどちらかで検証する。

### やらないこと

- Undoは実装しない。
- 締切順、優先度順、作成順などの条件ソートUIは実装しない。
- 条件ソートと手動順の切替状態、ユーザー設定、永続化は実装しない。
- リスト一覧の手動並び替え、リストのfractional index更新UIは実装しない。
- タスクの別リスト移動、別親への移動、ドラッグによる階層変更、インデント/アウトデントは実装しない。
- permanent delete、ゴミ箱UIの拡張、復元履歴、通知、検索、タグ、アプリロックは実装しない。
- DB schema migrationは原則行わない。既存 `sort_order TEXT NOT NULL` を使う。
- 新規Rust crate / pub package / UI frameworkは原則追加しない。どうしても必要な場合は、人間の事前承認を得て、理由・代替案・追加versionを完了報告へ記録する。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `taskveil-private/` 配下を読んだり変更したりしない。private側の詳細をpublic repoへ転記しない。

## 5. 実装手順（例）

1. `git -C taskveil status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、現在の `sort_order` 生成、`create_task`、`TaskRepository::update`、`TasksNotifier`、Tasks画面、widget fakeの構造を確認する。
3. `core/domain` にfractional index生成関数とunit testを追加する。
4. `app/rust/src/api.rs` の `create_task` を、対象兄弟の末尾 `sort_order` をRust側で生成する形へ変更する。
5. `app/rust/src/api.rs` にタスク並び替えAPIを追加し、同一list/同一parent/active task検証と `TaskRepository::update` 永続化を実装する。
6. Rust API変更に合わせて `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
7. `app/lib/src/core/bridge_service.dart`、`app/lib/src/core/providers.dart`、`app/test/widget_test.dart` のFakeBridgeServiceを更新する。
8. `app/lib/src/screens/tasks_screen.dart` と必要なら `app/lib/src/ui/task_components.dart` に、上/下移動の最小UIを追加する。
9. ARBへ文字列を追加し、`cd app && flutter gen-l10n` を実行する。
10. domain unit test、Dart/FRB統合テスト、widget testを追加/更新する。
11. 品質ゲートを実行する。
12. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] `core/domain` に決定的なfractional index生成ロジックが追加されている。
- [ ] fractional index生成は、先頭、末尾、2値の間、連続挿入、不正境界をunit testで検証している。
- [ ] 新規タスク作成時のタスク用 `sort_order` はRust/domain側で生成され、Flutterの暫定 `nextSortOrder()` に依存していない。
- [ ] サブタスク作成時の `sort_order` は、同じ `parent_task_id` を持つ兄弟内で末尾になる。
- [ ] タスク並び替えAPIがRust bridgeに追加され、対象/前後タスクが同一 `list_id` かつ同一 `parent_task_id` のactive taskであることを検証している。
- [ ] 別リスト、別親、削除済み、対象自身を境界にする並び替えはエラーになる。
- [ ] 並び替えAPIは生成した `sort_order` を永続化し、`getTasks(listId)` が新しい順序を返す。
- [ ] Rust API変更に対応してFRB生成物が再生成され、生成物は手編集されていない。
- [ ] `BridgeService` / `FrbBridgeService` / `FakeBridgeService` が並び替えAPIに対応している。
- [ ] `TasksNotifier` に手動並び替え操作が追加され、成功後に該当listの `tasksProvider` が再取得される。
- [ ] Tasks画面で同一階層内のタスクを手動で前後移動できる。
- [ ] 先頭/末尾では無効な移動操作が表示されない、または無効状態として扱われる。
- [ ] サブタスクを含む一覧で、並び替えにより親子関係や階層深度が変わらない。
- [ ] icon-only controlにはtooltip/semanticsがある。
- [ ] 追加UI文字列がen/ja ARB化され、生成済みlocalizationsが更新されている。
- [ ] UI文字列の直書き検出が通る。
- [ ] widget testで手動並び替えUIによる表示順変更とFakeBridgeService状態更新を検証している。
- [ ] Dart/FRB統合テストで新規task作成時の生成順と並び替えAPIの永続化を検証している。
- [ ] Undo、条件ソートUI、リスト並び替え、別親/別リスト移動、階層変更、新規依存追加がスコープ外として守られている。
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `docs/tasks/task-24-fractional-index.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクはM3-05全体ではなく、fractional indexとタスク手動並び替えに限定する。
- Undoは履歴データ構造、操作単位、復元時の競合方針が必要になるため別タスクに分ける。
- 条件ソートUIは、手動順 `sort_order` と締切/優先度/作成順の表示順をどう切り替えるか、ユーザー設定をどこに保存するかを決める必要があるため別タスクに分ける。
- リスト並び替えは `listsProvider` とリスト一覧UIの別スコープとして扱う。task-24で作るdomain helperは後続で再利用できる形にしてよい。
- `sort_order` は同期や将来の競合解決に関わるため、値の比較規則をDart/Rust/SQLite間で揃える。大文字小文字やロケール依存照合は避ける。
- `TaskRepository::list_active_by_list()` は全active taskを `sort_order ASC` で返す。UI階層表示は `task_tree.dart` が同一親ごとに再構成しているため、並び替え実装では「同一親の兄弟順」を壊さない。
- Rust APIを変更したらFRB再生成が必須である。生成物（`app/rust/src/frb_generated.rs`、`app/lib/src/rust/` 配下）は手編集しない。
- `flutter_rust_bridge` は `2.12.0` 固定であり、Rust側crateとDart側pubのバージョン一致を崩さない。
- 新規依存は原則追加しない。fractional indexは小さなdomain helperとして実装することを優先する。
- UI文字列は必ずARB化する。`Text('...')`、`Tooltip(message: '...')` などの直書きを残さない。
- 秘密情報、Device Key、SQLCipher鍵、DB鍵をログやDebug出力に含めない。
- `docs/01〜03` は変更禁止である。仕様と実装の矛盾を見つけた場合は、仕様書を書き換えず完了報告の未解決事項に記録する。
- public repoにprivate repoの詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- M3-05のうち実装した範囲と、Undo/条件ソート/リスト並び替えを分けた理由
- 追加したfractional index生成ロジックの仕様（文字集合、比較規則、先頭/末尾/中間生成、不正境界の扱い）
- 新規task作成時の `sort_order` 生成方針（root task / subtaskそれぞれ）
- 追加/変更したRust bridge API
- FRB再生成の結果
- 追加/変更したDart provider / service / fake
- 手動並び替えUIの仕様（上/下移動またはドラッグ&ドロップ、同一階層制約、無効操作の表示）
- サブタスク階層を壊さないための実装方針
- 追加/変更したi18nキー
- 追加/更新したテスト（domain unit、Dart/FRB統合、widget）
- 品質ゲート6点と `check_hardcoded_strings.sh` の実行結果
- FRB生成物が手編集されていないことの確認
- やらなかったことが守られていること（Undo、条件ソートUI、リスト並び替え、別親/別リスト移動、階層変更、新規依存追加なし）
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
- `core/domain/src/entities.rs`
- `core/domain/src/usecases.rs`
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/rust/src/api.rs`
- `flutter_rust_bridge.yaml`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/core_usecases_test.dart`
- `app/test/widget_test.dart`
- `app/tool/check_hardcoded_strings.sh`

### M3-05のうち実装した範囲

- 実装した範囲は、M3-05のうち `fractional index生成` と `タスク一覧の同一階層内の手動並び替えUI` に限定した。
- Undoは履歴データ構造と復元時の競合方針が別途必要なため実装していない。
- 条件ソートUIは、手動順と締切/優先度/作成順の切替状態・ユーザー設定の保存方針が別途必要なため実装していない。
- リスト並び替えは `listsProvider` とリスト一覧UIの別スコープになるため実装していない。

### fractional index生成ロジック

- `core/domain/src/sort_order.rs` を追加し、`fractional_index_between(previous, next)` と `fractional_index_after(last)` を公開した。
- 文字集合は ASCII の `0-9A-Za-z`。Rust `String`、Dart `String.compareTo`、SQLite `TEXT` の通常昇順比較で同じ順序になる前提で生成する。
- `previous` / `next` は省略可能で、先頭、末尾、2値の間を決定的に生成する。浮動小数点、時刻、乱数は使っていない。
- 既存境界は空文字と文字集合外を `InvalidSortOrder`、`previous >= next` を `InvalidSortOrderBoundary` として拒否する。表現空間がない境界は `SortOrderSpaceExhausted` として扱う。
- unit testで初期値、先頭、末尾、2値間、連続挿入、不正値、不正境界を検証した。

### 新規task作成時のsort_order生成方針

- Rust bridgeの `create_task` から `sort_order` 引数を削除し、Rust/domain側で生成する形に変更した。
- root taskは `parent_task_id == None` のactive兄弟内で最後尾に入る値を生成する。
- subtaskは同じ `parent_task_id` を持つactive兄弟内で最後尾に入る値を生成する。
- Flutter側の `TasksNotifier.createTask()` はタスク用 `nextSortOrder()` に依存しない。`nextSortOrder()` はリスト作成用の暫定ヘルパーとしてのみ残した。

### 追加/変更したRust bridge API

- `create_task(list_id, title, parent_task_id)`:
  - タスク用 `sort_order` は引数で受け取らず、同一階層の兄弟末尾として生成する。
  - 既存の親検証は維持し、候補親がactive一覧にない場合は `TaskRepository::get` で削除済み親も検証対象に含める。
- `reorder_task(task_id, previous_task_id, next_task_id)`:
  - 対象task、前後境界taskがactiveであることを確認する。
  - 前後境界taskは対象taskと同じ `list_id` かつ同じ `parent_task_id` の場合だけ許可する。
  - 対象自身を境界にする指定、同じ境界IDの重複、別リスト、別親、削除済みtaskはエラーにする。
  - 生成した `sort_order` と `updated_at` を `TaskRepository::update` で永続化する。

### FRB再生成

- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、成功した。
- 初回はFlutter SDK cacheへの書き込みがサンドボックスで拒否されたため、承認付きで同コマンドを再実行して成功した。
- `app/rust/src/frb_generated.rs` と `app/lib/src/rust/` 配下は生成コマンドで更新し、手編集していない。

### Dart provider / service / fake

- `BridgeService` / `FrbBridgeService` からタスク作成時の `sortOrder` 引数を削除した。
- `BridgeService` / `FrbBridgeService` に `reorderTask` を追加した。
- `TasksNotifier.createTask()` はRust/domain生成に任せ、成功後に `ref.invalidateSelf()` で再取得する。
- `TasksNotifier.reorderTask()` を追加し、並び替え成功後に `ref.invalidateSelf()` で該当listのtask一覧を再取得する。
- `FakeBridgeService` はテスト用に同じ文字集合の決定的fractional index生成と `reorderTask` 境界検証を持つよう更新した。

### 手動並び替えUI

- `TasksScreen` の各行に上/下移動のicon buttonを追加した。
- 上/下移動は、同じ `parentTaskId` を持つ兄弟配列だけを対象に、移動後の `previousTaskId` / `nextTaskId` 境界を計算して `TasksNotifier.reorderTask()` を呼ぶ。
- 先頭行の上移動、末尾行の下移動はdisabled状態にした。
- icon-only controlには `moveTaskUpTooltip` / `moveTaskDownTooltip` を設定した。
- `AppTaskRow` は任意の `trailing` を受け取れるようにし、既定では従来どおりchevronを表示する。

### サブタスク階層を壊さないための方針

- UI側では `parentTaskId` が同じ兄弟だけを移動候補にする。
- Rust bridge側でも境界taskの `list_id` と `parent_task_id` が対象taskと一致しない場合は拒否する。
- 並び替えでは `parent_task_id`、`list_id`、階層深度を変更しない。更新対象は `sort_order` と `updated_at` のみ。

### i18nキー

- `moveTaskUpTooltip`
- `moveTaskDownTooltip`

`app/lib/l10n/app_en.arb` / `app_ja.arb` を更新し、`flutter gen-l10n` で `app/lib/src/generated/l10n/*` を更新した。初回はFlutter SDK cache制約で失敗したため、承認付きで再実行して成功した。

### 追加/更新したテスト

- `core/domain` unit test:
  - 初期値、先頭生成、末尾生成、2値間生成、連続挿入、不正値、不正境界を追加。
- `app/test/core_usecases_test.dart`:
  - タスク作成時のroot/subtask兄弟ごとの生成順を検証。
  - `reorderTask` 後の `getTasks(listId)` が新しい順序を返すことを検証。
  - 対象自身、別リスト、別親、削除済み境界、削除済み対象の並び替え拒否を検証。
- `app/test/widget_test.dart`:
  - 上/下移動UIでroot taskの表示順とFakeBridgeService状態が変わることを検証。
  - subtaskの上移動で同じ親と階層表示が維持されることを検証。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（Rust 70 tests）。
- `cd app && flutter analyze`: 初回はFlutter SDK cache書き込みがサンドボックスで拒否されたため、承認付きで再実行して成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test`: 初回はFlutter SDK cache書き込みがサンドボックスで拒否されたため、承認付きで再実行して成功（Flutter 27 tests）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git diff --check`: 成功。

### やらなかったこと

- Undo、条件ソートUI、リスト並び替え、別親/別リスト移動、階層変更は実装していない。
- permanent delete、通知、検索、タグ、アプリロックは実装していない。
- 新規Rust crate / pub package / UI frameworkは追加していない。
- DB schema migrationは行っていない。既存 `sort_order TEXT NOT NULL` を使った。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。

### public/private境界

- `taskveil-private/` は読まず、変更していない。
- public repoへprivate側の課金、収益、法務、監査、公開前ロードマップ等の詳細は転記していない。

### 未解決事項・要人間判断

- なし。
