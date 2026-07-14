---
id: 019f6154-95fb-7a12-a930-e1252222fb05
title: Foreground realtime sync notification design
status: done
lane: critical
milestone: maintenance
---

# Foreground realtime sync notification design

## 1. 背景とコンテキスト

現在のFlutter clientはログイン中に30秒周期で同期を実行する。これによりforegroundで2台の端末を開いていても、変更端末のpushと受信端末のpullがpoll周期まで遅れ、変更がない場合もpreflight / pull / closure ACKを繰り返す。

Todoriの同期correctnessはPostgres上のcurrent state、server採番`seq`、device continuity、clientのpull / merge / push state machineが担っている。リアルタイム性を追加するときもこの境界を変えず、WebSocketは同期の正本ではなく同期実行を早める欠落可能な通知として扱う必要がある。

プロダクトオーナーは2026-07-15に、AWS統一を要件とせず、Cloudflare Durable Objectsをリアルタイム通知レイヤーの第一候補として設計を文書化する方針を示した。初稿にはserver-to-Worker認証、`high_water` metadata、hibernation後のexpiry、local commit後schedulerに欠陥があったため、同日に最小hint、用途別HMAC鍵、固定interval、Flutter lifecycle境界へ修正する判断を承認した。本work itemは修正版の設計契約を確定し、runtime実装を後続work itemへ分割する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §1.5、§6
- `docs/05_設計判断記録.md` ADR-002〜ADR-005、ADR-008、ADR-012、ADR-014、ADR-016
- `docs/09_運用ガイド.md` §2、§5、§7、§8
- `app/lib/src/core/providers.dart` のforeground pollingとsingle-flight同期
- `core/sync/src/apply.rs` のpreflight / pull / push state machine
- `server/src/routes/sync.rs` と `server/src/sync.rs`
- Cloudflare Durable ObjectsのWebSocket Hibernation、data location、limitsに関する公式文書

## 3. ゴール

foreground中のlocal mutationとremote changeを通常は数秒以内に他端末へ反映しながら、WebSocket / Cloudflareの停止、通知欠落、重複、順序逆転が同期correctnessやlocal編集可用性へ影響しない実装可能な設計契約を、ADR、技術仕様、運用ガイド、client境界へ記録し、runtime実装をUUIDv7 work itemへ分割する。

## 4. スコープ

### やること

- Postgresと既存HTTPS push / pullを唯一の同期正本として維持する。
- Cloudflare Worker + tenant単位Durable Objectを、foreground WebSocket通知の第一候補として記録する。
- local mutation後250msのdebounced immediate sync、commit後のchange notification、受信後pull、dirty follow-upを伴うsingle-flight / coalescingを定義する。
- 300秒ticket、期限30秒前refresh、1〜30秒backoff、接続中5分safety pull、切断中30秒fallback pollingを定義する。
- E2EE境界、固定hint frame、opaque channel / device tag、用途別HMAC鍵、失効、EU jurisdiction、metadata最小化を定義する。
- server-to-Worker publish認証、500ms best-effort timeout、source device除外、hibernation attachmentを定義する。
- provider障害時のdegraded behavior、観測指標、費用上限を設計する。
- ADR承認後に更新する技術仕様・運用ガイドと、runtime実装の分割単位を明示する。

### やらないこと

- WebSocketへ暗号blob、鍵、session token、domain plaintextを流さない。
- Durable Objectsを同期DB、履歴、outbox、message queueの正本にしない。
- WebSocket通知へdelivery guarantee、厳密な順序、ACK済み同期cursorの意味を持たせない。
- background中の即時同期を保証しない。APNs / FCMは別work itemとする。
- Worker、server、Rust core、Flutter clientのruntime実装やCloudflare本番resource作成を行わない。
- 変動する料金単価をADRの恒久契約に固定しない。

## 5. 実装手順

1. 現行30秒polling、local mutation、sync single-flight、server transaction / `high_water`境界を確認する。
2. 初稿の欠陥を修正し、通知レイヤーの責務、frame、ticket / publish認証、固定interval、失敗時挙動、却下案をADR-019へ記録する。
3. セキュリティ、privacy、失効遅延、provider障害、mobile lifecycle、通知stormのリスクをレビューする。
4. 2026-07-15のプロダクトオーナー承認を記録してADR-019をAcceptedへ変更し、`docs/03_技術仕様書.md`、`docs/09_運用ガイド.md`、client境界文書へ確定契約を同期する。
5. runtime実装をCloudflare Worker、server gateway、Flutter client、統合 / observabilityの依存順に次のwork itemへ分割する。
   - `019f621c-573d-7ad1-a3cf-0d52afce8c74`
   - `019f621c-5840-7a41-83d4-df5c19640355`
   - `019f621c-5935-7570-b99a-59c7c1b04bbb`
   - `019f621c-5a25-73b2-a4a6-1794d30d706c`
