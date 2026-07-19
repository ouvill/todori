# task-28: visual polish / product UI refinement

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-05

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` のM3では、リストCRUD、タスクCRUD、サブタスク、ゴミ箱・復元、Undo、手動/条件並び替えを実装してMVPのタスク操作を完成させる。task-20〜22でUI foundationとvisual directionが整備され、task-23〜27でTrash、fractional index、Undo、条件ソートUIまで実装済みである。

task-25では、AI生成画像・画像モックをピクセル完全基準にせず、長いタイトル、i18n、Dynamic Type、狭幅、タップ領域、tooltip/semanticsを優先する較正を行った。task-27で表示順切替が入り、実画面の操作密度が固まったため、App Store / README スクリーンショット前に、実データで破綻しない範囲で第一印象をプロダクト品質へ引き上げる段階に入る。

このタスクは新機能追加ではない。Lists / Tasks / Detail / Trash / Dialog / Empty state を、既存のFlutter UI、i18n、アクセシビリティ、widget test、品質ゲートを維持しながら磨き込む。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` M3 / M4 の文脈
- `docs/design/visual-direction.md`
- `docs/tasks/task-20-ui-foundation.md`
- `docs/tasks/task-21-visual-direction.md`
- `docs/tasks/task-22-design-direction-sketch.md`
- `docs/tasks/task-25-design-calibration-ui-pass.md`
- `docs/tasks/task-27-condition-sort-ui.md`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/l10n_test.dart`
- `app/tool/check_hardcoded_strings.sh`

必要に応じて、現在の実装で参照されている `app/lib/src/generated/l10n/` の生成結果も確認する。ただし生成物は手編集しない。

## 3. ゴール

Lists / Tasks / Detail / Trash / Dialog / Empty state を、実データで破綻しないまま、App Store / README スクリーンショット前の第一印象としてプロダクト品質へ引き上げる。

- `docs/design/visual-direction.md` の方針を、既存Flutter UIの実画面へ一貫して反映する。
- タイポグラフィ、余白、surface、border、icon、empty state、dialog、task row、metadata、sort control、restore action、Undo snackbar周辺の見た目と操作感を磨く。
- 長いタイトル、長いリスト名、日本語/英語、i18n、Dynamic Type、狭幅、実データ量、タップ領域、tooltip/semanticsを守る。
- 画像モックの雰囲気は参照するが、ピクセル完全再現や固定レイアウトではなく、実アプリで使える密度と安定性を優先する。
- 新規機能、DB/Rust/FRB/domain/storage変更、新規依存、private詳細の転記は行わない。

## 4. スコープ

### 想定変更ファイル

後続workerは、実装に必要な場合に限り、以下を中心に変更する。実際の差分は受け入れ基準を満たす最小範囲に留める。

- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/` 配下のl10n生成物
- `app/test/widget_test.dart`
- `app/test/l10n_test.dart`
- 必要な場合のみ `docs/design/visual-direction.md` の最小更新
- `docs/tasks/task-28-visual-polish.md`（実装完了時の `## 9. 完了報告` 追記のみ）

### やること

1. **現在画面の実データ前提確認**:
   - Lists / Tasks / Task detail / Trash / Dialog / Empty state を、既存fakeやwidget testのデータ、またはローカル実行データで確認する。
   - 長いリスト名、長いタスクタイトル、長いnote、priority、due date、done/wont_do、subtask、Undo snackbar、条件ソートcontrol、Trash restore actionが同時に出ても破綻しない箇所を優先して直す。
2. **theme / surface / typographyのpolish**:
   - `theme.dart` の既存tokenとMaterial 3 themeを尊重し、deep green / sage / warm white / thin border の方向性を整える。
   - 画面間でAppBar、surface、row、dialog、empty state、chip/pill、buttonの見た目が不必要にばらつく箇所を小さく揃える。
   - 角丸、影、border、背景色は、丸すぎる/重すぎる/一色に寄りすぎる状態を避け、実用密度を保つ。
3. **task row / metadata / sort controlのpolish**:
   - `task_components.dart` を中心に、completion control、priority dot、title、metadata、subtask hierarchy、chevron、手動並び替えbutton、条件ソートcontrol周辺の視覚階層を整える。
   - metadataは折り返し可能なまま維持し、priority/status/due/progressは色だけに依存させない。
   - task-27の表示順切替UIは、狭幅・Dynamic Type・日本語/英語で不自然に重ならず、手動順/条件ソートの違いが分かるようにする。
