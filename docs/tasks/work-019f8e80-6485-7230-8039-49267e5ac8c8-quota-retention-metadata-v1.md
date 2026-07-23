---
id: 019f8e80-6485-7230-8039-49267e5ac8c8
title: Quota retention and metadata contract v1
status: backlog
lane: critical
milestone: maintenance
---

# Quota retention and metadata contract v1

## 1. 背景とコンテキスト

ADR-023は約1 GiBのpaid-account safety ceiling、completed data保持、permanent Tombstone、server-visible metadata inventoryを採用した。Quota accounting、retention、privacy、backup deletionを実装可能なpublic contractへ固定する必要がある。

## 2. 事前に読むべきファイル

- `docs/01_企画書.md` §7
- `docs/03_技術仕様書.md` §10、§11
- `docs/redesign/product-requirements.md`
- `docs/redesign/threat-model.md`
- `docs/billing_overview.md`
- Record CAS/merge protocol v1 work item

## 3. ゴール

- Stored-byte accounting、Shared Space owner attribution、batch quota checkを定義する。
- Quota/subscription failureでlocal dataを失わないbehaviorを固定する。
- Server-visible metadata、log、backup、logical deletionのpublic inventory/SLA案を作る。

## 4. スコープ

### やること

- Ciphertext/signature/key/Tombstone accounting
- Owner transfer時quota attribution
- Warning/exceeded/storage-reducing mutation
- Completed/Tombstone/revision retention
- Metadata/log/push inventory
- Backup/logical deletion SLAの公開案

### やらないこと

- Concrete price/revenue/private contract
- Attachment quota
- Legal hold/enterprise retention
- Production implementation

## 5. 実装手順

1. Stored objectとbyte accountingを列挙する。
2. Quota transaction/failure behaviorを定義する。
3. Metadata/log/backup data flowをinventory化する。
4. Privacy/product/operations reviewを行う。
5. Test/observability planを作る。

## 6. 受け入れ基準

- [ ] 同じShared Space bytesを二重計上しない。
- [ ] Batchを部分受理しない。
- [ ] Quota超過でもpull/read/edit/delete/exportを許可する。
- [ ] Completed dataを自動purgeしない。
- [ ] Tombstone/revision/backup retentionが明示されている。
- [ ] Server-visible metadataとnon-visible dataがschema/logと一致する。
- [ ] Wrapped key material、security transition、base revision、delta/idempotency、push metadataをinventoryから漏らさない。
- [ ] Signed membership transition historyとinvitation metadataのretention/bytesをschemaとinventoryへ対応させる。
- [ ] Public/private境界reviewが合格している。

## 7. 制約・注意事項

- Concrete pricing、cost、contract、revenueをpublic repoへ置かない。
- E2EEをbackup retentionやlogical deletionの代わりにしない。
- 約1 GiBはsafety ceiling目安であり常時UI meterを要求しない。

## 8. 完了報告に含めるべき内容

- Accounting/retention/metadata contract
- Privacy/operations review
- Test/observability plan
- Public/private split
- Deferred implementation事項
