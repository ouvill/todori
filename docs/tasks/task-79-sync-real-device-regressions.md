# task-79 sync real-device regression fixes

> ステータス: 完了（default list衝突・セッション復元・List DEK refresh修正）
> 作業日: 2026-07-10

## 1. 目的

実機同期確認で見つかった以下2件を修正する。

- 2台目の `Sync now` が、pullした別IDのdefault listとローカルdefault listのUNIQUE制約衝突で `sync failed` になる。
- アプリ再起動後に永続セッションから `ACCOUNT_STATE` が復元されず、同期が `Sync is off` になる。

## 9. 完了報告

### 変更ファイル一覧

- `core/sync/src/apply.rs`
- `core/sync/src/enqueue.rs`
- `core/sync/src/account.rs`
- `app/rust/src/support.rs`
- `app/rust/src/sync_store.rs`
- `server/src/sync.rs`
- `server/src/routes/sync.rs`
- `server/tests/sync_server.rs`
- `docs/tasks/task-79-sync-real-device-regressions.md`

### 実装内容

- `apply_pull_list` で、pullしたマージ結果が `is_default=true` かつローカルに別IDのdefault listが存在する場合、ローカル `lists` 行だけ `is_default=false` にして保存する暫定デモーションを追加した。
- デモーション後も `sync_record_states` へ保存するplaintextは `is_default=true` のまま保持し、この処理自体ではrepushしない。
- `LocalSyncStore::default_list_id()` を追加し、`BridgeSyncStore` とcoreテスト用storeへ実装した。
- `ensure_account_runtime_restored()` を追加し、`get_account_session_state()`、`active_sync_context()`、`ensure_list_dek_for_list()`、bridge側 `run_sync_now()` から呼ぶようにした。
- bridge側 `run_sync_now()` で、初回backfill後・core同期前にlist key bundle一覧を取得し、MKでunwrapしたList DEKをruntime keysへマージするベストエフォート処理を追加した。取得失敗時は同期失敗にしない。
- `core/sync/src/account.rs` に `unwrap_list_dek_bundles()` と `AccountClient::list_key_bundles()` を追加した。
- serverに `GET /v1/tenants/{tenant_id}/list-keys` を追加した。

### ensure_account_runtime_restored 全文

```rust
fn ensure_account_runtime_restored() -> Result<(), String> {
    {
        let account = account_runtime_state();
        if account.session.is_some() {
            return Ok(());
        }
    }

    let state = core_state()?;
    let Some(_session_token) = load_account_secret(&state.db_dir, AccountSecretKind::SessionToken)
        .map_err(|error| error.to_string())?
        .and_then(|bytes| String::from_utf8(bytes).ok())
        .filter(|token| !token.is_empty())
    else {
        return Ok(());
    };
    let Some(local_wrapped_master_key) =
        load_account_secret(&state.db_dir, AccountSecretKind::MasterKeyWrap)
            .map_err(|error| error.to_string())?
    else {
        return Ok(());
    };
    let Some(email) = non_empty_setting(ACCOUNT_EMAIL_SETTING_KEY)? else {
        return Ok(());
    };
    let Some(user_id) = non_empty_setting(ACCOUNT_USER_ID_SETTING_KEY)? else {
        return Ok(());
    };
    let Some(tenant_id) = non_empty_setting(ACCOUNT_TENANT_ID_SETTING_KEY)? else {
        return Ok(());
    };
    let Some(device_id) = non_empty_setting(ACCOUNT_DEVICE_ID_SETTING_KEY)? else {
        return Ok(());
    };
    let expires_at = non_empty_setting(ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY)?
        .and_then(|value| value.parse::<i64>().ok());
    let Some(expires_at) = expires_at else {
        return Ok(());
    };
    if expires_at <= now_ms()? {
        return Ok(());
    }

    let device_key = load_or_create_device_key(&state.db_dir).map_err(|error| error.to_string())?;
    let master_key = match unwrap_master_key_with_device_key(&local_wrapped_master_key, &device_key)
    {
        Ok(master_key) => master_key,
        Err(_) => return Ok(()),
    };
    let session = account_session_to_dto(true, email, user_id, tenant_id, device_id);
    let keys = AccountKeyMaterial {
        master_key: Zeroizing::new(master_key),
        user_secret_key: Zeroizing::new([0; KEY_LEN]),
        tenant_root_dek: Zeroizing::new([0; KEY_LEN]),
        list_deks: Vec::new(),
    };
    replace_account_runtime_state(Some(session), Some(keys));
    Ok(())
}
```

### テスト結果

- `cargo test -p taskveil-sync`: 成功。36 passed。
- `cargo test -p taskveil-crypto`: 成功。28 passed / 1 ignored。
- `cargo test -p taskveil-storage`: 成功。48 passed / 1 ignored。
- `cargo test -p taskveil-server`: 成功。server統合テスト5 passed。
- `cargo build -p taskveil_app_bridge`: 成功。
- `cargo clippy -p taskveil_app_bridge -p taskveil-sync -- -D warnings`: 成功。
- `cargo fmt --all -- --check`: 成功。

### 手動確認手順

1. 2台の実機または実機+Simulatorで同じアカウントへログインする。
2. 片方で同期済みの状態にし、もう片方を再起動する。
3. 再起動後にログイン画面へ戻らず、`Sync is off` ではなくログイン済み同期状態で表示されることを確認する。
4. 2台目で `Sync now` を実行し、別IDのdefault listをpullしても `sync failed` にならないことを確認する。
5. 片方で新規リストを作成して同期し、もう片方の次回 `Sync now` でDEK取得後にpullできることを確認する。

### 未解決事項

- Inbox重複の恒久マージ方針はBACKLOG #30の裁定待ち。今回のdefault listデモーションは同期失敗を避ける暫定措置である。
