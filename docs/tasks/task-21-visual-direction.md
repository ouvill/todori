# task-21: ビジュアル方向性反映

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

task-20で `app/lib/src/ui/` 配下に `ThemeData`、spacing、共通task row、metadata、empty/loading/error state、dialogの基盤が追加され、Lists / Tasks / TaskDetail の画面文法が揃い始めた。一方、現状のUIはまだMaterial標準寄りの整理段階であり、Todoriのプロダクトらしさを示す視覚的な方向性は薄い。

参考画像 `assets/brand/generated/todori-mobile-product.png` は、深いグリーン/淡いセージ、白い大きな面、priority dot、due chip、サブタスク階層線、下部ナビ風の構成、鍵アイコンによる安心シグナルが印象的である。ただし、この画像は広告用モックであり、実アプリの情報設計・既存ルート・MVPスコープをそのまま置き換えるものではない。

このタスクでは、参考画像の方向性を「実アプリとして疲れない密度」に調整し、task-20で追加された既存UI foundationへ小さく反映する。ゴミ箱画面・復元UI、並び替え、通知へ進む前に、既存のLists / Tasks / TaskDetailが同じブランド文法を持つ状態にする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` M2-03 / M2-04 / M3-02 / M3-03 / M3-04 / M3-05 / M4-03
- `docs/tasks/task-18-task-editing-ui.md`
- `docs/tasks/task-19-subtasks-ui.md`
- `docs/tasks/task-20-ui-foundation.md`
- `assets/brand/generated/todori-mobile-product.png`
- `app/lib/main.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/l10n_test.dart`
- `app/tool/check_hardcoded_strings.sh`

## 3. ゴール

参考画像の視覚方向性を、既存UI foundationを活かした実アプリUIとして反映する。

- themeの色調を深いグリーン/淡いセージ/白い面を中心に調整する。
- task rowにpriority dotを追加し、priorityが一覧で直感的に読めるようにする。
- due date / status / progressなどのmetadata chipを、参考画像のような軽いpill表現へ磨き込む。
- サブタスク階層線を追加し、インデントだけに頼らず親子関係が読めるようにする。
- headerまたはAppBar付近に、小さな暗号化/ローカル保護シグナルを追加する。
- Lists / Tasks / TaskDetail の余白、surface、カード面、行密度を実アプリとして落ち着いた密度へ調整する。
- 既存widget testとi18n/直書き検出を維持する。

## 4. スコープ

### やること

1. **themeの色調整**:
   - `app/lib/src/ui/theme.dart` の既存 `buildTodoriTheme` を中心に、参考画像由来の深いグリーン、淡いセージ、白いsurfaceをMaterial 3 `ColorScheme` の範囲で反映する。
   - `ColorScheme.fromSeed` を使い続けてもよいが、必要なら `primary` / `primaryContainer` / `surface` / `surfaceContainer*` / `outlineVariant` などを最小限上書きする。
   - light themeを主対象にする。dark themeは破綻しない範囲で同じ方針を反映し、読めないコントラストを作らない。
   - `AppSpacing` などtask-20の小さなtokenは維持し、巨大なdesign token体系へ広げない。
2. **task rowのpriority dot**:
   - `app/lib/src/ui/task_components.dart` の `AppTaskRow` またはmetadata helperに、priorityを示す小さなdotを追加する。
   - dotは `priority == 0` では表示しない、または低彩度のnone表現に留める。`1..3` は色/濃さで差をつける。
   - 色だけに依存しないよう、既存のpriority metadata textまたはsemantics/tooltip相当を維持する。
   - 既存のcheckbox、title、metadata、chevron、行tap、`ValueKey` を壊さない。
3. **metadata chipの磨き込み**:
   - due date、status、priority、subtask progressのchipを、参考画像のdue chipのように軽いpillとして読みやすくする。
   - chipは横幅が狭い画面で折り返し可能なままにし、Dynamic Typeでテキストが潰れないようにする。
   - due dateは既存の `formatDueDate` / ARB文言を活かし、日付機能や通知機能へ広げない。
4. **サブタスク階層線**:
   - 既存の `depth` と `AppTaskRow` を使い、サブタスク行に薄い縦線またはL字状の階層ガイドを追加する。
   - 深すぎる階層でも破綻しないよう、task-20の表示上限や防御的表示方針を維持する。
   - 詳細画面の直下サブタスク表示にも、一覧と同じ文法を可能な範囲で適用する。
5. **小さな保護シグナル**:
   - TasksまたはTaskDetailのAppBar/header付近に、鍵アイコンなどを使った小さな暗号化/ローカル保護シグナルを追加する。
   - 文言は「暗号化済み」「ローカル保護」など、Phase 1のローカルSQLCipher保存時暗号化を過大に見せない範囲にする。
   - 新しい文言は必ず `app/lib/l10n/app_en.arb` と `app_ja.arb` に追加する。
   - Device KeyやDB鍵などの秘密情報は表示・ログ出力しない。
6. **既存画面の余白/面の微調整**:
   - `ListsScreen`、`TasksScreen`、`TaskDetailScreen` を対象に、白い大きな面、薄い境界線、落ち着いた背景色、行間を調整する。
   - 画面全体を広告モックのような大きなスマホ内レイアウトへ作り替えず、現行のScaffold/AppBar/route構成を維持する。
   - カードやsurfaceを使う場合は、既存情報密度が下がりすぎないようにし、カード内カードのような過剰な入れ子を避ける。
7. **i18nとアクセシビリティ維持**:
   - 追加・変更するUI文字列はARB化し、`flutter gen-l10n` を実行する。
   - icon-only buttonや保護シグナルにはtooltip/semantic labelを付ける。
   - 色だけでpriority/status/dueを伝えない。既存のtext/icon/semanticsを残す。
8. **テスト更新**:
   - `app/test/widget_test.dart` を更新し、既存の画面遷移、タスク作成、編集、サブタスク表示/作成、親完了確認が壊れていないことを維持する。
   - priority dot、due/status/progress metadata、保護シグナル、サブタスク階層線は、可能な範囲でwidget tree上の存在やsemanticsを検証する。
   - golden testやスクリーンショット比較基盤は必須にしない。

### やらないこと

- 参考画像をピクセル単位で再現しない。
- 広告用モックの情報構成を実アプリへそのまま移植しない。
- 新規pub依存、UIフレームワーク、icon package、画像処理ライブラリを追加しない。
- 画面構成やルーティングを大規模に変更しない。
- Today / Upcoming / Projects / Settings の下部ナビを実装しない。
- Focus timer、Pomodoro、Forestモード、タイマー設定を実装しない。
- ゴミ箱画面・復元UI、Undo、fractional index、ドラッグ&ドロップ並び替え、通知、検索UI、タグ、設定画面を実装しない。
- Riverpod、go_router、FRB、Rust API、DB schema、domain usecaseを変更しない。
- 本格的なセキュリティ状態画面、鍵管理画面、アプリロック、生体認証、Keychain本実装を追加しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `todori-private/` 配下を読んだり変更したりしない。private側の詳細をpublic repoへ転記しない。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルと参考画像を読み、task-20のUI foundationがどこまで使えるか確認する。
3. 参考画像から取り込む要素を、色、priority dot、due chip、階層線、保護シグナル、surface/spacingに分解する。
4. `app/lib/src/ui/theme.dart` で色とsurface/chip/list系のthemeを最小限調整する。
5. `app/lib/src/ui/task_components.dart` でpriority dot、metadata chip、階層線を追加または調整する。
6. `ListsScreen`、`TasksScreen`、`TaskDetailScreen` の余白、surface、header/AppBar付近の保護シグナルを調整する。
7. 追加文言を `app/lib/l10n/app_en.arb` / `app_ja.arb` へ追加し、`cd app && flutter gen-l10n` を実行する。
8. `app/test/widget_test.dart` と必要なl10n testを更新する。
9. 品質ゲートを実行する。
10. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] `assets/brand/generated/todori-mobile-product.png` を参考にした視覚方向性が、実アプリの既存UI foundationへ反映されている。
- [ ] 深いグリーン、淡いセージ、白いsurfaceの方向性が `ThemeData` / `ColorScheme` / 既存tokenの範囲で整理されている。
- [ ] 新規pub依存、UIフレームワーク、icon packageが追加されていない。
- [ ] `AppTaskRow` または同等の共通部品にpriority dotが追加され、Tasks画面とTaskDetailのサブタスク表示で同じ文法になっている。
- [ ] priority dotは色だけに依存せず、既存metadata textまたはsemantics/tooltipで意味が補完されている。
- [ ] due date / status / priority / subtask progressのmetadata chipが、折り返し可能で読みやすいpill表現に整理されている。
- [ ] サブタスク階層線または同等の階層ガイドが追加され、3階層以上でも表示が破綻しない。
- [ ] headerまたはAppBar付近に、小さな暗号化/ローカル保護シグナルが追加されている。
- [ ] 保護シグナルはPhase 1の実装状況を過大に表現せず、秘密情報を表示・ログ出力していない。
- [ ] Lists / Tasks / TaskDetail の既存導線、キー、主要操作が維持されている。
- [ ] 下部ナビ、Today/Upcoming/Projects/Settings、Focus timer、ゴミ箱/復元、Undo、並び替え、通知、検索、タグ、設定画面は実装されていない。
- [ ] Rust API、FRB生成物、DB schema、domain usecaseに変更が入っていない。
- [ ] 追加・変更UI文字列がen/ja ARB化されている。
- [ ] icon-only要素と保護シグナルのtooltip/semanticsが維持または追加されている。
- [ ] 既存widget testが更新され、タスク作成、編集、サブタスク表示/作成、親完了確認が引き続き検証されている。
- [ ] priority dot、metadata chip、階層線、保護シグナルについて、可能な範囲でwidget testまたはsemanticsで確認されている。
- [ ] golden testや新規スクリーンショット比較基盤を必須化していない。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `docs/tasks/task-21-visual-direction.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクは視覚文法の調整であり、機能追加タスクではない。M3/M4の後続機能を先取りしない。
- task-20で追加された `app/lib/src/ui/theme.dart` / `task_components.dart` / `states.dart` / `dialogs.dart` を優先して使い、画面ごとの場当たり的な装飾を増やさない。
- 参考画像は方向性の入力であり、実装の唯一の正解ではない。実アプリとして長時間使って疲れない密度を優先する。
- 保護シグナルは安心感を与える補助表示に留める。未実装のKeychain本実装、アプリロック、同期E2EE、監査済み状態を示唆しない。
- UI文字列は必ずARB化する。新しい `Text('...')` などの直書きを残さない。
- Dynamic Type、狭い画面、長いタスク名で、chipやbutton内テキストが潰れないようにする。
- `docs/01〜03` は変更禁止である。仕様と実装の矛盾を見つけた場合は、仕様書を書き換えず完了報告の未解決事項に記録する。
- public repoにprivate repoの詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- 参考画像から採用した要素と、採用しなかった要素
- 変更したUI foundationファイル
- `ThemeData` / color / surface / chip / spacingの調整内容
- priority dotの仕様（priority値ごとの表示、色以外の補完、semantics）
- due/status/priority/progress metadata chipの表示方針
- サブタスク階層線の表示方針（深い階層、孤立タスク、詳細画面での扱い）
- 暗号化/ローカル保護シグナルの文言、表示位置、過大表現を避けた点
- Lists / Tasks / TaskDetail の余白・surface・行密度の調整内容
- 追加/変更したi18nキー
- アクセシビリティ上維持・改善した点
- 追加/更新したテスト
- 品質ゲート6点と `check_hardcoded_strings.sh` の実行結果
- やらなかったことが守られていること（新規依存なし、Rust/FRB/DB/domain変更なし、下部ナビ/Focus timer/ゴミ箱/Undo/並び替え/通知未実装）
- 未解決事項・要人間判断

