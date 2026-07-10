# AGENTS.md

このファイルはCodex CLIが自動で読み込む開発ハンドブックである。Todoriリポジトリで作業する前に必ず読むこと。

## プロジェクト概要

Todoriは E2EE（エンドツーエンド暗号化）Todoアプリである。UIはFlutter、コアロジックはRustで実装し、両者を `flutter_rust_bridge`（バージョン `2.12.0` 固定）で接続する。

## リリース状態と互換性

Todoriは現在、一般リリース前である。

プロダクトオーナーがこの状態を変更するまで、既存client、wire protocol、API、local DB schema、server schema、開発データとの後方互換性は要件としない。

correctness・security・設計の一貫性を優先し、必要ならbreaking change、破壊的migration、開発データの再作成を行ってよい。互換レイヤ、dual read/write、旧形式fallbackは、taskで明示的に要求されない限り追加しない。

局所的な互換修正を積み重ねるより、正しい最終設計へ直接置き換える。重要な設計変更はtaskまたはADRへ記録する。

最初の外部配布を開始する前に、本節と `docs/09_運用ガイド.md` の互換性方針を更新する。

ドキュメント地図（読む順の目安）:

- `docs/01_企画書.md` ── プロダクト企画・ロードマップ
- `docs/02_機能仕様書.md` ── 機能仕様（F-01〜F-53）
- `docs/03_技術仕様書.md` ── **技術的な唯一の真実源**。実装と仕様書に矛盾があればこちらを優先する
- `docs/billing_overview.md` ── 公開版の課金方針（詳細な課金設計はprivate repo側）
- `docs/05_設計判断記録.md` ── ADR（設計判断記録）
- `docs/legal_overview.md` ── 公開版の法務・OSS方針（詳細な事業・法務メモはprivate repo側）
- `docs/07_Phase1計画書.md` ── **現在の実行計画**。マイルストーン（M1〜M5）と完了条件を定義する
- `docs/tasks/` ── 現在地、未着手候補、標準/重要変更の指示書と完了証拠。軽量作業はtask文書を省略できる

**`docs/01`・`docs/02` の変更には人間承認が必要**である。`docs/03_技術仕様書.md` は2026-07-08にプロダクトオーナーが全面編集を許可した（コミットをチェックポイントとして復元可能なため）。ただし変更時は外科的差分とし、日付・ADR参照注記を維持すること。実装中に仕様と矛盾する事実（ビルド不能、API仕様の相違等）を発見した場合は、該当タスクの完了報告の「未解決事項」に記録すること。

## リポジトリ構成

- `core/domain` ── 純粋ロジック・ユースケース（リスト/タスク操作、ステータス遷移、サブタスク制約検証等）
- `core/crypto` ── OPAQUE PoC、AEAD、HKDF、Device Key
- `core/storage` ── SQLCipher + rusqlite。`TaskRepository` / `ListRepository`
- `core/client` ── package `todori-client` / crate `todori_client`。Flutter / CLI / MCPが共有する唯一のprofile・application service入口
- `core/sync` ── frontend非依存の同期protocol、state machine、暗号record処理
- `app/` ── Flutterアプリ本体
- `app/rust` ── flutter_rust_bridge用のブリッジcrate（crate名 `todori_app_bridge`）
- `app/rust_builder` ── cargokitによるFFIプラグイン（iOS/macOS向けpodspec同梱）
- `cli` ── CLI雛形（Phase 1では未接続）
- `mcp-server` ── MCPサーバー雛形（Phase 1では未接続）
- `server` ── サーバー雛形（Phase 1では未使用。Phase 2以降のサーバー経由同期用）

## 品質ゲート（コミット前に全て通すこと）

```sh
cargo fmt --all -- --check
cargo clippy --workspace -- -D warnings
cargo test --workspace
cd app && flutter analyze
cd app && flutter test        # 事前に: cd app/rust && env CARGO_TARGET_DIR=target cargo build --release
sh app/tool/check_hardcoded_strings.sh
sh app/tool/check_client_boundaries.sh
sh app/tool/test_client_boundaries.sh
```

## 開発規約

