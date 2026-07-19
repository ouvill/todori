# Code Signing Setup for Apple Keychain Development

> Last updated: 2026-07-09

Taskveil uses the Apple Data Protection Keychain on iOS and macOS for the Device Key and account secrets. Signed Apple builds should use the app's `keychain-access-groups` entitlement so normal app launch does not show a Keychain password prompt.

This document is for local development signing. The repository-wide Apple Team ID is fixed to `4DQWW3VH88` for the iOS and macOS Runner targets. Do not commit Apple IDs, certificates, private keys, or provisioning profile identifiers to the repository.

## 1. Register a Personal Team

1. Open Xcode.
2. Open Xcode Settings.
3. Select Accounts.
4. Add your Apple ID.
5. Select the Apple ID and confirm that a Personal Team is listed.

A free Personal Team can sign local development builds for testing on your own devices. App Store submission, TestFlight distribution, and production distribution require the paid Apple Developer Program.

## 2. Confirm the Team ID

The configured Team ID is:

```text
4DQWW3VH88
```

Confirm the value in Xcode Accounts by selecting the team and inspecting its Team ID. You can also confirm it at `developer.apple.com/account` after signing in with the Apple Developer account.

## 3. Repository Signing Settings

The iOS and macOS `Runner` targets are already configured for all build configurations:

```text
DEVELOPMENT_TEAM = 4DQWW3VH88
CODE_SIGN_STYLE = Automatic
```

If Xcode asks you to resolve signing locally, keep the same Team ID:

1. Open `app/ios/Runner.xcworkspace` or `app/macos/Runner.xcworkspace`.
2. Select the `Runner` target.
3. Open Signing & Capabilities.
4. Select the team whose Team ID is `4DQWW3VH88`.
5. Confirm that the bundle identifier remains `com.taskveil.app`.
6. Build and run from Xcode or Flutter.

## 4. Entitlement Used by Taskveil

The tracked entitlements use this keychain access group:

```text
$(AppIdentifierPrefix)com.taskveil.app
```

At signing time, `$(AppIdentifierPrefix)` is expanded to the selected Team ID prefix. The signed app then has a concrete keychain group such as:

```text
<TEAMID>.com.taskveil.app
```

The Rust Keychain store reads the signed app's `keychain-access-groups` entitlement at runtime and passes that concrete value to `kSecAttrAccessGroup`.

## 5. Why This Removes Prompts

The normal path is:

1. The app is signed with `keychain-access-groups`.
2. The Rust store reads the signed access group entitlement.
3. The Keychain query uses Data Protection Keychain with `kSecUseDataProtectionKeychain`.
4. The item is scoped to the app's access group via `kSecAttrAccessGroup`.
5. The item keeps `AfterFirstUnlockThisDeviceOnly` accessibility.

With a stable signing identity and access group, macOS does not need the legacy login keychain ACL prompt on each rebuilt debug app. Unsigned or entitlement-less macOS builds can still fall back to the legacy path, but that path is only a development rescue path.

## 6. Verification Checklist

After setting a local Team ID:

1. Build the macOS app in debug mode.
2. Launch Taskveil and confirm no Keychain prompt appears on normal startup.
3. Quit and relaunch the app.
4. Rebuild and relaunch with the same Team selected.
5. Confirm no Keychain prompt appears and existing encrypted local data opens.
6. Repeat equivalent launch/relaunch checks on iOS Simulator or a development device when available.

If prompts still appear, confirm that the built app is signed with `keychain-access-groups` and that the access group contains the selected Team ID prefix plus `com.taskveil.app`.

## 7. App Store Note

Personal Team signing is enough for local development only. App Store submission, TestFlight, production provisioning profiles, and distribution certificates require enrollment in the paid Apple Developer Program.

## 8. トラブルシューティング（2026-07-09 実録）

### 1. 証明書はあるのに `security find-identity -v -p codesigning` が「0 valid identities」

- 原因: Keychain に入っている Apple WWDR 中間証明書が旧世代（2023-02-07 期限切れ）のみで、証明書の発行元である WWDR G3 が無い。チェーン検証が組めず identity が invalid 扱いになる。
- 解決:
  ```
  curl -fsSL -o /tmp/AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
  security add-certificates -k ~/Library/Keychains/login.keychain-db /tmp/AppleWWDRCAG3.cer
  ```
  直後に `security find-identity -v -p codesigning` で valid になることを確認。

### 2. ビルドが「"Runner" has entitlements that require signing with a development certificate」で失敗

- 原因: Flutter の macOS テンプレートはプロジェクトレベルに `CODE_SIGN_IDENTITY = "-"`（adhoc）を持つ。ターゲットレベルで `DEVELOPMENT_TEAM` と `CODE_SIGN_STYLE = Automatic` を設定しても、この "-" が継承されて adhoc のままになる。
- 解決: Runner ターゲットの Debug/Release/Profile 各 buildSettings に `CODE_SIGN_IDENTITY = "Apple Development";` を追加してターゲットレベルで上書き（project.pbxproj 設定済み）。プロジェクトレベルの "-" と Flutter Assemble ターゲットは変更不要。

### 3. ビルド中にパスワードダイアログが連打される / `errSecInternalComponent` で署名失敗

- 原因: 署名用秘密鍵がまだ codesign を信頼していないため、フレームワーク1個の署名ごとに鍵アクセス許可ダイアログが出る。放置・キャンセルすると errSecInternalComponent で失敗する。
- 解決: ダイアログが出たらログインパスワードを入力して「常に許可」（Always Allow）を選ぶ。1回で以後のビルドは無音になる。「許可」だと毎回聞かれるので注意。
  - ダイアログを見ずに済ませたい場合の代替（パスワードは本人が直接入力）:
    ```
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <ログインパスワード> ~/Library/Keychains/login.keychain-db
    ```

### 4. 署名ビルド後の初回起動について

- 署名済みビルドは Data Protection Keychain（access group: com.taskveil.app）を使う。旧 adhoc ビルドが legacy Keychain に保存したデバイスキーとは領域が別のため、初回起動時は新規デバイスキー生成となりローカルデータは初期状態になる。
- 起動確認は 2 回行い、Keychain プロンプトが一切出ないことをもって完了とする（task-77 の受け入れ基準）。
