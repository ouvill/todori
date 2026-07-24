---
id: 019f9344-5497-7c61-ba43-5127191bb37b
title: Task template and series domain redesign
status: active
lane: critical
milestone: maintenance
---

# Task template and series domain redesign

## 1. 背景とコンテキスト

現行P2-M8モデルは `TaskTemplate -> RecurrenceSchedule -> Task` を必須の依存関係とし、繰り返しタスクを作るためにTemplateを先に作成する。Template削除は参照Scheduleも削除し、future-only編集と決定的IDはschedule revisionとtemplate revisionの2軸を扱う。

しかしTemplateは「不定期に手動起票する定型作業」、繰り返しは「規則に従って自動起票するtask series」であり、本来は独立した利用意図である。共通するのはtask subtreeの再利用可能な内容だけである。

2026-07-24にプロダクトオーナーと概念モデルをレビューし、次を承認済みの設計入力とする。

- `TaskContent -> TaskBlueprintNode -> TaskBlueprint` を再利用可能な値オブジェクトとして定義する。
- `TaskTemplate`は名前付きの`TaskBlueprint`を所有し、直接作成・編集できる。
- `TaskSeries`は自身の`TaskBlueprint`とrecurrence configを所有し、Templateを必須参照しない。
- TemplateからTaskまたはSeriesを作る場合はBlueprintをコピーし、以後のライフサイクルを分離する。
- 生成済みTaskは任意のseries occurrence provenanceだけを保持する。

