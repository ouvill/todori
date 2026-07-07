# task-55: Homeサブツリー同伴表示

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
