---
id: 019f7700-5c50-7a82-b9ed-c1bbe51fc07d
title: Runtime deployment credential boundaries
status: active
lane: critical
milestone: maintenance
---

# Runtime deployment credential boundaries

## 1. 背景とコンテキスト

2026-07-19にプロダクトオーナーは、staging deployment foundationをAWS Lambda、API Gateway HTTP API、Neon、Cloudflare Workerで整備する計画を承認した。現行serverは起動時にmigration owner URLを要求し、選択中のbilling environmentにかかわらずRevenueCat sandbox / production両方のsecretを読むため、stagingとproductionの資格情報境界を満たさない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/03_技術仕様書.md`
- `docs/05_設計判断記録.md`
- `docs/ops/runbook-db-migration.md`
- `docs/ops/runbook-server-deploy.md`
- billing foundation release gate work item
- `server/src/main.rs`、`server/src/billing.rs`、`server/src/db.rs`

## 3. ゴール

通常runtimeからmigration owner資格を外し、billing secretをdeployment environment単位で分離し、Lambdaでsecret valueを環境変数やログへ展開せずに起動できる境界を確立する。

## 4. スコープ

### やること

- 選択中のRevenueCat environmentだけを読み、別environmentのwebhookを拒否する。
- migration専用binaryを追加し、通常server起動時migrationを廃止する。
- DB readiness endpointを追加する。
- AWS Parameters and Secrets Lambda Extensionまたはlocal envからtyped runtime configを構築する。
- Docker imageへserver、migration binary、必要なLambda extensionsを同梱する。
- 技術仕様、ADR、billing work item、運用runbookを同期する。

### やらないこと

- AWS、Neon、Cloudflare resourceを作成しない。
- production deploy、store提出、release tagを行わない。
- billingの商品、価格、entitlement契約を変更しない。

## 5. 実装手順

1. runtime configとsecret sourceの型を追加する。
2. BillingServiceを単一environment configへ変更する。
3. migration binaryとreadiness routeを追加する。
4. Docker / local dev起動契約を更新する。
5. unit / integration testと文書を更新する。

## 6. 受け入れ基準

- [x] staging設定はsandbox secretだけで起動し、production secretを要求しない。
- [x] production設定はproduction secretだけで起動し、sandbox secretを要求しない。
- [x] 別environmentのRevenueCat webhookを拒否する。
- [x] 通常serverは`DATABASE_MIGRATION_URL`なしで起動する。
- [x] migration binaryだけがowner URLで全migrationを再実行可能に適用する。
- [x] `/ready`はDB正常時200、異常時503となり、秘密情報を返さない。
- [x] Lambda secret取得とlocal env fallbackがtestされ、secret valueをログへ出さない。
- [ ] 対象品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- runtime DB loginのnon-owner / RLS検証を弱めない。
- productionにbilling bypassやdevelopment secret fallbackを追加しない。
- 新規依存と外部binaryはversion / digestを固定する。
- public文書へ実resource ID、domain、credentialを記録しない。

## 8. 完了報告に含めるべき内容

- config / migration / readinessの実装結果
- billing environment分離test
- secret非露出確認
- Docker buildと品質ゲート
- 独立検証結果と未解決事項

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-19
- 2026-07-20にTaskveil改名済みの`main`へrebaseし、crate / binaryを`taskveil-server` / `taskveil-migrate`、runtime環境変数を`TASKVEIL_*`、DB roleを`taskveil_app`へ統合した。
- `TASKVEIL_BILLING_ENVIRONMENT`でsandbox / productionの一方だけを選び、選択したprefixのRevenueCat設定だけを読む単一environment contractへ変更した。選択外snapshot / webhookは認証失敗とし、選択外secretがなくても起動できるunit testを追加した。
- 通常serverから起動時migrationと`DATABASE_MIGRATION_URL`を除去した。owner URLを読む`taskveil-migrate` binaryを追加し、既存の冪等migration runnerを専用binaryだけから呼ぶようにした。
- `/health`をprocess livenessのまま維持し、runtime poolで`SELECT 1`する`/ready`を追加した。成功時は200 `{"status":"ready"}`、失敗時は503 `{"status":"unavailable"}`だけを返す。
- LambdaではAWS Parameters and Secrets Lambda Extensionからtyped JSONを取得し、localでは環境変数へfallbackする`RuntimeConfig`を追加した。取得・decode・設定エラーは秘密値を含まない固定messageへ集約した。
- 通常imageとLambda imageへserver / migration binaryを同梱した。Lambda imageはbuild直前に指定されたofficial extension layer ARNを取得し、AWS Lambda Web AdapterとParameters and Secrets extensionを配置する。buildは`Cargo.lock`を含むworkspaceを使い、builder、runtime、Web Adapter imageをmanifest digestで固定する。
- ADR-022、技術仕様、billing release gate、migration / deploy runbookを同じenvironment分離契約へ同期した。

### 検証

- `cargo test -p taskveil-server`: unit 20件、auth 1件、billing 9件、realtime 2件、RLS 1件、sync 21件がPASSした。通常server、billing分離、readiness、runtime secret sourceを含む。
- `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`、`cargo audit --deny warnings`: PASS。
- Flutter release bridge build、`flutter analyze`、`flutter test`、hardcoded string / client boundary check: PASS。
- `docker buildx build --check`はportable / Lambda両DockerfileでPASSした。builder、distroless runtime、Lambda Web Adapterはmanifest digest固定済みである。Parameters and Secrets extensionを実ARNから取得した最終image buildはstaging deploy時の停止条件として再確認する。

### 独立検証・未解決事項

- 判定: 独立検証待ち。実装担当とは別の検証者による再実行を行うまでfront matterを`active`に保つ。
- Neon pooled non-owner role、資格情報不正時の実DB readiness、Lambda extension実起動は、実staging bootstrap後に確認する。
