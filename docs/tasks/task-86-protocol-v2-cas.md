# task-86: protocol v2 CAS correctness基盤

> ステータス: 完了（protocol v2 CAS、op-id ACK、atomic conflict rebaseへ置換）
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
- conflictをclient merge/rebaseへ接続し、server current headを失わずに新baseへ再送できるようにする。
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
- 正しいchanged-field clockを持つpayloadで、CASなしなら消える変更を保全するclient回帰test。

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

- [x] stale base pushがcurrentを上書きせずconflictを返す。
- [x] conflict clientがcurrentをmergeし、新base/new revisionで再pushする。
- [x] 先にACKしたclientを停止してもserver current headが失われず、正しいchanged-field clockを入力したpayloadでは両fieldが残る。production CRUDを通る2-client gateはchanged-field実装taskで行う。
- [x] retry/no-op、semantic superseded、live/delete両方向が収束する。
- [x] outbox headはrecordごとにcoalesceされ、old op responseがnew headをACKしない。
- [x] ACK、remote revision observe、domain/state、conflict rebase headは同一`BEGIN IMMEDIATE`で確定し、deferred/race時はrollbackまたはstale response無視となる。
- [x] response reorderは成功し、missing/duplicate/unknown/op-record mismatchは全体errorになる。
- [x] invalid base64/clock/state/collectionをrejectする。
- [x] v1 HTTP route、envelope fallback、dual schemaが残っていない。
- [x] workspace/server/Flutter品質ゲートと`git diff --check`が成功する。

## 7. 制約・注意事項

- protocol v2途中をrelease-readyと表現しない。
- HTTPやconflict fetchをSQLite write transaction内で行わない。
- conflictを未解決のままACKしない。stale opの削除はcurrent適用またはreplacement head生成と同一transactionでだけ確定する。
- tombstone受信時もsemantic stateを削除しない。
- serverは暗号blobを解釈しない。
- domain rowsは保持してよいがv1 sync metadataの互換維持は不要。
- task-86はCAS transport基盤であり、production CRUDの同時別field保全を完了扱いにしない。

## 8. 完了報告に含めるべき内容

- wire/server/local schemaの最終shape。
- CAS conflict/rebaseとresponse validationのテスト。
- 破棄したv1 compatibility surface。
- 品質ゲート。
- typed field clock/placement/rankへの後続事項。

## 9. 完了報告

- 作業日: 2026-07-10
- 結果: sync push/pullをshared typed protocol v2へ置換し、`base_revision_hlc` CAS、tagged live/tombstone、semantic fence、current envelope conflictを実装した。local schema v11はrecord単位outbox head、UUID `op_id`、server revision付きsemantic stateへ破壊的移行し、domain rowとlocal crypto cacheだけを保持する。
- Atomicity: Accepted/NoOpのop-id ACKとcurrent revision更新、Conflict/Supersededのop-id guard、remote HLC observe、domain/state適用、replacement head生成をowned `BEGIN IMMEDIATE`で確定する。deferredはrollbackし、送信中に新headへ置換された旧responseはdomain/stateへ触れない。
- 証拠: server CAS/semantic/schema/route 3 tests + auth 1 test、`taskveil-sync` 47 tests、`taskveil-storage` 64 tests（1 ignored）、`taskveil-client` 17 tests、bridge 1 testが成功。正しいchanged-field clockを与えた`conflict_current_merges_distinct_fields_and_rebases_without_first_client`、stale-response race、undecryptable current保持、owned transaction commit/drop rollbackを含む。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`、bridge release build、`flutter analyze`、`flutter test`（124 passed / visual QA harness 1 skipped）、hardcoded-string check、`git diff --check`が成功。
- Verifier: 初回監査のACK/reconcile atomicity、remote HLC observe、status shape指摘を修正後、独立再検証PASS（実装上のP1/P2なし）。
- Commits: `d8d7561`、`7d41701`、`f4e2504`、`27e10a2`、`d9eb85d`、`2458795`、`3412c68`。
- 未解決: production CRUDはまだ全fieldを同一HLCでstampするため、changed-field clock、typed completion/placement、固定幅rank、production common-client 2-client gateは次taskで実装する。durable quarantine/cursor page transaction、full resync、aggregate delete scopeも後続であり、task-86単体を同期全体のrelease-readyとは扱わない。
