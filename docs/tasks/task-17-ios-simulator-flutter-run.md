# task-17: iOS Simulatorでflutter run検証

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` では、Phase 1の先行プラットフォームをiOSとしている。2026-07-04時点で、iOS Simulator上のRustコア検証（`taskveil-crypto` / `taskveil-storage`）と実機ターゲットのリンクは成功済みである。一方、`flutter_rust_bridge` + Cargokit + SQLCipher vendored OpenSSLをFlutter/Xcodeビルドパイプラインへ組み込み、iOS Simulator上でアプリとして起動できるかは未確認である。

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

iOS Simulator上で `flutter run` によるTaskveilアプリのdebug起動を確認し、iOS向けFlutterビルドパイプラインの残リスクを記録する。

- `app/rust_builder/ios/taskveil_app_bridge.podspec` がCargokit経由でRust staticlibをビルドし、iOS Simulator向けにリンクできることを確認する。
- `flutter_rust_bridge` の生成物とローダーがiOS Simulator上で `taskveil_app_bridge` を解決できることを確認する。
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
- Cargokit、pod名、crate名、FRB stemの `taskveil_app_bridge` 一致制約を崩さない。
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

## 9. 完了報告

作業日: 2026-07-04

### 読んだファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/07_Phase1計画書.md`
- `docs/tasks/task-08-bridge-usecases.md`
- `docs/tasks/task-11-ci.md`
- `docs/tasks/task-16-flutter-analyze-build-artifact.md`
- `app/pubspec.yaml`
- `app/ios/Podfile`
- `app/ios/.gitignore`
- `app/rust/Cargo.toml`
- `app/rust_builder/`
- `flutter_rust_bridge.yaml`

### 使用した環境

- macOS: 26.5.1 (25F80)
- Xcode: 26.6 (17F113)
- Flutter: 3.44.4 stable (`ad70ec4617`)
- Dart: 3.12.2
- CocoaPods: 1.16.2（`Podfile.lock` 記録）

### 利用したiOS Simulator

- 機種: iPhone 15 Pro
- Runtime: iOS 17.0 (`com.apple.CoreSimulator.SimRuntime.iOS-17-0`)
- Device ID: `0339916F-631F-45E4-BC7C-915DBD1C590D`
- Boot状態: `Booted`

### 実行したコマンド

- `git -C taskveil status --short`
- `flutter --version`
- `cd app && flutter devices`
- `xcrun simctl list devices available`
- `cd app && flutter run -d 0339916F-631F-45E4-BC7C-915DBD1C590D --debug`
- `xcrun simctl get_app_container 0339916F-631F-45E4-BC7C-915DBD1C590D com.taskveil.app data`
- `find <simulator app data container> -maxdepth 4 -type f`
- `xxd -l 16 <simulator app data container>/Library/Application\ Support/taskveil-db/taskveil.db`
- 品質ゲート6点（下記）

通常サンドボックスではFlutter SDK cacheとCoreSimulatorへのアクセスが拒否されたため、Flutter / simctl / process確認の一部は承認付き実行で検証した。

### `flutter run` の結果

成功。`cd app && flutter run -d 0339916F-631F-45E4-BC7C-915DBD1C590D --debug` は以下まで到達した。

- `Running pod install...`: 成功（約1.2秒）
- `Running Xcode build...`: 成功（約515.5秒）
- `Syncing files to device iPhone 15 Pro...`: 成功
- Dart VM Service: `http://127.0.0.1:52296/.../`
- Flutter DevTools: `http://127.0.0.1:52296/.../devtools/`

途中で以下の警告が出たが、現時点ではエラーではなく、ビルド・起動は継続して成功した。

- `taskveil_app_bridge` がiOS向けSwift Package Managerを未サポートであり、将来のFlutterではエラーになる可能性がある、という警告。

### 到達点

- CocoaPods: `pod install` が成功し、`Runner.xcworkspace` に `Pods/Pods.xcodeproj` が接続された。
- Cargokit / Rust staticlib: iOS Simulator向けのXcode buildが成功したため、`taskveil_app_bridge` のCargokit script phaseとRust staticlibリンクは成立した。
- Xcode build: `iphonesimulator` SDK、対象device id指定でDebug buildが成功した。
- FRBローダー: アプリが起動しDart VM Serviceに接続できたため、起動時点で致命的なFRBロード失敗は発生していない。
- SQLCipher DB open: Simulatorのapp data containerに `Library/Application Support/taskveil-db/taskveil.db` と `device.key` が作成された。`taskveil.db` の先頭16bytesは `8119 0e38 9aaf a468 f912 73a5 ebec 5752` であり、平文SQLite headerではなかった。
- アプリ起動: `flutter run` がdebug接続状態まで到達し、起動直後クラッシュは発生しなかった。

### 変更したファイル

- `app/ios/Runner.xcodeproj/project.pbxproj`
  - CocoaPodsの `Pods_Runner.framework` / `Pods_RunnerTests.framework`、Pods xcconfig、`[CP] Check Pods Manifest.lock`、`[CP] Embed Pods Frameworks` をXcode projectへ接続した。
- `app/ios/Runner.xcworkspace/contents.xcworkspacedata`
  - `Pods/Pods.xcodeproj` をworkspaceへ追加した。
- `app/ios/Podfile.lock`
  - `Flutter` と `taskveil_app_bridge` のpod解決結果、checksum、CocoaPods 1.16.2を記録した。
- `docs/tasks/README.md`
  - task-17を完了へ更新した。
- `docs/tasks/BACKLOG.md`
  - iOS Simulatorでの `flutter run` 検証完了を現在地へ反映し、優先度付きバックログから当該行を外した。
- `docs/tasks/task-17-ios-simulator-flutter-run.md`
  - ステータスと本完了報告を追記した。

### コミット対象に含めなかった生成物

- `app/ios/Pods/`
- `app/ios/.symlinks/`
- `app/ios/Flutter/ephemeral/`
- `app/build/`
- Simulator app data container（`taskveil.db`、`device.key` を含む）
- Flutter / Dart tool cache

### 品質ゲート6点の実行結果

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（Rust 62件成功）。
- `cd app && flutter analyze`: 成功（承認付き実行、`No issues found`）。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test`: 成功（Flutter 11件成功、`flutter test` は承認付き実行）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。

追加で `git -C taskveil diff --check` を実行し、成功した。

### 未解決事項・要人間判断

- `taskveil_app_bridge` がiOS向けSwift Package Managerを未サポートである警告が出ている。現時点のFlutter 3.44.4では警告のみでビルド可能だが、将来のFlutterではエラー化される可能性があるため、SPM対応または警告への方針決定を後続で検討する。
- iOS実機署名、Release build、Archive、App Store提出準備は本タスクの範囲外であり未実施。
- iOS Keychain DeviceKeyStore本実装は未実施。引き続き後続タスクで扱う。
