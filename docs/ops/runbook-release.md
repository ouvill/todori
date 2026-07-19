# クライアントリリースrunbook

Taskveilクライアントのリリース手順の骨子を定義する。2026-07-15時点ではpre-releaseであり、最初の一般リリースは課金基盤完成後まで延期している。ストア提出、署名、Developer Program、公開告知、公開不可の判断事項は人間作業である。詳細な事業運用、価格、実証明書情報はpublic repoに書かない。

## 1. 対象

- iOS / macOSを先行対象とする。
- Android / Windows / Linuxはマルチプラットフォーム検証の結果に応じて後続で扱う。
- Phase 1 M5（リリース準備）とBilling foundation release gateに連動する。

## 2. リリース前ゲート

最初にBilling foundation release gate work itemが`done`で、独立検証とiOS sandbox E2Eが合格していることを確認する。少なくとも購入、購入復元、server-side receipt / event検証、冪等なentitlement集約、同期APIのrequest-time認可、失効・返金・再有効化が成立していなければリリース候補を作らない。

共通ゲート:

```sh
cargo fmt --all -- --check
cargo clippy --workspace -- -D warnings
cargo test --workspace
cd app && flutter analyze
cd app/rust && env CARGO_TARGET_DIR=target cargo build --release
cd app && flutter test
sh app/tool/check_hardcoded_strings.sh
git diff --check
```

UI変更を含む場合:

```sh
app/tool/visual_qa.sh
```

同期を含む場合:

```sh
./tool/dev_server.sh
```

その後、[`docs/dev/two-device-sync-test.md`](../dev/two-device-sync-test.md) の2台同期確認を行う。

## 3. リリース候補作成

1. `docs/tasks/STATUS.md`、`docs/tasks/work-*.md`、`docs/tasks/BACKLOG.md` の人間作業を確認する。
2. `docs/tasks/work-*.md` と `docs/tasks/task-*.md` の未解決事項にリリースブロッカーがないか確認する。
3. `SECURITY.md` の対象範囲に関わる未対応脆弱性がないか確認する。
4. バージョン番号とタグ名を人間が決める。

タグ例:

```sh
git tag -a v<MAJOR>.<MINOR>.<PATCH> -m "Taskveil v<MAJOR>.<MINOR>.<PATCH>"
```

実際のtag作成とpushは人間判断で行う。

## 4. ビルド

iOS release buildは署名、証明書、Provisioning Profile、App Store Connect設定を必要とする。これらの実値はprivate側または人間管理とする。

例:

```sh
cd app
flutter build ios --release
```

macOS:

```sh
cd app
flutter build macos --release
```

task-74後にmacOS署名付きbuildとKeychainゼロプロンプト、iOS Simulator build / install / launch、production UI起動を確認済みである。リリース候補では履歴上の成功を流用せず、現在のtoolchainと署名設定でiOS release buildを再実行し、iOS実機でKeychain、通知、購入・復元、同期を通し確認する。

## 5. ストア提出

ストア提出は人間作業である。public repoには次の実値を書かない。

- Apple Developer ProgramのTeam ID、証明書、Provisioning Profile。
- App Store Connectの実アプリID、スクリーンショット審査情報、審査メモ。
- 価格、商品ID、trial、launch offer、レシート検証の実運用詳細。
- 法務文書の未公開詳細。

提出前に確認する項目:

- E2EEの説明が実装と一致している。
- サーバーはユーザーデータを復号できない前提が崩れていない。
- Recovery Key、Device Key、Master Key、DEKをログへ出していない。
- クラッシュレポートを送る場合はF-53のオプトイン、PII除去対象、人間判断が完了している。
- ローカル通知権限、Keychain、SQLCipher DB open、同期の主要導線を実機で確認している。
- App Store sandboxの購入・復元と、server-side entitlement、失効・再有効化を確認している。
- 課金provider、product、価格、trial / grace、launch offer、税務・法務、secret運用の人間確認が完了している。

## 6. リリース後確認

- 新規インストールでローカルDBが作成される。
- アプリ再起動後もSQLCipher DBを開ける。
- 旧バージョンからの `PRAGMA user_version` migrationが成功する。
- 新DBを旧アプリで開かない方針が維持される。
- ローカル通知、登録/ログイン、2台同期が確認できる。
- 購入・復元後のentitlementと同期認可が一致し、失効時もlocal-only機能が継続する。
- 障害時にローカル編集が継続できる。

## 7. 差し戻し

クライアントリリースはDB migrationを伴う場合があるため、単純な旧バージョン配布で戻せるとは限らない。新しいDBを旧アプリが開けない場合は仕様通り `UnsupportedSchemaVersion` になる。

差し戻しが必要な場合は、DBを戻すのではなく、修正版を前方互換で出すことを基本にする。ストアでの公開停止、段階配信停止、緊急審査依頼は人間判断とする。
