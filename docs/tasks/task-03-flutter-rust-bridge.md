# task-03: flutter_rust_bridge統合

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

Todoriは「Flutter（UI）+ Rust（コアロジック）」構成を採用しており、両者は `flutter_rust_bridge` によるFFIバインディングで接続される（`docs/03_技術仕様書.md` §1.1〜1.3）。現時点のリポジトリでは Flutter アプリ (`app/`) と Rust workspace (`core/`, `cli/`, `mcp-server/`, `server/`) は雛形として別々にコミットされているのみで、両者を繋ぐブリッジは未構築である。

このタスクは、Dart側からRustコアの関数を実際に呼び出せる**最小の垂直貫通**を確立するPoCである。将来的にはUIのすべての操作がこのブリッジ経由で `core::domain` / `core::storage` / `core::sync` を呼び出すことになるが、本タスクではその配線の最小サンプルを1本通すことがゴールである。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` §1.1〜1.3（技術スタック選定、flutter_rust_bridge採用理由、懸念点と対策の表）
- `app/pubspec.yaml`（現在の依存関係。Flutter SDKバージョン制約 `sdk: ^3.12.2` を確認）
- `app/lib/main.dart`（現在は `flutter create` のデフォルトカウンターアプリのまま）
- `app/test/widget_test.dart`（現在のテストもデフォルトのまま）
- `core/domain/src/lib.rs`、`core/domain/src/entities.rs`（`Task` / `TaskStatus` の定義。ブリッジ経由で呼び出すサンプルAPIの中身として利用する）
- リポジトリルート `Cargo.toml`（workspace構成。新規crateをmembersに追加する）

## 3. ゴール

`flutter_rust_bridge` v2系を用いて、`app/` から Rust コア（`todori-domain` を含む）の関数をDartから呼び出せる最小構成を作る。Linuxデスクトップ環境で動作確認・自動テストができること。

## 4. スコープ

### やること

1. **codegenツールの導入**: `cargo install flutter_rust_bridge_codegen`（v2系。バージョンは執筆時点の最新安定版を選定し完了報告に記載する）。
2. **ブリッジ用crateの新設**: `app/rust/` ディレクトリに新規Rust crateを作成する。
   - crate名: `todori-app-bridge`
   - `app/rust/Cargo.toml` の `[lib]` に `crate-type = ["cdylib", "staticlib"]` を設定する
   - `todori-domain.workspace = true` を依存に追加し、リポジトリルート `Cargo.toml` の `[workspace] members` に `"app/rust"` を追加する
   - `flutter_rust_bridge` crate自体もリポジトリルート `Cargo.toml` の `[workspace.dependencies]` に追加し、`app/rust/Cargo.toml` から参照する
3. **公開API定義**: `app/rust/src/api.rs`（またはcodegenが要求する規約に沿ったファイル配置。`flutter_rust_bridge_codegen` v2 の標準構成に従うこと）に以下2関数を実装する。
   - `pub fn greet(name: String) -> String` — `format!("Hello {name} from todori-core")` を返す。ブリッジそのものが動作することを確認するための最小関数。
   - `pub fn create_draft_task(title: String) -> String` — `todori_domain::Task` の下書きインスタンスを1件生成し（`id` は `Uuid::now_v7()`、`status` は `TaskStatus::Todo`、他フィールドは適切なデフォルト値）、`serde_json::to_string` でJSON文字列化して返す。`todori-domain` とのリンクが機能していることを実証するための関数。
4. **codegen実行**: `flutter_rust_bridge_codegen generate`（または該当バージョンのコマンド）を実行し、`flutter_rust_bridge.yaml` 設定ファイルと生成物（`app/lib/src/rust/` 配下等、v2の標準出力先）を作成する。
5. **Flutter側の依存追加**: `app/pubspec.yaml` に `flutter_rust_bridge` と `ffi` パッケージを追加する（バージョンはRust側の `flutter_rust_bridge` crateとメジャーバージョンが一致すること。不一致があるとcodegenやランタイムでエラーになるため必ず確認する）。
6. **ネイティブライブラリのビルドとロード確認（Linux）**: `cargo build -p todori-app-bridge`（または `--release`）でLinux向け `.so` を生成し、Dart側から `DynamicLibrary.open` 等でロードできる場所に配置する手順を確立する（`flutter_rust_bridge` の `RustLib.init()` 相当のAPIを使う場合はそれに従う）。
7. **`app/lib/main.dart` の最小修正**: アプリ起動時（`initState` 等）に `greet("Todori")` をRust側に呼び出し、結果をテキストとして画面に表示する。既存のカウンター機能は残しても削ってもよいが、Rust呼び出し結果の表示を追加すること。
8. **Dartテストの追加**: `app/test/` に、Rust関数呼び出しを検証するテストを追加する（ファイル名例: `app/test/rust_bridge_test.dart`）。ネイティブライブラリをビルドしてロードする構成とし、`greet` と `create_draft_task` の両方を呼び出して期待する文字列/JSON構造が返ることを検証する。

### やらないこと

- Android/iOS/Windows向けのネイティブビルドをFlutterビルドパイプラインに組み込む作業（`android/app/build.gradle.kts` の変更、Xcodeプロジェクトの変更等）は行わない。Linux上で動作すればよい。他プラットフォーム用の生成ファイル・設定ファイルはcodegenが自動生成したものをそのまま残してよいが、追加の手作業でのビルド設定は不要。
- 非同期API・Stream（`flutter_rust_bridge` のasync機能）の導入。
- 既存UI（カウンターアプリ）の本格的な置き換えやデザイン実装。Rust呼び出し結果を表示する最小限の変更のみ行う。
- `core/storage` / `core/sync` / `core/crypto` とのブリッジ接続（本タスクは `todori-domain` の疎通確認のみ）。

## 5. 実装手順（例）

1. `cargo install flutter_rust_bridge_codegen` を実行し、バージョンを確認する（`flutter_rust_bridge_codegen --version`）。
2. `cargo new --lib app/rust --name todori-app-bridge` でcrateを作成し、`Cargo.toml` を編集する。
3. リポジトリルート `Cargo.toml` の `members` に `"app/rust"` を、`[workspace.dependencies]` に `flutter_rust_bridge = "<version>"` を追加する。
4. `app/rust/src/api.rs` にAPI関数を実装する。
5. `flutter_rust_bridge_codegen` の初期化コマンド（`flutter_rust_bridge_codegen create` または既存プロジェクトへの `integrate` 相当。バージョンのドキュメントに従う）を実行し、`flutter_rust_bridge.yaml` を生成・調整する。
6. `flutter_rust_bridge_codegen generate` を実行し、Dartバインディングコードを生成する。
7. `app/pubspec.yaml` に依存を追加し `cd app && flutter pub get` を実行する。
8. `app/lib/main.dart` を修正する。
9. `cd app/rust && cargo build` でネイティブライブラリをビルドし、Linuxで `flutter run -d linux` により動作確認する。
10. `app/test/rust_bridge_test.dart` を実装し `cd app && flutter test` で確認する。
11. 最後に `cargo fmt --all`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`、`cd app && flutter analyze` を実行する。

