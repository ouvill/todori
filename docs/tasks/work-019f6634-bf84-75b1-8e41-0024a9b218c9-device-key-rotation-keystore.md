---
id: 019f6634-bf84-75b1-8e41-0024a9b218c9
title: Crash-safe Device Key rotation and Android Keystore
status: done
lane: critical
milestone: P2-M5
---

# Crash-safe Device Key rotation and Android Keystore

## 1. 背景とコンテキスト

Device Keyはgenerationを持たず、SQLCipher rekeyのcrash recovery契約とAndroid本番Keystoreが未実装である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §4.3、§5.3
- `docs/05_設計判断記録.md` ADR-020
- `core/storage/`
- `core/client/`
- `app/rust/`

## 3. ゴール

OS secret storeにactive / pending capsuleを持たせ、SQLCipher rekeyをcrash-safeに完了し、Androidでnon-exportable AES-256-GCM Keystore sealingを使用する。

## 4. スコープ

### やること

- DK generationとDK-wrapped MKを一体化したversioned capsuleを導入する。
- pending保存、`PRAGMA rekey`、再open検証、active昇格、旧capsule削除を実装する。
- 起動時のpending専用rollback / commit recoveryを実装する。
- Android Keystore本番storeを実装し、本番平文`device.key`を拒否する。
- Apple実機runbookとplatform testを更新する。

### やらないこと

- 通常時のactive / pending互換fallbackを提供しない。
- OSからexport可能なAndroid master keyを保存しない。

## 5. 実装手順

1. capsule formatとsecret-store APIをversioned化する。
2. transactional rekey coordinatorとfailure injectionを追加する。
3. Android Keystore bridgeとproduction gateを実装する。
4. Apple / Android実機runbookと自動testを整備する。

## 6. 受け入れ基準

- crash位置ごとに再起動後activeまたはpendingの一方へ収束する。
- pendingはcrash recovery時だけ試され、通常fallbackにならない。
- Android本番buildは平文storeで起動せず、Keystore AES-256-GCM鍵は非exportableである。
- Apple実機でrotation、再起動、DB reopen、Keychainゼロプロンプトを確認する。
- 共通品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- secret、SQLCipher key、capsule plaintextをlogへ出さない。
- 開発 / test用file storeとproduction storeを型・build設定で分離する。

## 8. 完了報告に含めるべき内容

- capsule / rekey / recovery state transition
- failure injection結果
- Android / Apple実機証拠と未実施platform
- production file-store拒否の証拠

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-15
- 結果: DK generation、DK、optional DK-wrapped MKを持つcapsule v2と、`pending保存 -> PRAGMA rekey -> 新鍵再open/旧鍵拒否 -> active昇格 -> pending削除`を実装した。起動時はpendingが存在する場合だけactive / pendingを試してrollbackまたはcommitへ収束し、通常fallbackは行わない。capsuleとsession tokenはcanonical profile root由来の非秘密namespaceでprofile間分離した。
- Platform: Apple productionはData Protection Keychain、Android productionはnon-exportable AES-256-GCM Android Keystore鍵でcapsuleをsealする。release processの平文`device.key` / file capsuleは明示的に拒否する。Android JNI入力とRust capsule buffer、runtime DB keyは不要時にzeroizeする。
- 証拠: 全rotation境界のfailure injection、pendingなしfallback拒否、登録済みMK rewrap、namespace分離testが合格した。macOS署名profileアプリの`flutter drive --profile`を同一profileで2回連続実行し、rotation、DB reopen、再起動後active再利用、Keychain無プロンプトを確認した。JDK 21でAndroid instrumentation testをcompileし、arm64 NDK checkとrelease APK build（98.0 MB、armeabi-v7a / arm64-v8a / x86_64、JNI symbol同梱）が合格した。
- Commit: この完了報告を含むcommit
- 未解決: Android接続実機がないため、`connectedDebugAndroidTest`によるKeystore key non-exportability、active / pending roundtrip、端末再起動後DB reopenは未実施である。個人利用のAndroid外部配布gateはWork 5の実機確認まで保留する。unsigned macOS cargo test binaryはentitlement不足（OSStatus -34018）のため、署名済みmacOS profile appのE2EでApple経路を検証した。

### 独立検証

- 判定: 実装合格。Android実機release gateは未解除。
- 根拠: 初回検証でfailure injection境界、秘密buffer zeroize、test/profile namespace混線、固定global session token、runbook commandを指摘し、すべて修正した。別エージェントがtargeted Rust test、required fmt/clippy、arm64 NDK check、JDK 21 Android test compile、macOS profile drive 2回、Android release APK/JNI symbol、boundary script、secret-log grepを再確認し、実装差分にP0〜P2の残存指摘なしと判定した。
- 検証者: 実装を担当していない独立検証エージェント

### 2026-07-18 Android接続実機追補

上記完了報告のAndroid未実施判定は2026-07-15時点のスナップショットであり、Android部分を次の接続実機証拠で更新する。

- Device: Pixel 7a、Android 16（API 36）、wireless ADB。
- Environment: JDK 21.0.11、Gradle 9.1.0。JDK 26ではAndroid JDK image生成に失敗したため、runbook契約どおりJDK 21を明示した。
- Keystore: `./gradlew connectedDebugAndroidTest`が`BUILD SUCCESSFUL`となり、Keystore AES keyのnon-exportability、active / pending capsule roundtrip、profile namespace分離を確認した。
- Rotation / DB reopen: 同じprofileに対する`flutter drive --profile`を2回連続実行し、両runで`All tests passed`を確認した。DK rotation、新鍵でのSQLCipher DB reopen、旧鍵拒否、プロセス再起動後のactive capsule再利用が成立した。旧鍵拒否時のSQLCipher HMAC failure logは設計どおりで、秘密値はlogへ出ていない。
- 判定: Android platform crypto gateは合格。Android実機同期、課金、本番運用等の非暗号release gateは別途完了するまで一般配布しない。
