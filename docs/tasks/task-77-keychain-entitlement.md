# task-77: Data Protection Keychainとエンタイトルメントによるゼロプロンプト化

> ステータス: 完了（Keychain entitlementゼロプロンプト化）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

task-64と直近修正で、iOS/macOSのDevice Keyとaccount secretはApple Keychain backed storeへ移行した。macOSではData Protection Keychainを先に試し、`errSecMissingEntitlement (-34018)` の場合のみlegacy login keychain + ACLへフォールバックしている。

この暫定フォールバックは未署名・entitlementなしの開発ビルド救済としては有効だが、adhoc署名のdebugビルドではリビルドのたびにKeychainプロンプトが出る。`docs/design/ui-spec.md` の「起動時の無音原則」に従い、通常のアプリ起動ではOSの権限確認・パスワード入力を出してはならない。

本タスクでは、Chrome/Signalと同じく「署名済みアプリ + keychain-access-groups entitlement + Data Protection Keychain」を正規経路にし、macOS/iOSの通常起動をゼロプロンプトへ寄せる。legacy login keychain + ACLは、未署名・entitlementなしのローカル開発ビルド救済としてのみ残す。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` の「起動時の無音原則」
- `docs/tasks/task-64-keychain-device-key.md`
- `core/crypto/src/dev_key_store.rs`
- `app/macos/Runner/DebugProfile.entitlements`
- `app/macos/Runner/Release.entitlements`
- `app/macos/Runner.xcodeproj/project.pbxproj`
- `app/ios/Runner/`
- `app/ios/Runner.xcodeproj/project.pbxproj`

## 3. ゴール

- macOS/iOS Runner targetに `keychain-access-groups` entitlementを追加し、署名済みビルドがData Protection Keychainをプロンプトなしで使えるようにする。
- Rust Keychain storeで、Data Protection Keychainのqueryに実行中アプリのaccess groupを指定する。
- Device Key、session token、local wrapped Master Keyのすべてで同じData Protection Keychain正規経路を使う。
- macOS legacy login keychain + ACLは、`-34018` などentitlementなし/未署名ビルドのフォールバックとして残す。
- Team未設定の状態でもリポジトリのビルド設定を壊さず、実Team ID設定後の署名付き検証手順を文書化する。

## 4. スコープ

### やること

- `app/macos/Runner/DebugProfile.entitlements` と `Release.entitlements` に `keychain-access-groups = $(AppIdentifierPrefix)com.taskveil.app` を追加する。
- `app/ios/Runner/Runner.entitlements` がなければ作成し、Runner targetのDebug/Profile/Releaseへ配線する。
- `core/crypto/src/dev_key_store.rs` でData Protection Keychain queryに `kSecAttrAccessGroup` を指定する。
- access groupは署名時に展開されたentitlementから実行時に取得し、Personal Team/有料Teamのどちらでも同じ設定で動くようにする。
- legacy login keychain + ACL経路に、正規経路ではなく開発ビルド救済である旨のコメントを追加する。
- `docs/dev/code-signing-setup.md` を作成し、Personal Team登録、Team ID確認、`DEVELOPMENT_TEAM` 設定、ゼロプロンプトの仕組み、App Store提出時の有料プログラム要件を記載する。
- README、`docs/tasks/README.md`、`docs/tasks/BACKLOG.md` を更新する。
- 品質ゲートを実行し、結果を完了報告へ記録する。

### やらないこと

- git commit。
- `DEVELOPMENT_TEAM` の実値をリポジトリへコミットすること。
- 実Apple ID、Team ID、証明書、プロビジョニングプロファイル、private情報の記載。
- Keychain itemのservice/account名変更。
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` の変更。
- Device Keyやaccount secretのログ出力。
- Android Keystore、Windows/Linux Secret Service対応。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` の変更。

## 5. 実装手順（例）

1. 対象ファイルと既存Keychain fallbackを読む。
2. macOS entitlementsに `keychain-access-groups` を追加する。`com.apple.security.app-sandbox` は維持する。
3. iOS `Runner.entitlements` を作成し、`Runner.xcodeproj/project.pbxproj` のRunner target Debug/Profile/Releaseへ `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;` を追加する。
4. `core/crypto/src/dev_key_store.rs` で実行中アプリの `keychain-access-groups` entitlementを読み取り、Data Protection Keychainの `PasswordOptions` に `set_access_group` で指定する。
5. macOS legacy fallbackは `errSecMissingEntitlement (-34018)` の場合だけ使い、コメントで未署名/entitlementなし開発ビルド救済と明記する。
6. `docs/dev/code-signing-setup.md` を作成する。
7. README、`docs/tasks/README.md`、`docs/tasks/BACKLOG.md` を更新する。
8. 品質ゲートを実行し、実行不能なものは環境要因とコマンドを完了報告に記録する。
9. 本指示書の末尾に `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

