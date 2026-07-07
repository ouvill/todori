# task-60: チェック完了モーション受け入れFBの精度改善

> ステータス: 完了（2026-07-08）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

task-59でチェック完了モーションを実装し、チェック線path描画、局所パーティクル、左から右へ伸びる取り消し線、Reduce Motion分岐が入った。2026-07-08のモーション体感受け入れでは、方向性は維持したまま、精度に関するフィードバックが3件出た。

1. チェックのタップエリアとタップ時エフェクト（Ink波紋）の中心が、チェック円の中心とずれている。
2. 取り消し線アニメの線と、完了後の静的取り消し線の高さ/位置がずれる。終了瞬間にジャンプが見える。
3. セクション単独表示のタスク（メインタスクや期日付きサブタスク）は、完了するとアニメ描画前に行が消える/移動するため、完了モーションが見えない。

本タスクは、task-59の表現パラメータを増やすのではなく、受け入れFBで見つかった幾何・描画経路・Home再構成タイミングを整える。体感の最終受け入れは引き続き人間ドッグフーディングで行う。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（チェックボックス表現、チェック完了モーションの精度補足、Homeセクション）
- `docs/tasks/task-59-check-completion-motion.md` と完了報告
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- チェック円、48px級ヒット領域、Ink波紋を同心に揃える。
- 取り消し線のアニメ終了フレームと完了静止状態をピクセル一致させ、終了瞬間のジャンプをなくす。
- Homeで完了により別セクションへ移る/Closedへ移る/消える単独表示行でも、完了モーションが見えるように遅延退場させる。
- 行ごとのペンディング状態で、複数同時完了、連打、アニメーション中の再オープンを破綻させない。
- Reduce Motion有効時は遅延せず、従来どおり即時に再構成する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`（詳細タイトル横チェック/取り消し線経路に必要な場合）
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`（必要な場合）
- `docs/tasks/task-60-motion-refinement.md`（完了報告の追記のみ）

### やること

1. チェックのInkResponse/ヒット領域をチェック円中心に同心化する。
   - 視覚左寄せ後のオフセットを修正し、48pxタップ領域は維持する。
   - チェック円中心、ヒット領域中心、Ink波紋中心が一致する構造にする。
   - widget testでヒット中心を検証可能なら検証する。難しい場合は実装上の幾何値と目視証拠を完了報告へ記録する。
2. 取り消し線の描画を統一する。
   - アニメ用CustomPainterの線位置・太さを完了静止状態と完全一致させる。
   - 方式は自由とする。静止状態も同じpainterで描く、または `TextDecoration` のメトリクスへ整合させる。
   - 折返し各行で一致させ、終了時の高さ/位置/太さのジャンプをなくす。
3. 完了時の遅延遷移を実装する。
   - Homeの単独表示行を完了した場合、行をその場に留めて完了モーションを再生し、完了後に約200msのフェードアウトまたはスライドアウトを行ってからセクション再構成を反映する。
   - 対象は、完了により日付セクションからClosedへ移るルートタスク、表示中祖先下へ移るサブタスク、Homeから非表示になる単独表示行を含む。
   - 行別のペンディング状態管理で、複数同時完了、連打、アニメーション中の再オープンに耐える。
   - Undoスナックバーの表示タイミングは従来どおり維持する。
   - Reduce Motion有効時はペンディング遅延を使わず、即時に再構成する。
4. widget testを追加・更新する。
   - ペンディング中の行残留から再構成までを `pump` 進行で検証する。
   - 連打またはアニメーション中の再オープンで古いペンディング状態が残らないことを検証する。
   - Reduce Motion有効時に即時再構成されることを検証する。
5. 必要に応じてvisual QAを更新する。
   - 完了モーション中間フレームまたは退場直前フレームを保存し、人間が体感確認しやすい証拠を残す。

### やらないこと

