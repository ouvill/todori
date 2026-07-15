---
id: 019f6634-be4c-7240-8c46-fbc81935fc36
title: Versioned key generation and rotation
status: done
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

## 9. 完了報告

- 結果: envelope v4（suite / generation / tenant / collection / record AAD）、versioned user / tenant / list schema、MK由来HMAC manifest、`prepared -> active -> migrating -> retired` coordinatorを実装した。serverはminimum write generation未満のlive pushと重複rotationを拒否し、tombstoneは暗号blobを持たない。
- migration: clientはactive bundleとmigrating中の旧Tenant / List DEKを認証・保持し、envelope headerのgenerationで復号鍵を選ぶ。旧generationのremote live headもpull後にactive generationへ再暗号化してCAS repushする。local backfill、record state、outbox、pending rotation markerは同一SQLite transactionで確定し、key cache切替完了まで通常mutationをfail closedにする。
- manifest / replay: serverは旧active hashを指すpreparedと、そのhashを指す新activeをactivation transactionで検証・保存する。clientはscope別の最終認証済みmanifestをSQLCipher settingsへ永続化し、HMACとsuccessor chainの両方を検証してreplay / fork / downgradeを拒否する。
- retirement: 全live head移行、全非expired device ACK、migration完了から30日経過まで旧bundleを保持する。device expiryはowner APIで明示し、offlineやsession expiryだけでは除外しない。password変更 / Recovery再発行はMKを変えずwrapper revision CASだけを進める。
- scope: serverへtask-to-list linkageを開示しないためwire write generationはtenant同期epochとし、List単独rotationでは対象List DEKだけを変更、他List DEKは同素材を新epochへrewrapする。
- breaking境界: envelope v3、generation 0、旧key schemaのreader / writer / fallbackは追加していない。既存開発DBは再作成する。
- test: `cargo fmt --all -- --check` PASS、`cargo clippy --workspace -- -D warnings` PASS、`cargo test --workspace` PASS（sync 74件、storage 89件、server PostgreSQL統合testを含む。手動platform test 2件は既定どおりignored）。初回に検出したmanifest認証鍵fixtureとgeneration列fixtureの不一致をproduction契約へ修正し、全体を再実行した。
- 独立検証: 別agentがhistorical remote migration、manifest anchor / chain、pending marker、rotation overlap、ACK / retention / expiry、wrapper CAS、互換fallback不在を再検証し、P0 / P1 / P2なしでPASSと判定した。
