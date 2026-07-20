---
id: 019f7700-5e3e-76f2-9e7d-8ffc61004cc8
title: Staging continuous deployment
status: active
lane: critical
milestone: maintenance
---

# Staging continuous deployment

## 1. 背景とコンテキスト

Runtime boundaryとIaC完成後、同一commit SHAからserver / Workerをstagingへ安全に反映し、migration失敗やsmoke失敗時にDBを巻き戻さずcode versionを復旧できるCDが必要である。

## 2. 事前に読むべきファイル

- runtime deployment credential boundaries work item
- staging infrastructure as code work item
- `.github/workflows/ci.yml`
- `docs/ops/runbook-db-migration.md`
- `docs/ops/runbook-server-deploy.md`
- `realtime-worker/README.md`

## 3. ゴール

credentialなしのPR検証、人間承認付きinfra apply、手動から段階的に自動化するstaging deploy、smoke / rollback / provenance記録をGitHub Actionsへ実装する。

## 4. スコープ

### やること

- infra-check、infra-apply、deploy-staging workflowを追加する。
- ECR digest、Worker version、Lambda version / aliasを追跡する。
- migration前後の停止条件、smoke、code rollbackを実装する。
- 3回の手動成功後にmain CI成功から自動deployできるguardを追加する。

### やらないこと

- 実AWS / Cloudflare / Neonへのapplyやproduction deployを行わない。
- DB rollback、store配布、PR preview environmentを追加しない。

## 5. 実装手順

1. credentialなしinfra checkを追加する。
2. environment承認付きapply workflowを追加する。
3. exact SHA deploy、migration、version切替、smoke、rollbackを追加する。
4. workflow classifier / failure fixture / runbookを追加する。

## 6. 受け入れ基準

- [x] fork PRへcloud credentialが渡らない。
- [x] deployは直列化されmigration中にcancelされない。
- [x] migration失敗時はLambda aliasを変更しない。
- [x] smoke失敗時はLambda / Worker codeを直前versionへ戻す。
- [x] DBを自動rollbackしない。
- [x] exact commit / image digest / Lambda version / Worker versionをsummaryへ記録する。
- [x] auto deployは明示variableがtrueのときだけ有効になる。
- [ ] actionlint、shell / failure test、独立検証が合格する。

## 7. 制約・注意事項

- GitHub Actionsはfull commit SHAで固定する。
- secret value、connection string、ticket、UUID、record metadataをlog / summaryへ出さない。
- external applyはcredential保有者の人間承認点として残す。

## 8. 完了報告に含めるべき内容

- workflow trigger / permission / concurrency契約
- failure injectionとrollback結果
- provenance記録例
- credentialなし検証結果
- 実環境で残る人間作業と独立検証結果

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-19
- 2026-07-20にTaskveil改名済みの`main`へrebaseし、workflowのrole session、ECR / Lambda fixture、migration entrypoint、Worker environmentを`taskveil`名義へ統合した。
- `infra-check`はPR / main push / manualで、cloud credentialなしにOpenTofu fmt / validate / mock plan、境界検査、shell syntax、rollback fixtureを実行する。workflow全体のpermissionは`contents: read`だけである。
- `infra-apply`は`workflow_dispatch`、GitHub `staging` Environment承認、OIDCだけでstagingをplan / applyする。Cloudflare tokenは承認後にdeployment-provider secretから読み、production rootは対象にしない。
- `deploy-staging`は初期のmanual exact SHAと、`STAGING_AUTO_DEPLOY_ENABLED=true`設定後のmain CI成功eventだけを受ける。staging Environment、単一concurrency group、`cancel-in-progress: false`を使用する。
- deploy順序をCI成功確認、Worker test / dry-run、digest-pinned ECR push、Critical / High scan拒否、Worker version upload、forward-only migration、Lambda version / alias、Worker promotion、smokeに固定した。
- smokeは`/health`、`/ready`、保護APIの未認証拒否、不正Worker connect / publish拒否を確認する。migration失敗まではaliasを動かさず、切替後の失敗では専用rollback scriptがLambda aliasとWorker deploymentを直前codeへ戻す。DB rollback処理は持たない。
- GitHub Actionsはすべてfull commit SHAへ固定した。成功logにはexact commit、image digest、Lambda version、Worker versionだけを記録し、secret valueやrequest payloadは記録しない。

### Failure fixtureと静的検証

- `tool/ci/test_deploy_rollback.sh`で、切替前、Lambdaだけ切替後、Lambda / Worker切替後の3状態を注入した。切替済みcomponentだけがrollbackされ、DB rollback commandが存在しないことを確認してPASSした。
- official actionlint 1.7.12をchecksum固定で取得するinfra check、全deploy shellの`bash -n`、Action full-SHA / OIDC / production非apply境界検査: PASS。actionlintが検出した未使用shell変数も除去した。
- Workerはtypecheck、Vitest 12件、staging / production dry-runがPASS。統合HEADのRust / Flutter / security / client-boundary品質ゲートもPASSした。

### 人間承認点・独立検証

- 判定: 独立検証待ち。実装担当とは別の検証者によるworkflow / failure fixture再実行までfront matterを`active`に保つ。
- AWS / Cloudflare / Neon / RevenueCatのaccount、MFA、課金、初回OIDC / state bootstrap、secret投入、実applyは人間作業である。
- 実環境では3回連続のmanual deploy、2端末の登録・login・sync、Realtime通知、Cloudflare停止時HTTPS fallback、log allowlist、EU jurisdiction、各failure injectionを確認する。これらが完了するまでauto deploy variableを有効化しない。
