# task-54: タスク作成シート

> ステータス: 完了（worker実装）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

2026-07-08ドッグフーディング第4回で、task-52の下部常設クイック追加バーは即時入力欄ではなく、`design_lab_task_create_sheet.png` のようなタスク作成ボトムシートを開くトリガーにしたい、というフィードバックが出た。

task-52で確立した作成先の既定値、連続追加、IME composing、キーボードinsetの要件は維持する。本タスクでは、既存の下部バーを「タップして作成シートを開く入口」へ変更し、シート内でタイトル、Note、List、Dueを指定して作成できるようにする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（Homeクイック追加バー、チップ/pill、画面規範）
- `docs/tasks/task-52-quick-add-bar.md`
- `docs/tasks/task-53-swipe-and-motion.md`
- `app/test/visual_qa/design_lab_task_create_sheet_mock.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/rust/src/api.rs`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- 下部常設クイック追加バーを、タスク作成ボトムシートを開くトリガーへ変更する。
- Labモック準拠のシートを実装する。
- シート内でタイトル、Note、作成先List、Dueを指定できるようにする。
- Homeでは既定Inbox+今日期日、通常リスト画面では当該リスト+期日なしを初期値にする。
- Add task後もシートを閉じず、入力をクリアして連続追加できる。
- task-52のIME composing、空タイトル無効、キーボードinset、作成失敗時の扱いを継承する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/ui/task_components.dart` または新規小コンポーネント
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARB変更時の生成差分のみ）
- `app/rust/src/api.rs`（Note付き作成に必要な場合）
- `app/lib/src/rust/` と `app/rust/src/frb_generated.*`（Rust API変更時のFRB生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-54-create-task-sheet.md`（完了報告の追記のみ）

### やること

1. 下部バーを作成シートのトリガーに変更する。
   - Homeと通常リスト画面で同じ入口文法を使う。
   - バー内に直接入力する挙動は廃止し、タップでシートを開く。
   - tooltip/semanticsは「タスク作成を開く」意味へ更新する。
2. `showModalBottomSheet` 系でシートを実装する。
   - Labモック `design_lab_task_create_sheet_mock.dart` の構成を参照する。
   - 角丸は上のみ。`ui-spec.md` の既存トークンを優先し、新しい値が必要なら完了報告の未解決事項へ記録する。
   - 背景dimは控えめにし、強い暗幕にしない。
   - SafeArea、`isScrollControlled`、keyboard insetを考慮し、タイトル/Note/List/Due/Add taskがキーボードで隠れないようにする。
3. シート内容を実装する。
   - タイトル入力: 大きめplaceholder、自動フォーカス、trim後空ならAdd task無効。
   - Note入力: 任意。作成されるタスクの `note` として保存する。
   - Listチップ: 作成先リストを選べる。アーカイブ済みリストを候補に含めるかは既存作成可否と整合させ、判断を完了報告に記録する。
   - Dueチップ: Today / Tomorrow / 日付ピッカー / クリアを提供する。
   - Add taskボタン: タイトル空なら無効。実行中は二重送信を避ける。
4. 既定値と連続追加を維持する。
   - Home初期値は既定Inbox + 今日。
   - 通常リスト画面初期値は当該リスト + 期日なし。
   - 追加成功後もシートは開いたまま、タイトル/Noteをクリアし、List/Dueは現在選択値を維持する。
   - 初回オープン時の既定値は画面種別に従う。
