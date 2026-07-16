# Todori（トドリ）― E2EE Todoアプリ

> Status: pre-release. Todori is public for E2EE transparency and development visibility, but it is not ready for production use or broad external promotion yet.

The first general release is intentionally blocked until the billing foundation, server-side entitlement enforcement, and iOS sandbox purchase/restore flow are complete. Public billing principles are documented in [Billing Overview](./docs/billing_overview.md).

Todoriは、「プライバシーを一切妥協しない、ふわっと親しみやすいTodoアプリ」をコンセプトに掲げるTodo管理アプリです。E2EE（エンドツーエンド暗号化）とローカルファーストの設計を軸に、iOS・Android・Desktop（Windows・macOS・Linux）で動作するマルチプラットフォーム対応を目指しています。アカウント登録や課金を行わなくても、単一端末上でアプリのコア機能をフルに利用できる点が特徴です。

既存のTodoアプリの多くはタスクの内容を平文のままサーバーに保存していますが、Todoリストには健康・仕事・人間関係など機微な情報が含まれることが少なくありません。Todoriは、サーバー側がパスワードもタスク内容も知り得ないOPAQUE認証とE2EEを組み合わせることで、この課題に正面から向き合います。複数端末間の同期やOrganizationでのタスク共有など、サーバーを介した機能のみを有料の対象とすることで、気軽に使い始められる体験と、使うほど便利になる拡張性の両立を図ります。

UI面では、丸みや淡い配色を取り入れた親しみやすいデザインに加え、シンプルUIと高機能UIを利用シーンに応じて切り替えられる設計とし、MCP・CLI・ローカルAIといったオープンな拡張性によって、データ主権をユーザーの手元に残したまま最新のAI体験を取り込めるようにします。

## ドキュメント

- [企画書](./docs/01_企画書.md)
- [機能仕様書](./docs/02_機能仕様書.md)
- [技術仕様書](./docs/03_技術仕様書.md)
- [課金概要](./docs/billing_overview.md)
- [法務・OSS概要](./docs/legal_overview.md)
- [運用ガイド](./docs/09_運用ガイド.md)
- [Apple署名設定メモ](./docs/dev/code-signing-setup.md)
- [Security Policy](./SECURITY.md)

## リポジトリ構成

本リポジトリはmonorepo構成であり（詳細は[技術仕様書 §2](./docs/03_技術仕様書.md#2-リポジトリモジュール構成)を参照）、以下のディレクトリで構成される。

```
todori/
├── app/                  Flutterアプリ本体（iOS / Android / Windows / macOS / Linux）
├── core/                 Rustコアクレート群（暗号・同期・ドメインロジックの単一の実装源泉）
│   ├── domain/           エンティティ・ユースケース（todori-domain）
│   ├── crypto/           鍵導出・AEAD暗号化（todori-crypto）
│   ├── sync/             HLC・同期エンジン（todori-sync）
│   └── storage/          ローカルストレージアクセス層（todori-storage）
├── cli/                  Rust CLI「todori」（todori-cli）。coreを利用
├── mcp-server/           Rust MCPサーバー（todori-mcp-server）。coreを利用
├── server/               Rust APIサーバー（axum、todori-server）。AWS Lambda上で稼働
└── docs/                 設計ドキュメント
```

### 開発コマンド例

```sh
# Rustワークスペース全体のテスト
cargo test --workspace

# Flutterアプリの起動
cd app && flutter run
```

### 性能検証メモ

Phase 1の性能検証は `docs/tasks/task-67-performance-verification.md` に記録している。task-67で判明したHome 7140件相当の全行Widget構築ボトルネックは、task-68でHome/TasksのSliver遅延構築へ引き継ぎ、解消済み。

### マルチプラットフォーム検証メモ

初期のマルチプラットフォーム検証は `docs/tasks/task-74-multiplatform-verification.md` に記録している。その後、macOS署名付き起動とKeychainゼロプロンプト、iOS Simulatorでのbuild / install / launch、macOS + iOS Simulatorの2台同期、Focus motion、Android Rust FFI / Flutter release APK build、Android Keystore実装まで確認済みである。残るrelease確認はiOS / Android実機、Android接続実機でのKeystore / Device Key rotation / DB reopen / 同期、本番デプロイ、課金基盤であり、最新状態は `docs/tasks/STATUS.md` と `docs/tasks/work-*.md` を正本とする。

### core抽出メモ

task-75で同期オーケストレーションは `core/sync`、Device Key / Keychain / account secret store は `core/crypto` へ移した。`app/rust/src/api.rs` はFRB公開関数とDTO変換中心の薄いブリッジ層として維持する。

### Apple Keychain署名メモ

task-77でiOS/macOS Runnerに `keychain-access-groups` entitlementを追加し、署名済みAppleビルドではData Protection Keychainを正規経路として使う。macOS署名付きbuildはゼロプロンプト確認済みで、iOS実機確認はリリース前の人間作業として残る。ローカル検証は[Apple署名設定メモ](./docs/dev/code-signing-setup.md)に従う。

## License

Todoriは [`LICENSE`](./LICENSE)（AGPL-3.0-only）のもとで公開されています。コントリビューションには [`CONTRIBUTING.md`](./CONTRIBUTING.md) および [`CLA.md`](./CLA.md)（Contributor License Agreement）への同意が必要です。

Todori is currently in an early pre-release phase. Public issues and pull requests may be handled conservatively until the app, contribution process, and release policy mature.

セキュリティ脆弱性を見つけた場合は、public issueには詳細を書かず、[`SECURITY.md`](./SECURITY.md) の非公開報告導線を参照してください。
