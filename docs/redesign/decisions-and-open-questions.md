# Decision record and open questions

> 状態: 2026-07-23 product owner承認済みbaseline（未実装）

## 1. Decisions in this proposal

| ID | Decision | Reason |
|---|---|---|
| D-01 | Initial productは個人TODOと家族・友人共有に限定する | enterprise policy/recoveryをkey hierarchyへ混ぜない |
| D-02 | Personal Space 1つと、共有listごとのShared Spaceを使う | private list数をserverから隠し、共有を独立したmembership/key境界にする |
| D-03 | Shared Space membership/role/ownerはserver-visibleにする | 通常のRBACを使い、Signal Private Group System相当の複雑さを避ける |
| D-04 | Record kindと全domain fieldをencryptedにする | serverがtask/date/status/hierarchy/timerを知る必要がない |
| D-05 | Account identityはEd25519 signing keyとX25519 HPKE keyを持つ | content AEADとauthor authenticity、member key deliveryを分離する |
| D-06 | password由来AUKとrandom ARK/Space Keyを分離する | password change/recoveryでcontent再暗号化を避ける |
| D-07 | password authenticationはOPAQUEを第一候補にする | passwordをserverへ渡さず、標準aPAKEとclient export keyを利用する |
| D-08 | Space Keyからrecord IDごとにHKDFでRecord Keyを導出する | attachment/per-record shareがなく、random per-record DEK wrapを省ける |
| D-09 | contentはAEAD暗号化し、outer envelope全体をauthor署名する | viewer/shared-key holder/serverによるauthor偽装を検出する |
| D-10 | serverはcurrent head + CAS + cursorを持つopaque Record storeとする | plaintext mergeと無期限event logを避ける |
| D-11 | client typed 3-way mergeとConflict Recordを使う | common editを自動収束させ、same-field candidateも失わない |
| D-12 | Completion RecordとWork Sessionをimmutable recordにする | 完了/reopen/時間訂正後も成果履歴を残す |
| D-13 | permanent deleteはterminal TombstoneをSpace存続中保持する | stale resurrectionを単純に防ぎ、device lease/GC protocolを避ける |
| D-14 | new memberへ全historical Space Keyを渡す | 過去data閲覧というproduct contractを満たす |
| D-15 | member removalでaccess revokeとfresh Space Key generationをatomic commitする | old memberをnew contentから外す |
| D-16 | removal時にold Recordをbulk re-encryptしない | long-running migration、battery、failure recoveryを避ける |
| D-17 | old Recordのedit時はwhole Recordをcurrent generationで再暗号化する | progressive re-encryptionを例外なしで単純化する |
| D-18 | owner transferはold owner proposal + target acceptance + server transactionにする | owner 0/2人とforced transferを防ぐ |
| D-19 | invitation fragment/QR secretで初回identity keyをbindする | custom key transparencyを作らずserver key substitutionを防ぐ |
| D-20 | active timerはdevice-local、completed workだけPersonal Spaceへ同期する | 秒単位syncとdistributed lockを避け、個人実績を残す |
| D-21 | 添付fileを扱わない | structured TODOにscopeを絞り、object crypto/quota/previewを不要にする |
| D-22 | 課金Accountのencrypted structured dataは約1 GiBを安全上限目安にする | completed historyを長期保持しつつabuse/costを有限にする |
| D-23 | quota超過でもlocal read/edit、pull、delete、exportを許可する | service状態でlocal dataを人質にしない |
| D-24 | Double Ratchet、MLS、anonymous group credentialを採用しない | long-lived TODO current stateと要件が合わず過剰である |
| D-25 | Password/recovery transitionをAccount署名とsecurity revision CASで認可する | registration/wrapperの第三者置換とpartial updateを拒否する |
| D-26 | Personal Work SessionのShared Task参照をsoft external referenceにする | 共有Taskの削除/access喪失で個人成果記録をcascade deleteしない |
| D-27 | 正規editorによる意図的破壊をsecurity guaranteeに含めない | editorは正規鍵とwrite/delete権限を持ち、署名は旧contentを復元しない |

## 2. Cross-document invariants

実装仕様へ昇格するとき、次を変更するには明示的なthreat-model reviewとADRを必要とする。

1. serverはRecord kind、task field、relation、timer fieldをdecryptしない。
2. server RBACとclient cryptographic validationのどちらも省略しない。
3. author signatureをshared symmetric AEADで代用しない。
4. Account/Space keysをpassword、email、IDから直接導出しない。
5. removed memberへnew generation keyを配らない。
6. old-generation new mutationをserver/clientが受理しない。
7. new memberのhistorical accessを「join後だけ」へsilent変更しない。
8. permanent deleteを通常整理にしない。
9. quota/subscription状態でlocal data read/exportを禁止しない。
10. enterprise admin recoveryを個人/家族Spaceへ後付けしない。
11. unknown protocol/suiteをfallbackでdecryptしない。
12. active timer tickを同期正本にしない。

