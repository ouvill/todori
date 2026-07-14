---
id: 019f621c-5a25-73b2-a4a6-1794d30d706c
title: Foreground realtime integration and observability
status: backlog
lane: critical
milestone: maintenance
---

# Foreground realtime integration and observability

## 1. 背景とコンテキスト

Worker、server、clientは個別testだけではHMAC byte contract、source除外、provider outage、scheduler収束の接続不良を見逃し得る。production deployなしでcross-layer contractを固定し、残る人間作業を明示する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §6.7
- `docs/05_設計判断記録.md` ADR-019
- 先行3 work itemと完了報告
- `docs/dev/two-device-sync-test.md`

## 3. ゴール

共通fixtureとlocal runtime testにより、local mutationからremote sync開始までのnotification chain、provider failure時のfallback、秘密情報を持たないobservabilityを再現可能に検証する。

## 4. スコープ

### やること

- Rust / TypeScript共通HMAC fixtureとcross-language検証を追加する。
- local Workerで2接続、source除外、remote fan-out、duplicate、expiry、hibernation evictionを検証する。
- server publish failureとFlutter socket failureを含むdegraded pathを検証する。
- ticket / publish / connection / sync triggerのsecret-safe structured eventを追加・監査する。
- fake clockでlocal mutationからremote sync開始まで2秒未満を確認する。

### やらないこと

- 実Cloudflare、AWS、Neon、iOS / Android実機へdeployしない。
- production latency、費用、jurisdictionをlocal testで確認済みと扱わない。
- realtimeをrelease gateや同期correctness条件へ昇格しない。

## 5. 実装手順

1. ADR-019の固定JSON field順、UTF-8、base64url no-padding、domain separator、header / raw bodyを1つのbyte contract fixtureとしてRust / TypeScript双方で検証する。
2. local Worker WebSocket harnessでfan-out / expiry / evictionを実行する。
3. fake publisher / socket / clockでtimeout、disconnect、resume、poll fallbackを接続する。
4. structured eventのfield allowlistをtestし、識別子・secret漏洩を監査する。
5. 全repository品質ゲートとWorker CI相当commandを統合HEADで実行する。
6. 統合HEADを独立検証する。

## 6. 受け入れ基準

- Rustが生成したticket / publish signatureをTypeScriptが検証し、逆方向fixtureも一致する。
- source socketへechoせずremote socketだけがfixed hintを受ける。
- duplicate / out-of-order hintは同期結果を変えず、coalesced runだけを起動する。
- Worker / publish停止中もlocal mutationが成功し、30秒fallbackとresume syncで回復する。
- deterministic local testでmutation commitからremote sync開始まで2秒未満である。
- structured eventにsecret、ticket、tenant / device / opaque identifier、record metadataがない。
- 全品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- 実network SLOは本番deploy後の人間確認として残す。
- test secretはfixture専用の公開値と明記し、production secret形式と混同しない。
- flakyなwall-clock sleepに依存せずfake clockまたはbounded local timeoutを使う。
- 先行work itemの契約変更が必要ならADR-019へ戻り、場当たり的compatibilityを追加しない。

## 8. 完了報告に含めるべき内容

- cross-language fixture、local Worker、degraded pathの結果
- latency観測値と測定条件
- structured event field監査
- 本番deploy / credential / jurisdiction / 費用確認の残件