本変更はdomain、local schema、sync protocol、client、FRB、Flutter UI、仕様、ADRへまたがる。一般配布前の互換性方針に従い、旧schedule形式のcompatibility reader / writerは追加せず最終設計へ直接置換する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/work-019f6ccd-da7b-71b2-be11-781eb6e9be7e-p2-m8-templates-recurrence.md`
- `docs/02_機能仕様書.md` F-19〜F-21
- `docs/03_技術仕様書.md` template / schedule / task provenance / sync
- `docs/05_設計判断記録.md` ADR-007、ADR-015、ADR-016、ADR-021
- `core/domain/src/recurrence.rs`
- `core/storage/src/lib.rs`
- `core/client/src/runtime/recurrence.rs`
- `core/sync`
- `app/rust/src/api.rs`
- `app/lib/src/screens/templates_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`

## 3. ゴール

1. Task、Template、Seriesが同じ`TaskContent` / `TaskBlueprint`語彙を使う。
2. Templateを空のBlueprintから直接作成・編集できる。
3. 既存Task subtreeからTemplateまたはSeriesを作成できる。
4. TemplateからTaskまたはSeriesを作成できるが、作成後に永続参照やcascadeを持たない。
5. `TaskSeries`がBlueprint、起票先、RRULE、timezone、enabled、revision lineage、cursorを所有する。
6. TaskSeriesから生成したTask treeが複数端末、再実行、full resync、future-only編集で重複せず収束する。
7. Template編集・削除が既存TaskやTaskSeriesを変更しない。

## 4. スコープ

### やること

- `TaskContent`、`TaskBlueprintNode`、`TaskBlueprint`をdomain値オブジェクトとして導入する。
- `TaskTemplate`のsnapshot語彙をBlueprintへ置き換え、直接create / update APIを追加する。
- `RecurrenceSchedule`を`TaskSeries`へ置き換え、Template IDの必須参照を削除する。
- Seriesのatomic configをBlueprint、target list、RRULE、starts at、timezone、enabledで構成し、cursorと分離してmergeする。
- task provenanceをseries ID、series revision、occurrence instant、blueprint node keyへ置き換える。
- Task IDをseries ID、series revision、occurrence instant、blueprint node keyからUUIDv5で生成する。
- schema v22とsync protocol v8を導入し、`schedules` collectionを`task_series`へ置き換える。
- Template / SeriesはTenant Root DEK、生成TaskはList DEKで暗号化する既存境界を維持する。
- Templateからの手動起票、TemplateからSeries作成、Task subtreeからTemplate / Series作成をclient APIへ追加する。
- Template専用Blueprint editorをTask編集部品の制限モードとして提供し、空からの作成・直接編集・複製を可能にする。
- Series管理をTemplateの子UIから独立させる。
- F-19〜F-21、技術仕様、ADR-021の後継ADRを新モデルへ更新する。`docs/02_機能仕様書.md`の変更は2026-07-24のプロダクトオーナー承認に含む。

### やらないこと

- Template変数、条件分岐、外部イベントtrigger。
- Template更新を既存Task / Seriesへ自動伝播するlive link。
- 「この予定回だけ」「以後すべて」以外の複雑なSeries編集UI。
- server側での平文RRULE処理またはTask生成。
- 旧schema / protocolのdual read、dual write、fallback。
- push、Pull Request作成、merge。

## 5. 実装手順

1. 後継ADRと仕様差分を作成し、集約境界、コピーセマンティクス、削除セマンティクスを固定する。
2. domain型と変換、validation、決定的ID、streakをtest-firstで置き換える。
3. local schema v22、storage repository、atomic settlement、task provenanceを実装する。
4. sync protocol v8、collection、merge、暗号plaintext、full-resync依存順を実装する。
5. `TaskveilClient` APIとFRB typed DTOを置き換える。
6. FlutterへTemplate直接editorと独立したSeries管理UIを実装する。
7. Rust / Flutter / Postgres / cross-build / Visual QAを統合HEADで検証する。
8. 実装担当外の独立検証を行い、指摘を修正して完了記録を残す。

## 6. 受け入れ基準

- [x] `TaskContent`がTaskとBlueprintNodeで同じ内容語彙を表す。
- [x] Blueprintが1 root、非循環、node key一意、sibling order一意、最大100 node、49,152 bytesを検証する。
- [x] 空からTemplateを作成し、root / childの追加、削除、並び替え、内容編集ができる。
- [x] 既存Task subtreeからTemplateを作成できる。
- [x] TemplateからTask treeを手動起票できる。
- [x] Templateまたは既存TaskからTaskSeriesを作成できる。
- [x] Template編集・削除後も既存TaskSeriesのBlueprintと生成動作が変化しない。
- [x] Series編集がTemplateを変更せず、将来予定回だけへ作用する。
- [x] Series削除後も生成済みTaskを保持する。
- [x] deterministic ID、100件分割、長期offline、停止・再開、future-only編集、stale端末、full resyncで重複しない。
- [x] streakがSeries provenanceを使って従来契約を維持する。
- [x] schema v21からv22へ開発データを移行するか、互換不要方針に従い明示的に再作成する。
- [x] protocol v8のTemplate / TaskSeries / Task roundtrip、wrong key、collection mismatch、tombstone、2-client収束をtestする。
- [x] TemplateとSeriesの英日UI、390 px、text scale 2.0、semanticsを確認する。
- [x] 全品質ゲート、Postgres integration、iOS / Android Rust cross-build、FRB再生成、`git diff --check`が成功する。
- [x] before / after Visual QAを保存して目視する。
- [ ] 統合HEADを実装担当外が独立検証する。

## 7. 制約・注意事項

- TemplateとSeriesの間に永続FKを作らない。任意のsource template IDをprovenanceとして保存する機能も本作業では追加しない。
- TemplateからTaskまたはSeriesを作る操作はBlueprintの値コピーである。
- Templateの削除はTemplateだけをtombstone化し、Task / Seriesへcascadeしない。
- Seriesの削除はSeriesだけをtombstone化し、生成済みTaskを変更しない。
- Series configとcursorを別の同期field groupとして扱い、cursor進行がconfig編集を失わせないようにする。
- future-only編集、cursor lattice、local settlement、E2EE、Tenant Root DEK、List DEK、single-flight syncの既存correctnessを維持する。
- public repoへprivate情報を記録しない。
- 既存FRB生成物を手編集しない。

## 8. 完了報告に含めるべき内容

- domain集約、コピー・削除セマンティクス、旧モデルとの差分。
- schema v22 / protocol v8 / migrationまたは開発データ再作成判断。
- deterministic generation、future-only編集、sync収束、streakのテスト証拠。
- Template直接編集とSeries管理UIのテスト・Visual QA。
- 全品質ゲート、Postgres integration、cross-build、FRB再生成の結果。
- 独立検証の判定、指摘、修正、再検証結果。
- local commit hash、未解決事項、push / PR未実施。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-24
- domain: `TaskContent -> TaskBlueprintNode -> TaskBlueprint`を共通のcontent-only値として導入した。`TaskTemplate`と`TaskSeries`はそれぞれBlueprintを所有し、TemplateからTask / Seriesを作る操作は値コピーとした。Template / Series削除は生成済みTaskや相互集約へcascadeしない。Task provenanceとUUIDv5 IDはseries ID、config revision、occurrence instant、node keyへ一本化した。
- client / UI: 空からのTemplate作成、Blueprintのroot / child内容編集、追加、削除、並び替え、既存Task subtreeからのTemplate / Series作成を追加した。Templates画面はTemplateと「Recurring tasks」を独立sectionとして表示する。停止・再開テストで開始前編集が最初の予定回を飛ばす境界を検出し、subsecondを保持したRRULE列挙とcursor再計算へ修正した。
- DB / sync: local schema v22とprotocol v8へ更新し、`schedules`を`task_series` collectionへ置換した。通常Taskは保持して旧recurrence provenanceを外し、変換できない旧Template / Scheduleとprotocol v8未満のtransport stateは一般配布前方針に従い再作成する。zero-knowledge server migrationは一度だけlegacy encrypted recordを削除するmarkerを持ち、再起動時に再削除しない。
- テスト: `cargo test --workspace`はclient 47、domain 62、storage 89成功 / performance 1件手動skip、sync 80、server unit 20とPostgreSQL integration全件を含め成功した。deterministic tree、105予定回の100 + 5分割と再実行0件、停止・再開、Series削除後の105 Task保持、future-only revision、streak、full-resyncでのTemplate非依存、Tenant Root DEK / collection AADを確認した。
- Flutter: `flutter analyze`は0 issue、`flutter test`は276成功 / Visual QA harness 1件意図的skip。Templates widget 5件で英日、390 px、text scale 2.0、semantics、Template直接作成・編集・並び替え・削除を確認した。hardcoded string / client boundary / boundary self-testも成功した。
- build / Visual QA: FRBとl10nを再生成し、native release、iOS Simulator arm64、Android arm64-v8a Rust cross-buildに成功した。iOSは既知のdeployment target上書きwarning 1件のみ。beforeは`taskveil/app/build/visual_qa/p2_m8_templates_{en,ja,text_scale_2}.png`、afterは本worktreeの`app/build/visual_qa/task_series_domain_templates_{en,ja,text_scale_2}.png`と`task_series_domain_template_editor_en.png`を目視し、section分離、直接作成導線、英日、390 px、scale 2.0でoverflow / clippingがないことを確認した。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`、Flutter analyze / test、hardcoded string、client boundary 2種、PostgreSQL integration、iOS / Android cross-build、`git diff --check`が成功した。
- Commit: `f548363`（実装、仕様、ADR、schema v22 / protocol v8、FRB、UI、テスト）。
- 未解決: 実装担当外の独立検証のみ未実施。work itemは`active`を維持する。push / Pull Requestは行っていない。

### 独立検証

- 判定: 未実施
- 根拠: 統合HEADの実装と自己検証は完了したが、critical laneで必要な別セッションまたは人間による検証をまだ受けていない。
- 検証者: 未割り当て