- パーティクル粒数、半径、色、チェック描画そのもののパラメータ変更。
- チェック以外のモーション刷新。
- Home以外の再構成挙動変更。
- 完了/再オープンのステータス意味論変更。
- Undoスナックバーの仕様変更。
- 未完了子孫確認ダイアログの意味論変更。
- 画面全体のconfetti、トロフィー、音、全画面演出。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、`AppTaskCheckbox`、`AppAnimatedTaskTitle`、`_AnimatedStrikethroughPainter`、`AppTaskRow`、`AppHomeTaskRow`、`_buildHomeSections`、`_buildHomeClosedRows`、`_buildHomeTaskRow` の現行経路を把握する。
3. `AppTaskCheckbox` の48px領域、視覚円の配置、`InkResponse` の配置を確認し、ヒット領域中心とチェック円中心を一致させる。
4. 取り消し線のアニメ描画と完了静止描画のどちらを正本にするか決め、同じ計測値・同じline y・同じstroke widthで描かれるようにする。
5. Homeの完了操作時に、対象task idごとのペンディング完了状態を保持する。
6. ペンディング中は、旧セクション位置に行を残しつつ表示状態だけ完了扱いにして、チェック/取り消し線モーションを再生する。
7. 約800ms後に退場アニメーションを開始し、約200ms後にペンディング状態を外して通常の `_buildHomeSections` / `_buildHomeClosedRows` 再構成へ戻す。
8. 再オープン、Undo、同一task idの再操作、widget更新で、古いtimer/controllerが残らないようにdispose/cancelする。
9. `MediaQuery.disableAnimations` 等でReduce Motionを検出し、有効時は遅延退場をスキップする。
10. widget testと必要なvisual QAを追加・更新する。
11. 品質ゲートを実行し、指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] チェック円、48px級ヒット領域、Ink波紋中心が同心であり、48px級タップ領域が維持されていることがwidget testまたは完了報告の幾何説明で確認できる。
- [ ] 取り消し線のアニメ終了フレームと完了静止状態が、単一行・複数行とも同じ高さ/太さ/位置で描かれ、終了時ジャンプがないことがwidget test、golden/visual QA、または実装証拠で確認できる。
- [ ] Homeの単独表示行を完了したとき、完了モーション中は旧位置に行が残り、約800ms後の退場を経てからセクション再構成されることがwidget testで確認されている。
- [ ] 完了によりClosedへ移るルートタスク、表示中祖先下へ移るサブタスク、Homeから非表示になる単独表示行の少なくとも主要2経路がテストされている。
- [ ] 複数同時完了、連打、アニメーション中の再オープンで、古いペンディング行やtimerが残らないことがwidget testで確認されている。
- [ ] Undoスナックバーの表示タイミングとUndo実行経路が従来どおり維持されていることが確認されている。
- [ ] Reduce Motion有効時はペンディング遅延・退場モーションが使われず、即時に再構成されることがwidget testで確認されている。
- [ ] 完了報告に、ヒット領域同心化の実装箇所、取り消し線統一方式、Home遅延遷移の状態管理、追加・更新したテスト名、体感の最終受け入れは人間ドッグフーディングで行う旨が記録されている。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` の「チェック完了モーションの精度補足（2026-07-08#受け入れFB由来）」を正とする。
- task-59のチェック完了モーション方向性を維持する。粒数、半径、色、チェック線path描画durationなどは原則変更しない。
- 48px級タップ領域、tooltip/semantics、未完了は `done`、Closedは `todo` へ戻す既存トグル規則を維持する。
- 未完了子孫を持つ親を完了する場合の確認ダイアログとUndo経路を迂回しない。
- 遅延遷移はHomeの表示再構成に限定する。通常リスト画面、詳細画面Subtasks、詳細タイトルの再構成意味論を巻き込まない。
- ペンディング中の行は表示上の一時状態であり、DB上のステータス更新やUndo履歴の意味論を変更しない。
- Reduce Motion時は、動きのために状態反映を遅らせない。
- UI文字列を追加する場合はARB化する。ただし本タスクは原則として新規表示文言を追加しない。
- 新規依存は追加しない。既存のFlutter標準API、CustomPainter、AnimationController、Timer等の範囲で実装する。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- チェック円/ヒット領域/Ink波紋中心を同心化した実装箇所と幾何値
- 取り消し線描画統一の方式、実装箇所、単一行/複数行の整合方法
- Home遅延遷移の実装箇所、ペンディング状態のデータ構造、timer/controllerのcancel方針
- 完了によりClosedへ移るルート、表示中祖先下へ移るサブタスク、Home非表示になる単独表示行への適用確認
- 連打、複数同時完了、アニメーション中再オープン、Undoとの整合確認
- Reduce Motion分岐の実装箇所と確認結果
- 追加・更新したwidget test名と検証対象
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
- `docs/tasks/task-59-check-completion-motion.md` と完了報告
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

実装結果:

- `app/lib/src/ui/task_components.dart` の `AppTaskCheckbox` で、48x48の `SizedBox` 内に22x22のチェック円を `Center` 配置し、`_taskCheckboxVisualCenterOffset` を24.0へ変更した。
- `InkResponse` の `radius` は24.0、`containedInkWell: true`、`CircleBorder` を維持した。チェック円中心、48x48ヒット領域中心、Ink波紋中心、パーティクル起点は同じ48x48領域中心になった。
- 階層ガイド計算は `_taskCheckboxVisualCenterOffset` を参照する既存経路のまま、チェック中心変更に追従した。
- `AppAnimatedTaskTitle` は完了状態の静止表示でも `TextDecoration.lineThrough` を使わず、`_AnimatedStrikethroughPainter` をprogress 1.0で使う方式へ変更した。
- アニメ中と静止中の取り消し線は同じ `TextPainter` 計測、同じline y計算、同じstroke width計算、同じCustomPainterで描画される。単一行・複数行とも同じ経路で描画される。
- `app/lib/src/screens/tasks_screen.dart` のHome表示に `_pendingHomeCompletions`、`_pendingHomeCompletionTimers`、`_homeCompletionOperations` を追加した。
- ペンディング状態は `taskId -> _PendingHomeCompletion` のMapで、旧セクション、旧行index、完了表示用スナップショット行、件数加算対象かどうかを保持する。
- Homeで完了した単独表示行は、通常再構成から同一task idを一時除外し、旧セクション位置に完了表示のスナップショットを差し込む。800ms後に `_PendingHomeExitPhase.exiting` へ移し、200msのfade/translate後にMapから削除する。
- timerは `_pendingHomeCompletionTimers` にtask id単位で保持し、dispose、再オープン、キャンセル、外部更新時にcancelする。
- 完了操作中の再オープンは `_homeCompletionOperations[taskId]` のFuture完了を待ってからpendingをcancelし、`todo` へ戻す。
- Reduce Motion有効時は `_handleHomeCompleteTask` でpendingを作らず、従来どおり `onCompleteTask` を即時実行する。
- 未完了子孫を持つタスクは既存確認ダイアログ経路を維持し、pending遅延を使わない。
- Undoスナックバーの表示タイミングとUndo実行経路は `_showLatestUndoSnackBar` / `_applyUndo` の既存実装を変更していない。
- 新規pub/crate依存は追加していない。
- UI表示文言は追加していない。

適用確認:

- 完了によりClosedへ移るルートタスク: `home completion keeps standalone root until delayed exit` で、旧位置残留、800ms後退場、Closed再構成をpump制御で確認した。
- 表示中祖先下へ移るサブタスク: `home completion keeps standalone subtask before moving under ancestor` で、Today単独表示から完了後に親の下へ移る経路をpump制御で確認した。
- Homeから非表示になる単独表示行: 実装はpending idを通常Home再構成から除外し、旧セクションのpending行をtimer削除後に外す共通経路で処理する。専用widget testは追加していない。
- 複数同時完了とアニメーション中再オープン: `home completion pending state handles multi-complete and reopen` で2件の同時pendingと、片方の再オープン後に古いpending行が残らないことを確認した。
- 連打: `_handleHomeCompleteTask` は既存pending task idへの追加完了処理をreturnする。`home completion pending state handles multi-complete and reopen` で同じtask idのpending中再操作がreopen経路として処理されることを確認した。
- Reduce Motion: `home reduce motion completion reconfigures immediately` で `FakeAccessibilityFeatures(disableAnimations: true)` 時にpending exit keyが出ず、即時にClosedへ再構成されることを確認した。
- Undo: `checking a task marks it done through the bridge service` で完了後のUndoスナックバー表示、Undo実行、`todo` への復元を確認した。

追加・更新したwidget test:

- 追加: `task checkbox keeps 48px hit area centered on visual mark`
  - 48x48ヒット領域と22x22チェック描画の中心一致を確認した。
- 追加: `home completion keeps standalone root until delayed exit`
  - Home単独ルート行の旧位置残留、800ms後退場開始、退場後Closed再構成を確認した。
- 追加: `home completion keeps standalone subtask before moving under ancestor`
  - 単独表示サブタスクが完了中は旧セクションに残り、退場後に表示中親の下へ移ることを確認した。
- 追加: `home completion pending state handles multi-complete and reopen`
  - 複数同時pending、pending中再オープン、timer後の古いpending行削除を確認した。
- 追加: `home reduce motion completion reconfigures immediately`
  - Reduce Motion時の即時再構成を確認した。
- 更新: `completion motion exposes intermediate particle and strike frame`
  - 静止状態の取り消し線がTextDecorationではなくPainter経路で描かれることを確認する期待値へ変更した。
- 更新: `completion motion is skipped when reduce motion is enabled`
  - Reduce Motion時も静止取り消し線Painterがprogress 1.0で出ることを確認する期待値へ変更した。
- 更新: 既存の完了/Closed行表示テスト
  - 静止取り消し線が `TextDecoration.lineThrough` ではなくPainter経路になったため、Text本体のdecoration期待値を `TextDecoration.none` へ変更した。

visual QA:

- 作業前退避先: `app/build/visual_qa_before/`
- 実装後出力先: `app/build/visual_qa/`
- 既存スクリーンショット: `app/build/visual_qa/completion_motion_midframe.png`
- 追加スクリーンショット: `app/build/visual_qa/completion_motion_endframe.png`
- 追加スクリーンショット: `app/build/visual_qa/completion_motion_static.png`
- `completion_motion_endframe.png` はタップ後300msのpump制御で生成した。
- `completion_motion_static.png` は `pumpAndSettle` 後に生成した。
- 目視確認: `completion_motion_endframe.png` と `completion_motion_static.png` の複数行取り消し線は同じPainter経路で描かれ、線の高さ・太さ・位置に目視上のズレは見えなかった。

モーション最終受け入れ:

- 完了遅延遷移はwidget testのpump制御で確認した。
- 体感の最終受け入れは人間ドッグフーディングで行う。

品質ゲート:

- `cargo fmt --all -- --check`: exit 0
- `cargo clippy --workspace -- -D warnings`: exit 0
- `cargo test --workspace`: exit 0
- `cd app && flutter analyze`: exit 0
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
- `cd app && flutter test`: exit 0（95件成功、visual QA harness 1件skip）
- `sh app/tool/check_hardcoded_strings.sh`: exit 0
- `sh app/tool/visual_qa.sh`: exit 0（37件成功）
- `git diff --check`: exit 0

変更ファイル一覧:

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-60-motion-refinement.md`

未解決事項:

- なし