## 6. 受け入れ基準

- [ ] `cargo fmt --all -- --check` が差分なしで通過する（`app/rust` 配下も含む）
- [ ] `cargo clippy --workspace -- -D warnings` が警告ゼロで通過する（`todori-app-bridge` がworkspaceメンバーとして含まれること）
- [ ] `cargo test --workspace` が全テスト成功する
- [ ] `cd app && flutter analyze` が警告・エラーなしで完了する
- [ ] `cd app && flutter test` で、Rust関数呼び出し（`greet` / `create_draft_task`）を検証するテストを含め全テストが成功する。**もし構成上の制約（CI環境でのネイティブビルド不可等）で `flutter test` からのネイティブ呼び出しがどうしても成立しない場合に限り**、その理由を明記した上で代替として (a) `flutter run -d linux` による手動確認手順をドキュメント化し、(b) Dart単体でのFFIライブラリロード確認テスト（実際の関数呼び出しまでは行わずライブラリのロード自体を検証するテスト）で代替してよい。この代替を取った場合は完了報告に理由を必ず明記すること。

## 7. 制約・注意事項

- `flutter_rust_bridge` のRust側crateバージョンとDart側pubパッケージバージョンのメジャーバージョンは必ず一致させること（不一致は生成コードのコンパイルエラーやランタイムクラッシュの典型的な原因）。
- Rust関数はpanicせず `Result` を返す設計が望ましいが（`docs/03_技術仕様書.md` §1.3 表の「FFI境界でのエラーハンドリング」参照）、本PoCの2関数はいずれもエラーを起こしえない単純な処理のため、`Result` 化は必須としない（無理に複雑化しない）。
- 生成されたコード（`app/lib/src/rust/` 等）はリポジトリにコミットしてよい生成物として扱う（Dartプロジェクトの規約上、通常はコミットされる運用が一般的だが、`.gitignore` の既存設定と矛盾しないか確認すること）。

