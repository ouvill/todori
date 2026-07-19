---
id: 019f6634-bd37-7d63-9f67-87ef9730afbb
title: Crypto baseline hardening
status: done
lane: critical
milestone: maintenance
---

# Crypto baseline hardening

## 1. 背景とコンテキスト

一般配布前に、RFC 9807準拠OPAQUE、強度を固定したArgon2id、標準Recovery Key、用途・主体・suite・世代へ束縛したkey wrap、秘密鍵memoryのzeroizeを確立する。既存開発accountと旧wireの互換性は残さない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §4、§7、§11
- `docs/05_設計判断記録.md` ADR-020
- `core/crypto/src/lib.rs`
- `core/sync/src/lib.rs`
- `server/src/auth.rs`

## 3. ゴール

暗号suite v2を一意に識別し、RFC 9807 OPAQUE、Argon2id 64 MiB / t=3 / p=4、BIP39 24語Recovery、Taskveil key-wrap v1 AAD、zeroizing秘密鍵containerをproduction経路へ適用する。

## 4. スコープ

### やること

- ADR-020を確定し、技術仕様・運用ガイド・SECURITYを同期する。
- `opaque-ke >= 4.0.1`へ更新し、OPAQUE suite IDとdowngrade拒否を実装する。
- Recovery KeyをBIP39 English 24語・256-bit entropy・checksum・NFKDへ置換する。
- password / recovery / local MK / tenant / list wrapをv2 AADへ移行する。
- `LocalSyncKeys.list_deks`を含む平文鍵containerを`Zeroizing`化し、不要なcopyを除去する。
- 登録時に秘密鍵を保持しない`device_public_key`生成を削除する。

### やらないこと

- 旧OPAQUE、旧Recovery、wrap v1のreader / writerを残さない。
- record envelope、server key-generation schema、DK rekey、Organization共有は後続work itemで扱う。

## 5. 実装手順

1. suite ID、domain separator、Argon2 parameterを1か所に固定する。
2. OPAQUE client / server stateと保存recordへsuite IDを束縛する。
3. BIP39 entropyからRecovery wrap keyを導出し、checksum / Unicode異常を拒否する。
4. typed wrap contextを導入し、全call siteをbreaking更新する。
5. secret containerとtest vectorを更新し、旧形式拒否を確認する。

## 6. 受け入れ基準

- RFC 9807 compatible suiteだけがregistration / loginを完了し、unknown / old suiteはserverとclientで拒否される。
- Argon2idが64 MiB、3 iteration、4 laneで固定される。
- Recoveryは24語・256-bit entropy・checksum・NFKDで、phrase文字列ではなくentropyをHKDFへ渡す。
- wrong password、wrong checksum、wrong AAD、wrong suiteのnegative testが通る。
- production秘密鍵containerがdrop時にzeroizeされ、未使用device public keyが消える。
- 共通品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- XChaCha20-Poly1305、HKDF-SHA256、SQLCipherは維持する。
- `docs/01_企画書.md`と`docs/02_機能仕様書.md`は変更しない。
- secret、phrase、鍵、OPAQUE中間値をlog・fixture・完了報告へ出さない。

## 8. 完了報告に含めるべき内容

- 固定suite / Argon2 / Recovery / AAD契約
- dependency versionとvector / negative test結果
- 互換reader / fallbackがないこと
- 独立検証結果と後続work itemへの境界

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-15
- 結果: suite ID `0x0002`、OPAQUE `Ristretto255 + 3DH + Argon2id (64 MiB / t=3 / p=4)`、BIP39 English 24語Recovery、固定長Taskveil wrap v1 AAD、generation 1のaccount bundle、zeroizing秘密鍵containerをproduction経路へ適用した。OPAQUE state・account bundleはsuiteとgenerationを保存・照合し、unknown / old suite、generation 0、必須scopeのnil UUIDを拒否する。pre-Taskveil OPAQUE / Recovery / wrap contract、未使用`device_public_key`のreader / writer / fallbackは残していない。
- 証拠: RFC 9807 Appendix C.1.1 registration vector、BIP39 all-zero entropy vector、Taskveil wrap v1 63-byte golden vector、wrong password / checksum / AAD / suite / generation / scopeのnegative testを含む`cargo test --workspace`が合格した。`opaque-ke 4.0.1`、`bip39 2.2.2`（`zeroize` feature）をlockした。
- Commit: この完了報告を含むcommit
- 未解決: record envelope、server key-generation schema、rotation coordinatorは後続`work-019f6634-be4c-7240-8c46-fbc81935fc36`で扱う。DK rotation / Android Keystore、Organization hybrid PQC共有、最終統合監査もそれぞれ後続work itemで扱う。

### 独立検証

- 判定: 合格
- 根拠: 初回検証でgeneration 0・nil ID受入れ、suite定数重複、公式vector不足、Recovery phraseのzeroize不足、AAD golden vector不足、古い説明を指摘。すべて修正後、別エージェントが`git diff --check`、`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、crypto / sync / auth test、dependency feature treeを再確認し、P0〜P2の残存指摘なしと判定した。実装側でも`cargo test --workspace`、client boundary checks、`docs/01`・`docs/02`無変更を再確認した。
- 検証者: 実装を担当していない独立検証エージェント
