---
id: 019f6634-be4c-7240-8c46-fbc81935fc36
title: Versioned key generation and rotation
status: backlog
lane: critical
milestone: maintenance
---

# Versioned key generation and rotation

## 1. 背景とコンテキスト

現行のgeneration 0固定bundleとenvelope v3には、失効・侵害・algorithm移行時のfail-closed rotation契約がない。ADR-020の状態機械をclient / server / wireへ実装する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §4、§6
- `docs/05_設計判断記録.md` ADR-020
- `core/sync/`
- `core/storage/`
- `server/migrations/`、`server/src/sync.rs`

## 3. ゴール

versioned key schema、signed manifest、envelope v4、`prepared -> active -> migrating -> retired` coordinatorを実装し、旧generationでのlive writeをfail closedにする。

## 4. スコープ

### やること

- user / tenant / list key generationとrecipient tableを追加する。個人scope manifestはMK由来manifest-auth keyによるHMAC-SHA256で認証し、Organization root署名manifestはOrganization共有work itemで追加する。
- envelope v4へsuite IDとkey generationを埋め、AADへtenant / collection / record / suite / generationを束縛する。
- active / minimum-write generation、migration、continuity ACK、30日historyを実装する。
- password / Recovery wrapper revision、MK rewrap、Tenant / List DEK re-encryptionを区別する。
- crash / stale push / offline / removalの統合testを追加する。

### やらないこと

- generation 0、envelope v3、旧schemaの互換経路を残さない。
- 端末secret store rekeyとOrganization PQ配送は後続で扱う。

## 5. 実装手順

1. schemaと型付きmanifest / statusを追加する。
2. envelope v4 parser / AADを実装する。
3. server write gateとclient manifest gateを実装する。
4. rotation coordinatorとmigration / ACK / retirementを実装する。
5. failure injectionと3端末統合testを通す。

## 6. 受け入れ基準

- active未満のlive push、unknown suite / generation、manifest replayを拒否する。
- tombstoneは再暗号化せず、全live headと非expired端末ACKと30日経過まで旧bundleを削除しない。
- offline端末は更新取得まで対象scopeへ書き込めない。
- 各rotation境界のcrash後に旧世代か新世代の一方へ収束する。
- 共通品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- 定期的な全データ再暗号化は行わない。
- MK rotationは子鍵rewrapだけ、Tenant / List DEK rotationだけがcontent再暗号化を行う。
- serverは暗号plaintextを解釈しない。

## 8. 完了報告に含めるべき内容

- schema / wire / state transition契約
- failure injectionと3端末test結果
- history / retirement / fail-closedの証拠
- migrationと互換層がないこと
