# task-64: iOS/macOS Keychain DeviceKeyStore

> ステータス: 未着手
> 作業日: 未着手

## 1. 背景とコンテキスト

TodoriのローカルDBはSQLCipherで暗号化され、その鍵は常にDevice Key (DK) からHKDFで導出する。task-07で `DeviceKeyStore` trait、DK生成、`todori/local-db-key/v1` によるSQLCipher鍵導出は実装済みである。一方、現時点のアプリ統合では `app/rust/src/dev_key_store.rs` の `FileDeviceKeyStore` が `<db_dir>/device.key` に32byte DKを平文保存しており、本番利用禁止の暫定実装のままである。

本タスクでは、M4-02のセキュリティ必須項目として、iOS/macOSの本番用 `DeviceKeyStore` をApple Keychain backed実装へ置き換える。既存アーキテクチャでは `app/lib/main.dart` がアプリサポートディレクトリを決め、`init_core(db_dir, default_inbox_name)` を呼び、Rust側 `init_core` がDK確保、HKDF導出、SQLCipher DB openまでを一貫して行っている。この境界を維持するため、方式は **Rust側からApple Security frameworkを呼ぶKeychain実装** に固定する。Flutter側でKeychainへ保存してDKを `init_core` へ渡す方式は採用しない。

この選定により、DKバイト列はDart/FRB境界に出ず、既存の `DeviceKeyStore` traitと `ensure_device_key` / `derive_local_db_key` の流れを保てる。`init_core` の公開シグネチャ変更とFRB再生成も原則不要である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/03_技術仕様書.md` §4.2/§4.3（鍵階層・DK定義）、§5.3（ローカルDB鍵）
- `docs/tasks/task-07-device-key.md`
- `core/crypto/src/device_key.rs`
- `core/crypto/src/kdf.rs`
- `app/rust/src/api.rs` の `init_core`
- `app/rust/src/dev_key_store.rs`
- `app/lib/main.dart`
- `app/ios/`
- `app/macos/`
- `app/rust_builder/ios/todori_app_bridge.podspec`
- `app/rust_builder/macos/todori_app_bridge.podspec`
- `.cargo/config.toml`

## 3. ゴール

- iOS/macOS上で `FileDeviceKeyStore` ではなくApple Keychain backed `DeviceKeyStore` が使われる。
- DKはKeychainのgeneric password itemとして保存され、`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 相当でiCloud同期・バックアップ対象から外れる。
- 既存 `<db_dir>/device.key` がある端末では初回起動時に同じDKをKeychainへ移行し、移行成功後にファイルを削除する。
- Keychain移行失敗時はファイルDKを残し、旧経路で同じSQLCipher DBを開けることを優先する。
- iOS Simulatorで `flutter run` → アプリ再起動後も同じDKでDBが開けることを確認する。
- macOS dogfooding buildでも同じRust実装が動作することを確認する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `Cargo.toml`
- `app/rust/Cargo.toml`
- `app/rust/src/dev_key_store.rs`
- `app/rust/src/api.rs`
- `app/rust_builder/ios/todori_app_bridge.podspec`
- `app/rust_builder/macos/todori_app_bridge.podspec`
- `app/ios/` 配下（必要な場合のみ、Keychain利用に必要な最小差分）
- `app/macos/Runner/DebugProfile.entitlements`（必要な場合のみ）
- `app/macos/Runner/Release.entitlements`（必要な場合のみ）
- `docs/tasks/task-64-keychain-device-key.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. `app/rust/src/dev_key_store.rs` にApple Keychain backed実装を追加する。名前は `AppleKeychainDeviceKeyStore` または `KeychainDeviceKeyStore` とし、`#[cfg(any(target_os = "ios", target_os = "macos"))]` でApple platform限定にする。
2. KeychainアクセスはRust側でApple Security frameworkを呼ぶ。`SecItemCopyMatching` / `SecItemAdd` / `SecItemUpdate` / `SecItemDelete` 相当を使い、generic password itemとして32byte DKを保存する。実装にcrateを追加する場合は、workspace dependencyへ集約し、Apple platform限定依存にする。
3. Keychain itemの属性は以下を固定する。
   - class: generic password
   - service: `dev.todori.todori.device-key`
   - account: `default`
   - accessible: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 相当
   - data: DK 32byte
   - access group: 指定しない（単一アプリ内利用。Keychain sharingは使わない）
