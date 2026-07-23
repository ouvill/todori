# Sharing model

> 状態: 2026-07-23 product owner承認済みbaseline（未実装）

## 1. Scope

初期共有は、家族・partner・友人のsmall groupでTODO listを共同管理するための機能である。enterprise organizationの縮小版にはしない。

- 共有の暗号・認可単位はShared Spaceである。
- 初期UIでは1 Shared Spaceを1共有listとして見せる。
- data modelはSpace内にList Recordを置くため、将来複数list UIへ拡張できるが、初期製品の約束にはしない。
- Shared Space membershipとroleをserverは知る。
- Space表示名、list名、Task、comment、assignee等はE2EEにする。
- public link、guest、anonymous user、Account全体の共有、Task単体の共有は行わない。

## 2. Roles

| Action | owner | editor | viewer |
|---|---:|---:|---:|
| Read/decrypt content | yes | yes | yes |
| Create/edit/complete content | yes | yes | no |
| Permanent delete content | yes | yes | no |
| Invite/cancel invite | yes | no | no |
| Change role/remove member | yes | no | no |
| Rotate Space Key | yes | no | no |
| Transfer ownership/delete Space | yes | no | no |
| Leave | transfer/delete first | yes | yes |

Rules:

- Shared Spaceには常に正確に1 ownerがいる。
- owner自身をviewer/editorへ変更できない。先にowner transferする。
- serverはrequestごとにroleを検証する。
- clientはserver roleだけに依存せず、membership manifest、current generation、author signatureを検証する。
- viewerはSpace Keyを持つためplaintextを読めるが、valid editor/ownerとして署名されたmutationを作る権限はない。viewer自身のAccount signatureが正しくてもserver/clientはwriteを拒否する。
- editorのpermanent deleteをowner-onlyにするSpace optionは初期製品へ入れない。例外を増やす代わりにdeep confirmation、Completion Record、Conflict Recordで誤操作を緩和する。
- Editorは全contentを改変・permanent deleteできる。招待とrole変更の確定前にこの破壊権限をowner/targetへ表示し、readだけならviewerを選ぶよう案内する。
- Signatureはdestructive mutationのactorを検証するが、current-head-only storageから削除前contentを復元しない。Shared Spaceをbackupと表示せず、ownerは必要に応じてuser-controlled exportを保管する。

## 3. Membership state

server-side state:

```text
invited -> accepting -> active -> removal_pending -> removed
                              \-> leaving -> removed
```

- `invited`: one-time invitationはあるがAccount membershipはまだない。
- `accepting`: recipient identityをownerが確認し、keyring envelopeを準備中。
- `active`: read/writeはroleに従う。
- `removal_pending`: accessを停止し、new key generation commitが完了するまでSpace writeをfreezeする短期state。
- `removed`: read/write/key deliveryを拒否する。

Normal addはcurrent content writeをfreezeしない。Removal/leaveはold key holderを除くnew generationが必要なため、server transaction完了まで短時間writeをfreezeする。

## 4. Signed membership manifest

clientが検証するcanonical manifestは次を持つ。

```text
space_id
membership_revision
current_key_generation
owner_account_id
members [
  account_id,
  role,
  identity_version,
  signing_key_fingerprint,
  hpke_key_fingerprint,
  state
]
previous_manifest_digest
transition_kind
owner_signature
target_acceptance_signature | null
```

- ownerはexpected previous revision/digestへ対するtransitionを署名する。
- owner transferだけはtarget ownerのacceptance signatureも必須にする。
- serverはsame expected revisionから1 transitionだけをatomic commitする。
- active clientはsignature、previous digest、monotonic revision/generation、exactly-one-ownerを検証する。
- manifest plaintextをserverから隠さない。server RBACとclient cryptographic viewを一致させるための意図的metadataである。
- old manifest/transitionとpublic identity key historyはold Record signature/roleとmanifest chainの検証に必要なためSpace存続中保持し、quotaへ算入する。

