# task-88: typed pull + durable quarantine

> ステータス: 独立検証待ち（worker実装・品質ゲート完了、合否未判定）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

task-86 / task-87により、protocol v2のbase revision CAS、typed field clock、production CRUDを通る同時別field編集、transactional placement/rankまで実装した。一方、現行pullはmissing DEK、AEAD認証失敗、破損envelope、未知envelope version、typed plaintext検証失敗をすべて`Deferred`または汎用`sync failed`へ潰している。`run_sync_now`はrecordごとにdomain / sync stateをcommitした後、page cursorを別connectionでcommitするため、途中失敗やcrashでpageの一部だけが適用される。また、復号不能recordは永続保存されないままcursorが進み、task-80で確認した取りこぼしを再発させる。

ADR-012は、missing DEKをkey bundle refresh後に1回再試行し、なお処理不能なrecordをdurable quarantineへ保存してcursorを安全に進めること、unknown protocolをupgrade-requiredとしてpush / pullを停止すること、pageの適用・state・repush・quarantine・cursorを同一local transactionで確定することを要求している。本taskはlocal schema、鍵refresh、同期停止条件、データ回復性へ触れる重要変更レーンである。今回のプロダクトオーナー依頼を着手承認として扱い、task-86 / task-87のCAS・typed merge不変条件を維持したまま実装する。

## 2. 事前に読むべきファイル

- `docs/05_設計判断記録.md` ADR-012、ADR-014
- `docs/03_技術仕様書.md` 6章、11.1節
- `docs/tasks/task-80-sync-pull-recovery.md`
- `docs/tasks/task-82-sync-correctness-redesign.md`
- `docs/tasks/task-86-protocol-v2-cas.md`
- `docs/tasks/task-87-typed-field-clock-placement-rank.md`
- `core/sync/src/{protocol,engine,envelope,apply,enqueue,keys}.rs`
- `core/storage/src/{lib.rs,schema.sql}`
- `app/rust/src/{support,sync_store,api}.rs`
- `server/src/{routes/sync.rs,sync.rs}`

## 3. ゴール

- pull失敗を型付きにし、missing key、認証失敗、既知versionの破損、未知envelope / protocol versionを異なる回復方針へ接続する。
- missing DEKをtransaction外のkey refresh後に同じpage / recordで1回だけ再試行し、なお不足するrecordとcorrupt recordを暗号文のままdurable quarantineへ保存する。
- unknown protocol / envelopeをupgrade-requiredとして明示し、outbox push、後続pull、cursor前進を停止する。
- pull pageのdomain apply、sync record state、HLC observe、merge repush outbox、quarantine、cursorを1つの`BEGIN IMMEDIATE`で確定する。
- quarantineを後から再適用し、成功した適用と解決 / 削除を同じtransactionで確定できるようにする。
- production / common adapterと実SQLite storeを通る回復・停止・rollbackテストをrelease gateにする。

## 4. スコープ

### やること