4. iOS/macOSのCocoaPods buildでSecurity frameworkがリンクされるよう、必要なら `app/rust_builder/ios/todori_app_bridge.podspec` と `app/rust_builder/macos/todori_app_bridge.podspec` に `Security` framework指定を追加する。
5. `init_core` の公開シグネチャは維持し、Apple platformではKeychain backed storeを使う。非Apple platformおよびテストで必要な場合は既存 `FileDeviceKeyStore` を開発用fallbackとして残す。
6. 既存ファイルDKからの移行処理を実装する。KeychainにDKが無く、`<db_dir>/device.key` が存在する場合、ファイルDKをKeychainへ保存し、保存成功後にファイル削除を試みる。Keychain保存に失敗した場合はファイルを削除せず、同じファイルDKでDBを開く。
7. KeychainにDKが既にある場合はKeychainのDKを正とし、ファイルDKが残っていてもDB openには使わない。ただし完了報告に残存ファイルの扱いを記録する。
8. Rustテストを追加する。通常の単体テストでは移行分岐をfake backendまたは抽象化したhelperで検証し、実Keychainに触るテストはmacOS上でのみ実行できる `#[ignore]` テストとして用意する。
9. Dart/widget統合テストは既存Fakeを継続し、DKをDart側へ渡すAPIやFake Keychainを追加しない。Flutter側の初期化フロー変更は原則不要である。
10. iOS SimulatorとmacOS dogfoodingの手動確認手順を実行し、結果を完了報告に記録する。

### やらないこと

- Flutter側でKeychainへDKを保存する実装。
- `init_core` にDKや導出鍵を渡すAPI変更。
- DKバイト列をDart/FRB境界へ露出すること。
- Android Keystore、Windows/Linux Secret Service、他Desktop向けkeychain実装。
- Master Key、`wrap(MK, DK)`、アカウント登録、同期の実装。
- DKローテーション、SQLCipher `PRAGMA rekey`、既存DBの再暗号化。
- Keychain access group / Keychain sharing / iCloud Keychain同期の導入。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. `app/rust/src/dev_key_store.rs` を、既存 `FileDeviceKeyStore` を残したまま、Apple platform用Keychain実装と移行helperを追加できる構成へ整理する。
3. Security frameworkをRustから呼ぶための依存またはFFIを追加する。crate追加時はルート `Cargo.toml` の `[workspace.dependencies]` に集約し、`app/rust/Cargo.toml` ではApple platform限定で参照する。
4. Keychain query builder相当の小さな関数を作り、service/account/accessibilityを一箇所に固定する。エラーは `KeyStoreError::Backend(String)` へ変換するが、DKや導出鍵の値を含めない。
5. `DeviceKeyStore` 実装で、`load` は未保存なら `Ok(None)`、保存済みdataが32byteでなければsanitized error、`store` はaddまたはduplicate時update、`delete` は未保存でも成功扱いにする。
6. `init_core` から呼ぶstore選択関数を追加する。Apple platformでは `ensure_device_key` 相当の前に移行helperを通し、非Apple platformでは既存 `FileDeviceKeyStore` を使う。
7. 移行helperの分岐テストを書く。Keychain空+file有り+store成功、Keychain空+file有り+store失敗、Keychain有り+file有り、Keychain/fileとも空のケースを確認する。
8. macOS実Keychainテストは、service/accountにテスト専用suffixを付け、cleanupで `SecItemDelete` を行う `#[ignore]` テストにする。通常CIでは実Keychainへ触れない。
9. 必要ならpodspecへ `s.frameworks = 'Security'` または同等のlink指定を追加し、iOS/macOSのbuildを確認する。
10. 品質ゲートと手動確認を実行し、完了報告に結果を記録する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] iOS/macOS targetでは `init_core` がKeychain backed `DeviceKeyStore` を使い、`init_core` の公開シグネチャとDart呼び出しは変更されていない。
- [ ] Keychain itemはgeneric password、service `dev.todori.todori.device-key`、account `default`、`AfterFirstUnlockThisDeviceOnly` 相当で保存され、access groupを指定していない。
- [ ] DKが未保存ならKeychainへ新規生成・保存され、再起動後に同じDKからSQLCipher DBを再オープンできる。
- [ ] 既存 `<db_dir>/device.key` がある場合、Keychainへ移行後にファイル削除を試み、Keychain保存失敗時はファイルを残して旧経路でDB openできる。
- [ ] Keychainに既存DKがある場合はKeychainを正とし、残存ファイルDKがDB鍵選択に使われない。
- [ ] DK・SQLCipher導出鍵・Keychain dataバイト列がログ、Debug、Display、エラーメッセージ、完了報告へ出力されていない。
- [ ] Rust単体テストでKeychain/file移行分岐を検証し、実KeychainテストはmacOS限定の `#[ignore]` として扱い方を完了報告に記録している。
- [ ] Dart/widget統合テストは既存Fake継続で、DKをDart側へ渡すAPIが追加されていない。
- [ ] iOS Simulatorで `flutter run` 後、アプリ終了/再起動でデータが保持されDB openできることを手動確認し、機種・OS・device id・手順・結果を完了報告に記録している。
- [ ] macOS dogfooding buildで起動し、sandbox entitlements差異とKeychain動作結果を完了報告に記録している。

