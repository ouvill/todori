---
id: 019f621c-573d-7ad1-a3cf-0d52afce8c74
title: Foreground realtime Cloudflare Worker
status: done
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

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-15
- 結果: `realtime-worker/`へmodule Workerとtenant単位Durable Objectを追加した。`GET /v1/connect`はAuthorization headerの300秒ticketを検証し、production経路でEU jurisdiction namespaceを選択する。`POST /v1/publish`はcurrent / previous publish key、raw body HMAC、±30秒timestamp、512-byte上限を検証する。Hibernation attachmentへopaque device tagとexpiryを保存し、期限切れclose、送信元除外、同deviceの旧接続置換、tenant 128接続上限、client message拒否、固定change frameだけのfan-outを実装した。
- 固定version: Node 24.18.0、Wrangler 4.110.0、Vitest 4.1.9、`@cloudflare/vitest-pool-workers` 0.18.2、TypeScript 6.0.3をexact pinし、`package-lock.json`を追加した。pinned `workerd`が受理する最新日付に合わせ、Wrangler compatibility dateは`2026-07-13`とした。
- CI: Node version一致確認、`npm ci`、typecheck、Vitest、Wrangler `deploy --dry-run`だけを行うWorker jobを追加した。deploy処理は追加していない。
- 証拠: Node 24.18.0で`npm ci`、`npm run typecheck`、`npm test`（1 file、10 tests）、`npm run build`（Wrangler 4.110.0 dry-run）、`git diff --check`が成功した。fixture、invalid / unknown / tampered / expired ticket、current / previous key、publish時刻差 / body上限、source除外、duplicate hint、same-device置換、129件目拒否、eviction後attachment復元とexpiry closeを確認した。
- 共通品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker-backed integrationを含む`cargo test --workspace`、`app/rust` release build、`flutter analyze`、`flutter test`（232件成功、Visual QA harness 1件skip）、hardcoded string / client boundary scriptが成功した。`flutter analyze`は初回にvendored Cargokitのignored `.dart_tool`未生成で失敗したため、同build toolで`dart pub get`後に再実行して成功した。
- Commit: `b4853b3` (`feat(realtime): add Cloudflare wake-up Worker`)
- 未解決: Cloudflare account / EU namespace作成、production secret投入、jurisdiction / hibernation / latency / 費用の実環境確認はcredentialを持つ人間のdeploy後作業として残す。

### 独立検証

- 判定: 合格
- 根拠: 実装を担当していない検証担当が統合HEAD `b4853b398c808638455affa617bcfc4f2df04dd6`を確認した。Node 24.18.0でtypecheck、10件のVitest、Wrangler 4.110.0 dry-run build、`git diff main...HEAD --check`を再実行し、Node標準HMACによるticket / publish fixtureの独立再計算も一致した。HMAC byte contract、key rotation、EU production経路、Hibernation / expiry、source除外、接続上限、固定frame、secret-safe response / log、CI exact pinにブロッキング指摘がないことを確認した。
- 検証者: 実装を担当していない独立検証サブエージェント
