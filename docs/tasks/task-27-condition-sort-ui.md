# task-27: 条件ソートUI

> ステータス: 完了（条件ソートUI実装済み）
> 作業日: 2026-07-05

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` の M3-05 は「Undoと手動/条件並び替えを実装する」であり、完了条件に「削除/完了/編集のUndo」と「手動/締切/優先度/作成順ソート」を含めている。

task-24では、M3-05のうちfractional index生成とタスク一覧の同一階層内手動並び替えUIを実装済みである。task-26では、削除/完了/編集のUndoを実装済みである。したがって、M3-05の主な残りは **手動順 / 締切 / 優先度 / 作成順の条件ソートUI** である。

このタスクでは、永続順である `sort_order` を変更せず、FlutterのTasks画面で表示順を切り替える最小UIを追加する。Phase 1の最小実装として、切替状態はアプリ起動中のRiverpod provider状態に限定し、DB保存、永続設定画面、Rust/FRB/schema変更へ広げない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` M3-05
- `docs/tasks/task-24-fractional-index.md`
- `docs/tasks/task-25-design-calibration-ui-pass.md`
- `docs/tasks/task-26-undo.md`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/tool/check_hardcoded_strings.sh`

必要に応じて、現在の実装で参照されている `app/lib/src/generated/l10n/` の生成結果も確認する。ただし生成物は手編集しない。

## 3. ゴール

Tasks画面に小さな表示順切替controlを追加し、ユーザーが手動順、締切順、優先度順、作成順を切り替えられるようにする。

- 既定表示は手動順（`sort_order`）にする。
- 条件ソート時は `sort_order` を書き換えず、表示順だけを切り替える。
- 切替状態はPhase 1最小としてアプリ起動中のprovider状態に保持する。
- サブタスクを含む親子階層を壊さず、同一親の兄弟内だけを選択中の条件で並べる。
- 手動並び替えボタンは手動順モードのときだけ使える、または表示されるようにする。
- 追加UI文字列はen/ja ARBへ追加し、生成済みlocalizationsを更新する。
- widget testで各ソート条件、階層保持、手動並び替えUIの出し分けを検証する。

## 4. スコープ

### 想定変更ファイル

後続workerは、実装に必要な場合に限り、以下を中心に変更する。実際の差分は受け入れ基準を満たす最小範囲に留める。

- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/screens/tasks_screen.dart`
- 必要な場合のみ `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/` 配下のl10n生成物
- `app/test/widget_test.dart`
- 必要な場合のみ `app/test/l10n_test.dart`
- `docs/tasks/task-27-condition-sort-ui.md`（実装完了時の `## 9. 完了報告` 追記のみ）

### やること

1. **表示順modeの定義**:
   - 手動順、締切順、優先度順、作成順を表す小さなenumまたは同等の型をFlutter側に追加する。
   - 既定値は手動順にする。
   - providerはRiverpod 3.xの既存方針に合わせる。Phase 1ではアプリ起動中のprovider状態だけに保持し、DBや設定ファイルへ保存しない。
2. **ソート条件の仕様**:
   - 手動順: 既存の `sort_order ASC` を基準にする。tie breakerが必要な場合は `createdAt DESC`、さらに必要なら `id ASC` で安定化する。
   - 締切順: `dueAt` があるtaskを早い順に並べ、`dueAt == null` は最後に置く。`dueAt` が同じ場合は `sort_order ASC`、さらに必要なら `createdAt DESC` / `id ASC` で安定化する。
   - 優先度順: `priority` が高いtaskを先に並べる。priority値の大小関係は既存実装の表現を確認し、後続workerは「高 -> 低」の対応を完了報告に明記する。同じpriorityの場合は `sort_order ASC`、さらに必要なら `createdAt DESC` / `id ASC` で安定化する。
   - 作成順: Phase 1では **新しい順** に固定する。`createdAt DESC` を基準にし、同じ場合は `sort_order ASC`、さらに必要なら `id ASC` で安定化する。
