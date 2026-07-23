# Threat model

> 状態: 2026-07-23 product owner承認済みbaseline（未実装）

## 1. 目標水準

Taskveilは[Proton Driveが公開する脅威モデル](https://proton.me/blog/proton-drive-threat-model)と同程度を目安にする。正規clientが未侵害endpointで動作する限り、network interception、server storage leak、curious operator、server compromiseからcontent confidentialityとcryptographic authenticityを守る。

E2EEはendpoint、悪意ある共有相手、偽client、traffic analysis、availability、完全なfreshnessを解決しない。国家級攻撃者に対する完全耐性や、Signal Private Group System相当のmembership hidingは目標にしない。

## 2. Security assumptions

- 利用者が正規配布元から正規clientを取得している。
- OS、hardware、secure storage、CSPRNG、暗号libraryが想定どおり動作する。
- client releaseとdependencyがsecurity review、code signing、updateを受ける。
- TLSはserver APIとsoftware distributionを保護するが、content confidentialityの唯一の境界ではない。
- invitation secretまたはSafety Codeが、共有相手との既知channelで正しく渡る。
- 利用者がRecovery Keyを安全に保管する。
- serverはaccess controlとavailabilityを通常は提供するが、content confidentialityのためには信頼しない。

## 3. Protected assets

### 3.1 Secret key material

- Account Root Key、Recovery Key、Account Unlock Key。
- account signing private key、HPKE recipient private key。
- Personal/Shared Space Keyの全generationとrecord key。
- local database key、OS secure storage内のwrapping key。
- OPAQUE export key、MFA secret、session token。

### 3.2 Content

- task title、note、URL、status、priority、due/scheduled/reminder。
- recurrence rule、template、saved filter、search query。
- list/section/tagの名前、task hierarchy、rank、relation。
- comment、assignee、completion actor、Completion Record。
- Work Sessionのtask relation、started/ended time、duration、note。
- Personal Space内のrecord kindとprivate list数。
- plaintext search index、notification body、local analytics。

### 3.3 Integrity and authenticity

- ciphertextが別Space、record、generationへ移植されていないこと。
- mutationが表示されたauthorのsigning keyで作られたこと。
- membership、role、owner、key generationの変更が正規ownerに承認されたこと。
- clientが未知またはdowngraded protocol/cryptoを安全でないfallbackで受理しないこと。
- permanent delete済みrecordが古いdeviceから復活しないこと。

### 3.4 Availability and portability

- server障害、subscription失効、quota超過でもlocal dataを利用できること。
- encrypted/plaintext exportによりserviceから離脱できること。

Availabilityはcryptographic guaranteeではなくproduct requirementである。serverはaccess拒否、data omission、delay、account停止を行える。

## 4. Adversary model

| 攻撃者 | 能力 | 対策 | 残る限界 |
|---|---|---|---|
| Network attacker | 盗聴、改変、replay、delay | TLS、AEAD、signature、revision/generation binding | traffic timing/sizeは観測可能 |
| Stolen server snapshot | DB、backup、log、objectを取得 | plaintext key/contentを保存しない、encrypted local/export | metadataとpassword offline guessing riskは残る |
| Curious operator | 正規運用権限でDB/log/supportを見る | metadata minimization、log redaction、E2EE | account、membership、IP等は見える |
| Compromised/malicious server | response omit/replay/fork、public key substitution、access denial | signature、AEAD、invitation secret、key pinning、client rollback detection | 完全なfreshness/fork transparencyとavailabilityは保証しない |
| Credential attacker | password、MFA、sessionの一部を得る | OPAQUE、Argon2id KSF、MFA、rate limit、session revoke | password+MFA+encrypted key bundleを得ればAccountへ入れる可能性 |
| Thief with locked device | filesystem image、端末を取得 | OS secure storage、device lock、encrypted DB | weak device passcodeやOS compromiseは残る |
| Compromised endpoint | unlock済みmemory、screen、input、keychain access | app lock、secret lifetime短縮、log禁止 | E2EEでは防げない |
| Unauthorized account | inviteなし、非member | unguessable ID、server membership/RBAC、Space Key不保持 | DoSとenumeration対策は別途必要 |
| Malicious shared member | 正規plaintext/keyを取得、role内で改変・大量permanent delete | role/RBAC、signature、招待時の権限説明、removal+rekey、user export | 既取得dataのcopy/publicationと、editorによるavailability/integrity破壊を防げない |
| Removed member | old keys、old plaintext、offline mutationを保持 | server revoke、new generation、old-generation write拒否 | 除外前dataの遠隔消去はできない |
| Accidental action | 誤編集、誤完了、誤削除 | undo、archive-first、deep permanent-delete confirmation、conflict preservation | 利用者が確認した永久削除は復元不能 |

## 5. Guarantees

正規client、未侵害endpoint、正しくbootstrapされたidentityを前提に、次を保証目標とする。

### 5.1 Confidentiality

1. server、backup、networkだけではprotected contentを復号できない。
2. password、Recovery Key、Account Root Key、Space Key、private identity keyをserverへplaintextで送らない。
3. member外accountはserver accessとSpace Keyの両方を持たない。
4. removed memberはnew generationで作られたRecordと、除外後に編集されcurrent generationへ移ったRecordを復号できない。
5. new memberはownerが明示的に配布したhistorical Space Keysにより未削除の過去Recordを読める。
6. local DBとlocal search indexをstorage at restで暗号化する。

### 5.2 Integrity and authenticity

1. AEAD verification failure、signature failure、AAD mismatch、unknown suite、schema invariant failureをdomain dataとして適用しない。
2. serverはmember authorの有効signatureを作れない。
3. Space Keyを知るviewer/editorでも別memberのauthor signatureを偽造できない。
4. clientはrecord ID、Space ID、generation、protocol versionをcryptographically bindし、ciphertext swapを拒否する。
5. membership/role/owner transitionはowner署名、expected membership revision、server transactionを検証する。
6. identity key rotationは旧keyのsignatureを必要とし、旧keyがないsecurity resetは共有先で警告と再確認を必須にする。
7. 一度current generationを観測したclientは、それより古いgenerationで作られた新mutationを受理しない。

### 5.3 Offline and data safety

1. local mutation、materialized state、outboxを同じlocal transactionで確定する。
2. sync retryはidempotentで、network timeoutだけを理由にduplicateを作らない。
3. CAS conflictはclientが3-way mergeし、同じfieldの両方の値を復旧可能な形で保つ。
4. quota拒否、decrypt/signature/schema failureをlocal data消失として扱わない。
5. Tombstoneは旧live Recordよりterminalであり、同じrecord IDを再利用しない。

## 6. Explicit non-guarantees

### 6.1 Endpoint and client delivery

- malware、keylogger、screen capture、debugger、root/jailbreak、悪意あるaccessibility service。
- unlock済み端末を操作できる人物。
- 偽app、悪意あるupdate、build/signing infrastructure compromise。
- Web clientを配布するserverが同時にmalicious JavaScriptを配る攻撃。Webを提供する場合は別threat assessmentが必要である。

### 6.2 Shared recipient

- 正規memberが閲覧したplaintextのcopy、screenshot、export、再共有。
- removed memberの端末から除外前dataをremote eraseすること。
- 正規member同士のcollusion。
- Editor roleを与えたmemberによる全Recordの改変、大量permanent delete、Completion RecordのTombstone化。Signatureはactorを識別できるが、current-head-only server storageから旧ciphertextを復元しない。
- Shared Spaceはbackupではない。招待前にeditorの破壊権限を説明し、復旧が必要な利用者は定期的なencrypted/plaintext exportを自ら保管する。
- honest server access controlを無視するmalicious serverとremoved memberが、old generationで偽の「除外前」Recordを共謀して作ること。current generationのconfidentiality/authorshipは保護するが、完全なhistorical transparencyは初期目標外である。

### 6.3 Server behavior

- access denial、account suspension、quota policy、data deletion、notification suppression、traffic analysis。
- 初回syncしかしていないclientに対する完全なfork/rollback detection。
- global append-only transparency logによる全client同一viewの証明。
- server clockの真実性。server timestampはsync ordering/operationだけに使い、user event timeの真実とはみなさない。

### 6.4 Metadata and anonymity

- serverはAccount、email、device session、IP、push token、Space、membership、role、owner、key generation、encrypted byte size、request time/frequencyを知る。
- Shared Space数から共有list数を概ね推測できる。
- author account、record size bucket、change frequencyから行動を推測できる。
- Tor相当のnetwork anonymity、private contact discovery、membership hidingは提供しない。

### 6.5 Cryptographic properties

- TODO Recordにmessage-by-message forward secrecyやpost-compromise securityを提供しない。
- Space Key generationを知るmemberは、そのgenerationで暗号化された全Recordを復号できる。
- low-entropy passwordへのoffline dictionary attackを不可能にはできない。RFC 9807もsingle-server compromise後のexhaustive guessingを不可避とするため、memory-hard KSF、rate limit、MFA、高entropy passwordを併用する。
- quantum-resistant cryptographyは初期要件にしない。algorithm agilityを設け、標準とlibrary成熟後にmigrationする。

## 7. Server-visible metadata inventory

serverが保存または運用上観測する情報を次に限定し、公開privacy documentとschema reviewで照合する。

| Category | Server-visible |
|---|---|
| Account/authentication | random account ID、email、OPAQUE registration record/config、MFA state、account security revision、public identity bundle/version/key fingerprints/signatures |
| Encrypted account key material | wrapped ARK、recovery-wrapped ARK、wrapped identity private bundle、wrapped Personal Space keyring、および各objectのversion/size |
| Password/recovery transition | transition ID、one-time challenge、expected security revision、pending object digest、Account signature、success/failure/consumed state |
| Session/device | random device/session ID、push token、created/last-seen/revoked time、IP/abuse telemetry |
| Space | random Space ID、Personal/Shared type、state、owner、membership revision、current key generation、server sequence/delta lower bound、encrypted byte usage |
| Membership | Space/account ID、role、identity version、state、membership revision、join/remove time |
| Membership manifest/transition | Space/revision、currentおよびhistorical canonical manifestのversion/size/digest、previous manifest digest、transition kind、key-envelope-set digest、owner signature、target acceptance signature、commit time、retention state |
| Key delivery | Space/generation、recipient account/identity version、HPKE ciphertext、owner signature、object version/size |
| Record head/Tombstone | Space/record/revision/base-revision/operation ID、protocol/suite、generation、author account/identity version、nonce、ciphertext/padding/signatureと各size、server sequence、stored bytes、Tombstone flag |
| Delta/idempotency | Space sequence、record/revision ID、Tombstone flag、operation ID、request digest、result/status、retention lower bound |
| Invitation | random invite ID、Space ID、creator account、expiry/state、package version、encrypted invitation packageとsize、accepting account after acceptance |
| Plan/quota | plan/entitlement state、account/Space usage、quota check/result、owner attribution |
| Traffic/log/push | request time/size/route/result、rate-limit/abuse signals、generic wake-up target/timing/provider metadata |

serverが取得しない情報:

- Record kindがtask/list/tag/comment/completion/work sessionのどれか。
- private list数、list名、Shared Space表示名。
- task title/note/status/priority/date/reminder/recurrence。
- task hierarchy、section、tag、rank、assignee。
- timerとtaskのrelation、duration、started/ended time。
- search term、saved filter、notification content。

## 8. Threat-driven requirements

| Threat | Requirement |
|---|---|
| server public key substitution | invitation fragment secretで両identity keyをbindし、以後pinする。任意のSafety Codeを提供する |
| viewer forges author | record signatureとserver role checkを両方必須にする |
| removed member reads new data | removal transactionでaccess revokeとnew Space Key generationを同時にcommitする |
| old key remains on records | edit時は必ずcurrent generationでwhole Recordを再暗号化する |
| offline stale write | serverはremoved accountとold generation uploadを拒否し、clientもobserved generation downgradeを拒否する |
| malicious server swaps ciphertext | AAD/signatureへSpace ID、record ID、revision、generation、suiteを含める |
| server rolls back protocol | client hardcoded minimum versionとobserved highest versionを保持する |
| attacker replaces recovery registration/wrapper | ARKから復元したAccount signing keyでnew object digest、challenge、expected security revisionを署名し、serverがatomic CASする |
| conflict loses completion | immutable Completion RecordとCAS 3-way mergeを使う |
| quota causes data loss | local commitを先行し、outbox保持、pull/delete/exportを許可する |
| permanent delete resurrects | content-free permanent Tombstoneとrecord ID非再利用 |
| key/log leakage | secret/plaintextをlog、crash report、analytics、notification payloadへ出さない |

## 9. Security response

- cryptographic failureとplaintext leakageを通常sync errorとして自動無視しない。affected Recordをquarantineし、secretを含まないdiagnostic IDを出す。
- account/identity key compromiseではsession revokeだけで「安全」と表示しない。Account identity rotation、Shared Space rekey、Recovery Key rotationの範囲を案内する。
- critical algorithm/library vulnerabilityにはprotocol version、suite ID、minimum client versionを使ってfail closedまたはmigrationする。
- implementation前にtest vector、negative test、cross-platform interoperability、external security reviewをrelease gateへ入れる。