- `core/sync`に型付きpull分類を導入する。少なくとも`MissingDek`、key identityを特定できないtask用の`NoMatchingDek`、`AuthenticationFailed`、既知versionの`CorruptEnvelope` / `InvalidPlaintext`、`UnsupportedEnvelopeVersion`、`UnsupportedProtocolVersion`、既知protocolの不正responseを区別する。`Unsupported*`はupgrade-required、既知protocolの構文・clock・base64不正はpage全体のhard failure、missing / corruptだけをquarantine可能とする。汎用`Deferred`や`decrypt_failed_count`だけで判断しない。
- sync HTTPに明示的なprotocol / envelope capability preflightを設け、対応versionを確認してからoutboxを読む・pushする。未知versionはtyped `UpgradeRequired`としてそのrunのpush / payload pullを開始せず、local cursorとoutboxを変更しない。防御としてpull page内で未知envelopeを検出した場合もpageをrollbackし、後続I/Oとcursor前進を停止する。
- missing keyを検出した最初のpage attemptは未commitのまま破棄する。SQLite write transactionを閉じた後、production key-bundle経路で1回だけnetwork refreshし、local key cache / runtime key setを更新して同じpage全体を再実行する。1 page内の複数recordでrefreshを反復しない。refresh自体が失敗した場合はcorruptionへ誤分類せずrunを失敗させ、cursorを保持する。refresh成功後も不足するkeyはquarantineへ保存する。
- key identityを確定できるlistまたは既知taskは、期待DEKの不在と期待DEKによるAEAD認証失敗を分ける。list IDが暗号境界内にありlocal placementもない新規taskは、全candidate DEK不一致を`NoMatchingDek`としてkey-retry可能なquarantineへ保存し、根拠なくcorruptionへ断定しない。server-visibleな平文`list_id` / placementを追加しない。metadata leakageを増やすkey selectorが必要になった場合は実装を止め、別ADRとプロダクトオーナー裁定へ戻す。
- local schemaへdurable quarantineを追加する。rowは少なくともserver `seq`、record ID、collection、`revision_hlc`、live / tombstoneのtagged semantic metadata、live時の受信encrypted blob、型付きreason、first / last failure時刻、attempt countを保持し、同じ受信recordの再試行をidempotentにする。plaintext、DEK、Master Key、session token、詳細なcrypto error文字列は保存・ログ出力しない。
- pullはpage単位で1つのowned `BEGIN IMMEDIATE`を使う。page内全recordのdomain apply / delete、remote HLC observe、typed record state、CAS merge repush head、quarantine upsert / resolve、`SYNC_CURSOR_NAME`更新を同じtransactionに含める。cursorはpageの全recordが適用またはquarantineへ永続化された場合だけ`next_since`へ進め、どのwrite failure / panic相当crash windowでもpage全体をrollbackする。
- unresolved quarantineをsync開始時またはkey refresh成功後に再適用する。現在のtyped merge / semantic fenceを通し、成功時はdomain / record state / repush / HLCとquarantine解決・削除を同じtransactionで確定する。再適用失敗時はreason / attemptを安全に更新し、未知versionはupgrade-requiredへ昇格する。新しい有効revisionが同recordの古いquarantineをsupersedeする場合も、解決とcurrent applyを同じtransactionで行う。
- push conflict / supersededの`current`も同じtyped分類を使う。ただしcurrentを適用またはreplacement headへrebaseできない限り、task-86のstale outbox headをACKせず、pull cursorとも混同しない。
- `SyncRunSummary` / bridge statusはmissing-key quarantine、corruption quarantine、resolved件数、upgrade-requiredを観測可能な非機密状態として表す。FRB公開型を変える場合は2.12.0固定でcodegenし、生成物を手編集しない。`docs/03_技術仕様書.md`は最終のfailure taxonomy、quarantine schema、page transaction / retry境界へ外科的に同期する。

### やらないこと

- fuzzy-scan full resync、GC horizon、`410 Gone` continuity recovery、mark-and-sweep。
- offline list作成、List DEK生成、key-bundle upload queue、server key bundle upsert世代管理。
- aggregate list / subtree削除scope、epoch、未知descendantの削除保証、List DEK bundle削除。
- task-86のCAS wire / current-head / op ID ACK、task-87のtyped payload / field clock / rank契約の再設計。
- quarantine内容のUI一覧、手動破棄UI、復号済み内容の診断ログ、server側での暗号blob解釈。
- protocol v1、旧envelope、旧local sync metadataとのfallback、dual read / write。

## 5. 実装手順

1. missing key、期待DEKでのauth failure、corrupt typed plaintext、unknown envelope / protocol、page途中failure、quarantine replayの失敗テストを先に追加し、現行のsilent skip / partial commitを再現する。
2. protocol / envelope / apply errorを型分離し、push前protocol capability preflightとtyped `UpgradeRequired` outcomeを`core/sync` / serverへ実装する。
3. local schema migration、quarantine型 / repository、owned transaction操作を`core/storage`へ追加し、`BridgeSyncStore`のproduction / transaction adapterへ同じsurfaceを接続する。
4. pullをpage coordinatorへ組み替える。最初の`BEGIN IMMEDIATE` attemptでmissing keyを検出したら全rollbackし、transaction外でkey refreshを1回だけ実行してpageを再試行する。2回目は成功recordとdurable quarantineをcursorと同時commitする。
5. unresolved quarantineの再適用、成功時の解決 / 削除、新revisionによるsupersede、push conflict currentのoutbox保全をtyped apply経路へ接続する。
6. production/common adapter、暗号化SQLite、可能なら実HTTP/Postgresの2-client scenarioでrelease gateを追加し、refresh回数、cursor、quarantine row、domain/state/repush、outbox停止を直接観測する。
7. 技術仕様を最終shapeへ同期し、独立verifierがtask-86 / task-87不変条件、transaction境界、crypto metadata、全品質ゲートを再実行する。

## 6. 受け入れ基準