共通受け入れ基準は `docs/tasks/README.md` の「共通受け入れ基準」を満たすこと。

- [x] macOS Debug/Profile/Release用entitlementsに `keychain-access-groups` があり、値が `$(AppIdentifierPrefix)com.taskveil.app` で、app sandboxが維持されている。
- [x] iOS Runner targetに `Runner.entitlements` が配線され、同じ `keychain-access-groups` 値を持つ。
- [x] Device Keyとaccount secretのData Protection Keychain queryが `kSecUseDataProtectionKeychain`、`kSecAttrAccessGroup`、`AfterFirstUnlockThisDeviceOnly` 相当を使う。
- [x] macOS legacy login keychain + ACLは `-34018` などentitlementなし/未署名時のフォールバックとして残り、正規経路ではない旨がコードコメントで分かる。
- [x] `DEVELOPMENT_TEAM` の実値や秘密情報がコミット対象へ入っていない。
- [x] `docs/dev/code-signing-setup.md` にPersonal Team設定、Team ID確認、ゼロプロンプトの仕組み、App Store提出時の有料プログラム要件が書かれている。
- [x] 証拠として、entitlements/project設定をgrepまたは差分で確認し、品質ゲート結果と合わせて完了報告に記録している。
- [x] 完了報告に「親ホストでの署名付きビルド検証は人間がTeam ID設定後に実施」と明記している。

## 7. 制約・注意事項

- `$(AppIdentifierPrefix)` は署名時にTeam ID prefixへ展開される。Rustコードへ固定Team IDを埋め込まない。
- Team未設定でもプロジェクト設定を壊さない。`DEVELOPMENT_TEAM` は空のまま維持し、人間がローカルで設定する。
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 相当は維持する。iCloud同期や別端末復元に乗る属性を選ばない。
- legacy fallbackは秘密情報をログへ出してはならない。出力する場合もエラーコードや経路名だけにする。
- `app/macos/Runner/DebugProfile.entitlements` の `com.apple.security.network.server` と `com.apple.security.cs.allow-jit` は既存debug/profile用途として維持する。
- `app/macos/Runner/Release.entitlements` のapp sandboxは維持する。
- `docs/03_技術仕様書.md` は本タスクでは変更しない。仕様矛盾が見つかった場合は完了報告の未解決事項へ記録する。

## 8. 完了報告に含めるべき内容

- 作業日。
- 変更ファイル一覧。
- 追加したentitlementとaccess group値。
- Data Protection Keychain正規経路の実装要点。
- legacy fallback条件。
- 署名手順ドキュメントの要点。
- 実行した検証コマンドと結果。
- 親ホストでの署名付きビルド検証は人間がTeam ID設定後に実施する旨。
- 未解決事項。ない場合は「なし」と明記する。

## 9. 完了報告

作業日: 2026-07-08

### 変更ファイル

