# task-11: CI整備（M2-01）

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` のマイルストーンM2「ブリッジとUI骨格」は、M2-01「`flutter_rust_bridge` の再生成手順とCIキャッシュ方針を固定する」を定義している（完了条件: `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` が差分なしで再実行できること）。このタスクは同項目に対応する。

task-08でRust APIをユースケース単位に公開し、FRB生成物（`app/rust/src/frb_generated.rs`、`app/rust/frb_generated.h`、`app/lib/src/rust/` 配下）がコミット対象になった。task-09でFlutter画面骨格とwidget testが整備され、task-10でi18nと `app/tool/check_hardcoded_strings.sh` が追加された。これにより、Phase 1の手動品質ゲートはほぼ揃っているが、GitHub Actions上ではまだ完全には固定されていない。

現状の `.github/workflows/ci.yml` はRustの `fmt` / `clippy` / `test` とFlutterの `pub get` / `analyze` だけを実行している。`flutter test`、FRB再生成差分チェック、直書き検出、`app/rust` のreleaseビルド、macOSランナー上での実行方針が未整備である。M3のUI機能追加に進む前に、手元で確立した品質ゲートをCIへ移し、生成物のずれやFlutter/Rust両方の回帰をPull Requestで検出できるようにする。

## 2. 事前に読むべきファイル

- `docs/07_Phase1計画書.md` M2セクション（M2-01の完了条件、M2-02〜M2-04との関係）
- `docs/tasks/BACKLOG.md`（優先度1「CI整備」の内容）
- `docs/tasks/task-08-bridge-usecases.md`（FRB生成物、`flutter_rust_bridge_codegen generate`、Dartテストの前提）
- `docs/tasks/task-09-ui-skeleton.md`（`flutter test`、`app/rust` releaseビルド、widget testの前提）
- `docs/tasks/task-10-i18n.md`（`app/tool/check_hardcoded_strings.sh` とl10n生成構成）
- `.github/workflows/ci.yml`（既存CI。Rust jobとFlutter jobの現状）
- `flutter_rust_bridge.yaml`（FRB codegenの入出力）
- `app/pubspec.yaml` / `app/pubspec.lock`（Flutter SDK・依存関係・lockfileの現状）
- `app/rust/Cargo.toml` / `app/rust_builder/`（cargokit経由のネイティブビルド前提）
- `AGENTS.md` の品質ゲートと重要な設計制約

## 3. ゴール

`.github/workflows/ci.yml` をPhase 1の品質ゲートに合わせて更新し、Pull Requestと `main` へのpushで以下を自動検証できるようにする。

- Rust workspaceの `cargo fmt --all -- --check`
- Rust workspaceの `cargo clippy --workspace -- -D warnings`
- Rust workspaceの `cargo test --workspace`
- `flutter_rust_bridge_codegen` 2.12.0による再生成と生成物差分チェック
- `app/rust` のreleaseビルド（`env CARGO_TARGET_DIR=target cargo build --release`）
- `cd app && flutter analyze`
- `cd app && flutter test`
- `sh app/tool/check_hardcoded_strings.sh`

CIはmacOSランナーで動くことを基本とし、cargokit / Flutter / Rust / SQLCipher vendored OpenSSL / FRB生成物の組み合わせが、少なくともmacOS上で一気通貫に検証される状態にする。

## 4. スコープ

### やること

1. **既存CIの棚卸し**: `.github/workflows/ci.yml` を読み、現状のRust job / Flutter jobで実行されているコマンドと不足しているゲートを整理する。既存ファイルを置き換える場合も、意図が読み取れるjob名・step名を付ける。
2. **macOSランナー化**: 少なくともFRB再生成差分チェック、`app/rust` releaseビルド、Flutter analyze/test、直書き検出は `macos-latest` で実行する。Rustのfmt/clippy/testも同一jobにまとめてよいし、必要に応じて別jobに分けてもよい。ただし、バックログの「macOSランナーを使う」という条件を満たすこと。
3. **Rust toolchain設定**: `dtolnay/rust-toolchain@stable` 等、既存の方針に沿って `rustfmt` / `clippy` コンポーネントを導入する。Rust toolchainのバージョンを固定するかstableにするかは、既存リポジトリの設定ファイル有無を確認して決め、採用理由を完了報告に書く。
4. **Flutter SDK設定**: `subosito/flutter-action@v2` 等を使い、Flutter SDKをセットアップする。channel/version/cache指定は、`app/pubspec.lock` や現在のCI方針を見て決める。バージョン固定をしない場合は、その理由（例: 現状リポジトリにFlutterバージョン固定ファイルが無い）を完了報告に書く。
5. **依存キャッシュ**: Cargo registry/git/target、Flutter pub cache、必要であればFRB codegenのcargo install成果物をキャッシュする。キャッシュキーには少なくとも `Cargo.lock`、`app/pubspec.lock`、runner OSを含め、lockfile変更時に自然に更新されるようにする。キャッシュが複雑になりすぎる場合は、まず確実に動く最小構成を優先し、キャッシュ範囲を完了報告に明記する。
6. **FRB codegen導入**: CI上で `flutter_rust_bridge_codegen` を **2.12.0固定**で利用できるようにする。`cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked` など、実行環境で再現可能な手順を使う。既にキャッシュされたバイナリを使う場合も、`flutter_rust_bridge_codegen --version` を表示して2.12.0であることをログに残す。
7. **FRB再生成差分チェック**: リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行した後、`git diff --exit-code` で生成物に差分が無いことを確認する。差分チェック対象は少なくとも `app/rust/src/frb_generated.rs`、`app/rust/frb_generated.h`、`app/lib/src/rust/` を含める。必要なら `flutter_rust_bridge.yaml` の入出力と一致するよう対象を調整する。
8. **Flutterテスト前のネイティブビルド**: `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` をFlutter test前に実行する。`AGENTS.md` の品質ゲートにある前提をCIにも反映する。
9. **Flutterゲート追加**: `cd app && flutter pub get`、`cd app && flutter analyze`、`cd app && flutter test` を実行する。`flutter test` がCI上でローカルソケットを使えることを前提に、サンドボックス固有の代替コマンドはCIへ入れない。
10. **直書き検出追加**: `sh app/tool/check_hardcoded_strings.sh` をCIに追加する。Flutter analyze/testとは別stepにし、失敗時にUI文字列直書き違反だと分かるstep名にする。
11. **差分の最小化**: 変更対象は原則 `.github/workflows/ci.yml` のみとする。CI整備に本当に必要な補助スクリプトを追加する場合は、追加理由・置き場所・実行方法を完了報告に書く。
12. **検証**: ローカルで可能な範囲でYAML構文とコマンドの妥当性を確認する。GitHub Actionsの実行結果を確認できる場合は、対象ブランチ/コミットのCI結果を完了報告に記録する。ローカルでCI全体を完全再現できない場合は、その理由と代替確認内容を明記する。

### やらないこと

- `core/`、`app/lib/`、`app/rust/`、`app/rust_builder/` の実装変更。CIで検出された失敗を直すためのアプリ実装修正は本タスクでは行わず、完了報告の未解決事項に記録する。
- `docs/01_企画書.md`、`docs/02_機能仕様書.md`、`docs/03_技術仕様書.md`、`docs/04_課金設計書.md`、`docs/07_Phase1計画書.md` の変更。
- FRB生成物の手編集。CIでcodegen差分が出た場合は、生成コマンドを実行して生成物を更新するか、差分理由を調べる。手で整形して合わせてはならない。
- `flutter_rust_bridge` / `flutter_rust_bridge_codegen` のバージョン変更。2.12.0固定を維持する。
- 新規pubパッケージやRust crateの追加。CI用のGitHub Actionsの利用はよいが、アプリ/コアの依存関係は増やさない。
- iOS Simulatorでの `flutter run` 検証、iOS実機署名、macOSアプリの実行検証、Androidビルド検証。これらは別タスクで扱う。
- GitHub Pages、リリース、アーティファクト配布、デプロイ、カバレッジアップロード、PRコメントbotなどの周辺機能追加。
- `.github/workflows` 以外のCIサービス設定追加。
- CIを通すためにテストを削除・弱体化すること。失敗が既存コード由来なら、原因と次タスク候補を完了報告に残す。

## 5. 実装手順（例）

1. 2章のファイルを読み、既存CIと手動品質ゲートの差分を整理する。
2. `.github/workflows/ci.yml` のjob構成を決める。最初は `macos-latest` の単一jobで全ゲートを直列実行する構成を基本案とし、時間短縮やログ分離が必要ならRust/Flutter/FRBをjob分割する。
3. `actions/checkout@v4`、Rust toolchain、Flutter SDKをセットアップするstepを置く。
4. Cargo / Flutter pub のキャッシュを追加する。キャッシュが不安定な場合は、一度最小構成でCI成功を優先し、キャッシュの範囲を限定する。
5. `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace` をCIへ入れる。
6. `flutter_rust_bridge_codegen` 2.12.0を導入し、バージョン表示stepを追加する。
7. `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、生成物に対して `git diff --exit-code` を実行する。
8. `cd app && flutter pub get` を実行する。
9. `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` を実行する。
10. `cd app && flutter analyze` と `cd app && flutter test` を実行する。
11. `sh app/tool/check_hardcoded_strings.sh` を実行する。
12. ローカルで `git diff --check` や可能な範囲のYAML確認を行う。GitHub Actionsを実際に走らせられる場合は結果を確認する。
13. 指示書末尾に「## 9. 完了報告」を追記し、実装内容、CI job/step構成、キャッシュ方針、FRB差分チェックの対象、検証結果、未解決事項を記録する。

