# task-29: product experience alignment

> ステータス: 完了（rootをtask-firstのToday体験へ変更し、Listsを管理/切替画面へ再位置付け）
> 作業日: 2026-07-05

## 1. 背景とコンテキスト

task-28ではLists / Tasks / Detail / Trash / Dialog / Empty stateを小さくpolishしたが、後続の目視QAで `assets/brand/generated/taskveil-design-direction-mobile-focus-tasks.webp` と `assets/brand/generated/taskveil-design-direction-lists.webp` が示す体験と、現在の実装がまだ大きく違うことが分かった。

現在のアプリは `initialLocation: /lists` で、起動直後にリスト一覧が主役になる。これは機能確認用UIとしては堅実だが、Taskveilのdesign directionが示す「task-first」「Today領域」「静かで柔らかい作業開始面」とは距離がある。

このタスクでは、Rust/DB/FRBやタスク操作仕様を変更せず、Flutterの入口体験と主要画面構成をガッツリ調整する。目的は、リスト一覧をrootにするのではなく、既定リストのTasks画面を起動直後の主役にし、Lists画面は切替/管理のための落ち着いた画面へ下げることである。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/visual-direction.md`
- `docs/tasks/task-22-design-direction-sketch.md`
- `docs/tasks/task-28-visual-polish.md`
- `assets/brand/generated/taskveil-design-direction-mobile-focus-tasks.webp`
- `assets/brand/generated/taskveil-design-direction-lists.webp`
- `app/lib/src/router.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/tool/check_hardcoded_strings.sh`

## 3. ゴール

起動直後の体験を、リスト選択画面ではなく、Taskveilらしいtask-firstのToday/Inbox作業面へ寄せる。

- 初期routeをListsではなく、既定リストのTasks体験へ寄せる。
- Tasks画面に、design directionのToday領域に近い、少し贅沢なheader/summaryを追加する。
- Lists画面は `taskveil-design-direction-lists.webp` のように、管理/切替画面として静かな大きなsurfaceとsection感を持たせる。
- タスク操作、Undo、Trash、条件ソート、手動並び替え、Detail導線は維持する。
- 新規依存、Rust/DB/FRB/schema/domain/storage変更は行わない。

## 4. スコープ

### 想定変更ファイル

- `app/lib/src/router.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/home_screen.dart`（必要なら新規）
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/` 配下の生成物
- `app/test/widget_test.dart`
- `app/test/l10n_test.dart`
- `docs/tasks/task-29-product-experience-alignment.md`
- 必要な場合のみ `docs/tasks/README.md` / `docs/tasks/BACKLOG.md`

### やること

1. **root体験の変更**:
   - 起動直後はLists一覧そのものではなく、既定リスト（先頭list）を使ったTasks体験を表示する。
   - listが存在しない場合は、Taskveilの空状態として新規list作成へ自然に進める。
   - Lists画面はメニュー/切替/管理導線として残す。
2. **Tasks画面のToday/Inbox header**:
   - root表示時のTasks画面に、`Today` / 日付 / pending count / 小さなlist名表示を持つheaderを追加する。
   - headerは大きすぎてタスクを押し出さない範囲にしつつ、起動時の第一印象を作る。
   - permanent mascot、focus timer、未実装Focus機能は追加しない。
3. **Task list presentationの調整**:
   - `mobile-focus-tasks` のように、タスク行の読み順を「完了control → priority → title → compact due/progress → action」に整理する。
   - 手動並び替えや管理操作は常時主張しすぎないようにする。
   - 条件ソートと手動並び替えの既存挙動は維持する。
4. **Lists画面の再位置付け**:
   - Lists画面は `taskveil-design-direction-lists.webp` を参照し、Taskveil見出し、大きめのsurface、section label、静かなlist rowとして整える。
   - list countは現時点で安定した集計APIがないため、件数badgeの本実装は行わない。必要なら装飾ではなく既存データで可能な範囲に留める。
5. **i18n / test / QA**:
   - 追加文言はARB化する。
   - widget testを更新し、起動直後がTasks体験になること、Lists導線が残ること、既存タスク操作が壊れないことを確認する。
   - 指定2枚と実画面のスクリーンショットを目視比較し、完了報告に結果を書く。