4. **Lists / Tasks / Detail / Trash画面のpolish**:
   - Lists: 長いリスト名、リスト行、空状態、作成導線が落ち着いて見えるようにする。
   - Tasks: タスク一覧、サブタスク、条件ソート、手動並び替え、Undo snackbar、Trash導線の情報階層を整える。
   - Detail: タイトル、note、metadata、編集dialog、サブタスクセクション、破棄/復元に関わる導線が読みやすいようにする。
   - Trash: 削除済みtaskのmuted表現、削除metadata、restore action、empty/loading/error stateを「戻せる操作画面」として整える。
5. **Dialog / Empty stateのpolish**:
   - `dialogs.dart` と `states.dart` を中心に、確認dialog、入力dialog、空状態、loading/errorの文法を揃える。
   - Empty stateは短い説明と次のactionを優先し、通常画面内で過剰なオンボーディング文や常設マスコットを追加しない。
   - Dialogはscrollable、防御的なbutton wrap、destructive/restore文言、Dynamic Typeでの読みやすさを維持する。
6. **i18n / 文字列管理**:
   - 追加・変更するUI文字列は `app/lib/l10n/app_en.arb` と `app_ja.arb` に追加する。
   - 既存文言で足りる場合は新しいキーを増やしすぎない。
   - ARBを変更した場合は `cd app && flutter gen-l10n` を実行し、生成済みlocalizationsを更新する。
   - `sh app/tool/check_hardcoded_strings.sh` を通す。
7. **アクセシビリティ / 操作性**:
   - icon-only controlにはtooltip/semanticsを維持または追加する。
   - 主要操作は48px級のタップ領域を保つ。小さく見せる場合も実タップ領域を削らない。
   - 色だけで状態を伝えず、text、icon、semanticsで意味が分かるようにする。
8. **破綻確認とテスト**:
   - widget testを追加または更新し、長いタイトル、長いリスト名、日本語/英語、Dynamic Type相当、狭幅、Trash、Dialog、Empty state、条件ソートcontrol、Undo snackbar周辺の破綻を確認する。
   - スクリーンショット確認を行う場合は、対象画面、viewport、locale、text scale、確認結果を完了報告に具体的に記録する。
   - golden testや新規スクリーンショット比較基盤は必須にしない。
9. **デザイン正本の最小更新**:
   - 実装中に `docs/design/visual-direction.md` と実画面の判断がずれた場合だけ、public向けの抽象化済みルールとして最小更新する。
   - private詳細、公開前ロードマップ、課金、収益、法務、監査の詳細は追加しない。

### やらないこと

- 新機能を追加しない。
- 検索、通知、Keychain、オンボーディング、タイマー、Pomodoro、Focus timer、マスコット常駐、AIパネル、設定画面を実装しない。
- 新しい画面、route、bottom navigation、account/sync/billing/legal/audit/roadmap surfaceを追加しない。
- Rust API、FRB定義/生成物、DB schema、domain usecase、storage repositoryを変更しない。
- `core/`、`app/rust/`、`app/rust_builder/`、`cli/`、`mcp-server/`、`server/` を変更しない。
- 新規pub依存、Rust crate、UI framework、icon package、画像処理ライブラリ、golden/screenshot比較基盤を追加しない。
- `sort_order`、Undo履歴、条件ソート状態、永続設定、DB保存方針を変更しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `taskveil-private/` 配下を読んだり変更したりしない。
- `.github/` 配下を変更しない。
- public repoにprivate側の課金、収益、法務、監査、公開前ロードマップ詳細を転記しない。
- 画像モックをピクセル単位で再現しない。
- 新しいAI生成画像、画像モック、Figma相当成果物を追加しない。

## 5. 実装手順（例）

