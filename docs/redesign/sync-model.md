# Sync model

> 状態: 2026-07-23 product owner承認済みbaseline（未実装）

## 1. Goals

- networkを待たずlocal操作を確定する。
- serverがRecord plaintextをdecrypt、index、merge、scheduleしない。
- 複数deviceの通常編集を自動mergeし、同じfieldの競合も黙って捨てない。
- task、list、completion、comment、time tracking等を同じopaque Record protocolで扱う。
- completed historyを長期保持しつつ、every-edit revision logを無期限に増やさない。
- membership/key change、quota、permanent deleteでstale clientがdataを壊さない。
- protocolをCAS、client 3-way merge、immutable event、terminal Tombstoneの小さな組合せに留める。

## 2. Sync boundary

Spaceがaccess control、key generation、cursor、quota attribution、full resyncの境界である。Personal SpaceとShared Spaceは同じRecord protocolを使う。

server-visible:

- Space ID、type、membership、role、owner、current key generation。
- opaque record ID、revision ID、base revision ID、operation ID。
- author account/key version、ciphertext/signature、size bucket、Tombstone flag。
- Space-local monotonic server sequence、quota usage。

encrypted:

- Record kind、schema、field、relation、domain timestamp。
- list/task/tag/comment/completion/work session等の区別。
- task-to-list、parent/child、assignee、timer relation。

## 3. Record model

### 3.1 Record kinds

初期clientはciphertext内で少なくとも次を扱う。

- List、Section、Task、Tag。
- Comment、Completion Record。
- Work Session。
- Template、Saved Filter、Space Setting。
- Conflict Record。

Record kindをserver columnやrouteへ分けない。添付file/object protocolは存在しない。

### 3.2 Mutable and immutable

| Kind | Rule |
|---|---|
| Task/List/Section/Tag/Template/Saved Filter/Setting | 1 record IDにcurrent mutable headを持つ |
| Comment | edit可能だがedit markerを保持。permanent delete可能 |
| Completion Record | immutable。訂正はreversal/replacement relation |
| Work Session | immutable。訂正はcorrection Record、誤記録はpermanent delete |
| Conflict Record | 解決までimmutable candidateを保持し、resolution stateだけ更新 |
| Tombstone | terminal。contentなし。同じrecord IDをliveへ戻さない |

Taskがcompletedであり続けることとCompletion Recordは別である。Task current statusはviewを作り、Completion Recordはreopen後も成果履歴を残す。

### 3.3 Identifier

- Space、record、revision、operation IDはCSPRNGによる128-bit以上のrandom valueを使う。
- user timestampやemailをIDへ埋め込まない。
- same record IDをpermanent delete後に再利用しない。
- idempotent recurrence/completion等でdeterministic IDが必要な場合は、Space secret、series/command ID、occurrenceをdomain-separated PRFへ入れ、外からscheduleを推測できない値にする。exact constructionはADR/test vectorで固定する。

## 4. Local state

clientはSpaceごとに少なくとも次をencrypted DBへdurable保存する。

- materialized domain tablesとlocal search index。
- record IDごとのaccepted revision、base plaintext、generation、server sequence。
- local mutation outbox、operation ID、base revision/base plaintext。
- current/historical Space Key、membership revision、identity pin。
- pull cursorとserver delta-log lower bound。
- pending dependency、quarantine、Conflict Record。
- Tombstoneとnever-synced/server-acknowledged origin。
- quota/upload blocked state。

domain mutation、encrypted candidate、outbox、local logical counterは1つのlocal DB transactionでcommitする。network I/Oをこのtransaction内で行わない。

## 5. Server state and validation

### 5.1 Per Space

- Space row、current key generation、membership/role/owner revision。
- active memberごとのencrypted key envelopes。
- record IDごとのcurrent headまたはTombstone。
- monotonic `server_seq`。
- bounded delta log: `server_seq`, record ID, revision ID/Tombstone。
- quota bytesとidempotency operation result。

serverはplaintext revision historyを持たず、accepted current headを置換する。backup retentionは別運用policyに従う。

### 5.2 Read authorization

- active `owner`、`editor`、`viewer`だけがShared Spaceをreadできる。
- Personal Spaceはowner Accountだけがreadできる。
- removed/left memberのsessionは他Spaceで有効でも対象Spaceをreadできない。
- unguessable Space/record IDだけをauthorizationにしない。

### 5.3 Write validation

serverはaccepted mutationごとに次を順に検証する。

1. authenticated Account/sessionがactive memberである。
2. roleが`owner`または`editor`である。`viewer` writeは拒否する。
3. envelope author Accountがrequest Accountと一致する。
4. author identity key versionが有効で、outer envelope signatureが正しい。
5. key generationがSpaceのcurrent generationと一致する。
6. protocol version、suite、header shape、sizeがsupport範囲内である。
7. operation IDが既処理なら同じresultを返す。
8. `base_revision_id`がcurrent headに一致する。createはrecord ID未使用を要求する。
9. Tombstone済みrecord IDをliveへ戻していない。
10. mutation全体を受け入れてもquota内である。
11. head replacement、delta log、server sequence、quota、idempotency resultを1 transactionでcommitする。

