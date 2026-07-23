# Prior art

> 状態: 2026-07-23 product owner承認済みresearch basis（未実装）

## 1. 調査方針

既存製品のprotocolを混ぜて独自protocolを作らない。Taskveilと同じ問題に対応する部分だけを、一次資料または標準仕様から採用する。marketing上の「zero knowledge」だけでは判断しない。

## 2. Proton Drive

### 2.1 観察

Proton Driveはkeyとpassphraseをclientで生成し、file/folder名とcontentをE2EEにする。shareごとのrandom passphraseをmemberごとのaddress keyへ暗号化することで、data本体をmemberごとに再暗号化せずaccessを追加する。contentやkey materialには署名を使い、malicious serverによる偽造を検出する。

一方、Protonのprivacy policyはcreation/modification time、permission、uploader username、encrypted size等をservice運用のため取得すると明示する。脅威モデルもserver breachやdata seizureからのcontent保護と、偽client、credential compromise、endpoint compromise、完全なsecurityを明確に分けている。

参照:

- [The Proton Drive security model](https://proton.me/blog/protondrive-security)
- [Proton Drive threat model](https://proton.me/blog/proton-drive-threat-model)
- [Proton Drive privacy policy](https://proton.me/drive/privacy-policy)
- [Proton Drive signature management](https://proton.me/support/drive-signature-management)
- [Proton Key Transparency whitepaper](https://proton.me/files/proton_keytransparency_whitepaper.pdf)

### 2.2 Taskveilで採用する

- Spaceごとのrandom symmetric key。
- Space Keyをmemberごとのpublic encryption keyへ暗号化し、record本体をmemberごとに複製しない。
- content confidentialityとは別にauthor signatureを持つ。
- server-visible metadataを公開inventoryとして列挙する。
- 新memberへkey materialを渡すことで過去dataへaccessさせる。
- URL fragmentのようにserverへ送られないrandom secretをone-time invitationのbootstrapに利用する。

### 2.3 採用しない

- file/folderごとのasymmetric node keyとpassphrase tree。添付fileのないTODOには過剰である。
- OpenPGP packet model。TaskveilにPGP互換要件はない。
- guest/public linkでのcontent共有。初期製品はTaskveil Accountへbindする招待だけとする。
- Proton規模のkey transparencyを独自に再実装すること。初期identity bindingはone-time invitation secret、既存keyによるkey rotation署名、任意のSafety Codeで構成する。

## 3. Standard Notes

### 3.1 観察

Standard Notes protocol 004はserverをdumb data storeとして扱い、passwordから得るroot keyとrandomなitems keys、itemごとのrandom item keyを分離する。passwordまたはprotocol変更時は少数のitems keysをrewrapし、全dataの一括再暗号化を避ける。旧items keyのdataは明示的に編集された時に新keyへprogressively re-encryptする。content encryptionにはXChaCha20-Poly1305とauthenticated dataを使い、payloadにprotocol versionを含める。

参照:

- [Standard Notes encryption whitepaper](https://standardnotes.com/help/security/encryption)
- [Standard Notes security updates](https://standardnotes.com/help/security)
- [Standard Notes security audits](https://standardnotes.com/help/2/has-standard-notes-completed-a-third-party-security-audit)

### 3.2 Taskveilで採用する

- password-derived unlock keyとrandom data keyの分離。
- password変更時にroot data keyをrewrapし、全recordを再暗号化しない。
- key rotation後のprogressive re-encryption。
- versioned payload、AAD、hardcoded minimum supported version、downgrade拒否。
- local persistenceとsearch indexもdefaultで暗号化する。
- serverをopaque record storeとする境界。

### 3.3 変更して採用する

- Taskveilのauthenticationはpasswordの一部をserver passwordにする方式ではなく、OPAQUEを候補にする。
- itemごとのrandom DEKをwrapする代わりに、Space Key generationとrecord IDからHKDFでrecord keyを導出する。添付fileもrecord単位sharingもないため、key object数を増やす利点が小さい。
- Standard Notesのwhitepaperがscope外とするsync conflict、membership、role、signatureをTaskveil側で別に定義する。

## 4. Signal

### 4.1 観察

X3DH/PQXDH、Double Ratchet、Sesameは、offline recipientを含む非同期message session、messageごとのforward secrecy、multi-device session管理を扱う。Safety Numberは別経路でpublic identityを確認し、key substitutionを検出する。

SignalのPrivate Group Systemは、group membershipをserverから隠しながらserver access controlを成立させるため、anonymous credentialとzero-knowledge proofを使う。これは強いmetadata privacyを得る一方、通常のmembership tableより大幅に複雑である。

参照:

- [Signal protocol specifications](https://signal.org/docs/)
- [The Sesame Algorithm](https://signal.org/docs/specifications/sesame/)
- [Signal Safety Number support](https://support.signal.org/hc/en-us/articles/360007060632-What-is-a-safety-number-and-why-do-I-see-that-it-changed)
- [Signal Private Group System](https://signal.org/blog/signal-private-group-system/)

### 4.2 Taskveilで採用する

- identity public keyを別経路で確認できるSafety CodeというUX。
- key changeを通常の出来事として黙認せず、既存identity keyの署名または再確認を求める。
- cryptographic membershipとserver authorizationは別問題として扱う。
- removed memberが旧keyと旧plaintextを保持できる限界を明示する。

### 4.3 採用しない

- Double Ratchet、X3DH/PQXDH、Sesame。TODOは長期current stateをmulti-deviceで同期するもので、messageを順番に消費するsessionではない。
- Signal Private Group Systemのanonymous credentialとzero-knowledge access control。Taskveilの目標水準ではserverがShared Space membershipを知ることを許容し、通常のrole tableでaccess controlする。
- sender keysやmessage transcript protocol。Record CASとclient mergeを別に設計する。

## 5. MLS

[RFC 9420 Messaging Layer Security](https://www.rfc-editor.org/rfc/rfc9420.html)はgroup membershipをepochとして進め、新memberへWelcome messageを送り、removed memberをnew epoch secretから除外する標準protocolである。しかし、新memberは原則として追加前のmessageを読めず、各memberが順序づけられたgroup stateとratchet treeを保持する。Taskveilが求める「新memberも過去のcurrent dataを閲覧可能」「offlineで長期保持されるrecord」「旧recordは編集時だけnew keyへ移す」と一致しない。

初期製品ではMLSを採用しない。将来realtime chatを追加する場合は、そのchat dataだけに再評価し、TODO record key managementへ流用しない。

## 6. 標準primitive

候補にする標準と用途:

- [RFC 9807 OPAQUE](https://www.rfc-editor.org/rfc/rfc9807.html): passwordをserverへ開示しないaugmented PAKEと、client側export key。
- [RFC 9180 HPKE](https://www.rfc-editor.org/rfc/rfc9180.html): member public keyへSpace Keyを配送する標準hybrid encryption。
- [RFC 8032 Ed25519](https://www.rfc-editor.org/rfc/rfc8032.html): record、membership、identity rotationのsignature。
- [RFC 5869 HKDF](https://www.rfc-editor.org/rfc/rfc5869.html): purpose-separated key derivation。
- [RFC 8949 CBOR](https://www.rfc-editor.org/rfc/rfc8949.html): deterministic encodingを選ぶ場合の標準。
- [RFC 9106 Argon2](https://www.rfc-editor.org/rfc/rfc9106.html): OPAQUE KSF候補。mobile実測後にparameterを固定する。

## 7. 結論

TaskveilはProton Driveのshare keyとsignature、Standard Notesのkey separationとprogressive re-encryption、Signalのidentity verification UXを採る。Signal/MLSのmessage ratchet、Signal Private Group Systemのanonymous credential、Protonのfile key treeは採らない。

これにより、利用するcryptographic building blockは既存標準に寄せつつ、Taskveil固有のprotocolをAccount、Space、Record、membership transition、sync CASの小さな組合せへ限定する。