## 9. 完了報告

- 作業日: 2026-07-04
- 読んだファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/PLAYBOOK.md`
  - `docs/tasks/BACKLOG.md`
  - `docs/07_Phase1計画書.md` M2-03 / M2-04 / M3-02 / M3-03 / M3-04 / M3-05 / M4-03
  - `docs/tasks/task-18-task-editing-ui.md`
  - `docs/tasks/task-19-subtasks-ui.md`
  - `docs/tasks/task-20-ui-foundation.md`
  - `assets/brand/generated/todori-mobile-product.png`
  - `app/lib/main.dart`
  - `app/lib/src/ui/theme.dart`
  - `app/lib/src/ui/task_components.dart`
  - `app/lib/src/ui/states.dart`
  - `app/lib/src/ui/dialogs.dart`
  - `app/lib/src/screens/lists_screen.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/screens/task_detail_screen.dart`
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/test/widget_test.dart`
  - `app/test/l10n_test.dart`
  - `app/tool/check_hardcoded_strings.sh`

### 参考画像から採用した要素 / 採用しなかった要素

- 採用した要素:
  - 深いグリーンのbrand color、淡いセージ背景、白いsurface。
  - task row内の小さなpriority dot。
  - due/status/priority/progressを軽いpillとして読むmetadata。
  - サブタスクの薄い縦線 + 横線の階層ガイド。
  - 鍵アイコン付きの小さな保護シグナル。
