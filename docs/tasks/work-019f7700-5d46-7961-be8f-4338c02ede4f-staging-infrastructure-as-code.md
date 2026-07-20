---
id: 019f7700-5d46-7961-be8f-4338c02ede4f
title: Staging infrastructure as code
status: active
lane: critical
milestone: maintenance
---

# Staging infrastructure as code

## 1. 背景とコンテキスト

Runtime credential boundary完成後、AWS未ログインでも検証可能なOpenTofu定義とCloudflare environment契約をpublic repoへ置く。stagingだけを実体化対象とし、productionは別account / project向け定義に留める。

## 2. 事前に読むべきファイル

- runtime deployment credential boundaries work item
- `docs/03_技術仕様書.md`
- `docs/05_設計判断記録.md`
- `docs/ops/runbook-server-deploy.md`
- `realtime-worker/wrangler.jsonc`
- public/private repo split task

## 3. ゴール

AWS Lambda、API Gateway HTTP API、ECR、Secrets Manager、CloudWatch、GitHub OIDC、Cloudflare DNS / Workerを再現可能かつ秘密値をstateへ含めないIaCとして定義する。

## 4. スコープ

### やること

- OpenTofu 1.12系のmoduleとstaging / production rootを追加する。
- S3 state、ECR、Lambda version / alias、API Gateway、ACM、logs、budget、Secrets Manager container、IAM / OIDCを定義する。
- Cloudflare DNS / Worker Custom DomainとWrangler environmentを定義する。
- private repoにoperations文書を追加する。

### やらないこと

- 実resourceへの`apply`、secret version投入、production resource作成を行わない。
- VPC / NAT、Provisioned Concurrency、WAF / CloudFront、customer-managed KMSを追加しない。

## 5. 実装手順

1. module interfaceと安全な既定値を定義する。
2. staging / production rootとremote-state bootstrap手順を追加する。
3. Cloudflare environmentとDNS契約を追加する。
4. static validation、policy check、public/private混入checkを追加する。

## 6. 受け入れ基準

- [x] credentialなしでfmt / init / validateが成功する。
- [x] staging planは承認済みresourceだけを含み、secret valueをstate inputに持たない。
- [x] production rootは別account / backendを必須とし、apply導線を持たない。
- [x] Lambda roleはruntime secretだけを読める。
- [x] GitHub deploy roleだけがmigration / provider secretを読める。
- [x] Cloudflare WorkerのEU jurisdictionとCustom Domainが定義される。
- [ ] public/private境界と独立検証が合格する。

## 7. 制約・注意事項

- provider / Actionはlockfileまたはfull commit SHAで固定する。
- actual domain、account ID、zone ID、project ID、通知先はprivateまたはGitHub Environmentで扱う。
- OpenTofu stateにsecret payloadを書かない。

## 8. 完了報告に含めるべき内容

- module interfaceと生成resource
- IAM / state / secret境界の検証
- static / policy test
- private側変更の要約とpublic混入check
- 独立検証結果と未解決事項

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-19
- 2026-07-20にTaskveil改名済みの`main`へrebaseし、AWS / Cloudflare resource名、tag、GitHub OIDC session名、example repositoryを`taskveil`名義へ統合した。実ドメインは従来どおりprivate inventoryとGitHub Environment variableで管理する。
- OpenTofu 1.12.1向けにstate / OIDC / secret container bootstrap、再利用可能なdeployment module、staging / production rootを追加した。AWS provider 6.55.0とCloudflare provider 5.22.0をexact versionおよび各rootのlockfileで固定した。
- bootstrapとmoduleはS3 native locking、ECR immutable / scan-on-push / 10 image保持、Lambda version / alias、HTTP API、ACM、CloudWatch Logs 14日、Secrets Manager metadata、IAM、GitHub OIDC、月額5 USDの50% / 80% / 100% budget通知を定義する。初回はECRをbootstrapし、image digest確定後にLambda rootをapplyする順序で循環を避ける。
- stagingの既定値をx86_64、512 MB、30秒、reserved concurrency 10、API 20 RPS / burst 40、認証route 5 / 10とした。access logはrequest ID、route、status、latencyだけを出す。
- runtime / migration / deployment-provider secretはcontainerだけをbootstrapで作成し、secret version / payloadはOpenTofuへ渡さない。Lambdaはruntimeだけ、staging deploy roleは3件、通常CIは0件を読む境界にした。
- Cloudflare DNSでAPI custom domainを接続し、OpenTofuで既存の環境別Worker serviceへWorker Custom Domainを接続する。Wranglerにはstaging / production environmentを定義し、Worker codeのEU jurisdiction contractを維持した。
- production rootは独立backend、stagingと異なるAWS account / Neon projectをvalidationで必須化し、production apply workflowを用意していない。
- private repoへ`operations/`を追加し、実domain / account / zone / project / budget通知先 / bootstrap記録の置き場を定義した。secret valueをGitへ保存しない注意書きを含み、public repoからprivate repoへの参照は追加していない。

### 検証

- `tofu fmt -check -recursive infra`、bootstrap / staging / productionの`init -backend=false`と`validate`: PASS。
- credential不要のmock plan test: staging 1件、production 3件がPASS。productionでstaging AWS account IDまたはNeon project IDを再利用したcaseがvalidationで失敗することを確認した。
- Cloudflare provider 5.22.0の`cloudflare_workers_custom_domain`を含むstaging / production validateとmock planがPASSし、version uploadへ未対応のdomain optionを渡さない境界検査を追加した。
- `tool/ci/check_infra_boundaries.sh`: native lock、secret payload非混入、runtime / migration IAM分離、production apply禁止、Action full SHA、OIDC subjectを検証してPASS。
- `git diff --check`とsecret pattern scan: PASS。private repoにはinventory templateとbootstrap log templateだけを置き、実識別子・秘密値は未投入。

### 独立検証・未解決事項

- 判定: 独立検証待ち。実装担当とは別の検証者によるplan / IAM / public-private境界の再確認を行うまでfront matterを`active`に保つ。
- mock providerで定義上のplanを検証した。実accountでのstate bootstrap、provider APIを使うstaging plan / apply、OIDC subject、IAM実効権限、Cloudflare custom domain、Neon project分離は人間承認後に確認する。