5. Note付き作成経路を整える。
   - 既存 `create_task` / `BridgeService.createTask` がNoteを受け取れない場合は、挿入前にnoteを設定できる形でRust bridge/APIを拡張する。
   - Rust APIを変更した場合は `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、生成物を手編集しない。
   - 作成直後に `updateTask` して編集Undoを汚す実装は避ける。
6. テストとvisual QAを更新する。
   - 既存のクイック追加系widget testをシート方式へ更新する。
   - Home/通常リストでシートが開くこと、既定値、List変更、Due変更/クリア、Note保存、連続追加、空タイトル無効、IME composing中の誤作成防止を確認する。
   - visual QAでシート表示状態のスクリーンショットをHome/通常リスト各1枚以上生成する。

### やらないこと

- 時刻/リマインダー。
- 自然言語日付解析。
- 時刻機能実装前のPlanチップ表示。
- 優先度チップの必須実装。優先度は詳細画面で設定する。ただし既存構造への追加が軽く、チップ数/視覚密度の規則を破らない場合は追加してよい。
- Homeサブツリー同伴表示（task-55）。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、現行 `QuickAddBar`、`HomeTasksNotifier.createTask`、`TasksNotifier.createTask`、FRB `create_task` の引数を把握する。
3. 下部バーを、入力欄ではなくシート起動ボタン/バーとして再設計する。
4. タスク作成シートのstateを、タイトル、Note、選択List、Due、送信中、エラーで分ける。
5. Home/通常リストの初期List/Dueを決め、List候補を `listsProvider` から取得する。
6. Note付き作成に必要なbridge/API変更を最小範囲で行い、Rust API変更時はFRBを再生成する。
7. 既存クイック追加テストをシート方式へ更新し、List/Due/Note/連続追加/composingを固定する。
8. visual QA実行前に `app/build/visual_qa/` を `app/build/visual_qa_before/` へ退避し、実装後に `sh app/tool/visual_qa.sh` を実行する。
9. 品質ゲートを実行し、指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 下部バーが直接入力欄ではなく作成シートのトリガーになり、Home/通常リストでタップするとボトムシートが開くことがwidget testで確認されている。
- [ ] シートに大きめタイトル入力（自動フォーカス）、Note入力、Listチップ、Dueチップ、Add taskボタンがあり、UI文字列がen/ja ARB化されている。
- [ ] Home初期値が既定Inbox+今日、通常リスト初期値が当該リスト+期日なしであることがwidget testで確認されている。
- [ ] Listチップで作成先を変更でき、DueチップでToday/Tomorrow/日付ピッカー/クリアを扱えることがwidget testで確認されている。
- [ ] Note入力が作成タスクの `note` として保存され、作成直後の編集Undoを汚していないことがテストまたは完了報告の実装説明で確認できる。
- [ ] Add taskはタイトル空なら無効で、IME composing中に誤作成せず、送信中の二重作成を防ぐことがwidget testで確認されている。
- [ ] 追加成功後もシートが開いたままタイトル/Noteがクリアされ、連続追加できることがwidget testで確認されている。
- [ ] keyboard insetありの状態でもシート内容とAdd taskボタンが隠れないことがwidget testまたはvisual QAで確認されている。
- [ ] visual QAにHome/通常リストそれぞれのシート表示状態スクリーンショットが保存されている。
- [ ] 完了報告に、作成先/期日初期値、Note保存経路、FRB再生成有無、visual QAパス、品質ゲート結果が記録されている。

## 7. 制約・注意事項

- Homeの既定作成先は `isDefault == true` の既定Inboxである。sort order先頭やリスト名一致で推測しない。
- Homeの「今日」は端末ローカル日付の開始時刻を使う。
- 通常リスト画面の既定Dueは期日なしであり、勝手に今日へしない。
- Planチップは時刻機能実装まで置かない。LabモックにPlan/Estimate/Tagが見えていても、本タスクの必須UIには含めない。
- シート内のチップは操作要素なので、tooltip/semantics、48px級タップ領域、色だけに依存しない状態表現を維持する。
- UI文字列はDartへ直書きしない。
- Rust APIを変更した場合、FRB生成物は必ずcodegenで更新し、手編集しない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 下部バーをシートトリガーへ変更した箇所
- シートの実装箇所、表示方式、SafeArea/keyboard inset対応
- Home/通常リストの既定List/Due
- List/Due/Noteの保存経路
- Rust API/FRB生成物の変更有無
- 空タイトル、IME composing、二重送信、連続追加の挙動
- 追加・更新したl10nキー
- 追加・更新したテスト名と検証対象
- visual QA before/afterスクリーンショットの保存パス
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

### 作業日

- 2026-07-08

### 読んだファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md`
- `docs/tasks/task-52-quick-add-bar.md`
- `docs/tasks/task-53-swipe-and-motion.md`
- `app/test/visual_qa/design_lab_task_create_sheet_mock.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/rust/src/api.rs`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

### 作業前退避

- `app/build/visual_qa/*.png` を `app/build/visual_qa_before/` へコピーした。
- 退避先: `app/build/visual_qa_before/`

### 実装結果

- `app/lib/src/ui/task_components.dart` の `QuickAddBar` を直接入力欄から `showModalBottomSheet` のトリガーへ変更した。
- `QuickAddBar` は `ValueKey('quick-add-open')`、tooltip、semantics labelを持つボタン型の下部バーとして表示する。
- `app/lib/src/ui/task_components.dart` にタスク作成シートを追加した。
- シートは `showModalBottomSheet(isScrollControlled: true, useSafeArea: true)` で表示し、`barrierColor` は `scrim` のalpha 0.24にした。
- シートは `SafeArea(top: false)` と `MediaQuery.viewInsetsOf(context).bottom` を使う `AnimatedPadding` でkeyboard insetに追従する。
- シートは上部ハンドル、大きいタイトル入力、Note入力、Listチップ、Dueチップ、Add taskボタンで構成した。
- Add task成功後はシートを閉じず、タイトル/Noteをclearし、選択中のList/Dueを維持する。
- List候補はactive listとarchived listを重複除去して渡す実装にした。アーカイブ済みリスト画面では既存の作成可否と同じく当該リストを初期選択に含める。
- DueチップはToday、Tomorrow、日付ピッカー、クリアを扱う。

