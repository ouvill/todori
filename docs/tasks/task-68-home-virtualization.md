# task-68: Home/Tasksリスト描画の仮想化

> ステータス: 完了（2026-07-08）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

task-67の性能検証で、Rust storage層の起動近似は123msである一方、Flutter Homeの1万件fake seed初期pumpが21秒台になることが判明した。Home横断クエリは7140行相当を返しており、現状のFlutter UIはHomeパネル内の全行Widgetを初期pump時に実体化している。

本タスクでは、Home（および必要なTasks画面）のリスト描画をSliverベースの遅延構築へ移行し、可視行中心の構築へ変える。視覚・操作・完了遅延遷移・チェックモーション・スワイプ・D&D・階層ガイドは既存仕様を維持する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/task-67-performance-verification.md`
- `docs/07_Phase1計画書.md` M4-04
- `docs/02_機能仕様書.md` F-50〜F-52
- `app/lib/src/screens/home_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/task_tree.dart`
- `app/test/performance_large_data_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`

## 3. ゴール

- Homeを `CustomScrollView` + Sliverベースの遅延構築へ移行し、初期pumpで全行Widgetを構築しないこと。
- 必要に応じてTasks画面も同じ方針へ移行し、単一リスト1000件でも全行Widget実体化を避けること。
- Homeの単一パネルのwarm white面、角丸、区切り線、セクション見出し、折りたたみ、クイック追加バー、スクロール挙動を維持すること。
- 完了遅延遷移、チェックアニメ、スワイプ、D&D、階層ガイドが遅延構築下でも壊れないこと。
- task-67のFlutter性能テストを再実行し、Home 7140件相当のpump時間をbefore/afterで記録すること。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/screens/tasks_screen.dart`
- `app/test/performance_large_data_test.dart`
- `docs/tasks/task-68-home-virtualization.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `README.md`（必要なら性能検証メモ）

### やること

1. Homeの `ListView` / `Column` による全行構築を、`CustomScrollView` と `SliverList.builder` / `SliverChildBuilderDelegate` へ移行する。
2. Homeパネル面は `DecoratedSliver` 等で表現し、既存の面・角丸・border・padding・section dividerを維持する。
3. Home sectionの行データは軽量な構造体として保持し、実際の行Widgetはbuilder内で構築する。
4. 通常Tasks画面も、active/closedの行Widgetを事前生成している箇所をSliver遅延構築へ移行する。
5. 行Stateのkeyを既存と同等に安定させる。画面外へ出た行のアニメStateリセットは許容するが、Homeのペンディング退場ロジックは維持する。
6. task-67のFlutter大量データテストをtask-68のafter計測として再実行し、before値と比較する。
7. visual QAスクリーンショットをbefore退避とafter生成で比較し、視覚回帰の有無を完了報告へ記録する。
8. 品質ゲートを実行し、実行不能なものは環境起因として記録する。

### やらないこと

- Rust storage API、FRB API、DB schema、migrationの変更。
- Home取得件数制限、ページング、検索UI、同期機能の実装。
- UIの見た目・情報設計・文言の変更。
- 新規依存追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` の変更。
- git commit。

## 5. 実装手順（例）

1. `git status --short` で作業前状態を確認する。
2. task-67の完了報告、Home/Tasksの描画構造、performance test、visual QA harnessを読む。
3. 作業前のvisual QAスクリーンショットを退避する。
4. Home section builderを、行Widgetではなく `_HomeSectionRowData` を返す形に変更する。
5. `_HomeSectionsPanel` / `_HomeSection` をSliver化し、section headerと行をSliverで遅延構築する。
6. 通常Tasks画面のactive/closed行もSliver builderで構築する。
7. `flutter analyze` と対象widget testを早めに実行し、key・semantics・D&D・swipeの破損を検出する。
8. `cd app && flutter test test/performance_large_data_test.dart --reporter expanded` でafter値を取得する。
9. visual QAをafter生成し、before退避と目視比較する。
10. 品質ゲートを実行する。
11. 本ファイルへ `## 9. 完了報告` を追記し、README/BACKLOGを更新する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] Homeが `CustomScrollView` + Sliverベースの遅延構築になり、Home section行Widgetを初期buildで全件生成しない。
- [ ] Tasks画面のactive/closed行も、必要な範囲でSliver builderによる遅延構築になっている。
- [ ] Homeの単一パネル面、角丸、区切り線、セクション見出し、折りたたみ、クイック追加バー、スクロール挙動が既存視覚と一致している。
- [ ] 完了遅延遷移、チェックアニメ、スワイプ、D&D、階層ガイドの既存widget testが成功している。
- [ ] task-67のFlutter性能テスト再実行により、Home 7140件相当のpump時間before/afterが完了報告に記録されている。
- [ ] visual QAのbefore/afterスクリーンショットを生成し、目視比較結果と成果物パスが完了報告に記録されている。
- [ ] README/BACKLOGにtask-67未解決事項からtask-68へ引き継いだことが記録されている。
- [ ] 新規依存、Rust API変更、FRB生成物変更がない。

## 7. 制約・注意事項