これはglobal transparency logではない。serverのselective forkを完全には防げないが、同じclientへの単純rollback、owner以外のrole変更、ownerが0/2人になるtransitionを検出する。

## 5. Invitation

### 5.1 One-time invitation

1. ownerはShare操作で256-bit invitation secret、random invite ID、expiryを作る。
2. owner identity fingerprint、Space invitation metadata、intended roleをsecretでAEAD暗号化し、serverへuploadする。
3. link/QRはserverへ送るinvite IDと、URL fragment/QRだけに入るsecretを持つ。
4. recipientはTaskveil clientで開き、login/create Accountする。
5. recipient clientはpackageをdecryptし、owner identityをpinし、自身のsigned public identity acceptanceをsecretで暗号化してuploadする。
6. owner clientはacceptanceをdecryptし、表示Accountとidentityを確認する。
7. owner/recipient UIはintended role、historical access、editorなら改変・permanent delete権限を表示して確定する。
8. ownerはrecipientへhistorical keyringをHPKE encryptし、add transitionを署名する。
9. serverはinvitation unused/expiry、owner role、expected membership revision、recipient Account、key envelopeを1 transactionで検証しmembershipをactiveにする。
10. recipientはmanifest、owner signature、keyring、Space dataを検証して表示する。

### 5.2 Security properties and limits

- URL fragment secretはHTTP requestに含まれず、server単独のpublic key substitutionを防ぐbootstrap secretになる。
- linkを得た第三者は参加を試みられるため、one-time、short expiry、cancel、rate limit、recipient Account表示を必須にする。
- ownerがlinkを誤送信した場合、E2EEは相手のidentityを保証しない。owner confirmationで止める。
- invitation secretをanalytics、referrer、clipboard log、crash reportへ出さない。
- high-assurance useではowner/recipientがSafety CodeをQRまたは数字で比較できる。

## 6. New member and historical access

「new memberも過去のdataを閲覧可能」は明示的なproduct contractである。

- ownerはcurrent keyだけでなく、未削除Recordに必要な全historical Space Key generationをkeyringとしてrecipientへ送る。
- recipientは各Recordの`key_generation`に対応するkeyで過去/current dataをdecryptする。
- Completion Record、comment、Work SessionにShared Spaceで保存されているdataも同じscopeで見える。ただし個人Work SessionはPersonal Spaceに置くため共有されない。
- Tombstoneはcontentを持たないためnew memberはpermanent deleted contentを読めない。
- serverは「join後だけ」をfilterしない。active memberはShared Spaceのcurrent headsを全件readできる。
- owner UIは「招待すると、この共有listの過去の未削除dataも見える」と確定前に表示する。

New memberごとにRecordを再暗号化しない。Space Keyをrecipient public keyへ暗号化するだけである。

## 7. Role change

- ownerがtarget Account、old/new role、membership revisionを確認してmanifest transitionへ署名する。
- serverはexpected revision、owner role、target active、exactly-one-ownerを検証しatomic commitする。
- editorからviewerへの変更ではSpace Keyをrotationしない。viewerも同じplaintext accessを持つためconfidentialityは変わらない。
- viewerからeditorへの変更でもkey rotationしない。write authorizationと署名検証だけが変わる。
- role change前に取得したplaintext/write draftを遠隔消去できない。

## 8. Member removal

### 8.1 Required transaction

owner clientがactive memberをremoveするとき:

1. latest manifestとcurrent generationをpullする。
2. fresh random Space Keyを生成し、generationを`N + 1`にする。
3. removed memberを除くactive memberごとにnew key envelopeをHPKEで作る。
4. removed member、new generation、new key-envelope digestを含むmanifest transitionをownerが署名する。
5. serverへexpected membership revision付きatomic requestを送る。
6. serverは一時的にSpace writeをserializeし、owner/target/revision/signature/envelope completenessを検証する。
7. serverはtarget access revoke、new manifest/current generation/key envelopesを同じtransactionでcommitする。
8. commit後、serverはremoved Accountのread/writeを拒否し、全Accountによるold-generation writeを拒否する。
9. remaining clientsはnew manifest/keyをpullし、以後new/edited Recordをgeneration `N + 1`で暗号化する。

