# task-43: Design Lab準拠のタスク一覧ビジュアル整合

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-07

## 1. 背景とコンテキスト

2026-07-07の親レビューで、Design Labの `design_lab_task_list.png` と現本番の `home_tasks.png` を比較した結果、Today/タスク一覧の構造差分が明確になった。現本番はタスク行が行ごとの独立カードとして背景に並び、priority dotがタイトル前にあるため、多行タイトルでdot整列が破綻しやすい。Design Labは、単一の「Tasks」パネルの中に軽い行が並び、dotはメタデータ行の先頭にある。

本タスクでは、Design LabのToday/タスク一覧構造を本番へ反映する。ただし、配色・フォント・角丸トークンの変更やLucide全面統一は行わない。正本は `docs/design/ui-spec.md` セクション2・3・4であり、Design Labモックは構造参照として扱う。

あわせて、同じ画面構造変更で見える既知nitsとして、Lists画面のArchivedヘッダーchevron重複と、task-42で入った期日チップ内クリア導線によるチップ高さ不揃いを修正する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/design/ui-spec.md` セクション2・3・4・5
- `docs/tasks/task-42-detail-inline-edit.md` の完了報告
- `app/test/visual_qa/design_lab_mocks.dart`（`_TaskListMock` / `_TasksPanel` / `_TaskRow` / `_CompletedTodayRow`）
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- Today/homeのタスク行群を、単一の「Tasks」パネル内に収める。
- priority dotをタイトル前からメタデータ行の先頭へ移し、多行タイトル時のdot整列問題を構造的に解消する。
- 通常タスク行のtrailing chevronを撤去し、行タップで詳細へ遷移できるsemanticsを維持する。
- Add task FABを画面下中央のpill型へ寄せる。
- Closedセクション見出しをDesign Labの「Completed today N」風の控えめな1行へ整える。
- Lists画面のArchivedヘッダーchevron重複を解消する。
- 詳細画面を含むチップ高さを統一し、期日クリアは同じ高さの内包アイコンとして扱う。
- `docs/design/ui-spec.md` のタスク行/Today規範と既知逸脱を、本タスクの目標形と矛盾しない状態に保つ。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARBを変更した場合の生成差分のみ）
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/design/ui-spec.md`（本指示書作成時点で更新済み。実装中に矛盾が見つかった場合のみ最小更新）
- `docs/tasks/task-43-lab-visual-alignment.md`（完了報告の追記のみ）

### やること

1. **Today/タスク一覧の単一Tasksパネル化**
   - `home_tasks.png` のタスク行群を、単一の「Tasks」パネル（warm white surface、外側1px border）へ収める。
   - パネル内に見出し行（Tasks + pending pill）とタスク行を置く。
   - ルート行は軽いsurface差または薄い区切りで分離してよいが、行ごとに独立カードが背景に並ぶ構造へ戻さない。
   - card-in-cardの重さを出さないため、borderは外側パネルに集約する。
2. **priority dotのメタデータ行移動**
   - `AppTaskRow` のpriority dotをタイトル前からメタデータ行の先頭へ移す。
   - メタデータ順は `priority dot -> 日付pill -> 進捗pill` とする。
   - priority noneの場合、dotの空き領域を残さず、メタデータ行の先頭は日付pillにする。
   - Task detailのタイトル脇dotも同じ方針で撤去し、メタデータ行へ移す。
   - dotには既存のtooltip/semanticsを維持し、色だけに依存しない情報伝達を保つ。
3. **通常行のtrailing chevron撤去**
   - 通常表示のタスク行右端chevronを撤去する。
   - 行タップで詳細へ遷移する挙動は維持する。
   - 行のsemanticsに、遷移可能な行であることが伝わるlabel/hint/button相当を維持または追加する。
   - 手動並び替えモードの上下ボタンは維持する。
4. **Add task FABの画面下中央pill化**
   - home表示のAdd task FABを画面下中央のpill型にする。
   - 既存の作成ダイアログ、tooltip、semantics、48px級タップ領域を維持する。
   - 非home表示のFABは、既存文法と矛盾しない範囲で変更してよいが、不要な刷新はしない。