### やらないこと

- Rust API、FRB定義/生成物、DB schema、domain usecase、storage repositoryを変更しない。
- 新規pub依存、UI framework、icon package、画像生成、golden比較基盤を追加しない。
- Focus timer、Pomodoro、通知、検索、Keychain、オンボーディング、設定画面、同期、アカウント、課金は実装しない。
- Listsを削除しない。あくまでroot主役から管理/切替導線へ下げる。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `.github/` と `taskveil-private/` は変更しない。
- private詳細をpublic repoへ転記しない。

## 5. 実装手順（例）

1. `git -C taskveil status --short` で作業ツリーを確認する。
2. 指定2枚の画像と `docs/design/visual-direction.md` のMobile Task List / Layout Principlesを確認する。
3. root画面を追加またはrouterを変更し、初期表示を既定listのTasks体験へ寄せる。
4. Tasks画面にroot表示用header/summaryを追加する。
5. Lists画面を管理/切替画面として大きなsurface + section rowへ調整する。
6. ARBと生成済みl10nを更新する。
7. widget testを更新する。
8. 目視QA用スクリーンショットを一時生成し、指定画像との差分を確認する。
9. 品質ゲートを実行する。
10. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] 起動直後のrouteがLists一覧ではなく、既定listのTasks体験になっている。
- [ ] listが存在しない場合の空状態からlist作成へ進める。
- [ ] Lists画面への導線が残っている。
- [ ] Tasks画面root表示にToday/日付/pending count/list名相当のheaderがある。
- [ ] headerは実データ、長いlist名、日本語/英語、Dynamic Type、狭幅で破綻しない。
- [ ] Tasks画面のタスク行が、指定画像のようなtask-firstの読み順と静かな操作感に近づいている。
- [ ] 手動並び替え、条件ソート、Undo、Trash、Detail遷移の既存挙動が維持されている。
- [ ] Lists画面が `taskveil-design-direction-lists.webp` に近い管理/切替画面として整理されている。
- [ ] 追加文言がen/ja ARB化され、生成済みlocalizationsが更新されている。
- [ ] widget testでroot体験、Lists導線、既存タスク操作が検証されている。
- [ ] 目視QAで指定2枚との差分と残課題が完了報告に記録されている。
- [ ] Rust/DB/FRB/schema/domain/storageに変更が入っていない。
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [ ] `.github/` と `taskveil-private/` が変更されていない。
- [ ] `flutter analyze` が成功している。
- [ ] `flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `git diff --check` が成功している。

## 7. 制約・注意事項

- このタスクはvisual polishではなく、product experience alignmentである。
- design direction画像はピクセル完全基準ではないが、今回は指定2枚の体験差分を強く参照する。
- rootをTasks体験へ寄せても、Lists管理を消さない。
- 未実装のFocus timerや通知を、動く機能のように見せない。
- UI文字列は必ずARB化する。
- 実装者は最終合否判定をしない。目視QAの結果と残課題を完了報告へ具体的に書く。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- 指定2枚から採用した要素
- 採用しなかった要素と理由
- root体験の変更内容
- Tasks画面のheader/summary/row/action調整内容
- Lists画面の管理/切替画面化の内容
- 追加/変更したi18nキー
- 更新したwidget test
- 目視QAの対象、結果、残課題
- 品質ゲート結果
- Rust/DB/FRB/schema/domain/storageを変更していないこと
- docs/01〜03、`.github/`、`taskveil-private/` を変更していないこと
- 未解決事項・要人間判断

## 9. 完了報告

### 作業日

2026-07-05

### 読んだファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/visual-direction.md`
- `docs/tasks/task-22-design-direction-sketch.md`
- `docs/tasks/task-28-visual-polish.md`
- `assets/brand/generated/taskveil-design-direction-mobile-focus-tasks.webp`
- `assets/brand/generated/taskveil-design-direction-lists.webp`
- `app/lib/src/router.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`

### 実装結果

