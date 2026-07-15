---
id: 019f6634-c085-7bc3-b414-19de725fcb00
title: Organization device certificates and hybrid PQC sharing
status: backlog
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