5. **Closedセクション見出しの整理**
   - Closedセクション見出しを、Design Labの `Completed today N` に近い控えめな1行へ整える。
   - 中央寄せまたは左寄せの小さな見出し + 件数 + 開閉chevron 1つで構成する。
   - Closed行の再オープン挙動、Closedルート/サブタスク同伴規則は維持する。
6. **Lists画面Archivedヘッダーのchevron重複解消**
   - `Archived (N)` ヘッダーに左右2つのchevronが出る状態を解消し、chevronを1つにする。
   - 開閉tooltip/semanticsと48px級タップ領域を維持する。
7. **チップ高さの統一**
   - `TaskMetadata` 系pill、詳細画面の期日/優先度/status/progressチップ、期日クリア内包アイコンの高さを揃える。
   - 期日クリアはチップ内の同じ高さのアイコンとして扱い、他チップより背が高くならないようにする。
   - 新しいチップ色、角丸、影、フォントサイズを発明しない。
8. **ui-specとの整合**
   - `docs/design/ui-spec.md` セクション3のタスク行解剖図・Today画面規範が、本タスクの構造と一致していることを確認する。
   - 「既知の逸脱」からpriority dot整列項が消えていることを確認する。
   - 実装中にspecと実装の矛盾が見つかった場合、本タスクの範囲内で最小限のspec更新を行い、完了報告に記録する。
9. **テストとvisual QA追従**
   - 構造変更に合わせてwidget testを更新し、行タップ遷移、再オープン、手動並び替え、Lists Archived開閉、詳細画面チップ編集が壊れていないことを確認する。
   - 作業前に `app/build/visual_qa/` を `app/build/visual_qa_before/` へ退避する。
   - 実装後に `sh app/tool/visual_qa.sh` を実行し、少なくとも `home_tasks` / `home_tasks_ja` / `wont_do_row` / `lists` / `task_detail` のbefore/afterを完了報告に記録する。

### やらないこと

