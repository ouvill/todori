# task-78 sync initial backfill

> ステータス: 完了（2026-07-10）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

実機確認で、ログイン前から存在するローカルタスクが `sync_outbox` に登録されず、`sync_now` 成功後もサーバーへpushされない問題が見つかった。ローカルCRUD時だけoutboxへ登録する設計では、未ログイン期間に作られた既存データを初回同期で送信できない。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` §6
- `core/sync/src/enqueue.rs`
- `core/sync/src/apply.rs`
- `app/rust/src/support.rs`
- `app/rust/src/sync_store.rs`

## 3. ゴール

- 初回同期前に既存ローカルリスト/タスクを `sync_outbox` へ一括登録する。
- 登録/ログイン成功時に初回バックフィル状態をリセットし、アカウント切り替え後も再バックフィルできるようにする。
- 100件を超えるoutboxを1回の `sync_now` でpushしきれるようにする。

## 4. スコープ

- やること: `core/sync` へのバックフィル関数追加、bridge側トリガー、pushバッチドレイン、同期仕様/BACKLOG更新。
- やらないこと: FRB公開API変更、サーバーAPI変更、Inbox重複マージ方針の裁定。

## 5. 実装手順

1. `LocalSyncStore` / `SyncStateRepository` へoutbox存在確認とcursor削除を追加する。
2. `enqueue_backfill` を追加し、リスト→タスク順、タスク `created_at` 昇順、既存outbox/DEK欠落スキップを実装する。
3. `sync_now` 実行前に `initial_backfill` cursorを見て、未設定なら全リスト/全タスクをバックフィルする。
4. `run_sync_now` のpushを最大100イテレーションのバッチドレインにする。
5. 仕様書とBACKLOGを更新する。

## 6. 受け入れ基準

- [x] バックフィルでリストがタスクより先にenqueueされる。
- [x] outboxに既に行があるレコードはスキップされる。
- [x] タスクが `created_at` 昇順でenqueueされる。
- [x] DEK欠落リストのレコードはスキップされ、他は処理される。
- [x] `cargo test -p taskveil-sync` が成功する。
- [x] `cargo build -p taskveil_app_bridge` が成功する。
- [x] `cargo clippy -p taskveil_app_bridge -p taskveil-sync -- -D warnings` が成功する。
- [x] `cargo fmt --all -- --check` が成功する。

## 7. 制約・注意事項

- `app/rust/src/api.rs` のFRB公開APIシグネチャは変更しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` は変更しない。
- gitコマンドは使用しない。

## 8. 完了報告に含めるべき内容

- 変更ファイル一覧
- 検証結果
- `run_sync_now` のpushループ部分の最終コード
- 未解決事項

## 9. 完了報告

### 作業日

2026-07-10

### 実装結果

- `core/sync::enqueue_backfill` を追加し、既存の `enqueue_list_sync` / `enqueue_task_sync` を再利用して暗号化・HLC採番・record state保存を統一した。
- `initial_backfill` cursorを `sync_cursors` に保存し、未設定時だけ `sync_now` の前にバックフィルするようにした。
- 登録/ログイン成功時に `initial_backfill` cursorを削除するようにした。
- `run_sync_now` のpushを100件ずつ最大100回ドレインするようにした。
- `docs/03_技術仕様書.md` に初回バックフィル仕様を追記した。
- `docs/tasks/BACKLOG.md` にデバイス行重複排除とInbox重複解消を追記し、Inbox重複は要人間判断にも追加した。

### 変更ファイル一覧

- `core/storage/src/lib.rs`
- `core/sync/src/apply.rs`
- `core/sync/src/enqueue.rs`
- `core/sync/src/lib.rs`
- `app/rust/src/support.rs`
- `app/rust/src/sync_store.rs`
- `docs/03_技術仕様書.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/README.md`
- `docs/tasks/task-78-sync-initial-backfill.md`

### 検証結果

- `cargo test -p taskveil-sync`: 成功。33 passed。
- `cargo test -p taskveil-storage`: 成功。48 passed / 1 ignored。
- `cargo build -p taskveil_app_bridge`: 成功。
- `cargo clippy -p taskveil_app_bridge -p taskveil-sync -- -D warnings`: 成功。
- `cargo fmt --all -- --check`: 成功。

### run_sync_now pushループ最終コード

```rust
for _ in 0..MAX_PUSH_DRAIN_ITERATIONS {
    let outbox = store.list_outbox(PUSH_BATCH_LIMIT)?;
    if outbox.is_empty() {
        break;
    }
    summary.pushed_count += outbox.len();
    let push_ops = outbox
        .into_iter()
        .map(|entry| PushOp {
            outbox_id: entry.id,
            record_id: entry.record_id,
            collection: entry.collection,
            hlc: entry.hlc,
            deleted: entry.deleted,
            blob: entry.blob,
        })
        .collect::<Vec<_>>();
    let push_outcome = engine
        .push_batch(push_ops)
        .await
        .map_err(|_| "sync failed".to_string())?;
    for outcome in push_outcome.outcomes {
        match outcome.status {
            PushStatus::Accepted | PushStatus::NoOp => {
                store.ack_outbox(outcome.outbox_id)?;
                summary.push_acked_count += 1;
            }
            PushStatus::Superseded => {
                store.ack_outbox(outcome.outbox_id)?;
                summary.push_superseded_count += 1;
            }
        }
    }
}
```

### 未解決事項

- 同一インストールからの再ログインでサーバーのdevice行が増える問題は未解決。BACKLOG #29へ追記した。
- 2端末がそれぞれ別UUIDのInboxを持つ場合の重複マージ方針は未裁定。BACKLOG #30と要人間判断へ追記した。
