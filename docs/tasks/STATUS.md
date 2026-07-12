# Todori 開発ステータス

> 更新日: 2026-07-13

日常の作業開始地点である。完了履歴は各 `task-*.md` とgit、長期計画はPhase計画書、設計判断はADRを参照する。このファイルには現在と直近候補だけを置く。

## 現在

- 進行中: **task-106 Pomodoro / Stopwatch / Focus Experience** — conditional active、wall-clock engine、通知、専用Focus route、task swipe、見積対実績を実装する。
- 保留: なし。
- 最新の完了: **task-105 Timer Sync Foundation** — task statusと直交するlocal active state、Tenant Root DEK、completed work session同期、削除tombstoneを独立検証まで完了した。
- Phase 1: M1〜M4完了。M5リリース準備は人間作業を含む。
- Phase 2: P2-M1〜M5の自律実装完了。macOS + iOS Simulatorの2台同期を確認済み。

## 次の候補（最大3件）

1. **Canonical Inbox収束** — typed `is_default=true`候補を決定的に統合し、重複Inboxを冪等に解消する。出典: ADR-015 / task-79。
2. **SQLCipherクロスビルドCI** — iOS / AndroidのSQLCipher build差分をCIで継続検証する。出典: Phase 1計画書§6 / task-91。

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