- Lucideアイコン全面統一（task-44へ分離）。
- Focus timer、Focus開始ボタン、再生ボタンの実装。
- 配色、フォント、角丸トークン、影トークンの変更。
- 新しいpriority意味論、タグ、Plan、Estimate、Reminder、Repeat等のメタデータ追加。
- タスク作成フロー、削除モデル、アーカイブ意味論、Undoモデル、Rust/domain/storage/FRB APIの変更。
- 日付・時刻表記のロケール準拠リファクタ（別バックログ）。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章の事前ファイルを読み、Design Labの `_TasksPanel` と本番の `_TasksBody` / `AppTaskRow` / `TaskMetadata` / Task detail metadata構造を対応づける。
3. `app/build/visual_qa/` を `app/build/visual_qa_before/` へ退避し、`design_lab_task_list.png` と現状の `home_tasks.png` / `home_tasks_ja.png` / `wont_do_row.png` / `lists.png` / `task_detail.png` を目視する。
4. `TasksScreen` 側で、Tasks見出しとactive row群を単一パネルへ収める構造を作る。空状態とClosedセクションの既存分岐を壊さない。
5. `AppTaskRow` 側で、タイトル前priority dotと通常trailing chevronを撤去し、dotをmetadata先頭へ移す。必要ならmetadata itemとは別のleading metadata slotとして実装する。
6. `TaskDetailScreen` のpriority dot/priorityチップ構成を確認し、タイトル脇dotを残さずmetadata行へ揃える。
7. home FABを下中央pill型へ変更し、既存の作成動線とアクセシビリティを維持する。
8. `_CompletedSectionHeader` と `_ArchivedListsHeader` を整理し、chevron数とタップ領域を確認する。
9. チップ高さを共通化または制約で揃える。期日クリアアイコンを同じ高さに収める。
10. widget testとvisual QA harnessを必要最小限で更新する。visual QAの対象名は既存名を優先し、不要なスクリーンショット名増加を避ける。
11. 共通受け入れ基準の品質ゲートを実行する。
12. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `home_tasks.png` / `home_tasks_ja.png` のafterで、activeタスク行群が単一の「Tasks」パネル内にあり、行ごとの独立カードが背景に並んでいないことを確認できる。
- [ ] `home_tasks.png` / `home_tasks_ja.png` のafterで、priority dotがタイトル前ではなくメタデータ行の先頭にあり、priority noneの行は日付pillがメタデータ行の先頭にあることを確認できる。
- [ ] `task_detail.png` のafterで、詳細タイトル脇にpriority dotがなく、priority表現がメタデータ行に置かれていることを確認できる。
- [ ] `home_tasks.png` / `wont_do_row.png` のafterで、通常タスク行の右端chevronがなく、手動並び替え以外のtrailing affordanceが表示されていないことを確認できる。
- [ ] `home_tasks.png` / `home_tasks_ja.png` のafterで、Add task FABが画面下中央のpill型として表示され、下部余白や行内容に重なっていないことを確認できる。
- [ ] `wont_do_row.png` のafterで、Closedセクション見出しが小さな1行表示になり、件数と開閉chevronが1つだけ表示されていることを確認できる。
- [ ] `lists.png` / `lists_archived.png` のafterで、`Archived (N)` ヘッダーのchevronが1つだけ表示されていることを確認できる。
- [ ] `task_detail.png` のafterで、期日チップのクリアアイコンを含むチップ群の高さが揃い、1つのチップだけ背が高く見えないことを確認できる。
- [ ] `home_tasks_ja.png` / `lists.png` / `task_detail.png` のafterで、日本語表示・狭幅・長めの文言が親要素からはみ出さず、主要テキスト同士が重なっていないことを確認できる。
- [ ] 完了報告に `home_tasks` / `home_tasks_ja` / `wont_do_row` / `lists` / `task_detail` のbefore/after PNGパスと、`design_lab_task_list.png` との目視比較結果が記録されている。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` セクション2・3・4を正とする。Design Labは構造参照であり、ピクセル完全再現は目的にしない。
- 配色・フォント・角丸・影・間隔トークンは変更しない。必要に見える場合は実装を止め、完了報告の未解決事項に記録する。
- `PriorityDot` の色と直径11pxは維持する。Design Labの7px dotへ合わせない。
- Lucideアイコン統一はtask-44へ分離済みであり、本タスクでは既存Material Iconsを全面置換しない。新規に同一画面でMaterial/Lucide混在を増やさない。
- Focus再生ボタンは実装しない。Design Labのplay button相当はtimer未実装のため本タスクの対象外である。
- i18n、Dynamic Type、狭幅、48px級タップ領域、tooltip/semanticsを維持する。
- 通常行のchevronを撤去しても、行タップで詳細へ遷移できることがスクリーンリーダーに伝わるようにする。
- Closed行の再オープン、サブタスク同伴表示、手動並び替えモードの上下ボタン、task-42の詳細インライン編集は退行させない。
- widget testは構造変更に追従させる。find条件が古いchevronや旧dot位置に依存している場合は、挙動を検証する形へ更新する。
- visual QAはbefore/after必須であり、worker自身がPNGを目視して完了報告へパスと確認結果を書く。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- Tasks単一パネル化の実装箇所と、行分離の方法（軽いsurface差または区切り）
- priority dotをメタデータ行へ移した実装箇所、priority none時の表示、semantics維持内容
- 通常行chevron撤去後の行タップ遷移とsemantics維持内容
- Add task FAB下中央pill化の実装箇所
- Closedセクション見出し、Archivedヘッダーchevron、チップ高さ統一の修正内容
- `docs/design/ui-spec.md` を変更した場合は変更内容。変更しなかった場合は、本指示書作成時点の更新済みspecと矛盾がなかったこと
- 追加・更新したl10nキー
- 追加・更新したwidget testの対象と結果
- visual QA before/afterスクリーンショットの保存パス（必須: `home_tasks` / `home_tasks_ja` / `wont_do_row` / `lists` / `task_detail`）と、`design_lab_task_list.png` との目視比較結果
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

- 作業日: 2026-07-07
- 読んだファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/BACKLOG.md`
  - `docs/tasks/DESIGN_PLAYBOOK.md`
  - `docs/design/ui-spec.md` セクション2・3・4・5
  - `docs/tasks/task-42-detail-inline-edit.md` 完了報告
  - `app/test/visual_qa/design_lab_mocks.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/ui/task_components.dart`
  - `app/lib/src/screens/lists_screen.dart`
  - `app/lib/src/screens/task_detail_screen.dart`
  - `app/lib/src/ui/theme.dart`
  - `app/lib/l10n/app_en.arb`
  - `app/lib/l10n/app_ja.arb`
  - `app/test/widget_test.dart`
  - `app/test/support/fake_bridge_service.dart`
  - `app/test/visual_qa/visual_qa_screenshots_test.dart`
  - `app/tool/visual_qa.sh`
