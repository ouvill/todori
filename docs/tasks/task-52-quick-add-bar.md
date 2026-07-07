# task-52: 下部常設クイック追加バー

> ステータス: 完了（worker実装）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

2026-07-07 Home改善裁定では、画面下中央のAdd task pillと入力ダイアログを廃止し、下部常設のクイック追加バーへ置き換えることが決まった。Homeでは入力確定で既定Inboxへ今日期日のタスクを即作成する。通常リスト画面では、そのリストへ期日なしで作成する。

task-42ではインライン編集でIME composingを考慮した保存制御が実装済みである。本タスクでも、テキスト入力中のcomposing状態、空文字、キーボード出現時のレイアウトを扱う。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（Homeクイック追加バー）
- `docs/tasks/task-42-detail-inline-edit.md` と実装箇所（IME composingの扱い）
- `docs/tasks/task-51-home-restructure.md`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- Homeと通常リスト画面に、下部常設のクイック追加バーを実装する。
- 既存のHome Add task pill、通常リストのFAB、入力ダイアログ経由のタスク作成を置き換える。
- Homeでは入力確定で既定Inboxへ今日期日のタスクを作成する。
- 通常リスト画面では入力確定で現在のリストへ期日なしのタスクを作成する。
- 作成後も入力欄を継続利用でき、連続追加できる。
- 空文字は無視し、IME composing中の確定誤爆を避ける。
- キーボード出現時にも入力欄、Homeセクション、通常リスト行が破綻しない。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`（必要な場合のみ）
- `app/lib/src/ui/task_components.dart` または新規小コンポーネント
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARB変更時の生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-52-quick-add-bar.md`（完了報告の追記のみ）

### やること

1. 下部常設クイック追加バーを作る。
   - テキスト入力欄、追加アイコン/送信操作、必要なtooltip/semanticsを持つ。
   - Homeと通常リスト画面で同じ文法を使う。
   - SafeAreaとkeyboard insetを考慮し、キーボード表示時も入力欄が隠れないようにする。
2. 既存のAdd task UIを置き換える。
   - Homeのbottom Add task pillを撤去する。
   - 通常リスト画面のFABを撤去する。
   - `showAppTextInputDialog` 経由の新規タスク作成を使わない。
3. 作成先と期日を画面種別で分ける。
   - Homeでは既定Inboxへ作成し、`due_at` を今日のローカル日付に設定する。
   - 通常リスト画面では現在の `listId` へ作成し、`due_at` はnullのままにする。
   - アーカイブ済みリストを開いた画面で作成を許可するかどうかは既存挙動に合わせ、判断した内容を完了報告に記録する。
4. 入力挙動を整える。
   - Enter/submit、送信アイコン、モバイルIMEの完了操作で作成する。
   - trim後に空文字なら作成しない。
   - IME composing中は確定として扱わない。task-42の実装を参照する。
   - 作成成功後は入力欄を空にし、フォーカスは維持して連続追加できるようにする。
   - 作成失敗時は既存のエラー表示文法に合わせる。
5. テストとvisual QAを追加・更新する。
   - widget testでHome作成先/期日、通常リスト作成先/期日なし、空文字無視、連続追加、composing中の誤作成防止を確認する。
   - visual QA実行前に `app/build/visual_qa/` を `app/build/visual_qa_before/` へ退避し、実装後に `sh app/tool/visual_qa.sh` を実行する。
   - Homeと通常リスト画面の下部バー、キーボード想定のレイアウトを確認できる証拠を完了報告に記録する。

### やらないこと