## 7. 制約・注意事項

- `todori/local-db-key/v1` は互換性に関わるため変更禁止である。SQLCipher鍵導出は引き続き `derive_local_db_key(&device_key)` のみを使う。
- `FileDeviceKeyStore` は移行fallbackおよび非Apple開発用として残してよいが、iOS/macOS本番経路の正にしてはならない。
- Keychain移行ではデータロス回避を最優先する。Keychain保存が確認できる前に `device.key` を削除してはならない。
- Keychain itemのaccessibilityは `AfterFirstUnlockThisDeviceOnly` 相当に固定する。iCloud同期・バックアップ・別端末復元に乗る属性を選ばない。
- Keychain access groupは使わない。必要になった場合は、実際のビルド/実行エラー、必要なentitlement差分、データ移行影響を完了報告の未解決事項に記録し、独断で共有group設計へ広げない。
- macOSはsandbox entitlementsがiOSと異なる。`app/macos/Runner/DebugProfile.entitlements` / `Release.entitlements` は必要最小限の変更にし、Keychain sharingを有効化しない。
- `.cargo/config.toml` の `IPHONEOS_DEPLOYMENT_TARGET=15.0` を変更しない。
- cargoパッケージ名、pod名、FRB stemの `todori_app_bridge` 一致制約を崩さない。
- Rust APIを公開変更した場合のみFRB再生成を行う。生成物は手編集しない。本タスクでは `init_core` のシグネチャ維持を前提とするため、原則FRB再生成は不要である。
- 新規依存を追加する場合は、workspace dependencyへ集約し、不要なネットワーク取得や非Apple targetへの不要な依存波及を避ける。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 採用した方式（Rust側Security framework呼び出し）と、Dart側Keychain方式を採らなかった理由
- 追加・変更したKeychain storeの公開/内部API
- Keychain item属性（class、service、account、accessibility、access group有無）
- `FileDeviceKeyStore` からの移行ロジックと失敗時fallback
- 追加・更新したRustテスト名、実Keychainテストの扱い、実行結果
- Dart/widget統合テストがFake継続であること、DKをDartへ渡すAPIを追加していないこと
- iOS Simulator手動確認の機種、OS、device id、手順、結果
- macOS dogfooding build/起動確認、entitlements差異、Keychain動作結果
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）
