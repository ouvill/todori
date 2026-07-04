# docs/tasks/ ── 外部AIエージェント向け作業指示書

このディレクトリは、E2EE Todoアプリ「Todori」の実装作業を外部のAIコーディングエージェントに委託するための**作業指示書**を置く場所である。各指示書はリポジトリの事前知識がないAIエージェントが単独で読み、単独で完遂できることを目標に書かれている。

実行エージェントは作業前にリポジトリルートの `AGENTS.md` も読むこと。

## 前提ドキュメント

作業前に必ず以下を読むこと（各指示書内でも該当箇所を指示する）。

- [`docs/01_企画書.md`](../01_企画書.md) ── プロダクト企画・ロードマップ
- [`docs/02_機能仕様書.md`](../02_機能仕様書.md) ── 機能仕様（F-01〜F-53）
- [`docs/03_技術仕様書.md`](../03_技術仕様書.md) ── 技術仕様（本リポジトリの技術的な唯一の真実源）
- [`docs/billing_overview.md`](../billing_overview.md) ── 公開版の課金方針（Phase 1では不要なことが多い）
- リポジトリルートの [`README.md`](../../README.md) ── monorepo構成の概要

## タスク一覧

| ID | ステータス | ファイル | 概要 | 依存関係 |
|---|---|---|---|---|
| task-01 | 完了 | [task-01-opaque-poc.md](./task-01-opaque-poc.md) | OPAQUE認証PoC。`core/crypto` に opaque-ke を統合し、登録→ログイン→exportKey→KEK導出→Master Keyラップの一気通貫動作を実証する | 雛形（現在のリポジトリ状態）にのみ依存。task-02と並行実施可 |
| task-02 | 完了 | [task-02-sqlcipher-poc.md](./task-02-sqlcipher-poc.md) | SQLCipherビルド検証。`core/storage` に rusqlite(SQLCipher) を導入し、暗号化DBの動作・Androidクロスビルド可否を検証する | 雛形にのみ依存。task-01と並行実施可 |
| task-03 | 完了 | [task-03-flutter-rust-bridge.md](./task-03-flutter-rust-bridge.md) | flutter_rust_bridge統合。`app/` から Rust コアを呼び出す最小の垂直貫通を確立する | 雛形（`core/domain` 等）にのみ依存。task-01/02の結果は不要 |
| task-04 | 完了 | [task-04-phase1-plan.md](./task-04-phase1-plan.md) | Phase 1（MVP）計画書 `docs/07_Phase1計画書.md` の作成。ドキュメント作業のみでコード変更なし | 雛形にのみ依存。他タスクと並行実施可。ただし計画書内でtask-01〜03のPoC結果を前提とする箇所がある旨を明記する |
| task-05 | 完了 | [task-05-domain-usecases.md](./task-05-domain-usecases.md) | `core/domain` にリスト/タスク操作ユースケース（生成・編集・ステータス遷移・論理削除/復元・サブタスク制約検証）を追加する | 雛形にのみ依存。単独実施可。Phase1計画書M1-01に対応 |
| task-06 | 完了 | [task-06-storage-repositories.md](./task-06-storage-repositories.md) | `core/storage` に `lists` テーブルを追加し、`ListRepository` / `TaskRepository::update` を実装して `core/domain` のユースケースと接続する | task-02・task-05の成果物に依存。Phase1計画書M1-02/M1-03に対応 |
| task-07 | 完了 | [task-07-device-key.md](./task-07-device-key.md) | `core/crypto` にDevice Key生成・OSキーチェーン抽象（trait）・SQLCipher用ローカルDB鍵導出を実装し、`core/storage` でDK生成からDB openまでの統合テストを実証する | task-02・task-06の成果物に依存。Phase1計画書M1-04に対応 |
| task-08 | 完了 | [task-08-bridge-usecases.md](./task-08-bridge-usecases.md) | `todori-app-bridge` にリスト/タスク操作のユースケース単位APIを公開し、Dartテストからリスト作成・タスク作成・取得ができることを実証する | task-03・task-05〜07の成果物に依存。Phase1計画書M2-02に対応 |
| task-09 | 完了 | [task-09-ui-skeleton.md](./task-09-ui-skeleton.md) | Flutterの画面遷移骨格（リスト一覧→タスク一覧→タスク詳細）と状態管理（Riverpod）方針を実装する | task-08の成果物に依存。Phase1計画書M2-03に対応 |
| task-10 | 完了 | [task-10-i18n.md](./task-10-i18n.md) | i18n基盤（en/ja ARB）を導入し、画面骨格のUI文字列を外部化してシステム言語に追従させる | task-09の成果物に依存。Phase1計画書M2-04に対応 |
| task-11 | 完了 | [task-11-ci.md](./task-11-ci.md) | GitHub ActionsでRust/Flutter品質ゲート、FRB再生成差分チェック、直書き検出を自動化する | task-08〜10の成果物に依存。Phase1計画書M2-01に対応 |
| task-12 | 完了 | [task-12-open-source-readiness.md](./task-12-open-source-readiness.md) | OSS公開前監査。秘密情報、公開不適切情報、OSS基本文書、ライセンス、public repo向けCI/Actions安全性を棚卸しする | task-11までの成果物に依存。public repository化の事前確認 |
| task-13 | 完了 | [task-13-public-private-docs-split.md](./task-13-public-private-docs-split.md) | public repoを主、private repoを非公開資料側とする運用に向け、公開/非公開ドキュメント分類と移行計画を策定する | task-12の監査結果に依存。public repository化の事前確認 |
| task-14 | 完了 | [task-14-public-private-repo-split.md](./task-14-public-private-repo-split.md) | public/privateのsibling repo運用に向け、公開版の課金・法務要約、READMEリンク整理、private退避マッピングを作成する | task-13の分割方針に依存。private repo名は `todori-private`。GitHub repository作成・visibility変更は人間作業 |
| task-15 | 完了 | [task-15-security-policy.md](./task-15-security-policy.md) | public化前に `SECURITY.md` を作成し、脆弱性報告導線とGitHub private vulnerability reporting利用方針を整備する | task-12の監査結果に依存。GitHub private vulnerability reportingの有効化は人間作業 |
| task-16 | 完了 | [task-16-flutter-analyze-build-artifact.md](./task-16-flutter-analyze-build-artifact.md) | `flutter analyze` がmacOS build artifact内の古いcargokit参照で失敗する原因を調査し、品質ゲートを復旧する | task-14検証セッションで発見。機能変更ではなく品質ゲート復旧 |
| task-17 | 完了 | [task-17-ios-simulator-flutter-run.md](./task-17-ios-simulator-flutter-run.md) | iOS Simulatorで `flutter run` を実行し、Cargokit / CocoaPods / Xcode / FRB / SQLCipher のアプリ起動パイプラインを検証する | task-08〜11・task-16の成果物に依存。M2残のiOSビルド組み込み検証 |
| task-18 | 完了 | [task-18-task-editing-ui.md](./task-18-task-editing-ui.md) | タスク詳細画面で `title` / `note` / `priority` / `due_at` を編集し、ブリッジ更新API経由でDBへ反映する | task-08〜10の成果物に依存。M3-02のタスク編集部分 |
| task-19 | 完了 | [task-19-subtasks-ui.md](./task-19-subtasks-ui.md) | サブタスク表示・作成。`validate_parent` / `validate_parent_for` を使うブリッジ公開と、階層表示・進捗表示・親完了確認UIを実装する | task-08〜10・task-18の成果物に依存。M3-03相当 |
| task-20 | 完了 | [task-20-ui-foundation.md](./task-20-ui-foundation.md) | task-18/19後のUI文法を整える。ThemeData、共通task row/metadata、空状態、ダイアログ、既存Lists/Tasks/TaskDetailの見た目を小さく整理する | task-18・task-19の成果物に依存。ゴミ箱画面・復元UI、並び替え、通知へ進む前のUI基盤整備 |
| task-21 | 完了 | [task-21-visual-direction.md](./task-21-visual-direction.md) | 参考画像 `assets/brand/generated/todori-mobile-product.png` の方向性を、既存UI foundationへ実アプリの視覚文法として反映する | task-20の成果物に依存。ゴミ箱画面・復元UI、並び替え、通知へ進む前の視覚方向性反映 |

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
   - `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の内容は変更しない。実装中にこれらの記述と矛盾する事実（ビルド不能、API仕様の相違等）を発見した場合は、**仕様書を書き換えずに**完了報告の「未解決事項」として報告すること。
   - `.github/workflows` 配下は、当該タスクの指示書に明記がある場合を除き変更しない。
5. **依存追加の作法**: Rustの依存クレートを追加する場合は、必ずリポジトリルート `Cargo.toml` の `[workspace.dependencies]` にバージョンを集約し、各crateの `Cargo.toml` からは `foo.workspace = true` の形で参照すること（既存の `core/crypto/Cargo.toml` 等の記法に倣う）。
6. **不明点・仕様の矛盾**: 推測で進めず、判明した時点で完了報告の「未解決事項」セクションに記録し、実装は指示書のスコープ内で合理的な暫定解を取ってよい（暫定解の内容も報告すること）。

## 完了報告の規約

- 完了時は当該指示書ファイルの冒頭（タイトル直下）に `> ステータス: 完了（...）` と `> 作業日: YYYY-MM-DD` を追記し、このタスク一覧のステータス列も更新する。
- 各タスクの実行者は、完了時に当該指示書ファイルの末尾へ「## 9. 完了報告」を追記する（体裁はtask-01〜10の実例に倣う）。
- 必ず含める: 作業日、実装結果、8章（完了報告に含めるべき内容）で要求された項目、検証結果（品質ゲートの実行結果）、未解決事項。
- 未解決事項は次タスクの入力になるため、無い場合も「なし」と明記する。