- `core/crypto/Cargo.toml`
- `core/crypto/src/dev_key_store.rs`
- `app/macos/Runner/DebugProfile.entitlements`
- `app/macos/Runner/Release.entitlements`
- `app/ios/Runner/Runner.entitlements`
- `app/ios/Runner.xcodeproj/project.pbxproj`
- `docs/dev/code-signing-setup.md`
- `docs/tasks/task-77-keychain-entitlement.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `README.md`

### 実装結果

- macOS Debug/Profile/Release用entitlementsに `keychain-access-groups` を追加した。値は `$(AppIdentifierPrefix)com.taskveil.app`。`com.apple.security.app-sandbox` はDebugProfile/Releaseとも維持した。
- iOS `app/ios/Runner/Runner.entitlements` を作成し、Runner targetのDebug/Profile/Releaseへ `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;` を配線した。値はmacOSと同じ `$(AppIdentifierPrefix)com.taskveil.app`。
- `core/crypto/src/dev_key_store.rs` で実行中アプリの `keychain-access-groups` entitlementを `SecTaskCopyValueForEntitlement` で読み取り、Data Protection Keychainの `PasswordOptions::set_access_group` に渡すようにした。
- Device Key storeとaccount secret storeの両方に同じaccess group指定を適用した。
- Data Protection Keychain経路は既存どおり `use_protected_keychain()` と `AccessibleAfterFirstUnlockThisDeviceOnly` 相当を維持した。
- macOS legacy login keychain + ACL経路は、`errSecMissingEntitlement (-34018)` などentitlementなし/未署名ビルドのフォールバックとして残し、正規経路はData Protection Keychainである旨をコードコメントへ記録した。
- `DEVELOPMENT_TEAM` は設定していない。`grep -R "DEVELOPMENT_TEAM"` で対象project/Runner配下に実値混入なしを確認した。
- `docs/dev/code-signing-setup.md` を作成し、Personal Team登録、Team ID確認、Runner targetへのTeam設定、`$(AppIdentifierPrefix)` 展開、ゼロプロンプトになる仕組み、App Store提出時は有料Apple Developer Programが必要な点を記録した。

### エンタイトルメントとaccess group値

- entitlement key: `keychain-access-groups`
- tracked value: `$(AppIdentifierPrefix)com.taskveil.app`
- runtime Keychain access group: 署名済みアプリのentitlementから取得した `<TEAMID>.com.taskveil.app`

### フォールバック条件

- 正規経路: 署名済みiOS/macOSアプリのData Protection Keychain + `kSecAttrAccessGroup`。
- macOS fallback: Data Protection Keychain操作が `errSecMissingEntitlement (-34018)` になった場合のみ、legacy login keychain + ACLへフォールバックする。
- Flutter test processは既存どおりfile storeを使い、実Keychainへ触れない。

### 検証結果

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test -p taskveil-crypto`: 成功。28 passed / 1 ignored。実Keychain ignored testの扱いは従来どおり。
- `cargo test --workspace`: 成功。実Keychain ignored testと性能ignored testは従来どおり。
- `cd app && flutter analyze`: 成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test`: 成功。123 passed / 1 skipped。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `plutil -lint app/macos/Runner/DebugProfile.entitlements app/macos/Runner/Release.entitlements app/ios/Runner/Runner.entitlements`: 成功。
- `grep -R "DEVELOPMENT_TEAM" -n app/ios/Runner.xcodeproj app/macos/Runner.xcodeproj app/ios/Runner app/macos/Runner`: 出力なし。
- `grep -R "keychain-access-groups\\|CODE_SIGN_ENTITLEMENTS\\|set_access_group\\|SecTaskCopyValueForEntitlement" -n app/ios/Runner app/ios/Runner.xcodeproj app/macos/Runner core/crypto/src/dev_key_store.rs`: iOS/macOS entitlements、iOS project配線、Rust access group指定を確認。
- `git diff --check`: 成功。

### 未解決事項

- 親ホストでの署名付きビルド検証は人間がTeam ID設定後に実施する。

### 2026-07-09 追補: Team ID確定後の署名設定

プロダクトオーナー確定のApple Team ID `4DQWW3VH88` を、iOS/macOS `Runner` targetのDebug/Profile/Releaseへ設定した。task-77当初の「`DEVELOPMENT_TEAM` は未設定で維持」は、Team ID確定前の前提であり、本追補で置き換えた。

#### 追補変更ファイル

- `app/macos/Runner.xcodeproj/project.pbxproj`
- `app/ios/Runner.xcodeproj/project.pbxproj`
- `docs/dev/code-signing-setup.md`
- `docs/tasks/task-77-keychain-entitlement.md`

#### 設定方式

- xcconfigではなく、各 `project.pbxproj` の既存Runner target buildSettingsブロックへ直接追記した。
- macOS Runner target Debug/Profile/Release:
  - `DEVELOPMENT_TEAM = 4DQWW3VH88`
  - `CODE_SIGN_STYLE = Automatic`（既存値を維持）
- iOS Runner target Debug/Profile/Release:
  - `DEVELOPMENT_TEAM = 4DQWW3VH88`
  - `CODE_SIGN_STYLE = Automatic`
- RunnerTests targetとproject-level build settingsにはTeam IDを追加していない。

#### 署名ドキュメント

- `docs/dev/code-signing-setup.md` に確定Team ID `4DQWW3VH88` と、iOS/macOS Runner targetへ設定済みである旨を追記した。
- Team ID確認先として、Xcode Accountsに加えて `developer.apple.com/account` を追記した。

#### 追補検証結果

- `flutter build macos --debug`: 失敗。XcodeのSwift Package Manager依存解決が、sandbox外の `/Users/youhei/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/fluttergeneratedpluginswiftpackage.dia` へdiagnosticsを書き込めず `Operation not permitted`。同時にCoreSimulatorService接続無効のログも出た。署名エラーには到達していない。
- `env HOME=/private/tmp/taskveil-build-home PUB_CACHE=/Users/youhei/.pub-cache flutter build macos --debug`: 同じSwiftPM diagnostics書き込みエラーで失敗。Xcodeは実ユーザーの `~/Library/Caches/org.swift.swiftpm` を使い続けた。
- `flutter build ios --simulator --debug`: 失敗。macOS buildと同じくSwiftPM依存解決中に `/Users/youhei/Library/Caches/org.swift.swiftpm/...` への書き込みが `Operation not permitted`。署名エラーには到達していない。
- `cargo test -p taskveil-crypto`: 成功。28 passed / 1 ignored。
- `cd app && flutter analyze`: 成功。
- `cd app && flutter test`: 成功。123 passed / 1 skipped。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git diff --check`: 成功。
- `plutil -lint app/ios/Runner.xcodeproj/project.pbxproj app/macos/Runner.xcodeproj/project.pbxproj app/ios/Runner/Runner.entitlements app/macos/Runner/DebugProfile.entitlements app/macos/Runner/Release.entitlements`: 成功。