1. `git -C taskveil status --short` で作業ツリーを確認し、無関係な差分があれば触らない。
2. 2章のファイルを読み、task-20〜22のUI foundation / visual direction、task-25の較正方針、task-27後の条件ソートUIを把握する。
3. Lists / Tasks / Detail / Trash / Dialog / Empty state を、長いtitle、長いlist name、subtask、priority、due date、Undo、条件ソート、Trash restoreの観点で確認し、最小のpolish対象を決める。
4. `theme.dart`、`task_components.dart`、`states.dart`、`dialogs.dart` の既存部品で直せるものを優先して調整する。
5. 必要な場合だけ、`lists_screen.dart`、`tasks_screen.dart`、`task_detail_screen.dart`、`trash_screen.dart` の画面側を調整する。
6. UI文字列を変更した場合はARBへ反映し、`cd app && flutter gen-l10n` を実行する。
7. widget testを追加または更新し、長文、i18n、Dynamic Type、狭幅、主要画面、Dialog、Empty state、条件ソート、Trash restoreを検証する。
8. 必要な場合だけ `docs/design/visual-direction.md` を最小更新する。
9. 品質ゲートを実行する。
10. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] Lists / Tasks / Task detail / Trash / Dialog / Empty state の第一印象が、`docs/design/visual-direction.md` のdeep green / sage / warm white / thin border / quiet task-first UI方針に沿って整理されている。
- [ ] 変更はFlutter UI中心であり、4章の想定変更ファイルを中心とする最小範囲に収まっている。
- [ ] `theme.dart` の色、surface、border、typography、button/chip/dialog/list系themeが、画面間で不必要にばらつかない。
- [ ] paletteが緑一色の画面になっておらず、warm white、neutral text、小さなcoral/amber等のaccentが必要範囲で使われている。
- [ ] 過剰なshadow、gradient、decorative blob、card-in-card、広告モック風hero、常設マスコットが追加されていない。
- [ ] Lists画面で、長いリスト名、空状態、作成導線、リスト行のtap領域が破綻しない。
- [ ] Tasks画面で、長いタスクタイトル、priority dot、metadata、subtask hierarchy、condition sort control、手動並び替えbutton、Undo snackbar、Trash導線が不自然に重ならない。
- [ ] Task detail画面で、長いtitle、長いnote、metadata、編集dialog、サブタスクセクション、主要actionが読みやすい。
- [ ] Trash画面で、削除済みtask title、削除metadata、restore action、empty/loading/error stateが「戻せる操作画面」として明確である。
- [ ] Dialogは長い日本語/英語文言とDynamic Typeで本文・入力欄・buttonが押し潰されず、必要に応じてscroll/wrap/縦積みされる。
- [ ] Empty stateは短く、次のactionが分かり、通常画面内でオンボーディングやマスコット常駐に広がっていない。
- [ ] 日本語/英語localeで、主要画面の文言が欠けたりbutton内で不自然に切れたりしない。
- [ ] Dynamic Type相当の大きい文字で、row、metadata、dialog、empty state、sort control、restore actionが潰れない。
- [ ] 狭幅viewportで、checkbox、priority dot、metadata、sort control、manual reorder button、restore action、chevronが互いに重ならない。
- [ ] 主要操作のタップ領域が48px級に保たれている。
- [ ] icon-only controlにはtooltip/semanticsがある。
- [ ] priority/status/due/progress/sort mode/restoreなどの意味が色だけに依存せず、text/icon/semanticsでも分かる。
- [ ] 追加・変更UI文字列がen/ja ARB化され、ARB変更時は生成済みlocalizationsが更新されている。
- [ ] `app/lib/src/generated/l10n/` 配下は `flutter gen-l10n` による生成差分のみで、手編集されていない。
- [ ] widget testまたはスクリーンショット確認で、Lists / Tasks / Task detail / Trash / Dialog / Empty state の破綻確認が記録されている。
- [ ] widget testまたはスクリーンショット確認で、長いタイトル、日本語/英語、Dynamic Type相当、狭幅、条件ソートcontrol、Undo snackbar、Trash restore actionの確認が記録されている。
- [ ] 既存widget testのタスク作成、編集、サブタスク、ゴミ箱/復元、Undo、手動並び替え、条件ソートの期待が引き続き通る。
- [ ] 新機能、検索、通知、Keychain、オンボーディング、タイマー、マスコット常駐、設定画面が追加されていない。
- [ ] 新規依存、UI framework、icon package、画像モック、golden/screenshot比較基盤が追加されていない。
- [ ] Rust API、FRB定義/生成物、DB schema、domain usecase、storage repositoryに変更が入っていない。
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [ ] `taskveil-private/` と `.github/` が変更されていない。
- [ ] public repoにprivate詳細が転記されていない。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `git diff --check` が成功している。
- [ ] `docs/tasks/task-28-visual-polish.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクはvisual polishであり、新機能開発ではない。
- App Store / README スクリーンショット前の第一印象を上げることが目的だが、スクリーンショット専用の固定レイアウトや実データで壊れる装飾を作らない。
- `docs/design/visual-direction.md` はpublic repoのデザイン正本である。更新する場合は公開可能な抽象化済み内容に限る。
- task-20のUI foundation、task-25の較正方針、task-27の条件ソートUIを尊重し、既存の操作導線とテスト期待を壊さない。
- UI文字列は必ずARB化する。`Text('...')`、`Tooltip(message: '...')` などの直書きを残さない。
- `flutter_rust_bridge` は `2.12.0` 固定であり、Rust側crateとDart側pubのバージョン一致を崩さない。
- 秘密情報、Device Key、SQLCipher鍵、DB鍵を表示・ログ・Debug出力に含めない。
- `docs/01〜03` は変更禁止である。仕様と実装の矛盾を見つけた場合は、仕様書を書き換えず完了報告の未解決事項に記録する。
- public repoにprivate repoの課金、収益、法務、監査、公開前ロードマップ詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- 実データ前提で確認した画面と状態
- App Store / README スクリーンショット前の第一印象として改善した点
- 変更したUI foundationファイル
- `ThemeData` / color / surface / border / typography / spacing / icon / chip / dialog / empty stateの調整内容
- Lists / Tasks / Task detail / Trash / Dialog / Empty state ごとのpolish内容
- 条件ソートcontrol、手動並び替えbutton、Undo snackbar、Trash restore actionへの影響
- 長いタイトル、長いリスト名、日本語/英語、i18n、Dynamic Type、狭幅への対応内容
- タップ領域、tooltip/semantics、色以外の情報伝達で維持・改善した点
- 追加/変更したi18nキー
- `flutter gen-l10n` の実行結果（ARBを変更した場合）
- 追加/更新したwidget test、またはスクリーンショット確認の対象、viewport、locale、text scale、結果
- 品質ゲート6点、`check_hardcoded_strings.sh`、`git diff --check` の実行結果
- やらなかったことが守られていること（新機能なし、検索/通知/Keychain/オンボーディング/タイマー/マスコット常駐/設定画面なし、新規依存なし、Rust/FRB/DB/domain/storage変更なし）
- `docs/design/visual-direction.md` を更新した場合は、その内容と理由
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
- `docs/07_Phase1計画書.md`（M3/M4関連）
- `docs/design/visual-direction.md`
- `docs/tasks/task-20-ui-foundation.md`
- `docs/tasks/task-21-visual-direction.md`
- `docs/tasks/task-22-design-direction-sketch.md`
- `docs/tasks/task-25-design-calibration-ui-pass.md`
- `docs/tasks/task-27-condition-sort-ui.md`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/l10n_test.dart`
- `app/tool/check_hardcoded_strings.sh`

