---
id: 019f8e80-615d-7b70-b472-f3b38e4428c8
title: Record CAS merge and Tombstone protocol v1
status: backlog
lane: critical
milestone: maintenance
---

# Record CAS merge and Tombstone protocol v1

## 1. 背景とコンテキスト

ADR-023はopaque current head、base revision CAS、typed 3-way merge、Conflict Record、permanent Tombstoneを採用した。Wire/API/local transaction/full resyncを実装可能なstate machineとvectorへ固定する必要がある。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` §7
- `docs/05_設計判断記録.md` ADR-023
- `docs/redesign/sync-model.md`
- Crypto suite/encoding v1 work item

## 3. ゴール

- Record/batch/pull/full-resync protocolをbyte/API/state-machine levelで定義する。
- Typed 3-way merge ruleを全initial Record kindに対して固定する。
- Quota、CAS、Tombstone、dependency、failure injectionでdataを失わないことをmodel testで示す。

## 4. スコープ

### やること

- Server head/delta/idempotency transaction
- Local state/outbox/base snapshot transaction
- Normal sync/full resync
- Typed merge/Conflict Record
- Completion atomic batch
- Permanent Tombstone/referential cascade
- Old-generation rebase hook

### やらないこと

- Production implementation
- Membership/invitation lifecycle
- Bounded Tombstone GC/device expiry
- Cross-Space distributed transaction

## 5. 実装手順

1. Stateとmessageを列挙する。
2. Server/client transitionとinvariantを定義する。
3. Record kind別merge tableを作る。
4. Failure/retry/full-resync scenarioをmodel化する。
5. API/vector/test planを独立reviewする。

## 6. 受け入れ基準

- [ ] CAS/idempotency/cursor/quota transactionが曖昧でない。
- [ ] Same-field conflictの両candidateが保持される。
- [ ] Complete + Completion Recordがall-or-nothingである。
- [ ] Tombstoneからliveへ戻らない。
- [ ] Personal Work SessionのShared Task soft external referenceをstructural relation/cascadeから区別する。
- [ ] Never-synced local dataをfull resyncで黙って失わない。
- [ ] Model/property/failure test planがある。
- [ ] Independent sync correctness reviewが合格している。

## 7. 制約・注意事項

- Server plaintext merge、arbitrary field clock、blind re-pushを導入しない。
- TombstoneはSpace存続中保持するbaselineを変えない。
- Crypto bytesはcrypto-suite work itemのoutputへ依存する。

## 8. 完了報告に含めるべき内容

- Protocol/state diagrams
- Merge matrix
- API/vector/test plan
- Failure scenariosと判定
- Independent review結果
