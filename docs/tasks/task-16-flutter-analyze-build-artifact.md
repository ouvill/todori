# task-16: flutter analyze失敗原因の調査

> ステータス: 未着手

## 1. 背景とコンテキスト

task-14の検証セッションで品質ゲート6点を再実行したところ、`cd app && flutter analyze` が失敗した。失敗内容は `app/build/macos/Build/Intermediates.noindex/Pods.build/.../build_tool/bin/build_tool_runner.dart` が `package:build_tool/build_tool.dart` を解決できないこと、および生成された `pubspec.yaml` が古い絶対パス `/Users/youhei/workspaces/todori/app/rust_builder/cargokit/build_tool` を参照していることである。

`flutter test` は成功しており、失敗箇所はアプリ本体コードではなく、macOS build artifact または cargokit / CocoaPods が生成した中間ファイルを analyzer が拾っている可能性が高い。ただし品質ゲートとして `flutter analyze` が通らない状態は放置しない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/task-11-ci.md`
- `docs/tasks/task-14-public-private-repo-split.md`
- `app/.gitignore`
- `app/analysis_options.yaml`
- `app/pubspec.yaml`
- `app/rust_builder/`

## 3. ゴール

`flutter analyze` が失敗した原因を切り分け、品質ゲートとして安定して実行できる状態にする。

- build artifact が analyzer 対象に入っているだけなのか確認する。
- 古い絶対パスがどの生成物・手順から生じたか確認する。
- `flutter clean`、再ビルド、analysis exclude、cargokit生成物設定のいずれで解決すべきか判断する。
- 必要最小限の修正を行い、`cd app && flutter analyze` を成功させる。

## 4. スコープ

### やること

1. `git status --short` で作業ツリーを確認する。
2. `cd app && flutter analyze` を再実行し、現時点で再現するか確認する。
3. `app/build/` 配下が analyzer 対象に入る理由を確認する。
4. `app/analysis_options.yaml`、`.gitignore`、Flutter / Dart analyzer の対象範囲を確認する。
5. 旧パス `/Users/youhei/workspaces/todori/app/rust_builder/cargokit/build_tool` がどのファイルに残っているか検索する。
6. 原因が build artifact の残留であれば、再生成または analyzer 除外のどちらが妥当か判断する。
7. 必要な場合のみ設定ファイルを最小限変更する。
8. 品質ゲート6点を再実行する。
9. 完了報告を追記する。

### やらないこと

- Flutter / Rust / cargokit のバージョンを変更しない。
- `flutter_rust_bridge` 生成物を手編集しない。
- アプリ機能やUIを変更しない。
- unrelatedなbuild設定やCIをまとめて整理しない。
- `app/build/` などignore対象の生成物をコミットしない。

## 5. 実装手順（例）

1. `git status --short` を実行する。
2. `cd app && flutter analyze` を実行する。
3. `rg -n "/Users/youhei/workspaces/todori|build_tool/build_tool.dart|build_tool_runner" app .github` で古いパスと生成物参照を調べる。
4. `app/analysis_options.yaml` の `analyzer.exclude` を確認する。
5. `flutter clean` や macOS build artifact の再生成で直るかを確認する。ただし削除系操作は安全性を確認してから行う。
6. 設定修正が必要な場合は、最小限のexcludeや生成手順修正に留める。
7. 品質ゲートを実行する。
8. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] `flutter analyze` 失敗の原因が、build artifact残留、analyzer対象範囲、生成設定、または別原因のいずれかとして説明されている。
- [ ] 旧絶対パス `/Users/youhei/workspaces/todori/app/rust_builder/cargokit/build_tool` の発生源と現在の残存有無が記録されている。
- [ ] 必要な修正が最小限であり、アプリ機能・UI・FRB生成物を不要に変更していない。
- [ ] `app/build/` などignore対象の生成物がコミット対象に含まれていない。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `docs/tasks/task-16-flutter-analyze-build-artifact.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクは品質ゲート復旧のための調査・最小修正であり、機能開発ではない。
- `flutter analyze` が生成物を拾う問題は再発しやすいため、単にローカル生成物を消すだけで終わらせず、再発条件を完了報告に残す。
- 環境起因で実行できないゲートがある場合は、コード起因の失敗と区別して完了報告に記録する。

## 8. 完了報告に含めるべき内容

- 作業日
- 再現したエラー内容
- 原因の切り分け結果
- 旧絶対パスの発生源と残存有無
- 変更したファイル
- 変更しなかったが確認したファイル・ディレクトリ
- 品質ゲート6点の実行結果
- 未解決事項・要人間判断