## 3. Replacement applied to the public baseline

2026-07-23の人間承認後、次のbreaking redesignを公開正本へ反映した。既存実装は未変更であり、new baselineへ未準拠である。

| Area | Applied treatment |
|---|---|
| `docs/01_企画書.md` | initial product、enterprise除外、completed history、timer、約1 GiB quotaへ更新済み |
| `docs/02_機能仕様書.md` | Account/Space、一般TODO、shared roles、historical access、removal semanticsへ更新済み |
| `docs/03_技術仕様書.md` | algorithm/key/sync/server metadata baselineへ更新済み |
| `docs/05_設計判断記録.md` | ADR-023で旧判断の履歴とsupersede関係を記録済み |
| `docs/07_Phase1計画書.md` / `docs/08_Phase2計画書.md` | 既存完了履歴を維持し、legacy implementation planと明示済み |
| Existing implementation | 未変更。migration/compat layerなしの置換範囲はfuture implementation work itemで決める |

本work itemでは公開正本文書だけを変更し、implementationを変更しない。

## 4. Decisions deliberately deferred

設計の骨格を変えない実装前decision:

- OPAQUE library、exact RFC ciphersuite、Argon2id mobile parameter、server key/HSM配置。
- XChaCha20-Poly1305 library、deterministic CBOR profile、binary framing。
- Record max plaintext/ciphertext sizeとpadding bucket。
- Recovery Keyのhuman-readable encoding、checksum、print/export UX。
- invitation expiry、member count、rate limit。
- server delta-log retentionとfull-resync page size。
- push providerとgeneric wake-up payload。
- local DB engine、OS secure storage policy、app lock policy。
- exact free quota、warning threshold、billing/grace policy。
- backup expiryとlogical deletion SLA。
- external audit/release gate provider。

これらは「未決だから例外fallbackを入れてよい」という意味ではない。実装前ADRで1つを選び、test vectorとmigration/versionを持たせる。

## 5. Product decisions confirmed by product owner

次は2026-07-23のbaseline採用承認に含まれる。個別に変更する場合は本書と関連仕様を同じwork itemで更新する。

1. Shared Spaceは初期UIで1 listに対応し、serverはShared Space数/membershipを知る。
2. editorもpermanent deleteできる。owner-only policyは初期scope外である。
3. new memberは全historical keyを受け取り、permanent deleted以外の過去dataをすべて読める。
4. non-owner leave時、owner rekeyまでShared Space writeが一時freezeし得る。
5. owner transferでencrypted-byte quotaの負担もtargetへ移る。
6. Completion Recordはtask reopen後も残り、同じtaskを複数回completeした履歴を持つ。
7. Shared Taskに対する個人Work Sessionは共有せず、本人のPersonal Spaceにsoft external referenceとsnapshotを置き、Task削除/access喪失後も残す。
8. TombstoneはSpace存続中保持し、quota対象にする。
9. Web clientはinitial must-haveにせず、code-delivery/key-storage threatを別評価する。
10. Recovery Keyも既存deviceもないresetでは旧dataをsupportが復旧しない。

## 6. Required follow-up before implementation

1. Independent security/design reviewerがthreat model、invitation、remove/owner-transfer state machineをreviewする。
2. `docs/01`、`docs/02`、`docs/03`、ADRを本baselineへ整合する（完了）。
3. Crypto suite/encoding ADRとtest vector documentを作る。
4. Sync CAS/merge/Tombstone protocol ADRとstate-machine test planを作る。
5. Sharing invitation/membership/key generation ADRとmodel test planを作る。
6. Local storage/recovery UX、server metadata/privacy、quota/retentionを個別設計する。
7. その後にのみimplementation work itemをdependency順に分割する。

## 7. Approval checklist

- [x] Product scopeとinitial exclusionsに合意した。
- [x] Server-visible metadata inventoryを許容した。
- [x] OPAQUE/ARK/Space Key/signatureの形に合意した。
- [x] New member historical accessとhistorical keyringを確認した。
- [x] Removal時no bulk re-encryption + edit時current generationを確認した。
- [x] Owner transfer/leaveのavailability trade-offを確認した。
- [x] Completion/Work Session retentionと約1 GiB quotaを確認した。
- [x] Explicit non-guaranteesをproduct copyでも隠さないことに合意した。
- [x] 正本更新を完了し、implementationをfuture work itemへ分離した。
