---
id: 019f6634-c19c-7863-b38f-4e77517b154d
title: Crypto integration audit and release gate
status: done
lane: critical
milestone: maintenance
---

# Crypto integration audit and release gate

## 1. 背景とコンテキスト

暗号primitive単体だけでなく、account、local storage、sync、rotation、Organization共有を横断した統合監査と明示的release gateが必要である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §4〜§7、§11
- `docs/05_設計判断記録.md` ADR-020
- 先行4 work itemの完了報告
- `SECURITY.md`

## 3. ゴール

公式vector、failure injection、3端末攻撃scenario、platform secret store、dependency / fuzz / secret scanを統合し、個人配布とOrganization公開のgateを判定可能にする。

## 4. スコープ

### やること

- RFC 9807、BIP39、FIPS 203 / 204 vectorを統合実行する。
- 3端末、offline / removal / crash / stale push / history / expired-device scenarioを通す。
- parser fuzz、`cargo audit`、dependency pin、secret grepをCI / runbookへ追加する。
- 実装担当と独立した暗号レビューを実施し、外部監査前の表示制約を固定する。
- 個人配布1〜3、Organization公開4のgateを文書とCIへ反映する。

### やらないこと

- 外部監査を実施済みとみなさない。
- `audited`表示を外部レビュー完了前に出さない。

## 5. 実装手順

1. test matrixと再現可能なcommandを固定する。
2. fuzz / audit / pin / secret scanをautomationへ追加する。
3. 全攻撃 / crash / platform scenarioを実行する。
4. 独立暗号レビューを取り込み、release gateを判定する。

## 6. 受け入れ基準

- 計画の全positive / negative / failure-injection testが合格する。
- `cargo audit`、依存固定、parser fuzz、秘密情報grepが合格する。
- Apple / Android実機結果とcross-build結果が記録される。
- 独立暗号レビューが合格し、外部監査未実施の表示制約が維持される。
- 共通品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- 実機、credential、外部監査など人間作業を自動test合格で代替しない。
- public報告へ秘密値やprivate監査詳細を含めない。

## 8. 完了報告に含めるべき内容

- 全test / fuzz / audit / platform matrix
- 独立レビュー指摘と解消
- 個人配布 / Organization公開gateの判定
- 外部監査まで残る人間作業

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-15
- 結果: 暗号依存のexact pin、root / fuzz双方のlock検証、RustSec audit、秘密値・秘密鍵artifact scan、parser fuzzをCIと公開runbookへ追加した。envelope v4、personal / Organization manifest、account root、device certificate / identity、hybrid DEK package、signed revocationの正規形式をfuzzごとに深部まで通し、変異inputも検査する。長さfieldは32-bit環境でもoverflowせずfail closedになる。
- 自動証拠: `cargo fmt --all -- --check`、fuzz crate fmt / locked check、`cargo clippy --workspace --all-targets --locked -- -D warnings`、`cargo test --workspace`、bridge release build、`flutter analyze`、Flutter 245 tests（visual QA harness 1件skip）、boundary / hardcoded-string checks、dependency pin / secret scan、`git diff --check`が成功した。
- 暗号証拠: `cargo audit --deny warnings`は1,160 advisory / 455 dependencyを検査して指摘0件。最新60秒fuzzは481,589 runs、coverage 1,493 / feature 2,596、crash / timeoutなし。RFC 9807、BIP39、FIPS 203 / 204、wrong password / AAD / generation / suite、rotation failure injection、3端末、server攻撃scenarioはworkspace testで成功した。
- Platform証拠: macOS実機gateは合格済み。JDK 21によるAndroid cross / release APKとiOS cross-buildは先行work itemで成功済みだが、iOS / Android接続実機runtime gateは未実施である。
- Commit: この完了報告を含むcommit
- 未解決: iOS / Android接続実機確認、Organization product-level E2E、外部暗号専門家reviewが必要である。それまではiOS / Android個人配布、Organization公開、一般release、`audited`表示を許可しない。

### 独立検証

- 判定: 合格
- 根拠: 実装を担当していないagentが統合差分をreviewし、parser深部未到達、32-bit length overflow、fuzz lock fail-open、secret scan false-negative、CIの`rg`依存を指摘した。全件修正後、残存P0 / P1 / P2なしを確認した。独立実行したtargeted clippy、Organization / manifest / envelope test、pin / secret script、fmt、diff checkが成功し、20秒fuzzは172,067 runs、coverage 1,456 / feature 2,557、crash / timeoutなしだった。
- 検証者: Work 5独立暗号gate review agent