### 実データ前提で確認した画面と状態

- Lists: 長い日本語+英語リスト名、空状態、作成dialog。
- Tasks: 長い日本語+英語タスクタイトル、priority、due date、metadata、サブタスク階層、手動並び替えbutton、条件ソートmenu、Undo snackbar。
- Task detail: 長いtitle、長いnote、metadata、local protection signal、編集dialog、subtask section、trash action。
- Trash: 長い削除済みtask title、削除metadata、priority/due metadata、restore action、empty state。
- Dialog / Empty state: 狭幅320px相当、text scale 1.6相当、長い英日文言で例外が出ないこと。

### 改善した点

- `ThemeData` にdialog、popup menu、snackbar、button系themeを追加し、warm white surface、thin border、deep green、coral error accentの文法を画面間で揃えた。
- Lists行をcustom rowへ変更し、48px級の先頭icon/chevron領域と折り返しtitleを持つ落ち着いたsurfaceにした。
- `AppTaskRow` は完了済みrowのsurface/borderを少しmutedにし、metadata pillを軽くして、状態が色だけに寄りすぎないよう既存text/icon/semanticsを維持した。
- `AppEmptyState` は短い文言のまま、scrollableな小さなsurfaceへ収め、狭幅/Dynamic Typeで押し潰されにくくした。
- `dialogs.dart` と編集dialogのactionsをWrap化し、長いbutton labelや大きい文字で横に潰れにくくした。
- Tasksのsort menuは選択中iconを `check_circle_outline` にし、長いlabelをwrap可能にした。
- Task detailのnoteを読みやすいbody styleへ調整し、local protection signalも狭幅でwrapできるようにした。
- Trash rowは復元可能な操作画面として、restore系iconを淡いsurface上のprimary色で見せるようにした。
- Undo snackbarはfloating + margin付きにし、画面端に張り付かない落ち着いた表示へ寄せた。

