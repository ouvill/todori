# task-76: 運用ドキュメント整備

> ステータス: 完了（運用文書整備）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

Phase 2自律スコープでE2EEマルチデバイス同期、ローカル開発サーバー、2台同期手順、サーバーDB migration、Lambda/ECR/Neon想定のサーバー構成が揃った。一方、実AWS/Neonデプロイやクライアントリリースは人間帰還後であり、public repoに安全に置ける運用手順と、private側/人間管理へ残すべき実値の境界を明文化する必要がある。

本タスクでは、公開リポジトリ向けの運用ガイドとrunbookを整備し、開発運用・サーバー運用・DB migration・障害初動・クライアントリリースの入口を揃える。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/03_技術仕様書.md` §1.5、§2、§6.6、§11.3
- `tool/dev_server.sh`
- `docs/dev/two-device-sync-test.md`
- `SECURITY.md`
- `docs/05_設計判断記録.md` ADR-008 / ADR-009 / ADR-010
- `server/migrations/`
- `server/src/db.rs`
- `server/Dockerfile`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

## 3. ゴール

- `docs/09_運用ガイド.md` を作成し、開発運用、サーバー運用、クライアント運用、セキュリティ運用の索引と全体像をまとめる。
- `docs/ops/` 配下にサーバーデプロイ、DB migration、障害対応、クライアントリリースのrunbookを作成する。
- public repo安全性を維持し、公開不可の運用・事業詳細、実クレデンシャル、実アカウントID、実ドメインを書かない。
- README、`docs/tasks/README.md`、`docs/tasks/BACKLOG.md` を更新する。

## 4. スコープ

### やること

- `docs/09_運用ガイド.md` を作成する。
- `docs/ops/runbook-server-deploy.md` を作成する。
- `docs/ops/runbook-db-migration.md` を作成する。
- `docs/ops/runbook-incident.md` を作成する。
- `docs/ops/runbook-release.md` を作成する。
- `README.md` に運用ガイドへのリンクを追加する。
- `docs/tasks/README.md` と `docs/tasks/BACKLOG.md` にtask-76の状態を反映する。
- `git diff --check` とMarkdown体裁確認を実行する。

### やらないこと

- 実AWS/ECR/Lambda/Neonデプロイ。
- 実クレデンシャル、実アカウントID、実ドメイン、実監視URLの記載。
- 公開不可の運用・事業詳細、価格、レシート検証の詳細記載。
- `docs/01_企画書.md`、`docs/02_機能仕様書.md`、`docs/03_技術仕様書.md` の変更。
- コード変更。
- git commit。

## 5. 実装手順（例）

1. 指定された既存ドキュメントとサーバー構成を読む。
2. `docs/ops/` ディレクトリを作成する。
3. 運用ガイドと4つのrunbookを作成する。
4. READMEとタスク管理文書を更新する。
5. public/private境界、リンク、Markdown見出し、コマンド例を確認する。
6. `git diff --check` とMarkdown体裁確認を実行する。
7. 本指示書の末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

共通受け入れ基準は `docs/tasks/README.md` の「共通受け入れ基準」を満たすこと。

- [x] `docs/09_運用ガイド.md` があり、開発運用、サーバー運用、クライアント運用、セキュリティ運用を扱っている。
- [x] `docs/ops/runbook-server-deploy.md` があり、ECR build/push、Lambda更新、Neon migration適用、クレデンシャル必要箇所、未実施ドラフトであることを明記している。
- [x] `docs/ops/runbook-db-migration.md` があり、sqlx/Postgres migrationの適用・検証・ロールバック方針、expand-contract、`dev_server.sh` によるリハーサル手順を扱っている。
- [x] `docs/ops/runbook-incident.md` があり、サーバーダウン、DB障害、認証障害、セッション大量失効、依存脆弱性、E2EE前提を扱っている。
- [x] `docs/ops/runbook-release.md` があり、ゲート、タグ、ビルド、ストア提出は人間作業、M5連動を扱っている。
- [x] README、`docs/tasks/README.md`、`docs/tasks/BACKLOG.md` が更新されている。
- [x] public repoに公開不可の運用・事業詳細や実クレデンシャルが混入していない。
- [x] `git diff --check` とMarkdown体裁確認を実行している。

## 7. 制約・注意事項

- 実値が必要な箇所は `<PLACEHOLDER>` とし、「private側/人間管理」と明記する。
- サーバーは2026-07-08時点で未デプロイであり、ローカル運用のみ確認済みであることを明記する。
- E2EEのため、サーバー側でユーザーデータを復号できない前提を崩さない。
- `cargo audit` は推奨運用として扱い、導入済み前提にしない。
- `docs/03_技術仕様書.md` の節番号は現行文書に合わせ、インフラ構成は主に§1.5、サーバー不変条件は§6.6を参照する。

## 8. 完了報告に含めるべき内容

- 作業日。
- 作成・更新したファイル一覧。
- 各文書の要点。
- 検証結果（実行コマンド、成功/失敗、失敗時は環境要因かコード要因か）。
- 未解決事項。ない場合は「なし」と明記する。

## 9. 完了報告

作業日: 2026-07-08

### 作成・更新したファイル

- `docs/09_運用ガイド.md`
- `docs/ops/runbook-server-deploy.md`
- `docs/ops/runbook-db-migration.md`
- `docs/ops/runbook-incident.md`
- `docs/ops/runbook-release.md`
- `docs/tasks/task-76-ops-documentation.md`
- `README.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### 実装結果

- 運用ガイドを新設し、開発運用、ローカルサーバー、2台同期、Lambda/ECR/Neon構成、`user_version` 互換方針、セキュリティ運用の入口を整理した。
- サーバーデプロイrunbookを新設し、未デプロイのドラフトであること、ECR build/push、Lambda更新、Neon migration、クレデンシャルのprivate側/人間管理を明記した。
- DB migration runbookを新設し、`server/migrations/*.sql`、`run_migrations`、`dev_server.sh`、前方のみ/expand-contract、ロールバック方針を整理した。
- 障害対応runbookを新設し、サーバーダウン時もクライアントはローカル動作継続、E2EEによりサーバー側復号不可、DB/認証/セッション/同期/依存脆弱性の初動を整理した。
- クライアントリリースrunbookを新設し、M5連動のゲート、タグ、ビルド、ストア提出は人間作業、DB前方migration前提の差し戻し方針を整理した。
- READMEとタスク管理文書にtask-76と運用ガイド導線を追加した。

### 検証結果

- `git diff --check`: 成功。
- Markdown体裁確認: `find docs -name '*.md' -print0 | xargs -0 grep -n $'\\t'` でタブ混入なしを確認。
- `grep -R --exclude=task-76-ops-documentation.md -n -E 'AKIA[0-9A-Z]{16}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|aws_secret_access_key[[:space:]]*=|postgres://[^<]' docs README.md`: 秘密情報実値なしを確認。

### 未解決事項

- なし。
