# 暗号release gate

このrunbookはADR-020の暗号実装を外部配布候補として判定するための公開チェックリストである。自動test、実装担当と独立した内部review、接続実機確認、外部暗号reviewを別の証拠として扱い、未実施項目を別の合格で代替しない。

## 1. 自動gate

次をrepository rootで実行し、すべて成功させる。

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cd app/rust && env CARGO_TARGET_DIR=target cargo build --release
cd ../.. && cd app && flutter analyze && flutter test
cd .. && sh app/tool/check_hardcoded_strings.sh
sh app/tool/check_client_boundaries.sh
sh app/tool/test_client_boundaries.sh
sh tool/check_crypto_dependency_pins.sh
sh tool/check_secret_patterns.sh
cargo audit --deny warnings
cargo +nightly-2026-07-14 fuzz run crypto_parsers -- -max_total_time=60 -timeout=10 -max_len=16384 -dict=fuzz/crypto_parsers.dict
git diff --check
```

`cargo-audit 0.22.2`と`cargo-fuzz 0.13.2`を使用する。auditは脆弱性だけでなくwarning、unmaintained、unsound、yanked dependencyもfail closedにする。fuzzは`nightly-2026-07-14`でenvelope v5、personal manifest、account root、device certificate / identity、hybrid package、signed revocationのparserを同一inputで検査する。16 KiB上限とprotocol magic dictionaryにより、ML-DSA / ML-KEMを含む4 KiB超のcertificate / identity parserも対象にする。CI smokeは60秒であり、長時間campaignやcoverage reviewの代替ではない。

### 1.1 依存更新policy

- Cargo依存を変更するPRは、root workspaceと独立したfuzz crateの両方を解決し、`Cargo.lock`と`fuzz/Cargo.lock`を同時に更新する。片方だけを更新したPRはmergeしない。
- release gateでexact pinする依存と同じ暗号互換性境界にある依存は、通常の自動更新をpatchに限定する。minor / major updateは`lane: critical`のwork item、人間承認、公式vectorを含む全暗号gate、独立暗号reviewを必要とする。
- Dependabot security updateは抑止しない。生成PRが両lockfileを更新できない場合も`--locked`検証を緩和せず、専用worktreeで両lockfileと必要な実装を手動更新する。
- `flutter_rust_bridge`はRust crateとDart packageが同一versionであることを固定契約とし、Cargo単独のversion updateを行わない。

公式vectorと攻撃scenarioの対応は次の通りである。

| 契約 | 再現可能な証拠 |
|---|---|
| RFC 9807 OPAQUE / wrong password / production Argon2id | `cargo test -p taskveil-crypto opaque::tests` |
| BIP39 24語 / 256-bit entropy / checksum / NFKD | `cargo test -p taskveil-crypto key_hierarchy::tests::recovery_key` とzero-entropy vector test |
| FIPS 203 / 204 KATと実primitive | `cargo test -p taskveil-crypto organization::tests` |
| wrong AAD / generation / suite / envelope v3拒否 | `cargo test -p taskveil-sync envelope::tests` |
| preparedからretired、failure injection | `cargo test -p taskveil-client device_key_rotation::tests` と `cargo test -p taskveil-sync rotation::tests` |
| 3端末offline / removal / crash / history / expired device | `cargo test -p taskveil-sync rotation::tests::three_device_offline_removal_crash_and_retirement_converge` とDocker `sync_v2` |
| public-key substitution / certificate / roster / recipient / manifest攻撃 | `cargo test -p taskveil-crypto organization::tests`、`cargo test -p taskveil-sync organization::tests`、Docker `auth_server` |

## 2. Platform実機gate

実機手順は [`docs/09_運用ガイド.md`](../09_運用ガイド.md) §8.1.1を正本とする。各対象platformで同じprofileを2回起動し、DK rotation、process再起動、SQLCipher reopen、secret-store zero prompt、秘密値のlog非露出を確認する。

2026-07-18時点の証拠は次の通りである。

| Platform | Cross / package build | 接続実機runtime | 判定 |
|---|---|---|---|
| macOS | release appとbridge build済み | profile E2Eを2回実行し、Data Protection Keychain、DB reopen、prompt 0回を確認 | crypto platform gate PASS |
| iOS | device / Simulator cross-buildとno-codesign app build済み | 未実施 | iOS外部配布 BLOCKED |
| Android | JDK 21、arm64 NDK cross-build、universal / split release APK build済み | Pixel 7a / Android 16で`connectedDebugAndroidTest`とprofile E2Eを2回実行し、Keystore key non-exportability、active / pending capsule roundtrip、DK rotation、新鍵DB reopen、旧鍵拒否、プロセス再起動後のactive capsule再利用を確認 | crypto platform gate PASS。同期・課金等の非暗号release gateは別途必要 |

## 3. Reviewと表示gate

- Work 1〜4は各実装担当と独立した内部reviewを合格済みである。
- 外部暗号専門家によるreviewは未実施である。外部review報告と指摘解消が完了するまで「監査済み」「audited」と表示しない。
- Organizationのproduct-level multi-tenant招待、別経路Safety確認、全device配送、member / device除名からrotation完了までの実機E2Eは未完了である。
- 課金、store提出、production deploy等の非暗号release gateは本runbookの合格とは別に判定する。

## 4. 現在の判定

2026-07-18時点では、暗号実装の自動gateと内部独立reviewは合格している。macOSとAndroidのplatform crypto gateは実機合格し、iOSの個人利用外部配布、Organization共有の公開、一般リリース、`audited`表示は閉じたままである。Androidの一般配布も同期・課金等の非暗号release gateが完了するまで行わない。
