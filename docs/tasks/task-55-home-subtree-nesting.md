# task-55: Homeサブツリー同伴表示

> ステータス: 完了（worker実装）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

2026-07-08ドッグフーディング第4回で、Homeのセクションに表示される親タスクの下に、期日なしサブタスクもぶら下がって表示されてほしい、というフィードバックが出た。

現状のHome横断ビューは、`get_home_tasks` で期日ありタスクを横断取得し、Flutter側でOverdue / Today / Tomorrow / Upcomingへフラットに振り分ける構造である。通常リスト画面と詳細画面では、task-45で階層ガイドと子孫ツリー表示が整備済みである。本タスクではその文法をHomeにも持ち込み、Home対象のルートタスクが開いている配下サブツリー全体を同伴するようにする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション3（タスク行、タスク一覧構造、Homeセクション）
- `docs/tasks/task-45-tree-guides-and-detail.md`
- `docs/tasks/task-51-home-restructure.md`
- `docs/tasks/task-53-swipe-and-motion.md`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/ui/task_components.dart`
- `app/rust/src/api.rs`
- `core/storage` の `TaskRepository` / Home横断クエリ実装
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- Home各セクションで、表示対象ルートタスクの配下サブツリー全体を階層ガイド付きで表示する。
- 配下サブツリーには期日なしサブタスクも含める。
- 同一セクション内では、親配下に表示される子を重複して単独表示しない。
- 子が親より早い別セクションに該当する場合は、その子を該当セクションにも単独表示する。
- Homeの既存操作規則（チェックトグル、スワイプ、詳細遷移、D&Dなし）と整合させる。
- 1万件規模で全リスト全件取得へ逃げない設計にする。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

実装者は、受け入れ基準を満たす最小範囲で変更すること。

- `core/storage` の該当repository/query実装（必要な場合）
- `app/rust/src/api.rs`（Home横断DTO/API変更時）
- `app/lib/src/rust/` と `app/rust/src/frb_generated.*`（Rust API変更時のFRB生成差分のみ）
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`（必要な場合）
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`（Home行で階層ガイドが不足する場合）
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/`（ARB変更時の生成差分のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-55-home-subtree-nesting.md`（完了報告の追記のみ）

### やること

1. Home横断データ取得を設計する。
   - ルート該当タスクの子孫を取得できるようにする。
   - 実装方式はworkerに委ねるが、1万件時に全リスト全件取得へ逃げないこと。
   - 例: まずHome対象ルート/該当タスクと対象list範囲を絞り、対象list内または対象root周辺のタスクだけを取得して子孫を組み立てる。
   - Rust APIを変更した場合は `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、生成物を手編集しない。
2. Homeセクション内の表示規則を実装する。
   - セクションのルートタスクは、開いている配下サブツリー全体を同伴する。
   - 期日なしサブタスクも親の下に表示する。
   - closed子はmuted + 取り消し線で親の下に表示する。
   - Homeセクションが折りたたまれている場合は、そのセクション配下の同伴サブツリーも隠す。
3. 重複規則を実装する。
   - 子が同一セクションに該当する場合は親の下のみ表示し、同一セクションの単独行として重複させない。
   - 子が親と異なる、より早いセクションに該当する場合は、その早いセクションにも単独表示する。
   - 別セクションの単独表示は親コンテキストなしの現行standalone Home表現を維持し、リスト名ラベルを表示する。
   - 同じタスクが親配下表示と単独表示の両方に出る場合も、チェック/スワイプ/詳細遷移後の状態は同期する。
4. 既存操作規則と整合させる。
   - チェックボックスはHome内の親/子/単独表示すべてで既存トグル規則に従う。
   - スワイプは既存Home行と同じく完了/再オープン、期日変更に接続する。
   - Homeでは手動並び替えを行わない。D&D対象にしない。
   - 行タップは該当タスク詳細へ遷移する。
5. テストとvisual QAを追加・更新する。
   - widget testで期日なし子が親の下に出ることを確認する。
   - widget testで同一セクション重複なしを確認する。
   - widget testで子がより早い別セクションに該当する場合、別セクションにも単独表示されることを確認する。
   - widget testでclosed子がmuted表示/取り消し線の対象になることを確認する。
   - visual QAで、期日なしサブタスク付きseedの `home_tasks` スクリーンショットを生成する。

### やらないこと