- `app/lib/src/screens/home_screen.dart` を追加し、root `/` をtask-firstのHome画面に変更した。
- 起動直後は既存listの先頭を使って `TasksScreen(isHome: true)` を表示し、listがない場合はTaskveilの空状態からlist作成へ進めるようにした。
- `app/lib/src/router.dart` の `initialLocation` を `/lists` から `/` に変更し、`/lists` は管理/切替画面として残した。
- root表示のTasks画面に `Today` / 日付 / pending count / list名pill / Lists導線 / sort / trash / extended add task action を追加した。
- root表示では手動並び替えハンドルを常時主張させず、リスト管理画面から対象listへ入った通常Tasks画面では従来どおり手動並び替えを維持した。
- Lists画面を、Taskveil見出し、大きめのsurface、section label、静かなrow、新規list rowを持つ管理/切替画面へ再構成した。
- 押せるが何も起きないoverflow buttonは追加しない方針とし、未実装機能に見えるUIを避けた。

### 指定2枚から採用した要素

- `mobile-focus-tasks`: 起動直後にTodayを大きく見せる構成、pending count、作業対象listの控えめな表示、タスク行を主役にする余白、下部のAdd task action。
- `lists`: Taskveil見出し、LISTS section label、大きな白いsurface、アイコン付きlist row、New list row。

### 採用しなかった要素と理由

- Focus timer / Start button / completed today section: Phase 1の実装範囲外で、動く機能のように見せないため未採用。
- 検索、Projects section、件数badge: 現時点の安定した検索/集計APIと画面仕様がないため未採用。
- 参照画像の装飾イラストの常設表示: 今回は新規assetや画像生成を追加せず、実アプリとして破綻しないFlutter UI構造を優先した。

### i18n

追加したARBキー:

- `listsSectionTitle`
- `todayTitle`
- `homeTasksSectionTitle`
- `homePendingCount`
- `homeListMenuTooltip`
- `homeEmptyTitle`
- `homeEmptyBody`
- `homeNewListButton`
- `addTaskButton`

`flutter gen-l10n` を実行し、`app/lib/src/generated/l10n/` 配下を更新した。

### 更新したwidget test

- rootがListsではなくToday/Tasks体験であることを確認する期待値を追加した。
- Lists画面の確認は `Open lists` 導線経由へ変更した。
- 手動並び替え/条件ソートは、Lists管理画面から通常Tasks画面へ入った経路で従来どおり検証するようにした。
- listなし空状態は狭幅 + Dynamic Typeでもoverflowせず、スクロールしてlist作成dialogを開けることを確認した。

### 目視QA

- Web実行での目視QAを試みたが、現状のFlutter projectはweb未構成かつ `frb_generated.web.dart` が存在せず、FRB web targetのコンパイルエラーで起動できなかった。これは今回のUI変更ではなく既存のtarget制約として扱った。
- 代替として `/private/tmp/taskveil_visual_smoke_test.dart` を一時作成し、Flutter test rendererで以下のPNGを生成して確認した。
  - `/private/tmp/taskveil_visual_home.png`
  - `/private/tmp/taskveil_visual_lists.png`
- test rendererの既定fontでは文字がブロック表示になるためtypographyの最終確認には不向きだが、構造としてHomeはToday header / pending badge / list pill / task cards / Add task、ListsはTaskveil見出し / section label / large surface / list rows / New list rowになっていることを確認した。
- 残課題: 参照画像の装飾イラストやFocus timerのような強いブランド演出は、動く機能・asset方針が固まった後の別タスクで扱うのが安全。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功（Rust 74 tests）
- `cd app && flutter analyze`: 成功
- `cd app && flutter test --reporter compact`: 成功（Flutter 37 tests）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `git diff --check`: 成功

### 変更しなかった範囲

- Rust API / FRB定義 / DB schema / domain usecase / storage repositoryは変更していない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。
- `.github/` と `taskveil-private/` は変更していない。
- public repoにprivate詳細は転記していない。

### 未解決事項・要人間判断

- Flutter Webでの実行確認は、FRB web生成物がない既存制約により未実施。Web targetを正式対応する場合は別タスク化が必要。
- 参照画像相当の装飾イラスト、Focus timer、検索、Projects/Todayなどのスマートリスト、件数badgeは未実装。Phase 1の機能範囲と実データ仕様を決めてから別タスクで扱う。
