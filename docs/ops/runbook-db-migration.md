# DBマイグレーションrunbook

TaskveilサーバーDBのマイグレーション手順を定義する。2026-07-08時点の本番デプロイは未実施であり、このrunbookはローカルリハーサルと将来のNeon適用に向けたドラフトである。

## 1. 対象

対象は [`server/migrations/`](../../server/migrations/) 配下のPostgres SQLである。現在の実装では `server/src/db.rs` の `run_migrations` が `sqlx` のPostgres接続上でSQLを適用する。ローカル開発では [`tool/dev_server.sh`](../../tool/dev_server.sh) が同じSQLを `psql` で適用する。

## 2. 方針

- マイグレーションは前方のみとする。
- ロールバックはDBを巻き戻すのではなく、修正SQLまたは修正版アプリで前方に進める。
- 互換性が必要な変更はexpand-contractを使う。
- 既存データ削除、列の意味変更、型変更、NOT NULL追加、unique制約追加は、リハーサルと影響確認なしに行わない。
- E2EEデータの暗号blobをサーバー側で復号する作業は行わない。

## 3. expand-contractの目安

1. expand: nullable列、別名列、新テーブル、互換indexなどを追加する。
2. app update: 新旧schemaを両方扱えるサーバー/クライアントを出す。
3. backfill: 必要なデータを埋める。大量更新はバッチ化する。
4. contract: 全クライアント/サーバーが新schema前提になってから旧列・旧テーブルを撤去する。

contractは公開リポジトリだけで判断しない。実稼働状況、クライアント普及率、保持期間はprivate側/人間管理で判断する。

## 4. ローカルリハーサル

既存の開発DBを使う場合:

```sh
./tool/dev_server.sh
```

スクリプトは `taskveil-dev-postgres` を起動し、`server/migrations/*.sql` を順に適用してからサーバーを起動する。

クリーンDBで試す場合:

```sh
docker rm -f taskveil-dev-postgres
./tool/dev_server.sh
```

ヘルスチェック:

```sh
curl -i http://localhost:8080/health
```

2台同期の回帰確認:

```sh
# 詳細は docs/dev/two-device-sync-test.md
```

## 5. SQL追加時の確認項目

- ファイル名は既存の連番形式に合わせる。例: `YYYYMMDDNNNN_description.sql`
- `CREATE TABLE IF NOT EXISTS` や `CREATE INDEX IF NOT EXISTS` のように再適用耐性を持たせる。
- `ALTER TABLE ... ADD COLUMN` は既存環境で再適用されない前提を確認する。必要なら存在確認つきSQLにする。
- `server/src/db.rs` の `run_migrations` に新SQLを追加する。
- `server/tests/` にmigration後の基本CRUDまたはAPIテストを追加する。
- `tool/dev_server.sh` でローカル適用できることを確認する。

## 6. Neon適用手順

実Neonのdirect owner connection stringは `<NEON_MIGRATION_DATABASE_URL>` として扱い、private側または人間管理に置く。public repo、public issue、完了報告、CIログに実値を書かない。

事前にローカルリハーサルを通す。次に、Neonのbranch機能が利用できる場合は本番branchから検証branchを作成し、同じSQLを適用して確認する。

```sh
psql "<NEON_MIGRATION_DATABASE_URL>" -v ON_ERROR_STOP=1 -f server/migrations/<MIGRATION_FILE>.sql
```

アプリ起動時にも `DATABASE_MIGRATION_URL` のowner接続で `run_migrations` が走るため、SQLは再実行で壊れない設計にする。通常query用の `DATABASE_URL` は別のruntime loginを使用し、migrationが作成するNOLOGIN group role `taskveil_app`のmemberにする。

```sql
-- role名とpasswordは運用環境で管理する。実値をpublic repoへ記録しない。
CREATE ROLE <RUNTIME_LOGIN> LOGIN PASSWORD '<SECRET>'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
GRANT taskveil_app TO <RUNTIME_LOGIN>;
```

本番・共有環境では次を分離する。

- `DATABASE_MIGRATION_URL`: schema owner / migration専用。通常server requestへ渡さない。
- `DATABASE_URL`: pooled endpointを使うnon-owner runtime login。`INHERIT`付きで`taskveil_app`のmemberにし、serverは接続時にLOGIN / non-owner / NOSUPERUSER / NOBYPASSRLS / 権限継承を検証する。transaction poolで保持されないsession-level `SET ROLE`には依存しない。

ローカルの `tool/dev_server.sh` もowner接続と`taskveil_runtime` loginを分離する。

## 7. 検証

最低限の検証:

```sh
cargo test -p taskveil-server
cargo test --workspace
git diff --check
```

APIレベルの検証:

- `/health` が成功する。
- OPAQUE登録/ログインが成功する。
- push/pullがtenant分離、batch上限、blob上限、未来HLC拒否を維持している。
- 削除tombstoneの空blob方針が維持されている。
- application poolの `current_user` がnon-owner runtime loginで、`rolsuper = false`、`rolbypassrls = false`、`rolinherit = true`、`pg_has_role(current_user, 'taskveil_app', 'USAGE') = true`である。
- `tenants`、`tenant_members`、`tenant_seq`、tenant/list key bundle、sync record/historyでRLSと`FORCE ROW LEVEL SECURITY`が有効である。
- tenant contextなしでは0行、tenant contextありでは当該tenantだけが見え、別tenantへのinsert/update/deleteが拒否または0件になる。

## 8. ロールバック方針

DB migrationは前方のみで扱う。失敗時は次の順に判断する。

1. migration適用前に失敗した場合: SQLを修正して再リハーサルする。
2. expand migration適用後にアプリが失敗した場合: 旧アプリが新schemaを無視できるならLambdaイメージだけ戻す。
3. データ補正が必要な場合: 補正SQLを新しいmigrationとして追加する。
4. 破壊的変更が入った場合: 人間判断でNeon backup/restoreを検討する。復旧手順と影響ユーザー判断はprivate側/人間管理とする。

## 9. 禁止事項

- 本番DBのconnection stringをpublicな場所に記録する。
- ユーザーの暗号blobを復号しようとする。
- リハーサルなしに本番DBへ破壊的SQLを適用する。
- private側で扱う判断事項をpublic repoのrunbookに書く。