## 6. 受け入れ基準

- [ ] `.github/workflows/ci.yml` がPull Requestと `main` へのpushで実行される。
- [ ] CIの少なくとも主要検証jobが `macos-latest` で実行される。
- [ ] CIで `cargo fmt --all -- --check` が実行される。
- [ ] CIで `cargo clippy --workspace -- -D warnings` が実行される。
- [ ] CIで `cargo test --workspace` が実行される。
- [ ] CIで `flutter_rust_bridge_codegen` 2.12.0が使われ、`flutter_rust_bridge_codegen --version` 相当のログからバージョンを確認できる。
- [ ] CIで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` が実行される。
- [ ] CIでFRB生成物（少なくとも `app/rust/src/frb_generated.rs`、`app/rust/frb_generated.h`、`app/lib/src/rust/`）に対して `git diff --exit-code` 相当の差分チェックが実行される。
- [ ] CIで `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` が `flutter test` より前に実行される。
- [ ] CIで `cd app && flutter pub get` が実行される。
- [ ] CIで `cd app && flutter analyze` が実行される。
- [ ] CIで `cd app && flutter test` が実行される。
- [ ] CIで `sh app/tool/check_hardcoded_strings.sh` が実行される。
- [ ] Cargo / Flutter pub / 必要なcodegenインストール成果物のキャッシュ方針がworkflowまたは完了報告で説明されている。
- [ ] CI失敗時にRust fmt、Rust clippy、Rust test、FRB差分、Flutter analyze、Flutter test、直書き検出のどこで失敗したかstep名から判別できる。
- [ ] `docs/tasks/task-11-ci.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- `flutter_rust_bridge` 関連バージョンは2.12.0固定である。Rust側crate、Dart側pub、codegenのバージョンをずらさないこと。
- FRB生成物はコミット対象であり、手編集禁止である。CIでは再生成して差分が出ないことを確認する。
- `.cargo/config.toml` の `IPHONEOS_DEPLOYMENT_TARGET=15.0` は変更しないこと。
- SQLCipher鍵導出やDevice Key関連の実装には触れないこと。CIでテストを走らせるだけに留める。
- `app/tool/check_hardcoded_strings.sh` の検出範囲を広げる場合は、誤検知で開発を止めないよう実ファイルを確認し、変更理由を完了報告に書くこと。
- GitHub Actionsでネットワークアクセスを使ってFlutter SDK、pub依存、cargo依存、FRB codegenを取得するのは許容する。ただしリポジトリのアプリ依存関係を増やしてはならない。
- GitHub ActionsのmacOS runnerは実行時間が長くなりやすい。キャッシュを入れる場合も、まず正しさと再現性を優先する。
- ローカルのcodex sandboxでは `flutter test` がローカルソケット制約で失敗することがある。CIタスクではGitHub Actions上での実行を正とし、ローカルで完全再現できない場合は完了報告に明記する。
- 仕様書や計画書と実装実態が矛盾する場合は、仕様書を書き換えず、完了報告の「未解決事項」に記録する。

