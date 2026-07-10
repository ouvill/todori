# Todori 開発ステータス

> 更新日: 2026-07-10

日常の作業開始地点である。完了履歴は各 `task-*.md` とgit、長期計画はPhase計画書、設計判断はADRを参照する。このファイルには現在と直近候補だけを置く。

## 現在

- 進行中: **task-95 Fuzzy-scan full resync / GC horizon** — stable-key current-state scan、`base_seq`後delta、high-water closure、outbox保護付きmark-and-sweepを実装中。
- 最新の完了: **task-94 Rust client境界の命名整理** — 高水準入口を`TodoriClient`、起動設定を`LocalProfileConfig`、低水準transactional型を`SqliteMutationService`へ整理した。Flutter/Dart公開call surface不変を確認し、独立検証でP1 / P2 / P3なし。
- Phase 1: M1〜M4完了。M5リリース準備は人間作業を含む。
- Phase 2: P2-M1〜M5の自律実装完了。macOS + iOS Simulatorの2台同期を確認済み。

## 次の候補（最大3件）

1. **同期server RLS hardening** — non-owner application role、RLS policy、必要な`FORCE RLS`、cross-tenant testを実装する。出典: ADR-012 / task-86。

着手を決めた候補だけをtaskへ昇格する。その他の未着手候補は [`BACKLOG.md`](./BACKLOG.md) を参照する。

## 人間作業・判断

- iOS実機で通知、Keychainゼロプロンプト、同期を通し確認する。
- AWS / Neon本番デプロイと前段構成を決定する。
- 課金 / IAP / レシート検証の仕様をprivate側事業設計と合わせて確定する。
- Android実機で同期動作を確認する。
- public repoの未pushコミットを確認してpushする。

## 作業開始時に読むもの

1. `AGENTS.md`
2. この `STATUS.md`
3. `BACKLOG.md`（次候補以外を検討するときだけ）
4. 昇格済みの対象 `task-*.md`（存在する場合）
5. 対応するPhase計画書・技術仕様・ADR
