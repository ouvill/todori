# task-98: ADR-016 Archive-first削除同期実装

> ステータス: 完了（ADR-016のterminal deletionとserver-trusted continuityを実装）
> 作業日: 2026-07-11

## 1. 背景とコンテキスト

task-97 / ADR-016は、aggregate scope / epochやserver-visible hierarchy metadataを追加せず、bounded tombstone、terminal deletion、server-trusted device continuity、expired-device rebase、client-side late descendant cascadeで削除を収束させると裁定した。現行実装にはfuzzy full resync、GC horizon、CAS、transactionalな既知subtree削除がある一方、通常同期はentity pushがremote pullより先で、server push許可はclient申告cursorに依存し、tombstone後の高HLC Live、history残留、outbox一律保護、late descendant materializeを許す経路が残る。

本taskはAccepted済みADR-016を重要変更レーンで実装する。2026-07-11のプロダクトオーナー指示を人間承認とし、ADR-016の境界を変更する新判断は行わない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/STATUS.md` / `README.md` / `PLAYBOOK.md` / `BACKLOG.md`
- `docs/tasks/task-97-archive-first-deletion-sync-adr.md`
- `docs/tasks/task-95-fuzzy-scan-full-resync-gc-horizon.md`
- `docs/03_技術仕様書.md` §3.2 / §5.2 / §6 / §11
- `docs/05_設計判断記録.md` ADR-009 / 010 / 012 / 013 / 014 / 015 / 016
- `core/sync/`、`core/storage/`、`core/client/`、`server/`のschema、protocol、同期順、削除transaction、鍵bundle実装とtest

## 3. ゴール

- tombstoneを同一record IDのterminal stateとし、削除contentとhistoryを残さない。
- 通常syncをpreflight、pull/reconcile、continuity closure、List DEK bundle、entity pushの順へ固定する。
- server-issued closure proofとdevice continuityにより、expired / old-generation / old-protocol clientのwriteをserverで拒否する。
- expired full resyncでserver-seen、never-synced local-new、remote tombstone、missing dependencyをdurably分類し、削除を復活させずoffline新規list/taskを保持する。
- late descendantを表示せずclient-side tombstoneへ収束させ、必要なList DEKを安全条件成立前にretireしない。

## 4. スコープ

### やること

- `todori-sync`: breaking protocol、closure proof / ACK、pull-before-push orchestration、terminal reconcile、rebase分類、dependency cascade。
- `todori-server`: terminal tombstone、history purge、device continuity / proof schema、version / generation / high-water write guard。
- `todori-storage`: breaking local schema、durable origin / server-seen、closure crash recovery、classification sweep、dependency照会、reseed順、DEK retirement guard。
- `todori-client`: 共通`TodoriClient::sync_now`経路へ新しい順序とstorage adapterを統合する。
- 必須focused test、server統合test、複数device収束test、全品質ゲート。
- transaction / APIの確定に必要な範囲だけ`docs/03_技術仕様書.md`を外科的に更新する。

### やらないこと

- `docs/01_企画書.md` / `docs/02_機能仕様書.md`の変更。
- aggregate scope / epoch、list ID、parent ID、ancestor、scope/epoch等のserver-visible semantic metadata追加。
- canonical Inbox、SQLCipherクロスビルドCI、Organization悪意client対策への拡張。
- 旧schema / wireとの互換層、dual read/write、fallback。
- Flutter / FRB公開API・生成物の変更、新規依存、private repoの変更。

## 5. 実装手順

1. protocol versionをbreaking更新し、tenant/device/high-water/generation束縛のserver-issued closure proofとACKを追加する。
2. server schemaへdevice continuity / proofを追加し、preflight、pull/full-resync closure、ACK、key/entity write guardを同じserver-trusted stateで接続する。
3. serverのtombstone遷移をterminal化し、受理transactionでhistory insertをskipして既存historyをpurgeする。
4. local schemaへnever-synced creation originとserver-seenを追加し、enqueue/coalesce/restart後も保持、ACKで単調にserver-seenへ遷移させる。
5. normal syncをpreflight→pull/reconcile→local cursor/closure commit→proof ACK→pending bundle→lists→tasks pushへ変更する。
6. expired full resync closure後にremote live/tombstone、server-seen absent、never-synced local-new、missing/deleted dependencyをtransactional分類し、正当なlocal-newだけをbundle→list→task順へreseedする。
7. pulled taskのtyped placementとlocal tombstone/dependency chainを検証し、deleted ancestorへ到達するlate descendantをmaterializeせず同一transactionで自身のtombstoneへ変換する。
8. List DEKをretained stateとして保持し、ADR-016の全条件を満たす明示的なretirement判定以外で削除しない。
9. focused testから全品質ゲートへ進み、実装非担当エージェントが統合HEADを独立検証する。

## 6. 受け入れ基準

- [x] tombstone後の高いHLCを持つ同一ID Liveをserverが拒否し、再作成は新IDだけである。
- [x] tombstone受理時に旧contentをhistoryへ新規退避せず、同recordの既存historyを同一transactionで削除する。
- [x] normal syncでpull/reconcile/closure ACK前にList DEK bundleまたはentity pushへ到達しない。
- [x] server-issued proofがtenant/device/high-water/generationへ束縛され、正しいACK後だけcontinuityが単調更新される。
- [x] ACK前crashでserver continuityが進まず、ACK retryは冪等である。
- [x] expired / old-generation deviceと旧protocol clientのkey bundle・entity pushをserverが拒否する。
- [x] tenant/deviceを跨いだcontinuity proof ACKを拒否する。
- [x] remote current tombstoneがlocal live/domain/outboxを破棄し、tombstone stateを保持する。
- [x] server ACK済みだがcurrentに不在のrecordをdomain/state/outboxから破棄し、再pushしない。
- [x] current live + local mutationはtyped merge/rebase成功headだけを再pushし、mutationなしはremote currentを適用する。
- [x] never-synced offline新規list/taskのdurable origin、未ACK creation、鍵、ID非衝突、dependency closureを検証し、bundle→list→task順に保持・reseedする。
- [x] `base_revision_hlc=None`だけをlocal-new判定に使わず、originがcrash、restart、outbox coalesce後も保持される。
- [x] missing/deleted dependencyをmaterializeせず、表示・push対象から除外して削除へ収束させる。
- [x] 既知root/descendantの削除+tombstone enqueueが同一local transactionのまま維持される。
- [x] late descendantが復号後のplacement / ancestor stateからclient-side tombstoneへtransactionalにcascadeする。
- [x] late descendant分類、expired rebase、GC / active-device条件成立前にList DEKをretireしない。
- [x] 2-clientまたは複数device統合testで削除が最終的に収束する。
- [x] serverへsemantic hierarchy metadataを追加していない。
- [x] focused test、`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`が成功する。
- [x] `sh app/tool/check_client_boundaries.sh`、`sh app/tool/test_client_boundaries.sh`、`git diff --check`が成功する。
- [x] Flutter / FRB変更がない。または変更した場合はAGENTS.mdの全Flutter / FRB gateが成功する。
- [x] 独立検証でP1 / P2 / P3指摘がない。

## 7. 制約・注意事項

- protocol/server/local schemaはrelease前のためfinal designへ直接breaking変更し、互換shimを置かない。
- closure proofはopaque transport metadataに限り、content、list、parent、ancestor、aggregate scopeをserverへ漏らさない。
- pull pageのlocal apply/cursor commit前にproofをACKしない。full resyncではcurrent-state分類/rebase commit前にACKしない。
- network I/OをSQLite transaction内へ置かず、server transactionも短く保つ。
- local-new listはlocal DEK、pending wrapped bundle、local-new dependency closureが揃う場合だけ保持する。
- plaintext、鍵、session token、暗号library詳細errorをログ・test出力・完了報告へ含めない。
- FRB生成物を手編集しない。新規依存が必要ならworkspace dependenciesへ集約し、理由を記録する。

## 8. 完了報告に含めるべき内容

- server/local schema version、continuity / proof / origin / retirement stateの具体的なtable・constraint・transaction。
- protocol version、preflight / closure / ACK / write guard契約とsync順。
- terminal tombstone、history purge、expired rebase、late descendant cascade、reseed、DEK retirementの実装結果。
- 必須test名、複数device収束test、全品質ゲートの実測結果とskip / 環境制約。
- 独立検証の判定・指摘・再検証、commit hash、未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-11
- 結果: sync protocolをv3へbreaking更新し、通常同期をpreflight→pull/reconcile→continuity closure ACK→pending List DEK bundle→entity pushへ固定した。server migration `202607110002`で`tenant_device_continuity`、`device_resync_sessions`、`continuity_closure_proofs`と`list_key_bundles.deletion_seq`を追加し、proofをtenant/device/high-water/generationへ束縛した。local schemaはv16とし、`sync_record_origins`で`never_synced`と`server_seen`を永続的に区別する。
- 結果: terminal tombstone、history purge、expired-device rebase、server-seen absent purge、offline local-newのdependency検証とbundle→list→task reseed、missing/deleted dependencyとlate descendantのclient-side cascadeを実装した。List DEKはserverのGC/continuity guard成立後だけretireし、DELETE済みの再試行を冪等成功としてserver成功後のlocal crashから再開可能にした。
- 証拠: `server_trusted_continuity_binds_proofs_and_guards_all_writes`、`closure_ack_failure_keeps_local_commit_and_retries_before_push`、`remote_list_deletion_cascades_offline_descendant_and_converges_to_tombstone`、`list_key_retirement_waits_for_tombstone_gc_and_device_closure`、`full_resync_preserves_valid_never_synced_list_and_task_in_dependency_order`、`remote_list_tombstone_replaces_known_descendant_live_outbox_with_tombstone`が成功した。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`、`sh app/tool/check_client_boundaries.sh`、`sh app/tool/test_client_boundaries.sh`、`git diff --check`が成功した。
- skip / 環境制約: workspace testの既存macOS Keychain実アクセスtest 1件と10k encrypted seed性能test 1件は既定どおりignored。Flutter / FRB変更がないためFlutter固有gateは対象外。server統合testはDockerアクセスを許可した環境で実行した。
- Commit: `4d93b18`（実装）、完了記録commitはgit履歴を参照。
- 未解決: なし。

### 独立検証

- 判定: 合格（P1 / P2 / P3なし）
- 根拠: 初回指摘のdescendant stale outbox、missing dependency再分類、List DEK retirement lifecycle、複数device削除収束、ACK crash/retry testを修正した。再検証でList DEK retirementのserver成功後local crash windowが指摘されたため、guardを維持した冪等DELETEと二重実行testを追加し、最終再検証で全指摘の解消、semantic hierarchy metadata非追加、受け入れ基準充足を確認した。
- 検証者: 実装を担当していない独立検証エージェント（client_research）。
