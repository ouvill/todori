# サーバーデプロイrunbook

この文書はTodoriサーバーの初回/更新デプロイ手順ドラフトである。2026-07-08時点では実AWS/Neon環境へのデプロイは未実施であり、ローカル運用のみ確認済みである。実クレデンシャル、AWSアカウントID、ECRリポジトリ名、Lambda関数名、Neon connection string、実ドメインはpublic repoに書かず、private側または人間管理とする。

## 1. 前提

- 構成の正は [`docs/03_技術仕様書.md`](../03_技術仕様書.md) §1.5、§6、[`docs/05_設計判断記録.md`](../05_設計判断記録.md) ADR-008である。
- サーバーは `server/Dockerfile` でビルドするコンテナイメージとしてデプロイする。
- イメージにはAWS Lambda Web Adapterが含まれ、アプリ本体は通常のHTTPサーバーとして動作する。
- DBはNeon Postgresを使う。初期リージョンは `eu-central-1`、Lambdaも同一リージョンに配置する。
- 実値はすべてプレースホルダで示す。

## 2. 必要なクレデンシャルと実値

次の値はprivate側または人間管理で保持する。

| 値 | 用途 |
|---|---|
| `<AWS_ACCOUNT_ID>` | ECR registry / IAM / Lambda操作 |
| `<AWS_REGION>` | 初期想定は `eu-central-1` |
| `<ECR_REPOSITORY>` | todori-serverイメージ保管先 |
| `<LAMBDA_FUNCTION>` | 更新対象Lambda関数 |
| `<NEON_DATABASE_URL>` | Neon pooled connection string |
| `<PUBLIC_API_BASE_URL>` | クライアントに設定する公開API URL |
| `<WAF_OR_API_GATEWAY_CONFIG>` | 前段の制限設定。private側/人間判断 |

## 3. 事前検証

ローカルでRust品質ゲートとサーバーテストを通す。

```sh
cargo fmt --all -- --check
cargo clippy --workspace -- -D warnings
cargo test --workspace
git diff --check
```

ローカル開発サーバーを起動してヘルスチェックする。

```sh
./tool/dev_server.sh
curl -i http://localhost:8080/health
```

期待値は `HTTP/1.1 200 OK` と `{"status":"ok"}` である。

## 4. 初回デプロイ手順

### 4.1 ECRリポジトリ作成

実行者はAWS credentialを設定済みであることを確認する。credential値はコマンド履歴、ログ、完了報告に貼らない。

```sh
aws ecr create-repository \
  --repository-name <ECR_REPOSITORY> \
  --region <AWS_REGION>
```

### 4.2 Docker build

リポジトリルートで実行する。Lambdaの実行アーキテクチャに合わせ、`linux/arm64` または `linux/amd64` を選ぶ。

```sh
docker buildx build \
  --platform linux/arm64 \
  -f server/Dockerfile \
  -t <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/<ECR_REPOSITORY>:<IMAGE_TAG> \
  --load \
  .
```

### 4.3 ECR login / push

```sh
aws ecr get-login-password --region <AWS_REGION> \
  | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com

docker push <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/<ECR_REPOSITORY>:<IMAGE_TAG>
```

### 4.4 Neon DB準備

Neon project / database / pooled endpointを作成する。作成操作とconnection stringはprivate側または人間管理で扱う。

初回migrationは [`docs/ops/runbook-db-migration.md`](./runbook-db-migration.md) に従い、ローカルでリハーサルしてから適用する。

### 4.5 Lambda作成または更新

初回はLambda関数、IAM role、環境変数、前段のCloudFront + WAFまたはAPI Gatewayを作成する。以下は更新時と同じイメージ設定の例であり、IAM roleや前段設定はprivate側/人間管理で決める。

```sh
aws lambda update-function-code \
  --function-name <LAMBDA_FUNCTION> \
  --image-uri <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/<ECR_REPOSITORY>:<IMAGE_TAG> \
  --region <AWS_REGION>

aws lambda update-function-configuration \
  --function-name <LAMBDA_FUNCTION> \
  --environment "Variables={DATABASE_URL=<NEON_DATABASE_URL>,RUST_LOG=info,todori_server=info}" \
  --region <AWS_REGION>
```

`DATABASE_URL` は秘密情報である。実値をpublic repo、public CI logs、issue、PR、完了報告へ貼らない。

## 5. 更新デプロイ手順

1. 事前検証を通す。
2. `<IMAGE_TAG>` を決める。推奨はgit tagまたはcommit SHA由来の値。
3. Docker build / ECR pushを行う。
4. DB migrationが必要な場合は、Lambda更新前にexpand migrationを適用する。
5. `aws lambda update-function-code` でLambdaを更新する。
6. `/health` と最小の登録/ログイン/同期導線を確認する。

## 6. 検証

公開API URLでヘルスチェックする。

```sh
curl -i <PUBLIC_API_BASE_URL>/health
```

クライアント2台同期確認は [`docs/dev/two-device-sync-test.md`](../dev/two-device-sync-test.md) を、Server URLだけ `<PUBLIC_API_BASE_URL>` に置き換えて実施する。実ユーザー情報や実Recovery Keyをログに残さない。

## 7. ロールバック

コードのみの問題でDB schema互換が保たれている場合、直前のイメージタグへ戻す。

```sh
aws lambda update-function-code \
  --function-name <LAMBDA_FUNCTION> \
  --image-uri <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/<ECR_REPOSITORY>:<PREVIOUS_IMAGE_TAG> \
  --region <AWS_REGION>
```

DB migrationを含む変更は原則としてDBを戻さない。前方修正migrationまたは修正版イメージで復旧する。詳細は [`docs/ops/runbook-db-migration.md`](./runbook-db-migration.md) を参照する。

## 8. 未実施事項

- 実AWS/ECR/Lambda/Neonデプロイ。
- CloudFront + WAFまたはAPI Gateway throttlingの最終選定。
- 本番監視、アラート、ログ保持期間。
- 公開不可の運用・事業判断。これらはprivate側/人間管理とする。