- 作業前退避:
  - `mkdir -p app/build/visual_qa_before && find app/build/visual_qa -maxdepth 1 -type f -name '*.png' -exec cp -p {} app/build/visual_qa_before/ \; && find app/build/visual_qa_before -maxdepth 1 -type f -name '*.png' -print | wc -l`: exit 0
  - 退避ファイル数: 31
  - 退避先: `app/build/visual_qa_before/`
- Tasks単一パネル化:
  - `app/lib/src/screens/tasks_screen.dart` のhome表示で、active task row群を `_TasksPanel` 内へ移した。
  - `_TasksPanel` は `Tasks` 見出し、pending pill、active row群を1つのsurface + 1px border内に置く。
  - パネル内の行分離は `Divider` による薄い区切りを使い、home表示の `AppTaskRow` は `framed: false` で行ごとの外側borderを出さない。
- priority dot:
  - `app/lib/src/ui/task_components.dart` の `TaskMetadata` にpriority dot用slotを追加した。
  - `AppTaskRow` のタイトル前 `PriorityDot` を削除し、metadata行の先頭へ移した。
  - priority noneの場合は `PriorityDot` を生成しないため、metadata行の先頭は日付pillになる。
  - `PriorityDot` のtooltip/semanticsは `l10n.taskPriority(...)` を継続して使う。
  - `app/lib/src/screens/task_detail_screen.dart` の詳細タイトル脇 `PriorityDot` を削除し、詳細metadata行へ移した。
- 通常行chevron:
  - `app/lib/src/screens/tasks_screen.dart` の通常 `AppTaskRow.trailing` へ渡していた `Icons.chevron_right` を削除した。
  - `app/lib/src/ui/task_components.dart` の `trailing ?? const Icon(Icons.chevron_right)` を削除した。
  - 行の `InkWell.onTap` による詳細遷移は維持した。
  - 手動並び替えモードの `_TaskReorderControls` は上下ボタンを維持し、末尾のchevronだけ削除した。
- Add task pill:
  - `app/lib/src/screens/tasks_screen.dart` のhome表示では `FloatingActionButton.extended` を下部 `bottomNavigationBar` 内の中央に配置した。
  - tooltipは `l10n.newTaskTooltip`、labelは `l10n.addTaskButton` を継続して使う。
- Closedセクション見出し:
  - `app/lib/src/screens/tasks_screen.dart` の `_CompletedSectionHeader` を小さい1行表示へ変更した。
  - 表示要素はchevron 1つ、`completedTasksTitle`、`completedTasksCount(count)`。
  - `completed-section-toggle` key、tooltip、semantics button、開閉処理は維持した。
- Archivedヘッダー:
  - `app/lib/src/screens/lists_screen.dart` の `_ArchivedListsHeader` から左右2つのchevron表示を削除し、右端のchevron 1つにした。
  - tooltip、semantics button、48px領域の右端アイコン、行全体のtap処理を維持した。
- チップ高さ:
  - `app/lib/src/screens/task_detail_screen.dart` の `_DetailPill` を `minHeight: 32` に揃えた。
  - 期日クリアIconButtonを `SizedBox.square(dimension: 32)` 内に収め、他のdetail pillより背が高くならない構造にした。
- `docs/design/ui-spec.md`:
  - 変更していない。
  - セクション3のタスク行、タスク一覧構造、Today/home、Task detail規範は本タスク実装後の構造と矛盾しないことを確認した。
  - セクション5の既知の逸脱は「なし」のままであることを確認した。
