# task-66: アクセシビリティ検証パス（M4-03）

> ステータス: 完了（2026-07-08）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

Phase 1計画書のM4-03は、Dynamic Type、スクリーンリーダーラベル、コントラストの確認項目が通ることを完了条件としている。TaskveilはHome中心のタスク一覧、詳細画面、リスト管理、ボトムシート、スワイプ、D&D、チップ類を持つため、見た目のpolish完了後にアクセシビリティの横断検証を行う必要がある。

本タスクは検証パスであり、視覚デザイン変更は行わない。修正はa11y属性、Semantics、Tooltip、タップ領域に限定する。色コントラスト不足が見つかった場合も、このタスクでは色調整せず、計算結果と要人間判断として完了報告へ記録する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` M4-03
- `docs/design/ui-spec.md`
- `app/lib/src/screens/home_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`

## 3. ゴール

- 全画面のicon-only controlについて、Tooltipまたは同等のSemanticsが不足していないことを棚卸しし、欠落を修正する。
- タスク行、チェックボックス、スワイプアクション、D&D、シート、チップ類の読み上げが意味を成す状態にする。
- text scale 2.0相当で主要画面が破綻しないことをwidget testまたはvisual QAで確認する。
- `docs/design/ui-spec.md` と実装トークンの主要色組み合わせについてWCAG AAコントラスト比を計算し、結果を完了報告に表で残す。
- Reduce Motion分岐の実装箇所とテスト証跡を確認し、未網羅があれば完了報告に記録する。
- macOS VoiceOverの人間実行用手動確認手順を完了報告に残す。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/` 配下
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-66-a11y-pass.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. 作業前に `app/build/visual_qa/` をタスク用のbeforeディレクトリへ退避する。
2. Home、Tasks、Lists、Task detail、ボトムシート、ダイアログ、メニュー、スワイプ、D&Dのicon-only controlを棚卸しする。
3. 欠落しているTooltip/Semanticsを追加する。UI文字列はARB化し、生成物は `flutter gen-l10n` で更新する。
4. タスク行のSemanticsに、状態、優先度、期日、リスト名または親タスク名、サブタスク文脈、開く操作が伝わるか確認し、必要なら補強する。
5. チェックボックス、スワイプアクション、D&D reorder semantics、シート、チップ類の読み上げをwidget testで検証する。
6. visual QAにtext scale 2.0相当の主要画面スクリーンショットを追加し、生成結果を目視する。
7. theme/ui-specの主要色組み合わせをWCAG AAで計算し、AA合否と未解決事項を完了報告へ記録する。
8. Reduce Motion分岐の既存テストと実装を確認する。不足がある場合は、このタスクの制約内で直せるものだけ直し、残りは未解決事項へ送る。
9. 品質ゲートを実行し、実行不能なものは環境起因を明記する。

### やらないこと

- 視覚デザイン、色、余白、角丸、タイポグラフィ、モーション演出の見た目変更。
- WCAG不足を解消するための色調整。計算結果を要人間判断として記録する。
- 新しい依存追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` の変更。
- git commit。

## 5. 実装手順（例）

1. `git status --short` で作業前状態を確認する。
2. `app/build/visual_qa/` を `app/build/visual_qa_before_task66_<timestamp>/` へ退避する。
3. `docs/07_Phase1計画書.md` M4-03、`docs/design/ui-spec.md`、主要画面実装を読む。
4. `IconButton`、`PopupMenuButton`、`SlidableAction`、チップ、カスタムInkWell、ドラッグ対象を検索し、Tooltip/Semanticsの有無を棚卸しする。
5. 不足箇所を最小差分で修正する。見た目の変更を伴う修正は行わない。
6. `flutter gen-l10n` を実行する。
7. semantics matcherを使うwidget testを追加する。
8. visual QAのtext scale 2.0ケースを追加し、`sh app/tool/visual_qa.sh` を実行する。
9. コントラスト計算スクリプトまたは手計算を実行し、結果表を作る。
10. 品質ゲートを実行する。
11. 本ファイルへ `## 9. 完了報告` を追記し、README/BACKLOGを更新する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 全画面のicon-only controlについてTooltip/Semantics棚卸し結果と修正した欠落一覧が完了報告に記録されている。
- [ ] タスク行、チェックボックス、スワイプアクション、D&D、シート、チップ類のSemanticsが主要widget testで検証されている。
- [ ] タスク行の読み上げに状態、優先度、期日、親コンテキストまたはリスト名、開く操作が含まれる。
- [ ] text scale 2.0相当の主要visual QAスクリーンショットが生成され、破綻有無が完了報告に記録されている。
- [ ] ui-spec/theme主要色組み合わせのWCAG AAコントラスト計算表が完了報告に記録され、不足は要人間判断として扱われている。
- [ ] Reduce Motion分岐の実装箇所とテスト証跡が完了報告に記録されている。
- [ ] macOS VoiceOver手動確認手順が人間実行用に完了報告へ記録されている。
- [ ] `flutter analyze`、`flutter test`、Rust品質ゲート、直書き検出、visual QAの結果が完了報告に記録されている。

## 7. 制約・注意事項