## 8. 完了報告に含めるべき内容

- 採用した `flutter_rust_bridge` / `flutter_rust_bridge_codegen` の正確なバージョン
- codegenの再実行手順（依存追加やAPI変更のたびに何を実行すればよいか。`app/README.md` 等への追記があれば併記）
- Linux以外のプラットフォーム（Android/iOS/Windows/macOS）へのビルド組み込みに必要な残作業のリスト（次タスクへの引き継ぎ用）
- `flutter test` でのネイティブ呼び出し検証が成立したか、代替手段を取ったか、その理由
- 未解決事項（あれば）

## 9. 完了報告

作業日: 2026-07-04

### 実装結果

- `app/rust/` に `todori-app-bridge` crateを追加した。
- `flutter_rust_bridge 2.12.0` / `flutter_rust_bridge_codegen 2.12.0` を採用した。
- `flutter_rust_bridge.yaml` を追加し、`crate::api` からDart/Rust生成物を作る構成にした。
- Rust APIとして `greet(name: String) -> String` と `create_draft_task(title: String) -> String` を実装した。
- Flutter UIの起動時に `greet("Todori")` を呼び、結果を画面に表示するようにした。
- `app/test/rust_bridge_test.dart` を追加し、Dart側から実際にRust関数を呼び出すテストを実装した。

### 採用バージョン

| 対象 | version |
|---|---|
| Rust crate `flutter_rust_bridge` | `2.12.0` |
| CLI `flutter_rust_bridge_codegen` | `2.12.0` |
| Dart package `flutter_rust_bridge` | `2.12.0` |
| Dart package `ffi` | `2.2.0`（lockfile解決結果） |

### codegen再実行手順

API変更後はリポジトリルートで以下を実行する。

```sh
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

生成物:

- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `app/lib/src/rust/frb_generated.io.dart`
- `app/rust/src/frb_generated.rs`
- `app/rust/frb_generated.h`

テスト用ネイティブライブラリは、生成コードのデフォルト探索先に合わせて以下で作成した。

```sh
cd app/rust
env CARGO_TARGET_DIR=target cargo build --release
```

### flutter testでの検証

- 代替手段ではなく、実FFI呼び出しで検証した。
- `flutter test` で `greet` と `create_draft_task` の呼び出しが成功した。
- widget testはネイティブライブラリに依存しすぎないよう、`MyApp(greeting: Future.value(...))` でUI表示を検証する構成にした。

### Linux以外の残作業

- iOS: `app/rust` crateをiOS向け `staticlib` としてビルドし、Xcode projectへリンクする設定が必要。macOS runnerまたは実機環境で検証する。
- Android: `cargo-ndk` またはcargokit等で `todori-app-bridge` の `cdylib` をABI別に生成し、Gradleへ組み込む必要がある。
- macOS/Windows/Linux: desktop向けのdynamic library配置先をFlutter build/runの成果物に合わせて固定する必要がある。
- CI: FRB生成差分チェック、Cargo/Dart依存キャッシュ、プラットフォーム別ビルドジョブを追加する必要がある。

### 検証

- `cargo build --release`（`app/rust`, `CARGO_TARGET_DIR=target`）成功。
- `cargo clippy --workspace -- -D warnings` 成功。
- `cargo test --workspace` 成功。
- `cd app && flutter analyze` 成功。
- `cd app && flutter test` 成功。

### 未解決事項

- `flutter_rust_bridge` 生成マクロ由来で、clippyの `not_unsafe_ptr_arg_deref` が発生したため、`app/rust/src/lib.rs` にcrate限定の `#![allow(clippy::not_unsafe_ptr_arg_deref)]` を追加した。手書きAPIではなく生成FFI境界に対するallowである。
- Linux以外のプラットフォームへのビルド組み込みは未実施。