3. **親子階層を壊さない表示順適用**:
   - task一覧全体を単純にflattenして並べ替えない。
   - root task同士、同一 `parent_task_id` を持つsubtask同士を、それぞれ選択中の条件で並べる。
   - 親子関係、階層深度、subtask表示位置は維持する。
   - 条件ソート時も、subtaskは同一親の兄弟内で同じ条件により並べる。
4. **Tasks画面の小さな切替control**:
   - `TasksScreen` の既存toolbar/header付近に、小さな表示順切替controlを追加する。
   - controlは `SegmentedButton`、`DropdownMenu`、popup menuなど、既存画面密度を壊さない形を選ぶ。
   - 新しい設定画面、永続設定、global preferencesは追加しない。
   - icon-only controlを使う場合はtooltip/semanticsを付ける。
   - task-25の較正方針に従い、長い日本語/英語文言、狭い画面、Dynamic Typeで破綻しないようにする。
5. **手動並び替えUIとの連動**:
   - task-24で追加された上/下移動などの手動並び替えcontrolは、手動順モードのときだけ使える、または表示されるようにする。
   - 締切順、優先度順、作成順では手動並び替え操作を実行できないようにする。
   - 条件ソート中に手動並び替えAPIを呼ばない。
6. **i18n**:
   - 表示順切替、各sort label、必要なtooltip/semanticsは `app/lib/l10n/app_en.arb` と `app_ja.arb` に追加する。
   - ARBを変更したら `cd app && flutter gen-l10n` を実行し、生成済みlocalizationsを更新する。
   - `sh app/tool/check_hardcoded_strings.sh` を通す。
7. **テスト**:
   - `app/test/widget_test.dart` に、手動順、締切順、優先度順、作成順の表示順を検証するwidget testを追加または更新する。
   - `dueAt == null` が締切順で最後に置かれることを検証する。
   - priorityが高いtaskから低いtaskへ並ぶことと、tie breakerが安定していることを検証する。
   - 作成順が新しい順であることを検証する。
   - サブタスクが同一親の兄弟内で条件ソートされ、親子階層が壊れないことを検証する。
   - 条件ソート時に手動並び替えbuttonが表示されない、または無効であり、手動順モードでは使えることを検証する。

### やらないこと

- Rust API、FRB定義/生成物、DB schema、domain usecase、storage repositoryは原則変更しない。
- 条件ソート時に `sort_order` を書き換えない。
- 条件ソート状態をDB、ローカル設定、shared preferences、settings画面へ永続化しない。
- リスト一覧の並び替え、リスト用条件ソート、別リスト移動、別親への移動、階層変更、インデント/アウトデントは実装しない。
- 条件ソート中の手動並び替え、手動並び替えUndo、複数条件のカスタムソート、昇順/降順のユーザー切替は実装しない。
- 検索、通知、Keychain、オンボーディング、タイマー、タグ、設定画面、同期、アカウント、課金、サーバー連携は実装しない。
- 新規Rust crate / pub package / UI frameworkは原則追加しない。どうしても必要な場合は、人間の事前承認を得て、理由・代替案・追加versionを完了報告へ記録する。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `taskveil-private/` 配下を読んだり変更したりしない。private側の課金、収益、法務、監査、公開前ロードマップ詳細をpublic repoへ転記しない。
- `.github/` 配下を変更しない。

## 5. 実装手順（例）

