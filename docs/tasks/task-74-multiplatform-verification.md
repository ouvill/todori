# task-74: マルチプラットフォームビルド検証

> ステータス: 完了（環境制約あり）
> 作成日: 2026-07-08
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

P2-M5前半 task-73 で削除同期ADR-010ドラフト、削除tombstone blob空化、List DEK整合まで完了した。Phase 2自律スコープの最後に、同期・アカウント・Keychain・SQLCipher・reqwest(rustls) を含む現在のアプリが主要ターゲットでビルドできるかを確認する。

本タスクは実装追加ではなく検証が主目的である。Android、macOS、iOS Simulator のビルドを実行し、コード互換問題があれば指示書スコープ内の小さな条件付きコンパイルやfeature flag修正で解消する。Gradle、Android SDK/NDK、Xcode署名など人間作業が必要な環境不足は、具体的なコマンド、エラー、必要作業として記録する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/03_技術仕様書.md` §2、§4.3、§5.3、§6、§11.2
- `docs/08_Phase2計画書.md` P2-M5
- `docs/tasks/task-64-keychain-device-key.md` の `## 9. 完了報告`
- `docs/tasks/task-73-adr010-and-dek-alignment.md` の `## 9. 完了報告`
- `Cargo.toml`
- `app/rust/Cargo.toml`
- `app/rust/src/dev_key_store.rs`
- `app/rust/src/api.rs`
- `app/pubspec.yaml`
- `app/android/`、`app/ios/`、`app/macos/` のビルド設定

## 3. ゴール

- Android向けRust FFIビルドと `flutter build apk --debug` を試行し、成功/失敗を証拠付きで記録する。
- macOS `flutter build macos --release` が成功することを確認する。
- iOS Simulator `flutter build ios --simulator --debug` が成功することを確認する。
- reqwest(rustls)、security-framework、SQLCipher、OpenSSL vendoring、cargokit/FRBのクロスコンパイル互換問題を切り分ける。
- 非Apple platformでは `FileDeviceKeyStore` fallbackが使われ、Apple Keychain依存がAndroid/Linuxビルドへ漏れないことを確認する。
- Android Keystore本実装を後続バックログへ、出典付きで追加する。
- README/BACKLOG/task指示書を検証結果に合わせて更新する。

## 4. スコープ

### 想定変更ファイル

- `docs/tasks/task-74-multiplatform-verification.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `README.md`
- `app/rust/Cargo.toml`
- `app/rust/src/dev_key_store.rs`
- 必要な場合のみ、Android/iOS/macOSビルド設定の最小差分

### やること

1. `git status --short` で作業前状態を確認する。
2. Android toolchain前提を確認する: `cargo ndk --version`、`rustup target list --installed | grep aarch64-linux-android`、`cd app && flutter doctor -v`。
3. `cd app/rust && cargo ndk -t arm64-v8a -o ../android/app/src/main/jniLibs build --release` を試行する。
4. `cd app && flutter build apk --debug` を試行し、成功時はAPKサイズを記録する。
5. `cd app && flutter build macos --release` を実行する。
6. `cd app && flutter build ios --simulator --debug` を実行する。
7. 失敗時は環境不足かコード互換問題かを切り分け、コード互換問題だけを最小修正する。
8. `security-framework` がApple platform限定依存になっていること、非Appleでは `FileDeviceKeyStore` が使われることを確認する。
9. Android Keystore対応をBACKLOGへ出典付きで追加する。
10. READMEへマルチプラットフォーム検証メモを追加する。
11. 品質ゲートをすべて実行し、本指示書へ `## 9. 完了報告` を追記する。

### やらないこと

- git commit。
- Android Keystore本実装。
- Linux/Windows向けの正式keychain実装。
- iOS実機Release署名、App Store提出、Play Store提出。
- 本番AWS/ECR/Lambda/Neonデプロイ。
- ADR-010の人間承認や仕様変更。

## 5. 実装手順

1. task-64/task-73の完了報告を読み、Keychain fallback、List DEK、同期エンジンの既知未解決事項を確認する。
2. `app/rust/Cargo.toml` と `dev_key_store.rs` を読み、Android/LinuxにApple Security framework依存が入らないことを静的確認する。
3. Android Rustビルドを単独で実行し、SQLCipher/OpenSSL/reqwest/ring等のクロスコンパイルエラーを先に切り分ける。
4. Flutter Android debug APKビルドを実行し、cargokit/Gradle/NDK連携のエラーを確認する。
5. macOS release buildとiOS Simulator debug buildを実行する。
6. コード互換問題があれば、target cfg、feature flag、依存のtarget限定化、最小ビルド設定修正で対応する。
7. 成功したビルド成果物のパスとサイズを記録する。失敗した場合はエラー要約と人間作業を記録する。
8. README/BACKLOGを更新する。
9. 品質ゲートを実行する。
10. 完了報告にプラットフォーム別ビルド結果表、互換問題と対処、人間作業が必要な項目を記録する。