- 採用しなかった要素:
  - Today / Upcoming / Projects / Settings の下部ナビ。
  - Focus timer / Forest / タイマー操作。
  - 広告モックの大きなスマホ内レイアウト、ピクセル単位の再現、余白過多の構成。
  - 通知、検索、タグ、設定、ゴミ箱/復元、Undo、並び替え。

### 変更したUI foundationファイル

- `app/lib/src/ui/theme.dart`
  - `ColorScheme.fromSeed` を維持しつつ、deep green / sage / white surfaceの方向へ `primary`、`primaryContainer`、`surface`、`surfaceContainer`、`surfaceContainerHighest`、`outlineVariant` を最小限上書きした。
  - light themeを主対象にし、dark themeも同じgreen/sage方針で読めるコントラストにした。
  - AppBar title、FAB、input、list/chip/card相当のsurface/borderを既存Material 3 theme内で調整した。
- `app/lib/src/ui/task_components.dart`
  - `TaskMetadata` を標準 `Chip` から軽いpill表示へ変更した。
  - `AppTaskRow` にpriority dot、subtask階層ガイド、白いsurface/borderを追加した。
  - `AppProtectionSignal` を追加し、保護シグナルのtooltip/semanticsを共通化した。
- `app/lib/src/ui/states.dart` / `app/lib/src/ui/dialogs.dart`
  - 読了したが、このタスクでは変更なし。

