---
id: 019f621c-5935-7570-b99a-59c7c1b04bbb
title: Foreground realtime Flutter client
status: backlog
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

- `todori-client`へasync `RealtimeTicket`取得API、FRBへ`RealtimeTicketDto`を追加する。
- Dartへ`web_socket_channel 3.0.3`をdirect dependencyとして追加する。
- connection lifecycle、ticket refresh、reconnect backoff、fixed frame parserを実装する。
- 250ms debounce、single-flight dirty follow-up、5分safety / 30秒fallback pollingを実装する。
- list / taskの全sync mutationとcompleted timer保存後にschedulerを起動する。

### やらないこと

- Flutterへtenant / device UUID、session token、sync cursor、outbox、merge logicを公開しない。
- background delivery、APNs / FCM、network reachability dependencyを追加しない。
- WebSocket frameをsync ACKや到達証明にしない。

## 5. 実装手順

1. `todori-client` / FRB / BridgeServiceへticket DTOを薄く接続し、FRB生成物を2.12.0で再生成する。
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

- WebSocket接続はFlutter lifecycle adapter、ticket認証は`todori-client`、同期state machineは`todori-sync`の責務を維持する。
- `app/rust`へnetwork client、runtime、secretを持たせない。
- `web_socket_channel`以外のnetwork / lifecycle dependencyを追加しない。
- anonymous / account-bound unavailable時のlocal CRUDを壊さない。

## 8. 完了報告に含めるべき内容

- TodoriClient / FRB / Dart interface変更
- scheduler、connection、polling state machineの観測証拠
- mutation coverageとwidget / provider test結果
- 実端末・本番Workerで残る確認事項

