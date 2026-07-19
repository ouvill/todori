# task-20: UI基盤整備

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` のM3では、タスクCRUD、サブタスク、ゴミ箱・復元、Undo、並び替えを順に実装してMVPのタスク操作を完成させる。task-18でタスク詳細編集、task-19でサブタスク表示・作成・進捗・親完了確認が追加され、画面上の情報量と操作導線が増えた。

一方、現在のFlutter UIはtask-09のskeletonを起点に機能を足してきた状態であり、リスト行、詳細画面、空状態、確認ダイアログ、色、typography、spacing、状態表示の文法がまだ画面ごとに散らばっている。ゴミ箱画面・復元UI、並び替え、通知へ進む前に、今後のM3/M4画面追加で迷わないための小さなUI foundationを整える。

このタスクは大規模リデザインやブランド完成ではない。Flutter標準とMaterialを前提に、既存画面を壊さず、共通化してよい最小単位だけを整理する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/02_機能仕様書.md` F-02 / F-05 / F-06 / F-07 / F-48 / F-49
- `docs/07_Phase1計画書.md` M2-03 / M2-04 / M3-02 / M3-03 / M3-04 / M3-05 / M4-03
- `docs/tasks/task-09-ui-skeleton.md`
- `docs/tasks/task-10-i18n.md`
- `docs/tasks/task-18-task-editing-ui.md`
- `docs/tasks/task-19-subtasks-ui.md`
- `app/lib/main.dart`
- `app/lib/src/router.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/l10n_test.dart`
- `app/tool/check_hardcoded_strings.sh`

## 3. ゴール

task-18/19後の既存UIを小さく整え、後続のゴミ箱画面・復元UI・並び替え・通知UIが同じ文法で追加できる状態にする。

- `ThemeData`、色、typography、spacingの扱いを軽く整理する。
- タスク行、ステータス/priority/due date/進捗などのmetadata表示を共通部品化する。
- Lists / Tasks / TaskDetail の既存表示を、共通部品とMaterial標準の見た目に揃える。
- 空状態、loading/error表示、確認/入力ダイアログの文法を統一する。
- i18nとアクセシビリティ最低基準を維持する。
- 既存widget testを中心に、画面遷移・主要表示・ダイアログが壊れていないことを確認する。

## 4. スコープ

### やること

1. **ThemeDataの軽い整理**:
   - `app/lib/main.dart` または小さなthemeファイルを追加し、`MaterialApp` / `MaterialApp.router` へ適用する `ThemeData` を整理する。
   - Material 3を前提に、`ColorScheme.fromSeed` などFlutter標準の仕組みを使う。
   - primary / surface / error / outline / muted text相当の使い方を、既存Material色と `ColorScheme` の範囲で整理する。
   - headline / title / body / label の使い分けを、既存 `textTheme` をベースに必要最小限で整える。
   - spacingは新規パッケージや巨大なdesign token体系ではなく、`const` 値または小さなローカル定数として、8px単位を目安に使い回せる形にする。
2. **共通UI部品の追加**:
   - `app/lib/src/ui/` など既存構成に馴染む場所へ、以下のような小さな共通部品を追加する。
   - タスク行: title、checkbox/status、サブタスクindent、metadata、chevronを一貫して表示する部品。
   - metadata表示: priority、due date、status、subtask progressを必要に応じて横並びまたは折り返しで表示する部品。
   - empty state: Lists / Tasks / Subtasks / 将来のTrashで使える、icon + title + optional body/action程度の部品。
   - loading/error state: 既存の `CircularProgressIndicator` とerror textを画面ごとに揃える部品またはヘルパー。
   - confirm/input dialog: 既存のタスク作成、編集、親完了確認で使う文法を揃える小さな部品または関数。
   - 部品化は画面を読みやすくする範囲に留め、抽象化しすぎない。
3. **既存画面の見た目整理**:
   - `ListsScreen`、`TasksScreen`、`TaskDetailScreen` を共通部品へ寄せる。
   - task-18/19で追加した編集、サブタスク作成、進捗表示、親完了確認の導線を維持する。
   - タスク行は、トップレベル/サブタスク、done/todo、priority/due date、進捗の表示が同じルールで読めるようにする。
   - 詳細画面は、タイトル、note、metadata、サブタスクセクション、操作ボタンの間隔と情報階層を整える。
   - 空リスト/空タスク/空サブタスクの表示を同じ文法に揃える。
