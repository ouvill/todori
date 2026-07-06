# task-42: 詳細画面インライン編集

> ステータス: 未着手

## 1. 背景とコンテキスト

2026-07-07のドッグフーディングで、タスク詳細画面の右上編集ボタンを押して一括編集ダイアログを開く導線が面倒である、というフィードバックが出た。タイトルやノートの軽い修正、期日・優先度の変更は、詳細画面を見ているその場で済ませたい。

現行の `TaskDetailScreen` は右上の編集IconButtonから `_EditTaskDialog` を開き、`title` / `note` / `priority` / `dueAt` をまとめて保存する。task-18で編集APIとUIは通っており、task-26で編集Undoも実装済みだが、操作の重さがドッグフーディング上の摩擦になっている。

本タスクでは一括編集ダイアログを廃し、詳細画面上のタイトル・ノート・期日・優先度を直接編集できるモデルへ移行する。Design Labの `task_detail` モックは構成の参考にするが、ピクセル再現は目的にしない。正本は `docs/design/ui-spec.md` のTask detail規範である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/design/ui-spec.md` セクション2・3・4
- `docs/tasks/task-18-task-editing-ui.md` の完了報告
- `docs/tasks/task-26-undo.md` の完了報告
- `docs/tasks/task-40-task-list-behavior.md` の完了報告
- `docs/tasks/task-41-list-nav-simplify.md` の完了報告
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/visual_qa/design_lab_task_detail_mock.dart`
- `app/test/visual_qa/design_lab_task_create_sheet_mock.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- タスク詳細画面の右上編集ボタンを撤去する。
- `_EditTaskDialog` による一括編集フローを撤去し、タイトル/ノート/期日/優先度を詳細画面上で直接編集できるようにする。
- タイトルはタップでその場のTextFieldへ切り替わり、フォーカス喪失または確定で保存される。空文字は保存せず、元のタイトルへ戻す。
- ノートはタップで複数行TextFieldへ切り替わり、フォーカス喪失または確定で保存される。未設定時は「ノートを追加」のプレースホルダ行を表示する。
- 期日と優先度はチップをタップして、それぞれ日付ピッカー/選択メニューを開き、選択後に即保存する。
- 保存は既存の `update_task` API経由で都度実行し、既存の編集Undoが効くことを確認する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`（既存チップのinteractive化が必要な場合のみ）
- `app/lib/src/ui/dialogs.dart`（一括編集ダイアログ以外の既存共通ダイアログ流用が必要な場合のみ）
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARBを変更した場合の生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/design/ui-spec.md`（Task detail規範の直接編集モデル更新。plannerが未更新の場合のみ）
- `docs/tasks/task-42-detail-inline-edit.md`（完了報告の追記のみ）

### やること

1. **一括編集導線の撤去**:
   - `TaskDetailScreen` のAppBar actionsから編集IconButtonを撤去する。
   - `_editTask` と `_EditTaskDialog` を撤去する。
   - status変更、再オープン、削除を含む右上overflowは維持する。
2. **タイトルのインライン編集**:
   - タイトル表示をタップ/キーボード操作でTextFieldへ切り替える。
   - 編集開始時は既存タイトルを選択またはカーソル配置し、確定しやすくする。
   - フォーカス喪失、IME確定後の送信、キーボード確定で保存する。
   - trim後の空文字は保存せず、元のタイトル表示へ戻す。
   - 日本語IME変換中のEnter/確定で誤保存しないよう、Flutterで扱える範囲のcomposition状態またはsubmit条件を確認する。制約が残る場合は完了報告の未解決事項へ記録する。
3. **ノートのインライン編集**:
   - ノートがある場合は本文タップで複数行TextFieldへ切り替える。
   - ノートがない場合はl10nされた「ノートを追加」プレースホルダ行を表示し、タップで複数行TextFieldへ切り替える。
   - フォーカス喪失または明示的な確定で保存する。空ノートは空文字として保存してよいが、保存後はプレースホルダ表示へ戻す。
4. **期日・優先度チップ編集**:
   - 期日チップタップで日付ピッカーを開き、選択後に `updateTask` で即保存する。
   - 期日なし状態でも編集できるよう、既存の「No due date」相当のチップまたはプレースホルダチップを維持する。
   - 期日クリア導線を維持する。既存編集ダイアログ内UIを流用してよいが、一括編集ダイアログへ戻さない。
   - 優先度チップタップで選択メニューを開き、選択後に即保存する。priority `0..3` の既存意味と文言を維持する。
5. **保存とUndo**:
   - 各フィールド保存は既存の `tasksProvider(listId).notifier.updateTask` / bridge `update_task` 経由で行う。
   - 保存後は既存の編集Undoスナックバーを表示し、Undoで変更前へ戻ることを確認する。
   - 複数フィールドを一括保存する新APIや新しいUndoモデルは作らない。
6. **l10n / accessibility / visual QA**:
   - 新しい表示文字列、tooltip、semanticsはen/ja ARBへ追加する。
   - icon-only controlを追加する場合はtooltip/semanticsと48px級タップ領域を維持する。
   - `sh app/tool/visual_qa.sh` 実行前に `app/build/visual_qa/` を `app/build/visual_qa_before/` へ退避する。
   - `task_detail.png` のbefore/afterに加え、タイトルまたはノート編集中状態の `task_detail_editing.png` 等を生成し、完了報告へパスを記録する。

### やらないこと

- task-43のDesign Lab準拠ビジュアル統一、遷移動線整理、Lucide全面統一。
- サブタスク並び替え。
- 新規メタデータ項目（Plan、Estimate、Tag、Reminder、Repeat等）の追加。
- 新しい編集API、Undo履歴モデル、DB schema、Rust/domain/storage/FRB APIの変更。
- 削除モデル、アーカイブ、ステータス遷移、同期、通知、検索の変更。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章の事前ファイルを読み、現行の `_EditTaskDialog`、`updateTask`、編集Undo、`TaskMetadata` の構成を把握する。
3. `app/build/visual_qa/` を `app/build/visual_qa_before/` へ退避し、現状の `task_detail.png` を確認する。
4. 詳細画面のAppBarから編集IconButtonを外し、overflow menuだけを残す。
5. タイトル/ノートの表示コンポーネントを小さなStatefulWidgetまたは画面内private widgetへ分け、TextEditingControllerとFocusNodeのライフサイクルを閉じ込める。
6. 保存helperを画面内で共通化し、更新対象以外の既存値を保ったまま `updateTask` を呼ぶ。
7. 期日チップと優先度チップにタップ動線を付け、既存の日付ピッカー/priority文言を流用して即保存する。
8. 保存成功時に既存の `_showLatestUndoSnackBar` を使って編集Undo導線を維持する。
9. en/ja ARBを更新した場合は `flutter gen-l10n` を実行する。
10. widget testでタイトル編集保存、空文字破棄、ノート追加/編集、期日/優先度チップ編集、編集Undoを確認する。
11. visual QAに `task_detail_editing.png` 等の編集中状態を追加し、before/afterを目視確認する。
12. 共通受け入れ基準の品質ゲートを実行する。
13. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] 詳細画面の右上編集ボタンと `_EditTaskDialog` が撤去され、status変更/再オープン/削除のoverflowは維持されていることがwidget testで確認できる。
- [ ] タイトルをタップして編集し、フォーカス喪失または確定で `updateTask` 経由で保存されることがwidget testで確認できる。
- [ ] タイトルを空文字にして確定した場合、保存されず元のタイトルへ戻ることがwidget testで確認できる。
- [ ] ノート未設定時に「ノートを追加」プレースホルダが表示され、ノート追加/編集が複数行TextFieldから保存できることがwidget testで確認できる。
- [ ] 期日チップから日付設定と期日クリアができ、選択後に即保存されることがwidget testで確認できる。
- [ ] 優先度チップからpriority `0..3` を選択でき、選択後に即保存されることがwidget testで確認できる。
- [ ] タイトル/ノート/期日/優先度の少なくとも1ケースで、保存後の編集Undoが変更前へ戻すことをwidget testで確認できる。
- [ ] 日本語IME変換中のEnter/確定で誤保存しないための実装上の考慮があり、Flutter/widget testで検証できない範囲は完了報告の未解決事項に記録されている。
- [ ] `task_detail.png` のbefore/afterと、編集中状態の `task_detail_editing.png` 等が生成され、完了報告にPNGパスと目視確認結果が記録されている。
- [ ] インライン編集状態でも `docs/design/ui-spec.md` のTask detail規範、タイポグラフィ、間隔、角丸、影規則に従い、新しい色/角丸/影が追加されていない。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` セクション3のTask detail規範を正とする。Design Labモックは構成参考であり、ピクセル再現を狙わない。
- 新しい色、角丸、影、面色を発明しない。必要になった場合は実装を止め、完了報告の未解決事項へ記録する。
- タイトルは `headlineSmall`、ノートは `bodyLarge`、createdは `bodySmall` の既存文法を維持する。詳細タイトルをNewsreader/Lora等へ変更しない。
- チップは詳細画面のみ最大4個を許容する。新規メタデータ項目を足してチップ数を増やさない。
- 右上overflowは削除サブメニュー等の既存重要操作を保持する。編集ボタン撤去に巻き込んで削除しない。
- 保存中の二重送信を避ける。必要なら該当フィールドだけ一時的にdisabled/loading状態にするが、大きなローディング面を追加しない。
- 入力中の秘密情報は扱わないが、既存方針どおりログやdebug出力にタスク本文を追加しない。
- UI文字列は直書きせず、必要な文言はen/ja ARBへ追加する。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 撤去した編集IconButton / `_EditTaskDialog` / 関連helper
- タイトルインライン編集の保存条件、空文字破棄条件、IME確定への対応内容
- ノート追加/編集の保存条件とプレースホルダ文言
- 期日チップ編集、期日クリア、優先度チップ編集の実装箇所
- `updateTask` / `update_task` と編集Undoの接続確認結果
- 追加・更新したl10nキー
- 追加・更新したwidget testの対象と結果
- visual QA before/after/編集中スクリーンショットの保存パスと目視確認結果
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）