- 自然言語日付解析（例: `tomorrow`, `next Friday`, `明日` の解釈）。これはBACKLOGの将来枠へ送る。
- スワイプ/モーション実装（task-53）。
- Homeセクション再構成（task-51で完了済み前提）。
- タスク詳細画面のインライン編集変更。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、既存 `_createTask`、`todayTasksProvider.createTask`、通常 `tasksProvider(listId).createTask`、task-42のcomposing判定を把握する。
3. Home/通常リストで共有できる `QuickAddBar` 相当の小コンポーネントを設計する。
4. `Scaffold.bottomNavigationBar` または同等の構造で、SafeArea/keyboard insetを考慮して配置する。
5. Homeでは既定Inbox+今日期日、通常リストでは現在リスト+期日なしへ分岐して作成する。
6. 既存のFAB/Add pill/dialog作成経路を撤去し、不要になったl10nキーがあれば整理する。
7. 空文字、連続追加、composing中、失敗時の挙動をwidget testで固定する。
8. visual QAを更新し、before/afterを保存する。
9. 品質ゲートを実行し、指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] Homeに下部常設クイック追加バーが表示され、既存のHome Add task pillと入力ダイアログが表示されないことがwidget testで確認されている。
- [ ] 通常リスト画面に下部常設クイック追加バーが表示され、既存のFABと入力ダイアログが表示されないことがwidget testで確認されている。
- [ ] Homeで入力確定すると、既定Inboxへ `due_at` 今日のタスクが作成されることがwidget testで確認されている。
- [ ] 通常リスト画面で入力確定すると、そのリストへ `due_at == null` のタスクが作成されることがwidget testで確認されている。
- [ ] 作成成功後に入力欄が空になり、フォーカスを維持して連続追加できることがwidget testで確認されている。
- [ ] trim後の空文字ではタスクが作成されないことがwidget testで確認されている。
- [ ] IME composing中の入力が確定として扱われず、誤作成しないことがwidget testで確認されている。
- [ ] キーボード表示相当のviewport/insetでも入力欄とリスト内容が重なって破綻しないことがwidget testまたはvisual QAで確認されている。
- [ ] Home/通常リストのvisual QA before/afterで下部バーの配置が確認できる。
- [ ] 完了報告に、作成先/期日分岐、composing判定、visual QA before/afterパス、品質ゲート結果が記録されている。

## 7. 制約・注意事項

- Homeの作成先はtask-46で導入された `isDefault == true` の既定Inboxである。`lists.first` やsort order先頭を使わない。
- Homeの「今日」は端末ローカル日付で判定する。
- 通常リスト画面で期日を勝手に今日にしない。Homeのみ今日期日とする。
- TextFieldの制御でcomposing範囲を破壊しない。task-42のインライン編集実装を参照し、IME入力中の日本語/中国語等で誤作成しないようにする。
- UI文字列はARB化する。placeholder、tooltip、semantics、エラー文言をDartへ直書きしない。
- 自然言語日付解析は実装しない。必要なUI余白や内部メソッド名も、将来解析を前提に複雑化しすぎない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- クイック追加バーの実装箇所、配置方式、SafeArea/keyboard inset対応
- Homeと通常リストの作成先/期日分岐
- 既存Add task pill/FAB/dialog作成経路の撤去箇所
- 空文字、連続追加、IME composing、作成失敗時の挙動
- 追加・更新したl10nキー
- 追加・更新したテスト名と検証対象
- visual QA before/afterスクリーンショットの保存パス
- BACKLOGへ自然言語日付解析を送ったことの確認
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

### 作業日

2026-07-07

### 読んだファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3
- `docs/tasks/task-42-detail-inline-edit.md`
- `docs/tasks/task-51-home-restructure.md`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
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

- `app/lib/src/ui/task_components.dart` に `QuickAddBar` を追加した。
- `QuickAddBar` は `TextField`、左側の追加アイコン、右側の送信 `IconButton`、tooltip、semantics、作成失敗時の `SnackBar` を持つ。
- `QuickAddBar` は `Scaffold.bottomNavigationBar` として `TasksScreen` に配置した。
- `QuickAddBar` は `SafeArea(top: false)` と `MediaQuery.viewInsetsOf(context).bottom` を使う `AnimatedPadding` で keyboard inset に追従する。
- `TasksScreen` の Home bottom Add task pill と通常リスト FAB を撤去した。
- `TasksScreen._createTask` から `showAppTextInputDialog` 経由の新規タスク作成を撤去した。
- Homeでは `homeTasksProvider.notifier.createTask(title)` を呼び、既存 provider 経路で `isDefault == true` の既定Inboxへ `dueAt = todayStartMs` で作成する。
- 通常リストでは `tasksProvider(listId).notifier.createTask(title)` を呼び、現在の `listId` へ `dueAt == null` で作成する。
- アーカイブ済みリスト画面では、既存FABと同じく作成を許可する挙動を維持した。
- trim後の空文字は `QuickAddBar` 内で無視する。
- 作成成功後は controller を clear し、同じ `FocusNode` へ `requestFocus()` する。
- `TextField.onEditingComplete` を no-op にし、`onSubmitted` 時に `TextEditingValue.composing` が有効かつ非collapsedの場合は作成しない。
- 作成失敗時は `quickAddCreateError` を `SnackBar` に表示し、入力値を保持してフォーカスを戻す。

