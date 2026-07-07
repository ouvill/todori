# task-59: チェック完了モーション

> ステータス: 完了（worker実装）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

2026-07-08のモーション体感レビューで、チェック完了時の気持ちよさについて人間裁定が出た。参照はAny.doの左から右へ伸びる取り消し線と、Xのハート操作に近いチェック起点の小パーティクルである。

task-56でチェックボックスの幾何、未チェックリング、チェックマークのpath描画は導入済みである。一方、現行のタイトル取り消し線は `TextDecoration.lineThrough` による静的表示で、完了遷移時に左から右へ伸びる表現はない。パーティクルも未実装である。

本タスクでは、既存の落ち着いたUI文法を維持したまま、チェックON時だけ「チェック線path描画 → チェック点から局所パーティクル → タイトル取り消し線の左から右への伸長」を実装する。celebration禁止規則は全廃しない。許容されるのは、チェックボックス起点・半径24px級・0.5秒級・ブランド色の局所パーティクルだけであり、画面全体のconfetti、トロフィー、音、全画面演出は引き続き禁止である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（チェックボックス表現、Homeスワイプ/モーション）と裁定済み事項
- `docs/design/visual-direction.md` の Completion Behavior
- `docs/tasks/task-53-swipe-and-motion.md`
- `docs/tasks/task-56-checkbox-polish.md`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- チェックON時に、チェックマークの線がpath描画として視認できる状態を維持・整理する。
- チェックON時に、タイトルの取り消し線が左から右へ伸びる遷移を追加する。
- チェックON時に、チェックボックス中心から6〜10粒の局所パーティクルを短く放射する。
- 一覧、Home、詳細画面タイトル横チェック、詳細画面Subtasksで同じ完了モーション文法を使う。
- Reduce Motion有効時は、パーティクルと取り消し線伸長を無効化し、即時状態変化にする。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/task_detail_screen.dart`（詳細タイトル横チェック/タイトル描画接続に必要な場合）
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`（必要な場合）
- `docs/tasks/task-59-check-completion-motion.md`（完了報告の追記のみ）

### やること

1. チェックマークのpath描画アニメーションを整理する。
   - `CustomPainter` + `PathMetric` 等で、チェック線が進行して描かれることを明確にする。
   - task-56の既存スケールインは、path描画を妨げない形で置換または統合してよい。
   - チェックONは250ms級、OFFは150ms級の静かな戻りを維持する。
2. タイトル取り消し線の左から右への伸長アニメーションを追加する。
   - `TextPainter` 等でタイトルの実レイアウトを計測し、複数行に対応する。
   - 複数行では、1行目から順に行ごとに連続して線が伸びるようにする。
   - 既存の `TextDecoration.lineThrough` は完了状態の静的表示として維持し、遷移時だけアニメーション描画で上書きする。
3. 完了パーティクルを追加する。
   - チェックボックス中心から6〜10粒を放射する。
   - 色はcoral / amber / sage系のブランド色に限定する。
   - 半径24px級、500ms級、fade + scale outに収める。
   - 完了時のみ発火し、再オープン/チェック解除時は出さない。
   - 一覧行と詳細画面タイトル横チェックの両方で発火する。
4. Reduce Motion分岐を実装する。
   - OSのアクセシビリティ設定でReduce Motion相当が有効な場合は、パーティクルと取り消し線伸長を無効化する。
   - Reduce Motion有効時も状態、色、静的取り消し線、semanticsは即時に正しく反映する。
5. widget testを追加・更新する。
   - チェックON/OFFの状態遷移を `pump` 進行で確認する。
   - Reduce Motion有効時に、パーティクル/伸長アニメーション分岐が使われず、即時状態になることを確認する。
   - 描画詳細のピクセル完全検証は不要だが、アニメーション中間時刻の破綻がないことは `pump` で確認する。
6. 完了報告に実装アニメーション一覧表を記録する。
   - 対象、実装箇所、duration、curve、Reduce Motion時の挙動を表にする。
   - 体感の最終受け入れは人間ドッグフーディングで行う旨を明記する。

