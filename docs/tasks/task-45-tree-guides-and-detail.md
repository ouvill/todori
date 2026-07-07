# task-45: 階層ガイド描画と詳細画面Subtasks/インライン編集調整

> ステータス: 完了（2026-07-07実装）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

2026-07-07ドッグフーディング第2回で、サブタスク階層ガイドの横棒がチェックボックス中心とずれて見えること、最後の子と継続中の子が同じ縦線に見えること、詳細画面のSubtasksが直接の子だけで孫タスクを表示しないことが指摘された。

また、task-42で詳細画面のタイトル/ノートをインライン編集化した後、読み取り表示からTextFieldへ切り替わる瞬間にpaddingやTextField decorationの差でレイアウトが動く。詳細画面では、編集可能でありながら読み取り時と編集時の位置が変わらないことを UI spec の規則にする。

本タスクでは、階層ガイドの描画文法、詳細画面Subtasksの子孫ツリー表示、タイトル/ノート編集開始時のがたつき解消を扱う。チェックボックスのトグル一貫性はtask-44の範囲であり、本タスクでは主目的にしない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（タスク行、タスク一覧構造、Task detail）
- `docs/tasks/task-44-checkbox-toggle-consistency.md`
- `app/lib/src/ui/task_components.dart`（チェックボックスとツリーガイド描画）
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`（インライン編集とSubtasks一覧）
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- サブタスク階層ガイドの横棒を、チェックボックスの垂直中心の高さへ揃える。
- 最後の子はL字（└）、後続兄弟がある子はT字（├）として描き分ける。
- 3階層以上のネストでも祖先の縦線が正しく続くようにする。
- 詳細画面のSubtasksに、直接の子だけでなく子孫ツリー全体を階層ガイド付きで表示する。
- 詳細画面のタイトル/ノートで、読み取り表示から編集状態へ切り替えても該当要素のオフセットが動かないようにする。
- widget testとvisual QAで退行検出できる証拠を残す。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/core/task_tree.dart`（既存構造で不足する場合のみ）
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`（3階層seed追加が必要な場合）
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-45-tree-guides-and-detail.md`（完了報告の追記のみ）

### やること

1. **階層ガイドをL字/T字として描き分ける**
   - 横棒をチェックボックスの垂直中心に揃える。
   - 最後の子はL字（└）として、縦線が横棒で終端する。
   - 後続兄弟がある子はT字（├）として、縦線が上下に続く。
   - 3階層以上で、祖先階層の縦線が必要な行まで続く。
2. **ツリー描画に必要な構造情報を渡す**
   - 既存の `buildTaskTree` / `flattenTaskTree` 相当を流用する。
   - `TaskTreeNode.depth` だけで足りない場合は、「この行が各祖先階層で最後かどうか」を表せる情報を最小限追加する。
   - ad hocなタイトル文字列判定や、特定seedに依存した描画条件を避ける。
3. **詳細画面Subtasksを子孫ツリー全体にする**
   - `directSubtasksOf` だけでなく、対象タスク配下の子孫ツリーを表示する。
   - 深い階層のインデントと階層ガイドは一覧と同じ文法にする。
   - 行タップで該当サブタスク詳細へ遷移する挙動は維持する。
4. **タイトル/ノート編集開始時のがたつきを解消する**
   - 読み取り表示と編集状態で、同一のTextStyle、padding、strut/line-heightを使う。
   - TextFieldのborder/label/contentPadding差で、編集開始前後の該当要素オフセットが変わらないようにする。
   - 実装方式は自由だが、widget testで編集開始前後のオフセット不変を検証する。
5. **widget testとvisual QAを追加・更新する**
   - 最後の子がL字であることを、ガイド描画のkey/semantics/テスト用構造情報など、goldenに依存しない方法で検証する。
   - goldenなしで困難な場合は、visual QAスクリーンショット目視を受け入れ証拠にし、その理由を完了報告へ書く。
   - 詳細画面に孫タスクが階層表示されることをwidget testで検証する。
   - タイトル編集開始時のオフセット不変をwidget testで検証する。可能ならノートも同様に検証する。
   - サブサブタスクを含むseedで `home_tasks` / `task_detail` のvisual QAスクリーンショットを生成し、3階層を確認する。

### やらないこと

