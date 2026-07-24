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

- [ ] `TaskContent`がTaskとBlueprintNodeで同じ内容語彙を表す。
- [ ] Blueprintが1 root、非循環、node key一意、sibling order一意、最大100 node、49,152 bytesを検証する。
- [ ] 空からTemplateを作成し、root / childの追加、削除、並び替え、内容編集ができる。
- [ ] 既存Task subtreeからTemplateを作成できる。
- [ ] TemplateからTask treeを手動起票できる。
- [ ] Templateまたは既存TaskからTaskSeriesを作成できる。
- [ ] Template編集・削除後も既存TaskSeriesのBlueprintと生成動作が変化しない。
- [ ] Series編集がTemplateを変更せず、将来予定回だけへ作用する。
- [ ] Series削除後も生成済みTaskを保持する。
- [ ] deterministic ID、100件分割、長期offline、停止・再開、future-only編集、stale端末、full resyncで重複しない。
- [ ] streakがSeries provenanceを使って従来契約を維持する。
- [ ] schema v21からv22へ開発データを移行するか、互換不要方針に従い明示的に再作成する。
- [ ] protocol v8のTemplate / TaskSeries / Task roundtrip、wrong key、collection mismatch、tombstone、2-client収束をtestする。
- [ ] TemplateとSeriesの英日UI、390 px、text scale 2.0、semanticsを確認する。
- [ ] 全品質ゲート、Postgres integration、iOS / Android Rust cross-build、FRB再生成、`git diff --check`が成功する。
- [ ] before / after Visual QAを保存して目視する。
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
