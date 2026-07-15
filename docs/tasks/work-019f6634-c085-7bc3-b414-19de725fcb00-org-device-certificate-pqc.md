---
id: 019f6634-c085-7bc3-b414-19de725fcb00
title: Organization device certificates and hybrid PQC sharing
status: complete
lane: critical
milestone: maintenance
---

# Organization device certificates and hybrid PQC sharing

## 1. 背景とコンテキスト

server侵害を脅威に含めるOrganization共有には、server提供公開鍵の真正性、端末別失効、harvest-now-decrypt-later耐性が必要である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §4.6
- `docs/05_設計判断記録.md` ADR-020
- account / device / membership / key bundle実装

## 3. ゴール

account root、認証済みdevice certificate、Safety number、Ed25519 + ML-DSA-65署名、X25519 + ML-KEM-768の端末別DEK配送を実装する。

## 4. スコープ

### やること

- review済み固定`aws-lc-rs`でFIPS 203 / 204 primitiveを導入する。
- account rootとdevice signing / hybrid KEM key、proof-of-possession、失効を実装する。
- Safety number / QRを別経路確認するまで共有を`unverified`に保ち、DEK配送しない。
- hybrid transcriptをHKDF-SHA384へ束縛し、残存各deviceへ個別wrapする。
- public-key substitution、certificate改変、recipient追加、replayのnegative testを追加する。

### やらないこと

- strict mode、key transparency log、PQC TLSを実装しない。
- 除名前に取得済みの旧dataを遠隔消去できるとは表現しない。

## 5. 実装手順

1. dependency pin、cross-build / size budgetを固定する。
2. root / device key type、certificate、PoPを実装する。
3. Safety number確認stateとUI / API gateを実装する。
4. per-device hybrid KEM deliveryとrotation連携を実装する。
5. FIPS vector、攻撃server、cross-build testを通す。

## 6. 受け入れ基準

- unsigned / revoked / unknown-suite device keyをclientが拒否する。
- Safety number未確認とroot変更後はList / Tenant DEKを配送しない。
- X25519とML-KEM-768双方、scope、generation、recipient fingerprintをtranscriptへ認証する。
- iOS / Android / macOS cross-buildとbinary sizeを記録する。
- 共通品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- Organization機能は本work item完了まで公開しない。
- AWS-LC versionはCargo.lockだけでなくmanifestで正確に固定する。
- root秘密鍵はMK wrap、device秘密鍵は端末secret store外へ出さない。

## 8. 完了報告に含めるべき内容

- certificate / Safety number / hybrid transcript契約
- FIPS vectorとmalicious-server test
- platform build / binary size
- Organization公開gateの状態

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-15
- 結果: account rootへEd25519 + ML-DSA-65、deviceへEd25519署名鍵とX25519 + ML-KEM-768 KEM鍵を導入した。root署名device certificate、server challengeへのPoP、hybrid署名した連鎖型失効statement、Safety number / raw QRの別経路確認、root変更時の再確認、verified deviceごとのDEK配送を実装した。Organization manifestは両root署名とrecipient集合を認証し、clientはgeneration、active status、scope、現在deviceのrecipient membership、両verified rosterとのrecipient集合完全一致を検証する。
- 暗号契約: `aws-lc-rs = 1.17.1`をmanifestで固定し、FIPS 203 / 204のML-KEM-768 / ML-DSA-65を使用する。X25519とML-KEM shared secretは、両device公開鍵、両ciphertext、scope kind / ID、generation、recipient key fingerprintを含むtranscriptへ束縛し、HKDF-SHA384でXChaCha20-Poly1305 wrapping keyを導出する。certificate fingerprintはcanonical signed payloadのSHA-384、recipient key fingerprintはhybrid KEM公開鍵のSHA-256として分離した。
- 攻撃server対策: unsigned / expired / revoked / unknown-suite certificate、certificate改変、PoP改変、root差し替え、Safetyとroster取得間のroot差し替え、revocation omission / fork、generation replay、recipient追加、signed manifestにないrecipient package、Safety number未確認時の配送を拒否するtestを追加した。確認済みroot、roster revision / chain head、generationをSQLCipherへ単調pinし、roster更新後は次generationが成立するまでfail closedとする。device失効は対象accountが所属する全Organizationを同一transactionでrotation-requiredにする。member / device除名前に取得済みの旧dataを遠隔消去できるとは表現しない。
- 証拠: `cargo test -p todori-sync` 77件、client trust-pin 1件、Docker Organization認証統合1件、crypto Organization 7件が合格した。AWS-LC providerのACVP由来ML-KEM / ML-DSA known-answer self-testと実primitive roundtripが合格した。`cargo clippy --workspace --all-targets -- -D warnings`、`flutter analyze`、Flutter全245 testが合格し、Safety numberはout-of-band確認checkboxを選ぶまでconfirm不可、QRはversion byte + SHA-384 digestのraw 49 bytesを符号化する。
- Platform / size: `cargo check`は`aarch64-apple-ios`、`aarch64-apple-ios-sim`、Android `arm64-v8a`で合格した。release buildはmacOS app 112,644 KiB（bridge framework 56,556 KiB）、iOS Runner.app 51,448 KiB（arm64 bridge 25,476 KiB）、Android universal APK 103,395,898 bytes、split APKはarmeabi-v7a 31,099,854 bytes / arm64-v8a 38,116,870 bytes / x86_64 41,103,330 bytesだった。AndroidはJDK 21を使用した。
- Commit: この完了報告を含むcommit
- 未解決: Apple / Android接続実機でのdevice identity secret-store、再起動、root / device key再openはWork 5で確認する。外部暗号レビューとOrganizationのproduct-level multi-tenant flowは未完了のため、Organization公開gateと`audited`表示は閉じたままとする。

### 独立検証

- 判定: PASS（残存P0 / P1 / P2なし）
- 根拠: 実装を担当していない検証者が、Safety rootのlocal pin、roster chain、recipient集合完全一致、generation fail-closed、TDR1 continuity、全Organizationのrotation-requiredを確認した。`cargo fmt --all -- --check`、`git diff --check`、全target clippy、sync 77件、client trust-pin、Docker server統合、crypto Organization 7件を独立再実行して合格した。
- 検証者: 独立Codex review session `/root/work4_crypto_verify`
