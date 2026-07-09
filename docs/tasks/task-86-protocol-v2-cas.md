# task-86: protocol v2 CAS correctness基盤

> ステータス: 実装中
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

latest-one encrypted blobを`revision_hlc` LWWで更新すると、同じbaseからの別field編集で先にACKされたblobが消える。serverは復号mergeできないため、v2はbase revision CASとclient merge/rebaseを必須とする。release前のためv1互換は作らない。

## 2. 事前に読むべきファイル

- `docs/05_設計判断記録.md` ADR-012、ADR-014
- `docs/tasks/task-82-sync-correctness-redesign.md`
- `core/sync/src/{engine,enqueue,apply,field_map,merge,envelope}.rs`
- `core/storage/src/lib.rs`
- `server/src/sync.rs`
- `server/migrations/202607080001_sync_server.sql`
- `server/tests/sync_server.rs`

## 3. ゴール

- v1 wireをshared typed v2 wireへ完全置換する。
- stale encrypted blobのblind overwriteをCASで拒否する。
- conflictをclient merge/rebaseへ接続し、ACK済み別field変更を保全する。
- outbox responseをop IDで厳密照合する。

## 4. スコープ

### やること

- `/v2/tenants/{id}/push|pull`とshared `SyncCollection` / tagged state DTO。
- `base_revision_hlc`、`revision_hlc`、`mutation_hlc`、`delete_hlc`。
- server current-head CAS、semantic live/delete fence、collection immutability。
- local sync schemaの破壊的v2 migration、recordごとのoutbox coalesce、op ID ACK。
- conflict current envelopeのmerge/rebase、remote revision observe。
- response件数/ID検証、strict base64 decode。
- envelope v2のみ。v1 fallbackなし。
- CASなしで変更が消える2-client回帰test。

### やらないこと

- typed task/list plaintextの全面移行。
- changed-fieldだけのclock更新。
- completion/placement compound、固定幅rank、reorder/rebalance。
- durable quarantine、cursor page transaction、full resync。
- aggregate delete scope / epoch。

## 5. 実装手順

1. 消失する2-client scenarioとinvalid response testを先に追加する。
2. shared wire型とserver schema/route/CASを実装する。
3. local v2 state/outbox schemaとcoalesce/ACK by op IDを実装する。
4. client engineのstrict response validationとconflict merge/rebaseを実装する。
5. v1 route/envelope/schema codeを削除する。
6. 独立検証と全品質ゲートを実行する。

## 6. 受け入れ基準

- [ ] stale base pushがcurrentを上書きせずconflictを返す。
- [ ] conflict clientがcurrentをmergeし、新base/new revisionで再pushする。
- [ ] 先にACKしたclientを停止しても同時別field編集が両方残る。
- [ ] retry/no-op、semantic superseded、live/delete両方向が収束する。
- [ ] outbox headはrecordごとにcoalesceされ、old op responseがnew headをACKしない。
- [ ] response reorderは成功し、missing/duplicate/unknown/op-record mismatchは全体errorになる。
- [ ] invalid base64/clock/state/collectionをrejectする。
- [ ] v1 HTTP route、envelope fallback、dual schemaが残っていない。
- [ ] workspace/server/Flutter品質ゲートと`git diff --check`が成功する。

## 7. 制約・注意事項

- protocol v2途中をrelease-readyと表現しない。
- HTTPやconflict fetchをSQLite write transaction内で行わない。
- conflict時にoutboxをACKしない。
- tombstone受信時もsemantic stateを削除しない。
- serverは暗号blobを解釈しない。
- domain rowsは保持してよいがv1 sync metadataの互換維持は不要。

## 8. 完了報告に含めるべき内容

- wire/server/local schemaの最終shape。
- CAS conflict/rebaseとresponse validationのテスト。
- 破棄したv1 compatibility surface。
- 品質ゲート。
- typed field clock/placement/rankへの後続事項。
