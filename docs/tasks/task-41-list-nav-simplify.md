# task-41: リスト一覧のナビゲーション単純化

> ステータス: 未着手

## 1. 背景とコンテキスト

2026-07-07のドッグフーディングで、リスト一覧の各行にある「…」メニューとchevronは不要であり、リスト操作は開いた各リスト画面の右上サブメニューで行いたい、という実機フィードバックが出た。

現行の `ListsScreen` は、リスト行にナビゲーション、改名、アーカイブ、削除、アーカイブ解除、chevronを同居させている。これは管理画面としては機能するが、task-firstなホーム体験に対して、リスト一覧がやや操作過多に見える。

本タスクでは `docs/design/ui-spec.md` セクション3の新規則に従い、リスト一覧の行を純粋なナビゲーション行へ単純化する。リスト単位の操作は、そのリストを開いた `TasksScreen` の右上overflowメニューへ移設する。既定インボックスでは削除/アーカイブを表示せず、保護対象操作が誤って選べないようにする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/design/ui-spec.md` セクション3
- `docs/tasks/task-35-list-rename.md` の完了報告
- `docs/tasks/task-37-list-archive.md` の完了報告
- `docs/tasks/task-38-trash-removal.md` の完了報告
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/router.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- `ListsScreen` の通常/アーカイブ済みリスト行から、行内「…」メニューとchevronを撤去する。
- リスト行のタップは、そのリストを開くだけにする。
- 「New list」行は維持する。
- リスト改名/アーカイブ/削除/アーカイブ解除は、開いたリスト画面の右上overflowメニューから実行できる。
- 既定インボックスでは削除/アーカイブをメニューに表示しない。
- アーカイブ済みリストを開いた場合は、右上overflowに「アーカイブ解除」を表示する。
- 既存の確認ダイアログ、件数警告、アーカイブ誘導文言は流用する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/router.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARBを変更した場合の生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-41-list-nav-simplify.md`（完了報告の追記のみ）

### やること

1. **Lists画面の行単純化**:
   - `_ListManagementRow` から行内PopupMenuButtonとchevronを撤去する。
   - 通常リスト行はタップで `/lists/:listId/tasks` を開くだけにする。
   - 「New list」行は既存どおり作成ダイアログを開く。
   - アーカイブ済みリスト行もタップで該当リストを開けるようにする。現状すでに遷移できる場合は、その挙動を維持する。
   - 行内に操作メニューが残っていないことをwidget testで確認する。
2. **TasksScreenへのリスト操作移設**:
   - 開いたリスト画面の右上にoverflowメニューを追加する。
   - 非home表示ではAppBar actionsに置く。
   - home表示では既存のヘッダー右上の並びに置く。既存のメニュー/ソートとの順序は、`ui-spec.md` のToday/home規範を崩さない範囲で整理する。
   - メニュー項目は、通常リストでは改名/アーカイブ/削除、アーカイブ済みリストでは改名/アーカイブ解除/削除を基本とする。
   - 既定インボックスでは削除/アーカイブを非表示にする。改名を許可するかは既存仕様・実装に合わせ、少なくとも保護対象操作を表示しない。
3. **既存フローの流用**:
   - 改名はtask-35のダイアログ・provider経路を流用する。
   - アーカイブ/アーカイブ解除はtask-37のprovider経路と文言を流用する。
   - 削除はtask-38の不可逆確認・件数警告・アーカイブ誘導文言を流用する。
   - 重複実装を避け、必要なら画面内private helperを整理する。ただし大きな共通化や新規アーキテクチャは行わない。
4. **アーカイブ済みリスト表示との整合**:
   - `TasksScreen` が対象リストの `archivedAt` 相当を判定できるようにする。既存providerで足りるならそれを使う。
   - 現状のroute引数だけでアーカイブ済み判定が難しい場合は、最小限のprovider/helper追加に留める。
   - アーカイブ済みリストから「アーカイブ解除」を実行後、通常一覧と対象画面が矛盾しないようにprovider invalidationを確認する。
5. **widget test**:
   - Lists行に行内メニュー/chevronが存在しないことを確認する。
   - 開いたリスト画面のoverflowから改名できることを確認する。
   - 開いたリスト画面のoverflowからアーカイブできることを確認する。
   - 開いたリスト画面のoverflowから削除確認フローに入れることを確認する。
   - 既定インボックスでは削除/アーカイブが表示されないことを確認する。
   - アーカイブ済みリストを開くと「アーカイブ解除」が表示されることを確認する。
