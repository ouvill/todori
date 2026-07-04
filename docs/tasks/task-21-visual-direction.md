# task-21: ビジュアル方向性反映

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
