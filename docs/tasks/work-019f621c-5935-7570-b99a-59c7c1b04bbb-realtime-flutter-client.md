---
id: 019f621c-5935-7570-b99a-59c7c1b04bbb
title: Foreground realtime Flutter client
status: done
lane: critical
milestone: maintenance
---

# Foreground realtime Flutter client

## 1. 背景とコンテキスト

送信端末のlocal mutationと受信端末のchange hintを既存sync runへ早く接続しなければ、WebSocketだけを追加しても30秒poll待ちは解消しない。sync correctnessをRustへ残したまま、Flutter lifecycleに接続とschedulerを置く。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §6.7
- `docs/05_設計判断記録.md` ADR-019
- `docs/dev/client-profile-architecture.md`
- `core/client/src/runtime/sync.rs`
- `app/lib/src/core/providers.dart`
- `app/lib/main.dart`

## 3. ゴール

logged-in foreground clientが短命ticketでWebSocketへ接続し、valid change hintまたはsync対象local mutationから250ms以内にcoalesced syncをrequestし、provider停止時は30秒pollingへ安全に縮退する。

## 4. スコープ

### やること

- `taskveil-client`へasync `RealtimeTicket`取得API、FRBへ`RealtimeTicketDto`を追加する。
- Dartへ`web_socket_channel 3.0.3`をdirect dependencyとして追加する。
- connection lifecycle、ticket refresh、reconnect backoff、fixed frame parserを実装する。
- 250ms debounce、single-flight dirty follow-up、5分safety / 30秒fallback pollingを実装する。
- list / taskの全sync mutationとcompleted timer保存後にschedulerを起動する。

### やらないこと

- Flutterへtenant / device UUID、session token、sync cursor、outbox、merge logicを公開しない。
- background delivery、APNs / FCM、network reachability dependencyを追加しない。
- WebSocket frameをsync ACKや到達証明にしない。

## 5. 実装手順

1. `taskveil-client` / FRB / BridgeServiceへticket DTOを薄く接続し、FRB生成物を2.12.0で再生成する。
2. WebSocket connectorをtest double可能なDart interfaceとして実装する。
3. foreground / login connect、background / logout / dispose close、期限30秒前refreshを実装する。
4. 1、2、4、8、16、30秒 + jitter reconnectとconnected / disconnected polling切替を実装する。
5. sync対象mutation成功後の共通triggerとdirty follow-up schedulerを接続する。
6. 統合HEADを独立検証する。

## 6. 受け入れ基準

- valid固定frameだけがsyncを起動し、invalid JSON、unknown version / type、extra metadata frameは無視される。
- 連続triggerは250msで1 runへまとまり、run中triggerは完了後の追従runを保証する。
- foreground / login / refresh / reconnect / background / logout lifecycleがfake clock / socket testで再現される。
- connected時5分、disconnected時30秒、resume時即時syncになる。
- list create / rename / archive / unarchive / delete、task create / update / status / reorder / delete / undo、completed timer保存がlocal trigger対象である。
- ticket、Authorization header、opaque identifierがlogやerror表示へ出ない。
- FRB generated diff、Flutter test、repository共通品質ゲート、独立検証が合格する。

## 7. 制約・注意事項

- WebSocket接続はFlutter lifecycle adapter、ticket認証は`taskveil-client`、同期state machineは`taskveil-sync`の責務を維持する。
- `app/rust`へnetwork client、runtime、secretを持たせない。
- `web_socket_channel`以外のnetwork / lifecycle dependencyを追加しない。
- anonymous / account-bound unavailable時のlocal CRUDを壊さない。

## 8. 完了報告に含めるべき内容

- TaskveilClient / FRB / Dart interface変更
- scheduler、connection、polling state machineの観測証拠
- mutation coverageとwidget / provider test結果
- 実端末・本番Workerで残る確認事項

## 9. 完了報告

### 実装

- `taskveil-client`にactive sync contextを内部利用する`RealtimeTicket`取得APIを追加し、session token、tenant / device IDをfrontendへ公開せず、FRB 2.12.0で`RealtimeTicketDto`生成物を再生成した。
- `web_socket_channel 3.0.3`をdirect dependencyにし、ticketをAuthorization headerだけで渡す`wss`接続を実装した。query、fragment、userinfo、`/v1/connect`以外のpathは拒否する。
- login / foregroundで接続し、background / logout / disposeで切断するlifecycle、期限30秒前ticket更新、1 / 2 / 4 / 8 / 16 / 30秒 + jitterの再接続を実装した。
- 整数`v: 1`と`type: changed`だけの固定frameを受理し、binary、invalid JSON、`v: 1.0`、unknown、追加metadata frameを無視する。
- 250ms debounce、single-flight dirty follow-up、接続中5分safety pull、切断中30秒polling、resume即時syncを共通schedulerへ実装した。
- 指定されたlist / taskの全sync mutation、Undo、completed timer保存成功後を共通triggerへ接続した。anonymous CRUDと既存provider invalidation semanticsは維持した。
- ticket、WebSocket URL、Authorization header、tenant / device / opaque identifierをlogへ出す経路は追加していない。

### 検証

- `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`: PASS。既存のKeychain実機test 1件とmanual performance test 1件だけがintentional ignore。
- `cargo build --manifest-path app/rust/Cargo.toml --release`: PASS。
- `flutter analyze`: PASS。`flutter test`: 241件PASS、既存visual QA harness 1件だけがintentional skip。
- realtime / provider / sync / timer focused Flutter tests: 31件PASS。
- hardcoded strings、client boundary scripts、FRB再生成の内容hash一致、`git diff --check`: PASS。
- Node 24.18.0でWorkerの`npm ci`、typecheck、Vitest 10件、Wrangler 4.110.0 dry-run buildを再実行してPASS。
- 独立検証担当が修正後HEAD `2a09335d1a5c2c38729b6e63a5f0f62924e5d4e8`を再検証し、契約違反・ブロッキング指摘なしでPASSと判定した。

### Commit

- `5ce02c8 feat(realtime): add Flutter connection and sync scheduler`
- `2a09335 fix(realtime): require integer frame version`

### 未解決事項

- 実端末のforeground / background lifecycle、deployed Workerとの実接続、実Cloudflare latencyはdeploy後の人間確認として残す。このwork itemではdeploy、credential投入、AWS / Neon変更、releaseを行っていない。
