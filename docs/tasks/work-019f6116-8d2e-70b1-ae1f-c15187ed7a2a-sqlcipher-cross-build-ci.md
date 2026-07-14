---
id: 019f6116-8d2e-70b1-ae1f-c15187ed7a2a
title: SQLCipher cross-build CI
status: backlog
lane: standard
milestone: M5
---

# SQLCipher cross-build CI

## 1. 背景とコンテキスト

Phase 1ではhostとiOS向けSQLCipher PoCが成立している一方、Phase 1計画書§6にAndroid / iOSクロスビルドの継続検証が未解決事項として残っている。task-91もこのCI整備を後続候補へ移している。vendored SQLCipher / OpenSSLのtarget差分を通常CIで検出できるようにする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/07_Phase1計画書.md` の§3と§6
- `docs/tasks/task-91-phase1-documentation-refresh.md`
- `.github/workflows/ci.yml`
- `.cargo/config.toml`
- `core/crypto/Cargo.toml` / `core/storage/Cargo.toml`

## 3. ゴール

iOSとAndroid向けのSQLCipher依存crateがCIで継続的にcross-buildされ、hostだけでは見えないtoolchain、SDK、vendored native dependencyの破損を検出できる状態にする。

## 4. スコープ

### やること

- 現在のiOS / Android build前提と既存CI runnerを調査する。
- 必要なRust target、Apple SDK、Android NDKを明示的に準備するCI jobを追加する。
- `todori-crypto` と `todori-storage` のSQLCipher経路を両target向けにbuild検証する。
- CI定義と再現用コマンドを必要な運用文書へ記録する。

### やらないこと

- SQLCipher、rusqlite、OpenSSLのdependencyを更新しない。
- local DB schema、鍵導出、製品コードの挙動を変更しない。
- signing、store提出、release配布を自動化しない。
- Android / iOS実機でのruntime検証をCI build成功で代替しない。

## 5. 実装手順

1. 現行CIとローカルで成立しているiOS / Android cross-buildコマンドを確認する。
2. runnerごとにRust target、Xcode / SDK、Android NDKの準備方法を固定する。
3. SQLCipherを含む最小の対象crateをiOSとAndroidへbuildするjobを追加する。
4. cacheが失敗を隠さず、toolchain差分を再現できる構成にする。
5. CI相当のコマンドを実行し、既存のhost / Flutter / boundary gateも維持されることを確認する。
6. 統合HEADを別担当が独立検証する。

## 6. 受け入れ基準

- CIがiOS向け `todori-crypto` / `todori-storage` のSQLCipher経路をcross-buildする。
- CIがAndroid向け `todori-crypto` / `todori-storage` のSQLCipher経路をcross-buildする。
- 必要なRust targetとnative toolchainの準備がworkflowから判別でき、失敗時に対象platformが特定できる。
- `.cargo/config.toml` の `IPHONEOS_DEPLOYMENT_TARGET=15.0` を維持する。
- 既存のRust、Flutter、boundary品質ゲートを削除または緩和しない。
- repositoryの共通品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- 新規external dependencyを追加しない。CI actionやtoolchain追加が必要な場合は、権限と供給網リスクを確認する。
- vendored SQLCipher / OpenSSLをsystem libraryへ置き換えない。
- build検証と実機runtime検証を明確に区別する。
- public/private境界、Phase計画書、製品仕様を変更しない。

## 8. 完了報告に含めるべき内容

- iOS / Androidそれぞれのrunner、target、toolchain、実行コマンド
- SQLCipherを含むことを確認した対象crateとbuild結果
- 既存品質ゲートと独立検証の結果
- CIでは確認できない実機runtime項目と未解決事項