### l10n

- 追加キー:
  - `quickAddHint`
  - `quickAddSubmitTooltip`
  - `quickAddTextFieldSemantics`
  - `quickAddCreateError`
- `flutter gen-l10n` を実行し、`app/lib/src/generated/l10n/` を更新した。

### テスト

- 更新: `home add task creates in default inbox with today due date`
  - Homeのクイック追加バーから既定Inboxへ今日期日で作成されること、HomeのFAB/ダイアログが表示されないことを確認。
- 追加: `list quick add creates in current list without due date`
  - 通常リストのクイック追加バーから現在リストへ期日なしで作成されること、通常リストのFAB/ダイアログが表示されないことを確認。
- 追加: `quick add ignores blanks and keeps focus for consecutive adds`
  - 空文字無視、作成後の入力欄clear、フォーカス維持、連続追加を確認。
- 追加: `quick add submit ignores active composing range`
  - composing中の `TextInputAction.done` でタスクが作成されないことを確認。
- 更新: `default inbox empty tasks and quick add survive narrow Dynamic Type`
  - narrow viewport / Dynamic Typeでクイック追加バーが表示され、入力開始しても既存作成ダイアログが表示されないことを確認。
- 更新: visual QA `_openTask`
  - 常設バー追加後も同名Text重複で既存スクショが失敗しないよう、hit-test可能なタイトルを開く実装に変更。
- 追加: visual QA `quick_add_home_normal` / `quick_add_home_inputting` / `quick_add_list_normal` / `quick_add_list_inputting`
  - Home/通常リストの通常状態と keyboard inset 入力中状態をPNG出力する。

### visual QA

- before:
  - `app/build/visual_qa_before/home_tasks.png`
  - `app/build/visual_qa_before/wont_do_row.png`
- after:
  - `app/build/visual_qa/quick_add_home_normal.png`
  - `app/build/visual_qa/quick_add_home_inputting.png`
  - `app/build/visual_qa/quick_add_list_normal.png`
  - `app/build/visual_qa/quick_add_list_inputting.png`
  - `app/build/visual_qa/home_tasks.png`
  - `app/build/visual_qa/wont_do_row.png`
- 目視確認:
  - `assets/brand/explorations/home-20260707/home_a_ticktick.png` の下部バーは、左追加アイコン、中央入力、右追加/送信操作、下部常設の丸いバー構造だった。
  - `quick_add_home_normal.png` / `quick_add_list_normal.png` は、下部常設の丸い入力バー、左追加アイコン、右送信アイコンを表示している。
  - `quick_add_home_inputting.png` / `quick_add_list_inputting.png` は、keyboard inset相当でバーが上がり、入力欄と表示行が重なっていない。

### BACKLOG確認

- 自然言語日付解析は `docs/tasks/BACKLOG.md` の優先度付きバックログ #4 に将来枠として存在することを確認した。

### 品質ゲート

- `cargo fmt --all -- --check`: exit 0
- `cargo clippy --workspace -- -D warnings`: exit 0
- `cargo test --workspace`: exit 0
- `cd app && flutter analyze`: exit 0
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
- `cd app && flutter test`: exit 0（79 passed, 1 skipped）
- `sh app/tool/check_hardcoded_strings.sh`: exit 0
- `sh app/tool/visual_qa.sh`: exit 0（34 passed）
- `git diff --check`: exit 0

### 変更ファイル一覧

- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/app_localizations.dart`
- `app/lib/src/generated/l10n/app_localizations_en.dart`
- `app/lib/src/generated/l10n/app_localizations_ja.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-52-quick-add-bar.md`

### 未解決事項

- なし