- l10n:
  - ARBキーの追加・更新なし。
  - `flutter gen-l10n` は実行していない。
- widget test:
  - `app/test/widget_test.dart` の `tapping a list navigates to its task list` に通常行chevron非表示の確認を追加した。
  - `polished list, sort, detail, and dialog surfaces stay stable` のpriority dot確認を、タイトル横ではなくタイトル下metadata行にあることを確認する条件へ更新した。
  - `archiving a list moves it to the archived section` にArchivedヘッダーのchevronが閉時/開時それぞれ1つであることの確認を追加した。
  - `flutter test test/widget_test.dart`: exit 0（39 tests passed）
- visual QA before/after:
  - 参照モック: `app/build/visual_qa/design_lab_task_list.png`
  - before: `app/build/visual_qa_before/home_tasks.png`
  - after: `app/build/visual_qa/home_tasks.png`
  - before: `app/build/visual_qa_before/home_tasks_ja.png`
  - after: `app/build/visual_qa/home_tasks_ja.png`
  - before: `app/build/visual_qa_before/wont_do_row.png`
  - after: `app/build/visual_qa/wont_do_row.png`
  - before: `app/build/visual_qa_before/lists.png`
  - after: `app/build/visual_qa/lists.png`
  - before: `app/build/visual_qa_before/lists_archived.png`
  - after: `app/build/visual_qa/lists_archived.png`
  - before: `app/build/visual_qa_before/task_detail.png`
  - after: `app/build/visual_qa/task_detail.png`
- visual QA目視比較結果:
  - `home_tasks.png`: activeタスク行群が単一の `Tasks` パネル内にあり、行ごとの独立カードは表示されていない。priority dotはmetadata行の先頭にあり、通常行右端chevronは表示されていない。下中央に `Add task` pillが表示されている。
  - `home_tasks_ja.png`: 日本語表示で単一 `Tasks` パネル、metadata行先頭dot、下中央pillが表示されている。主要テキスト同士の重なりは確認されなかった。
  - `wont_do_row.png`: Closed見出しは1行表示で、chevronは1つ。Closed行の先頭コントロールとwont_do metadata pillが表示されている。
  - `lists.png`: `Archived (1)` ヘッダーのchevronは1つ。
  - `lists_archived.png`: 展開状態の `Archived (1)` ヘッダーのchevronは1つ。
  - `task_detail.png`: 詳細タイトル脇にpriority dotはなく、priority dotはmetadata行に表示されている。期日クリアアイコンを含むチップ群の高さは同じ行高に収まっている。
  - `design_lab_task_list.png` との比較: 本番afterは単一Tasksパネル、metadata行先頭dot、通常行chevronなし、下中央Add task pill、Closed見出し1行の構造を持つことを確認した。
- 品質ゲートの実行結果:
  - `cargo fmt --all -- --check`: exit 0
  - `cargo clippy --workspace -- -D warnings`: exit 0
  - `cargo test --workspace`: exit 0
  - `cd app && flutter analyze`: exit 0
  - `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: exit 0
  - `cd app && flutter test`: exit 0（56 passed、1 skipped）
  - `sh app/tool/check_hardcoded_strings.sh`: exit 0
  - `sh app/tool/visual_qa.sh`: exit 0（29 tests passed）
  - `git diff --check`: exit 0
- 検証時の環境対応:
  - 初回 `flutter analyze` は `app/macos/Flutter/ephemeral/Packages/.packages` がディレクトリとして存在しFlutter toolが削除できずexit 1になった。
  - 当該生成物を `/private/tmp/todori-task43-packages-dir-<timestamp>` へ退避し、`flutter analyze` を再実行してexit 0を確認した。
- 変更ファイル一覧:
  - `app/lib/src/screens/lists_screen.dart`
  - `app/lib/src/screens/task_detail_screen.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/ui/task_components.dart`
  - `app/test/widget_test.dart`
  - `docs/tasks/README.md`
  - `docs/tasks/task-43-lab-visual-alignment.md`
- Rust/domain/storage/FRB API:
  - 変更していない。
  - `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` は実行していない。
- 未解決事項:
  - なし。
