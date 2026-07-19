---
id: 019f6116-8d2e-70b1-ae1f-c15187ed7a2a
title: SQLCipher cross-build CI
status: done
lane: standard
milestone: M5
---

# SQLCipher cross-build CI

## 1. 背景とコンテキスト

host、iOS Simulator core test、iOS実機target link、Android Rust FFI buildは成立している。Androidは後続work itemで、非docs変更ごとのarm64 release APK buildと、週次 / 手動のEmulator runtime testをCIへ導入済みである。一方、iOSは単発のSimulator / no-codesign buildに留まり、継続的なrelease build guardがない。task-74の単発検証とPhase 1計画書§6の残件を、配布構成まで含む継続的なguardへ変える。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/07_Phase1計画書.md` の§3と§6
- `docs/tasks/task-74-multiplatform-verification.md`
- `.github/workflows/ci.yml`
- `.cargo/config.toml`
- `core/crypto/Cargo.toml` / `core/storage/Cargo.toml`

## 3. ゴール

iOS / Androidの配布相当buildが非docs変更ごとにCIで成立し、hostだけでは見えないtoolchain、SDK、vendored native dependency、FRB / Cargokit、packagingの破損を検出できる状態にする。

## 4. スコープ

### やること

- 現在のiOS / Android build前提と既存CI runnerを調査する。
- 既存のAndroid arm64 release APK gateとEmulator gateを維持する。
- 既存のmacOS Flutter jobへiOS arm64 Rust targetとno-codesign release buildを追加する。
- iOS `Runner.app`と埋め込みRust frameworkのarm64 sliceを検証する。
- CI定義と再現用コマンドを必要な運用文書へ記録する。

### やらないこと

- SQLCipher、rusqlite、OpenSSLのdependencyを更新しない。
- local DB schema、鍵導出、製品コードの挙動を変更しない。
- signing、store提出、release配布を自動化しない。
- Android / iOS実機でのruntime検証をCI build成功で代替しない。

## 5. 実装手順

1. 現行CIとローカルで成立しているiOS / Android release buildコマンドを確認する。
2. macOS runnerへiOS arm64 Rust targetを明示し、既存Flutter job内でno-codesign release buildを行う。
3. `Runner.app`と`taskveil_app_bridge.framework`の成果物、arm64 sliceを検証する。
4. Cargokit targetを既存cacheへ含め、PRのrestore-only方針を維持する。
5. CI相当のコマンドを実行し、既存のhost / Flutter / boundary gateも維持されることを確認する。
6. 統合HEADを別担当が独立検証する。

## 6. 受け入れ基準

- CIが非docs変更ごとにiOS no-codesign release appをbuildし、`taskveil-client`経由の`taskveil-crypto` / `taskveil-storage`を含むarm64 Rust frameworkを埋め込む。
- CIが非docs変更ごとにAndroid arm64 release APKと`libtaskveil_app_bridge.so`を検証する既存gateを維持する。
- Android Emulator runtime testは週次scheduleと手動実行に限定し、iOS Simulator runtime testは追加しない。
- 必要なRust targetとnative toolchainの準備がworkflowから判別でき、失敗時に対象platformが特定できる。
- `.cargo/config.toml` の `IPHONEOS_DEPLOYMENT_TARGET=15.0` を維持する。
- 既存のRust、Flutter、boundary品質ゲートを削除または緩和しない。
- repositoryの共通品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- 新規external dependencyを追加しない。CI actionやtoolchain追加が必要な場合は、権限と供給網リスクを確認する。
- vendored SQLCipher / OpenSSLをsystem libraryへ置き換えない。
- build検証と実機runtime検証を明確に区別する。
- public/private境界と製品仕様を変更しない。Phase計画書はCIの現状記述だけを更新する。

## 8. 完了報告に含めるべき内容

- iOS / Androidそれぞれのrunner、target、toolchain、実行コマンド
- SQLCipherを含むことを確認した対象crateとbuild結果
- 既存品質ゲートと独立検証の結果
- CIでは確認できない実機runtime項目と未解決事項

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-17
- 結果: 既存のmacOS `Flutter quality gates`に`aarch64-apple-ios` target、iOS no-codesign release build、`Runner.app`と埋め込みRust frameworkのarm64検証を追加した。Android arm64 release APK / JNI gateと週次・手動Emulator gateは維持した。
- cache: CIでだけCargokitのCargo targetを`app/target`へ固定し、`flutter-rust-ios-v1` keyと旧key fallbackを追加した。PRはrestore-only、main成功時だけsaveする既存方針を維持した。
- iOS証拠: persistent targetのcold buildはXcode 364.6秒で成功し、`Runner.app` 77.9MB、`app/target` 717MB、埋め込み`taskveil_app_bridge.framework` arm64を確認した。同targetのwarm buildはXcode 10.7秒で成功した。
- dependency証拠: `taskveil_app_bridge -> taskveil-client -> taskveil-crypto / taskveil-storage`のiOS target dependency経路と、`app/target/aarch64-apple-ios`の各成果物を確認した。
- Commit: `83afb45`
- 未解決: iOS / Android実機のKeychain / Keystore、通知、購入・復元、DB reopen、同期は従来どおりrelease gateに残る。iOS buildは`taskveil_app_bridge`のSwift Package Manager非対応に関するFlutterの将来error予告を出すが、現行のCocoaPods buildは成功する。

### 品質ゲート

- `cargo fmt --all -- --check`: PASS
- `cargo clippy --workspace --all-targets -- -D warnings`: PASS
- `cargo test --workspace`: PASS。sandbox内の初回はlocal socket拒否で2件失敗したが、sandbox外の再実行でserver integration testを含む全件が成功した。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: PASS
- `cd app && flutter analyze`: PASS
- `cd app && flutter test`: PASS（257件、Visual QA harness 1件は設計どおりskip）
- `sh app/tool/check_hardcoded_strings.sh`: PASS
- `sh app/tool/check_client_boundaries.sh`: PASS
- `sh app/tool/test_client_boundaries.sh`: PASS
- `sh tool/ci/test_classify_changes.sh`: PASS
- `git diff --check`: PASS

### 独立検証

- 判定: 合格
- 根拠: 別担当が統合差分、classifier全case、shell構文、common gate、iOS cold / warm build、persistent target成果物、Runner / framework arm64、Android gate維持、cache key / fallback / PR restore-only、文書とpublic/private境界を再確認した。cache pathが当初実体を持たない点を指摘し、Cargokitのpersistent target override追加後のcold / warm buildで解消を確認した。未解決のP1 / P2 / P3指摘はない。
- 検証者: 実装を担当していない別エージェント
