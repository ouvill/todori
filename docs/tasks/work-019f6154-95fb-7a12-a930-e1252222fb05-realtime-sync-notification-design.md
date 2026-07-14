---
id: 019f6154-95fb-7a12-a930-e1252222fb05
title: Foreground realtime sync notification design
status: active
lane: critical
milestone: maintenance
---

# Foreground realtime sync notification design

## 1. 背景とコンテキスト

現在のFlutter clientはログイン中に30秒周期で同期を実行する。これによりforegroundで2台の端末を開いていても、変更端末のpushと受信端末のpullがpoll周期まで遅れ、変更がない場合もpreflight / pull / closure ACKを繰り返す。

Todoriの同期correctnessはPostgres上のcurrent state、server採番`seq`、device continuity、clientのpull / merge / push state machineが担っている。リアルタイム性を追加するときもこの境界を変えず、WebSocketは同期の正本ではなく同期実行を早める欠落可能な通知として扱う必要がある。

プロダクトオーナーは2026-07-15に、AWS統一を要件とせず、Cloudflare Durable Objectsをリアルタイム通知レイヤーの第一候補として設計を文書化する方針を示した。本work itemはその設計契約を確定するための文書化だけを扱い、runtime実装は後続work itemへ分割する。

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

foreground中のlocal mutationとremote changeを通常は数秒以内に他端末へ反映しながら、WebSocket / Cloudflareの停止、通知欠落、重複、順序逆転が同期correctnessやlocal編集可用性へ影響しない設計契約を、ADRと技術仕様へ記録できる状態にする。

## 4. スコープ

### やること

- Postgresと既存HTTPS push / pullを唯一の同期正本として維持する。
- Cloudflare Worker + tenant単位Durable Objectを、foreground WebSocket通知の第一候補として記録する。
- local mutation後のdebounced immediate sync、commit後のchange notification、受信後pull、single-flight / coalescingを定義する。
- reconnect、foreground復帰、network復帰、通知欠落時のfallback pullを定義する。
- E2EE境界、opaque channel ID、短命ticket、失効、rate limit、EU jurisdiction、metadata最小化を定義する。
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
2. ADR-019 draftへ通知レイヤーの責務、event envelope、認証、失敗時挙動、却下案を記録する。
3. セキュリティ、privacy、失効遅延、provider障害、mobile lifecycle、通知stormのリスクをレビューする。
4. プロダクトオーナー承認後、ADR-019をAcceptedへ変更し、`docs/03_技術仕様書.md`と`docs/09_運用ガイド.md`へ確定契約を同期する。
5. runtime実装をCloudflare endpoint、server publish / ticket、client connection、immediate sync scheduler、統合テスト / observabilityの依存順に後続work itemへ分割する。
6. 文書差分のリンク、用語、日付、ADR参照、public/private境界を独立検証する。

## 6. 受け入れ基準

- ADRが、WebSocketは欠落可能なhintであり、Postgres + HTTPS pullだけが同期到達状態を証明することを明記している。
- foreground即時同期が `local commit -> debounced sync -> server commit -> notify -> remote pull -> UI refresh` として定義されている。
- notification payloadがversion、event type、opaque channel、`high_water`以下の最小metadataに限定され、暗号blob、鍵、tenant UUID、session token、plaintextを含まない。
- duplicate、out-of-order、disconnect、provider outage、app resume、network regainの全てで、既存sync state machineから回復できる。
- WebSocket接続中の低頻度safety pullと、切断中のbounded fallback pollingが定義されている。
- device / membership / entitlement失効後のticket再発行拒否と、既存接続で許容するmetadata露出窓が明記されている。
- Cloudflareを外して別providerへ交換しても、core sync protocolとPostgres schemaを変更しない境界が定義されている。
- runtime実装が独立して受け入れ可能な後続work itemへ分割されている。
- `git diff --check`と文書リンク確認が合格し、別担当または別セッションの独立検証結果が記録されている。

## 7. 制約・注意事項

- `lane: critical` とし、ADR-019をAcceptedへ変更する前にプロダクトオーナーの明示承認を得る。
- `docs/03_技術仕様書.md`は技術的な唯一の真実源であるため、Proposed ADRを確定仕様として先行転記しない。
- Cloudflare Durable Object IDはjurisdiction外のログへ現れ得るため、tenant UUIDを`idFromName`等へ直接渡さない。
- clientが通知を受信した事実をcontinuity ACK、outbox ACK、pull cursor更新として扱わない。
- 通知publishをPostgres transactionの成功条件にせず、通知失敗によって同期済みwriteを失敗扱いにしない。
- secret、token、tenant UUID、暗号blob、復号済みplaintextをログ、task報告、public issueへ含めない。
- public/private境界を変更せず、account ID、resource名、credential、実料金予測の詳細はpublic文書へ記録しない。

## 8. 完了報告に含めるべき内容

- 承認されたADR-019の要点と、承認日
- 更新した技術仕様・運用ガイドの節
- notification envelope、ticket、fallback、degraded behaviorの確定値
- 後続runtime work itemのIDと依存順
- 実行した文書検証と独立検証の結果
- 未決のCloudflare account / jurisdiction / observability設定
