---
id: 019f8e80-603d-7f30-a949-f0e89b35fecd
title: Crypto suite and canonical encoding v1
status: backlog
lane: critical
milestone: maintenance
---

# Crypto suite and canonical encoding v1

## 1. 背景とコンテキスト

ADR-023はOPAQUE、HPKE、Ed25519、HKDF、AEAD、deterministic encodingのprotocol familyを採用したが、exact ciphersuite、parameter、library、binary contractは未固定である。実装前にinteroperableなv1をtest vector付きで確定する。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md`
- `docs/05_設計判断記録.md` ADR-023
- `docs/redesign/cryptography-and-key-management.md`
- `docs/redesign/threat-model.md`
- `docs/redesign/prior-art.md`

## 3. ゴール

- OPAQUE ciphersuite/KSF、AEAD、HKDF、HPKE、signature、hash、random、canonical encodingを1つのversioned suiteとして固定する。
- Account/key/Record/invitation/membership objectのdomain separation、AAD、signature inputをbyte-levelで定義する。
- Official vectorとTaskveil vector、negative vectorを作る。

## 4. スコープ

### やること

- Maintained library、license、audit、platform support調査
- Low-end mobileでのArgon2id benchmark plan
- Nonce/ID/randomness contract
- Deterministic CBOR profileとsize/padding候補
- Version/suite negotiationとdowngrade拒否
- Protocol document、test vector format、security review checklist

### やらないこと

- Production implementation
- PQC hybridの独自追加
- Legacy `TWK1` compatibility
- Sharing/sync state machine

## 5. 実装手順

1. Standard/RFCと候補libraryを比較する。
2. Exact suiteとencoding profileを提案する。
3. Byte-level object grammarとdomain labelsを定義する。
4. Positive/negative vectorを作る。
5. Cross-platform実装可能性とDoS/sizeをreviewする。

## 6. 受け入れ基準

- [ ] Exact algorithm/parameter/library候補と採否理由がある。
- [ ] Canonical bytes、AAD、signature input、domain labelsが曖昧でない。
- [ ] Unknown/downgrade/fallback拒否が定義されている。
- [ ] Official/Taskveil/negative vectorが機械可読である。
- [ ] OPAQUE mobile benchmark条件が再現可能である。
- [ ] Independent cryptographic reviewが合格している。

## 7. 制約・注意事項

- RFC 9807/9180/8032等のstandard primitiveを変形しない。
- HPKE Base modeのsender authenticationをowner signatureで補う境界を混同しない。
- Legacy implementationをnew v1へ見せるcompatibility aliasを作らない。

## 8. 完了報告に含めるべき内容

- Suite/encoding decision
- Library/platform/benchmark evidence
- Vector locationとverification command
- Independent review結果
- Deferred migration/implementation事項