- [ ] pull failureが`MissingDek` / `NoMatchingDek` / `AuthenticationFailed` / 既知version corruption / unsupported envelope / unsupported protocol / invalid known-protocol responseへ型分類され、silent skipまたは汎用`Deferred`だけでcursorを進める経路がない。
- [ ] protocol / envelope capability preflightがoutbox読取・pushより先に実行され、unsupported versionでは`UpgradeRequired`が観測でき、push / payload pull / outbox ACK / cursor更新が0件である。page内の未知envelopeもpage全rollbackと後続停止になる。
- [ ] missing keyはSQLite write transactionを保持せずproduction key-bundle refreshを1回だけ行って同じpageを再試行する。refresh成功後に取得できたrecordは適用され、refresh失敗時はcursor不変、なお不足するrecordはmissing-key quarantineとなる。
- [ ] missing-key / auth failure / corrupt plaintextのquarantine rowが受信encrypted blobまたはtagged tombstone、seq、record ID、collection、revision / semantic metadata、型付きreason、attempt / timestampを保持し、plaintext・鍵・tokenを含まない。同一record / seqの再処理は重複rowを作らない。
- [ ] page内のapply / delete、remote HLC、record state、merge repush outbox、quarantine upsert / resolve、cursorが単一`BEGIN IMMEDIATE`でcommitされる。各write地点へfailureを注入するとdomain・state・outbox・quarantine・cursorがすべてpage開始前へrollbackする。
- [ ] quarantineは後続key refreshまたは新しい有効recordで再適用でき、成功したdomain/state/repushとquarantine解決・削除がatomicである。再適用失敗はdataを失わず、unsupported versionはcursorを動かさずupgrade-requiredへ遷移する。
- [ ] push conflict / superseded currentが処理不能な場合、stale local outbox headをACKせず、処理可能な場合だけcurrent適用またはreplacement head生成と同一transactionで進む。task-86 CASとtask-87 typed field mergeの既存release gateが継続成功する。
- [ ] production/common adapterと実SQLite storeを通るrelease gateで、少なくとも2-clientまたは実HTTP/Postgres scenarioにより、missing DEK refresh成功、missing DEK継続quarantine + cursor前進、corrupt quarantine + cursor前進、unknown version停止、crash rollback、quarantine再適用を観測できる。fixtureがstore内部へ直接完了状態を注入しない。
- [ ] key refresh / HTTPがlocal write transaction内で呼ばれないことをinstrumented testで確認し、同一pageの複数missing recordでもnetwork refreshが1回である。quarantine済み個別recordはpreflight成功後の無関係なlocal pushを永久停止させない。
- [ ] schema migration、技術仕様、README共通品質ゲート、Docker/Postgresを含むworkspace test、必要なFlutter / FRB gate、`git diff --check`が成功し、独立verifierがP1 / P2なしの根拠を返す。

## 7. 制約・注意事項

- HTTP、protocol preflight、key bundle取得、runtime key更新をpage write transaction内で行わない。missing keyを検出したtransactionは必ずrollbackしてからnetworkへ出る。
- quarantineは「捨ててもよいrecord」ではない。cursor前進を許す代わりに、受信stateを再適用可能な形でSQLCipher DBへ永続化する。成功確認前のdelete、件数上限による無通知eviction、ログだけの代替を禁止する。
- unsupported versionをcorruption quarantineへ降格しない。新しいversionを古いclientが破損扱いしてcursorを進めると回復不能になるため、upgrade-requiredはrun全体の停止条件とする。
- known-version corruptionとkey refresh失敗を混同しない。network failure時はcursorを保持して再試行可能にし、crypto failureの詳細を外部へ露出しない。
- serverはplaintextを解釈しない。task-to-list placement、field clock、quarantine reasonをserver schemaへ追加しない。新しいserver-visible key selectorやmetadata linkageは本taskの暗黙判断で追加しない。
- cursorは`next_since`をrecordごとに書かず、page transactionの最後に一度だけ更新する。page再試行とquarantine upsertは冪等にする。
- remote HLC observeやmerge repushをquarantine確定より先に別commitしない。quarantine再適用もproduction typed merge / semantic live-delete fenceを迂回しない。
- 本taskが独立検証まで合格する前に、復号不能recordの回復性またはpull cursorをrelease-readyと表現しない。

## 8. 完了報告に含めるべき内容

- final failure taxonomyと、各型のretry / quarantine / upgrade-required / hard-failure方針。
- protocol / envelope preflightのwire shapeと、push前停止を確認した証拠。
- quarantine schema、暗号blob / metadata保持範囲、idempotency key、解決 / 削除条件。
- missing DEK検出からtransaction rollback、1回refresh、page再実行までの正確な順序と、network I/Oがtransaction外である証拠。
- page transactionに含めたdomain / state / HLC / repush / quarantine / cursorと、failure injectionによる全rollback結果。
- quarantine再適用、新revision supersede、push conflict currentのoutbox保全結果。
- production/common adapter release gate、migration、全品質ゲート、独立検証の結果。
- 本task外に残したfull resync / GC、offline list作成、aggregate削除と、新たな未解決事項。

## 9. 完了報告

