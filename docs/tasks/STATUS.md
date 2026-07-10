# Todori 開発ステータス

> 更新日: 2026-07-10

日常の作業開始地点である。完了履歴は各 `task-*.md` とgit、長期計画はPhase計画書、設計判断はADRを参照する。このファイルには現在と直近候補だけを置く。

## 現在

- 実装中: **task-89 offline list作成 + key-bundle upload queue** — 重要変更レーン。List DEK生成、local cache、list/state/outbox、bundle queueをatomicに作成し、preflight後・entity push前のimmutable bundle uploadと2-client復号をrelease gateにする。
- 最新の完了: **task-88 typed pull + durable quarantine** — pull failure taxonomy、push前capability preflight、transaction外key refresh、durable quarantine、page単位cursor transaction、quarantine再適用を実装した。production adapter / 実HTTP / Postgres / SQLCipherの回復・停止・rollback gateを含め、独立再検証でP1 / P2 / P3なしを確認済み。
- Phase 1: M1〜M4完了。M5リリース準備は人間作業を含む。
- Phase 2: P2-M1〜M5の自律実装完了。macOS + iOS Simulatorの2台同期を確認済み。

## 次の候補（最大3件）

1. **Fuzzy-scan full resync / GC horizon** — stable-key current-state scan、`base_seq`後delta、high-water closure、outbox除外付きmark-and-sweepを実装する。出典: ADR-010 / ADR-012。task-88までの依存完了。
2. **同期server RLS hardening** — non-owner application role、RLS policy、必要な`FORCE RLS`、cross-tenant testを実装する。出典: ADR-012 / task-86。
3. **SQLCipherクロスビルドCI** — iOS / AndroidのSQLCipher build差分をCIで継続検証する。出典: Phase 1計画書§6。

着手を決めた候補だけをtaskへ昇格する。未着手候補の詳細は [`BACKLOG.md`](./BACKLOG.md) を参照する。

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
