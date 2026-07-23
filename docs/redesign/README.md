# Taskveil redesign foundations

> 状態: 2026-07-23 product owner承認済みbaseline。未実装。
>
> 基点: local `main` commit `017e53a`、2026-07-23。

## 1. 目的

Taskveilを、個人のtask管理と家族・友人との共有を提供するlocal-first E2EE TODOアプリとしてゼロから再定義する。本ディレクトリは、実装を始める前に製品要件、保証範囲、鍵、同期、共有の境界を合意するための設計案である。

既存実装、local DB、server schema、wire protocolとの互換性は前提にしない。本baselineは2026-07-23にproduct ownerが採用を承認した。`docs/01_企画書.md`、`docs/02_機能仕様書.md`、`docs/03_技術仕様書.md`、`docs/05_設計判断記録.md`を本baselineへ整合し、旧実装と旧ADRは互換対象ではなく履歴として扱う。

## 2. 読む順

1. [Product requirements](./product-requirements.md)
2. [Threat model](./threat-model.md)
3. [Cryptography and key management](./cryptography-and-key-management.md)
4. [Sync model](./sync-model.md)
5. [Sharing model](./sharing-model.md)
6. [Prior art](./prior-art.md)
7. [Decision record and open questions](./decisions-and-open-questions.md)

## 3. 設計の要約

- Taskveilは一般的な高機能TODOの便利さをE2EEのために大きく削らない。検索、filter、calendar、recurrence、reminder、template、timer等はclient側で実現する。
- 完了taskと完了したwork sessionは利用者の成果記録として通常は保持する。永久削除は明示的な例外操作とする。
- 添付fileは扱わない。課金利用者のserver上の暗号化structured dataは約1 GiBを安全上限の目安とする。
- accountごとに1つの`Personal Space`、共有関係ごとに`Shared Space`を持つ。`Space`は暗号鍵、同期、membership、quotaの境界を表す、本設計で定義する唯一の主要な独自用語である。
- serverはaccount、device session、Space、membership、role、key generation、opaque record、ciphertext size、trafficを知る。taskの内容、種類、status、date、hierarchy、timerとの関係は知らない。
- password認証はOPAQUEを候補とし、password由来のunlock keyとrandomなaccount root keyを分離する。
- Spaceの各recordはcurrent Space Key generationから導出した鍵でAEAD暗号化し、authorが署名する。
- serverはcurrent record headを保持するopaque storeであり、plaintextのmerge、search、notification schedulingを行わない。
- 共有ではserverのrole-based access controlと暗号学的key possession/signatureを併用する。
- 新規memberには保持中の全Space Key generationを渡し、過去dataを読めるようにする。
- member除外時はserver accessを直ちに失効させ、新generationのSpace Keyを残存memberへ配る。旧recordは一括再暗号化せず、次の編集時にcurrent generationへ移す。
- Double Ratchet、MLS、Signal Private Group System相当の匿名credential、独自key transparencyは初期製品へ入れない。

## 4. 用語

| 用語 | 定義 |
|---|---|
| E2EE | plaintextと復号鍵を正規endpoint以外へ渡さず、serverやnetworkだけでは内容を読めないend-to-end encryption |
| client / endpoint | Taskveilを実行し、利用者の鍵と復号済みdataを扱う端末上のapp |
| server | 認証、session、access control、key envelope、opaque encrypted record、quota、通知wake-upを扱うservice |
| Account | login、recovery、device、長期identityの単位 |
| Space | 同じmembership、Space Key generations、sync cursor、quotaを共有する暗号・認可境界 |
| Personal Space | 1 AccountだけがmemberであるprivateなSpace。private list数やrecord種別をserverから隠す |
| Shared Space | 家族・友人と共有するSpace。初期UIでは1つの共有listに対応する |
| Record | serverが中身を解釈せず保存する、1件の暗号化同期単位 |
| Key generation | membership変更等で更新されるSpace Keyの世代。単調増加する番号を持つ |
| Key envelope | ある鍵を別の鍵で暗号化し、許可されたrecipientだけが復号できるobject |
| AEAD | 暗号化と改ざん検知を同時に行うauthenticated encryption |
| Signature | author private keyによる電子署名。共有鍵を知る別memberやserverによるauthor偽装を検出する |
| Tombstone | plaintext contentを持たず、recordが永久削除済みであることだけを表す同期状態 |
| Local-first | network成功を待たずlocal encrypted DBへ操作を確定し、後から同期する動作 |
| Progressive re-encryption | 旧generationのrecordを一括処理せず、そのrecordが編集された時にcurrent generationで暗号化し直すこと |

## 5. 文書上の規則

- `MUST`は安全性またはdata correctnessのため必須、`SHOULD`は強い推奨、`MAY`は任意を意味する。
- algorithm名は設計候補であり、実装前にlibrary、test vector、cross-platform support、auditabilityを含むADRで固定する。
- 「serverから隠す」はserverがそのplaintext fieldを取得しないことを意味する。traffic、size、timing、membershipからの推測まで防ぐ意味ではない。
- `1 GiB`は公開可能な製品安全上限の目安であり、価格、原価、plan構成を定めない。
