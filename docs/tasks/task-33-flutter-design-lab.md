# task-33: Flutter Design Lab ── visual QA based design mock playground

> ステータス: 完了（2026-07-05）
> 作業日: 2026-07-05

## 1. 背景とコンテキスト

task-28〜32で本番UIの見た目は段階的に整ってきたが、まだ「見た目が不満足」「もっと大胆に試行錯誤したい」という課題が残っている。

本番画面を直接いじると、DB/Undo/並び替え/状態管理/アクセシビリティを壊さない制約が強く、デザイン探索の速度が落ちる。そこで、既存のvisual QAハーネス上にFlutter製のDesign Labを作り、実アプリのtheme/font/spacingを使いながら、本番ルートや本番ロジックを変更せずに複数のToday/Task UI案をPNGで比較できるようにする。

このタスクはプロダクト機能追加ではなく、デザイン探索用の開発者向けモック基盤を追加するものである。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/visual-direction.md`
- `docs/tasks/task-29-product-experience-alignment.md`
- `docs/tasks/task-30-design-mood-alignment.md`
- `docs/tasks/task-32-task-list-interaction-refinement.md`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/test/support/fake_bridge_service.dart`

## 3. ゴール

- Flutterで描画するDesign Lab用モックを追加する。
- `sh app/tool/visual_qa.sh` で本番画面スクリーンショットに加えて、複数のDesign Lab PNGを生成できるようにする。
- 本番アプリのroute、provider、DB、FRB、Rust APIを変更せずに、Today/Task体験の見た目を大胆に比較できる状態にする。
- 生成PNGを見れば、カード量、余白、スマートリスト風の構造、タスク密度、アイコン/メタデータの出し方を比較できる。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/visual_qa/design_lab_mocks.dart`（新規、または同等のtest-onlyファイル）
- `docs/tasks/task-33-flutter-design-lab.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

**A. Design Labモックの追加**

- test-onlyのFlutter widgetとしてDesign Labを追加する。
- 本番theme（`buildTaskveilTheme`）、既存spacing、Material Icons、実フォント読み込みを使う。
- 最低3案のPNGを生成する:
  - calm Today案: 余白と見出しを活かした、静かなToday面。
  - dense Today案: 作業アプリとして密度を上げたToday面。
  - smart lists案: Todayをスマートリストとして扱う将来像の探索。
- 各案は実データ風の日本語/英語混在タイトル、priority、due表現、completed affordanceを含む。

**B. visual QAへの接続**

- `sh app/tool/visual_qa.sh` 実行時に `app/build/visual_qa/design_lab_*.png` が生成されるようにする。
- 通常の `flutter test` ではDesign Labスクリーンショットは従来どおりskipされ、CI負荷を増やさない。

**C. 本番UIとの分離**

- 本番routeにDesign Labへの入口を追加しない。
- 本番providerやDB seedを変更しない。
- 本番i18nキーを増やさない。Design Labはtest-onlyのモック文字列を許可する。

### やらないこと

- 本番UIの見た目をこのタスクで置き換えない。
- Todayスマートリストの仕様確定、DB query、FRB API、Rust API、domain/storage実装を行わない。
- 外部アイコンセットや新規pub依存を追加しない。
- 新規画像アセットを追加しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `.github/` と `taskveil-private/` は変更しない。

## 5. 実装手順例

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読む。
3. `app/test/visual_qa/design_lab_mocks.dart` に、Design Lab専用widgetと3案のモックを追加する。
4. `app/test/visual_qa/visual_qa_screenshots_test.dart` にDesign Labのスクリーンショットtestを追加する。
5. `sh app/tool/visual_qa.sh` を実行し、既存8枚に加えてDesign Lab PNGが生成されることを確認する。
6. 生成PNGを目視し、文字の重なり、過剰なカード、見出しの崩れ、アイコン欠けがないか確認する。
7. `flutter analyze` / `flutter test` / `sh app/tool/check_hardcoded_strings.sh` / `git diff --check` を実行する。
8. 完了報告を追記する。

## 6. 受け入れ基準

- [x] `sh app/tool/visual_qa.sh` で `design_lab_*.png` が3枚以上生成される。
- [x] 既存のvisual QA PNG（home/list/detail/trash/dialog等）も引き続き生成される。
- [x] 通常の `cd app && flutter test` ではvisual QA harnessがskipされ、Design LabがCI標準ゲートへ混入しない。
- [x] Design Labは本番route/provider/DB/FRB/Rust APIに依存しないtest-only widgetである。
- [x] Design Labは本番theme/font/spacingを使い、実際のFlutter制約内で表示される。
- [x] 3案の違いがスクリーンショット上で明確に比較できる。
- [x] 日本語/英語混在タイトル、長文、priority/due/completed表現が破綻しない。
- [x] 外部依存、新規画像アセット、本番i18nキーを追加していない。
- [x] `cd app && flutter analyze` が成功している。
- [x] `cd app && flutter test` が成功している。
- [x] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [x] `git diff --check` が成功している。
- [x] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [x] `.github/` と `taskveil-private/` が変更されていない。