- 作業日: 2026-07-10
- Worker結果: pull failureを`MissingDek`、`NoMatchingDek`、`AuthenticationFailed`、`CorruptEnvelope`、`InvalidPlaintext`、unsupported envelope/protocol、invalid known-protocol responseへ分離した。missing系はtransaction外key refresh後に同pageを1回再試行し、継続missingとknown-version corruptionだけをquarantineする。unsupportedはupgrade-required、known protocolの不正base64 / clock / response shapeはcursorを動かさないhard failureとした。`NoMatchingDek`はlist linkageを特定できない新規taskの全candidate認証不一致で用い、corruptionへ断定しない。
- Preflight / durable block: `GET /v2/tenants/{tenant_id}/preflight`が`{ protocol_version, envelope_version }`を返し、clientはoutbox読取より先に両値を確認する。unsupported値はrequired `protocol:envelope`をSQLCipher settingへ保存し、同client version中の後続runはnetwork I/Oを行わない。将来supported constantsがrequired値へ追いついたclientはblockを論理解除してpreflightを再確認できる。`unsupported_preflight_durably_blocks_outbox_before_push`でpreflight 1回、push 0回、outbox保持、cursor未作成、2回目network 0回を確認した。
- Schema / quarantine: local schema v13で`sync_quarantine`を追加した。record IDをidempotency keyとするlatest-head rowがcollection、server seq、revision HLC、live/tombstone tag、semantic HLC、live暗号blob、型付きreason、optional required list ID、first/last failure時刻、attempt countを保持する。plaintext、鍵、token、詳細crypto errorは保持しない。同revision再試行はattemptだけを増やし、新revisionはheadを置換する。quarantine recordのoutbox row自体は保持し、`list_outbox_heads`だけがそのrecordを除外するため無関係なpushは継続する。
- Transaction / key refresh: page初回はowned `BEGIN IMMEDIATE`でdomain apply/delete、remote HLC observe、typed record state、merge repush outbox、quarantine upsert/resolveを実行する。missing系を検出したtransactionはdropして全rollbackし、HTTP key refreshとruntime/SQLCipher key cache更新をtransaction外で1回だけ行い、同page全体を再実行する。page末尾でcursorを1回だけ書き、commit成功後にだけsummaryへ件数を反映する。refresh失敗はcursor/quarantine/domainを変更しない。
- Replay / supersede / conflict: sync開始時にunresolved missing系quarantineがあればtransaction外refresh後、現在のtyped merge / semantic fenceを通して再適用する。成功時のdomain/state/repush/HLCとquarantine deleteは同一transactionで確定する。新しい有効revisionのpage適用も古いquarantineを同transactionでsupersedeする。push conflict/superseded currentの適用不能時はACKを含むtransactionをrollbackするためstale outbox opを保持する。個別quarantine recordだけがpush列挙から外れ、unrelated outboxは停止しない。
- Production release gate: `production_pull_refreshes_once_then_atomically_applies_and_quarantines`をDocker/Postgres、real Axum HTTP、`BridgeSyncStore`、SQLCipher DBで実行した。同pageの複数missingに対するrefresh 1回、valid record適用、継続missing quarantine、認証失敗quarantine、cursor前進を観測した。後続runでmissing quarantineを再適用し、serverの新しいvalid revisionでauth quarantineをsupersedeした。refresh failureではcursor/domain/quarantineが不変、page末尾のunknown envelopeでは先行valid applyを含めdomain/state/outbox/quarantine/HLC/cursorが全rollbackしdurable upgrade blockへ遷移した。
- Failure matrix: production adapterのSQLite triggerで`sync_record_states` insert、`sync_quarantine` insert、`sync_cursors` insertを各々失敗させた。各caseでlists、record state、outbox、quarantine、cursor、`sync_local_hlc`をpage開始前の0件へrollbackした。既存`undecryptable_conflict_current_keeps_the_local_outbox_head`も成功した。
- Bridge /暫定回復退役: `SyncRunSummary` / `SyncStatusDto`へmissing-key quarantine、corruption quarantine、resolved件数、upgrade-requiredを追加し、FRB 2.12.0 codegenを実行した。login/registerは初回backfill cursorだけをresetし、task-80の暫定`main` pull cursor resetを退役した。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`（server sync 7件、client 22件、sync 49件、storage 67件成功/1件ignored、bridge 2件を含む）、bridge release build、`flutter analyze`、`flutter test`（124 passed / visual QA harness 1 skipped）、hardcoded-string check、`git diff --check`が成功した。
- Commits: `313b451`、`1d39772`、`67a2d1a`、`9395a9a`（本仕様・worker報告commitは後続）。
- 独立検証: 未実施。workerは合否判定、task完了化、`STATUS.md`完了同期を行っていない。
- 本task外: fuzzy-scan full resync / GC horizon、offline list作成 + key-bundle upload queue、aggregate list/subtree削除scope / epochは変更していない。serverへplaintext、placement、field clock、quarantine reason、平文list linkageを追加していない。