- 修正はa11y属性、Semantics、Tooltip、タップ領域に限定する。視覚デザイン変更は禁止する。
- UI文字列を追加する場合は必ず `app/lib/l10n/app_en.arb` と `app_ja.arb` に追加し、生成物を更新する。
- 既存FRB生成物はRust APIを変更しない限り触らない。
- スクリーンリーダー用ラベルは内部値（`todo`、`wont_do`など）ではなく、既存のl10n表示名を使う。
- 色だけに依存する意味（期限超過、優先度など）はSemanticsにも含める。
- コントラスト不足の修正はこのタスクでは行わず、完了報告の未解決事項へ送る。
- Dynamic Type検証で見つかった破綻がa11y属性だけで解消できない場合は、見た目を変えずに直せる範囲を超えるため未解決事項へ記録する。

## 8. 完了報告に含めるべき内容

- 作業日、読んだファイル
- 作業前visual QA退避先
- icon-only control棚卸し結果
- 修正した欠落一覧
- 追加・更新したSemantics/Tooltip/l10nキー
- 追加・更新したwidget test名と検証対象
- text scale 2.0 visual QAスクリーンショットのパスと目視結果
- コントラスト計算表（組み合わせ、前景、背景、比率、AA判定）
- Reduce Motion分岐の確認結果
- macOS VoiceOver手動確認手順
- 品質ゲート実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

- 作業日: 2026-07-08
- 読んだファイル: `docs/07_Phase1計画書.md` M4-03、`docs/design/ui-spec.md`、`app/lib/src/screens/home_screen.dart`、`app/lib/src/screens/tasks_screen.dart`、`app/lib/src/screens/lists_screen.dart`、`app/lib/src/screens/task_detail_screen.dart`、`app/lib/src/ui/task_components.dart`、`app/lib/src/ui/theme.dart`、`app/test/widget_test.dart`、`app/test/visual_qa/visual_qa_screenshots_test.dart`
- 作業前visual QA退避先: `app/build/visual_qa_before_task66_20260708074843`

icon-only control棚卸し:

- Home header: Lists `IconButton.filledTonal` と sort `PopupMenuButton` は既存tooltipあり。
- Tasks app bar: list actions / sort `PopupMenuButton` は既存tooltipあり。
- Lists: back `IconButton` はMaterial back tooltipあり。Home行は既存tooltip/semanticsあり。通常リスト行は純ナビゲーション行としてテキスト読み上げあり。
- Task detail: overflow menu、親リンク、clear due/reminder icon buttonsは既存tooltipあり。
- Task row: checkboxは既存tooltip/checked semanticsあり。D&Dは既存 `CustomSemanticsAction`（Move task up/down）あり。スワイプアクションは表示ラベルあり。
- ボトムシート/チップ: Dueチップの現在値読み上げと、詳細チップのbutton semanticsが弱かったため補強した。

修正した欠落一覧:

- `AppHomeTaskRow` / `AppTaskRow` に行要約Semanticsを追加し、状態、優先度、期日、リスト名または親タスク名、サブタスク階層、開く操作を読み上げ対象にした。
- タスク行Semanticsは `explicitChildNodes: true` にし、子のチェックボックスやチップの意味を潰さないようにした。
- タスク作成シートのDueチップに `Due date: <value>` / `期限日: <value>` のSemanticsを追加した。
- 詳細画面のタップ可能な `_DetailPill` にbutton/enabled semanticsを付け、期日・リマインダーチップ等が操作可能だと伝わるようにした。
- 既存の親コンテキストsemanticsテストは、行要約にも親文脈が含まれるため複数ノード存在を許容する期待値へ更新した。

追加・更新したl10nキー:

- `taskCreateDueChipSemantics`
- `taskRowStatusSemantics`
- `taskRowDueSemantics`
- `taskRowListSemantics`
- `taskRowSubtaskLevelSemantics`
- `taskRowOpenHint`

追加・更新したテスト:

- `home task rows expose meaningful semantics summaries`: Homeタスク行にタイトル、状態、優先度、期日、開く操作が含まれることをSemantics matcherで確認。
- `task checkbox exposes button and checked semantics`: チェックボックス単体がbutton + checked semanticsを持つことを確認。
- `task creation sheet chips expose current semantic values`: 作成シートDueチップの現在値Semanticsを確認。
- 既存D&D tests: `subtask semantics reorder keeps the same parent and depth` 等でMove up/down custom semantics継続を確認。

Dynamic Type / visual QA:

- 追加スクリーンショット:
  - `app/build/visual_qa/home_tasks_text_scale_2.png`
  - `app/build/visual_qa/task_create_sheet_home_text_scale_2.png`
  - `app/build/visual_qa/lists_text_scale_2.png`
  - `app/build/visual_qa/task_detail_text_scale_2.png`
- 目視結果: text scale 2.0で大きく折り返すが、Home、Lists、Task detail、作成シートの主要操作は表示され、明確な重なり崩壊はなし。作成シートのチップ列は横スクロール前提で右端が画面外へ続くが、既存仕様の横スクロール領域内の挙動として許容した。

