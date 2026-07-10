# task-89: offline list作成 + key-bundle upload queue

> ステータス: 実装待ち（重要変更レーン・着手承認済み）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

task-84はremote sessionから独立した`LocalCryptoContext`とMK-wrapped List DEK cacheを実装し、task-85〜task-88はproduction CRUD、protocol v2 CAS、typed field clock / placement / rank、durable quarantineをtransactionalな共通client / sync経路へ移した。一方、account-boundのlist作成だけは、domain rowを書き込む前に`ensure_list_dek_for_list`がserverへList DEK bundleをuploadするため、network不通やsession期限切れでは実行できない。login時の不足key補完もその場で新しいDEKを生成してserverへupsertし、local listと既存cacheの由来をdurableに結び付けていない。

ADR-013は、offline list作成時にList DEK生成、MK-wrap local cache、list row、entity outbox、key-bundle upload queueを同一local transactionで確定し、key bundleをentity recordより先にidempotent uploadすることを要求している。現行serverの`ON CONFLICT DO UPDATE`は、stale clientが同じlist IDの既存bundleを無条件に置換できるため、この契約を満たさない。本taskではserver bundleを`(tenant_id, list_id)`ごとのcreate-if-absent immutable rowへ固定し、同一ciphertextのretryだけを成功、異なるciphertextをtyped conflictとして拒否する。今回のプロダクトオーナー依頼をADR-013の実装着手とこのprotocol選択の承認として扱い、task-86〜task-88の同期不変条件を維持する。

## 2. 事前に読むべきファイル

- `docs/05_設計判断記録.md` ADR-011〜ADR-014
- `docs/03_技術仕様書.md` 4.3節、6章、11.1節
- `docs/tasks/task-84-local-crypto-context.md`
- `docs/tasks/task-85-transactional-crud-migration.md`
- `docs/tasks/task-86-protocol-v2-cas.md`
- `docs/tasks/task-87-typed-field-clock-placement-rank.md`
- `docs/tasks/task-88-typed-pull-durable-quarantine.md`
- `core/client/src/{local_crypto,crud_service}.rs`
- `core/crypto/src/key_hierarchy.rs`
- `core/sync/src/{account,keys,engine,enqueue}.rs`
- `core/storage/src/{lib.rs,schema.sql}`
- `app/rust/src/{api,support,sync_store}.rs`
- `server/src/{routes/sync.rs,sync.rs}`
- `server/migrations/202607080002_account_key_bundles.sql`
- `server/tests/{auth_server,sync_v2_server}.rs`

## 3. ゴール

- account-bound profileでnetworkと有効sessionがなくてもlistを作成し、再起動後もそのlist配下のlocal mutationを継続できるようにする。
- List DEK、local cache、typed list state、entity outbox、key-bundle upload queueのdurable stateを1つの`BEGIN IMMEDIATE`で確定する。
- online復帰後、protocol preflightの次、entity outbox pushの前にpending key bundleを冪等にuploadし、serverがDEKを取得できないrecordを先に公開しない。
- serverのList DEK bundleをcreate-if-absentへ変更し、retryは受理するが異なるbundleによる既存keyの上書きを拒否する。
- production CRUD、暗号化SQLite、実HTTP / Postgresを通るoffline→online→2-client復号のscenarioをrelease gateにする。

## 4. スコープ

### やること

