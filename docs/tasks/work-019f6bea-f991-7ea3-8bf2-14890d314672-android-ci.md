---
id: 019f6bea-f991-7ea3-8bf2-14890d314672
title: Android CI build and emulator gates
status: active
lane: standard
milestone: P2-M5
---

# Android CI build and emulator gates

## 1. 背景とコンテキスト

Android Rust FFI、Flutter release APK build、Android Keystore実装は完了したが、公開文書の一部は未完としたままである。また現行CIはFlutterのhost testを実行するが、Android package build、Keystore instrumentation test、Android上のDevice Key rotationを継続的に検証していない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/08_Phase2計画書.md` P2-M5
- `.github/workflows/ci.yml`
- `docs/09_運用ガイド.md` §8.1.1

## 3. ゴール

Androidの実装済み範囲と未完の実機gateを公開文書で一致させ、Android release APK buildをコードPRのCI gateにする。Android Emulator上のKeystoreとDevice Key rotationは週次および手動CIで検証する。

## 4. スコープ

### やること

- Android進捗の公開文書を整合させる。`docs/01_企画書.md`の変更は2026-07-17のプロダクトオーナー承認に基づく。
- 非docs変更でAndroid arm64 release APKをbuildする。
- 週次scheduleと`workflow_dispatch`でAndroid Emulator testを実行する。
- PRではAndroid Cargo / Gradle cacheをrestore-onlyにする。

### やらないこと

- Pixel 10 / Android 37.1 / 16 KiB page-sizeをCIの必須matrixにしない。
- Emulator testを全PRの必須gateにしない。
- Android実機、通知、2台同期のrelease gateをEmulatorで代替しない。
- product API、DB schema、暗号仕様、FRB公開interfaceを変更しない。

## 5. 実装手順

1. `STATUS.md`、Phase計画書、企画書、READMEのAndroid進捗を整合させる。
2. CIにAndroid arm64 release APK build jobとcacheを追加する。
3. API 36 / Google APIs / x86_64 Emulatorでinstrumentation testとDevice Key rotation testを実行するjobを追加する。
4. classifier、workflow、shell、ローカルAndroid buildを検証する。

## 6. 受け入れ基準

- 非docs PR / main pushでAndroid arm64 release APK build jobが実行される。
- docs-only PRでAndroidの重いjobがskipされる。
- schedule / `workflow_dispatch`でAndroid Emulator test jobが実行される。
- Emulator jobが`connectedDebugAndroidTest`と同一profileのDevice Key rotation test 2回を実行する。
- JDK 21、Flutter 3.44.6、Rust 1.97.0、SDK 36、NDK 28.2.13676358、Emulator Actionのcommit SHAが固定される。
- classifier regression、shell syntax、actionlint、`git diff --check`が合格する。
- Android arm64 release APKに`libtodori_app_bridge.so`が同梱される。

## 7. 制約・注意事項

- Actionはtagではなくimmutable commit SHAで固定する。
- 秘密値をCI logやartifactへ出力しない。
- PRから大容量cacheをsaveしない方針を維持する。
- GitHub実runと独立検証が完了するまで`status: active`を維持する。

## 8. 完了報告に含めるべき内容

- 文書整合の対象と人間承認の記録
- Android build / Emulator jobのtrigger、固定version、cache方針
- ローカルbuildとGitHub Actions実runの結果
- Pixel 10 / Android実機に残すgate

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-17
- 結果: プロダクトオーナー承認に基づき、`STATUS.md`、Phase 1 / Phase 2計画書、企画書、READMEをAndroid Rust FFI / Flutter release APK build / Keystore実装済みの状態へ整合した。CIに非docs変更のAndroid arm64 release APK jobと、週次 / `workflow_dispatch`限定のAPI 36 x86_64 Emulator jobを追加した。Emulator jobはKeystore instrumentation testと同一profileのDevice Key rotation test 2回を実行する。初回の実runで、native threadから文字列指定の`FindClass`を使うとapplication classを解決できない問題を検出し、Kotlinから渡された`AndroidCapsuleStore`をJNI `GlobalRef`として保持する本修正を適用した。
- 固定条件: JDK 21、Flutter 3.44.6、Rust 1.97.0、SDK 36、NDK 28.2.13676358、`ReactiveCircus/android-emulator-runner` commit `a421e43855164a8197daf9d8d40fe71c6996bb0d`。Android Cargo / Gradle cacheはPR restore-only、非PRの成功時だけsaveとした。
- 証拠: classifier regression 14件、shell syntax、Action SHA固定check、actionlint 1.7.12、`git diff --check`が成功した。ローカルのarm64 release APK buildとx86_64 debug APK buildが成功し、release APKへの`lib/arm64-v8a/libtodori_app_bridge.so`同梱を確認した。PR run [29529641483](https://github.com/ouvill/todori/actions/runs/29529641483)はAndroid arm64 release APKを含む全必須jobが成功し、Emulator jobは意図どおりskipされた。手動run [29529651043](https://github.com/ouvill/todori/actions/runs/29529651043)は全jobが成功し、Emulator上でinstrumentation test 2件、Device Key rotation / SQLCipher reopen test 2回が成功した。成功後にx86_64 Android Cargo / Gradle cacheも保存された。
- Commit: Android JNI修正 `1c0cc2e`を含むPR #24のcommit群。
- 未解決: Pixel 10 / Android 37.1 / 16 KiB page-sizeの前方互換確認、Android接続実機でのKeystore / Device Key rotation / DB reopen / 同期release gate、独立検証が残る。

### 独立検証

- 判定: 未実施
- 根拠: GitHub Actions実run後に、実装を担当していない別セッションまたは人間がworkflow trigger、cache条件、APK / Emulator結果を再検証する。
- 検証者: 未定
