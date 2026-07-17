---
id: 019f6116-8d2e-70b1-ae1f-c15187ed7a2a
title: SQLCipher cross-build CI
status: active
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
3. `Runner.app`と`todori_app_bridge.framework`の成果物、arm64 sliceを検証する。
4. Cargokit targetを既存cacheへ含め、PRのrestore-only方針を維持する。
5. CI相当のコマンドを実行し、既存のhost / Flutter / boundary gateも維持されることを確認する。
6. 統合HEADを別担当が独立検証する。

## 6. 受け入れ基準

- CIが非docs変更ごとにiOS no-codesign release appをbuildし、`todori-client`経由の`todori-crypto` / `todori-storage`を含むarm64 Rust frameworkを埋め込む。
- CIが非docs変更ごとにAndroid arm64 release APKと`libtodori_app_bridge.so`を検証する既存gateを維持する。
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
