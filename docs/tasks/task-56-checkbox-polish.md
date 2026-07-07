# task-56: チェックボックスpolish

## 1. 背景とコンテキスト

2026-07-08ドッグフーディング第5回で、チェックボックス周辺に3件のフィードバックが出た。

1. ツリー表示でチェックマークの丸と縦線がずれている。
2. チェックするのが楽しくなるようにチェックマークをアニメーションさせたい。
3. チェック前の円の線が太い。

task-45で階層ガイドは導入済みで、task-53でスワイプと軽量モーション、`flutter_animate` が導入済みである。本タスクでは、チェックボックスと階層ガイドの幾何・見た目・マイクロモーションだけを磨き込む。行レイアウト全体やスワイプ/セクション開閉のモーション設計は変更しない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（タスク行解剖図、階層ガイド規則、チェックボックス表現、Homeスワイプ/モーション）
- `docs/tasks/task-45-tree-guides-and-detail.md`
- `docs/tasks/task-49-detail-refinements.md`
- `docs/tasks/task-53-swipe-and-motion.md`（完了報告の既存アニメーション一覧を含む）
- `docs/tasks/task-55-home-subtree-nesting.md`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- ツリー表示で、階層ガイドの縦線・横棒・チェックボックス中心を同じ幾何基準へ揃える。
- 未チェックリングを細く、mutedな表現へ調整する。
- チェックON時に小さく気持ちよいスケールインを加え、OFF時は静かに戻す。
- 一覧、Home、詳細画面タイトル横チェック、詳細画面Subtasksのチェック表現を同じ文法へ揃える。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`（階層ガイド引数や詳細画面接続の調整が必要な場合）
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-56-checkbox-polish.md`（完了報告の追記のみ）

### やること

1. 階層ガイドの幾何を修正する。
   - 縦線の起点は親チェックボックス中心のx座標に揃える。
   - 子の横棒は、親中心から降りる縦線から子チェックボックスの垂直中心の高さへ接続する。
   - 3階層ツリーで、各深さの子チェックボックス中心が同一のx座標列に整列することを確認する。
2. 未チェックリングを調整する。
   - strokeは1.5px級に細くする。
   - 色は `onSurfaceVariant` 系のmuted色にする。
   - 48px級タップ領域、tooltip/semantics、既存トグル規則は維持する。
3. チェックアニメーションを調整する。
   - チェックON時は塗りとチェックアイコンがスケールインする。
   - durationは250ms級、curveは軽いオーバーシュートを持つ `easeOutBack` 系を使う。
   - チェックOFF時は150ms級の控えめなフェードで未チェックリングへ戻す。
   - 既存依存の `flutter_animate` は使用してよい。新規依存は追加しない。
4. 詳細画面のタイトル横チェックにも同じ表現を適用する。
   - 一覧/ネスト行/詳細タイトル横/詳細Subtasksで見た目とON/OFFモーションの文法を揃える。
5. widget testを追随させる。
   - アニメーション自体の体感評価はテストしない。
   - `pump` 進行で、チェックON/OFF後の状態遷移と最終表示が破綻しないことまで確認する。
6. visual QAを更新する。
   - 3階層ツリーを含む `home_tasks` と `task_detail` のスクリーンショットで整列を目視できるようにする。
   - モーションの最終受け入れは人間ドッグフーディングで行う旨を完了報告に明記する。

### やらないこと

- スワイプ動作やスワイプ表示の変更。
- 行挿入、完了行移動、セクション開閉アニメーションの変更。
- チェック以外のタスク行レイアウト変更。
- Homeセクション構造やサブツリー表示規則の変更。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、`AppTaskCheckbox`、`_TaskHierarchyGuide`、`AppTaskRow`、`AppHomeTaskRow`、詳細画面タイトル行のチェック接続を把握する。
3. 現行のチェックボックス中心x、階層ガイドx、子行インデント、横棒長の関係を整理する。
4. 親チェックボックス中心から縦線が降り、子チェックボックス中心高さへ横棒が接続するように `_TaskHierarchyGuide` と呼び出し側の座標を調整する。
5. `AppTaskCheckbox` を、未チェックリングstroke 1.5px級・muted色、チェックONスケールイン、OFF短時間フェードの表現へ調整する。
6. 詳細画面タイトル横チェックが `AppTaskCheckbox` と同じ表現を使っていることを確認し、不足があれば接続を揃える。
7. widget testを更新し、`pump` 進行後のチェックON/OFF状態と3階層表示の存在を確認する。
8. `sh app/tool/visual_qa.sh` を実行し、`home_tasks` と `task_detail` の3階層表示を目視確認する。
9. 品質ゲートを実行し、指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 階層ガイドの縦線が親チェックボックスの水平中心から降り、子の横棒が子チェックボックスの垂直中心へ接続していることが、3階層visual QAスクリーンショットで確認できる。
- [ ] 各深さの子チェックボックス中心が同一のx座標列に整列していることが、`home_tasks` または通常リストの3階層表示で確認できる。
- [ ] 未チェックリングが1.5px級stroke、`onSurfaceVariant` 系muted色になり、48px級タップ領域とtooltip/semanticsが維持されている。
- [ ] チェックON時に塗りとチェックマークが250ms級・軽いオーバーシュートでスケールインし、OFF時は150ms級の控えめなフェードで戻る。
- [ ] 一覧、Home、詳細画面タイトル横チェック、詳細画面Subtasksで同じチェック表現とトグル規則が使われている。
- [ ] チェックON/OFFの状態遷移が、widget testの `pump` 進行で確認されている。
- [ ] visual QAに `home_tasks` と `task_detail` の3階層ツリー確認用スクリーンショットが保存されている。
- [ ] 完了報告に、座標基準、stroke/色、duration/curve、更新したテスト、visual QAパス、モーション最終受け入れが人間ドッグフーディングである旨が記録されている。

## 7. 制約・注意事項

- `AppTaskCheckbox` の48×48タップ領域を縮めない。
- チェック操作の意味論を変えない。未完了は `done`、Closedは `todo` へ戻す既存規則を維持する。
- 未完了子孫を持つ親を完了する場合の確認ダイアログとUndo経路を迂回しない。
- 階層ガイド調整のために、タスク行タイトル、メタデータ、Home行右側メタデータ、スワイプactionのレイアウトを変更しない。
- モーションは150〜250ms級に留める。celebration、confetti、紙吹雪、強いバウンス、長い遅延は入れない。
- task-53の既存モーション（行挿入、Closed領域開閉、Homeセクション開閉）を変更しない。
- 新規依存は追加しない。`flutter_animate` はtask-53で導入済みのため使用してよい。
- UI文字列を追加する場合はARB化する。ただし本タスクは原則として新規表示文言を追加しない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 階層ガイドの座標基準と変更箇所
- 3階層でのチェックボックス中心列とガイド接続の確認結果
- 未チェックリングのstroke/色、48pxタップ領域、tooltip/semantics維持の確認
- チェックON/OFFモーションのduration、curve、実装箇所
- 詳細画面タイトル横チェックへの適用確認
- 追加・更新したwidget test名と検証対象
- visual QAスクリーンショットの保存パス（`home_tasks` / `task_detail`）
- モーションの最終受け入れは人間ドッグフーディングで行う旨
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）