コントラスト計算表（WCAG 2.x、通常文字AA=4.5:1、large/UI=3:1）:

| 組み合わせ | 前景 | 背景 | 比率 | 判定 |
|---|---:|---:|---:|---|
| primary text on surface | `#2F6F4E` | `#FFFCF7` | 5.85 | AA |
| primary text on surfaceContainer | `#2F6F4E` | `#F2F7EF` | 5.51 | AA |
| onPrimary on primary | `#FFFFFF` | `#2F6F4E` | 5.99 | AA |
| onPrimaryContainer on primaryContainer | `#163B28` | `#DDEBDD` | 10.06 | AA |
| coral text on surface | `#E8755A` | `#FFFCF7` | 2.88 | 不足 |
| amber text on surface | `#EDB73E` | `#FFFCF7` | 1.79 | 不足 |
| low priority dot on surface | `#A8BEA8` | `#FFFCF7` | 1.94 | 不足 |
| outlineVariant on surface | `#D9E3D6` | `#FFFCF7` | 1.29 | 不足 |
| overdue due pill | `#E8755A` | `#FCE9E1` | 2.51 | 不足 |
| future due pill | `#EDB73E` | `#FCF0D6` | 1.62 | 不足 |
| today due pill | `#2F6F4E` | `#E8ECE2` | 5.00 | AA |
| muted due pill | `#6B7069` | `#ECEAE5` | 4.21 | large/UIのみAA |
| metadata pill primary | `#2F6F4E` | `#F6F8F1` | 5.60 | AA |
| overdue metadata coral | `#E8755A` | `#F6F8F1` | 2.75 | 不足 |
| snackbar text | `#FFFFFF` | `#24382D` | 12.51 | AA |
| snackbar action | `#F6E7B7` | `#24382D` | 10.15 | AA |

不足箇所の扱い:

- coral/amber/softSage dot/outlineは、ui-spec上のブランド・状態色として既存採用されている。色調整は本タスク範囲外のため未変更。
- priority dotはSemanticsで優先度を補足しているが、非テキストコントラストとしては不足する。要人間判断。
- overdue/future pillのcoral/amber文字は通常文字AA不足。色調整または文法変更が必要か要人間判断。
- outlineVariantは装飾線/区切り線として使用。UIコンポーネント境界としてAA 3:1を求めるかは要人間判断。

Reduce Motion確認:

- `AppTaskCheckbox` は `MediaQuery.disableAnimationsOf(context)` でチェック描画durationをゼロ化し、パーティクルを無効化する。
- `AppAnimatedTaskTitle` はReduce Motion時に取り消し線伸長を無効化する。
- Home完了処理は `MediaQuery.disableAnimationsOf(context)` 時にpending遅延退場を作らず即時再構成する。
- 既存テスト `completion motion is skipped when reduce motion is enabled`、`home reduce motion completion reconfigures immediately` が通過。
- `AnimatedSize` 等の汎用軽量アニメーションは残る。今回の制約（a11y属性・semantics・タップ領域限定）外のため未変更。

macOS VoiceOver手動確認手順（人間実行用）:

1. `cd app && flutter build macos --debug` を実行する。
2. `open build/macos/Build/Products/Debug/taskveil.app` で起動する。
3. macOSでVoiceOverを有効化する（`Command + F5`）。
4. Homeで `VO + Right` を使い、ヘッダー、Overdue/Today/Tomorrow/Upcoming見出し、タスク行、チェックボックス、クイック追加バーを順に読む。
5. タスク行がタイトル、状態、優先度、期日、リスト名または親タスク名、開く操作を含むことを確認する。
6. チェックボックスで `VO + Space` を押し、完了/再オープンが実行でき、状態読み上げが変わることを確認する。
7. 通常リストで手動順に切り替え、D&D対象行にMove up/down相当の操作が出ることを確認する。
8. クイック追加バーを開き、List/DueチップとAdd taskボタンを読み、Dueチップが現在値を含むことを確認する。
9. Task detailでタイトル、ノート、期日、優先度、リマインダー、サブタスク行、overflow menu、clear buttonsを読む。
10. 文字サイズをmacOSアクセシビリティ設定で大きくした状態でも、主要操作へ到達できることを確認する。

品質ゲート:

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（taskveil_app_bridgeのreal Keychain ignored 1件は既存どおり）。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter analyze`: 成功。
- `cd app && flutter test`: 成功（114 passed、visual QA harness 1 skipped）。並列実行時にiOS ephemeral再生成と競合したため、`app/ios/Flutter/ephemeral/Packages/.packages` を一度 `/private/tmp/taskveil_ios_ephemeral_packages_task66` へ退避し、単独再実行で成功。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `cd app && sh tool/visual_qa.sh`: 成功（41 tests）。

変更ファイル:

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/app_localizations*.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-66-a11y-pass.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

未解決事項:

- coral/amber/softSage dot/outline系のコントラスト不足は要人間判断。色調整するとui-specトークン変更を伴うため、本タスクでは未変更。
- `AnimatedSize` 等の汎用軽量アニメーションに対するReduce Motion完全網羅は未実施。チェック完了モーションとHome完了再構成の主要分岐は検証済み。