#### 未解決事項

- Codex sandboxではXcode/SwiftPMがユーザーLibrary配下へ書けず、macOS/iOSのFlutter buildは署名検証前に停止した。親ホストの非sandbox環境で `cd app && flutter build macos --debug` と `cd app && flutter build ios --simulator --debug` を再実行し、署名付きビルド成功とKeychainプロンプト有無を確認する。

### 最終追補（2026-07-09 macOS署名付き検証完了）

親ホストで署名付きmacOSビルドと起動時ゼロプロンプトを検証し、受け入れ基準を満たした。

#### 検証前に解決した障害

詳細は `docs/dev/code-signing-setup.md` セクション8を参照。

1. Keychain内のWWDR中間証明書が旧世代（期限切れ）のみで開発証明書がinvalid扱いになった。WWDR G3を追加インストールして解決した。
2. Flutter macOSテンプレートのproject-level `CODE_SIGN_IDENTITY = "-"` がadhoc署名を強制していた。macOS Runner targetのDebug/Profile/Releaseに `CODE_SIGN_IDENTITY = "Apple Development"` を追加し、`app/macos/Runner.xcodeproj/project.pbxproj` で上書きして解決した。
3. 署名秘密鍵が未信頼で、フレームワーク署名ごとにKeychain許可ダイアログが出て `errSecInternalComponent` で失敗した。鍵アクセスを「常に許可」にして解決した。

#### legacy Keychainアイテムの整理

旧adhocビルドが残したlegacy Keychainアイテム（`com.taskveil.app.device-key` など）が、新署名バイナリからのアクセス時にパスワード確認を誘発した。そのためlegacyアイテムと `~/Library/Containers/com.taskveil.app` を削除し、クリーン状態から再検証した。

#### 最終検証結果

- プロダクトオーナー実機確認日: 2026-07-09。
- `flutter build macos --debug`: 成功。
- アプリを2回起動し、Keychainパスワード確認・許可ダイアログは一切出なかった。
- macOS署名付きビルドのゼロプロンプト受け入れ基準をクリアした。

#### 残る未検証

- iOS Simulator/実機でのゼロプロンプト確認は、帰還後リストで継続する。
