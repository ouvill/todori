# Cryptography and key management

> 状態: 2026-07-23 product owner承認済みbaseline（未実装）
>
> 本書はprotocol shapeを定める。algorithm parameter、binary format、libraryは実装前のADRとtest vectorで固定する。

## 1. Goals

- password、recovery、content keyを分離する。
- password変更、device追加、member追加でcontent全体を再暗号化しない。
- Shared Spaceのmember除外後はnew contentをold keyで暗号化しない。
- AEADによる改ざん検知に加えてauthor authenticityを署名で検証する。
- versioningとdomain separationを最初から持ち、algorithm migrationでその場しのぎのfallbackを作らない。
- 1つのcross-platform cryptographic coreを全official clientで共有する。

## 2. Candidate cryptographic suite

| Purpose | Candidate |
|---|---|
| Password authentication | RFC 9807 OPAQUE-3DH。maintained implementationがsupportするRFC ciphersuite |
| Password hardening | OPAQUE KSFとしてArgon2id。parameterはlow-end mobile実測とRFC 9106を基に固定 |
| Key derivation | RFC 5869 HKDF-SHA-256。OPAQUE suite内部は当該suite指定に従う |
| Content/wrap AEAD | XChaCha20-Poly1305、256-bit key、random 192-bit nonce |
| Member key delivery | RFC 9180 HPKE Base mode: X25519/HKDF-SHA-256/ChaCha20-Poly1305 |
| Signature | RFC 8032 Ed25519 |
| Hash | SHA-256またはsuiteが指定するhash |
| Random | OS CSPRNGから得る256-bit以上のkey material、128-bit以上のrandom ID |
| Encoding | deterministic CBOR profile候補。float、duplicate map key、indefinite lengthを禁止 |

HPKE Base mode自体はsender authenticationを持たないため、HPKE key envelope全体をownerのEd25519 keyで署名する。XChaCha20-Poly1305、HPKE内部のChaCha20-Poly1305、OPAQUE内部のAEADを別の用途として扱い、nonce/key空間を共有しない。

採用しないもの:

- custom cipher、custom KEM、custom signature。
- raw ECDHを直接使う独自ECIES。
- passwordをそのままdata encryption keyにすること。
- deterministic content encryption。
- Double Ratchet、MLS、sender keys、blockchain。
- 初期製品でのpost-quantum hybrid独自構成。

## 3. Key hierarchy

```text
Password
  └─ OPAQUE export key
       └─ Account Unlock Key (AUK)
            └─ wraps Account Root Key (ARK)

Recovery Key (RK: random 256-bit)
  └─ Recovery Wrap Key
       └─ wraps the same ARK

ARK (random 256-bit)
  ├─ wraps Account Identity Bundle
  │    ├─ Ed25519 signing private key
  │    └─ X25519 HPKE recipient private key
  └─ wraps Personal Space Key generation 1

Shared Space Key generation N (SSK-N)
  └─ HPKE envelope for each active member Account public key

Personal/Shared Space Key generation
  └─ HKDF(space ID, record ID, purpose, suite)
       └─ Record Encryption Key

Device Local Wrapping Key (DLWK: random 256-bit)
  ├─ protects local database key/capsule
  └─ protects locally cached ARK
```

`Account Root Key`はpasswordから独立したAccountのroot secret、`Space Key`はあるSpace generationの全Recordを保護するrandom symmetric keyである。

## 4. Key invariants

1. Password、OPAQUE export key、AUK、RK、ARK、private identity key、Space Keyをserverへplaintextで送らない。
2. ARK、Space Key、identity private keyはCSPRNGで生成し、password、email、Account IDから導出しない。
3. Password変更では同じARKをnew AUKでrewrapする。RecordとSpace Keyを再暗号化しない。
4. Recovery Key変更では同じARKをnew Recovery Wrap Keyでrewrapする。
5. Shared Space Keyはmembership removalまたはsecurity resetでgenerationを上げる。通常のpassword changeでは上げない。
6. Record Encryption KeyはSpace ID、record ID、generation、purpose、suiteへdomain-separateする。
7. content AEAD nonceは暗号化ごとにCSPRNGで新規生成する。record revisionをnonceとして使わない。
8. wrap/envelopeのAADはprotocol object kind、version、suite、Account/Space/record ID、key generation、recipient key IDを固定順で含む。
9. plaintext keyをlocal DBへ直接保存しない。process memoryではzeroizing containerを使い、必要以上にclone/logしない。
10. unknown version、unknown suite、nonce length mismatch、signature failure、AEAD failureはfail closedする。

