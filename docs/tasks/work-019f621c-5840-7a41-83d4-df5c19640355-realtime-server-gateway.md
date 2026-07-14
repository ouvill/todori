---
id: 019f621c-5840-7a41-83d4-df5c19640355
title: Foreground realtime server gateway
status: active
lane: critical
milestone: maintenance
---

# Foreground realtime server gateway

## 1. 背景とコンテキスト

Workerはtenant identityやsessionを検証しない。Todori serverが既存request-time認証を正本として短命ticketを発行し、accepted push commit後だけ認証済みbest-effort publishを行う必要がある。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §6、§6.7
- `docs/05_設計判断記録.md` ADR-019
- `server/src/auth.rs`
- `server/src/routes/sync.rs`
- `server/src/sync.rs`

## 3. ゴール

認証済み端末へ300秒realtime ticketを発行し、accepted push commit後に500ms以内で署名済みchange publishを試行しながら、provider障害をpush correctnessへ波及させないserver gatewayを実装する。

## 4. スコープ

### やること

- `POST /v2/tenants/{tenant_id}/realtime/ticket`と`RealtimeTicketResponse`を追加する。
- channel / device tagのdomain-separated HMAC導出、ticket署名、current / previous key validation contractを実装する。
- accepted resultが1件以上あるpushだけをpublishし、source device tagをWorkerへ渡す。
- realtime configのall-absent disabled / partial startup failureを実装する。
- secret-safe structured eventとunit / Postgres integration testを追加する。

### やらないこと

- server DB schema、sync protocol、PushResponse wire shapeを変更しない。
- provider failureをretry queueやpush failureへ変えない。
- 実secret、Cloudflare resource、AWS / Neon設定をcommitしない。

## 5. 実装手順

1. `hmac = 0.12.1`をworkspaceへ追加し、`sha2 0.10`を維持する。
2. 32-byte base64 secret、URL、key ID、current / previous keyをstartup時に厳密検証する。
3. ADR-019の固定順payloadをbase64url no-paddingし、domain separatorとpayload segmentをHMAC-SHA256で署名した2-segment ticketと300秒expiryを返す。
4. push commit結果からaccepted有無を判定し、固定順512-byte以下bodyと3 headerをADR-019のraw body contractで署名して500ms timeoutで送る。
5. timeout、transport、non-2xxを機密値なしで観測し、元のPushResponseは成功のまま返す。
6. 統合HEADを独立検証する。

## 6. 受け入れ基準

- ticket endpointは現行sync endpointと同じrequest-time session / device / membership policyを呼ぶ。Billing foundationが同policyへentitlementを追加した時点で自動的に継承し、このwork itemではDB schema、固定plan、開発用entitlementを追加しない。
- ticket payloadが`kid`、`aud`、opaque `channel` / `device`、`iat` / `exp`だけを固定順で持ち、tokenがADR-019の2-segment wireと一致する。
- publish body、key ID / timestamp / signature header、domain separator、raw body署名、512-byte上限がADR-019と一致する。
- no-op / conflict / supersededだけのpushはpublishせず、accepted pushだけpublishする。
- Worker timeout、network error、4xx / 5xxでもcommit済みpush responseが成功する。
- realtime全設定なしでserverが起動しticketは503、部分設定はstartup errorになる。
- secret、ticket、tenant / device UUID、opaque identifierがlogへ出ない。
- repository共通品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- `hmac 0.13`へ上げて`sha2`系譜を二重化しない。
- HMAC比較はconstant-time APIを使う。
- ticketをURL queryへ入れず、clientへsession token以外の認可正本を渡さない。
- publishをPostgres transaction内やresponse後fire-and-forgetで実行しない。

## 8. 完了報告に含めるべき内容

- public endpoint、ticket wire、config / key rotation契約
- accepted判定とbest-effort publishの証拠
- auth、tamper、disabled、timeout test結果
- production secret投入前に残る人間作業
