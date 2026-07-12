# task-102: タスク計画属性とCapture

> ステータス: 進行中（共有command / FRB契約を先行実装）
> 着手日: 2026-07-13

## 1. 背景とコンテキスト

`Task`、local DB、同期plaintextには`priority`、typed `due`、`scheduled_at`、`estimated_minutes`が存在するが、作成・更新commandは全属性を運べない。特に作成時のpriority / Planと、編集時のPlanがclient境界で失われるため、Design Labで検証したList / Due / Plan / PriorityのCaptureをproductionへ接続できない。

本taskでは共有契約を先に完成させ、その統合後にproduction CaptureとTask detailを同じ契約へ接続する。`due`は完了期限、`scheduled_at`は作業を始める予定instant、`estimated_minutes`は作業見積りであり、互いに代用しない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md` / `STATUS.md` / `BACKLOG.md`
- `docs/03_技術仕様書.md` §3.6 / §4.8
- `docs/05_設計判断記録.md` ADR-017
- `docs/tasks/task-100-product-ui-redesign-v2.md`
- `docs/tasks/task-101-task-due-semantics-redesign.md`
- `core/domain/src/entities.rs` / `usecases.rs`
- `core/client/src/runtime/application.rs` / `crud_service.rs` / `mutation_service.rs`
- `core/storage/src/lib.rs`
- `core/sync/src/field_map.rs`
- `app/rust/src/api.rs`とFRB生成設定
- `app/lib/src/core/bridge_service.dart` / `providers.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/task_detail_screen.dart`

## 3. ゴール

- create / updateがpriority、typed due、scheduled_at、estimated_minutesを欠落なく保存する。
- domain row、undo、同期record state、outbox headが1つのtransactionで更新される。
- CaptureからList / Due / Plan / Priorityを作成前に設定できる。
- Planで開始予定日時と5分刻みの見積りを設定できる。
- 一覧と詳細でpriorityを静かに識別・編集できる。

## 4. スコープ

### やること

- `CreateTaskCommand` / `UpdateTaskCommand`と内部mutation inputへpriority、typed due、scheduled_at、estimated_minutesを追加する。
- anonymous / account-bound双方で同じ属性を1 transaction、1 outbox headへ保存する。
- priorityを0〜3、設定済みestimated_minutesを正の5分刻みとして検証する。
- FRB Rust APIを更新し、正規codegenでDart APIを生成して`BridgeService`へ公開する。
- CaptureへList / Due / Plan / Priorityのproperty rowを実装する。
- Plan sheetへ予定日時、5分刻み見積り、25 / 45 / 60分presetを実装する。
- Task detailへ編集可能なPriority / Plan property rowを追加する。
- task rowへpriority 1 / 2 / 3の小さなdotを表示し、Tooltip / Semanticsで色以外にも意味を伝える。
- focused Rust / bridge / provider / widget testとVisual QAを追加する。

### やらないこと

- Task / DB / sync schemaの新規field追加やmigration。
- Search、Calendar、Timer、Pomodoro、Focus routeの実装。
- `scheduled_at`をdueやreminderとして扱うこと。
- Timer開始によるtask status変更。
- 新規package、互換mode、Design Labからproductionへのimport。

## 5. 実装手順

1. domain validationとclient command / mutation inputを先行更新する。
2. anonymous / account-bound create / updateへ全属性を適用し、transaction / undo / outboxのatomicity testを固定する。
3. FRB Rust APIを更新し、`flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`で生成物を更新する。
4. `BridgeService`、fake、providerのtyped interfaceを同期する。
5. production Captureのproperty rowsとPlan / Priority sheetを実データ契約へ接続する。
6. Task detailとtask rowの表示・編集を同じprovider契約へ接続する。
7. 狭幅、日本語、text scale 2.0、sheet全状態をVisual QAする。
8. 統合HEADで品質ゲートを実行し、実装非担当者が独立検証する。

## 6. 受け入れ基準

- [ ] create / updateの公開commandがpriority、typed due、scheduled_at、estimated_minutesを持つ。
- [ ] priority 0〜3だけを受理し、estimated_minutesはnullまたは正の5分刻みだけを受理する。
- [ ] scheduled_atがdueとは別の開始予定instantとして保存・更新・clearできる。
- [ ] account-bound createが全属性をtask rowと同期plaintextへ保存し、outbox headを1件だけ持つ。
- [ ] account-bound updateが全属性、edit undo、HLC、record state、outbox headを1 transactionで更新する。
- [ ] anonymous create / update / undoも全属性を保持する。
- [ ] outboxまたはrecord state失敗時にdomain row、undo、HLCを含めてrollbackする。
- [ ] FRB / Dartがtyped `TaskDueInput`を維持し、scheduled_atとestimated_minutesを公開する。
- [ ] CaptureでList / Due / Plan / Priorityを設定して1回のcreateで保存できる。
- [ ] Plan sheetが予定日時と見積りを提供し、5分刻みと25 / 45 / 60分presetを持つ。
- [ ] priority dotが一覧で低強度に表示され、Tooltip / Semanticsで値を識別できる。
- [ ] Task detailでpriority、due、scheduled_at、estimated_minutesを編集・clearできる。
- [ ] 320px、390x844、日本語、text scale 2.0でsheetにoverflowや操作不能がない。
- [ ] Design Labはfake data専用のままでproductionからimportされない。
- [ ] Rust / Flutterのfocused test、Visual QA、共通品質ゲートが成功する。
- [ ] 独立検証で受け入れ基準とtransaction / outbox不変条件が合格する。

## 7. 制約・注意事項

- `TaskDue`はADR-017のsealed tagged unionを維持し、raw epoch期限へ戻さない。
- `scheduled_at`は開始予定、`due`は完了期限、`remind_at`は通知、`estimated_minutes`は見積りである。
- `in_progress`はKanbanまたはユーザーの明示操作専用であり、Plan / Capture / Timerから自動変更しない。
- sync field mapは既存fieldを利用し、schema / protocol versionを不要に変更しない。
- FRB生成物を手編集しない。
- productionから`app/test/visual_qa`やDesign Labをimportしない。
- 実装担当と独立検証担当を分け、WIPはtask-102の1件に限定する。

## 8. 完了報告に含めるべき内容

- command / FRB / Dartの最終API shape。
- anonymous / account-boundのcreate / update / undoと、1 transaction / 1 outboxの証拠。
- validation errorの境界とfocused test名。
- Capture、Plan sheet、Priority表示、Task detailの実装結果。
- Visual QAの保存先と狭幅、日本語、text scale 2.0の所見。
- 全品質ゲート、独立検証、commit hash、未解決事項。