## 7. 制約・注意事項

- Design Labは実験場であり、プロダクト仕様の確定ではない。採用する案は後続タスクで本番UIへ落とし込む。
- Design Lab内の文字列はtest-onlyモックとして扱う。本番画面へ移す場合はARB化する。
- 「Todayはスマートリスト」という将来像は探索してよいが、このタスクではデータ抽出仕様や永続仕様を確定しない。
- visual QAのフォント読み込み（Material Icons / Inter / Lora / Hiragino fallback）を壊さない。
- public repoにprivate repoの課金、収益、法務、監査、公開前ロードマップ詳細を転記しない。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- 追加したDesign Lab PNG名
- 3案それぞれの狙いと、スクリーンショット目視結果
- 本番UI/route/provider/DB/FRB/Rust APIを変更していないこと
- 追加/変更したtest-onlyファイル
- 実行した検証コマンドと結果
- 外部依存、新規画像アセット、本番i18nキーを追加していないこと
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` を変更していないこと
- `.github/` と `taskveil-private/` を変更していないこと
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
- `docs/tasks/task-29-product-experience-alignment.md`
- `docs/tasks/task-30-design-mood-alignment.md`
- `docs/tasks/task-32-task-list-interaction-refinement.md`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/test/support/fake_bridge_service.dart`

### 実装結果

- `app/test/visual_qa/design_lab_mocks.dart` を追加し、test-onlyの `DesignLabMockApp` と3種類のFlutterモックを実装した。
- `app/test/visual_qa/visual_qa_screenshots_test.dart` にDesign Lab用のスクリーンショットtestを3件追加した。
- `DesignLabMockApp` は本番 `buildTaskveilTheme`、既存spacing、Material Icons、visual QAの実フォント読み込みを使う。
- 本番route、provider、DB seed、FRB、Rust API、ARB、本番画面ファイルは変更していない。

### 追加したDesign Lab PNG

- `app/build/visual_qa/design_lab_today_calm.png`
  - 狙い: 余白、大きなToday見出し、目立つNow領域を使い、静かで上品なToday面を比較する。
  - 目視結果: 見出しと余白の印象が強く、現行より情緒寄り。カード存在感も比較対象として分かる。
- `app/build/visual_qa/design_lab_today_dense.png`
  - 狙い: Now/Later/Doneの切替と密度高めの行で、作業道具としてのToday面を比較する。
  - 目視結果: 情報密度が上がり、タスク管理アプリらしい実用感が出る。文字崩れや重なりはなし。
- `app/build/visual_qa/design_lab_smart_lists.png`
  - 狙い: Todayをスマートリストとして扱う将来像を、Today/Upcoming/Inbox/Completedの仮想ビューと横断タスク一覧で比較する。
  - 目視結果: Todayが単なる見出しではなく仮想ビューに見える。日本語/英語混在、priority/due/context表示は破綻なし。

### 検証結果

- `cd app && dart format test/visual_qa/design_lab_mocks.dart test/visual_qa/visual_qa_screenshots_test.dart`: 成功
- `cd app && flutter analyze`: 成功（No issues found）
- `cd app && flutter test`: 成功（38 passed / visual QA harness 1 skipped）
- `sh app/tool/visual_qa.sh`: 成功（既存8枚 + Design Lab 3枚 = 11 screenshots）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `git diff --check`: 成功
- `cd core && cargo fmt --all -- --check`: 成功
- `cd core && cargo clippy --workspace -- -D warnings`: 成功
- `cd core && cargo test --workspace`: 成功（Rust 74 tests passed）

### スコープ確認

- 本番UIの見た目は置き換えていない。
- Todayスマートリストの仕様確定、DB query、FRB API、Rust API、domain/storage実装は行っていない。
- 外部アイコンセットや新規pub依存は追加していない。
- 新規画像アセットは追加していない。
- 本番i18nキーは追加していない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。
- `.github/` と `taskveil-private/` は変更していない。

### 独立調査

- subagent `Mendel` が既存visual QAの差し込み口を読み取り専用で確認し、Design Labはtest側に置くのが安全と報告した。
- その方針どおり、Design Labは `app/test/visual_qa/` 配下だけに追加した。

### 未解決事項

- なし。