- task-44のチェックボックストグル一貫性修正。
- Undoスナックバー調整。
- スマートリスト、Inbox自動プロビジョニング、Todayリンク。
- Rust/domain/storage/FRB APIの変更。
- DB schema変更、FRB再生成。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、現在の `TaskTreeNode` / `flattenTaskTree` / `AppTaskRow` 階層ガイドがどの情報で描画されているか確認する。
3. 3階層以上のツリーを表せるtest seedを確認し、不足していれば `FakeBridgeService` またはvisual QA seedへ最小追加する。
4. `flattenTaskTree` の戻り値または補助構造で、各行の `depth`、最後の子かどうか、継続する祖先線を表せるようにする。
5. `AppTaskRow` へ階層ガイド描画に必要な情報を渡し、横棒をチェックボックス中心へ合わせ、L字/T字を描き分ける。
6. `TasksScreen` の一覧表示に新しい階層ガイド情報を渡す。既存のActive/Closedセクション規則は維持する。
7. `TaskDetailScreen` のSubtasksを、対象タスクの子孫ツリー全体へ変更する。一覧と同じガイド文法・同じ行コンポーネントを使う。
8. `_InlineTitleEditor` / `_InlineNoteEditor` の読み取り状態と編集状態のpadding/style/strutを揃える。
9. widget testを追加・更新する。位置検証は `tester.getTopLeft` / `tester.getRect` 等で、編集開始前後の該当要素オフセットを比較する。
10. 作業前に必要なvisual QA画像を退避し、実装後に `sh app/tool/visual_qa.sh` を実行して `home_tasks` / `task_detail` の3階層表示を確認する。
11. 共通受け入れ基準の品質ゲートを実行する。
12. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 一覧のサブタスク階層ガイドで、横棒がチェックボックスの垂直中心の高さに接続していることを確認できる。
- [ ] 最後の子はL字（└）、後続兄弟がある子はT字（├）として描き分けられていることが、widget testのkey/semantics/構造検証、またはvisual QA目視証拠で確認できる。
- [ ] 3階層以上のネストで、祖先階層の縦線が必要な行まで続いていることを `home_tasks` visual QAスクリーンショットで確認できる。
- [ ] 詳細画面のSubtasksに孫タスク以降の子孫が表示され、一覧と同じ深さ/階層ガイド文法で描画されることがwidget testで検証されている。
- [ ] タイトル編集開始前後で、該当タイトル要素のオフセットが変わらないことがwidget testで検証されている。
- [ ] ノート編集開始前後で、該当ノート要素のオフセットが変わらないことがwidget testまたは完了報告の目視証拠で確認されている。
- [ ] `home_tasks` / `task_detail` のvisual QAスクリーンショットに、サブサブタスクを含む3階層表示が含まれている。
- [ ] task-44のチェックボックストグル挙動、Undoスナックバー挙動を変更していない。変更が必要になった場合は理由を完了報告に記録している。
- [ ] Rust/domain/storage/FRB API、DB schema、生成FRBファイルに変更がない。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` セクション3の階層ガイド、Task detail規則を正とする。
- 階層ガイドの描画は、固定座標の偶然合わせではなく、チェックボックス領域の中心と行paddingに基づいて説明できる形にする。
- `TaskTreeNode.depth` だけでL字/T字や祖先線継続を表現できない場合は、ツリーflatten時に構造情報を追加する。UI側で全タスク配列を毎行探索し続ける実装は避ける。
- 詳細画面Subtasksは一覧と同じ文法を使う。詳細画面専用の別ルールを増やさない。
- インライン編集のがたつき解消で、タイトル/ノートのタイポグラフィをui-specから外さない。
- TextFieldのlabel表示がレイアウト差の原因になる場合は、visible labelではなくsemantics/tooltip/placeholder等でアクセシビリティを維持する方法を検討する。
- golden testを新規導入しない。既存のwidget testとvisual QAで確認する。
- visual QAはライトモードを必須証拠とする。ダークモード正式対応は直近スコープ外である。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 階層ガイドのL字/T字、横棒位置、祖先縦線継続の実装箇所
- ツリーflattenまたは構造情報を変更した場合は、そのデータ構造と理由
- 詳細画面Subtasksを子孫ツリー全体にした実装箇所
- タイトル/ノート編集開始時のがたつき解消の実装箇所
- 追加・更新したwidget test名と検証対象
- visual QA before/afterスクリーンショットの保存パス（必須: `home_tasks` / `task_detail`）と3階層表示の目視確認結果
- goldenなしでL字/T字をwidget testできなかった場合は、その理由と代替証拠
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-07

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md`
- `docs/tasks/task-44-checkbox-toggle-consistency.md`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