- Homeでの並び替え。
- 親のいないタスクの挙動変更。
- Homeセクション定義（Overdue / Today / Tomorrow / Upcoming）の変更。
- クイック追加シート（task-54）。
- 期日変更シートの選択肢追加。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、現行 `get_home_tasks`、`HomeTasksNotifier`、`_buildHomeSections`、`buildTaskTree`、`AppTaskRow`/`AppHomeTaskRow` の責務を把握する。
3. Home横断DTOを拡張するか、既存DTOのままFlutter側で組み立てるかを決める。
4. 対象ルート/対象list範囲を絞って子孫取得するqueryを設計し、1万件時の全リスト全件取得を避ける根拠を完了報告へ書けるようにする。
5. Homeセクション構築を、フラットな `TaskDto` 配列から、セクションごとの表示ノード列へ変更する。
6. 同一セクション重複排除と、より早い別セクションの単独表示を実装する。
7. Home子行にも階層ガイド、チェック、スワイプ、詳細遷移を接続する。
8. widget testとvisual QA seedを追加・更新する。
9. 品質ゲートを実行し、指示書末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] Homeのセクション対象ルートタスクの下に、期日なしサブタスクを含む開いている配下サブツリー全体が階層ガイド付きで表示されることがwidget testで確認されている。
- [ ] 子が親と同じHomeセクションに該当する場合、その子が同一セクション内で単独重複表示されないことがwidget testで確認されている。
- [ ] 子が親より早い別セクションに該当する場合、その子が早いセクションにも親コンテキストなしで単独表示されることがwidget testで確認されている。
- [ ] closed子が親の下に残り、muted + 取り消し線で表示されることがwidget testで確認されている。
- [ ] Homeの親/子/単独表示のチェックトグル、スワイプ期日変更、行タップ詳細遷移が既存規則どおり動くことがwidget testで確認されている。
- [ ] HomeではD&D並び替えが有効化されていないことが既存テストまたは追加テストで確認されている。
- [ ] Home横断クエリまたはbridge層の設計が、1万件時に全リスト全件取得を避ける説明を完了報告へ記録できる形になっている。
- [ ] Rust APIを変更した場合はFRB生成物がcodegen由来で更新され、手編集されていない。
- [ ] visual QAに期日なしサブタスク付きseedの `home_tasks` スクリーンショットが保存されている。
- [ ] 完了報告に、重複排除規則、別セクション単独表示規則、性能配慮、visual QAパス、品質ゲート結果が記録されている。

## 7. 制約・注意事項

- Home対象のルート判定は、Overdue / Today / Tomorrow / Upcoming の既存セクション定義に従う。
- 期日なしルートタスクをHomeへ新規表示しない。期日なしタスクがHomeに出るのは、Home対象親の配下サブタスクとして同伴される場合だけである。
- 「開いている配下サブツリー」は、通常リスト画面で表示されるactive/closed子の扱いに揃える。closed子を親の下から落とさない。
- 同一タスクが別セクションに単独表示される場合でも、状態のsource of truthを分けない。
- Homeでは手動並び替えを行わない。既存D&D実装をHome行へ流用しない。
- 横断クエリのために、全アクティブリストの全タスクを毎回取得する実装は避ける。やむを得ず暫定的に採る場合は、完了報告の未解決事項に性能リスクと代替案を記録する。
- UI文字列を追加する場合はARB化する。
- Rust APIを変更した場合、FRB生成物は必ずcodegenで更新し、手編集しない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- Home横断クエリ/bridge/providerの変更内容
- 1万件時に全リスト全件取得を避けるための設計説明
- Homeセクション構築と表示ノードの実装箇所
- 期日なし子、同一セクション重複排除、別セクション単独表示、closed子表示の実装内容
- チェックトグル、スワイプ、詳細遷移、D&D非対象との整合
- Rust API/FRB生成物の変更有無
- 追加・更新したテスト名と検証対象
- visual QA before/afterスクリーンショットの保存パス
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-08

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md`
- `docs/tasks/task-45-tree-guides-and-detail.md`
- `docs/tasks/task-51-home-restructure.md`
- `docs/tasks/task-53-swipe-and-motion.md`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/core/task_tree.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/ui/task_components.dart`
- `app/rust/src/api.rs`
- `core/storage/src/lib.rs`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

実装結果:

- `core/storage/src/lib.rs` の `HomeTask` に `is_home_target` を追加した。
- `core/storage/src/lib.rs` の `TaskRepository::list_home` を再帰CTEに変更し、Home対象タスクを起点にその子孫だけを取得するようにした。
- `app/rust/src/api.rs` の `HomeTaskDto` に `is_home_target` を追加した。
- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、`app/lib/src/rust/api.dart`、`app/lib/src/rust/frb_generated.dart`、`app/rust/src/frb_generated.rs` を更新した。
- `app/lib/src/screens/tasks_screen.dart` でHomeセクションごとの表示ノードを `FlattenedTaskTreeNode` として構築するようにした。
- `app/lib/src/screens/tasks_screen.dart` で同一セクション、または親がより早いセクションにある子は単独表示から除外するようにした。
- `app/lib/src/screens/tasks_screen.dart` で子が親より早いセクションに該当する場合は、その子を早いセクションにも単独表示するようにした。
- `app/lib/src/ui/task_components.dart` の `AppHomeTaskRow` に階層ガイド用の `depth`、`isLastSibling`、`ancestorLineContinuations`、key引数を追加した。
- `app/test/support/fake_bridge_service.dart` の `getHomeTasks` を、実装と同じHome対象タスク+子孫取得、`isHomeTarget` 付きDTO返却に変更した。

