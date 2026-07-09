# task-83: production同期テストとtransactional client基盤

> ステータス: 完了（task editのtransactional common-client vertical sliceを実装）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

ADR-012は、domain row、outbox、sync record state、local HLCを同一SQLite transactionで確定することを同期correctnessの最初の依存とした。現行Flutter bridgeはdomain repositoryのcommit後に別connectionの`BridgeSyncStore`を呼び、HLC、outbox、record stateも個別commitするため、途中失敗でlocal-only変更を作る。

既存2-client testはproduction CRUD / enqueueを通らず、変更fieldだけへHLCを付ける独自clientを使うため、この欠陥を検出できない。本タスクでは共通`core/client`の最初のvertical sliceとしてtask editを移し、失敗注入でtransaction原子性を証明する。

## 2. 事前に読むべきファイル

- `docs/05_設計判断記録.md` ADR-011、ADR-012
- `docs/tasks/task-82-sync-correctness-redesign.md`
- `app/rust/src/api.rs`
- `app/rust/src/support.rs`
- `app/rust/src/sync_store.rs`
- `core/storage/src/lib.rs`
- `core/sync/src/enqueue.rs`
- `server/tests/sync_server.rs`

## 3. ゴール

- `core/storage`へ`BEGIN IMMEDIATE`のwrite unit-of-workを追加する。
- `core/client` crateを追加し、task edit + undo snapshot + HLC + outbox + record stateを1 transactionでcommitするproduction入口を作る。
- Flutter bridgeの`update_task`を共通client入口へ移す。
- outboxまたはrecord-state書込失敗時に全変更がrollbackされる自動テストを追加する。
- connection `busy_timeout`を共通設定する。

## 4. スコープ

### やること

- workspaceへ`todori-client`を追加する。
- enqueueに必要なstore traitをpull/apply storeから分離する。
- storage write transactionへtask read/update-with-undo、setting、outbox、record-state操作を追加する。
- task editのdomain処理とsync enqueueを`todori-client`へ置く。
- active accountのlocal crypto contextがある場合にFlutter `update_task`から新入口を使用する。
- transaction failure injection testと成功testを追加する。

### やらないこと

- protocol v2 clock / placement実装。
- create/list/delete/reorder/status/undoをすべて移行すること。
- remote sessionとlocal key cacheの完全分離。
- pull page/cursor transaction、full resync、aggregate delete。
- FRB公開signatureの変更。

## 5. 実装手順

1. `LocalMutationSyncStore`を抽出する。
2. storageへimmediate write transactionと必要なtransaction-scoped操作を追加する。
3. `core/client`へtask edit application serviceとtransaction-backed sync storeを実装する。
4. outbox/record-state failure triggerを使うrollback testを先に通す。
5. Flutter bridgeの`update_task`を共通clientへ委譲する。
6. fmt、clippy、workspace test、Flutter側品質ゲートを実行する。

## 6. 受け入れ基準

- [x] `core/client`がworkspace memberであり、Flutter / CLIから依存可能である。
- [x] write unit-of-workが`TransactionBehavior::Immediate`を使う。
- [x] connectionに有限の`busy_timeout`が設定される。
- [x] task、undo、local HLC、outbox、record stateが同一transactionでcommitされる。
- [x] outbox INSERT失敗で5状態すべてが旧状態へrollbackされる。
- [x] record state UPSERT失敗でもdomain/outbox/HLCがrollbackされる。
- [x] 成功時はtask、undo、HLC、outbox、record stateがすべて存在する。
- [x] Flutter `update_task`の公開signatureとDTO結果が維持される。
- [x] 既存workspace testとFlutter品質ゲートが成功する。
- [x] `git diff --check`が成功する。

## 7. 制約・注意事項

- transaction中にHTTPやkey refreshを行わない。
- account-bound profileでlocal keyがない場合はdomain更新前に明示errorとし、匿名profileのlocal-only fallbackと区別する。
- repository内のnested transactionを作らない。
- 本タスクでは現行protocol v1 payloadを維持し、field clock問題は後続taskで直す。
- public FRB APIを変更しないため生成物差分は原則不要だが、規約に従いcodegen差分有無を確認する。

## 8. 完了報告に含めるべき内容

- 追加したunit-of-workと共通client API。
- failure injectionごとのrollback結果。
- Flutter bridge移行範囲。
- 実行した品質ゲート。
- 未移行CRUD、local key cache、protocol v2への後続事項。

## 9. 完了報告

- 作業日: 2026-07-10
- 結果: `todori-client`と`SqliteWriteTx`を追加し、account-boundかつlocal key利用可能時のFlutter `update_task`を、task、undo、local HLC、outbox、record stateの同一`BEGIN IMMEDIATE` transactionへ移した。匿名profileだけは従来のlocal-only経路を維持し、account-boundでkey利用不能な状態はdomain-only commitせず明示errorにした。
- 証拠: `todori-client` 4 test成功（success、outbox失敗rollback、既存record-state更新失敗rollback、missing List DEK rollback）。`cargo test --workspace`成功（Docker/Testcontainers 5件を含む）。`cargo clippy --workspace -- -D warnings`、`flutter analyze`、`flutter test` 124件、hardcoded strings check、FRB codegen、`git diff --check`成功。
- Commit: 未コミット
- 未解決: vertical sliceは`update_task`だけで、production 2-client test、残りCRUD/Undo、session非依存`LocalCryptoContext`とList DEK local cacheは後続。再起動後にDEK未復元の場合はsilent commitせず編集を失敗させるため、offline-first要件は未達。protocol v2 field clock / placementも後続。
