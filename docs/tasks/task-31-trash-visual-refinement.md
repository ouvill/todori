# task-31: trash visual refinement ── relative dates / quiet metadata / dark dot QA

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-05

## 1. 背景とコンテキスト

task-30で主要なタスク行は「相対日付ピル + priority dot」の文法に寄せたが、完了報告の未解決事項として次が残っている。

- Trash画面の日付表記がTasks画面と同じ相対表記になっていない。
- priority dot色トークン（coral/amber/softSage）のダークテーマ視認性が未検証である。

今回のbeforeスクリーンショット（`sh app/tool/visual_qa.sh` による `app/build/visual_qa/trash.png`）では、Trash行に `Deleted: 1970-01-01` / `Priority: Medium` / `2026-07-02` のような冗長なチップが残っていた。これは `docs/design/visual-direction.md` の「Trash is an operational screen, not a danger zone」「Deleted rows should look recoverable」という方針、およびtask-30後のタスク行文法から見ると視覚ノイズが強い。

このタスクは新機能ではない。Trash画面の表示密度、日付表記、priority表現、visual QA seed / dark screenshot検証だけを小さく整える。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/visual-direction.md`
- `docs/tasks/task-23-trash-restore-ui.md`
- `docs/tasks/task-30-design-mood-alignment.md`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`
- `app/tool/check_hardcoded_strings.sh`

必要に応じて `app/lib/src/generated/l10n/` の生成結果も確認する。ただし生成物は手編集しない。

## 3. ゴール

- Trash行の削除日時と期限日を、Tasks画面と同じ相対/短縮日付文法へ統一する。
- Trash行のpriority表現を、冗長な `Priority:` チップからpriority dot + tooltip/semanticsへ寄せる。
- Trash行を「危険領域」ではなく「復元可能なタスク」として、控えめで読みやすい見た目に整える。
- visual QA seedで `1970-01-01` のような不自然な日時が出ないようにし、before/afterの判断材料を信頼できる状態にする。
- ダークテーマでpriority dotの視認性を目視確認できるvisual QA screenshotを追加する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/` 配下（ARB変更時のみ生成差分）
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-31-trash-visual-refinement.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

**A. Trash日付表記の統一**

- `_TrashTaskRow` の削除日時・期限日を `formatRelativeDueDate` 相当の表示にする。
- 今日/明日/短縮日付の文法はTasks画面と一致させる。
- 削除日時は「Deleted: YYYY-MM-DD」のような長いラベルを避ける。表示文言を残す場合も短く、ローカライズされた落ち着いた表現にする。
- 期限切れの期限日は既存のoverdue semanticsと同等に、色だけで意味を伝えない。

**B. Trash priority表現のquieting**

- `Priority: Medium` のようなpriorityチップをTrash行から削除する。
- priority > 0 の場合は既存 `PriorityDot` を使い、tooltip/semanticsで意味を保持する。
- priority noneはdot非表示にする。

**C. Trash行の視覚密度調整**

- 復元ボタンのtooltip/semanticsと48px級タップ領域は維持する。
- 行の構造は大きく変えないが、丸い大アイコン・余白・チップ数が画面を重くしている場合は、現行デザイン文法に合わせて控えめにする。
- 長いタイトル、日本語、狭幅、Dynamic Typeで折返しが破綻しないようにする。

**D. visual QA seedの現実化**

- `FakeBridgeService` の `createdAt` / `updatedAt` / `deletedAt` / `completedAt` / undo `createdAt` について、visual QA上で `Jan 1, 1970` や `1970-01-01` が出ないよう、現実的なepoch millisecondsを使う。
- 既存widget testが順序やUndo競合を検証している場合は壊さない。必要ならテスト期待値を現在の意味に合わせて更新する。

**E. ダークモードpriority dot QA**

- `app/test/visual_qa/visual_qa_screenshots_test.dart` に、ダークテーマのタスク画面またはpriority dot確認用スクリーンショットを追加する。
- 追加スクリーンショット名は `home_tasks_dark.png` など、用途が分かるものにする。
- 生成されたPNGを目視し、coral/amber/softSageのdotが背景に埋もれていないことを完了報告に記録する。

### やらないこと

- Rust API / FRB / DB schema / domain / storage / core配下 / cli / mcp-server / server は変更しない。
- 復元仕様、削除仕様、Undo仕様、並び替え仕様を変更しない。
- Focus timer、検索、通知、設定画面、マスコット常駐、bottom navigationなどの新機能を追加しない。
- Lists / Tasks / Task detailの大規模再設計はしない。今回の変更はTrashの整合とvisual QAの検証足場に限定する。
- 新規pub依存や新規画像アセットを追加しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `taskveil-private/` と `.github/` は変更しない。

## 5. 実装手順例

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読む。
3. 現状の `sh app/tool/visual_qa.sh` を実行し、`app/build/visual_qa/` を `app/build/visual_qa_before_task_31/` へ退避する。
4. `trash_screen.dart` の `_TrashTaskRow` を、相対日付・priority dot・控えめなmetadata構成へ変更する。
5. UI文字列の変更がある場合は `app_en.arb` / `app_ja.arb` を更新し、`cd app && flutter gen-l10n` を実行する。
6. `FakeBridgeService` のテスト用時刻を現実的なepoch millisecondsへ変更し、既存widget testへの影響を確認する。
7. `visual_qa_screenshots_test.dart` にダークテーマ確認用スクリーンショットを追加する。
8. `sh app/tool/visual_qa.sh` を再実行し、before/afterのPNGを目視する。
9. `flutter analyze` / `flutter test` / `sh app/tool/check_hardcoded_strings.sh` / `git diff --check` を実行する。必要に応じてRust側品質ゲートも実行する。
10. この指示書末尾に `## 9. 完了報告` を追記し、README/BACKLOGの状態を同期する。

