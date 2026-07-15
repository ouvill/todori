---
id: 019f6634-bf84-75b1-8e41-0024a9b218c9
title: Crash-safe Device Key rotation and Android Keystore
status: backlog
lane: critical
milestone: P2-M5
---

# Crash-safe Device Key rotation and Android Keystore

## 1. 背景とコンテキスト

Device Keyはgenerationを持たず、SQLCipher rekeyのcrash recovery契約とAndroid本番Keystoreが未実装である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §4.3、§5.3
- `docs/05_設計判断記録.md` ADR-020
- `core/storage/`
- `core/client/`
- `app/rust/`

## 3. ゴール

OS secret storeにactive / pending capsuleを持たせ、SQLCipher rekeyをcrash-safeに完了し、Androidでnon-exportable AES-256-GCM Keystore sealingを使用する。

## 4. スコープ

### やること

- DK generationとDK-wrapped MKを一体化したversioned capsuleを導入する。
- pending保存、`PRAGMA rekey`、再open検証、active昇格、旧capsule削除を実装する。
- 起動時のpending専用rollback / commit recoveryを実装する。
- Android Keystore本番storeを実装し、本番平文`device.key`を拒否する。
- Apple実機runbookとplatform testを更新する。

### やらないこと

- 通常時のactive / pending互換fallbackを提供しない。
- OSからexport可能なAndroid master keyを保存しない。

## 5. 実装手順

1. capsule formatとsecret-store APIをversioned化する。
2. transactional rekey coordinatorとfailure injectionを追加する。
3. Android Keystore bridgeとproduction gateを実装する。
4. Apple / Android実機runbookと自動testを整備する。

## 6. 受け入れ基準

- crash位置ごとに再起動後activeまたはpendingの一方へ収束する。
- pendingはcrash recovery時だけ試され、通常fallbackにならない。
- Android本番buildは平文storeで起動せず、Keystore AES-256-GCM鍵は非exportableである。
- Apple実機でrotation、再起動、DB reopen、Keychainゼロプロンプトを確認する。
- 共通品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- secret、SQLCipher key、capsule plaintextをlogへ出さない。
- 開発 / test用file storeとproduction storeを型・build設定で分離する。

## 8. 完了報告に含めるべき内容

- capsule / rekey / recovery state transition
- failure injection結果
- Android / Apple実機証拠と未実施platform
- production file-store拒否の証拠