- コミットメッセージは [Conventional Commits](https://www.conventionalcommits.org/)（`feat:` / `fix:` / `docs:` / `chore:` 等）に従う。本文は日本語で構わない。1タスクにつき1〜数コミットを目安とする。
- Rust依存クレートを追加する場合は、必ずリポジトリルート `Cargo.toml` の `[workspace.dependencies]` にバージョンを集約し、各crateからは `foo.workspace = true` の形で参照する。
- UI文字列は必ずARB化する（`app/lib/l10n/app_en.arb` + `app_ja.arb`）。文字列の直書きは `app/tool/check_hardcoded_strings.sh` が検出する。
- 状態管理はRiverpod 3.x（`AsyncNotifier` + `invalidateSelf`）を用いる。`riverpod_generator` は使わない。ルーティングは `go_router` を用い、ルート定義は `app/lib/src/router.dart` に集約する。
- 秘密情報（パスワード、Device Key、導出鍵、exportKey等）をログやDebug出力に含めてはならない。
- `core/` はcrate群の配置ディレクトリでありcrate名ではない。Cargo packageは `todori-<role>`、Rust crate名は `todori_<role>` とし、bare `core` package/lib、dependency alias、曖昧なumbrella crateを作らない。`todori_app_bridge`だけはCargo / pod / FRB stemの固定契約として例外とする。
- Flutter bridge、CLI、MCPのTodori共通入口は `todori-client` とする。frontend adapterから `todori-crypto` / `todori-domain` / `todori-storage` / `todori-sync`へ直接依存せず、repository、暗号鍵、同期coordinatorを保持しない。`app/rust`はFRB公開関数、process内`ClientProfile` handle、typed input / DTO変換だけに限定する。新しい共通機能は先に `core/client` のfrontend-neutral APIとして実装する。詳細は `docs/dev/client-profile-architecture.md` を参照する。
- 作業は `docs/tasks/README.md` の3レーン（軽量 / 標準 / 重要変更）で行う。標準・重要変更は実装着手時に指示書へ昇格し、`docs/tasks/PLAYBOOK.md` のフェーズを通す。`## 9. 完了報告` は実装結果と独立検証の共同記録とする。候補段階や軽量作業ではtask文書を作らない。

## 環境

- ホスト: macOS（Apple Silicon）、Xcode 26.6、CocoaPods 1.16.2
- Rustターゲット導入済み: `aarch64-apple-darwin` / `aarch64-apple-ios` / `aarch64-apple-ios-sim` / `x86_64-apple-ios` / `aarch64-linux-android`。`cargo-ndk` 導入済み
- `flutter_rust_bridge_codegen` 2.12.0（`~/.cargo/bin`）。Rust側crate（`flutter_rust_bridge`）とDart側pub（`flutter_rust_bridge`）の**バージョンは `=2.12.0` 固定で一致必須**
- Docker 29.x 利用可能（daemon稼働確認済み2026-07-08）。サーバーテスト用PostgresはDocker（testcontainers等）で用意する

## 重要な設計制約・ハマりどころ（変更・違反禁止）

1. **命名の三位一体**: cargoパッケージ名 = pod名 = FRB stem = `todori_app_bridge`。cargokitはパッケージ名から `lib<名前>.a` を探し、FRBローダーは `<stem>.framework` を探すため、どれか一つでも変えると壊れる。
2. **`.cargo/config.toml` の `IPHONEOS_DEPLOYMENT_TARGET=15.0` を消さない**。消すとiOS実機ターゲットで `___chkstk_darwin` 未定義のリンクエラーが発生する（vendoredのOpenSSL/SQLCipherがSDK最新でビルドされるため）。
3. **FRB再生成**: Rust API（`app/rust/src/api.rs`）を変更したら、リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。生成物（`frb_generated.*`、`app/lib/src/rust/` 配下）はコミット対象であり、**手編集禁止**である。
4. **SQLCipher鍵は常にDevice Key由来**（HKDF、`info=todori/local-db-key/v1`）。この文脈文字列は互換性に関わるため変更禁止であり、テストで値が固定されている。
5. `FileDeviceKeyStore`（`app/rust/src/dev_key_store.rs`）と `InMemoryDeviceKeyStore` は開発用実装である。**本番はOSキーチェーン実装（未実装、バックログ参照）に置き換え必須**である。
6. `sort_order` は暫定連番（`'a0'`, `'a1'`, ...）である。fractional index本実装はM3のタスクである。
7. macOS実行: `cd app && flutter build macos --debug` でビルドし、実行後のアプリの実データは `~/Library/Containers/dev.todori.todori/` に生成される。DBが暗号化されているかは `head -c 16 <db> | xxd` で乱数ヘッダを確認して検証する。
8. iOS向けコア検証手法（確立済み）: `cargo test --no-run --target aarch64-apple-ios-sim -p todori-crypto -p todori-storage` → `xcrun simctl boot <device>` → `xcrun simctl spawn <device> <test binary>`。
9. Flutter widget testの `FontLoader` は同一familyへ複数フォントを追加してもグリフフォールバックしない（Skiaがweight近似で1書体を選ぶ）。日本語フォールバックは `TextStyle.fontFamilyFallback` に別family（例: Hiragino Sans）を指定する。visual QAハーネス（`app/test/visual_qa/`）はこの方式で実フォントを登録している。

## サンドボックス実行時の既知の制約（codex exec / workspace-write）

- `.git` へ書き込めない場合がある。コミットは承認を得るか、サンドボックス外で実施する。
- ローカルソケットのbindが禁止されている場合があり、`flutter test` が実行不能なことがある。テストは必ず書き、実行不能な場合は環境起因である旨を完了報告に明記し、承認付き実行やユーザーへの依頼で代替する。
- ネットワークアクセスが禁止されている場合がある。新規依存追加（pub.dev/crates.io）は事前承認を得るか、ユーザーに依頼する。

## 現在地とバックログ

現在地と次の3候補は `docs/tasks/STATUS.md`、未着手候補は `docs/tasks/BACKLOG.md` を参照すること。