## 5. Account registration and login

### 5.1 Registration

1. clientはAccount ID、ARK、Recovery Key、Ed25519/X25519 identity key pair、Personal Space Keyを生成する。
2. clientとserverはOPAQUE registrationを行う。passwordをserverへ送らない。
3. clientはOPAQUE `export_key`からdomain-separated HKDFでAUKを導出する。
4. AUKでARKをwrapし、Recovery Keyから導出したRecovery Wrap Keyでも同じARKをwrapする。
5. ARKでidentity private bundleとPersonal Space Keyをwrapする。
6. serverはOPAQUE registration record、public identity bundle、wrapped ARK、wrapped private bundle、wrapped Personal Space Key、recovery-wrapped ARKを保存する。
7. clientはRecovery Keyを一度表示し、copy/print/encrypted exportを促す。serverはRecovery Keyを受け取らない。

OPAQUE `export_key`はserverとのsession keyと別物であり、AUK derivation以外へ直接流用しない。OPAQUE contextへTaskveil protocol/version/domainをbindする。

### 5.2 Login

1. OPAQUE AKEを完了し、clientとserverが相互認証したsessionを得る。
2. clientだけが得る`export_key`からAUKを導出する。
3. wrapped ARK、identity bundle、Personal Space Keyを順にunwrapする。
4. public/private identityの一致、Account/Space binding、version、signatureを検証する。
5. local DLWKでARKをrewrapし、OS secure storage policyに従ってcacheする。
6. どの段階でも失敗した場合、anonymous/local-only stateへ黙ってfallbackしてaccount-bound dataを編集しない。

TLSを併用し、OPAQUEだけをtransport encryptionやAPI authorizationの代わりにしない。

## 6. Password and recovery

### 6.1 Password change

old passwordまたはunlock済みARKを持つ正規clientだけが実行する。

1. new passwordでfresh OPAQUE registrationを行う。
2. new OPAQUE export keyからnew AUKを導出する。
3. 同じARKをnew AUKでwrapする。
4. clientはnew OPAQUE registration recordとnew wrapped ARKのdigest、Account ID、expected account security revision、server challenge、transition IDをAccount signing keyで署名する。
5. serverはcurrent public identity key、challenge、expected revision、digestを検証し、OPAQUE record、wrapped ARK、security revisionをatomic CASで置換する。
6. other sessionを維持または失効するpolicyはserver authentication policyで決める。

### 6.2 Recovery Key

- Recovery Keyはrandom 256-bit secretをhuman-safe encodingしたものとする。
- checksum、version、formatを持つが、word listやBase32 encoding自体をentropy sourceにしない。
- support agent、email OTP、billing proofだけでARKを復旧しない。

Recoveryによる認証状態の置換は、Recovery Keyを知るという主張だけでは認可しない。

1. clientはAccount ID、current account security revision、one-time server challenge、recovery-wrapped ARKを取得する。
2. Recovery KeyでARKをunwrapし、ARKからidentity private bundleを復元してcurrent public identityとの一致を検証する。
3. new passwordでfresh OPAQUE registrationをpending stateとして作り、new AUKで同じARKをwrapする。
4. new Recovery Keyを生成してARKをnew Recovery Wrap Keyでwrapする。旧Recovery Keyはtransition成功後に無効化する。
5. clientは次のcanonical recovery transitionをAccount signing keyで署名する。

```text
account_id
transition_id
server_challenge
expected_account_security_revision
new_opaque_registration_digest
new_wrapped_ark_digest
new_recovery_wrapped_ark_digest
```

6. serverはchallenge未使用、transition ID未処理、expected revision一致、current public identity keyによるsignature、各pending objectのdigest一致を検証する。
7. serverはOPAQUE registration record、wrapped ARK、recovery-wrapped ARK、account security revision、challenge/transition消費、既存session revokeを1 transactionでcommitする。部分更新を許可しない。
8. clientはcommit後にnew Recovery Keyを一度表示し、copy/print/encrypted exportを促す。