1. `git -C taskveil status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、既存の `tasksProvider`、`task_tree.dart`、Tasks画面、task-24の手動並び替えUI、task-25のUI較正方針、task-26後のUndo action表示を把握する。
3. Flutter側に表示順modeの型とproviderを追加する。既定値は手動順にする。
4. 既存のtask tree構築処理に沿って、同一親の兄弟ごとに選択中のsort modeを適用する。
5. 締切、優先度、作成順の比較関数を実装し、null dueAt、priority tie、createdAt tieの扱いを明確にする。
6. `TasksScreen` に小さな表示順切替controlを追加する。
7. 手動並び替えcontrolを、手動順モードのときだけ使える、または表示する形へ調整する。
8. ARBへ文字列を追加し、`cd app && flutter gen-l10n` を実行する。
9. widget testを追加/更新し、各sort mode、階層保持、手動並び替えUIの出し分けを検証する。
10. 品質ゲートを実行する。
11. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] Tasks画面に、手動順 / 締切 / 優先度 / 作成順を切り替える小さなcontrolが追加されている。
- [ ] 既定表示は手動順（`sort_order`）である。
- [ ] 切替状態はアプリ起動中のprovider状態に限定され、DB、設定画面、永続設定へ保存されていない。
- [ ] 手動順は `sort_order ASC` を基準にし、必要なtie breakerが実装または完了報告に明記されている。
- [ ] 締切順は `dueAt` が早いtaskから並び、`dueAt == null` は最後に置かれる。
- [ ] 締切順で `dueAt` が同じ場合のtie breakerが実装され、完了報告に明記されている。
- [ ] 優先度順はpriority高 -> 低で並び、既存priority値と高低の対応が完了報告に明記されている。
- [ ] 優先度順でpriorityが同じ場合のtie breakerが実装され、完了報告に明記されている。
- [ ] 作成順はPhase 1最小として新しい順（`createdAt DESC`）に固定されている。
- [ ] 作成順で `createdAt` が同じ場合のtie breakerが実装され、完了報告に明記されている。
- [ ] 条件ソート時に `sort_order` が書き換えられない。
- [ ] task一覧全体をflattenした条件ソートになっておらず、親子階層と階層深度が維持されている。
- [ ] root task同士、同一親のsubtask同士が、それぞれ選択中の条件で並ぶ。
- [ ] subtaskは同一親の兄弟内で同じ条件により並ぶ。
- [ ] 手動並び替えbuttonは手動順モードのときだけ使える、または表示される。
- [ ] 締切順、優先度順、作成順では手動並び替えAPIが呼ばれない。
- [ ] 追加UI文字列がen/ja ARB化されている。
- [ ] `cd app && flutter gen-l10n` が実行され、生成済みlocalizationsが更新されている。
- [ ] widget testで、手動順、締切順（null最後）、優先度順（高 -> 低）、作成順（新しい順）の表示順を検証している。
- [ ] widget testで、サブタスク階層が壊れず、同一親の兄弟内だけが条件ソートされることを検証している。
- [ ] widget testで、手動順モードと条件ソートモードにおける手動並び替えbuttonの出し分け、または有効/無効を検証している。
- [ ] 長い日本語/英語文言、狭い画面、Dynamic Typeで表示順切替controlとタスク行が不自然に重ならない。
- [ ] icon-only controlにはtooltip/semanticsがある。
- [ ] Rust API、FRB定義/生成物、DB schema、domain usecase、storage repositoryに不要な変更が入っていない。
- [ ] Rust/DB/FRB/schema変更が必要になった場合は、理由、代替案、変更範囲、実行した追加検証が完了報告に明記されている。
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [ ] `taskveil-private/` と `.github/` が変更されていない。
- [ ] public repoにprivate詳細が転記されていない。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `git diff --check` が成功している。
- [ ] 変更ファイルは4章「想定変更ファイル」を中心とする最小範囲に収まり、スコープ外ファイルを変更していない。
- [ ] `docs/tasks/task-27-condition-sort-ui.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクはM3-05の残りである条件ソートUIだけを扱う。
- task-24で実装済みのfractional index / 手動並び替えを前提にし、`sort_order` の生成・永続化・手動並び替えAPIを作り直さない。
- task-26で実装済みのUndoを前提にし、Undo履歴やSnackBar actionの仕組みを作り直さない。
- 条件ソートは表示順の切替であり、永続順の変更ではない。手動順に戻したときは、既存の `sort_order` による順序が見えること。
- Phase 1では、sort modeの永続化をしない。アプリ再起動後に既定の手動順へ戻ることは許容する。
- UIはTasks画面内の小さなcontrolに留める。設定画面、preferences、複雑なsort builderは追加しない。
- `dueAt == null` の扱い、priority高低、createdAtの方向は、実装とテストと完了報告で一致させる。
- UI文字列は必ずARB化する。`Text('...')`、`Tooltip(message: '...')` などの直書きを残さない。
- `flutter_rust_bridge` は `2.12.0` 固定であり、Rust側crateとDart側pubのバージョン一致を崩さない。
- 秘密情報、Device Key、SQLCipher鍵、DB鍵をログやDebug出力に含めない。
- `docs/01〜03` は変更禁止である。仕様と実装の矛盾を見つけた場合は、仕様書を書き換えず完了報告の未解決事項に記録する。
- public repoにprivate repoの課金、収益、法務、監査、公開前ロードマップ詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- M3-05のうち実装した範囲と、Rust/DB/FRB/schema変更を避けた理由
- 追加した表示順modeの型/providerと、状態保存方針
- Tasks画面に追加した切替controlの仕様
- 手動順、締切順、優先度順、作成順それぞれの比較仕様
- `dueAt == null` の扱い
- priority値と高低の対応
- 作成順を新しい順に固定したこと
- 各条件のtie breaker
- 親子階層を壊さないための実装方針
- 条件ソート時に `sort_order` を書き換えていないことの確認
- 手動並び替えbuttonを手動順モードだけに限定した方法
- 追加/変更したi18nキー
- `flutter gen-l10n` の実行結果
- 追加/更新したwidget test
- `flutter analyze`、`flutter test`、`check_hardcoded_strings.sh`、`git diff --check` の実行結果
- Rust/DB/FRB/schemaを変更していないことの確認。変更した場合は、理由、代替案、変更範囲、追加検証
- やらなかったことが守られていること（永続設定なし、DB保存なし、設定画面なし、リストソートなし、階層変更なし、新規依存なし）
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` を変更していないこと
- `taskveil-private/` と `.github/` を変更していないこと
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
- `docs/tasks/task-24-fractional-index.md`
- `docs/tasks/task-25-design-calibration-ui-pass.md`
- `docs/tasks/task-26-undo.md`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/` 配下の既存生成物
- `app/test/widget_test.dart`
- `app/test/l10n_test.dart`
- `app/tool/check_hardcoded_strings.sh`