### ThemeData / color / surface / chip / spacing

- primaryは `0xFF2F6F4E` を中心に、参考画像の深いグリーンへ寄せた。
- scaffold背景は淡いセージの `surfaceContainer`、task/list/detailの主要面は白寄りの `surface` にした。
- `outlineVariant` を薄いsage borderとして使い、row/pill/detail surfaceの境界を控えめに揃えた。
- metadata pillは `surfaceContainer` 背景、999px radius、薄いborder、green icon/textで表示する。
- `AppSpacing` はtask-20の `xs/sm/md/lg/xl` を維持し、巨大なtoken体系は追加していない。

### priority dot

- `priority == 0`: dotは表示しない。
- `priority == 1`: green系dot。
- `priority == 2`: yellow green系dot。
- `priority == 3`: coral/red系dot。
- done行ではdotを低彩度化する。
- 色だけに依存しないよう、既存metadata textの `Priority: Low/Medium/High` / `優先度: 低/中/高` を維持し、dotにはtooltip/semanticsとして同じ `taskPriority(...)` 文言を渡した。
- `ValueKey('task-priority-dot-${task.id}')` を追加し、widget testから存在確認できるようにした。
- 既存の `ValueKey('task-row-${task.id}')` と `ValueKey('task-done-${task.id}')` は維持した。

### metadata chip

- status / priority / due date / subtask progress の文言は既存ARB由来のまま維持した。
  - 例: `Status: To do`, `Priority: High`, `Due: 2026-07-04`, `Progress: 1/2`
- pillは `Wrap` で折り返し可能にし、狭い幅では1 pillごとに最大幅制約を持たせてDynamic Typeで潰れにくくした。
- due dateは既存 `formatDueDate` と `taskDueAt` を使い、通知や日付機能の拡張は行っていない。

### サブタスク階層線

