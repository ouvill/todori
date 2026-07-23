---
id: 019f8e32-ddb2-7731-995d-4829d55840b9
title: E2EE product foundations redesign
status: done
lane: critical
milestone: maintenance
---

# E2EE product foundations redesign

## 1. 背景とコンテキスト

Taskveilを一般リリース前のmainから再設計する。初期製品は、一般的な個人向けTODO機能と、家族・友人との小規模共有を提供するE2EEアプリとする。企業向け機能は将来の拡張を妨げない境界だけを考慮し、初期製品へは含めない。

本work itemは設計baselineの作成と、product owner承認後の公開正本文書への反映を扱う。既存実装、wire protocol、DB schemaとの互換性は前提にせず、実装変更は行わない。Product ownerは2026-07-23にbaselineの採用と継続作業を承認した。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/STATUS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/01_企画書.md`
- `docs/02_機能仕様書.md`
- `docs/03_技術仕様書.md`
- `docs/05_設計判断記録.md`
- `docs/tasks/task-14-public-private-repo-split.md`

## 3. ゴール

- 製品要件、脅威モデル、暗号と鍵管理、同期、共有を相互に矛盾しない一組の設計案として記録する。
- server-visible metadataと、E2EEで保護するdataを明示する。
- 標準化されたprimitiveと単純なkey hierarchyを選び、独自暗号protocolを避ける。
- Signal、Proton Drive、Standard Notes等の一次資料から、採用する設計と採用しない設計を区別する。
- 実装へ進む前に人間が承認または修正できるdecision pointを残す。

## 4. スコープ

### やること

- 一般的なTODO、完了履歴、stopwatch、Pomodoro、time tracking、local-first動作の製品要件
- 課金利用者のserver-side encrypted structured dataに対する約1 GiBの安全上限
- Proton Drive程度を目安にした脅威モデル
- password認証、recovery、account/device、鍵階層、署名、algorithm versioning
- opaque record store、offline mutation、競合、削除、quotaを含む同期モデル
- 新規memberの過去閲覧、owner移譲、role、server access control、除外時key rotation
- 除外時に旧dataを一括再暗号化せず、編集時にcurrent keyへ移すprogressive re-encryption
- server-visible metadata inventoryと明示的な非保証
- 承認後の`docs/01_企画書.md`、`docs/02_機能仕様書.md`、`docs/03_技術仕様書.md`、ADRへのbaseline反映

### やらないこと

- app、core、server、schema、protocolの実装
- 既存dataのmigrationまたは後方互換設計
- 添付file
- enterpriseのorganization、SSO、SCIM、admin recovery、監査、法的保全
- 課金価格、収益、法務、内部roadmapの詳細
- algorithm parameter、binary encoding、API endpointの実装可能な最終固定

## 5. 実装手順

本work itemに実装工程はない。設計工程は次の順で行う。

1. 既存の公開仕様と現在の前提を確認する。
2. 先行製品と標準仕様の一次資料を調査する。
3. 製品境界と用語を固定する。
4. 脅威モデルから鍵・署名・server metadata境界を導く。
5. 同期と共有のstate transitionを設計する。
6. 文書間の不変条件、scope、非保証、未決事項を照合する。
7. Product owner承認後、公開正本文書とADRをbaselineへ整合する。

## 6. 受け入れ基準

- [x] `docs/redesign/`に入口、製品要件、脅威モデル、暗号・鍵管理、同期、共有、先行調査がある。
- [x] 独自用語を最小化し、使用する用語を定義している。
- [x] title、note、status、due、reminder、recurrence、hierarchy、timer linkage等をserverが復号できない。
- [x] serverが知るaccount、membership、role、ciphertext size、traffic等を隠れる情報と混同せず列挙している。
- [x] new memberが過去dataを読める鍵配布を定義している。
- [x] member除外はserver revokeと新key generationを行い、旧dataのbulk re-encryptionを要求しない。
- [x] 旧recordを編集するとcurrent key generationで暗号化する。
- [x] owner移譲が単一owner不変条件を壊さない。
- [x] content AEADに加えてauthor signatureとmembership changeの署名を扱う。
- [x] 完了taskを通常は保持し、永久削除を例外操作とし、約1 GiB quotaの挙動を定義している。
- [x] 添付fileとenterprise機能を初期scopeへ含めていない。
- [x] Signal、Proton Drive、Standard Notesの採否理由を一次資料付きで記録している。
- [x] 実装fileを変更していない。
- [x] 公開正本文書が承認済みbaselineと矛盾しない。
- [x] ADRが旧判断の履歴を残しつつsupersede関係を明示している。
- [x] `git diff --check`が成功する。
- [x] Markdown内のlocal linkが存在する。
- [x] 統合した文書差分に対する独立security reviewが合格している。

## 7. 制約・注意事項

- 本設計案は人間承認後にのみ正本へ反映する。
- 暗号suite、wire encoding、KSF parameter、conflict test vectorは実装前の個別ADRとsecurity reviewで固定する。
- 「serverが読めない」と「serverが存在やaccess patternを知らない」を区別する。
- 共有相手が正当に復号したplaintextをcopyすることは防げない。
- 除外前にmemberが取得した旧dataを遠隔消去できるとは表現しない。
- public repoへprivateな課金、法務、内部roadmap詳細を置かない。

## 8. 完了報告に含めるべき内容

- 作成・変更した設計文書
- 主要な採用判断と、明示的に採用しなかったprotocol
- verification結果と未決事項
- 実装変更がないこと
- 人間承認および独立検証の状態

## 9. 完了報告

### 作業結果

- 作業日: 2026-07-23
- 結果: 承認済みredesign baselineを公開正本文書とADR-023へ反映し、旧実装資料をlegacyとして区別した。
- 証拠: `git diff --check`成功、変更・新規Markdown 29件の相対link確認成功、実装file変更なし。
- Commit: 未コミット
- 未解決: 暗号suite/encoding、同期merge、共有key lifecycle、local recovery、quotaを個別critical work itemで固定する。

### 独立検証

- 判定: 合格
- 根拠: 初回レビューのrecovery認可、malicious editor non-guarantee、Work Session cross-Space relation、metadata inventoryの4指摘を修正した。再レビューで判明したmembership manifest/transition historyのserver state・metadata不足も修正し、再々レビューでblocking findingなし。`git diff --check`、変更・新規Markdown 29件のlocal link、実装file変更なしを再確認した。
- 検証者: 作業を担当していないsub-agent `/root/independent_security_review`