### M3-05のうち実装した範囲

- 実装した範囲は、M3-05のうち `Tasks画面の手動順 / 締切順 / 優先度順 / 作成順の表示順切替UI` に限定した。
- Rust/DB/FRB/schemaは変更していない。条件ソートは表示順のみの切替であり、永続順 `sort_order` の生成・保存・並び替えAPIを変更する必要がなかったため。
- Undo、手動並び替えUndo、リストソート、設定画面、永続設定、DB保存、新規依存追加は実装していない。

### 表示順modeと状態保存方針

- `app/lib/src/core/task_tree.dart` に `TaskSortMode` enumを追加した。
  - `manual`
  - `dueDate`
  - `priority`
  - `createdAt`
- `app/lib/src/core/providers.dart` に `taskSortModeProvider` を追加した。
- providerは `NotifierProvider.family` で、listごとの選択状態をアプリ起動中のRiverpod provider状態だけに保持する。
- DB、shared preferences、設定画面、Rust側状態への保存は行っていない。
- 既定値は `TaskSortMode.manual`。

### Tasks画面の切替control

- `TasksScreen` のAppBar actionsに `PopupMenuButton<TaskSortMode>` を追加した。
- icon-onlyの小さなcontrolとし、tooltipは `taskSortTooltip` でARB化した。
- popup itemには手動順、締切順、優先度順、作成順を表示し、現在選択中の項目にはcheck iconを表示する。
- 狭い画面で行本体と重ならないよう、既存のAppBar action内に収めた。

### 比較仕様

- 手動順:
  - `sortOrder ASC`
  - tie breaker: `createdAt DESC`
  - さらに同値の場合: `id ASC`
- 締切順:
  - `dueAt` があるtaskを `dueAt ASC`
  - `dueAt == null` は最後
  - tie breaker: 手動順と同じ `sortOrder ASC` -> `createdAt DESC` -> `id ASC`