## 6. 受け入れ基準

- [x] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。
- [x] Android Rust FFIビルドを `cargo ndk` で試行し、成功/失敗、対象ABI、成果物またはエラーを完了報告に記録している。
- [x] `flutter build apk --debug` を試行し、成功時はAPKパスとサイズ、失敗時は具体的エラーと必要な人間作業を記録している。
- [x] `flutter build macos --release` の成功/失敗と成果物パスを記録している。
- [x] `flutter build ios --simulator --debug` の成功/失敗と成果物パスを記録している。
- [x] reqwest(rustls)、security-framework、SQLCipher、OpenSSL vendoring、FRB/cargokitの互換問題があれば原因と対処を記録している。
- [x] 非Apple platformで `FileDeviceKeyStore` fallbackが使われ、Apple Keychain依存がAndroid/Linuxビルドへ入らないことを確認している。
- [x] Android Keystore本実装をBACKLOGへ出典付きで追加している。
- [x] 完了報告にプラットフォーム別ビルド結果表がある。

## 7. 制約・注意事項

- `flutter_rust_bridge` はRust/Dartとも `=2.12.0` 固定であり、更新しない。
- cargoパッケージ名、pod名、FRB stem の `taskveil_app_bridge` を変更しない。
- `.cargo/config.toml` の `IPHONEOS_DEPLOYMENT_TARGET=15.0` を消さない。
- Rust APIを変更した場合はFRB再生成が必要だが、本タスクでは原則API変更を避ける。
- `FileDeviceKeyStore` はAndroid/Linuxの暫定fallbackとしてのみ扱い、本番安全性を主張しない。
- 秘密情報（password、session token、MK、DEK、Device Key、SQLCipher鍵）をログ、完了報告、ビルドログ抜粋へ出さない。
- 環境不足をコードで迂回しない。SDK/NDK/Xcode/署名/ライセンス不足は人間作業として記録する。

## 8. 完了報告に含めるべき内容

- 作業日、読んだファイル
- 実行した検証コマンド一覧
- プラットフォーム別ビルド結果表（Android Rust、Android APK、macOS release、iOS Simulator debug）
- 成功した成果物のパスとサイズ
- 失敗したコマンドのエラー要約と必要な人間作業
- 発見したクロスコンパイル互換問題と対処
- DeviceKeyStore fallback確認結果
- README/BACKLOG更新内容
- 品質ゲート実行結果
- 変更ファイル一覧
- 未解決事項

## 9. 完了報告

作業日: 2026-07-08

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/08_Phase2計画書.md` P2-M5
- `docs/03_技術仕様書.md` §2、§4.3、§5.3、§6、§11.2
- `docs/tasks/task-64-keychain-device-key.md` の `## 9. 完了報告`
- `docs/tasks/task-73-adr010-and-dek-alignment.md` の `## 9. 完了報告`
- `Cargo.toml`
- `app/rust/Cargo.toml`
- `app/rust/src/dev_key_store.rs`
- `app/rust/src/api.rs`
- `app/pubspec.yaml`
- `README.md`

実行した検証コマンド:

- `cargo ndk --version`
- `rustup target list --installed | grep aarch64-linux-android`
- `flutter --version`
- `flutter doctor -v`
- `cd app/rust && cargo ndk -t arm64-v8a -o ../android/app/src/main/jniLibs build --release`
- `cd app && flutter build apk --debug`
- `cd app && env GRADLE_USER_HOME=/private/tmp/taskveil-gradle flutter build apk --debug`
- `cd app && flutter build macos --release`
- `cd app && env HOME=/private/tmp/taskveil-home PUB_CACHE=/Users/youhei/.pub-cache flutter build macos --release`
- `cd app && env CFFIXED_USER_HOME=/private/tmp/taskveil-home HOME=/private/tmp/taskveil-home PUB_CACHE=/Users/youhei/.pub-cache flutter build macos --release`
- `cd app && flutter build ios --simulator --debug`
- `cargo tree -p taskveil_app_bridge --target aarch64-linux-android | grep security-framework || true`

プラットフォーム別ビルド結果:

| 対象 | コマンド | 結果 | 成果物/エラー |
|---|---|---|---|
| Android Rust FFI | `cargo ndk -t arm64-v8a -o ../android/app/src/main/jniLibs build --release` | 成功 | `app/android/app/src/main/jniLibs/arm64-v8a/libtaskveil_app_bridge.so`、13MB。生成物は検証後に削除した |
| Android APK debug | `flutter build apk --debug` | 失敗（環境） | 初回は `~/.gradle/...gradle-9.1.0-all.zip.lck` 作成不可。`GRADLE_USER_HOME=/private/tmp/taskveil-gradle` 再試行では `~/.android/cache/... Operation not permitted` と `NDK not configured. Preferred NDK version is '28.2.13676358'` |
| macOS release | `flutter build macos --release` | 失敗（環境） | SwiftPM依存解決前に `~/Library/Caches/org.swift.swiftpm/... Operation not permitted`。`CFFIXED_USER_HOME` 再試行では `sandbox-exec: sandbox_apply: Operation not permitted` |
| iOS Simulator debug | `flutter build ios --simulator --debug` | 失敗（環境） | SwiftPM依存解決前に `~/Library/Caches/org.swift.swiftpm/... Operation not permitted`。CoreSimulatorService接続不可、log書き込み不可も併発 |

環境確認:

- `cargo-ndk 4.1.2`
- `aarch64-linux-android` target導入済み
- Flutter `3.44.4`、Dart `3.12.2`
- `flutter doctor -v`: Android toolchainはOK。Xcodeは `Xcode requires additional components to be installed` で、`sudo xcodebuild -runFirstLaunch` が必要と表示された。
- Android SDKのNDKは `30.0.14904198` のみ確認。Flutter/Gradleが要求した `28.2.13676358` は未導入。

発見したクロスコンパイル互換問題と対処:

- Android targetで `ensure_device_key_with_migration` が未使用警告になった。Apple platform専用の移行helperであり、Androidでは呼ばれないため、`#[cfg(any(test, target_os = "ios", target_os = "macos"))]` を付けてAndroid build warningを解消した。
- `reqwest` は `rustls-tls` / `webpki-roots` 経路でAndroid向けにコンパイルされた。
- SQLCipherは `rusqlite` の `bundled-sqlcipher-vendored-openssl` 経路でAndroid向けにコンパイルされた。
- `cargo tree -p taskveil_app_bridge --target aarch64-linux-android | grep security-framework || true` は出力なし。Apple `security-framework` 依存はAndroid targetへ入っていない。
- FRB/cargokitの名前不整合は見つからなかった。Android Rust FFIの成果物名は `libtaskveil_app_bridge.so`。

DeviceKeyStore fallback確認:

- `app/rust/Cargo.toml` では `security-framework` は `target.'cfg(any(target_os = "ios", target_os = "macos"))'.dependencies` に限定されている。
- `load_or_create_device_key()`、`load_account_secret()`、`store_account_secret()`、`delete_account_secret()` は、`#[cfg(not(any(target_os = "ios", target_os = "macos")))]` 分岐で `FileDeviceKeyStore` / `FileSecretStore` を使う。
- Android/Linuxでは現時点で暫定ファイル保存fallbackであり、本番向けAndroid Keystore実装は未実装。

README/BACKLOG更新内容:

- `README.md` にマルチプラットフォーム検証メモを追加した。
- `docs/tasks/README.md` にtask-74完了状態を反映した。
- `docs/tasks/BACKLOG.md` の現在地へtask-74結果を追加した。
- `docs/tasks/BACKLOG.md` の優先度付きバックログへAndroid Keystore DeviceKeyStoreを、Android Developers公式ドキュメントを出典として追加した。
- `docs/tasks/BACKLOG.md` の要人間判断へ、Android/macOS/iOS実ビルド再検証に必要な人間作業を追加した。

品質ゲート実行結果:

- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功
  - `taskveil-crypto`: 24 passed
  - `taskveil-domain`: 40 passed
  - `server/tests/sync_server.rs`: 5 passed
  - `taskveil-storage`: 48 passed, 1 ignored
  - `taskveil-sync`: 29 passed
  - `taskveil_app_bridge`: 4 passed, 1 ignored
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter analyze`: 成功
- `cd app && flutter test`: 成功（123 passed、visual QA harness 1 skipped）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `git diff --check`: 成功

変更ファイル一覧:

- `README.md`
- `app/rust/src/dev_key_store.rs`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/README.md`
- `docs/tasks/task-74-multiplatform-verification.md`