## 8. 完了報告に含めるべき内容

- 変更したworkflowファイルとjob/step構成
- 採用したrunner（例: `macos-latest`）とその理由
- Rust toolchain / Flutter SDK / FRB codegenのバージョン方針
- キャッシュ方針（対象、キーに含めたlockfile、キャッシュしなかったものがあればその理由）
- FRB再生成差分チェックの対象パスと実行コマンド
- Flutter test前の `app/rust` releaseビルドの扱い
- 直書き検出スクリプトのCI上での実行位置
- GitHub Actionsまたはローカルで確認した検証結果
- 未解決事項（あれば）

## 9. 完了報告

作業日: 2026-07-04

### 変更内容

- `.github/workflows/ci.yml` を更新し、Pull Requestと `main` へのpushで実行される `quality-gates` jobを追加した。
- 既存のUbuntu上のRust job / Flutter job分割を、`macos-latest` 上の単一jobに統合した。cargokit、Flutter、Rust、SQLCipher vendored OpenSSL、FRB生成物を同じmacOS環境で一気通貫に検証するためである。

### job/step構成

`Phase 1 quality gates` jobは以下の順で実行する。

1. `actions/checkout@v4`
2. Rust toolchain setup（`dtolnay/rust-toolchain@stable`、`rustfmt` / `clippy`）
3. Cargo cache restore/save
4. Flutter SDK setup（`subosito/flutter-action@v2`、`channel: stable`、Flutter cache有効）
5. `flutter_rust_bridge_codegen 2.12.0` のcache restore/save
6. `flutter_rust_bridge_codegen 2.12.0` のinstallと `flutter_rust_bridge_codegen --version`
7. `cargo fmt --all -- --check`
8. `cargo clippy --workspace -- -D warnings`
9. `cargo test --workspace`
10. `cd app && flutter pub get`
11. `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`
12. `git diff --exit-code -- app/rust/src/frb_generated.rs app/rust/frb_generated.h app/lib/src/rust`
13. `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`
14. `cd app && flutter analyze`
15. `cd app && flutter test`
16. `sh app/tool/check_hardcoded_strings.sh`

