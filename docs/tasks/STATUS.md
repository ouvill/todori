# Todori 開発ステータス

> 更新日: 2026-07-10

日常の作業開始地点である。完了履歴は各 `task-*.md` とgit、長期計画はPhase計画書、設計判断はADRを参照する。このファイルには現在と直近候補だけを置く。

## 現在

- 進行中: なし。
- 最新の完了: **task-91 frontend共通client境界の基礎固定** — SQLite sync adapterを`todori-client`へ移し、server testのbridge逆依存を除去した。CLI/MCP入口、crate命名、legacy bridge負債の増加防止CIを固定し、独立検証でP1 / P2 / P3なしを確認済み。
- Phase 1: M1〜M4完了。M5リリース準備は人間作業を含む。
- Phase 2: P2-M1〜M5の自律実装完了。macOS + iOS Simulatorの2台同期を確認済み。

## 次の候補（最大3件）

1. **ClientProfile全面移設** — `app/rust/api.rs` / `support.rs`のprofile open、account/session、CRUD/query、settings/reminder、sync coordinatorを`todori-client`へ移し、bridgeのlegacy exceptionと下位crate直接依存を0にする。出典: ADR-011 / task-91。
2. **Fuzzy-scan full resync / GC horizon** — stable-key current-state scan、`base_seq`後delta、high-water closure、outbox除外付きmark-and-sweepを実装する。出典: ADR-010 / ADR-012。ClientProfile全面移設に依存。
3. **同期server RLS hardening** — non-owner application role、RLS policy、必要な`FORCE RLS`、cross-tenant testを実装する。出典: ADR-012 / task-86。

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
