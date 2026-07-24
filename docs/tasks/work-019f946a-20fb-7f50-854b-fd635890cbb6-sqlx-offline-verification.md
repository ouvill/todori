---
id: 019f946a-20fb-7f50-854b-fd635890cbb6
title: SQLx compile-time and offline query verification
status: done
lane: critical
milestone: maintenance
---

# SQLx compile-time and offline query verification

## 1. 背景とコンテキスト

serverはPostgresアクセスに`sqlx-core` / `sqlx-postgres`のruntime query APIを使用している。固定SQLも`query::<Postgres>`と文字列名による`Row::try_get`で読み出しているため、SQL構文、schema、bind型、結果列名・型の不整合はコンパイル時に検出されない。

Postgres採用時のADRはsqlxのコンパイル時クエリ検証を利点としている。serverのクエリ数とリリース前の品質要求に対して、その検証を実際の開発・CI経路へ組み込む。

本変更はRust依存とDBアクセス層を横断するため重要変更レーンとする。2026-07-24にプロダクトオーナーから、専用workspaceでのリファクタ、sqlx offline検証対応、必要に応じたDocker Postgres利用について承認を得た。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/03_技術仕様書.md`のserver / Postgres節
- `docs/05_設計判断記録.md`のADR-002 / ADR-003 / ADR-008
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/task-70-sync-server.md`
- `Cargo.toml`
- `server/Cargo.toml`
- `server/src/db.rs`
- `.github/workflows/ci.yml`

## 3. ゴール

- serverの固定SQLをsqlxのcompile-time checked query macroで検証する。
- live databaseなしで通常のRust build / testを実行できるoffline metadataを正本化する。
- fresh Postgresへmigrationを適用したschemaからmetadataを再生成・検査できる手順とCI gateを設ける。
- workspace内のrusqlite / SQLCipher依存とPostgres専用sqlx構成を共存させる。

## 4. スコープ

### やること

- Postgresとquery macroに限定したsqlx依存構成への変更
- `server/src`の固定DML / SELECTを`query!`、`query_as!`、`query_scalar!`へ移行
- 必要なnamed row型と明示的なnullability / type overrideの追加
- `.sqlx/` offline metadataの生成とversion control対象化
- Docker Postgresへ全migrationを適用してmetadataを再生成・検査する開発コマンド
- CIでoffline buildとmetadata freshnessを検査する品質ゲート
- macroでは検証できない動的SQLとmigration SQLに対する既存統合テストの維持

### やらないこと

- DB schema、RLS policy、wire protocol、公開APIの意味変更
- local SQLCipher / rusqlite storageのsqlx化
- ORMまたはquery builderの導入
- 本変更と無関係なserver機能追加

## 5. 実装手順

1. `sqlx` facadeをdefault feature無効・Postgres専用で導入し、rusqliteとのlinks競合がないことを最小macroで検証する。
2. fresh Docker Postgresへmigrationを適用し、compile-time query解析用のDBを準備する。
3. scalar query、named row query、write queryの順でproduction固定SQLをmacroへ移行する。
4. 動的にSQL文字列を選択・構築する箇所は、可能ならliteral branchへ分解する。真に動的な箇所は理由を明示してruntime queryを維持する。
5. `.sqlx/`を生成し、`SQLX_OFFLINE=true`かつDB接続なしでserverをbuild / testできることを確認する。
6. metadata生成・freshness検査を再現可能なscriptとCIへ組み込む。
7. 統合HEADで品質ゲートを実行し、完了報告へ記録する。

## 6. 受け入れ基準

- [x] workspaceがrusqlite / SQLCipherとPostgres用sqlx macroをlinks競合なく解決できる。
- [x] `server/src`の固定SELECT / DMLが原則compile-time checked macroを使用し、runtime queryの例外が動的SQLまたは接続検証等の合理的な箇所に限定されている。
- [x] bind型、結果列名、結果型、nullabilityがfresh migrated Postgres schemaに対して検証される。
- [x] `.sqlx/`がversion controlされ、DB接続なしの`SQLX_OFFLINE=true cargo check -p taskveil-server --all-targets`が成功する。
- [x] Docker Postgresへ全migrationを適用してoffline metadataを再生成できる。
- [x] CIがoffline metadata欠落・不整合を検出する。
- [x] serverの既存DB統合テストが成功し、認証・同期・課金・RLSの意味論が変わっていない。
- [x] `cargo fmt --all -- --check`
- [x] `cargo clippy --workspace --all-targets -- -D warnings`
- [x] `cargo test --workspace`
- [x] `sh app/tool/check_client_boundaries.sh`
- [x] `sh app/tool/test_client_boundaries.sh`
- [x] `git diff --check`

