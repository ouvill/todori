# task-25: design calibration UI pass

> ステータス: 実装完了（親検証待ち・`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-05

## 1. 背景とコンテキスト

task-20でUI foundationが整備され、task-21で最初の参考画像の視覚方向性が既存Flutter UIへ反映され、task-22で `docs/design/visual-direction.md` と複数の画像モックが作成された。その後、task-23でゴミ箱画面・復元UI、task-24でfractional indexとタスク手動並び替えUIが追加され、実画面の情報量と操作導線が増えている。

一方、AI生成画像や画像モックのvisual directionに完全追従すると、実アプリUIとしての密度、長いタイトル、i18n、Dynamic Type、狭い画面、タップ領域、tooltip/semantics、既存操作との整合が崩れる可能性がある。画像はTodoriらしさを共有する参照素材であり、実装正解やピクセル完全基準ではない。

このタスクでは、新しいモックや新機能を追加せず、既存Flutter UIを小さく較正する。目的は、`docs/design/visual-direction.md` の方向性と、既に動いているLists / Tasks / Task detail / Trash / Empty state / Dialog / task-24の並び替えUIを、実アプリとして継続利用できる密度と操作性へ揃えることである。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/task-20-ui-foundation.md`
- `docs/tasks/task-21-visual-direction.md`
- `docs/tasks/task-22-design-direction-sketch.md`
- `docs/tasks/task-23-trash-restore-ui.md`
- `docs/tasks/task-24-fractional-index.md`
- `docs/design/visual-direction.md`
- `app/lib/main.dart`
- `app/lib/src/router.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/l10n_test.dart`
- `app/tool/check_hardcoded_strings.sh`

必要に応じて、現在の実装で参照されている `app/lib/src/generated/l10n/` の生成結果も確認する。ただし生成物は手編集しない。

## 3. ゴール

AI生成画像や画像モックの方向性を、既存Flutter UIの実画面として破綻しない形へ較正する。

- `docs/design/visual-direction.md` を、画像へのピクセル追従ではなく「採用する要素 / 採用しない要素 / 実アプリで優先する判断」に使える文書へ必要最小限強化する。
- Lists / Tasks / Task detail / Trash / Empty state / Dialog / task-24の並び替えUIを、既存UI foundationに沿って小さく調整する。
- 実画面の情報密度、長いタイトル、日本語/i18n、Dynamic Type、狭い画面、タップ領域、tooltip/semanticsを優先して、画像モック由来の過剰な余白・角丸・装飾・常設要素を抑制する。
- 新規機能や新しい画像モックを追加せず、後続のUndoや条件ソートUIへ進める前のUI判断基準を整える。

## 4. スコープ

### やること

1. **デザイン正本の較正**:
   - `docs/design/visual-direction.md` の既存方針を読み、必要なら文言を強化する。
   - AI生成画像・画像モックは参照素材であり、実装正解・ピクセル完全基準ではないことを明確にする。
   - 採用する要素、採用しない要素、実アプリ優先で調整する判断基準を、後続実装者が読んで判断できる形にする。
   - 既にある画像リンクやpublic向けの抽象化済み方針は維持し、private詳細を追加しない。
2. **既存実画面の小さな較正**:
   - 対象候補は既存画面中心とする: Lists、Tasks、Task detail、Trash、Empty state、Dialog、task-24で追加された並び替えUI。
   - `app/lib/src/ui/theme.dart`、`task_components.dart`、`states.dart`、`dialogs.dart` など既存UI foundationを優先して使う。
   - 画像モックの雰囲気より、実画面の読みやすさ、操作しやすさ、反復利用時の密度を優先する。
   - 調整は色、surface、border、radius、spacing、row density、metadata wrapping、icon button配置、dialog文法など、既存UIの範囲に留める。