## 6. 受け入れ基準

- [ ] `app/build/visual_qa/trash.png` で、Trash行に `Deleted: YYYY-MM-DD` 形式が残っていない。
- [ ] `app/build/visual_qa/trash.png` で、Trash行の期限日がTasks画面と同じ相対/短縮日付文法になっている。
- [ ] `app/build/visual_qa/trash.png` で、`Priority:` チップが存在せず、priorityはdot + tooltip/semanticsで表現されている。
- [ ] `app/build/visual_qa/trash.png` と `task_detail.png` に `1970` 由来の日付が表示されていない。
- [ ] ダークテーマのpriority dot確認スクリーンショットが `app/build/visual_qa/` に生成され、dotが背景に埋もれていない。
- [ ] 復元ボタンのtooltip/semanticsと48px級タップ領域が維持されている。
- [ ] 長いタイトル、日本語、狭幅、Dynamic TypeでTrash行が破綻しない。
- [ ] 追加・変更UI文字列がen/ja ARB化され、ARB変更時は生成済みlocalizationsが更新されている。
- [ ] `app/lib/src/generated/l10n/` 配下は `flutter gen-l10n` による生成差分のみである。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `git diff --check` が成功している。
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [ ] `taskveil-private/` と `.github/` が変更されていない。

## 7. 制約・注意事項

- このタスクはvisual refinementであり、新機能開発ではない。
- `docs/design/visual-direction.md` はpublic repoのデザイン正本である。画像モックのピクセル再現より、実データ、i18n、アクセシビリティ、狭幅、Dynamic Type、操作性を優先する。
- visual QAは必ずbefore/afterで見る。実装者の自己申告だけで合格扱いにしない。
- UI文字列は必ずARB化する。`Text('...')`、`Tooltip(message: '...')` などの直書きを残さない。
- `FakeBridgeService` はwidget/visual QAの共有基盤である。時刻を現実化しても、Undo競合や並び替えのテスト意味を変えない。
- priority dotの意味は色だけに依存しない。tooltip/semanticsを維持する。
- public repoにprivate repoの課金、収益、法務、監査、公開前ロードマップ詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- Trash日付表記の変更内容
- Trash priority表現の変更内容
- Trash行の密度・余白・復元ボタンの保持内容
- visual QA seedの時刻現実化内容
- ダークテーマpriority dot QAの追加内容とスクリーンショットパス
- before/afterスクリーンショットの保存パスと目視比較結果
- 追加/変更したi18nキーと `flutter gen-l10n` の実行結果
- 追加/更新したwidget testの対象と結果
- 品質ゲート（`flutter analyze` / `flutter test` / `check_hardcoded_strings.sh` / `git diff --check`）の実行結果
- やらなかったことが守られていること（新機能なし、Rust/FRB/DB/core変更なし、新規pub依存なし）
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` を変更していないこと
- `taskveil-private/` と `.github/` を変更していないこと
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
- `docs/tasks/task-23-trash-restore-ui.md`
- `docs/tasks/task-30-design-mood-alignment.md`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`
- `app/tool/check_hardcoded_strings.sh`

