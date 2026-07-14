# task-102: タスク計画属性とCapture

> ステータス: 完了（planning属性をatomic commandとproduction UIへ接続）
> 作業日: 2026-07-13

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

- [x] create / updateの公開commandがpriority、typed due、scheduled_at、estimated_minutesを持つ。
- [x] priority 0〜3だけを受理し、estimated_minutesはnullまたは正の5分刻みだけを受理する。
- [x] scheduled_atがdueとは別の開始予定instantとして保存・更新・clearできる。
- [x] account-bound createが全属性をtask rowと同期plaintextへ保存し、outbox headを1件だけ持つ。
- [x] account-bound updateが全属性、edit undo、HLC、record state、outbox headを1 transactionで更新する。
- [x] anonymous create / update / undoも全属性を保持する。
- [x] outboxまたはrecord state失敗時にdomain row、undo、HLCを含めてrollbackする。
- [x] FRB / Dartがtyped `TaskDueInput`を維持し、scheduled_atとestimated_minutesを公開する。
- [x] CaptureでList / Due / Plan / Priorityを設定して1回のcreateで保存できる。
- [x] Plan sheetが予定日時と見積りを提供し、5分刻みと25 / 45 / 60分presetを持つ。
- [x] priority dotが一覧で低強度に表示され、Tooltip / Semanticsで値を識別できる。
- [x] Task detailでpriority、due、scheduled_at、estimated_minutesを編集・clearできる。
- [x] 320px、390x844、日本語、text scale 2.0でsheetにoverflowや操作不能がない。
- [x] Design Labはfake data専用のままでproductionからimportされない。
- [x] Rust / Flutterのfocused test、Visual QA、共通品質ゲートが成功する。
- [x] 独立検証で受け入れ基準とtransaction / outbox不変条件が合格する。

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

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-13
- command / bridge: `CreateTaskCommand`と`UpdateTaskCommand`がpriority、ADR-017のtyped due、scheduled_at、estimated_minutesを運ぶ。FRBを正規codegenし、Dart `BridgeService`、providers、fakeへ同じ契約を接続した。priorityは0〜3、見積りはnullまたは正の5分刻みだけを受理する。
- atomicity: anonymous / account-boundのcreate / updateで全planning属性を保存する。account-boundは1つの`SqliteWriteTx`内でdomain row、edit undo、HLC、record state、暗号plaintext、outbox headを更新し、同一taskのoutbox headは1件へcoalesceする。outbox / record state failure時のrollback testを維持した。schema / protocol version変更はない。
- UI: CaptureをList / Due / Plan / Priorityの縦積みhairline property rowへ拡張した。Planは開始予定日時、±5分、25 / 45 / 60分preset、clear / applyを持ち、PriorityはNone / Low / Medium / Highをdot・文字・選択markで示す。選択値は連続登録でも保持する。Task detailはStatus / Due / Plan / Priority / Reminder / Subtasksの順で、明示的sentinelにより他属性編集時のplanning値維持と明示的null clearを区別する。Plan / Capture / Timerからstatusや`in_progress`は変更しない。
- responsive / accessibility: 日本語text scale 2.0でPlan footerが横にはみ出す問題をtestで検出し、adaptive `Wrap`へ修正した。320px、390x844、日本語、text scale 2.0、RTLで操作到達性とoverflowなしを確認した。priority dotはTooltip / Semanticsを持ち、property rowでは重複読上げを除外する。
- 証拠: domain planning validation、account-bound create plaintext / outbox head、update undo / HLC / outbox、rollback、native bridge create-update-clear、Capture全属性と連続登録、Detail update / clear、Home invalidationの回帰testが成功した。Visual QAは64 case成功、70 PNGを生成し、Capture英日・320・text scale 2.0、Plan通常・320・text scale 2.0、Priority、Detail Planを目視した。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker統合testを含む`cargo test --workspace`、Rust bridge release build、`flutter analyze`、`flutter test --concurrency=1`（148成功、Visual QA harness 1件は通常実行で意図的skip）、hardcoded strings、client boundaries、`git diff --check`が成功した。
- Commits: `ac7cda0`、`40d1548`、`f326bec`、`2fc0f00`、`140fb54`。
- 未解決: なし。Search、Calendar、Timer / Focusは後続taskで実装する。

### 独立検証

- 判定: 合格（HEAD `140fb54`、修正要求なし）。
- 根拠: 実装非担当者がcommand / FRB / Dart、validation、anonymous / account-bound、単一transaction / 単一outbox head、undo / rollback、明示的null、status非変更を照合した。`cargo fmt`、workspace clippy、focused Rust atomicity / rollback 7件、Rust bridge release build、`flutter analyze`、core usecase + widget 112件、hardcoded strings、client boundaries、`git diff --check`を再実行して成功した。関連70 PNGとRTL testを確認し、欠け・overflow・home indicator下の未着色・読めない属性状態がないと判定した。
- 検証者: 実装非担当サブエージェント `/root/task102_verifier`。