3. **長いタイトル・狭い画面・Dynamic Typeの防御**:
   - 長いタスク名、長いリスト名、日本語文言、英語文言、Dynamic Typeで、row、metadata、dialog button、empty state、並び替えボタンが潰れないようにする。
   - 固定heightでテキストを潰す実装を避け、必要に応じてwrap、Flexible、Expanded、縦積み、幅制約を使う。
   - mobile幅でタイトル、metadata、checkbox、priority dot、上/下移動、restore action、chevronが互いに押し潰さないようにする。
4. **タップ領域とアクセシビリティ**:
   - icon-only controlにはtooltip/semanticsを維持または追加する。
   - 上/下移動、復元、削除、詳細遷移、作成、確認dialogの主要操作は、誤タップしにくいタップ領域を保つ。
   - priority/status/due/progressなどは色だけで伝えず、text/semanticsを維持する。
5. **i18n維持**:
   - 追加・変更するUI文字列は `app/lib/l10n/app_en.arb` と `app_ja.arb` に追加する。
   - 既存文言で足りる場合は新しいキーを増やしすぎない。
   - ARBを変更した場合は `cd app && flutter gen-l10n` を実行し、生成済みlocalizationsを更新する。
   - `sh app/tool/check_hardcoded_strings.sh` を通す。
6. **破綻確認**:
   - widget test、または実機/Simulator/desktopのスクリーンショット確認で、少なくとも狭い幅、長いタイトル、日本語/i18n、Dynamic Type相当、Trash、並び替えUI、dialog/empty stateが破綻しないことを確認する。
   - 既存widget testを活かし、必要なら長いタイトルや並び替えUIの検証を追加する。
   - golden testや新規スクリーンショット比較基盤は必須にしない。

### やらないこと

- 新しいAI生成画像、画像モック、Figma相当成果物を追加しない。
- AI生成画像をピクセル単位で再現しない。
- 新規機能を追加しない。
- Undoは実装しない。
- 条件ソートUI、締切/優先度/作成順ソート切替、設定保存は実装しない。
- 検索、通知、Keychain、オンボーディング、タイマー、Focus timer、Pomodoro、マスコット常駐、AIパネル、設定画面は実装しない。
- persistent lock/encryption mark、常設マスコット、bottom navigationを追加しない。
- 新規pub依存、UIフレームワーク、icon package、画像処理ライブラリを追加しない。
- Rust API、FRB定義/生成物、DB schema、domain usecase、storage repositoryを変更しない。
- 既存routeや状態管理を大規模に作り直さない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `todori-private/` 配下を読んだり変更したりしない。public repoにprivate側の課金、収益、法務、監査、公開前ロードマップ詳細を転記しない。

## 5. 実装手順（例）