- 見た目は変更しない。Homeのwarm white単一パネル、内部padding、角丸、border、section divider、行dividerは既存と同じ視覚を維持する。
- `SliverList.builder` へ移す際、行に渡す `ValueKey('task-row-$id')`、checkbox key、swipe key、D&D key、hierarchy guide keyを維持する。
- Home完了遅延遷移は、データ更新後もpending行スナップショットを保持して退場させる既存ロジックを壊さない。
- 画面外へ出た行のentry animation stateリセットは許容する。ただしデータ凍結pending、Undo、reopen、due変更の操作結果は壊してはならない。
- `DecoratedSliver` / `SliverPadding` / `SliverMainAxisGroup` 等のFlutter標準Sliverを優先し、新規依存は追加しない。
- visual QAはフォント差分・時刻差分を考慮し、同一環境でbefore/afterを生成して比較する。

## 8. 完了報告に含めるべき内容

- 作業日、読んだファイル
- 実装方式（Home/TasksそれぞれのSliver化範囲）
- Home 7140件相当のpump時間before/after
- Tasks単一リスト1000件pump時間before/after
- visual QA before/after成果物パスと目視比較結果
- 完了遅延遷移、チェックアニメ、スワイプ、D&D、階層ガイドの検証結果
- 変更ファイル一覧
- 品質ゲート実行結果
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-08

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/task-67-performance-verification.md`
- `docs/07_Phase1計画書.md` M4-04
- `docs/02_機能仕様書.md` F-50〜F-52
- `app/lib/src/screens/home_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/core/task_tree.dart`
- `app/test/performance_large_data_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/widget_test.dart`

実装方式:

- Home: `ListView` + `Column` + 全行Widget生成を廃止し、`CustomScrollView` / `SliverPadding` / `SliverMainAxisGroup` / `DecoratedSliver` / `SliverList.builder` へ移行した。
- Home panel: 既存のwarm white面・角丸・border・内部padding・section dividerを `DecoratedSliver` とSliver内dividerで維持した。
- Home section: `_HomeSectionData.rows` を `List<Widget>` から `List<_HomeSectionRowData>` へ変更し、行Widgetはbuilder内で `_buildHomeTaskRow` を呼んで構築する形にした。
- Home closed section: closed rowも `_HomeSectionRowData` として保持し、展開時のみ `SliverList.builder` で構築する形にした。
- Tasks: active/closed行の全件Widget生成を廃止し、通常リストも `CustomScrollView` + `_TaskRowsSliver` + `SliverList.builder` へ移行した。
- 行key: `task-row-$id` / `task-done-$id` / `task-swipe-actions-$id` / `task-drop-target-$id` / hierarchy guide keyを維持し、Home行shellにも `task-home-row-shell-$id` keyを追加した。

Flutter widget test計測結果:

| 画面 | before | after（単体性能test） | after（全体test内） | 備考 |
|---|---:|---:|---:|---|
| Home | 21304ms | 630ms | 802ms | total 10000 / Home表示scope 7140相当 |
| Tasks | 1019ms | 132ms | 166ms | total 10000 / 単一リスト1000 |

実行コマンド:

- `cd app && flutter test test/performance_large_data_test.dart --reporter expanded`
- `cd app && flutter test --reporter expanded`

visual QA:

- before: `app/build/visual_qa_task68_before/`（43 PNG）
- after: `app/build/visual_qa_task68_after/`（43 PNG）
- 生成コマンド: `sh app/tool/visual_qa.sh`
- 比較コマンド: `diff -qr app/build/visual_qa_task68_before app/build/visual_qa_task68_after`
- 比較結果: 差分なし。43 PNGがbefore/afterで一致。
- 目視確認: `home_tasks.png`、`home_tasks_text_scale_2.png`、`task_list_reorder_dragging.png`、`task_swipe_complete_leading.png`、`quick_add_home_normal.png` を確認し、Homeパネル、Dynamic Type、D&D、swipe、quick add barの崩れなし。全43枚はbyte-identicalで視覚差分なし。

完了遅延遷移・チェックアニメ・スワイプ・D&D・階層ガイドの検証:

- `cd app && flutter test --reporter expanded`: 成功（116 passed、visual QA harness 1 skipped）。
- 既存widget testで、Home completion pending、completion motion、leading/trailing swipe、Home due swipe、task list D&D、hierarchy guide、closed subtree、semanticsを確認した。
- 仮想化により画面外行が初期widget treeに存在しなくなったため、該当widget test 2件は `scrollUntilVisible` で対象行を可視化してから検証する形に更新した。

変更ファイル一覧:

- `README.md`
- `app/lib/src/screens/tasks_screen.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-68-home-virtualization.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

品質ゲート実行結果:

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（task-67性能ignored 1件、real Keychain ignored 1件は既存方針どおり）。
- `cd app && flutter analyze`: 成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test --reporter expanded`: 成功（116 passed、visual QA harness 1 skipped）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git diff --check`: 成功。
- `sh app/tool/visual_qa.sh`: 成功（41 screenshot tests、出力43 PNG）。
- `diff -qr app/build/visual_qa_task68_before app/build/visual_qa_task68_after`: 差分なし。

未解決事項:

- なし。