## 7. 制約・注意事項

- sqlx macroが参照するschemaはrepositoryの全migrationを順番に適用したfresh Postgresから作る。
- 実DB接続情報、password、secretをrepository、ログ、offline metadata、完了報告へ含めない。
- `.env`へ実接続情報をcommitしない。
- production runtimeは引き続きpooled non-owner loginを使い、migration / metadata生成用owner接続と分離する。
- RLS、transaction-local user / tenant context、prepared statement利用の契約を変更しない。
- macroの導入だけを理由にunsafeなtype / nullability overrideを行わず、schemaとSQLから説明できるoverrideだけを使用する。

## 8. 完了報告に含めるべき内容

- macroへ移行したproduction query数と、残したruntime queryの一覧・理由
- sqlx / rusqlite共存を確認した依存解決結果
- offline metadata生成・検査コマンド
- fresh Postgresで実行したmigrationとDB統合テスト
- 実行した品質ゲートと結果
- 独立検証の判定と根拠

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-24〜2026-07-25
- 結果: serverのproduction固定SQL 148箇所を`query!`、`query_as!`、`query_scalar!`へ移行した。runtime queryは残しておらず、全migrationを順次実行する11箇所だけを`raw_sql`として維持した。
- 結果: SQLx 0.9.0のPostgres macroを導入した。クライアントのrusqlite 0.40.1 / libsqlite3-sys 0.38.1とpatched SQLCipherは維持し、SQLxがlockfileへ解決する未使用のoptional SQLite driverだけを`[patch.crates-io]`のfail-closed shimへ差し替えた。
- 結果: 142件の一意なquery metadataを`.sqlx/`へ生成した。`tool/sqlx_prepare.sh`はSQLx CLI 0.9.0を検証し、fresh Docker Postgresの作成、11 migrationの適用、metadata生成または`--check`、作成したcontainer IDだけの削除を行う。
- 結果: CIのRust jobを`SQLX_OFFLINE=true`に固定し、DBなしのserver全target checkを追加した。別jobでSQLx CLIとfresh Postgresを使うmetadata freshness checkを追加した。
- 証拠: `cargo tree -i libsqlite3-sys`で0.38.1の単一解決、`./tool/sqlx_prepare.sh --check`、一時container削除確認、`env -u DATABASE_URL SQLX_OFFLINE=true cargo check -p taskveil-server --all-targets`、`cargo fmt --all -- --check`、`env -u DATABASE_URL SQLX_OFFLINE=true cargo clippy --workspace --all-targets -- -D warnings`、Docker統合testを含む`env -u DATABASE_URL SQLX_OFFLINE=true cargo test --workspace`、client boundary 2 script、dependency pin / secret pattern check、Actionlint、`cargo audit --deny warnings`、`git diff --check`が成功した。
- Commit: この完了報告を含むcommit（PR履歴を参照）
- 未解決: なし。

### 独立検証

- 判定: 合格
- 根拠: 初回検証はSQLx移行とmetadata一致を確認したが、rusqlite 0.39.0が含むSQLCipher SQLite 3.50.4のWAL-reset bug、CLI version未検証、container cleanup対象を指摘した。修正後にrusqlite 0.40.1 / libsqlite3-sys 0.38.1の単一解決とSQLCipher SQLite 3.51.3、shim通常未build・SQLx SQLite有効化時のcompile failure、CLI 0.9.0検証、container ID限定cleanupと残存0件を確認した。offline locked all-target、fresh 11 migrationとmetadata check、148 invocation / 142 unique query / 142 metadataのhash一致、workspace clippy / Docker統合test込みtest、fmt、boundary、dependency pin、secret、Actionlint、audit、diffを独立再実行して成功した。
- 検証者: sqlx_independent_review