各品質ゲートはstep名を分け、Rust fmt、Rust clippy、Rust test、FRB差分、Flutter analyze、Flutter test、直書き検出のどこで失敗したか判別できる構成にした。

### バージョン方針

- Rust toolchainは既存CIと同じ `stable` を維持した。リポジトリ内に `rust-toolchain.toml` 等の固定ファイルが無いため、今回のCI整備では新たな固定を導入しない。
- Flutter SDKは `subosito/flutter-action@v2` の `channel: stable` を維持した。`app/pubspec.lock` のSDK制約は `flutter: ">=3.38.4"` だが、リポジトリにFlutterバージョン固定ファイルが無いため、現時点ではstable channel運用とする。
- FRB codegenは `cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked` で2.12.0固定にした。CIログに `flutter_rust_bridge_codegen --version` を出し、Rust側crate / Dart側pubと同じ2.12.0であることを確認できるようにした。

### キャッシュ方針

- Cargo cacheは `~/.cargo/registry`、`~/.cargo/git`、workspace rootの `target`、Flutter test前ビルド用の `app/rust/target` を対象にした。
- Cargo cache keyは `${{ runner.os }}-cargo-${{ hashFiles('Cargo.lock') }}` とし、runner OSと `Cargo.lock` の変更で自然に更新される。
- Flutter cacheは `subosito/flutter-action@v2` のcache機能を使い、keyにrunner OSと `app/pubspec.lock` を含めた。
- FRB codegen cacheは `~/.cargo/bin/flutter_rust_bridge_codegen` とcargo install metadataを対象にし、keyにrunner OS、FRB codegen 2.12.0、`Cargo.lock` を含めた。cache hit時もversion確認を行い、2.12.0でなければ `--force` 付きで再installする。