new key deliveryに失敗したmemberがいる場合はremoval transaction全体をcommitしない。serverがSpace Keyを生成または補完しない。

### 8.2 No bulk re-encryption

- generation 1..NのRecordをremoval時に一括再暗号化しない。
- old Recordはold generationのままreadできる。
- remaining memberがold Recordをeditすると、whole Recordをcurrent generationで暗号化する。
- backgroundで自動bulk migrationしない。
- old keysはold Recordとnew member historical accessのためactive member keyringに保持する。

### 8.3 What removal guarantees

- honest serverはremoved AccountのSpace API accessを直ちに拒否する。
- removed memberはnew Space Keyを得ず、除外後のnew/edited Recordをdecryptできない。
- removed memberのoffline outboxはserver RBACとold-generation checkで拒否される。

Removalが保証しないこと:

- removed memberが既にdownload/decryptしたpast dataの消去。
- old generationのunchanged Recordをremoved memberが忘れること。
- active memberがremoved memberへplaintext/new keyを再共有しないこと。
- malicious serverがremoved memberへold ciphertextを返さないこと。old keyで読めるdataは既にaccess済みとみなす。

## 9. Member-initiated leave

editor/viewerはleaveをrequestできる。

1. serverはmemberを`leaving`としてnew read/writeを止め、Space writeを短時間freezeする。
2. ownerへgeneric wake-upを送り、owner clientがmember removalと同じnew-generation transactionをcommitする。
3. commit後にmemberを`removed`とする。

ownerがofflineの間、remaining memberがold keyでnew contentを作るとleaving memberもcryptographically読めるため、Spaceはwrite-frozenのままにする。これはavailability上のtrade-offであり、serverにSpace Key生成を許すより安全で単純である。

初期productはleave開始前に「ownerがkey更新するまで共有listの編集が一時停止する場合がある」と説明する。長期owner不在を避けるためowner transferを提供する。

## 10. Owner transfer

Owner transferはmembershipを変えないため通常key rotationを必要としない。

1. current ownerがactive editorをtargetに選ぶ。
2. owner clientは`owner -> editor`、`target editor -> owner`、expected revision、quota attribution移行を含むproposalへ署名する。
3. target clientはproposal内容、Space、quota impactを表示し、acceptance signatureを返す。
4. current owner clientまたはtarget clientが両signatureをserverへ送る。
5. serverは両Account active、target editor、proposal expiry、same revision、quota capacity、exactly-one-ownerを検証する。
6. serverは2 role、owner field、quota attribution、manifest revisionを1 transactionでcommitする。
7. all clientsは両signatureとnew manifest chainを検証する。

Rules:

- target acceptanceなしのforced transferはしない。
- transfer requestはexpiry/cancelを持つ。
- targetがviewerなら先にeditorへrole変更する。1 requestへ例外的に混ぜない。
- outgoing ownerはdefaultでeditorになる。
- transferとmember remove/addを同じtransitionに混ぜない。
- transfer中もold ownerが唯一ownerであり、commit後はtargetが唯一ownerになる。
- Account support、server operator、課金者だけを理由にownerを書き換えない。

## 11. Space deletion

- ownerだけがShared Spaceを永久削除できる。
- member数、未完了Task、completed historyをclientで表示し、Space name再入力等のstrong confirmationを要求する。
- clientはknown RecordをTombstone化し、serverはSpace deletion stateを設定してnew writes/invitesを拒否する。
- memberはlocal cached plaintext/keyを次回syncで削除するが、offline deviceのremote eraseは保証しない。
- server backup expiryは運用policyに従う。
- archiveを通常の「使わなくなった共有list」操作として提供し、Space deleteを整理目的で使わせない。

