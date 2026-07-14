---
id: 019f6116-8c37-78a2-9ba3-06c03d2a3ea0
title: Canonical Inbox convergence
status: done
lane: critical
milestone: maintenance
---

# Canonical Inbox convergence

## 1. 背景とコンテキスト

複数deviceがdefault Inboxを独立作成した場合、typed plaintextの `is_default=true` 候補が複数存在し得る。task-79では同期後の一時的なlocal demotionで重複表示を抑えたが、local rowと認証済みplaintextの意味が一致しない状態が残る。ADR-015で決定したcanonical Inbox収束を実装し、この暫定状態を解消する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/05_設計判断記録.md` のADR-015
- `docs/tasks/task-79-sync-real-device-regressions.md`
- default Inboxの生成、同期、local保存を担う `core/client` / `core/sync` / `core/storage` の実装とテスト

## 3. ゴール

認証済みtyped plaintext上のliveなdefault Inbox候補を決定的に1件へ収束させ、複数deviceが同じcanonical Inboxを参照する状態を冪等に実現する。

## 4. スコープ

### やること

- ADR-015の候補抽出、canonical選択、alias保持、収束規則を実装する。
- canonical UUIDを候補UUIDの最小値として決定する。
- local aliasを永続化し、旧候補を参照する操作をcanonicalへ解決する。
- multi-device、再同期、再起動を含む回帰テストを追加する。

### やらないこと

- serverへdefault Inboxのplaintext pointerを追加しない。
- Inbox名の文字列比較をdefault判定へ使わない。
- wire protocolやE2EE境界へ不要な互換layerを追加しない。
- task-79の履歴を書き換えない。

## 5. 実装手順

1. 現在のdefault Inbox生成、同期apply、local demotionの経路と不変条件を特定する。
2. ADR-015どおり、認証済みtyped plaintextからliveな `is_default=true` 候補を収集する。
3. UUID最小値をcanonicalとして選び、aliasを永続化して参照解決へ適用する。
4. 新規accountの単一default生成と既存accountの収束を同じ不変条件で扱う。
5. 暫定demotionを正しい収束処理へ置き換え、multi-device回帰テストを追加する。
6. 統合HEADで品質ゲートを実行し、別担当による独立検証を行う。

## 6. 受け入れ基準

- 複数のliveなdefault候補があるとき、全deviceがUUID最小値の同じcanonical Inboxへ収束する。
- 収束処理を繰り返しても結果が変わらず、再起動後もaliasが維持される。
- 旧候補を参照するlocal操作と同期recordがcanonicalへ解決され、ユーザーのtaskを失わない。
- default判定は認証済みtyped plaintextに基づき、server plaintextや表示名heuristicへ依存しない。
- 新規accountではdefault Inboxが1件だけ作成される。
- task-79で確認された実機同期regressionを再発させない自動テストがある。
- repositoryの共通品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- `lane: critical` とし、ADR-015を実装契約の正本にする。契約変更が必要なら実装前にADRを更新して人間承認を得る。
- local DB、同期protocol、暗号境界へ触れる場合も、pre-release方針に従いfallbackや二重経路を追加しない。
- 復号済みplaintext、鍵、tokenをログや完了報告へ含めない。
- public/private境界を変更しない。

## 8. 完了報告に含めるべき内容

- 実装したcanonical選択、alias永続化、参照解決の概要
- 追加・更新したmulti-deviceと冪等性テスト
- 実行した品質ゲートと独立検証の結果
- ADR-015との差分、残る実機確認、未解決事項

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-15
- 結果: schema v19のdurable `list_aliases`、認証済みtyped plaintextからのUUID最小選挙、closure / quarantine guard、単一`BEGIN IMMEDIATE`内のcanonical materialization、alias配下taskのplacement更新とcanonical List DEK再暗号化、旧alias IDのlocal CRUD解決を実装した。通常sync、full resync、quarantine replay、後着alias task、再起動を同じ冪等な収束規則で扱う。
- 証拠: `todori-storage` 89 passed / 1 ignored、`todori-sync` 68 passed、`todori-client` 43 unit + 4 doc passed。後着のより小さい候補、alias flatten、live list quarantine保留、鍵不足rollback、canonical DEK再暗号化、再起動後alias、削除済みlistの空結果契約を自動テストで確認した。
- Commit: `b787b5e` (`feat(sync): converge canonical inbox`)
- ADR-015との差分: なし。server-visibleなcanonical pointerやplaintext metadataは追加せず、alias list recordとList DEK bundleを保持する。
- 未解決: なし。実機2台での再確認は追加の運用観測として未実施であり、自動テストと独立品質ゲートの合否には影響しない。

### 独立検証

- 判定: 合格
- 根拠: 実装を担当していない検証担当が統合HEADを静的レビューし、初回に検出した削除済みlistの`getTasks`回帰を修正後に再検証した。`git diff --check`、`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`（server integrationを含む）、`sh app/tool/check_client_boundaries.sh`、`sh app/tool/test_client_boundaries.sh`、`cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`、`cd app && flutter analyze`、`cd app && flutter test`、`sh app/tool/check_hardcoded_strings.sh`が成功した。Flutterは232件成功、Visual QA harness 1件のみ仕様どおりskipした。
- 検証者: 実装を担当していない独立検証サブエージェント