未解決事項:

- Android APK debugは未成功。人間環境でNDK `28.2.13676358` をAndroid SDK Managerから導入し、通常権限で `~/.android/cache` に書ける状態で再実行する必要がある。
- macOS releaseは未成功。人間環境で `sudo xcodebuild -runFirstLaunch` を実行し、通常権限で `~/Library/Caches/org.swift.swiftpm` とXcode/SwiftPMの `sandbox-exec` が使える状態で再実行する必要がある。
- iOS Simulator debugは未成功。上記Xcode初期化に加え、CoreSimulatorServiceへ接続でき、`~/Library/Logs/CoreSimulator` へ書ける通常環境で再実行する必要がある。
- AndroidではDevice Keyとアカウント秘密情報が暫定 `FileDeviceKeyStore` / `FileSecretStore` fallbackのままである。本番化前にAndroid Keystore backed実装へ置き換える。
- ADR-010の人間承認、410 Gone、フル再同期は引き続き未実装。

### 追記: flutter_local_notifications向けAndroid desugaring修正

作業日: 2026-07-08

- `app/android/app/build.gradle.kts` の `compileOptions` で `isCoreLibraryDesugaringEnabled = true` を有効化した。
- `app/android/app/build.gradle.kts` に `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` を追加した。
- Java互換設定は既存の `sourceCompatibility = JavaVersion.VERSION_17` / `targetCompatibility = JavaVersion.VERSION_17` を維持した。Java 8 API desugaring要件はcore library desugaringで満たす。
- `multiDexEnabled` は現時点では追加していない。`minSdk = flutter.minSdkVersion` であり、必要性は実Gradleビルド側のmethod countやminSdk条件で判断する。
- Gradleビルドはサンドボックスで `~/.gradle` / `~/.android` 書き込み制約により実行不能な可能性が高いため未実行。親環境で `cd app && flutter build apk --debug` により検証する。

追加変更ファイル:

- `app/android/app/build.gradle.kts`

### 追記: cargokit Gradle 9互換修正

作業日: 2026-07-08

- `app/rust_builder/cargokit/gradle/plugin.gradle` の `CargoKitBuildTask` で、Gradle 9で削除された `project.exec { ... }` を使用しないようにした。
- `ProcessBuilder` ベースの `runProcess()` helperを追加し、既存の `chmod +x <run_build_tool>` と `<run_build_tool> build-gradle` の実行を置き換えた。
- `processBuilder.directory(project.projectDir)` により、従来の `project.exec` と同じプロジェクトディレクトリ基準の作業ディレクトリを維持した。
- cargo build toolへ渡す `CARGOKIT_*` と `CARGOKIT_JAVA_HOME` の環境変数は従来と同じキー・値で設定している。
- 子プロセスは `inheritIO()` で標準入出力をGradle側へ流し、起動失敗・割り込み・非ゼロ終了は `GradleException` として伝播する。
- サンドボックスではGradle実行不可のため、`flutter build apk --debug` による実機検証は未実行。親環境でAndroid buildを再検証する。

追加変更ファイル:

- `app/rust_builder/cargokit/gradle/plugin.gradle`

### 追記: Android AARメタデータ要件対応

作業日: 2026-07-08

- Android APKビルドで `flutter_local_notifications` 22系が compile SDK 36を要求するため、`app/android/app/build.gradle.kts` の `compileSdk` を `flutter.compileSdkVersion` 参照から明示値 `36` へ変更した。
- `targetSdk` は `flutter.targetSdkVersion` 参照から明示値 `35` へ変更した状態を維持した。
- `minSdk = flutter.minSdkVersion` は現行値を維持した。`flutter_local_notifications` 向けのminSdk要件を満たす既存設定を変更していない。
- その他のAndroid設定は変更していない。

追加変更ファイル:

- `app/android/app/build.gradle.kts`

### 追記: taskveil_app_bridge AARメタデータ要件対応

作業日: 2026-07-08

- Android APKビルドで `:taskveil_app_bridge` モジュールが compile SDK 33でコンパイルされ、AARメタデータ要件15件により失敗したため、`app/rust_builder/android/build.gradle` の `compileSdkVersion` を `36` へ変更した。
- `minSdkVersion 19`、`ndkVersion android.ndkVersion`、namespace、cargokit/FRB設定は維持した。
- サンドボックスではGradle実行不可のため、`flutter build apk --debug` による再検証は未実行。親環境でAndroid buildを再検証する。

追加変更ファイル:

- `app/rust_builder/android/build.gradle`