### FRB差分チェック

- 再生成コマンドはリポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。
- 差分チェック対象は `flutter_rust_bridge.yaml` の出力先に合わせ、`app/rust/src/frb_generated.rs`、`app/rust/frb_generated.h`、`app/lib/src/rust` とした。
- 差分チェックは `git diff --exit-code -- app/rust/src/frb_generated.rs app/rust/frb_generated.h app/lib/src/rust` で実行する。

### Flutter test前のネイティブビルド

- `Flutter test` stepより前に `Build app/rust release library for Flutter tests` stepを置き、`app/rust` で `env CARGO_TARGET_DIR=target cargo build --release` を実行する。
- Dart/Flutterテストが参照するネイティブライブラリを、task-08以降の手元手順と同じrelease buildで用意するためである。

### 直書き検出

- `UI hardcoded string check` stepを最後に追加し、`sh app/tool/check_hardcoded_strings.sh` を実行する。
- Flutter analyze/testとは別stepにしたため、失敗時にUI文字列直書き違反であることをCIログから判別できる。

### 検証結果

ローカルで以下を確認した。

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); puts "yaml ok"'` 成功。
- `cargo fmt --all -- --check` 成功。
- `cargo clippy --workspace -- -D warnings` 成功。
- `cargo test --workspace` 成功（Rust 62件成功）。
- `flutter_rust_bridge_codegen --version` が `flutter_rust_bridge_codegen 2.12.0` を出力。
- `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` 成功。通常サンドボックスではFlutter SDK cache更新がワークスペース外書き込みとして拒否されたため、承認付き実行で確認した。
- `git diff --exit-code -- app/rust/src/frb_generated.rs app/rust/frb_generated.h app/lib/src/rust` 成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` 成功。
- `cd app && flutter pub get` 成功。通常サンドボックスではFlutter SDK cache更新がワークスペース外書き込みとして拒否されたため、承認付き実行で確認した。
- `cd app && flutter analyze` 成功。承認付き実行で確認した。
- `cd app && flutter test` 成功（Flutter 11件成功）。承認付き実行で確認した。
- `sh app/tool/check_hardcoded_strings.sh` 成功。
- `git diff --check` 成功。

GitHub Actions上の実行結果は、このブランチをpushしていないため未確認である。

### 未解決事項

- GitHub Actions上の実CI結果は未確認である。push後に `Phase 1 quality gates` jobの通過を確認する必要がある。

### 追補: CI初回実行後の修正

- `56cd613` push後のGitHub Actions初回実行で、`Set up Flutter SDK` がSDKダウンロード中の一時的なexit code 92で失敗した。rerunでは同stepは通過した。
- rerun後、`Flutter analyze` が `app/rust_builder/cargokit/build_tool/` をアプリ本体の一部として解析し、Cargokit build_toolの未解決依存により失敗した。ローカルにはgit管理外の `.dart_tool/package_config.json` が存在したため再現しなかったが、CIのfresh checkoutでは存在しないことが原因である。
- `.github/workflows/ci.yml` に `Cargokit build_tool pub get` stepを追加し、`app/rust_builder/cargokit/build_tool` で `dart pub get` を実行してから `flutter analyze` へ進むよう修正した。`flutter analyze` 自体はAGENTS.mdの品質ゲートどおり維持する。
