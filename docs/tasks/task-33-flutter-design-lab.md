# task-33: Flutter Design Lab ── visual QA based design mock playground

> ステータス: 未着手
> 作業日: -

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
- 本番theme（`buildTodoriTheme`）、既存spacing、Material Icons、実フォント読み込みを使う。
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
- `.github/` と `todori-private/` は変更しない。

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

- [ ] `sh app/tool/visual_qa.sh` で `design_lab_*.png` が3枚以上生成される。
- [ ] 既存のvisual QA PNG（home/list/detail/trash/dialog等）も引き続き生成される。
- [ ] 通常の `cd app && flutter test` ではvisual QA harnessがskipされ、Design LabがCI標準ゲートへ混入しない。
- [ ] Design Labは本番route/provider/DB/FRB/Rust APIに依存しないtest-only widgetである。
- [ ] Design Labは本番theme/font/spacingを使い、実際のFlutter制約内で表示される。
- [ ] 3案の違いがスクリーンショット上で明確に比較できる。
- [ ] 日本語/英語混在タイトル、長文、priority/due/completed表現が破綻しない。
- [ ] 外部依存、新規画像アセット、本番i18nキーを追加していない。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `git diff --check` が成功している。
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [ ] `.github/` と `todori-private/` が変更されていない。

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
- `.github/` と `todori-private/` を変更していないこと
- 未解決事項（なければ「なし」）
