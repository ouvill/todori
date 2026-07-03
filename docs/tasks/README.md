# docs/tasks/ ── 外部AIエージェント向け作業指示書

このディレクトリは、E2EE Todoアプリ「Todori」の実装作業を外部のAIコーディングエージェントに委託するための**作業指示書**を置く場所である。各指示書はリポジトリの事前知識がないAIエージェントが単独で読み、単独で完遂できることを目標に書かれている。

## 前提ドキュメント

作業前に必ず以下を読むこと（各指示書内でも該当箇所を指示する）。

- [`docs/01_企画書.md`](../01_企画書.md) ── プロダクト企画・ロードマップ
- [`docs/02_機能仕様書.md`](../02_機能仕様書.md) ── 機能仕様（F-01〜F-53）
- [`docs/03_技術仕様書.md`](../03_技術仕様書.md) ── 技術仕様（本リポジトリの技術的な唯一の真実源）
- [`docs/04_課金設計書.md`](../04_課金設計書.md) ── 課金設計（Phase 1では不要なことが多い）
- リポジトリルートの [`README.md`](../../README.md) ── monorepo構成の概要

## タスク一覧

| ID | ファイル | 概要 | 依存関係 |
|---|---|---|---|
| task-01 | [task-01-opaque-poc.md](./task-01-opaque-poc.md) | OPAQUE認証PoC。`core/crypto` に opaque-ke を統合し、登録→ログイン→exportKey→KEK導出→Master Keyラップの一気通貫動作を実証する | 雛形（現在のリポジトリ状態）にのみ依存。task-02と並行実施可 |
| task-02 | [task-02-sqlcipher-poc.md](./task-02-sqlcipher-poc.md) | SQLCipherビルド検証。`core/storage` に rusqlite(SQLCipher) を導入し、暗号化DBの動作・Androidクロスビルド可否を検証する | 雛形にのみ依存。task-01と並行実施可 |
| task-03 | [task-03-flutter-rust-bridge.md](./task-03-flutter-rust-bridge.md) | flutter_rust_bridge統合。`app/` から Rust コアを呼び出す最小の垂直貫通を確立する | 雛形（`core/domain` 等）にのみ依存。task-01/02の結果は不要 |
| task-04 | [task-04-phase1-plan.md](./task-04-phase1-plan.md) | Phase 1（MVP）計画書 `docs/07_Phase1計画書.md` の作成。ドキュメント作業のみでコード変更なし | 雛形にのみ依存。他タスクと並行実施可。ただし計画書内でtask-01〜03のPoC結果を前提とする箇所がある旨を明記する |
| task-05 | [task-05-domain-usecases.md](./task-05-domain-usecases.md) | `core/domain` にリスト/タスク操作ユースケース（生成・編集・ステータス遷移・論理削除/復元・サブタスク制約検証）を追加する | 雛形にのみ依存。単独実施可。Phase1計画書M1-01に対応 |
| task-06 | [task-06-storage-repositories.md](./task-06-storage-repositories.md) | `core/storage` に `lists` テーブルを追加し、`ListRepository` / `TaskRepository::update` を実装して `core/domain` のユースケースと接続する | task-02・task-05の成果物に依存。Phase1計画書M1-02/M1-03に対応 |
| task-07 | [task-07-device-key.md](./task-07-device-key.md) | `core/crypto` にDevice Key生成・OSキーチェーン抽象（trait）・SQLCipher用ローカルDB鍵導出を実装し、`core/storage` でDK生成からDB openまでの統合テストを実証する | task-02・task-06の成果物に依存。Phase1計画書M1-04に対応 |
| task-08 | [task-08-bridge-usecases.md](./task-08-bridge-usecases.md) | `todori-app-bridge` にリスト/タスク操作のユースケース単位APIを公開し、Dartテストからリスト作成・タスク作成・取得ができることを実証する | task-03・task-05〜07の成果物に依存。Phase1計画書M2-02に対応 |
| task-09 | [task-09-ui-skeleton.md](./task-09-ui-skeleton.md) | Flutterの画面遷移骨格（リスト一覧→タスク一覧→タスク詳細）と状態管理（Riverpod）方針を実装する | task-08の成果物に依存。Phase1計画書M2-03に対応 |

依存関係の要点: **task-01・task-02・task-03・task-04は互いに独立しており並行着手できる。** 各タスクは現在コミット済みの雛形（Rust workspace: `core/{domain,crypto,sync,storage}`, `cli`, `mcp-server`, `server` + Flutter `app/`）にのみ依存し、他タスクの成果物を前提としない。task-04（計画書）は内容としてtask-01〜03のPoC結果を参照する記述を含むが、計画書自体の執筆はPoCの完了を待たずに着手してよい（未完了の場合は「前提: task-0Xの結果待ち」と明記すること）。

## 共通規約

1. **作業前に仕様書を読む**: 各指示書が指定する `docs/01〜04` の該当箇所を必ず読み、リポジトリの設計思想と矛盾しない実装を行うこと。
2. **品質ゲート**: 以下がすべて通過することをコミット前に確認する。
   - `cargo fmt --all -- --check`
   - `cargo clippy --workspace -- -D warnings`
   - `cargo test --workspace`
   - Flutter（`app/`）に変更を加えた場合は追加で `cd app && flutter analyze` も通過すること
3. **コミット規約**: [Conventional Commits](https://www.conventionalcommits.org/)（`feat:` / `fix:` / `docs:` / `chore:` 等）に従う。コミット本文は日本語で構わない。1タスクにつき1〜数コミットを目安とする。
4. **変更禁止事項**:
   - `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` / `docs/04_課金設計書.md` の内容は変更しない。実装中にこれらの記述と矛盾する事実（ビルド不能、API仕様の相違等）を発見した場合は、**仕様書を書き換えずに**完了報告の「未解決事項」として報告すること。
   - `.github/workflows` 配下は、当該タスクの指示書に明記がある場合を除き変更しない。
5. **依存追加の作法**: Rustの依存クレートを追加する場合は、必ずリポジトリルート `Cargo.toml` の `[workspace.dependencies]` にバージョンを集約し、各crateの `Cargo.toml` からは `foo.workspace = true` の形で参照すること（既存の `core/crypto/Cargo.toml` 等の記法に倣う）。
6. **不明点・仕様の矛盾**: 推測で進めず、判明した時点で完了報告の「未解決事項」セクションに記録し、実装は指示書のスコープ内で合理的な暫定解を取ってよい（暫定解の内容も報告すること）。