実装結果:

- `app/lib/src/core/task_tree.dart` に `FlattenedTaskTreeNode` を追加し、`flattenTaskTree` が `isLastSibling` と `ancestorLineContinuations` を返すようにした。
- `app/lib/src/core/task_tree.dart` に `descendantTaskTreeOf` を追加し、対象タスク配下の子孫ツリーを詳細画面用に深さ1始まりで構築するようにした。
- `app/lib/src/ui/task_components.dart` の `AppTaskRow` に `isLastSibling`、`ancestorLineContinuations`、`hierarchyGuideHorizontalKey` を追加した。
- `app/lib/src/ui/task_components.dart` の `_TaskHierarchyGuide` で、現在行の枝を `isLastSibling` に応じてT字またはL字として描画し、祖先列は `ancestorLineContinuations` が `true` の列だけ縦線を続けるようにした。
- 横棒のY座標は `AppSpacing.xs + 24` を基準にし、行先頭48pxチェック領域の垂直中心に合わせた。
- `app/lib/src/screens/tasks_screen.dart` は `FlattenedTaskTreeNode` の構造情報を `AppTaskRow` へ渡すようにした。
- `app/lib/src/screens/task_detail_screen.dart` は `directSubtasksOf` ではなく `descendantTaskTreeOf` と `flattenTaskTree` を使い、Subtasksに直接の子と孫以降を表示するようにした。
- `app/lib/src/screens/task_detail_screen.dart` のタイトル/ノート編集は、読み取り表示と編集状態で同一のpadding、TextStyle、StrutStyleを使い、編集状態は `EditableText` で配置するようにした。
- `app/test/visual_qa/visual_qa_screenshots_test.dart` のvisual QA seedに3階層目のサブタスク `Confirm final copy in the hero panel` を追加した。
- task-44のチェックボックストグル挙動、Undoスナックバー挙動は変更していない。
- Rust/domain/storage/FRB API、DB schema、生成FRBファイルの変更はなし。

追加・更新したwidget test:

- `hierarchy guides expose L and T branches aligned to checkbox`: 一覧で最初の子がT字、最後の子がL字、孫行に祖先縦線継続情報が渡ること、横棒中心Yがチェックボックス中心Yに合うことを検証した。
- `detail subtasks show descendant tree with hierarchy guides`: 詳細画面Subtasksに孫タスクが表示され、子/孫/最後の子へ階層情報が渡ることを検証した。
- `inline title and note editing keep text offsets stable`: タイトルとノートについて、読み取りTextと編集時 `EditableText` のtop-leftが変わらないことを検証した。

visual QAスクリーンショット:

- before: `app/build/visual_qa_before/home_tasks.png`
- before: `app/build/visual_qa_before/task_detail.png`
- after: `app/build/visual_qa/home_tasks.png`
- after: `app/build/visual_qa/task_detail.png`

目視確認結果:

- `app/build/visual_qa/home_tasks.png` で3階層のサブタスク表示を確認した。
- `app/build/visual_qa/home_tasks.png` で横棒がチェック中心の高さに接続していることを確認した。
- `app/build/visual_qa/home_tasks.png` で最後の子がL字で終端していることを確認した。
- `app/build/visual_qa/task_detail.png` で孫タスクがSubtasks内に階層表示されていることを確認した。
- `app/build/visual_qa/task_detail.png` で最後の子がL字で終端していることを確認した。

検証結果:

- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功
- `cd app && flutter analyze`: 成功
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter test`: 成功（65件、skip 1件）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `sh app/tool/visual_qa.sh`: 成功（30 PNG生成）
- `git diff --check`: 成功

変更ファイル一覧:

- `app/lib/src/core/task_tree.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/widget_test.dart`
- `docs/tasks/task-45-tree-guides-and-detail.md`

未解決事項:

- なし