serverはAEAD plaintext、domain schema、relation、task statusを検証しない。signatureが正しくてもciphertextをdecryptできないため、client validationは省略できない。

### 5.4 Tombstone

Tombstoneは次だけをouter envelopeとして持つ。

- Space/record/revision/base/operation ID。
- current key generation。
- author Account/key version。
- deletion markerとsignature。

旧ciphertextをTombstoneへ含めない。TombstoneはSpace存続中保持しquotaへ算入する。これにより、device expiry protocolやbounded tombstone GCを初期製品へ持ち込まず、stale resurrectionを単純に防ぐ。

## 6. Normal sync cycle

1. **Session**: server sessionとAccount security revisionを確認する。
2. **Membership/key refresh**: membership revision、current generation、必要なkey envelopeを取得・検証する。
3. **Pull**: local cursorより後のdeltaを取得する。delta log範囲外ならfull resyncへ移る。
4. **Verify**: signature、generation、AAD、AEAD、canonical encoding、schema、domain invariantを検証する。
5. **Materialize**: remote headをlocal accepted stateへtransactionalに反映する。local outboxと競合する場合はmerge candidateを作る。
6. **Rebase**: old generationのlocal unsent mutationをcurrent generationで再暗号化し、current remote headへ3-way mergeする。
7. **Push**: outboxをdependency順にCAS uploadする。
8. **Resolve CAS**: conflict responseをdecryptし、3-way mergeしてnew revisionをpushする。
9. **Advance cursor**: pull結果とlocal materializationがcommitした後だけcursorを進める。
10. **Wake-up**: generic pushはこのcycleを開始するhintであり、正本ではない。

Membership/key refreshをentity pushより前に行う。これにより、removed member、old generation、owner transitionを知らないstale writeを先に送らない。

## 7. Three-way merge

clientは`base`、`local`、`remote current`をdecryptしてtyped schemaごとにmergeする。任意JSONにgeneric LWW clockを付けない。

### 7.1 Common rule

- localだけがbaseから変わったfield: local。
- remoteだけが変わったfield: remote。
- 両方が同じ値へ変わったfield: その値。
- 両方が異なる値へ変わったfield: domain ruleがあれば適用し、なければremote currentを一時表示値として採用し、両candidateを含むencrypted Conflict Recordを作る。

Conflict Recordは片方をlossy logへ落とすのではなくSpaceへ同期する。利用者が選択/編集するとtarget Recordへnew revisionを書き、Conflict Recordをresolvedにする。

### 7.2 Compound fields

意味上atomicな組を分割mergeしない。

- task status、completed/wont-do reason、current completion reference。
- due kind/date/time/timezone。
- placement: list ID、section ID、parent task ID、rank。
- recurrence ruleとtimezone/anchor。
- timer started/ended/active duration。

同じcompound fieldを両方が変えた場合はConflict Recordにする。

### 7.3 Collections

- tag/assignee等の集合はelement単位のadd/remove operation IDをplaintext内に持ち、独立elementの変更をmergeする。
- 同じelementへのconcurrent add/removeはdomain ruleを明示する。初期baselineはremove-winsとし、candidateをConflict Recordへ残す。
- comment、Completion Record、Work Sessionは別record IDなので通常は集合追加として共存する。
- manual rank collisionはrankとrecord IDのstable tie-breakで表示し、clientが必要時にrankをrebalanceする。

### 7.4 Completion

- complete commandはTask status revisionとimmutable Completion Recordを同じlocal transaction/outbox batchへ入れる。
- retryは同じoperation/Completion Record IDを使う。
- concurrent editとcompletionは異なるfieldならmergeする。
- concurrent completeはCompletion Recordのcommand IDが同じならdeduplicateし、別actor/commandなら両方を履歴に残してTask current stateを1つへ収束させる。
- reopenはTask statusを変更するが、過去Completion Recordを削除しない。

## 8. Atomic batch

次は複数Recordでもall-or-nothing server transactionを要求する。

- Task complete + Completion Record作成。
- 同じSpaceにあるrelated Recordを含むpermanent delete batch。
- recurring next occurrence settlement。
- owner/membership/key-generation transition。

batchは1 Space内に限定し、全operationのauthorization、generation、CAS、quotaを検証してからcommitする。cross-Space moveはsource deleteとdestination createをlocal workflowで調整するが、distributed transactionとして「完全atomic」と表示しない。失敗時はcopy完了を確認してからsource archive/deleteをretryする。

## 9. Full resync and recovery

delta logのlower boundよりcursorが古い、local stateが破損した、new deviceである場合はfull resyncする。