これにより第三者は、Recovery KeyまたはAccount signing keyを復元せずにregistration recordやwrapperだけを置換できない。Malicious serverによる拒否やrollbackはavailability/freshnessの限界として残るが、正規serverは署名のないrecovery transitionを受理しない。

### 6.3 Irrecoverable reset

Password、Recovery Key、unlock済みdeviceのすべてを失った場合、旧ARKとcontentは復旧不能である。

- serverはnew cryptographic Account stateを作れるが、旧ciphertextをdecryptできない。
- 同じAccount IDのsilent resetは共有identityとkey pinを壊すため行わない。
- resetはnew identity version/security resetとして明示し、Shared Space ownerによる再招待/再key deliveryを必要とする。
- 旧encrypted dataの削除は利用者が復旧不能を確認した後に別操作で行う。

## 7. Account identity

Accountはstableなidentity bundleを持つ。

```text
identity_version
account_id
ed25519_signing_public_key
x25519_hpke_public_key
previous_identity_statement | null
self_signature
```

- private bundleはARKでwrapするため、同じAccountの正規deviceは同じidentityを使う。
- public bundleはserver-visibleであり、Record signature verifyとmember key deliveryに使う。
- normal rotationはold signing keyがnew bundle全体へ署名する。clientはchainを検証してpinを更新する。
- old keyを失ったresetはchainを作れないため、Shared Spaceでsecurity warningとinvitation/Safety Codeによる再確認を必須にする。
- public key historyはold Record signature verifyに必要な期間保持する。

Account-level identityはdevice-level cryptographic isolationを提供しない。Account keyを復元した1 deviceが侵害されるとAccountとして署名/復号できる。初期製品ではserver session revokeとAccount security resetで対処し、device certificate treeを導入しない。

## 8. Record encryption and signature

### 8.1 Conceptual envelope

```text
protocol_version
crypto_suite_id
space_id
record_id
revision_id
base_revision_id | null
operation_id
key_generation
author_account_id
author_identity_version
nonce
ciphertext
padding
author_signature
```

Record kind、field、relation、user timestampsはciphertext内に置く。outer headerはserver routing、RBAC、CAS、quota、client verificationに必要な最小限とする。

### 8.2 Encryption

1. typed plaintextをcanonical encodeする。
2. current Space Key generationとrecord IDからHKDFでRecord Encryption Keyを導出する。
3. fresh random nonceを作る。
4. outer headerのcanonical bytesをAADにする。
5. plaintextとpaddingをXChaCha20-Poly1305で暗号化する。
6. header、nonce、ciphertextのcanonical bytes全体をauthor Ed25519 keyで署名する。

Decryptはsignature、header/AAD、AEAD、canonical encoding、typed schema、domain invariantの順で検証する。署名済みでもrole違反、unknown generation、terminal Tombstoneの復活は拒否する。

### 8.3 Padding

exact plaintext length leakを減らすためsmall Recordをsize bucketへpaddingする。候補は256/512 B、1/2/4/8/16/32/64 KiBである。最大Record size、compressionの有無、bucketはmobile/storage benchmarkとside-channel評価後に固定する。secret-dependent compressionをnetwork attacker inputと同じcontextで行わない。

## 9. Space Key lifecycle

### 9.1 Personal Space

- Account作成時にgeneration 1を生成し、ARKでwrapする。
- membershipはAccount本人だけなので通常rotationを行わない。
- ARK/Space Key compromise時のsecurity reset、algorithm migrationでnew generationを作れる。
- historical generationは旧Record復号のため保持する。

### 9.2 Shared Space

- owner clientがgeneration 1を生成する。
- active memberごとにHPKEでSpace Keyを暗号化し、ownerがenvelopeとmembership revisionへ署名する。
- removal/security resetごとにfresh random Space Keyを生成し、generationを1増やす。
- retained memberへnew generationだけを追加配布する。除外memberへは配布しない。
- old Recordを一括再暗号化しない。Recordの次回editではcurrent generationを使用する。
- historical generationは、未削除のold Recordとnew memberのpast accessのため保持する。