- local schemaへtenant / list単位のdurable key-bundle upload queueを追加する。rowはserverへ送るMK-wrapped List DEK bundleをそのまま保持し、同じlistのpending entryをimmutableにする。同一bundleの再登録はno-op、異なるbundleはlocal integrity errorとし、plaintext DEK、Master Key、session token、entity plaintext、詳細crypto errorを保存しない。attempt count / 最終試行時刻等を持つ場合も非機密な運用metadataだけに限定する。
- account-boundのlist createを`core/client`へ移す。List IDとList DEKを生成し、server用MK-wrap、list IDをAADに含むlocal cache用MK-wrap、typed list plaintext / fixed-width rank / initial HLCをtransaction前のpure処理で準備する。単一`BEGIN IMMEDIATE`内でlocal cache row、domain list row、sync record state、entity outbox head、local HLC、key-bundle queue rowを確定し、commit後にruntime key setをdurable cacheから再構成する。transaction失敗時は生成した鍵materialをzeroizeし、durableな部分状態を残さない。
- bridgeのaccount-bound `create_list`を上記common clientへ委譲し、事前network uploadを行う`ensure_list_dek_for_list`経路を退役する。Anonymousのlocal-only作成は維持するが、`AccountBoundUnavailable`をAnonymousへfallbackさせない。
- sync runの順序を`capability preflight → pending key bundle upload / local ACK → entity outbox read・push → pull`へ固定する。queueが空になったことを確認するまでentity outboxを読まず、bundle uploadの一時失敗またはpermanent conflict時はqueueとentity outboxを保持してrunを失敗させる。HTTPはlocal write transaction外で行い、成功後のqueue deleteは送信したlist ID / bundleと一致するheadだけを短いtransactionでACKする。
- serverの`POST /v2/tenants/{tenant_id}/list-keys`をcreate-if-absent semanticsへ変更する。初回だけinsertし、同じ`(tenant_id, list_id, wrapped_list_dek)`の再送はidempotent success、同じtenant / listで異なるciphertextはtyped `KeyBundleConflict`（HTTP 409相当）として既存rowを変更しない。key generation / rotation世代は本taskでは導入せず、将来のrotationは別ADRとする。
- crash / retryを分散transactionとして扱う。server成功後・local queue ACK前の停止では同じqueued ciphertextを再送し、serverのidempotent success後にACKする。queue ACK後・entity push前の停止では次runがbundle存在を前提にentity pushを再開する。server応答前後の不確実性を理由に新しいDEKや新しいbundle ciphertextを生成し直さない。
- logout / session期限切れ / app再起動をまたぐoffline→online回復を実装する。login / key refreshはserver bundle集合にないlocal listをその場で別DEK生成して補完せず、同じprofile / MKでlocal cacheとserver bundleを復号し、同じlist IDが両方にある場合はList DEKの一致を確認してからdurable local cache / pending queue / remote集合をmergeしてruntimeをReadyにする。pending bundle upload成功前にremote bundle集合だけでlocal cacheを全置換・欠落させず、pending rowを保持する。key不一致、またはpending rowもcacheもない不足listはfail closedする。
- `SyncRunSummary` / bridge statusにpending key bundle件数、今回upload / retry件数、typed conflict等を非機密な形で観測可能にする。FRB公開型を変更する場合は2.12.0固定でcodegenし、生成物を手編集しない。`docs/03_技術仕様書.md`を最終schema、create-if-absent protocol、sync ordering、recovery境界へ外科的に同期する。

### やらないこと

- List DEK rotation、世代番号、共有listのmember別seal、membership変更、鍵失効。
- aggregate list / subtree削除scope、epoch、未知descendant削除、List DEK bundle / local cacheの削除。
- fuzzy-scan full resync、GC horizon、mark-and-sweep。
- task-86のCAS current-head / op ID ACK、task-87のtyped field clock / placement / rank、task-88のquarantine / cursor page transactionの再設計。
- serverへentity plaintext、task-to-list placement、field clock、rank、local queue stateを追加すること。
- protocol v1、旧bundle overwrite semantics、queueなし同期とのdual write / fallback。
- key queueの手動破棄UI、List DEK再生成による自動修復、端末削除・account data wipe。

## 5. 実装手順

1. production `create_list`のoffline失敗、現行server bundle overwrite、server成功後local ACK失敗、login時の別DEK生成を再現する失敗testを先に追加する。
2. local schema migrationとqueue / incremental local-cacheのtransaction APIを追加し、same-bundle no-op、different-bundle拒否、tenant分離、failure injectionを実装する。
3. List DEK生成・2種類のwrap・typed list enqueueをcommon-client list createの単一`BEGIN IMMEDIATE`へ接続し、bridgeのaccount-bound事前network経路を置換する。
4. server list-key endpointをcreate-if-absent / same-ciphertext idempotent / different-ciphertext conflictへ変更し、clientにtyped outcomeを追加する。
5. sync coordinatorをpreflight後のqueue drainへ接続し、entity outboxより先のupload、compare-and-ACK、crash retry、login / refresh時のpending local key reconciliationを実装する。
6. production CRUD、SQLCipher DB、real Axum HTTP、Docker / Postgres、2 clientを用いたoffline→online recovery release gateと、各local write地点のrollback matrixを追加する。
7. 技術仕様を最終shapeへ同期し、独立verifierがtask-86〜task-88のrelease gate、metadata境界、全品質ゲートを再実行する。

## 6. 受け入れ基準