1. membership/keyringを取得・検証する。
2. Spaceのcurrent heads/Tombstonesをpage取得する。
3. staging tablesでsignature/decrypt/schema/relationを検証する。
4. dependency順にmaterializeし、unresolved relationをpending/quarantineへ置く。
5. remote-acknowledged local rowでserver current/Tombstoneにないものを勝手にre-uploadしない。permanent deletionまたはcorruptionとしてreviewする。
6. never-synced local Recordはrecord ID未使用、parent dependency有効、current generationへre-encrypt可能ならoutboxへ保持する。
7. validation完了後にstagingとcurrent stateをatomic swapする。

new deviceはserver responseだけを初回正本として受けるため、malicious serverの完全なforkを検出できない。既存deviceとのcheckpoint比較または将来transparency serviceは別設計とする。

## 10. Referential integrity

serverはRecord relationを知らないためclientが維持する。

- Task parent、list、section、tag、assignee等のstructural relationではcycle、cross-Space reference、missing target、invalid assigneeを拒否する。
- Personal SpaceのWork SessionからShared Taskへの`(space_id, record_id)`は唯一のsoft external referenceとして許可する。通常のreferential-integrity対象にせず、encrypted display snapshotをWork Session内へ保持する。
- parent/listがまだ未到着ならpending dependencyへ置き、通常UIへ孤児として出さない。
- parent/listのTombstoneがあるlate childはmaterializeせず、自身のTombstoneをenqueueする。
- permanent task delete時はclientが知る同じSpaceのComment、Completion Record等を同じbatchでTombstone化する。
- Personal Work Sessionのsoft external referenceはTask delete、member removal、Shared Space access喪失でcascade deleteしない。Taskを解決できない場合はsnapshotを表示し、linkをunavailableとして扱う。
- 別offline clientが後から未知のrelated Recordを送った場合、受信clientがdeleted relationを検出してTombstoneへ収束させる。

このclient-side cascadeはhonest server access controlの下でeventual convergenceを提供する。serverがrelation metadataを持たないため、malicious serverによるselective omissionを完全には証明しない。

## 11. Key generation and progressive re-encryption

- serverはcurrent generation以外のnew mutationを拒否する。
- old-generation Recordを読むだけではrewriteしない。
- edit、completionに伴うTask update、conflict resolution、correction等でRecordを更新するとき、whole Recordをcurrent generationで暗号化する。
- fieldだけを別generationで暗号化するhybrid Recordを作らない。
- old Recordに対するconcurrent editがremovalをまたいだ場合、active member clientはmembership/key refresh後にplaintextをmergeし、current generationでnew revisionを作る。
- removed memberのoutboxはserver RBACで拒否し、new keyを得られないためrebaseできない。
- background bulk re-encryptionは初期製品で自動実行しない。

## 12. Quota behavior

- serverはactual stored encrypted bytesをSpaceへ計上し、Space owner Accountのquotaへ1回だけ加算する。
- owner transferはquota attributionも移す。targetにcapacityがなければtransfer前に解決を求める。
- editor uploadもSpace owner quotaを消費するため、serverはbatch commit時にowner quotaを検査する。
- quota exceededではnew/expanded live mutationを拒否するが、pull、existing data download、Tombstone/permanent delete、Account exportに必要なreadを許可する。
- storageを減らすTombstone batchはquota超過中も受け入れる。
- clientはrejected outboxをdurable保持し、automatic retry stormを避けるbackoffと明示状態を持つ。
- serverは古いcompleted Recordを自動purgeしない。

価格、free quota、grace periodは本設計のscope外である。

## 13. Push notification

- push payloadはAccount/device routing用opaque wake-up tokenとcoarse reasonだけを持つ。
- Space名、Task title、due、author、commentを入れない。
- push providerはAccount/deviceとwake-up timingを観測できるためserver-visible metadata inventoryへ含める。
- push deliveryなしでもforeground/polling/full resyncで同じstateへ収束する。

## 14. Failure handling

| Failure | Client behavior |
|---|---|
| auth expired | local edit継続、outbox保持、再認証を促す |
| membership removed | 対象Shared Spaceをread-only/closedにし、new mutationを作らない |
| generation stale | key refresh、active memberならcurrent generationへre-encrypt |
| CAS conflict | typed 3-way merge、必要ならConflict Record |
| quota exceeded | local edit/outbox保持、read/export/delete継続 |
| signature/AEAD failure | quarantine、適用しない、security-visible error |
| schema unknown | upgrade required、fallback deserializeしない |
| dependency missing | pending、bounded retry後も通常UIへ出さない |
| server cursor rollback | local highest cursorより後退なら拒否/警告 |
| local DB transaction failure | domain/outboxを全rollback |

## 15. Deliberately excluded complexity

- operation logを永遠にreplayするevent sourcing。
- arbitrary JSON field clocks。
- server-side plaintext merge。
- message ratchet、per-message key deletion、MLS tree。
- distributed active-timer lock。
- bounded Tombstone GCとexpired-device lease。
- server-visible list/task/hierarchy scope。
- cross-Space distributed transaction。

必要性が実測で生じたものだけを、threat modelとmigrationを伴う個別ADRで追加する。
