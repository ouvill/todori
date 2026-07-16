---
id: 019f6c6a-121f-7363-aa7a-e84ba20ec454
title: Crypto dependency major upgrade
status: backlog
lane: critical
milestone: maintenance
---

# Crypto dependency major upgrade

## 1. 背景とコンテキスト

Dependabotの通常更新から分離した、暗号依存とplatform依存の破壊的更新をmaintainer PRで評価する。exact pin、両lockfile、暗号release gateを維持し、Dependabot branchは直接修理しない。

`opaque-ke`、hash / KDF / MAC、AEAD、乱数は型とtraitを共有する互換性境界である。`x25519-dalek`は鍵API、`jni`はAndroid platform APIへ影響するため、同じdiffへ混在させない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/ops/crypto-release-gate.md`
- `docs/03_技術仕様書.md`
- `docs/05_設計判断記録.md` ADR-020
- `Cargo.toml`
- `fuzz/Cargo.toml`
- `tool/check_crypto_dependency_pins.sh`

## 3. ゴール

破壊的依存更新を互換性のある単位で実施し、algorithm、context string、serialized / wire形式、FRB公開面を意図せず変更していないことを公式vectorと全release gateで証明する。

## 4. スコープ

### やること

- `opaque-ke`、`sha2`、`hkdf`、`hmac`、`chacha20poly1305`、`rand`を互換性のある1セットとして評価する。
- `opaque-ke`が`digest 0.11`へ対応する安定版を持たない場合、hash / KDF系だけを部分更新せず、互換セット全体を保留する。
- `x25519-dalek`の移行を暗号互換セットとは別コミットにする。
- `jni`の移行をAndroid platform API変更として別コミットにする。
- 各更新単位で`Cargo.lock`と`fuzz/Cargo.lock`を生成し、双方の`cargo metadata --locked`を通す。
- 公式暗号vector、OPAQUE、AEAD / HKDF、Organization、rotation、negative testを実行する。
- FRB regenerate / build、Flutter test、Android Rust cross-build、release APK build、fuzz、auditを実行する。
- 実装者と異なるreviewerによる独立暗号reviewを受ける。

### やらないこと

- Dependabot branchを直接修理しない。
- hash / KDF系だけを先行更新してOPAQUE互換境界を分断しない。
- algorithm、context string、serialized / wire形式、FRB公開面を無承認で変更しない。
- release gate、exact pin、`--locked`を緩和しない。

## 5. 実装手順

1. 実装開始時の最新mainから、このwork item専用のbranch / worktreeを作成する。
2. upstream release noteと公式仕様を確認し、互換セットのversion候補とmigration差分を記録する。
3. OPAQUE互換セットを1コミット、`x25519-dalek`を別コミット、`jni`を別コミットとして移行する。
4. 各コミットで両lockfileを再生成し、意図しないtransitive dependency変更をreviewする。
5. 全暗号・FRB・Flutter・Android・fuzz・audit gateを実行する。
6. platform依存を変更した場合は、該当する接続実機gateを実施する。
7. 独立暗号review合格後にのみmerge可能とする。

algorithm、context string、serialized / wire形式、FRB公開面の変更が必要になった場合は作業を止め、このwork item内で影響、migration、互換性方針を追記して設計承認を取り直す。

## 6. 受け入れ基準

- official crypto vectors、OPAQUE、AEAD / HKDF、Organization、rotation、negative testが全件成功する。
- root / fuzz双方のlockfileが更新され、pin checkと双方のlocked metadataが成功する。
- FRB regenerate / build、Flutter test、Android Rust cross-build、release APK buildが成功する。
- parser fuzzと`cargo audit --deny warnings`が成功する。
- algorithm、context string、serialized / wire形式、FRB公開面が不変であるか、変更時の再承認が記録されている。
- platform依存変更時の接続実機gateが成功する。未実施の場合は`release blocked`を維持する。
- 実装者と異なるreviewerの独立暗号reviewが合格する。
- 独立暗号review合格までmerge・releaseしない。

## 7. 制約・注意事項

- `lane: critical`として人間承認と独立検証を必須にする。
- 依存versionを上げること自体を目的にせず、暗号互換性とplatform接続性を優先する。
- 実機gateを環境都合で省略した場合は成功扱いにせず、release blockとして明記する。
- public repoへprivate情報を含めない。

## 8. 完了報告に含めるべき内容

- 採用したversion setとupstream根拠。
- commit単位のmigration境界と両lockfileの差分説明。
- algorithm、context string、serialized / wire形式、FRB公開面の不変確認。
- 全gateのcommandと結果、接続実機の対象端末。
- 独立暗号reviewer、判定、未解決risk。