6. **visual QA**:
   - `lists.png` で行内「…」メニューとchevronがないことを確認する。
   - `lists_archived.png` でArchivedセクションの行も静かなナビゲーション行になっていることを確認する。
   - リストを開いた画面でoverflowメニューを展開したスクリーンショットを追加または更新する。

### やらないこと

- task-40のタスク一覧Closed挙動変更。
- タスク詳細画面インライン編集（task-42予定）。
- Design Lab準拠の全面ビジュアル刷新、遷移動線全体整理、Lucide統一（task-43予定）。
- リスト型（プロジェクト/エリア等）の新設。
- リスト並び替え、検索、通知、同期の変更。
- 削除モデルやアーカイブ意味論の再設計。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章の事前ファイルを読み、現行のLists行操作、TasksScreenのAppBar/home header、lists providerの改名/アーカイブ/削除経路を把握する。
3. `ListsScreen` の `_ListManagementRow` を純粋なナビゲーション行に変更し、不要になったaction引数とenumを削る。
4. `TasksScreen` にリスト操作用overflowメニューを追加する。home / non-home の配置差分を整理する。
5. リスト改名/アーカイブ/削除/アーカイブ解除の既存helper・文言・provider経路を移設または再利用する。
6. 既定インボックスの保護対象操作をメニューから隠す。判定方法は既存の「最初のリストを保護する」実装に依存しすぎず、利用可能なID/metadata/providerを確認して決める。
7. アーカイブ済みリストを開いた状態で「アーカイブ解除」が出ることを確認する。
8. en/ja ARBを更新した場合は `flutter gen-l10n` を実行する。
9. widget testとvisual QAを追加・更新する。
10. 共通受け入れ基準の品質ゲートを実行する。
11. 指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `ListsScreen` の通常リスト行に行内PopupMenuButtonとchevronがないことがwidget testで確認できる。
- [ ] `ListsScreen` のアーカイブ済みリスト行に行内PopupMenuButtonとchevronがなく、タップで対象リストを開けることがwidget testで確認できる。
- [ ] 「New list」行からリスト作成ダイアログを開く既存フローが維持されていることがwidget testで確認できる。
- [ ] 開いた通常リスト画面の右上overflowから改名できることがwidget testで確認できる。
- [ ] 開いた通常リスト画面の右上overflowからアーカイブできることがwidget testで確認できる。
- [ ] 開いた通常リスト画面の右上overflowから削除確認フローに入り、既存の不可逆警告/件数警告/アーカイブ誘導文言が流用されていることがwidget testで確認できる。
- [ ] 既定インボックスでは削除/アーカイブ項目が右上overflowに表示されないことがwidget testで確認できる。
- [ ] アーカイブ済みリストを開いた画面では「アーカイブ解除」が表示され、実行できることがwidget testで確認できる。
- [ ] `lists.png` / `lists_archived.png` / リストを開いた画面のoverflow展開スクリーンショットを生成し、完了報告にPNGパスが記録されている。
- [ ] UI文字列を追加・変更した場合、en/ja ARBと生成l10nが更新され、直書き文字列チェックに通っている。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` セクション3のリスト一覧規則を正とする。
- リスト一覧行はナビゲーション行であり、行内に操作メニューやchevronを置かない。
- 保護対象操作（削除/アーカイブ）は既定インボックスに表示しない。実行時に弾くだけでなく、UI上で選べないこと。
- 既存の確認ダイアログとl10n文言を優先して流用する。文言を増やす場合はen/ja ARBへ追加する。
- 削除はtask-38後の恒久削除モデルに従い、軽い操作として扱わない。
- アーカイブは保全経路であり、削除とは意味が異なる。メニュー文言・確認文言で混同しない。
- home表示のヘッダー右上にoverflowを追加する場合、既存のリストメニュー/ソート導線を壊さない。
- 新規依存は追加しない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- `ListsScreen` から撤去した行内操作と、残したナビゲーション/新規作成動線
- `TasksScreen` へ移設したリスト操作メニューの配置（home / non-home）
- 既定インボックスの保護対象操作を非表示にした判定方法
- アーカイブ済みリストを開いた場合のメニュー内容とアーカイブ解除フロー
- 流用した確認ダイアログ・件数警告・アーカイブ誘導文言
- 追加・更新したl10nキー
- 追加・更新したwidget testの対象と結果
- visual QAスクリーンショットの保存パスと目視確認結果
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）
