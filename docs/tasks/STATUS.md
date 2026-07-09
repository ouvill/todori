# Todori 開発ステータス

> 更新日: 2026-07-10

日常の作業開始地点である。完了履歴は各 `task-*.md` とgit、長期計画はPhase計画書、設計判断はADRを参照する。このファイルには現在と直近候補だけを置く。

## 現在

- 実装中: なし
- 最新の決定: task-82 / ADR-012で、同期correctnessをfield clock、placement、transactional outbox、cascade tombstone、typed pull failure、snapshot full resyncの一体として保証する方式を採用した。現行同期実装は未準拠であり、release blockerとして扱う。
- Phase 1: M1〜M4完了。M5リリース準備は人間作業を含む。
- Phase 2: P2-M1〜M5の自律実装完了。macOS + iOS Simulatorの2台同期を確認済み。

## 次の候補（最大3件）

1. **production同期テスト + transactional client基盤** — production CRUD経路を通る2-client/crash-windowテストを先に追加し、domain更新、outbox、sync state、local HLCを共通client層の同一transactionへ移す。出典: ADR-011 / ADR-012 / task-82。
2. **field clock + placement同期** — `revision_hlc` と `field_hlcs` を分離し、taskの `list_id` / `parent_task_id` / `sort_order` をcompound placementとして同期する。rank collision、push結果照合、collection固定も含む。出典: ADR-012 / task-82。
3. **cascade tombstone + typed pull** — subtree/list配下全recordのtombstone、list key bundle削除状態、missing DEK / corrupt / unknown protocol時のcursor規約を実装する。出典: ADR-010 / ADR-012 / task-82。

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
