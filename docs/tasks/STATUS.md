# Todori 開発ステータス

> 更新日: 2026-07-10

日常の作業開始地点である。完了履歴は各 `task-*.md` とgit、長期計画はPhase計画書、設計判断はADRを参照する。このファイルには現在と直近候補だけを置く。

## 現在

- 進行中: なし。
- 最新の完了: **task-88 typed pull + durable quarantine** — pull failure taxonomy、push前capability preflight、transaction外key refresh、durable quarantine、page単位cursor transaction、quarantine再適用を実装した。production adapter / 実HTTP / Postgres / SQLCipherの回復・停止・rollback gateを含め、独立再検証でP1 / P2 / P3なしを確認済み。
- Phase 1: M1〜M4完了。M5リリース準備は人間作業を含む。
- Phase 2: P2-M1〜M5の自律実装完了。macOS + iOS Simulatorの2台同期を確認済み。

## 次の候補（最大3件）

1. **offline list作成 + key bundle queue** — List DEK生成、local cache、list row、entity outbox、key-bundle upload queueをatomicに作り、bundleをrecordより先にidempotent uploadする。出典: ADR-013 / task-84未解決事項。

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