- `AppTaskRow.depth` を使い、`depth > 0` の行に薄い縦線と短い横線を表示する。
- deep hierarchyでは既存方針どおり表示インデントを4段階までに抑制し、無制限階層データでもUIが広がりすぎないようにした。
- Tasks画面ではflatten済みtreeの各subtask行へ適用した。
- TaskDetail画面の直下サブタスクにも `depth: 1` と同じ階層ガイドを適用した。
- 孤立タスクの扱いは既存 `buildTaskTree` / `flattenTaskTree` の防御的表示方針を維持した。
- `ValueKey('task-hierarchy-guide-${task.id}')` を追加し、widget testで子/孫行の階層ガイドを確認した。

### 暗号化/ローカル保護シグナル

- 追加文言:
  - en: `Local protection`
  - ja: `ローカル保護`
  - tooltip en: `Stored locally with encrypted database protection.`
  - tooltip ja: `ローカル保存データベースの暗号化で保護されています。`
- 表示位置:
  - Tasks画面のAppBar action。
  - TaskDetail画面のdetail header内。
- Phase 1のローカルSQLCipher保存時暗号化を示す補助表示に留め、同期E2EE、監査済み、Keychain本実装、アプリロック、生体認証を示唆する文言は使っていない。
- Device Key、DB鍵、SQLCipher鍵、exportKey等の秘密情報は表示・ログ出力していない。
- `Tooltip` と `Semantics(label: ...)` を付与した。

### Lists / Tasks / TaskDetail

- Lists:
  - 一覧行を白いsurface + 薄いborder + 16px radiusへ寄せ、淡いsage背景上で読みやすくした。
  - 既存のlist tap導線、FAB、空状態は維持した。
- Tasks:
  - AppBarにローカル保護シグナルを追加した。
  - task rowを白いsurface、薄いborder、8px間隔のListViewへ変更した。
  - checkbox、title、metadata、chevron、行tapは維持した。
- TaskDetail:
  - title / note / protection signal / metadata / created_at を白いdetail surfaceにまとめた。
  - 直下subtask行へpriority dotと階層線を適用した。
  - edit、subtask追加、trash移動の既存導線は維持した。

### 追加/変更したi18nキー

- `localProtectionLabel`
- `localProtectionTooltip`

`cd app && flutter gen-l10n` を実行し、`app/lib/src/generated/l10n/` 配下を更新した。

### アクセシビリティ

- protection signalにtooltipとsemantic labelを追加した。
- priority dotはtooltip/semanticsを持ち、metadata textも維持して色だけに依存しない。
- metadata pillはicon + textを維持した。
- icon-onlyの既存編集ボタン/FAB tooltipは維持した。
- metadataは `Wrap`、row titleは `Expanded` を使い、固定heightで文字を潰さない構成を維持した。

### 追加/更新したテスト

- `app/test/widget_test.dart`
  - Tasks画面とTaskDetail画面の `Local protection` 表示を確認した。
  - 3階層subtask表示テストで、子/孫の `task-hierarchy-guide-*` を確認した。
  - 編集後priority highになったtaskの `task-priority-dot-*` を確認した。
  - 既存の画面遷移、タスク作成、編集、サブタスク表示/作成、親完了確認テストは維持した。
- `app/test/l10n_test.dart`
  - en/ja の `localProtectionLabel` を確認した。
- golden testやスクリーンショット比較基盤は追加していない。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（Rust 62件）。
- `cd app && flutter gen-l10n`: 成功。
- `cd app && flutter analyze`: 成功（No issues found）。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test`: 成功（Flutter 20件）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git -C todori diff --check`: 成功。

### やらなかったこと

- 新規pub依存、新規Rust依存、UIフレームワーク、icon packageは追加していない。
- Rust API、FRB生成物、DB schema、domain usecaseは変更していない。
- 下部ナビ、Today/Upcoming/Projects/Settings、Focus timer、Forest、ゴミ箱画面・復元UI、Undo、並び替え、通知、検索、タグ、設定画面は実装していない。
- 本格的なセキュリティ状態画面、鍵管理画面、アプリロック、生体認証、Keychain本実装は追加していない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。
- `todori-private/` は読んでおらず、private詳細をpublic repoへ転記していない。

### 未解決事項・要人間判断

- なし。