Space Keyをhash chainで導出しない。old keyからnew key、new keyからold keyを計算できない独立random keyにする。

### 9.3 Historical keyring

Shared Spaceの各active memberは、参加時点に関係なく全retained generationを受け取る。

- ownerはnew memberのHPKE public keyへhistorical keyringをwrapする。
- keyringにはSpace ID、generation/key pair、membership revision、suite、owner signatureを含む。
- serverはkeyring ciphertextとgeneration一覧を持つが、Space Keyは知らない。
- generation数はmembership/security event数に比例する。家族・友人のsmall groupと約1 GiB quotaでは許容し、tree-based group key agreementを導入しない。
- generation GCは、そのgenerationで暗号化された未削除Recordが0件であることを全active clientが証明できる方式が決まるまで行わない。

## 10. Invitation identity binding

初回key deliveryでserverによるrecipient key substitutionを防ぐため、one-time invitationにserverへ送られないrandom secretを使う。

1. owner clientは256-bit invitation secretとrandom invite IDを作る。
2. serverへはinvite ID、expiry、secretでAEAD暗号化したowner identity/Space invitation packageだけをuploadする。
3. linkのpath/queryにinvite ID、URL fragmentまたはQR payloadにsecretを入れる。fragmentはHTTP requestに含まれない。
4. recipient clientはsecretでpackageを開き、owner identity fingerprintをpinする。
5. recipientは自身のpublic identity bundleとsigned acceptanceをsecretで暗号化してserverへ置く。
6. owner clientはacceptanceをsecretで開くため、serverがrecipient keyを差し替えられない。
7. ownerはrecipient keyへhistorical keyringをHPKE encryptし、membership activationをcommitする。
8. inviteは1回使用、短期expiry、rate limit、cancel可能とする。

link secretを得た攻撃者は招待へ参加を試みられる。serverはacceptanceをintended Accountへbindし、owner UIはrecipient identityを表示する。high-assurance利用者向けに、Signal型のpairwise Safety CodeをQR/数字で比較できるようにする。

このflowのexact message formatとsecurity proofは実装前ADRの対象である。ad-hocなraw ECDHは使わず、invitation packageはAEAD、member key deliveryはHPKE、identityはEd25519署名に限定する。

## 11. Local key storage

- DLWKをCSPRNGで生成し、Apple Keychain / Android Keystore等のOS secure storageで保護する。
- SQLCipher等のlocal encrypted DB keyはDLWKからdomain-separated deriveまたはDLWKでwrapする。
- ARK cacheはDLWKでwrapし、Account/DB profile bindingをAADへ含める。
- biometric/app PINはOS key release policyを強化するoptionであり、ARKの唯一のbackupにしない。
- push extension、widget、notification service extensionへARK/Space Keyを広く共有しない。必要な最小local plaintextをplatform security境界内で別途保護する。
- log、analytics、crash dump、clipboard history、screenshotへsecretを出さない。

## 12. Versioning and migration

次を独立したversion空間とする。

- OPAQUE configuration/version。
- Account envelope/version。
- Record protocol version。
- crypto suite ID。
- plaintext schema version。
- local DB schema version。
- export format version。

clientはminimum supported versionと一度観測したhighest security versionをlocal durableに保持する。serverがold versionを返してもsilent downgradeしない。

Algorithm migrationはnew suite/Space generationを作り、new/edited Recordへ適用する。old suiteはread-only decryptを一定期間維持し、bulk migrationを行う場合も別のexplicit jobにする。unknown suiteを「試せるalgorithmから順に試す」fallbackは作らない。

## 13. Required implementation gates

実装前後に少なくとも次を要求する。

- maintained libraryとversion、platform support、license、audit historyの選定。
- RFC/official test vectorとTaskveil cross-language/cross-platform vector。
- nonce uniqueness、wrong key、wrong AAD、swap、truncation、unknown version、invalid signatureのnegative test。
- key zeroizationとsecret logging audit。
- OPAQUE parameterのlow-end device benchmarkとDoS評価。
- invitation flow、owner transfer、member removalのstate-machine/model test。
- external cryptographic design review。
