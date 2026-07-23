---
id: 019f8e80-624a-76d2-a5af-6d848921e114
title: Sharing membership and key lifecycle v1
status: backlog
lane: critical
milestone: maintenance
---

# Sharing membership and key lifecycle v1

## 1. 背景とコンテキスト

ADR-023はone-time secret invitation、historical keyring、owner/editor/viewer、removal rekey、owner transferを採用した。Server RBACとcryptographic transitionを一致させる実装可能なstate machineが必要である。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` §8
- `docs/05_設計判断記録.md` ADR-023
- `docs/redesign/sharing-model.md`
- `docs/redesign/threat-model.md`
- Crypto suite/encoding v1 work item
- Record CAS/merge protocol v1 work item

## 3. ゴール

- Invitation、add、role change、remove、leave、owner transfer、identity reset、Space deleteを完全なstate machineとして固定する。
- New member historical accessとremoved member new-content exclusionをtest可能にする。
- Server/key-substitution、concurrency、offline ownerの限界を明示する。

## 4. スコープ

### やること

- Signed membership manifest grammar
- Invitation secret packages/acceptance
- Historical keyring envelope
- Atomic removal/new generation
- Progressive re-encryption trigger
- Leave write-freeze
- Dual-signature owner transfer
- Identity rotation/reset

### やらないこと

- Production implementation
- Anonymous membership/private contact discovery
- Enterprise admin/SSO/SCIM
- MLS/Double Ratchet/key transparency独自実装

## 5. 実装手順

1. Actors/state/transitionを列挙する。
2. Message、signature、expected revisionを定義する。
3. Server transactionとclient validationを対応させる。
4. Concurrency/offline/malicious server scenarioをmodel化する。
5. UX confirmationとnon-guarantee copyをreviewする。

## 6. 受け入れ基準

- [ ] Shared Spaceに常にexactly one ownerがいる。
- [ ] New memberが全historical generationを受け取る。
- [ ] Removal transaction失敗時にpartial membership/key stateがない。
- [ ] Removed memberへnew keyを配らない。
- [ ] Old Record editがcurrent generationになる。
- [ ] Owner transferにtarget acceptanceが必要である。
- [ ] Editorの改変/permanent-delete権限を招待・role UXで明示し、意図的破壊をsecurity guaranteeに含めない。
- [ ] Membership manifest/transition historyのdigest/signature/key-envelope-set binding、retention、quota、server-visible metadataが一致する。
- [ ] Model/state-machine/security reviewが合格している。

## 7. 制約・注意事項

- Removed memberのpast plaintext remote eraseを保証しない。
- Server-visible membership/roleを隠すための匿名credentialを追加しない。
- Invitation exact bytesはcrypto suite/encoding v1へ依存する。

## 8. 完了報告に含めるべき内容

- State/message/transaction specification
- Model test scenarios
- UX/non-guarantee review
- Independent security review
- Deferred implementation事項