1. `git -C todori status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、task-20〜24で追加されたUI foundation、visual direction、Trash、並び替えUIを把握する。
3. `docs/design/visual-direction.md` のうち、画像追従と実アプリ判断の境界が曖昧な箇所を洗い出す。
4. `docs/design/visual-direction.md` を必要最小限更新し、AI画像から採用する要素 / 捨てる要素 / 実アプリ優先の判断を明文化する。
5. Lists / Tasks / Task detail / Trash / Empty state / Dialog / 並び替えUIを実機能画面として確認し、密度、長いタイトル、i18n、Dynamic Type、狭い画面、タップ領域、tooltip/semanticsの観点で小さく調整する。
6. UI文字列を変更した場合はARBへ反映し、`cd app && flutter gen-l10n` を実行する。
7. widget testを更新または追加し、長いタイトル、Trash、並び替えUI、dialog/empty state、tooltip/semanticsが壊れていないことを確認する。スクリーンショットで確認する場合は、確認対象と結果を完了報告に具体的に記録する。
8. 品質ゲートを実行する。
9. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] `docs/design/visual-direction.md` に、AI生成画像・画像モックは参照素材であり、実装正解・ピクセル完全基準ではないことが明記または強化されている。
- [ ] `docs/design/visual-direction.md` に、採用する要素 / 採用しない要素 / 実アプリ優先で調整する判断基準が、後続実装者に分かる形で整理されている。
- [ ] Lists / Tasks / Task detail / Trash / Empty state / Dialog / task-24の並び替えUIのうち、実画面として必要な較正が既存UI foundationに沿って行われている。
- [ ] 画面調整は既存の `theme.dart` / `task_components.dart` / `states.dart` / `dialogs.dart` などの範囲を優先し、大規模なUI構造変更になっていない。
- [ ] 新規pub依存、UIフレームワーク、icon packageが追加されていない。
- [ ] 新しい画像モック、常設マスコット、persistent lock/encryption mark、bottom navigationが追加されていない。
- [ ] Undo、条件ソートUI、検索、通知、Keychain、オンボーディング、タイマー、マスコット常駐は実装されていない。
- [ ] 長いタスクタイトル、長いリスト名、日本語/i18n文言でrow、metadata、dialog、empty stateが破綻しない。
- [ ] Dynamic Type相当の大きい文字で、タイトルやbutton/chip文言が潰れず、必要に応じてwrapまたは縦積みされる。
- [ ] 狭い画面幅で、checkbox、priority dot、metadata、上/下移動ボタン、restore action、chevronが互いに不自然に重ならない。
- [ ] icon-only controlにはtooltip/semanticsがある。
- [ ] 主要操作のタップ領域が小さくなりすぎていない。
- [ ] priority/status/due/progressなどが色だけに依存せず、text/semanticsでも意味が分かる。
- [ ] 追加・変更UI文字列がen/ja ARB化され、生成済みlocalizationsが更新されている。
- [ ] スクリーンショット確認またはwidget testで、密度、長いタイトル、日本語/i18n、Dynamic Type、狭い画面、Trash、並び替えUI、dialog/empty stateの破綻確認が記録されている。
- [ ] 既存widget testのタスク作成、編集、サブタスク、ゴミ箱/復元、手動並び替えの期待が引き続き通る。
- [ ] Rust API、FRB生成物、DB schema、domain usecase、storage repositoryに不要な変更が入っていない。
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [ ] public repoにprivate詳細が転記されていない。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `git diff --check` が成功している。
- [ ] `docs/tasks/task-25-design-calibration-ui-pass.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクはUI実装判断の較正であり、新機能開発やモック制作ではない。
- 画像やモックの雰囲気より、実データ、長い文言、アクセシビリティ、i18n、反復操作、狭い画面での安定性を優先する。
- `docs/design/visual-direction.md` はpublic repoのデザイン正本である。private詳細、未公開ロードマップ、課金/収益/法務/監査の具体情報を追加しない。
- task-20のUI foundationを尊重し、必要な小調整だけ行う。新しいdesign systemや巨大なtoken体系を作らない。
- task-24の並び替えUIは、Undoや条件ソートUIへ進む前の既存機能として較正する。並び替え機能そのものの仕様拡張はしない。
- UI文字列は必ずARB化する。`Text('...')`、`Tooltip(message: '...')` などの直書きを残さない。
- 秘密情報、Device Key、SQLCipher鍵、DB鍵をログやDebug出力に含めない。
- `docs/01〜03` は変更禁止である。仕様と実装の矛盾を見つけた場合は、仕様書を書き換えず完了報告の未解決事項に記録する。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- AI画像・画像モックから採用した要素
- AI画像・画像モックから捨てた要素
- 実アプリ優先で調整した理由
- 更新した `docs/design/visual-direction.md` の内容
- 変更したUI foundation / screenファイル
- Lists / Tasks / Task detail / Trash / Empty state / Dialog / 並び替えUIごとの較正内容
- 実画面の密度、長いタイトル、日本語/i18n、Dynamic Type、狭い画面への対応内容
- タップ領域、tooltip/semantics、色以外の情報伝達で維持・改善した点
- 追加/変更したi18nキー
- 追加/更新したwidget test、またはスクリーンショット確認の対象と結果
- 品質ゲート6点、`check_hardcoded_strings.sh`、`git diff --check` の実行結果
- やらなかったことが守られていること（新規機能なし、Undoなし、条件ソートUIなし、検索/通知/Keychain/オンボーディング/タイマーなし、画像モック追加なし、新規依存なし、Rust/FRB/DB/domain変更なし）
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` を変更していないこと
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
- `docs/tasks/task-20-ui-foundation.md`
- `docs/tasks/task-21-visual-direction.md`
- `docs/tasks/task-22-design-direction-sketch.md`
- `docs/tasks/task-23-trash-restore-ui.md`
- `docs/tasks/task-24-fractional-index.md`
- `docs/design/visual-direction.md`
- `app/lib/main.dart`
- `app/lib/src/router.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/*`
- `app/test/widget_test.dart`
- `app/test/l10n_test.dart`
- `app/tool/check_hardcoded_strings.sh`

### AI画像・画像モックから採用した要素

- deep green / pale sage / warm white surface / thin border の方向性は維持した。
- priority dot + text metadata、折り返し可能なpill metadata、静かなTrash/restore表現は維持した。
- task-firstの読み順、metadataのwrap、icon-only controlのtooltip/semanticsを実アプリ側へ優先して反映した。

### AI画像・画像モックから捨てた要素

- ピクセル完全再現、固定phone-frame比率、固定1行row、過剰な余白、常時大きいheaderは採用しない方針を明文化した。
- main task headerのpersistent lock/encryption markは採用しない方針に合わせ、Tasks画面AppBarの常設 `AppProtectionSignal` を外した。
- bottom navigation、常設マスコット、Focus timer、AI/account/billing/legal/audit/roadmap surfaceは追加していない。

### 実アプリ優先で調整した理由

- 長い日本語/英語タイトル、狭い320px相当幅、Dynamic Type相当の大きい文字、並び替えicon button、Trash restore actionが横方向で競合しないことを優先した。
- 画像モックの余白や常設安心シグナルより、反復利用時の密度、48px級タップ領域、tooltip/semantics、metadata wrapを優先した。

### 更新した `docs/design/visual-direction.md`

- 冒頭に `Calibration Rule` を追加した。
- 画像/モックはtasteの参照であり、実装正解やピクセル完全基準ではないことを強化した。
- `Adopt from images` / `Do not adopt from images` / image directionと実アプリ制約が衝突した場合の優先判断を整理した。
- public repo向けの抽象化済みデザイン方針のみで、private詳細は追加していない。

### 変更したUI foundation / screenファイル

- `app/lib/src/ui/task_components.dart`
  - `AppTaskRow` を `ListTile` 依存から小さなcustom layoutへ変更した。
  - checkbox/status icon領域を48pxに保ち、title/metadataをwrapし、trailing操作は狭幅または大きい文字で下段へstackするようにした。
  - 既定のchevron、priority dot、hierarchy guide、既存keyは維持した。
- `app/lib/src/ui/dialogs.dart`
  - confirm/text input dialogを `scrollable: true` にして、長い文言や大きい文字で本文とactionsが押し出されにくいようにした。
- `app/lib/src/screens/tasks_screen.dart`
  - main task headerの常設 `AppProtectionSignal` を削除し、Trash導線は維持した。
- `app/lib/src/screens/trash_screen.dart`
  - Trash行をcustom layoutへ変更し、長いtitle/metadata/restore actionが狭幅・Dynamic Typeで潰れないようにした。
- `app/lib/src/screens/lists_screen.dart`
  - 長いlist nameをwrap可能にした。
- `app/lib/src/screens/task_detail_screen.dart`
  - edit dialog内の日付操作button `Wrap` に `runSpacing` を追加した。

### 画面ごとの較正内容

- Lists: 長いリスト名を1行固定にせずwrap可能にした。
- Tasks: 長いtask title、priority dot、metadata、checkbox、上/下移動button、chevronの競合を減らした。常設保護シグナルは外し、作業密度を優先した。
- Task detail: 詳細本文/metadata/サブタスク表示は維持し、edit dialog内buttonの縦逃げを改善した。詳細画面の保護シグナルは文脈表示として維持した。
- Trash: muted title、deleted metadata、restore actionを維持しつつ、狭幅ではrestore actionを下段へ逃がすようにした。
- Empty state: 既存文法を維持し、狭幅/Dynamic Typeのwidget test対象に追加した。
- Dialog: text input / confirm dialogをscrollableにした。
- 並び替えUI: 上/下移動icon buttonは既存tooltip/key/動作を維持し、`AppTaskRow` 側で狭幅時に下段へ逃がすようにした。

### 密度・長いタイトル・日本語/i18n・Dynamic Type・狭い画面

- 320px幅 + text scale 1.6相当のwidget testを追加した。
- 日本語を含む長いlist/task/trash titleで、row、metadata、reorder control、restore actionがoverflow例外を出さないことを確認した。
- `TaskMetadata` の既存wrap方針を維持し、row側で横幅を奪い合わないようにした。

### タップ領域・tooltip/semantics・色以外の情報伝達

- task checkbox/status icon領域は48pxのboxに収め、主要操作のタップ領域を小さくしないようにした。
- 上/下移動、Trash導線、restore action、priority dot tooltip/semanticsは維持した。
- priority/status/due/progress/deletedAtはmetadata textを維持し、色だけに依存していない。

### i18n

- 追加/変更したi18nキー: なし。
- ARBおよび生成済みlocalizationsは変更していない。
- 既存のen/ja文言をそのまま使用し、直書きUI文字列は追加していない。

### 追加/更新したwidget test

- `long task titles survive narrow width and Dynamic Type`
  - 長い日本語/英語task title、priority dot、上/下移動UI、320px幅、text scale 1.6相当を検証。
- `empty state and create dialog survive narrow Dynamic Type`
  - empty stateと新規list dialogが狭幅/Dynamic Typeで例外を出さないことを検証。
- `trash rows restore long titles on narrow Dynamic Type`
  - 長い削除済みtitle、priority metadata、restore action、復元後empty stateを検証。
- 既存のタスク作成、編集、サブタスク、親完了確認、Trash/restore、手動並び替えwidget testは継続して通過した。

### 品質ゲート

- `git -C todori diff --check`: 成功。
- `git -C todori status --short`: 変更ファイルのみ表示（無関係差分なし）。
- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（Rust 70 tests）。
- `cd app && flutter analyze`: 初回はFlutter SDK cache書き込みがサンドボックスで拒否されたため、承認付きで再実行して成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test`: 初回はFlutter SDK cache書き込みがサンドボックスで拒否された。承認付き再実行後、追加テストの操作対象が狭幅で画面端にかかる問題を修正し、最終的に成功（Flutter 30 tests）。
- `cd todori && sh app/tool/check_hardcoded_strings.sh`: 成功。

### やらなかったこと

- 新機能は追加していない。
- Undo、条件ソートUI、検索、通知、Keychain、オンボーディング、タイマー、Focus timer、Pomodoro、常設マスコット、bottom navigationは実装していない。
- 新しいAI生成画像、画像モック、Figma相当成果物は追加していない。
- 新規依存、UIフレームワーク、icon packageは追加していない。
- Rust API、FRB定義/生成物、DB schema、domain/storage/core実装は変更していない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。

### public/private境界

- `todori-private/` 配下は読んでおらず、変更していない。
- public repoには抽象化済みのUI/デザイン判断のみを記録し、課金、収益、法務、監査、公開前ロードマップ詳細は追加していない。

### 未解決事項・要人間判断

- 最終合否判定は親Codexまたは別検証セッションで行う。
- BACKLOGの現在地更新は、親Codexの検証後に行うのが安全と判断し、このworkerでは変更していない。