1万件時に全リスト全件取得を避けるための設計:

- storage層の `list_home` は、まず `due_at IS NOT NULL`、active list、activeまたは当日closed条件に合うHome対象タスクIDを `home_targets` で絞る。
- その後 `home_targets` を起点に `home_scope` 再帰CTEで子孫だけを取得する。
- Homeと無関係なactive list内の全タスクは取得しない。

Home表示規則:

- 期日なし子は、Home対象親の配下サブツリーとして表示する。
- 同一セクションに該当する子は、親の下にだけ表示し、同一セクションの単独行にはしない。
- 子が親より早いセクションに該当する場合は、早いセクションにも親コンテキストなしで単独表示する。
- closed子は親の下に残り、既存の `isTaskClosed` 表現によりmuted + 取り消し線で表示する。
- Homeセクションを折りたたむと、当該セクション内の同伴サブツリーも非表示になる。

既存操作規則との整合:

- Home親/子/単独表示は既存のチェックトグル経路を使用する。
- Home親/子/単独表示は既存の `Slidable` 期日変更経路を使用する。
- Home親/子/単独表示は既存の詳細遷移経路を使用する。
- Homeでは `_TaskDragReorderTarget` を生成せず、D&D対象にしない。
- 同じタスクが親配下表示と単独表示の両方に出る場合も、同じ `TaskDto` IDをsource of truthとして扱う。

追加・更新したテスト:

- `core/storage/src/lib.rs` `list_home_filters_due_active_and_closed_tasks_across_active_lists`: 期日ありHome対象タスクの期日なし子孫が返り、子孫の `is_home_target` がfalseになることを追加検証した。
- `app/test/widget_test.dart` `home shows target subtrees with duplicate and interaction rules`: 期日なし子の親配下表示、同一セクション重複排除、親より早い子の別セクション単独表示、closed子の取り消し線、折りたたみ、重複表示時の状態同期、チェックトグル、スワイプ期日変更、詳細遷移、D&D非対象を検証した。
- `app/test/support/fake_bridge_service.dart` のHome fake取得を更新し、widget testのseedで子孫同伴を検証できるようにした。

visual QA:

- 作業前退避先: `app/build/visual_qa_before/`
- before: `app/build/visual_qa_before/home_tasks.png`
- after: `app/build/visual_qa/home_tasks.png`
- `app/build/visual_qa/home_tasks.png` を目視し、Tomorrowセクションの `Plan the product launch event` の下に、期日なしサブタスク `Draft the launch checklist` と `Confirm final copy in the hero panel` が階層ガイド付きで表示されていることを確認した。

品質ゲート:

- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功
- `cd app && flutter analyze`: 成功
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter test`: 成功（85件成功、visual QA harness 1件skip）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `sh app/tool/visual_qa.sh`: 成功（36件成功）
- `git diff --check`: 成功

変更ファイル一覧:

- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `docs/tasks/README.md`
- `docs/tasks/task-55-home-subtree-nesting.md`

未解決事項:

- なし

親レビュー指摘対応（fixer追記、2026-07-08）:

- Home同伴サブツリー内の期日なしタスクでは、`No due date` ピルを表示しないようにした。
- Homeセクション件数バッジを表示行数から分離し、期日でそのセクションに該当する未完了Home対象タスク数のみを数えるようにした。同伴サブツリー行は件数に含めない。
- Home同伴サブツリー内のリスト名ラベルは、セクションルートと同じリストの場合は非表示にし、異なるリストの場合のみ表示するようにした。
- `app/test/widget_test.dart` の `home shows target subtrees with duplicate and interaction rules` に、期日なしピル非表示、件数バッジ、同一/別リストの子ラベル表示条件の検証を追加した。

fixer確認結果:

- `cd app && flutter analyze`: 成功
- `cd app && flutter test`: 成功（85件成功、visual QA harness 1件skip）
- `sh app/tool/visual_qa.sh`: 成功（36件成功）
- `app/build/visual_qa/home_tasks.png` を目視し、Tomorrowセクションが「1」、期日なし同伴サブタスクに日付ピルなし、同じInbox配下の子にリスト名ラベルなしであることを確認した。
