# task-17: iOS Simulatorでflutter run検証

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` では、Phase 1の先行プラットフォームをiOSとしている。2026-07-04時点で、iOS Simulator上のRustコア検証（`todori-crypto` / `todori-storage`）と実機ターゲットのリンクは成功済みである。一方、`flutter_rust_bridge` + Cargokit + SQLCipher vendored OpenSSLをFlutter/Xcodeビルドパイプラインへ組み込み、iOS Simulator上でアプリとして起動できるかは未確認である。

`docs/07_Phase1計画書.md` のリスク表では、`app/rust_builder` のiOS用podspecは同梱済みで、残作業はiOS Simulator/実機での `flutter run` 確認とされている。task-16でmacOS build artifact由来の `flutter analyze` 失敗は復旧済みであるため、このタスクではiOS SimulatorでのFlutterアプリ起動を検証し、Cargokit / CocoaPods / Xcode / FRBローダー / SQLCipherリンクの残リスクを切り分ける。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md`
- `docs/tasks/task-08-bridge-usecases.md`
- `docs/tasks/task-11-ci.md`
- `docs/tasks/task-16-flutter-analyze-build-artifact.md`
- `app/pubspec.yaml`
- `app/ios/`
- `app/rust/Cargo.toml`
- `app/rust_builder/`
- `flutter_rust_bridge.yaml`

## 3. ゴール

iOS Simulator上で `flutter run` によるTodoriアプリのdebug起動を確認し、iOS向けFlutterビルドパイプラインの残リスクを記録する。

- `app/rust_builder/ios/todori_app_bridge.podspec` がCargokit経由でRust staticlibをビルドし、iOS Simulator向けにリンクできることを確認する。
- `flutter_rust_bridge` の生成物とローダーがiOS Simulator上で `todori_app_bridge` を解決できることを確認する。
- 初回起動時の開発用Device Key / SQLCipher DB openがiOS Simulator上で致命的に失敗しないことを確認する。
- 失敗がある場合は、Cargokit / CocoaPods / Xcode / Rust target / FRB / アプリコード / サンドボックス環境制約のどこで起きたかを切り分け、必要最小限の修正または未解決事項として記録する。

## 4. スコープ

### やること

1. `git status --short` で作業ツリーを確認する。
2. `flutter devices` と `xcrun simctl list devices available` で利用可能なiOS Simulatorを確認する。
3. 必要に応じてSimulatorをbootする。
4. `cd app && flutter run -d <iOS Simulator device id> --debug` を実行し、ビルド・インストール・起動ログを確認する。
5. `flutter run` が対話実行やGUI制約で完走確認できない場合は、`cd app && flutter build ios --simulator --debug` と `xcrun simctl install/launch` など、可能な代替検証を行い、代替した理由を完了報告に記録する。
6. 失敗した場合は、エラー箇所を切り分ける。必要な修正が小さくタスク範囲内であれば最小限修正する。
7. 修正した場合は、品質ゲート6点を再実行する。修正なしの検証のみでも、影響確認として実行可能な品質ゲートを実行する。
8. 指示書末尾に「## 9. 完了報告」を追記する。

### やらないこと

- iOS実機署名、Provisioning Profile、Apple Developer Team設定、Releaseビルド、Archive、App Store提出準備は行わない。
- iOS Keychain DeviceKeyStoreを実装しない。`FileDeviceKeyStore` は開発用のままとし、本番置き換えは別タスクで扱う。
- Flutter / Rust / Cargokit / CocoaPods / Xcode projectを大きく再構成しない。
- `flutter_rust_bridge` 生成物を手編集しない。
- UI機能、タスクCRUD、通知、同期、課金、法務文書を変更しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` を変更しない。
- private repoの詳細情報をpublic repoへ転記しない。

## 5. 実装手順（例）

1. `git status --short` を実行する。
2. `cd app && flutter devices` を実行し、iOS Simulatorのdevice idを控える。
3. `xcrun simctl list devices available` でboot可能なSimulatorを確認する。
4. 未bootの場合は `xcrun simctl boot <device id>` を試す。既にboot済みならそのまま進む。
5. `cd app && flutter run -d <device id> --debug` を実行する。
6. Cargokit / CocoaPods / Xcode / Rust buildで失敗する場合は、ログから失敗箇所を切り分ける。
7. Rust APIを変更した場合に限り、`flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。ただし本タスクでは原則Rust API変更を行わない。
8. 修正が必要な場合は最小限に留め、生成物やbuild artifactをコミットしない。
9. 品質ゲートを実行する。
10. 完了報告を追記する。

## 6. 受け入れ基準

- [ ] 利用したiOS Simulatorの機種名、OS version、device id、boot状態が記録されている。
- [ ] `cd app && flutter run -d <device id> --debug` の結果が記録されている。
- [ ] `flutter run` が環境制約で完走できなかった場合、代替検証の内容と理由が記録されている。
- [ ] CargokitがiOS Simulator向けRust staticlibをビルドできたか、失敗した場合は失敗箇所が記録されている。
- [ ] CocoaPods / Xcode build / FRBローダー / SQLCipherリンク / 初回起動のどこまで到達したかが記録されている。
- [ ] 必要な修正が最小限であり、iOS実機署名・Release設定・Keychain本実装・UI機能追加へスコープを広げていない。
- [ ] `app/build/`、`Pods/`、DerivedData、Simulator dataなどの生成物がコミット対象に含まれていない。
- [ ] `cargo fmt --all -- --check` が成功している、または未実行の場合は環境制約として理由が記録されている。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している、または未実行の場合は環境制約として理由が記録されている。
- [ ] `cargo test --workspace` が成功している、または未実行の場合は環境制約として理由が記録されている。
- [ ] `cd app && flutter analyze` が成功している、または未実行の場合は環境制約として理由が記録されている。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している、または未実行の場合は環境制約として理由が記録されている。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している、または未実行の場合は環境制約として理由が記録されている。
- [ ] `docs/tasks/task-17-ios-simulator-flutter-run.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- iOS Simulator起動や `flutter run` は、ローカルソケット、Flutter SDK cache、Xcode/Simulator GUI、DerivedDataなど、サンドボックス外のリソースへアクセスする可能性がある。承認付き実行が必要な場合は、環境制約として扱う。
- このタスクの主目的は「iOS SimulatorでFlutterアプリとして起動できるか」の検証である。ビルド失敗時に大きな設計変更が必要なら、無理に直さず未解決事項として次タスク化する。
- `FileDeviceKeyStore` は開発用の平文ファイル保存であり、本番利用禁止である。このタスクではiOS Keychain置き換えを行わない。
- Cargokit、pod名、crate名、FRB stemの `todori_app_bridge` 一致制約を崩さない。
- `.cargo/config.toml` の `IPHONEOS_DEPLOYMENT_TARGET=15.0` を変更しない。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- 使用したmacOS / Xcode / Flutter環境
- 利用したiOS Simulator（機種名、OS version、device id、boot状態）
- 実行したコマンド
- `flutter run` の結果
- 代替検証を行った場合は内容と理由
- 到達点（Cargokit / CocoaPods / Xcode build / FRBローダー / SQLCipher DB open / アプリ起動）
- 変更したファイル
- コミット対象に含めなかった生成物
- 品質ゲート6点の実行結果
- 未解決事項・要人間判断