### 変更したUI foundation / screenファイル

- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/test/widget_test.dart`

### 条件ソート / 手動並び替え / Undo / Restoreへの影響

- 条件ソートは表示順切替のみを維持し、`sort_order`、provider、task tree、永続化仕様は変更していない。
- 手動並び替えbuttonは既存tooltip/key/動作を維持し、狭幅では既存どおり下段へ逃がす。
- Undo snackbarの文言・action・履歴適用処理は変更せず、見た目だけをtheme/marginで調整した。
- Trash restore actionのtooltip/semantics/key/復元処理は変更せず、行surfaceとicon表現だけを調整した。

### i18n / l10n

- UI文字列の追加・変更なし。
- ARB変更なしのため `flutter gen-l10n` は不要。
- `app/lib/src/generated/l10n/` は変更していない。

### 追加/更新したwidget test

- `polished list, sort, detail, and dialog surfaces stay stable` を追加。
  - viewport: 320x640相当。
  - text scale: 1.6相当。
  - locale: default English UI内で日本語+英語の実データ文字列を投入。
  - 確認対象: 長いlist name、長いtask title、長いnote、priority/due metadata、sort menu、Task detail、edit dialog。
- 既存 `long task titles survive narrow width and Dynamic Type` を、縦に伸びた実画面をscrollして操作する確認へ更新。
- Flutter widget/l10n/core usecase testsは全37件成功。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（Rust 74 tests）。
- `cd app && flutter analyze`: 成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test`: 成功（Flutter 37 tests）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git diff --check`: 成功。
- 補足: 初回の `dart format` / `flutter analyze` / `flutter test` はFlutter SDK cache書き込みがサンドボックスで拒否されたため失敗。承認付き再実行では成功しており、コード起因の失敗ではない。

### やらなかったこと / 境界確認

- 新機能、検索、通知、Keychain、オンボーディング、タイマー、マスコット常駐、設定画面は追加していない。
- 新規依存、UI framework、icon package、画像モック、golden/screenshot比較基盤は追加していない。
- Rust API、FRB定義/生成物、DB schema、domain usecase、storage repositoryは変更していない。
- `app/lib/src/core/providers.dart` / `app/lib/src/core/task_tree.dart` は変更していない。
- `docs/design/visual-direction.md` は更新していない。既存方針内の実装調整で足りたため。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。
- `taskveil-private/` と `.github/` は読まず、変更していない。
- public repoにprivate詳細（課金、収益、法務、監査、公開前ロードマップ等）は転記していない。

### 未解決事項・要人間判断

- なし。

### 独立検証後の状態同期修正

- 検証指摘を受け、`docs/tasks/README.md` のtask-28行を `完了` に更新した。
- `docs/tasks/BACKLOG.md` の現在地へtask-28完了済みを追記し、優先度付きバックログからtask-28を削除して残タスクの番号を詰めた。
- コード、Flutter UIファイル、private repo、`.github/` は変更していない。

### 目視QA追記（2026-07-05）

- `test/visual_qa_screenshots_test.dart` を一時的に作成し、Lists / Empty state / Tasks / Task detail / Edit dialog / Trash のmobile幅スクリーンショットを生成して確認した。
- Flutter widget test標準のAhemフォントでは文字が黒い矩形になるため、目視QA用テストではmacOS実フォントとMaterial Iconsを読み込んで撮影した。
- 目視確認の結果、Lists / Empty state / Detail / Trashは概ね方向性に沿っていたが、FABの影が黒く重く、Tasks画面の手動並び替え矢印が強く見えた。
- `app/lib/src/ui/theme.dart` でFABのelevationを抑え、`app/lib/src/screens/tasks_screen.dart` で手動並び替えbuttonとchevronの視覚トーンを落とした。
- 目視QA用の一時テストと生成PNGはコミット対象にしない。
- 追記後の検証: `flutter analyze` 成功、`flutter test` 成功（37 tests）、`sh app/tool/check_hardcoded_strings.sh` 成功、`git diff --check` 成功。
- 補足: Flutter系コマンドの通常サンドボックス実行はSDK cache書き込みで失敗したため、承認付き再実行で確認した。コード起因の失敗ではない。