### Trash日付表記の変更内容

- `trash_screen.dart` の `_TrashTaskRow` で、削除日時と期限日を `formatRelativeDueDate` 相当の表示へ変更した。
- 削除日時は `Deleted: 1970-01-01` 形式ではなく `Deleted Jul 1` / `削除 Jul 1` の短い表記にした。
- 期限日はTasks画面と同じ `Today` / `Tomorrow` / `Jul 2` 相当の短縮文法を使い、期限切れはcoral表示に加えて `taskDueOverdue` のsemanticsを維持した。

### Trash priority表現の変更内容

- Trash行の visible な `Priority: Medium` チップを削除した。
- `PriorityDot` をTrash行タイトルの前に表示し、priority noneではdotを表示しない。
- dotには `Priority: Medium` 等のtooltip/semanticsを付与し、意味を色だけに依存させない。

### Trash行の密度・余白・復元ボタン

- 行左の大きな丸アイコンを48pxから40pxへ抑え、Trash行の視覚重量を下げた。
- 行構造、折返し、restore actionの配置は既存構成を維持した。
- 復元ボタンは `IconButton` のtooltip/semanticsと48px級タップ領域を維持した。

### visual QA seedの時刻現実化

- `FakeBridgeService` の `createdAt` / `updatedAt` / `deletedAt` / `completedAt` / undo `createdAt` を、2026-07-01 09:00 UTC起点の現実的なepoch millisecondsへ変更した。
- visual QAのTrash/Detailで `1970` 由来の日付が出ないことをafter PNGで確認した。

### ダークテーマpriority dot QA

- `app/test/visual_qa/visual_qa_screenshots_test.dart` に `home_tasks_dark.png` 生成ケースを追加した。
- スクリーンショット: `app/build/visual_qa/home_tasks_dark.png`
- 目視結果: dark背景上でcoral（high）、amber（medium）、softSage（low）のpriority dotがいずれも判別でき、背景に埋もれていない。

### before/afterスクリーンショット

- before: `app/build/visual_qa_before_task_31/`
  - 主確認: `app/build/visual_qa_before_task_31/trash.png`
  - `Deleted: 1970-01-01`、`Priority: Medium`、`2026-07-02` の冗長チップが残っていた。
- after: `app/build/visual_qa/`
  - 主確認: `app/build/visual_qa/trash.png`
  - 追加確認: `app/build/visual_qa/home_tasks_dark.png`, `app/build/visual_qa/task_detail.png`
  - 目視結果: Trash行は `Deleted Jul 1` と `Jul 2` の短縮表示になり、visibleな `Priority:` チップと `1970` 表示は消えた。Task detailにも `1970` 表示はない。

### i18nキーと生成結果

- 変更: `taskDeletedAt`
  - en: `Deleted: {deletedAt}` -> `Deleted {deletedAt}`
  - ja: `削除日時: {deletedAt}` -> `削除 {deletedAt}`
- 追加キーはなし。
- `cd app && flutter gen-l10n` を実行し、`app/lib/src/generated/l10n/` 配下を再生成した。生成物は手編集していない。

### 追加/更新したwidget test

- `visual_qa_screenshots_test.dart`
  - `home_tasks_dark.png` 生成ケースを追加した。
- `widget_test.dart`
  - Trash復元テストで `Deleted:` / `1970` が表示されないことを確認するよう更新した。
  - Trash長文/Dynamic Typeテストで visible な `Priority: Medium` チップではなく `Priority: Medium` tooltipを確認するよう更新した。

### 品質ゲート

- `sh app/tool/visual_qa.sh`: 成功（8 screenshot tests passed）。after PNGを `app/build/visual_qa/` に生成。
- `cd app && flutter analyze`: 成功（No issues found）。
- `cd app && flutter test`: 成功（37 tests passed、visual QA harnessは通常実行ではskip）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git diff --check`: 成功。

### やらなかったことの遵守

- 新機能追加、Focus timer、検索、通知、設定画面、マスコット常駐、bottom navigationは実装していない。
- Rust API / FRB / DB schema / domain / storage / core配下 / cli / mcp-server / server は変更していない。
- 新規pub依存、新規画像アセットは追加していない。
- Lists / Tasks / Task detailの大規模再設計はしていない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。
- `taskveil-private/` と `.github/` は変更していない。
- public repoへprivate側の課金、収益、法務、監査、公開前ロードマップ詳細は転記していない。

### 未解決事項

- なし。