6. 文書差分のリンク、用語、日付、ADR参照、public/private境界を独立検証する。

## 6. 受け入れ基準

- ADRが、WebSocketは欠落可能なhintであり、Postgres + HTTPS pullだけが同期到達状態を証明することを明記している。
- foreground即時同期が `local commit -> debounced sync -> server commit -> notify -> remote pull -> UI refresh` として定義されている。
- WebSocket notification frameが正確に`{"v":1,"type":"changed"}`だけを持ち、`high_water`、opaque identifier、暗号blob、鍵、tenant UUID、session token、plaintextを含まない。
- duplicate、out-of-order、disconnect、provider outage、app resume、network regainの全てで、既存sync state machineから回復できる。
- 用途別HMAC鍵、±30秒publish時刻窓、300秒ticket、connection attachment expiry、source device除外が定義されている。
- WebSocket接続中5分のsafety pull、切断中30秒polling、1〜30秒reconnect、250ms debounceが定義されている。
- 現行sync endpointと同じrequest-time session / device / membership policyによるticket再発行拒否、将来のentitlement判定継承、最大300秒のchange timing露出窓が明記されている。
- channel / device tag、ticket、publishのfield順、encoding、domain separator、署名対象bytes、header、body上限がcross-language fixtureを作れる粒度で固定されている。
- Cloudflareを外して別providerへ交換しても、core sync protocolとPostgres schemaを変更しない境界が定義されている。
- runtime実装が独立して受け入れ可能な後続work itemへ分割されている。
- `git diff --check`と文書リンク確認が合格し、別担当または別セッションの独立検証結果が記録されている。

## 7. 制約・注意事項

- `lane: critical` とし、ADR-019の修正版に対する2026-07-15のプロダクトオーナー承認を記録する。
- `docs/03_技術仕様書.md`は技術的な唯一の真実源であるため、Proposed ADRを確定仕様として先行転記しない。
- Cloudflare Durable Object IDはjurisdiction外のログへ現れ得るため、tenant UUIDを`idFromName`等へ直接渡さない。
- clientが通知を受信した事実をcontinuity ACK、outbox ACK、pull cursor更新として扱わない。
- 通知publishをPostgres transactionの成功条件にせず、通知失敗によって同期済みwriteを失敗扱いにしない。
- secret、token、tenant UUID、暗号blob、復号済みplaintextをログ、task報告、public issueへ含めない。
- public/private境界を変更せず、account ID、resource名、credential、実料金予測の詳細はpublic文書へ記録しない。

## 8. 完了報告に含めるべき内容

- 承認されたADR-019の要点と、承認日
- 更新した技術仕様・運用ガイドの節
- notification frame、HMAC、ticket、scheduler、fallback、degraded behaviorの確定値
- 後続runtime work itemのIDと依存順
- 実行した文書検証と独立検証の結果
- 未決のCloudflare account / jurisdiction / observability設定

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-15
- 結果: ADR-019をAccepted化し、Postgres / HTTPSを唯一の同期正本、固定change hint、用途別HMAC鍵、byte-level ticket / publish wire、EU Durable Object、Flutter lifecycle scheduler、5分safety pull / 30秒fallback pollingとして確定した。技術仕様、運用ガイド、client境界へ同期し、Worker、server gateway、Flutter client、integration / observabilityの後続4 work itemを`backlog`で登録した。
- 証拠: `git diff --check`と相対Markdown link検査が成功した。`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker-backed server integrationを含む`cargo test --workspace`、`app/rust` release build、`flutter analyze`、`flutter test`（232件成功、Visual QA harness 1件skip）、hardcoded string / client boundary 3 scriptが成功した。`flutter analyze`は初回にvendored Cargokitのignored `.dart_tool`未生成で失敗したため、同build toolで`dart pub get`後に再実行して成功した。
- Commit: `e7bacab` (`docs(sync): accept realtime notification contract`)
- 未解決: Cloudflare account / EU namespace作成、production secret投入、jurisdiction / latency / 費用の実環境確認はcredentialを持つ人間のdeploy後作業として残す。runtime実装は登録した後続4 work itemで行う。

### 独立検証

- 判定: 合格
- 根拠: 実装を担当していない検証担当が統合差分を3 passで確認した。初回のticket / publish byte contract、余分なticket claim、未実装billingとの認可境界、remote pull後UI invalidationの4指摘と、再検証時のpublish署名対象 / UUID表現の2指摘を修正した後、ADR、技術仕様、client境界、後続4 work itemの整合、front matter、public/private境界、`git diff --check`、相対linkを再確認して合格した。
- 検証者: 実装を担当していない独立検証サブエージェント
