# Taskveil

**プライバシーを妥協しない、ローカルファーストのE2EE Todoアプリ。**

[![CI](https://github.com/ouvill/taskveil/actions/workflows/ci.yml/badge.svg)](https://github.com/ouvill/taskveil/actions/workflows/ci.yml)
[![License: AGPL-3.0-only](https://img.shields.io/badge/License-AGPL--3.0--only-blue.svg)](./LICENSE)
[![Status: pre-release](https://img.shields.io/badge/status-pre--release-orange.svg)](#プロジェクトの状態)

Taskveilは、タスクの内容をサービス提供者からも見えないようにすることを目指した、Flutter + Rust製のTodoアプリです。アカウントやサーバーを使わずに単一端末で利用でき、同期を有効にした場合もタスク本文はクライアント側で暗号化されます。

このリポジトリでは、クライアント、暗号化されたローカルストレージ、同期プロトコル、認証・同期サーバーの実装と設計資料を公開しています。

## プロジェクトの状態

> [!WARNING]
> Taskveilは**一般リリース前**です。配布済みの安定版はなく、実データでの常用や本番運用はまだ推奨しません。API、同期プロトコル、データベーススキーマは予告なく変更され、開発中のデータを引き継げない場合があります。

現在、macOSとAndroidでは主要な暗号・端末鍵フローを実機確認済みです。一方、iOS実機検証、Android実機での同期、課金・認可のE2E検証、本番環境へのデプロイはリリースゲートとして残っています。また、暗号実装は内部レビュー済みですが、**外部の暗号専門家による監査は未実施**です。

- 最新の進捗: [開発ステータス](./docs/tasks/STATUS.md)
- 暗号機能の公開条件: [暗号release gate](./docs/ops/crypto-release-gate.md)
- 公開版の課金方針: [Billing Overview](./docs/billing_overview.md)

## 特徴

- **ローカルファースト** — アカウント登録やサーバー接続なしで、リストとタスクを端末上で管理できます。
- **暗号化されたローカルデータ** — SQLCipherデータベースを、OSのKeychain / Keystoreで保護したDevice Key由来の鍵で暗号化します。
- **E2EE同期** — サーバーは暗号化されたレコードを中継・保存し、タスク本文を復号しません。認証にはOPAQUEを使用します。
- **日常のタスク管理** — 階層化したリストとタスク、期限、リマインダー、検索、テンプレート、繰り返しタスク、Focusタイマーを実装しています。
- **クロスプラットフォームUI** — FlutterでiOS、Android、macOS、Windows、Linuxを対象とし、日本語・英語UIを提供します。プラットフォームごとのリリース検証状況は同一ではありません。
- **共有Rustコア** — ドメインロジック、暗号、ストレージ、同期処理をRust crateとして分離し、フロントエンドから再利用できる構成です。

CLIとMCPサーバーは将来の拡張用の雛形であり、現時点では実用的なタスク操作には対応していません。Organization共有もリリースゲートを満たすまで公開対象外です。

## セキュリティモデル

Taskveilは、ローカルDBと同期レコードの両方を暗号化します。同期サーバーは暗号化されたレコード本文を復号しませんが、認証、端末、テナント、同期順序など、サービス提供に必要なメタデータは扱います。保護対象、鍵階層、サーバーから見える情報の詳細は[技術仕様書 §4](./docs/03_技術仕様書.md#4-暗号設計)を参照してください。

脆弱性を発見した場合は、公開IssueやPull Requestへ詳細を書かず、[Security Policy](./SECURITY.md)の非公開報告手順を利用してください。

## ローカルで試す

### 必要なもの

- [Rust](https://www.rust-lang.org/tools/install) 1.97.0（[`rust-toolchain.toml`](./rust-toolchain.toml)で固定）
- [Flutter](https://docs.flutter.dev/get-started/install) 3.44.6
- 実行対象に応じたFlutterのプラットフォームツールチェーン
- 同期サーバーも動かす場合はDocker

### クライアント

```sh
git clone https://github.com/ouvill/taskveil.git
cd taskveil/app
flutter pub get
flutter run
```

使用可能な端末は `flutter devices` で確認できます。単一端末のローカル利用では同期サーバーは不要です。

### 開発用同期サーバー

リポジトリルートで次を実行すると、開発用PostgreSQLコンテナの作成、マイグレーション、Rust APIサーバーの起動をまとめて行います。

```sh
./tool/dev_server.sh
```

既定では `http://localhost:8080` で起動します。クライアント2台を使った同期確認は[2台同期テスト手順](./docs/dev/two-device-sync-test.md)を参照してください。

## 開発とテスト

Rustワークスペースの基本品質ゲートは次のとおりです。

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

serverのSQLはSQLxのコンパイル時検証を使用します。通常のbuildとtestはversion control済みの`.sqlx/`を使うため、PostgreSQLへの接続は不要です。クエリまたはmigrationを変更した場合は、Postgres対応のSQLx CLIを導入してfresh databaseからmetadataを更新します。

```sh
cargo install sqlx-cli --version 0.9.0 --locked --no-default-features --features postgres,rustls
./tool/sqlx_prepare.sh
./tool/sqlx_prepare.sh --check
env -u DATABASE_URL SQLX_OFFLINE=true cargo check -p taskveil-server --all-targets
```

`sqlx_prepare.sh`は一時的なDocker Postgresへ全migrationを適用し、終了時にコンテナを削除します。
SQLxはPostgreSQL専用です。SQLx 0.9.0がlockfileへ解決する未使用のSQLite driverは
`third_party/sqlx-sqlite-lockfile-shim`でfail-closedにし、クライアントの
rusqlite / SQLCipher依存から分離しています。

Flutter側を変更した場合は、Rust bridgeをビルドしてから解析とテストを実行します。

```sh
cd app/rust
env CARGO_TARGET_DIR=target cargo build --release
cd ..
flutter analyze
flutter test
```

完全な品質ゲートと開発上の制約は[開発ハンドブック](./AGENTS.md)に記載しています。

## リポジトリ構成

```text
taskveil/
├── app/              FlutterクライアントとRust FFI bridge
├── core/
│   ├── client/       frontend共通のapplication service
│   ├── crypto/       鍵管理、暗号、OPAQUE
│   ├── domain/       エンティティとユースケース
│   ├── storage/      SQLCipherローカルストレージ
│   └── sync/         E2EE同期protocolとstate machine
├── server/           認証・同期・認可を提供するRust API
├── realtime-worker/  foreground同期のwake-up通知
├── cli/              CLI雛形（未接続）
├── mcp-server/       MCPサーバー雛形（未接続）
└── docs/             仕様、ADR、運用資料、作業履歴
```

各frontendは `core/client` を共通の入口とし、暗号鍵、repository、同期coordinatorを直接所有しない設計です。詳しくは[client / frontend adapter architecture](./docs/dev/client-profile-architecture.md)を参照してください。

## ドキュメント

| 文書 | 内容 |
|---|---|
| [機能仕様書](./docs/02_機能仕様書.md) | ユーザー向け機能の仕様 |
| [技術仕様書](./docs/03_技術仕様書.md) | アーキテクチャ、暗号、ストレージ、同期の正本 |
| [設計判断記録](./docs/05_設計判断記録.md) | 主要な設計判断とその背景 |
| [運用ガイド](./docs/09_運用ガイド.md) | 開発、サーバー、リリース、セキュリティ運用 |
| [開発ステータス](./docs/tasks/STATUS.md) | 現在地と未完了のリリースゲート |
| [法務・OSS概要](./docs/legal_overview.md) | 公開リポジトリの法務・OSS方針 |

## コントリビューション

IssueやPull Requestを作成する前に[コントリビューションガイド](./CONTRIBUTING.md)を確認してください。コミットには[Conventional Commits](https://www.conventionalcommits.org/)を使用します。

Pull Requestの提出には[Contributor License Agreement](./CLA.md)への同意が必要です。Taskveilは一般リリース前のため、互換性やセキュリティに影響する提案は慎重に取り扱う場合があります。

## ライセンス

Taskveilは[GNU Affero General Public License v3.0 only](./LICENSE)で公開されています。