## 12. Account identity change and compromise

### 12.1 Signed normal rotation

- old identity keyがnew identity bundleを署名する。
- Shared Space manifestはnew fingerprint/versionへowner-signed transitionする。
- HPKE keyが変わる場合、current/historical keyringをnew keyへ再wrapする。
- Space contentのbulk re-encryptionは不要である。

### 12.2 Unsigned security reset

old identity keyを失ったAccountはserver上で同一人物だとしてもcryptographically同一とは証明できない。

- active Shared Spaceでidentity warningを出し、そのAccountへのnew key deliveryをblockする。
- ownerがnew invitation secret/Safety Codeで再確認する。
- compromised old AccountをremoveしてSpace Keyをrotateし、new identityをaddする。
- 「key changed」warningをsilent acceptしない。

Account signing/private key compromiseが疑われる場合、session revokeだけでは過去にcopyされたSpace Keyを無効にできない。各Shared Spaceでremove/re-addまたはsecurity rekeyを行う。

## 13. Concurrent membership operations

- all membership changesはexpected `membership_revision` CASを使う。
- same revisionから2 owner operationsが来た場合、1つだけcommitし、他はlatest stateをpullして人間の意図を再確認する。
- automatic mergeでmember removeとrole change、owner transferを組み合わせない。
- generation incrementを伴うremove/security resetは、role-only transitionより優先するのではなくserver transaction順でserializeする。
- clientはmembership conflictをcontent conflictとして自動解決しない。

## 14. Shared content semantics

- assigneeはactive member Account IDをencrypted Record内で参照する。serverはTask assigneeを知らない。
- removed memberをassigneeに持つTaskはclientが`unassigned`またはhistorical actor表示へ移す。Record editが発生するためcurrent generationへ再暗号化する。
- comment/Completion Recordはauthor signatureを検証し、author removal後もhistorical authorとして表示する。
- Shared Space TaskをcompleteしたactorはShared Completion Recordへ残る。
- 個人のWork SessionはPersonal Spaceに置き、Shared Space memberへ自動共有しない。Shared Taskへの参照はsoft external referenceであり、Task削除・member removal・access喪失後もencrypted display snapshotを伴う個人成果記録として残す。
- notification mention/reminderはclientがdecrypt後にlocal scheduleする。server pushへTask/comment plaintextを入れない。

## 15. Enterprise extension boundary

将来追加できるもの:

- organizationが複数Spaceのbilling/policy参照を持つ。
- additional role/policy、managed invitation、directory。
- organization-owned Account key/recoveryまたはcompliance feature。

初期designに入れないもの:

- organization root key、admin escrow、manager key。
- SSO/SCIM、domain claim、group role、audit export。
- legal hold、retention override、admin permanent access。
- ownerより強いhidden administrator。

Enterpriseを追加する場合は、個人/家族Spaceのthreat modelを暗黙に弱めず、別Space typeと明示的key/recovery policyにする。

## 16. State-machine acceptance scenarios

1. New viewer invitation: past/current Recordを読めるが、serverはwriteを拒否し、clientもviewer signature mutationを受理しない。
2. New editor invitation: historical keyringを得てpast dataを読み、current generationでnew Recordを書ける。
3. Editor removal: server accessとold-generation uploadが拒否され、remaining memberのnew/edited Recordはnew keyになる。unchanged old Recordはrewriteされない。
4. Re-edit after removal: generation NのTaskをremaining editorがeditし、generation N+1のwhole Recordとして保存する。
5. Owner transfer: target acceptance前はold ownerだけ、commit後はtargetだけがownerである。
6. Concurrent remove/transfer: one revisionだけcommitし、losing operationはlatest membershipを表示して再確認する。
7. Member leave while owner offline: leaving member accessを止め、Space writeをfreezeし、owner rekey後にresumeする。
8. Identity unsigned reset: new keyをsilent acceptせず、remove/reinvite/rekeyを要求する。