- [ ] account-bound production `create_list`がnetwork I/Oと有効sessionなしで成功し、List DEK、local MK-wrap cache、domain list、strict typed record state、entity outbox、local HLC、key-bundle queueを単一`BEGIN IMMEDIATE`でcommitする。Anonymous / AccountBoundUnavailableの既存境界を崩さない。
- [ ] local cache / list row / record state / entity outbox / HLC / key queueの各write地点へfailureを注入すると全状態が開始前へrollbackする。成功後・runtime更新前にprocessを停止しても、再openしたproduction clientがdurable cacheから新listのDEKを復元し、そのlist配下のtask CRUDをofflineで継続できる。
- [ ] server list-key APIはcreate-if-absentであり、初回createと同一queued ciphertextの任意回retryを成功させる。同じtenant / listの異なるciphertextはtyped conflictとなり、Postgresの既存bundle、local queue、entity outboxを変更しない。旧`ON CONFLICT DO UPDATE`上書き経路が残らない。
- [ ] syncの観測順が`preflight → key bundle upload → queue ACK → entity outbox read / push → pull`である。unsupported preflight、transient upload failure、bundle conflict、local ACK failureの各caseでentity push / outbox ACK / pullが0件、queueとentity outboxが保持され、HTTP中にSQLite write transactionを保持しない。
- [ ] server upload成功後・local ACK前のcrash / failureを同じqueue payloadの再送で回復し、重複server rowやDEK再生成を起こさない。queue ACK後・entity push前のcrashでは次runがrecord pushを再開し、bundleを持たないserverへentity recordが先行するwindowがない。
- [ ] session期限切れまたはlogout後にlistをoffline作成し、app再起動と再loginを経ても、local cacheをMKで復号してpending queueを保持し、remote bundle集合とのlist ID / List DEK一致を検証したmergeで同じkeyを復元する。remote cache全置換でpending keyを消さない。online sync後にqueueが解決し、別production clientがkey refresh後にlist recordをpull / 復号して同じtyped listを得る。key mismatch、またはpending rowもcacheもない不足listは別DEKを自動生成せずfail closedする。
- [ ] queueはtenant / listで分離され、保存・ログ・error・bridge status・server schemaにplaintext DEK、Master Key、session token、entity plaintext、field clock、placement、rank、詳細crypto errorを露出しない。server-visible metadataは既存のtenant ID、list ID、opaque wrapped bundleと非機密なprotocol outcomeに限定される。
- [ ] production release gateがbridgeと同じcommon-client CRUD、暗号化SQLite、real Axum HTTP、Docker / Postgresを通り、fixtureからlist row、cache、queue、outbox、server bundleを完成状態へ直接注入せず、offline create→restart/login→bundle upload→entity push→2-client pull/decryptを観測する。
- [ ] task-86 CAS / op ID ACK、task-87 production 2-client distinct-field・placement/rank、task-88 preflight・durable quarantine・page rollbackの既存release gateが継続成功し、key queue retryがoutbox coalesce、quarantine、cursorを破壊しない。
- [ ] local / server migration、技術仕様、README共通品質ゲート、Docker/Postgresを含むworkspace test、必要なFRB / Flutter gate、`git diff --check`が成功し、独立verifierがP1 / P2なしの再現可能な根拠を返す。

## 7. 制約・注意事項

- List DEK平文を永続化しない。生成後は`Zeroizing`等で保持し、local cache用wrap、server bundle用wrap、typed list暗号化に必要な範囲を越えて残さない。Debug、panic、SQL error、test failureへ鍵やbundle内容を出さない。
- network I/OをSQLite write transaction内で行わない。local transactionとserver transactionを1つに見せかけず、durable queue、immutable server create、compare-and-ACKでcrash recoveryを証明する。
- queue rowは送信成功前に削除しない。retry時にbundleを再wrapしない。serverが同じlist IDへ異なるbundleを返した / 保持した場合は、上書き、local key差替え、entity pushを行わず明示的に停止する。
- capability preflightをkey bundle uploadより前に維持し、task-88のdurable upgrade block中はkey uploadを含むnetwork I/Oを行わない。key upload完了前にentity outboxを読まないことでbundle-before-recordを構造的に保証する。
- login / refreshのremote bundle集合を常に正本としてlocal pending keyを消さない。local cacheとremote bundleを同じMKで復号し、同じlist IDのDEK一致を確認した場合だけmergeする。local pendingをserver既存bundleより優先して上書きせず、remote集合だけでcacheを全置換もしない。同一profile / MK / list ID / DEKの検証に失敗した場合はpartial Readyにせずfail closedする。
- serverはbundleを復号せず、entity recordとの平文linkageを保持しない。将来List DEK rotationや共有listを実装するときは、本taskのimmutable generation 0へ暗黙の上書き例外を追加せず別ADRで世代条件を裁定する。
- release前方針に従い、誤った旧overwrite挙動やqueueなし経路の互換層を残さない。schema / APIを変える場合も正しい最終shapeへ直接置換する。
- 本taskが独立検証まで合格する前に、offline list作成またはbundle-before-recordをrelease-readyと表現しない。

## 8. 完了報告に含めるべき内容

- local queue / cache schema、idempotency key、immutable条件、保存metadataと秘密情報境界。
- production list createで生成・wrapした値と、単一transactionへ含めたcache / domain / state / outbox / HLC / queue、runtime再構成の境界。
- server create-if-absent wire outcome、same-bundle retry、different-bundle conflict、旧overwrite経路の除去。
- preflightからbundle upload / local ACK / entity push / pullまでの正確な順序と、network I/Oがtransaction外である証拠。
- 各local write failureの全rollback、server成功後local ACK failure、queue ACK後entity push前crashの回復結果。
- logout / session期限切れ / restart / loginを含むoffline→online recoveryと、production 2-client pull / decrypt gateの観測結果。
- task-86〜task-88 regression、migration、全品質ゲート、独立検証の結果。
- 本task外に残したkey rotation / sharing、aggregate削除、full resync / GCと、新たな未解決事項。