### やらないこと

- 音の追加。
- ハプティクスの追加。
- チェック以外のモーション変更。
- 行挿入、行移動、セクション開閉、スワイプaction、D&Dの変更。
- チェック操作のステータス遷移、Undo、未完了子孫確認ダイアログの意味論変更。
- 画面全体のconfetti、トロフィー、全画面演出、マスコット主導のcelebration。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、`AppTaskCheckbox`、`_TaskCheckboxPainter`、`AppTaskRow`、`AppHomeTaskRow`、詳細画面タイトル行の描画経路を把握する。
3. チェックON/OFFの状態変化タイミング、Undoスナックバー、Closed/再オープン経路を確認し、モーションだけを差し込む位置を決める。
4. チェックマークのpath描画を、250ms級のON遷移で明確に進行するよう整理する。
5. タイトル用のアニメーション取り消し線ウィジェット/ペインターを追加し、通常行、Home行、詳細タイトルで共通利用できる形にする。
6. `TextPainter` で折返し後の行幅と行位置を計測し、複数行の取り消し線を行ごとに左から右へ描く。
7. チェックボックス中心を起点にした小パーティクルペインターを追加し、完了遷移時だけ500ms級で発火させる。
8. `MediaQuery.disableAnimations` 等のFlutter標準情報を使い、Reduce Motion時はパーティクルと伸長アニメーションをスキップする。
9. widget testを追加・更新し、通常モーション分岐とReduce Motion分岐を `pump` 進行で確認する。
10. 必要に応じてvisual QAを更新し、チェック完了後の静的最終状態に破綻がないことを確認する。
11. 品質ゲートを実行し、指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] チェックON時に、チェックマーク線が250ms級でpath描画されることが `pump` 進行または実装アニメーション一覧表で確認できる。
- [ ] タイトルの取り消し線が左から右へ300ms級で伸び、複数行タイトルでは行ごとに連続して伸びる実装になっている。
- [ ] 既存の `TextDecoration.lineThrough` が完了状態の静的表示として維持され、遷移時だけアニメーション描画で上書きされている。
- [ ] チェックON時のみ、チェックボックス中心から6〜10粒・半径24px級・500ms級・coral/amber/sage系の局所パーティクルが発火し、チェック解除/再オープン時は発火しない。
- [ ] 一覧、Home、詳細画面タイトル横チェック、詳細画面Subtasksで同じチェック完了モーション文法が使われている。
- [ ] Reduce Motion有効時はパーティクルと取り消し線伸長が無効化され、状態、色、静的取り消し線、semanticsが即時反映されることがwidget testで確認されている。
- [ ] チェックON/OFFの状態遷移とアニメーション中間時刻が、widget testの `pump` 進行で破綻しないことが確認されている。
- [ ] 完了報告に、実装アニメーション一覧表、追加・更新したテスト名、Reduce Motion確認、体感の最終受け入れは人間ドッグフーディングで行う旨が記録されている。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` の2026-07-08人間裁定（チェック完了モーション）を正とする。
- 48×48のチェックボックスタップ領域、tooltip/semantics、未完了は `done`、Closedは `todo` へ戻す既存トグル規則を維持する。
- 未完了子孫を持つ親を完了する場合の確認ダイアログとUndo経路を迂回しない。
- パーティクルはチェックボックス起点の局所表現に限定する。画面全体へ広がる粒子、confetti、トロフィー、音、全画面演出は入れない。
- パーティクル色は既存ブランド色（coral / amber / sage系）を使い、新しい色トークンを発明しない。
- 総時間は800ms以内に収め、操作をブロックしない。連続タップやUndoで状態が変わっても古いアニメーションが意味の違う状態を描き続けないようにする。
- Reduce Motion時は、動きのために状態反映を遅らせない。
- UI文字列を追加する場合はARB化する。ただし本タスクは原則として新規表示文言を追加しない。
- 新規依存は追加しない。既存のFlutter標準API、CustomPainter、既存依存の範囲で実装する。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- チェックマークpath描画の実装箇所、duration、curve
- 取り消し線伸長の実装箇所、TextPainter計測方法、複数行対応の方法
- 完了パーティクルの実装箇所、粒数、半径、duration、色、発火条件
- Reduce Motion分岐の実装箇所と確認結果
- 一覧、Home、詳細画面タイトル横チェック、詳細画面Subtasksへの適用確認
- 追加・更新したwidget test名と検証対象
- 実装アニメーション一覧表（対象、実装箇所、duration、curve、Reduce Motion時の挙動）
- visual QAを更新した場合はスクリーンショットの保存パス
- 体感の最終受け入れは人間ドッグフーディングで行う旨
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-08

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3、裁定済み事項
- `docs/design/visual-direction.md` Completion Behavior
- `docs/tasks/task-53-swipe-and-motion.md`
- `docs/tasks/task-56-checkbox-polish.md`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

実装結果:

- `app/lib/src/ui/task_components.dart` の `AppTaskCheckbox` を `StatefulWidget` 化し、既存の `_TaskCheckboxPainter` によるチェックマークpath描画を維持した。
- `AppTaskCheckbox` にチェックON遷移時のみ発火する `_CompletionParticles` / `_CompletionParticlesPainter` を追加した。
- `AppAnimatedTaskTitle` / `_AnimatedStrikethroughPainter` を追加し、通常行、Home行、詳細画面タイトルで使用した。
- `app/lib/src/screens/task_detail_screen.dart` の詳細タイトル読み取り表示を `AppAnimatedTaskTitle` へ接続した。
- 新規pub/crate依存は追加していない。
- UI表示文言は追加していない。

チェックマークpath描画:

- 実装箇所: `app/lib/src/ui/task_components.dart` `AppTaskCheckbox` / `_TaskCheckboxPainter`
- ON duration: 250ms
- ON curve: `Curves.easeOutBack`
- OFF duration: 150ms
- OFF curve: `Curves.easeOutCubic`
- path描画方法: `Path.computeMetrics().single.extractPath(0, metric.length * checkProgress)` でチェック線を進行描画する。
- Reduce Motion時: `TweenAnimationBuilder` のdurationを `Duration.zero` にし、状態を即時表示する。

取り消し線伸長:

- 実装箇所: `app/lib/src/ui/task_components.dart` `AppAnimatedTaskTitle` / `_AnimatedStrikethroughPainter`
- duration: 300ms
- curve: `Curves.easeOutCubic`
- TextPainter計測方法: `TextPainter` に同じ `TextSpan`、`TextStyle`、`StrutStyle`、`maxLines`、`ellipsis`、`TextScaler`、`Locale`、`TextDirection` を渡し、`layout(maxWidth: size.width)` 後に `computeLineMetrics()` を取得する。
- 複数行対応: `progress * lines.length` を行ごとの進捗へ分配し、1行目から順に `line.width * lineProgress` まで線を描画する。
- 静的表示: 完了状態では既存どおり `TextDecoration.lineThrough` を指定し、遷移中のみオーバーレイ描画で取り消し線を描く。
- Reduce Motion時: オーバーレイ描画を出さず、`TextDecoration.lineThrough` を即時表示する。

完了パーティクル:

- 実装箇所: `app/lib/src/ui/task_components.dart` `_CompletionParticles` / `_CompletionParticlesPainter`
- 粒数: 8
- 半径: 最大24px
- duration: 500ms
- easing: 移動 `Curves.easeOutCubic`、fade `Curves.easeInCubic`
- 色: `_priorityHighCoral`、`_priorityMediumAmber`、`_priorityLowSoftSage`
- 発火条件: `AppTaskCheckbox.didUpdateWidget` で `isDone` が `false` から `true` に変化し、Reduce Motionでない場合のみ発火する。
- チェック解除/再オープン時: controllerを停止し、値を0へ戻す。粒子は発火しない。
- Reduce Motion時: `_CompletionParticles` を配置しない。

適用確認:

- 一覧: `AppTaskRow` のタイトルを `AppAnimatedTaskTitle` へ置換し、チェックは既存どおり `AppTaskCheckbox` を使用する。
- Home: `AppHomeTaskRow` のタイトルを `AppAnimatedTaskTitle` へ置換し、チェックは既存どおり `AppTaskCheckbox` を使用する。
- 詳細画面タイトル横チェック: `task_detail_screen.dart` で既存どおり `AppTaskCheckbox` を使用する。
- 詳細画面タイトル: `_InlineTitleEditor` の読み取り表示を `AppAnimatedTaskTitle` へ置換した。
- 詳細画面Subtasks: `AppTaskRow` 経由で同じ `AppTaskCheckbox` と `AppAnimatedTaskTitle` を使用する。

追加・更新したwidget test:

- 追加: `completion motion exposes intermediate particle and strike frame`
  - 通常モーションでチェックON後150ms時点に `task-completion-particles` と `task-strikethrough-overlay` が存在し、完了後に静的 `TextDecoration.lineThrough` になることを確認した。
- 追加: `completion motion is skipped when reduce motion is enabled`
  - `MediaQueryData(disableAnimations: true)` でチェックON後にパーティクル/伸長オーバーレイが出ず、静的 `TextDecoration.lineThrough` が即時表示されることを確認した。
- 既存実行: `checking a task marks it done through the bridge service`
- 既存実行: `nested task row checkbox toggles done todo done`
- 既存実行: `detail subtask checkbox toggles without triggering row navigation`
- `cd app && flutter test` 全体で90件実行、visual QA harness 1件skip。

visual QA:

- 作業前退避先: `app/build/visual_qa_before/`
- 作業前退避PNG数: 36
- 実装後出力先: `app/build/visual_qa/`
- 実装後PNG数: 37
- 追加スクリーンショット: `app/build/visual_qa/completion_motion_midframe.png`
- `completion_motion_midframe.png` はチェックON後90ms時点をpump制御で撮影し、チェック起点の粒子と複数行タイトル2行目の取り消し線途中フレームを目視した。

実装アニメーション一覧:

| 対象 | 実装箇所 | トリガー | duration | curve | Reduce Motion時の挙動 |
|---|---|---|---:|---|---|
| チェックマークpath描画 | `AppTaskCheckbox` / `_TaskCheckboxPainter` | `isDone: false -> true` | 250ms | `Curves.easeOutBack` | duration 0msで即時表示 |
| チェックOFF戻り | `AppTaskCheckbox` / `_TaskCheckboxPainter` | `isDone: true -> false` | 150ms | `Curves.easeOutCubic` | duration 0msで即時表示 |
| 完了パーティクル | `_CompletionParticles` / `_CompletionParticlesPainter` | `isDone: false -> true` | 500ms | 移動 `Curves.easeOutCubic` / fade `Curves.easeInCubic` | 描画しない |
| タイトル取り消し線伸長 | `AppAnimatedTaskTitle` / `_AnimatedStrikethroughPainter` | `isDone: false -> true` | 300ms | `Curves.easeOutCubic` | オーバーレイを描画せず静的取り消し線を即時表示 |

モーション最終受け入れ:

- モーションは静止画で検証できないため、体感の最終受け入れは人間ドッグフーディングで行う。

品質ゲート:

- `cargo fmt --all -- --check`: exit 0
- `cargo clippy --workspace -- -D warnings`: exit 0
- `cargo test --workspace`: exit 0
- `cd app && flutter analyze`: exit 0
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
- `cd app && flutter test`: exit 0（90件実行、visual QA harness 1件skip）
- `sh app/tool/check_hardcoded_strings.sh`: exit 0
- `sh app/tool/visual_qa.sh`: exit 0（37件実行）
- `git diff --check`: exit 0

変更ファイル一覧:

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/README.md`
- `docs/tasks/task-59-check-completion-motion.md`

未解決事項:

- なし
