# task-84: session非依存LocalCryptoContext

> ステータス: 完了（session非依存のaccount-bound local crypto復元を実装）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

task-83のtransactional task editは、再起動後にList DEKがRAMへ復元されないためfail closedする。remote sessionとlocal crypto availabilityを分離し、既存List配下の編集をofflineで継続できる基盤が必要である。

## 2. 事前に読むべきファイル

- `docs/05_設計判断記録.md` ADR-011〜ADR-013
- `docs/tasks/task-83-transactional-client-foundation.md`
- `app/rust/src/support.rs`
- `core/client/src/task_service.rs`
- `core/storage/src/lib.rs`
- `core/sync/src/account.rs`

## 3. ゴール

- MK-wrapped List DEK bundleをtenant/list単位でSQLCipherへ永続化する。
- login/register/key refresh後にcacheを更新する。
- session tokenや期限に依存せず、再起動後にlocal mutation contextを復元する。
- account-boundでcache欠落/破損時は匿名fallbackせずfail closedする。

## 4. スコープ

### やること

- storage schema v10とwrapped List DEK cache repository。
- cacheのreplace/loadとtenant分離テスト。
- account key materialからcache bundleを生成・検証する処理。
- bridge runtimeでsession restoreとlocal crypto restoreを分離する。
- task editのrestart/session-expiry/cache-corruptionテスト。
- 明示logout後もaccount bindingを維持し、anonymous mutationへ降格させない。

### やらないこと

- 残りCRUDのtransactional client移行。
- offline list作成とkey-bundle upload queue。
- protocol v2 field clock / placement。
- production 2-client server fixtureの全面置換。
- aggregate削除scope / epochとList DEK cache削除。

## 5. 実装手順

1. v10 migrationとtenant-scoped cache APIを追加する。
2. key materialをMK-wrapped cache bundleへ変換し、復元するpure処理を追加する。
3. auth/refresh成功時にcacheを更新する。
4. restart時にsessionとは独立してlocal mutation contextを復元する。
5. missing/corrupt/wrong-tenant/logout/expired-sessionを自動テストする。
6. 独立検証後に品質ゲートを実行する。

## 6. 受け入れ基準

- [x] DB schema v9からv10へtransactionalに移行する。
- [x] List DEK平文を永続化せず、MK-wrapped bundleだけを保存する。
- [x] cache lookupがtenant IDで分離される。
- [x] login/register/refreshで検証済みbundleが永続cacheへ反映される。
- [x] runtimeを破棄した再open後、session tokenなし/期限切れでもtask editがdomain+undo+HLC+outbox+record stateをatomic commitする。
- [x] cache欠落・破損・tenant不一致はtyped unavailableとなり、domain/sync stateを変更しない。
- [x] logout後にaccount-bound DBがAnonymousへ降格しない。
- [x] 既存workspace testとFlutter品質ゲートが成功する。
- [x] `git diff --check`が成功する。

## 7. 制約・注意事項

- secret、鍵平文、wrapped bundle内容をログ・error・完了報告へ出さない。
- network I/OをSQLite write transaction内で行わない。
- 部分的に復元できたList DEK集合をReadyとして公開しない。
- list削除でcache rowを削除しない。
- app/rustの`OnceLock`を2-client/restartテストfixtureの基盤にしない。pure処理とcore/clientをテストする。

## 8. 完了報告に含めるべき内容

- schema/cache APIとlocal crypto状態遷移。
- restart、期限切れ、欠落、破損、tenant分離のテスト結果。
- auth/refresh/logout経路の変更。
- 実行した品質ゲート。
- 残りCRUD、offline list作成、production 2-client fixtureへの後続事項。

## 9. 完了報告

- 作業日: 2026-07-10
- 結果: schema v10へtenant/user/deviceのprofile bindingとList DEK cacheを追加した。cache ciphertextはMKでwrapしlist IDをAADへ含める。register/login/refreshで全件検証後にtransactional replaceし、再起動・session期限切れ・logout後も既存Listのlocal mutationはsession非依存contextからoutboxを生成する。cache欠落/破損、別account、別tenant row、旧account stateの途中書込はAnonymousへ降格せずfail closedする。offline list作成はkey upload queue未実装のためrow作成前に明示失敗する。
- 証拠: `todori-client` 8 test、`todori-storage` 57 test成功/1件ignored、`todori-sync` 39 test、`todori-crypto` 29 test成功/1件ignored。`cargo test --workspace`（Docker/Testcontainers 5件を含む）、`cargo clippy --workspace -- -D warnings`、Rust release build、`flutter analyze`、`flutter test` 124件、hardcoded strings check、`git diff --check`成功。独立verifierでP1なしを確認した。
- Commit: 未コミット
- 未解決: v9既存accountはbindingを自動移行するが、旧schemaにList DEK cacheがないため次回loginでcacheを補完するまでfail closedする。残りCRUDの同一transaction移行、offline list作成用key-bundle upload queue、production 2-client fixture、bridge状態分岐の直接test、`LocalSyncKeys` drop時zeroizeは後続。protocol v2 field clock / placementとcascade deleteも未実装。