### 既定値と保存経路

- Home初期値: `isDefault == true` の既定Inbox + `homeLocalRangesMs().todayStartMs`。
- 通常リスト初期値: 表示中リスト + `dueAt == null`。
- Home作成は `HomeTasksNotifier.createTask(listId:, title:, note:, dueAt:)` から `BridgeService.createTask` を呼ぶ。
- 通常リスト作成は `TasksNotifier.createTask(title, note:, dueAt:)` から `BridgeService.createTask` を呼ぶ。
- Noteは `BridgeService.createTask(note:)` からRust `create_task(..., note: Option<String>)` へ渡し、Rust側でinsert前の `Task.note` に設定する。
- 作成後に `updateTask` は呼ばない。

### Rust API / FRB

- `app/rust/src/api.rs` の `create_task` に `note: Option<String>` を追加した。
- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行した。
- FRB生成差分:
  - `app/lib/src/rust/api.dart`
  - `app/lib/src/rust/frb_generated.dart`
  - `app/rust/src/frb_generated.rs`

### 入力挙動

- タイトルtrim後が空の場合、Add taskボタンは無効。
- タイトル入力のcomposing rangeが有効かつ非collapsedの場合、Add taskボタンは無効。
- 送信中はAdd taskボタンを無効化し、二重送信を防ぐ。
- 作成失敗時は既存の `quickAddCreateError` をSnackBarで表示し、入力値とフォーカスを保持する。

### l10n

- 追加キー:
  - `quickAddOpenTooltip`
  - `quickAddOpenSemantics`
  - `taskCreateTitleHint`
  - `taskCreateListChip`
  - `taskCreateListTooltip`
  - `taskCreateDueChip`
  - `taskCreateDueTooltip`
- `flutter gen-l10n` を実行し、`app/lib/src/generated/l10n/` を更新した。

### テスト

- 更新: `home add task creates in default inbox with today due date`
  - Homeでシートが開くこと、既定Inbox+今日、Note保存、空タイトル時Add無効を確認。
- 更新: `list create sheet creates in current list without due date`
  - 通常リストでシートが開くこと、当該リスト+期日なしで作成することを確認。
- 更新: `create sheet ignores blanks and keeps focus for consecutive adds`
  - 空タイトル無視、作成後のタイトルclear、フォーカス維持、連続追加を確認。
- 更新: `create sheet submit ignores active composing range`
  - composing中に作成されないことを確認。
- 追加: `create sheet changes list and due, clears due, saves note, and keeps selections`
  - List変更、Due Tomorrow、日付ピッカー、Dueクリア、Note保存、選択維持を確認。
- 追加: `create sheet disables add while submitting`
  - 送信中にAdd taskが無効化され、二重作成されないことを確認。
- 更新: `default inbox empty tasks and quick add survive narrow Dynamic Type`
  - 狭幅/Dynamic Typeで下部バーとシート起動を確認。
- 更新: visual QA
  - `task_create_sheet_home`
  - `task_create_sheet_list`

### visual QA

- before:
  - `app/build/visual_qa_before/`
  - `app/build/visual_qa_before/design_lab_task_create_sheet.png`
- after:
  - `app/build/visual_qa/task_create_sheet_home.png`
  - `app/build/visual_qa/task_create_sheet_list.png`
  - `app/build/visual_qa/design_lab_task_create_sheet.png`
- 目視比較:
  - `app/build/visual_qa/design_lab_task_create_sheet.png` と `app/build/visual_qa/task_create_sheet_home.png` を確認した。
  - `app/build/visual_qa/design_lab_task_create_sheet.png` と `app/build/visual_qa/task_create_sheet_list.png` を確認した。
  - 実装シートはハンドル、大きいタイトル入力、Note、Listチップ、Dueチップ、Add taskボタンを表示している。
  - `task_create_sheet_home.png` はList Inbox / Due Todayを表示している。
  - `task_create_sheet_list.png` はList Inbox / Due No due dateを表示している。

### 品質ゲート

- `cargo fmt --all -- --check`: exit 0
- `cargo clippy --workspace -- -D warnings`: exit 0
- `cargo test --workspace`: exit 0
- `cd app && flutter analyze`: exit 0
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
- `cd app && flutter test`: exit 0（84 passed, 1 skipped）
- `sh app/tool/check_hardcoded_strings.sh`: exit 0
- `sh app/tool/visual_qa.sh`: exit 0（36 passed）
- `git diff --check`: exit 0

### 変更ファイル一覧

- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/generated/l10n/app_localizations.dart`
- `app/lib/src/generated/l10n/app_localizations_en.dart`
- `app/lib/src/generated/l10n/app_localizations_ja.dart`
- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-54-create-task-sheet.md`

### 未解決事項

- なし
