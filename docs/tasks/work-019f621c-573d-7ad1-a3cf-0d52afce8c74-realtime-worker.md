---
id: 019f621c-573d-7ad1-a3cf-0d52afce8c74
title: Foreground realtime Cloudflare Worker
status: active
lane: critical
milestone: maintenance
---

# Foreground realtime Cloudflare Worker

## 1. 背景とコンテキスト

ADR-019はCloudflare Worker + tenant単位Durable Objectを、同期の正本ではないforeground wake-up hint providerとして採用した。本work itemはprovider境界だけを実装し、Postgres / HTTPS同期へcorrectness責務を追加しない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §6.7
- `docs/05_設計判断記録.md` ADR-019
- `docs/09_運用ガイド.md` §5.1

## 3. ゴール

EU jurisdictionのDurable Objectへ認証済みWebSocketを接続し、serverの署名済みpublishだけから固定change hintを期限内のremote deviceへfan-outできるWorkerを、local testとCIで再現可能にする。

## 4. スコープ

### やること

- `realtime-worker/`へTypeScript module Worker、Durable Object、Wrangler / Vitest設定を追加する。
- `GET /v1/connect`のUpgrade ticket検証と`POST /v1/publish`の署名検証を実装する。
- `jurisdiction("eu").getByName(channel)`、Hibernation attachment、source device除外、expiry closeを実装する。
- 1 opaque device tagにつき最新1接続、1 tenantにつき128接続上限、client application message拒否を実装する。
- Node 24.18.0、Wrangler 4.110.0、Vitest 4.1.9、`@cloudflare/vitest-pool-workers` 0.18.2、TypeScript 6.0.3をexact pinする。

### やらないこと

- Cloudflare account/resource作成、secret投入、preview / production deployを行わない。
- Workerへtenant / device UUID、session token、暗号blob、sync cursor、delivery queueを持たせない。
- WebSocket frameでrecordを配送しない。

## 5. 実装手順

1. ADR-019で固定したfield順、UTF-8、base64url no-padding、domain separator、headerをそのまま使うHMAC ticket / publish shared fixtureを定義する。
2. Worker routeでbody上限、key ID、signature、timestamp、ticket audience / expiryを検証する。
3. Durable Objectへopaque channelだけでrouteし、connection attachmentをhibernation後も復元する。
4. `{"v":1,"type":"changed"}`だけをfan-outし、source / expired socketを除外する。
5. Node CI jobへ`npm ci`、typecheck、Vitest、Wrangler dry-run buildを追加する。
6. 統合HEADを独立検証する。

## 6. 受け入れ基準

- invalid / unknown key、tampered ticket、expired ticket、不正audience、±30秒外publish、過大bodyが拒否される。
- ticketが`<payload>.<signature>`の2 segmentで、payloadが`kid` / `aud` / `channel` / `device` / `iat` / `exp`だけを固定順で持ち、publishが固定3 headerと512-byte以下のraw body署名を使う。
- valid publishがremote socketだけへ固定frameを送り、duplicate publishはduplicate hintに留まる。
- 同device再接続で旧socketが閉じ、129件目のtenant接続が拒否される。
- Durable Object eviction / hibernation後もexpiryとdevice tagが復元される。
- logとresponseへsecret、ticket、opaque identifier、tenant / device UUIDを出さない。
- Worker CIとrepository共通品質ゲート、独立検証が合格する。

## 7. 制約・注意事項

- HMAC-SHA256はWeb Cryptoを使い、独自暗号primitiveを実装しない。
- ticket keyとpublish keyを混用しない。current / previous key ID以外を受理しない。
- Worker停止は同期遅延であり、delivery保証を追加しない。
- npm依存はexact versionとlockfileで固定する。

## 8. 完了報告に含めるべき内容

- route / Durable Object / HMAC / attachment実装の概要
- pinしたNode / npm依存とCI command
- invalid、expiry、source除外、hibernation test結果
- 本番deploy前に残る人間作業