- 優先度順:
  - priority値の高い順。既存UIでは `3 = High / 高`, `2 = Medium / 中`, `1 = Low / 低`, `0 = None / なし`。
  - tie breaker: 手動順と同じ `sortOrder ASC` -> `createdAt DESC` -> `id ASC`
- 作成順:
  - Phase 1最小として `createdAt DESC` の新しい順に固定
  - tie breaker: `sortOrder ASC` -> `id ASC`

### 親子階層とsort_order

- `buildTaskTree(tasks, sortMode: ...)` がroot同士と同一親のchildren listだけを選択中の条件でsortする。
- `flattenTaskTree` 前に親子treeを組むため、task一覧全体を単純flattenして条件ソートしていない。
- subtaskは親の直下に残り、同一 `parentTaskId` を持つ兄弟内だけで条件ソートされる。
- 条件ソート時に `sort_order` は書き換えていない。`reorderTask` APIも呼び出していない。

### 手動並び替えbutton

- `TasksScreen` では `TaskSortMode.manual` のときだけ `_TaskReorderControls` を `AppTaskRow.trailing` に渡す。
- 締切順、優先度順、作成順では上/下移動buttonを表示しないため、手動並び替え操作と `reorderTask` API呼び出しは発生しない。

### i18n

- `app/lib/l10n/app_en.arb` / `app_ja.arb` に以下のキーを追加した。
  - `taskSortTooltip`
  - `taskSortManual`
  - `taskSortDueDate`
  - `taskSortPriority`
  - `taskSortCreatedAt`
- `flutter gen-l10n` を実行し、`app/lib/src/generated/l10n/` 配下を更新した。
- 初回はFlutter SDK cacheへの書き込みがsandboxで拒否されたが、承認付き再実行で成功した。

### 追加/更新したテスト

- `app/test/widget_test.dart`
  - 手動順が既定であることを表示順で検証。
  - 締切順で `dueAt == null` が最後になることを検証。
  - 優先度順で `3 > 2 > 1`、同priorityのtie breakerが手動順になることを検証。
  - 作成順が新しい順になることを検証。
  - 条件ソート時に手動並び替えbuttonが表示されず、手動順へ戻すと表示されることを検証。
  - subtaskが親の直下に残り、同一親の兄弟内だけで締切順に並ぶことを検証。
- `app/test/l10n_test.dart`
  - 追加したsort系l10nキーのen/ja読み込みを検証。

### 検証結果

- `cd app && flutter gen-l10n`
  - 初回: Flutter SDK cache書き込みがsandboxで拒否。
  - 承認付き再実行: 成功。
- `cd app && dart format lib/src/core/providers.dart lib/src/core/task_tree.dart lib/src/screens/tasks_screen.dart test/widget_test.dart test/l10n_test.dart`
  - 成功。
- `cd app && flutter analyze`
  - 初回: Flutter SDK cache書き込みがsandboxで拒否。
  - 承認付き再実行: 成功。`No issues found!`
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`
  - 成功。Rust/DB/FRB/schemaは未変更だが、指示に従いrelease buildを実行した。
- `cd app && flutter test`
  - 初回: Flutter SDK cache書き込みがsandboxで拒否。
  - 承認付き再実行: 成功。`All tests passed!`
- `cd taskveil && sh app/tool/check_hardcoded_strings.sh`
  - 成功。
- `git -C taskveil diff --check`
  - 成功。

### スコープ確認

- Rust API、FRB定義/生成物、DB schema、domain usecase、storage repositoryは変更していない。
- 条件ソート状態をDB、ローカル設定、shared preferences、settings画面へ永続化していない。
- 条件ソート時に `sort_order` を書き換えていない。
- リスト一覧のソート、リスト用条件ソート、別リスト移動、別親への移動、階層変更、インデント/アウトデントは実装していない。
- 新規Rust crate / pub package / UI frameworkは追加していない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。
- `taskveil-private/` と `.github/` は読んでおらず、変更していない。
- public repoにprivate詳細は転記していない。

### 未解決事項・要人間判断

- なし。