4. **i18n維持**:
   - 追加・変更するUI文字列は `app/lib/l10n/app_en.arb` と `app_ja.arb` に追加する。
   - 既存文言を再利用できる場合は新しいキーを増やしすぎない。
   - `cd app && flutter gen-l10n` を実行し、生成済みlocalizationsを更新する。
   - `sh app/tool/check_hardcoded_strings.sh` を通す。
5. **アクセシビリティ最低限の確認**:
   - icon-only buttonにはtooltipまたはsemantic labelを維持する。
   - checkbox、行tap、主要actionがwidget testで探しやすいkey/semanticsを失わないようにする。
   - Dynamic Typeで破綻しにくいよう、固定heightでテキストを潰さず、metadataは折り返しまたは縦積みを許容する。
   - 色だけに依存して状態を伝えず、status textやiconも併用する。
6. **テスト**:
   - 既存の `app/test/widget_test.dart` を中心に更新する。
   - 画面遷移、タスク作成、編集、サブタスク表示/作成、親完了確認ダイアログの既存期待を維持する。
   - 新しい共通部品は、画面テストから自然に検証できる範囲でよい。必要な場合のみ小さなwidget testを追加する。
   - golden testやスクリーンショット比較は必須にしない。

### やらないこと

- 新規デザインシステムパッケージ、UIフレームワーク、icon packageを追加しない。
- 大規模なブランド刷新、ロゴ、独自イラスト、アニメーション、複雑なモーション設計は行わない。
- 画面構成やルーティングの全面作り直しは行わない。
- Riverpod、go_router、FRB、Rust API、DB schema、domain usecaseを変更しない。
- ゴミ箱画面・復元UIは実装しない。
- Undoは実装しない。
- fractional index本実装、ドラッグ&ドロップ並び替え、手動/条件ソートUIは実装しない。
- ローカル通知、スヌーズ、予定時刻通知登録は実装しない。
- タグ、検索UI、高機能UIモード、設定画面は実装しない。
- widget/goldenの新規大規模整備や画像スナップショット基盤の導入は行わない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `taskveil-private/` 配下を読んだり変更したりしない。private側の詳細をpublic repoへ転記しない。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、既存の画面構成、i18n、widget testの期待を把握する。
3. 現在のLists / Tasks / TaskDetailで重複している表示文法を洗い出す。
4. `ThemeData` とspacing/color/typographyの最小方針を決める。
5. `app/lib/src/ui/` などに小さな共通部品を追加する。
6. `ListsScreen`、`TasksScreen`、`TaskDetailScreen` を共通部品へ段階的に差し替える。
7. 追加・変更UI文字列をARBへ反映し、`flutter gen-l10n` を実行する。
8. 既存widget testを更新し、必要なら共通部品の小さなwidget testを追加する。
9. 品質ゲートを実行する。
10. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] Flutter標準/Materialを前提にした `ThemeData` の軽い整理が行われている。
- [ ] 新規デザインシステムパッケージや大規模テーマ刷新が導入されていない。
- [ ] spacing、色、typographyの使い方が、後続画面で再利用できる小さな形に整理されている。
- [ ] タスク行の共通部品または同等の共通化により、Tasks画面とサブタスク表示でtitle/status/metadata/indent/chevronの文法が揃っている。
- [ ] status、priority、due date、subtask progressなどのmetadata表示が共通化または明確に整理されている。
- [ ] Lists / Tasks / TaskDetail の既存導線が維持されている。
- [ ] タスク作成、編集、サブタスク作成、親完了確認ダイアログの文法が統一されている。
- [ ] 空リスト、空タスク、空サブタスクの表示が同じ文法に揃っている。
- [ ] loading/error状態が画面ごとに不必要にばらつかない。
- [ ] 追加・変更UI文字列がen/ja ARB化されている。
- [ ] icon-only buttonのtooltip/semanticsが維持されている。
- [ ] 色だけで状態を伝えず、text/icon/semanticsでも状態が分かる。
- [ ] 既存widget testが更新され、タスク作成、編集、サブタスク表示/作成、親完了確認が引き続き検証されている。
- [ ] golden testや新規スクリーンショット比較基盤を必須化していない。
- [ ] Rust API、FRB生成物、DB schema、domain usecaseに不要な変更が入っていない。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `docs/tasks/task-20-ui-foundation.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクはUI foundationであり、機能追加タスクではない。後続のゴミ箱画面・復元UI・Undo・並び替え・通知を先取りしない。
- 既存のtask-18/19で実装済みの編集・サブタスク機能を壊さない。
- 画面の見た目を整える場合も、i18n、widget test、直書き検出を必ず維持する。
- 共通部品は小さく保つ。将来必要かもしれない汎用抽象を先に作らない。
- Flutter標準Materialで足りる範囲に留める。新規pub依存は原則追加しない。
- 既存の `app/lib/src/core/task_tree.dart` の責務をUI部品へ混ぜ込まない。親子関係や進捗計算の純粋ロジックは既存ヘルパーを優先する。
- 秘密情報、Device Key、DB鍵、SQLCipher鍵をログやDebug出力に含めない。
- `docs/01〜03` は変更禁止である。仕様と実装の矛盾を見つけた場合は、仕様書を書き換えず完了報告の未解決事項に記録する。
- public repoにprivate repoの詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- 追加/変更したUI foundationファイル
- `ThemeData` / color / typography / spacingの整理内容
- 追加/変更した共通UI部品
- Lists / Tasks / TaskDetail の見た目整理内容
- 空状態、loading/error、ダイアログの統一方針
- status / priority / due date / subtask progress表示の方針
- i18nキーの追加/変更内容
- アクセシビリティ上維持・改善した点
- 追加/更新したテスト
- 品質ゲート6点と `check_hardcoded_strings.sh` の実行結果
- やらなかったことが守られていること（新規依存なし、Rust/FRB/DB/domain変更なし、ゴミ箱/Undo/並び替え/通知未実装）
- 未解決事項・要人間判断

## 9. 完了報告

- 作業日: 2026-07-04
- 読んだファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/PLAYBOOK.md`
  - `docs/tasks/BACKLOG.md`
  - `docs/02_機能仕様書.md` F-02 / F-05 / F-06 / F-07 / F-48 / F-49
  - `docs/07_Phase1計画書.md` M2-03 / M2-04 / M3-02 / M3-03 / M3-04 / M3-05 / M4-03
  - `docs/tasks/task-09-ui-skeleton.md`
  - `docs/tasks/task-10-i18n.md`
  - `docs/tasks/task-18-task-editing-ui.md`
  - `docs/tasks/task-19-subtasks-ui.md`
  - `app/lib/main.dart`
  - `app/lib/src/router.dart`
  - `app/lib/src/screens/lists_screen.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/screens/task_detail_screen.dart`
  - `app/lib/src/core/providers.dart`
  - `app/lib/src/core/task_tree.dart`
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/test/widget_test.dart`
  - `app/test/l10n_test.dart`
  - `app/tool/check_hardcoded_strings.sh`

### 実装結果

- `app/lib/src/ui/theme.dart` を追加し、Material 3 / `ColorScheme.fromSeed` ベースのlight/dark `ThemeData` と8px単位の `AppSpacing` を定義した。
- `app/lib/main.dart` の `TaskveilApp.build` で通常起動時・初期化失敗時の両方に共通themeを適用した。`RustLib.init()` / `initCore()` / DB初期化処理は変更していない。
- `app/lib/src/ui/states.dart` を追加し、loading / error / empty state の表示文法を共通化した。
- `app/lib/src/ui/dialogs.dart` を追加し、list/task/subtask作成の入力ダイアログと親完了確認ダイアログを共通化した。
- `app/lib/src/ui/task_components.dart` を追加し、`AppTaskRow` / `TaskMetadata` / metadata label helperを実装した。`TaskRow` 相当部品は `ValueKey('task-row-${task.id}')`、`ValueKey('task-done-${task.id}')`、`ValueKey('subtask-row-${subtask.id}')` を維持している。
- `ListsScreen` / `TasksScreen` / `TaskDetailScreen` を共通theme、state、dialog、task row/metadataへ寄せた。
- `app/tool/check_hardcoded_strings.sh` の検出対象に `app/lib/src/ui/` を追加した。

### ThemeData / color / typography / spacing

- seed colorはエメラルド系 `0xFF10B981` とし、Flutter標準の `ColorScheme.fromSeed` からlight/dark themeを生成した。
- surface / outline / error / muted text相当は `ColorScheme` の `surface`、`surfaceContainerHighest`、`outlineVariant`、`error`、`onSurfaceVariant` を使う方針にした。
- typographyは既存 `textTheme` をベースに、AppBar title / headlineSmall / titleMedium / labelMedium のweightを最小限だけ調整した。
- spacingは `AppSpacing.xs/sm/md/lg/xl` に集約し、既存画面の余白を8px単位へ寄せた。

### 共通UI部品

- `AppTaskRow`: title、done checkbox/status icon、indent、metadata、chevron、tap導線を一貫表示する。
- `TaskMetadata`: status / priority / due date / subtask progress をicon + textのChipで折り返し可能に表示する。
- `AppEmptyState`: icon + title + optional body/actionで、空リスト・空タスク・空サブタスク・task not foundの文法を揃えた。
- `AppLoadingState` / `AppErrorState`: `CircularProgressIndicator` とerror textの画面ごとの差をなくした。
- `showAppTextInputDialog` / `showAppConfirmDialog`: 作成系入力ダイアログと確認ダイアログのボタン文法を統一した。

### Lists / Tasks / TaskDetail の整理

- Listsは空状態と作成ダイアログを共通部品化し、既存のリスト行と遷移導線を維持した。
- Tasksは階層表示を `AppTaskRow` へ寄せ、トップレベル/サブタスク、done/todo、metadata、chevronの表示規則を統一した。
- TaskDetailはタイトル、note、metadata、created_at、サブタスクセクション、追加/削除アクションの間隔を `AppSpacing` へ寄せた。
- 詳細画面のサブタスク行では `descendantStatsOf(subtask.id, tasks)` の重複呼び出しをやめ、行ごとに一度だけ計算するよう整理した。

### 空状態、loading/error、ダイアログ

- 空リスト・空タスクは共通empty stateでicon + title + bodyを表示する。
- 空サブタスクとtask not foundも同じempty state文法に寄せた。
- loading/errorは `AppLoadingState` / `AppErrorState` 経由に統一した。
- list/task/subtask作成は `showAppTextInputDialog`、未完了子孫を持つ親完了確認は `showAppConfirmDialog` へ統一した。

### status / priority / due date / subtask progress

- statusは内部値 `todo` / `done` をそのまま表示せず、`statusTodo` / `statusInProgress` / `statusDone` / `statusWontDo` のARBラベルへ変換して表示する。
- priorityは `priorityNone` / `priorityLow` / `priorityMedium` / `priorityHigh` の既存ARBラベルをmetadata表示にも使う。
- due dateは `formatDueDate` で `yyyy-MM-dd` または `noDueDate` に揃える。
- subtask progressは既存の `subtaskProgress(doneCount, totalCount)` をmetadata chipで表示する。

### i18n

- 追加/変更したARBキー:
  - `listsEmptyTitle`
  - `listsEmptyBody`
  - `tasksEmptyTitle`
  - `tasksEmptyBody`
  - `statusTodo`
  - `statusInProgress`
  - `statusDone`
  - `statusWontDo`
  - `noDueDate`
- `taskPriority` のplaceholder型を `int` から `String` に変更し、表示値をローカライズ済みpriority labelへ寄せた。
- `cd app && flutter gen-l10n` を実行し、`app/lib/src/generated/l10n/` 配下を更新した。

### アクセシビリティ

- AppBarの編集アイコン、FAB、既存icon付きボタンのtooltip / labelを維持した。
- checkboxの `ValueKey('task-done-${task.id}')` と行キーを維持し、widget testから引き続き探索できるようにした。
- metadataは色だけでなくicon + textでstatus / priority / due / progressを伝える。
- metadataは `Wrap` で折り返し可能にし、固定heightでテキストを潰さない構成にした。

### テスト

- `app/test/widget_test.dart` の期待値を、status/priorityの表示ラベル変更に合わせて更新した。
- 既存widget testは、リスト表示、画面遷移、タスク作成、編集、サブタスク表示/作成、親完了確認を引き続き検証している。
- golden testやスクリーンショット比較基盤は追加していない。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（Rust 62件）。
- `cd app && flutter gen-l10n`: 成功。
- `cd app && flutter analyze`: 成功（No issues found）。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test`: 成功（Flutter 20件）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功（`main.dart` / `src/screens` / `src/ui` 対象、検出0件）。
- `git -C taskveil diff --check`: 成功。

### やらなかったこと

- 新規pub依存・新規Rust依存は追加していない。
- Rust API、FRB生成物、DB schema、domain usecaseは変更していない。
- ゴミ箱画面・復元UI、Undo、fractional index、ドラッグ&ドロップ並び替え、通知、タグ、検索UI、設定画面は実装していない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。
- `taskveil-private/` は読んでおらず、private詳細をpublic repoへ転記していない。

### 未解決事項・要人間判断

- なし。
