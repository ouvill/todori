# Cotori（コトリ）― E2EE Todoアプリ

Cotori（仮称）は、「プライバシーを一切妥協しない、ふわっと親しみやすいTodoアプリ」をコンセプトに掲げるTodo管理アプリです。E2EE（エンドツーエンド暗号化）とローカルファーストの設計を軸に、iOS・Android・Desktop（Windows・macOS・Linux）で動作するマルチプラットフォーム対応を目指しています。アカウント登録や課金を行わなくても、単一端末上でアプリのコア機能をフルに利用できる点が特徴です。

既存のTodoアプリの多くはタスクの内容を平文のままサーバーに保存していますが、Todoリストには健康・仕事・人間関係など機微な情報が含まれることが少なくありません。Cotoriは、サーバー側がパスワードもタスク内容も知り得ないOPAQUE認証とE2EEを組み合わせることで、この課題に正面から向き合います。複数端末間の同期やOrganizationでのタスク共有など、サーバーを介した機能のみを有料の対象とすることで、気軽に使い始められる体験と、使うほど便利になる拡張性の両立を図ります。

UI面では、丸みや淡い配色を取り入れた親しみやすいデザインに加え、シンプルUIと高機能UIを利用シーンに応じて切り替えられる設計とし、MCP・CLI・ローカルAIといったオープンな拡張性によって、データ主権をユーザーの手元に残したまま最新のAI体験を取り込めるようにします。

## ドキュメント

- [企画書](./docs/01_企画書.md)
- [機能仕様書](./docs/02_機能仕様書.md)
- [技術仕様書](./docs/03_技術仕様書.md)
- [課金設計書](./docs/04_課金設計書.md)
- [事業・法務方針](./docs/06_事業・法務方針.md)

## リポジトリ構成

本リポジトリはmonorepo構成であり（詳細は[技術仕様書 §2](./docs/03_技術仕様書.md#2-リポジトリモジュール構成)を参照）、以下のディレクトリで構成される。

```
cotori/
├── app/                  Flutterアプリ本体（iOS / Android / Windows / macOS / Linux）
├── core/                 Rustコアクレート群（暗号・同期・ドメインロジックの単一の実装源泉）
│   ├── domain/           エンティティ・ユースケース（cotori-domain）
│   ├── crypto/           鍵導出・AEAD暗号化（cotori-crypto）
│   ├── sync/             HLC・同期エンジン（cotori-sync）
│   └── storage/          ローカルストレージアクセス層（cotori-storage）
├── cli/                  Rust CLI「cotori」（cotori-cli）。coreを利用
├── mcp-server/           Rust MCPサーバー（cotori-mcp-server）。coreを利用
├── server/               Rust APIサーバー（axum、cotori-server）。AWS Lambda上で稼働
└── docs/                 設計ドキュメント
```

### 開発コマンド例

```sh
# Rustワークスペース全体のテスト
cargo test --workspace

# Flutterアプリの起動
cd app && flutter run
```
