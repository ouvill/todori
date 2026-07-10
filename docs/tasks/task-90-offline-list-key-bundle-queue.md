# task-90: offline list作成 + key-bundle upload queue

> ステータス: 完了（offline list key queue実装・独立再検証合格）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

task-84はremote sessionから独立した`LocalCryptoContext`とMK-wrapped List DEK cacheを実装し、task-85〜task-88はproduction CRUD、protocol v2 CAS、typed field clock / placement / rank、durable quarantineをtransactionalな共通client / sync経路へ移した。一方、account-boundのlist作成はserverへのList DEK bundle uploadを先に要求するため、network不通やsession期限切れでは実行できない。

ADR-013は、offline list作成時にList DEK生成、MK-wrap local cache、list row、entity outbox、key-bundle upload queueを同一local transactionで確定し、key bundleをentity recordより先にidempotent uploadすることを要求する。現行serverの`ON CONFLICT DO UPDATE`はstale clientが同じlist IDの既存bundleを置換できるため、本taskでcreate-if-absentへ固定する。2026-07-10のプロダクトオーナー依頼をADR-013実装とこのprotocol選択の承認として扱う。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` 4.3節、6章、11.1節
- `docs/05_設計判断記録.md` ADR-011〜ADR-014
- `docs/tasks/task-84-local-crypto-context.md`
- `docs/tasks/task-85-transactional-crud-migration.md`
- `docs/tasks/task-86-protocol-v2-cas.md`
- `docs/tasks/task-87-typed-field-clock-placement-rank.md`
- `docs/tasks/task-88-typed-pull-durable-quarantine.md`
- `core/client/src/{local_crypto,crud_service}.rs`
- `core/sync/src/{account,keys,engine,enqueue}.rs`
- `core/storage/src/lib.rs`
- `app/rust/src/{api,support,sync_store}.rs`
- `server/src/{routes/sync.rs,sync.rs}`

## 3. ゴール

- account-bound profileでnetworkや有効sessionがなくてもlistを作成できる。
- List DEK、local cache、typed list state、entity outbox、key-bundle queueを1つの`BEGIN IMMEDIATE`で確定する。
- online復帰後、preflightの次、entity outbox pushの前にpending bundleを冪等uploadする。
- serverのList DEK bundleをcreate-if-absentとし、同一ciphertext retryだけを成功させる。
- production CRUD、SQLCipher、実HTTP/Postgresを通るoffline→online→2-client復号をrelease gateにする。

## 4. スコープ

### やること

- local schemaへtenant/list単位のdurable key-bundle upload queueを追加する。opaqueなMK-wrapped List DEKだけを保持し、同一bundle再登録はno-op、異なるbundleはintegrity errorとする。
- account-bound list createを`core/client`へ移し、List DEK生成、server/local用wrap、domain list、typed state、outbox、HLC、queueを単一transactionへ入れる。
- bridgeのaccount-bound `create_list`から事前network uploadを除去する。Anonymousはlocal-only、AccountBoundUnavailableはfail closedを維持する。
- sync順序を`preflight → bundle upload/ACK → entity outbox push → pull`へ固定する。upload/ACK failure時はentity pushとpullへ進まない。
- server endpointをcreate-if-absentへ変更し、同一bundle retryは成功、異なるbundleはtyped conflictとして既存rowを維持する。
- server成功後local ACK前、queue ACK後entity push前、restart/logout/session期限切れのcrash/retryを安全に回復する。
- login/key refreshでremote bundleだけによるlocal pending cacheの消失や別DEK自動生成を行わず、同じlist IDのDEK一致を検証してmergeする。
- 技術仕様へ最終schema、sync ordering、create-if-absent semanticsを反映する。

### やらないこと

- List DEK rotation、共有list、membership、鍵失効。
- aggregate削除scope/epoch、List DEK bundle削除。
- fuzzy full resync、GC horizon、mark-and-sweep。
- protocol v1や旧overwrite semanticsとの互換層。
- serverへのentity plaintext、placement、field clock、rank、local queue stateの追加。

## 5. 実装手順

1. offline create、server overwrite、ACK failure、login時の別DEK生成を再現するtestを追加する。
2. local migrationとqueue/cacheのtransaction APIを実装する。
3. common-client list createとbridgeを接続する。
4. server APIとclient outcomeをimmutable create semanticsへ変更する。
5. sync coordinatorへpreflight後のqueue drainを接続する。
6. offline→restart/login→upload→push→2-client decryptのproduction gateとrollback matrixを追加する。
7. 技術仕様・完了報告を同期し、独立検証を行う。

## 6. 受け入れ基準

- [ ] account-bound production `create_list`がnetwork/sessionなしで成功し、cache/domain/state/outbox/HLC/queueを単一transactionでcommitする。
- [ ] 各local write failureで全状態がrollbackし、commit後の再openではdurable cacheからDEKを復元してtask CRUDを継続できる。
- [ ] serverは初回createと同一ciphertext retryを成功させ、同一tenant/listの異なるciphertextをtyped conflictとして拒否し、既存bundleを変更しない。
- [ ] 観測順が`preflight → bundle upload → queue ACK → outbox read/push → pull`であり、preflight/upload/ACK failure時のentity push/pullは0件となる。
- [ ] server成功後local ACK前の停止を同じpayloadのretryで回復し、DEKやbundleを再生成しない。
- [ ] logout/session期限切れ後のoffline create、再起動、再loginを経てもpending cache/queueが保持され、別clientがbundle取得後にlistを復号できる。
- [ ] pending row/cache欠落やkey mismatchでは別DEKを自動生成せずfail closedする。
- [ ] plaintext DEK、MK、session token、entity plaintext、詳細crypto errorをDB・ログ・bridge・serverへ露出しない。
- [ ] task-86〜task-88のrelease gateと全品質ゲートが継続成功する。
- [ ] 独立verifierが受け入れ基準を再実行し、P1/P2なしと判定する。

## 7. 制約・注意事項

- List DEK平文を永続化せず、必要範囲を越えて保持しない。
- network I/OをSQLite write transaction内で行わない。
- queue rowを送信成功前に削除せず、retry時にbundleを再wrapしない。
- capability preflightをbundle uploadより先に維持し、upgrade block中は追加network I/Oを行わない。
- remote bundle集合を理由にlocal pending keyを削除・置換しない。同一profile/MK/list ID/DEKの検証失敗はfail closedする。
- rotationや共有はimmutable generation 0への例外にせず、別ADRで扱う。
- 独立検証合格前にrelease-readyと表現しない。

## 8. 完了報告に含めるべき内容

- queue/cache schema、idempotency、秘密情報境界。
- transactionへ含めたstateとruntime再構成境界。
- server create-if-absent outcomeと旧overwrite除去。
- preflightからupload、ACK、push、pullまでの順序。
- rollback/crash recovery結果。
- logout/session期限切れ/restart/loginを含む2-client gate。
- task-86〜task-88 regression、migration、品質ゲート、独立検証。
- 本task外のkey rotation、sharing、aggregate削除、full resync/GC。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-10
- 結果: local schema v14へ`pending_list_key_bundles`を追加し、account-bound `create_list`をcommon clientの単一`BEGIN IMMEDIATE`へ移した。List DEK生成、list IDをAADに持つlocal MK-wrap cache、domain list、typed record state、entity outbox、local HLC、server用MK-wrap queueを同時確定するため、session期限切れ・logout・network不通でもlocal listを作成できる。commit後はdurable cacheからruntime crypto contextを再構成する。
- Queue / cache: queue keyは`(tenant_id, list_id)`で、opaqueなserver用MK-wrapped List DEKと`created_at`だけを保持する。同じciphertextの再登録はno-op、異なるciphertextはintegrity errorとした。local cacheも同じlist IDの異なるciphertextによるincremental置換を拒否する。ACKはtenant/list/ciphertext一致行だけを短いtransactionで削除する。
- Sync ordering: sync runを`durable upgrade block → capability preflight → pending bundle upload → compare-and-ACK → initial backfill → entity outbox read/push → pull`へ変更した。production bridgeのinitial backfillはcore coordinatorのpre-push hookへ移し、preflight前にoutboxを読まない。bundle uploadまたはlocal ACK失敗時はbackfill、entity push、pullへ進まずqueue/outboxを保持する。server成功後・local ACK前の失敗は同じqueued ciphertextの再送で回復し、DEKを再生成しない。
- Server: `POST /v2/tenants/{tenant_id}/list-keys`から`ON CONFLICT DO UPDATE`を除去した。初回insertと同一ciphertext retryは成功し、同じtenant/listの異なるciphertextはHTTP 409 / `AccountClientError::KeyBundleConflict`となり、既存rowを変更しない。
- Login / refresh: remote bundleとlocal cacheの同一list IDは復号済みDEK一致を必須とし、remoteにないlocal keyはpending queueがある場合だけ保持する。mismatch、またはpendingでないlocal-only keyはfail closedし、別DEK自動生成やremote集合によるpending cache消失を行わない。
- 証拠: `account_bound_list_create_commits_key_cache_domain_sync_and_queue_atomically`とcache/list/HLC/record-state/outbox/pendingの6 write境界failure matrix、queue immutable/compare-ACK test、server same-bundle retry/different-bundle conflict testが成功した。実SQLCipher restart/relogin reconciliation testはremoteにないlocal keyをpending rowがある場合だけ保持する。`offline_list_bundle_upload_precedes_entity_push_and_second_client_decrypts`はSQLCipher/common-client create、real Axum HTTP、Docker/Postgresを通し、local ACK failure時にserver key=1/entity record=0/queue=1/outbox=1/pre-push hook=0、retry時にpending=0/outbox=1でhook=1、完了後queue/outbox=0、別clientで`Created offline`を復号・materializeすることを確認した。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`（server sync v2 9件、client 24件、storage 69件成功/1件ignored、sync 50件、bridge 5件を含む）、bridge release build、`flutter analyze`、`flutter test`（130 passed / visual QA harness 1 skipped）、hardcoded-string check、`git diff --check`が成功した。Rust/FRB公開関数signatureは変更していないためcodegenは不要。
- Commit: 未コミット。
- 未解決: List DEK rotation / sharing、aggregate削除scope / epoch、fuzzy full resync / GC horizon、RLS hardeningは本task外。`LocalSyncKeys` drop時zeroizeも後続のまま残す。

### 独立検証

- 判定: 合格（P1 / P2 / P3なし）
- 根拠: 初回レビューでproduction bridgeのinitial backfillがpreflight前にoutboxを読むP2を検出した。backfillをcore coordinatorのpre-push hookへ移した修正後、ACK failure時hook=0、retry時pending=0/outbox=1でhook=1、2-client復号まで再確認した。`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`、bridge release build、`flutter analyze`、`flutter test`（130 passed / visual QA harness 1 skipped）、hardcoded-string check、`git diff --check`をverifierが再実行して全て成功した。秘密情報露出とpublic/private境界違反はなかった。
- 検証者: 実装を担当していない独立verifier agent
