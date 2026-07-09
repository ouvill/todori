# task-82: 同期correctness基盤の再設計

> ステータス: 完了（ADR-012採用・技術仕様と実装順へ反映）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

task-72〜80で2台同期、削除tombstone、初回backfill、pull取りこぼしの暫定回復まで実装した。しかし2026-07-10の設計レビューで、ADR-004 / ADR-005 / ADR-010の方向性そのものよりも、同期correctnessを成立させる不変条件が仕様とproduction実装の間で欠けていることが確認された。

主な差分は、通常CRUDが全field HLCを更新してfield-level LWWをrecord-level LWWへ退化させること、`sort_order` が同期payloadから除外されること、domain更新とoutbox登録が別transactionであること、階層削除がroot/list 1件のtombstoneしか生成しないこと、復号不能recordをskipしてcursorを前進させること、フル再同期に固定snapshot/high-waterがないことである。

プロダクトオーナーは同日のレビュー結果を採用した。本タスクはコードを修正せず、同期correctnessの正本をADRと技術仕様へ反映し、後続実装順を更新する設計タスクである。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` §6、§8、§11
- `docs/05_設計判断記録.md` ADR-004、ADR-005、ADR-009〜011
- `docs/tasks/task-72-sync-engine.md`
- `docs/tasks/task-73-adr010-and-dek-alignment.md`
- `docs/tasks/task-80-sync-pull-recovery.md`
- `core/sync/src/enqueue.rs`
- `core/sync/src/apply.rs`
- `core/sync/src/engine.rs`
- `app/rust/src/api.rs`
- `app/rust/src/sync_store.rs`
- `server/src/sync.rs`

## 3. ゴール

- ADR-004 / ADR-005 / ADR-010を補正する同期correctnessの設計判断を採用状態で記録する。
- field HLC、record revision、placement、transactional outbox、cascade tombstone、pull失敗、full resyncの不変条件を技術仕様へ反映する。
- full resyncを先行実装せず、データ損失を防ぐ基盤から実装する順番へSTATUS / BACKLOGを更新する。
- 現行コードの動作を採用済み仕様と誤認しないよう、既知のrelease blockerを明記する。

## 4. スコープ

### やること

- `docs/05_設計判断記録.md` にADR-012を追加する。
- `docs/03_技術仕様書.md` の同期clock、並び順、同期flow、削除、full resync、テスト要件を更新する。
- `docs/tasks/STATUS.md` の現在とNextを更新する。
- `docs/tasks/BACKLOG.md` へ後続候補を分解して登録する。

### やらないこと

- Rust / Dart / SQL migration / APIの実装変更。
- ADR-010の「削除後の未push編集を復活として扱う」というプロダクト裁定の撤回。
- fractional positionの具体的な符号化方式や新規依存の選定。
- RLS policy、GC job、protocol v2 endpointの実装。

## 5. 実装手順

1. ADR-004 / ADR-005 / ADR-010とproduction経路の差分を列挙する。
2. ADR-012へcorrectness不変条件と既存ADRへの補正関係を記録する。
3. 技術仕様§6へclock、placement、transaction、pull、full resync、cascade deleteを反映する。
4. 技術仕様§11へproduction経路を通る必須テストを追加する。
5. STATUSのNextを依存順へ並べ替え、BACKLOGへ後続候補を分解する。
6. 文書間の用語、ADR参照、日付、実装済み/未実装の区別を確認する。

## 6. 受け入れ基準

- [x] ADR-012がAcceptedとして追加され、ADR-004 / ADR-005 / ADR-010を補正する範囲が明記されている。
- [x] `revision_hlc` と `field_hlcs` の役割が分離され、未変更fieldのHLCを更新しないことが明記されている。
- [x] task placementが `list_id` / `parent_task_id` / `sort_order` の原子的な同期値として定義されている。
- [x] domain更新、outbox、sync record stateが同一transactionで確定することが明記されている。
- [x] subtree/list削除が配下全recordのtombstoneを生成することが明記されている。
- [x] 復号不能・未知protocolをsilent skipしてcursorを進めないことが明記されている。
- [x] full resyncに固定 `snapshot_seq`、安定page token、delta catch-up、mark-and-sweep、high-water cursorが定義されている。
- [x] production CRUD経路、reorder、cascade delete、crash window、cursor/full resyncを通すテスト要件が明記されている。
- [x] STATUS / BACKLOGがfull resync先行ではなくcorrectness依存順になっている。
- [x] `git diff --check` が成功している。

## 7. 制約・注意事項

- ADR-012は既存のE2EE、最新状態方式、server seq cursor、空blob tombstoneを廃止しない。
- top-level revisionと暗号payload内field clockは別の責務であり、再pushのために全field clockを更新してはならない。
- serverは暗号payloadから親子関係を読めないため、cascade tombstoneはclientが削除前に列挙する。
- full resyncは通常pullの `since=0` 呼び出しと同一視しない。
- 現行実装はADR-012未準拠であり、文書更新だけで同期安全性が向上したとは扱わない。

## 8. 完了報告に含めるべき内容

- 採用したcorrectness不変条件。
- 補正したADRと技術仕様の節。
- STATUS / BACKLOGへ反映した実装順。
- 実行した文書検証。
- コード未変更であることと、残るrelease blocker。

## 9. 完了報告

- 作業日: 2026-07-10
- 結果: ADR-012を採用し、field clock、placement、transactional outbox、cascade tombstone、typed pull failure、snapshot full resyncを同期correctnessの前提として正本化した。実装順はfull resync先行からcorrectness基盤優先へ変更した。
- 証拠: `rg -n "ADR-012|revision_hlc|snapshot_seq|cascade tombstone|transactional outbox" docs` でADR、技術仕様、task、STATUS / BACKLOGの参照を確認。`git diff --check` 成功。
- Commit: 未コミット
- 未解決: 現行Rust実装はADR-012未準拠。後続taskでproduction同期テスト、共通client transaction、field clock / placement、cascade delete / typed pull、snapshot full resync、server protocol / RLSを順に実装する。
