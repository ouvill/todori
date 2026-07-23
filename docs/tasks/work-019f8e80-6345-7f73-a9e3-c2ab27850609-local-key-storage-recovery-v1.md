---
id: 019f8e80-6345-7f73-a9e3-c2ab27850609
title: Local key storage and recovery v1
status: backlog
lane: critical
milestone: maintenance
---

# Local key storage and recovery v1

## 1. 背景とコンテキスト

ADR-023はAUK/ARK/Recovery Key/Device Local Wrapping Keyを分離した。OS secure storage、encrypted DB、cache、password change、recovery、irrecoverable resetをcross-platform contractへ固定する必要がある。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` §5、§6
- `docs/05_設計判断記録.md` ADR-023
- `docs/redesign/cryptography-and-key-management.md`
- `docs/redesign/threat-model.md`
- Crypto suite/encoding v1 work item

## 3. ゴール

- Local DB/key capsule/OS secure storageのv1 contractを定義する。
- Registration/login/password change/recovery/device revoke/resetをcrash-safeにする。
- Recovery UXが「supportにも復旧不能」というboundaryを正しく伝える。

## 4. スコープ

### やること

- DLWK/DB key/ARK cache lifecycle
- Apple Keychain/Android Keystore adapter contract
- Recovery Key encoding/checksum/export
- Password change/recovery/reset transaction
- App lock/biometric policy
- Secret lifetime/log/crash behavior

### やらないこと

- Production implementation
- Social/admin recovery
- Enterprise escrow
- Legacy capsule compatibility

## 5. 実装手順

1. Key/cache stateとfailure pointを列挙する。
2. Platform secure-store contractを定義する。
3. Recovery encoding/UXを比較・選定する。
4. Crash/restart/lost-device scenarioをmodel化する。
5. Platform/security reviewを行う。

## 6. 受け入れ基準

- [ ] Plaintext ARK/Space KeyをDBへ保存しない。
- [ ] Partial password/recovery updateでAccountをlock outしない。
- [ ] Recovery transitionがAccount ID、one-time challenge、new OPAQUE/wrapper digest、expected security revisionをAccount signatureへbindする。
- [ ] Serverがrecovery transitionをatomic CASし、challenge消費と既存session revokeを同じtransactionで行う。
- [ ] Key復元不能時にanonymous fallback mutationを作らない。
- [ ] Recovery Keyなしのresetが旧identityを装わない。
- [ ] Secret log/crash/clipboard policyが明示されている。
- [ ] Platform別failure/test matrixがある。
- [ ] Independent security reviewが合格している。

## 7. 制約・注意事項

- OS biometricをAccount recoveryの代わりにしない。
- Legacy namespace/capsuleをnew v1として再利用しない。
- Exact crypto bytesはcrypto suite/encoding v1へ依存する。

## 8. 完了報告に含めるべき内容

- Platform/key state contract
- Recovery encoding/UX decision
- Crash/failure matrix
- Security review結果
- Deferred implementation事項
