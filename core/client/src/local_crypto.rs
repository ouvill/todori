use std::path::Path;

use todori_crypto::key_hierarchy::{
    unwrap_local_list_dek_with_master_key, unwrap_local_tenant_root_dek_with_master_key,
    wrap_local_list_dek_with_master_key, wrap_local_tenant_root_dek_with_master_key, KEY_LEN,
};
use todori_domain::Uuid;
use todori_storage::{
    open_encrypted, ListRepository, LocalCryptoRepository, LocalListKeyBundle, LocalProfileBinding,
    LocalTenantRootKeyBundle, SqliteListRepository, SqliteLocalCryptoRepository, StorageError,
};
use todori_sync::{account::AccountKeyMaterial, LocalSyncKeys};
use zeroize::Zeroizing;

use crate::LocalMutationContext;

pub enum LocalCryptoAvailability {
    Anonymous,
    Ready(LocalCryptoContext),
    AccountBoundUnavailable(LocalCryptoUnavailable),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LocalCryptoIdentity {
    pub tenant_id: Uuid,
    pub user_id: Uuid,
    pub device_id: Uuid,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LocalCryptoUnavailable {
    MissingMasterKey,
    CorruptKeyCache,
    MissingListKey(Uuid),
    MissingTenantRootKey,
}

pub struct LocalCryptoContext {
    tenant_id: Uuid,
    user_id: Uuid,
    device_id: Uuid,
    master_key: Zeroizing<[u8; KEY_LEN]>,
    sync_keys: LocalSyncKeys,
}

impl LocalCryptoContext {
    pub fn tenant_id(&self) -> Uuid {
        self.tenant_id
    }

    pub fn user_id(&self) -> Uuid {
        self.user_id
    }

    pub fn device_id(&self) -> Uuid {
        self.device_id
    }

    pub fn master_key(&self) -> &[u8; KEY_LEN] {
        &self.master_key
    }

    pub fn sync_keys(&self) -> &LocalSyncKeys {
        &self.sync_keys
    }

    pub fn mutation_context(&self) -> LocalMutationContext {
        LocalMutationContext {
            device_id: self.device_id.to_string(),
            keys: self.sync_keys.clone(),
        }
    }
}

pub fn load_local_crypto_context(
    db_path: &Path,
    db_key: &[u8; 32],
    master_key: Option<[u8; KEY_LEN]>,
) -> Result<LocalCryptoAvailability, StorageError> {
    let connection = open_encrypted(db_path, db_key)?;
    let repository = SqliteLocalCryptoRepository::new(connection);
    let Some(binding) = repository.load_binding()? else {
        return Ok(LocalCryptoAvailability::Anonymous);
    };
    let Some(master_key) = master_key else {
        return Ok(LocalCryptoAvailability::AccountBoundUnavailable(
            LocalCryptoUnavailable::MissingMasterKey,
        ));
    };
    let bundles = repository.load_bundles(binding.tenant_id)?;
    let entries = bundles
        .into_iter()
        .map(|bundle| (bundle.list_id, bundle.wrapped_list_dek))
        .collect::<Vec<_>>();
    let Some(tenant_root) = repository.load_tenant_root(binding.tenant_id)? else {
        return Ok(LocalCryptoAvailability::AccountBoundUnavailable(
            LocalCryptoUnavailable::MissingTenantRootKey,
        ));
    };
    let sync_keys = match unwrap_local_cache_entries(
        binding.tenant_id,
        &tenant_root.wrapped_tenant_root_dek,
        &entries,
        &master_key,
    ) {
        Ok(keys) => keys,
        Err(_) => {
            return Ok(LocalCryptoAvailability::AccountBoundUnavailable(
                LocalCryptoUnavailable::CorruptKeyCache,
            ));
        }
    };

    if let Some(list_id) = missing_required_list_key(db_path, db_key, &sync_keys)? {
        return Ok(LocalCryptoAvailability::AccountBoundUnavailable(
            LocalCryptoUnavailable::MissingListKey(list_id),
        ));
    }

    Ok(LocalCryptoAvailability::Ready(LocalCryptoContext {
        tenant_id: binding.tenant_id,
        user_id: binding.user_id,
        device_id: binding.device_id,
        master_key: Zeroizing::new(master_key),
        sync_keys,
    }))
}

pub fn persist_account_crypto_context(
    db_path: &Path,
    db_key: &[u8; 32],
    identity: LocalCryptoIdentity,
    keys: &AccountKeyMaterial,
    now_ms: i64,
) -> Result<LocalCryptoContext, StorageError> {
    persist_local_crypto_context(
        db_path,
        db_key,
        identity,
        &keys.master_key,
        LocalSyncKeys::from_account_keys(keys),
        now_ms,
    )
}

pub fn persist_local_crypto_context(
    db_path: &Path,
    db_key: &[u8; 32],
    identity: LocalCryptoIdentity,
    master_key: &[u8; KEY_LEN],
    sync_keys: LocalSyncKeys,
    now_ms: i64,
) -> Result<LocalCryptoContext, StorageError> {
    let entries = sync_keys
        .list_deks
        .iter()
        .map(|(list_id, list_dek)| {
            wrap_local_list_dek_with_master_key(&list_id.to_string(), list_dek, master_key)
                .map(|wrapped| (*list_id, wrapped))
                .map_err(|_| {
                    StorageError::IncompatibleSchema("invalid local sync key material".to_string())
                })
        })
        .collect::<Result<Vec<_>, _>>()?;
    let tenant_root_dek = sync_keys.tenant_root_dek.as_deref().ok_or_else(|| {
        StorageError::IncompatibleSchema("local Tenant Root DEK is missing".to_string())
    })?;
    let wrapped_tenant_root_dek = wrap_local_tenant_root_dek_with_master_key(
        &identity.tenant_id.to_string(),
        tenant_root_dek,
        master_key,
    )
    .map_err(|_| {
        StorageError::IncompatibleSchema("invalid local Tenant Root DEK material".to_string())
    })?;
    let tenant_root = LocalTenantRootKeyBundle {
        tenant_id: identity.tenant_id,
        key_version: 1,
        wrapped_tenant_root_dek,
        updated_at: now_ms,
    };
    persist_wrapped_context(
        db_path,
        db_key,
        identity,
        *master_key,
        WrappedLocalKeyCache {
            list_entries: entries,
            tenant_root,
        },
        sync_keys,
        now_ms,
    )
}

fn unwrap_local_cache_entries(
    tenant_id: Uuid,
    wrapped_tenant_root_dek: &[u8],
    entries: &[(Uuid, Vec<u8>)],
    master_key: &[u8; KEY_LEN],
) -> Result<LocalSyncKeys, ()> {
    let list_deks = entries
        .iter()
        .map(|(list_id, wrapped)| {
            unwrap_local_list_dek_with_master_key(&list_id.to_string(), wrapped, master_key)
                .map(|list_dek| (*list_id, list_dek))
                .map_err(|_| ())
        })
        .collect::<Result<Vec<_>, _>>()?;
    let tenant_root_dek = unwrap_local_tenant_root_dek_with_master_key(
        &tenant_id.to_string(),
        wrapped_tenant_root_dek,
        master_key,
    )
    .map_err(|_| ())?;
    Ok(LocalSyncKeys {
        list_deks,
        tenant_root_dek: Some(Zeroizing::new(tenant_root_dek)),
    })
}

struct WrappedLocalKeyCache {
    list_entries: Vec<(Uuid, Vec<u8>)>,
    tenant_root: LocalTenantRootKeyBundle,
}

fn persist_wrapped_context(
    db_path: &Path,
    db_key: &[u8; 32],
    identity: LocalCryptoIdentity,
    master_key: [u8; KEY_LEN],
    wrapped_cache: WrappedLocalKeyCache,
    sync_keys: LocalSyncKeys,
    now_ms: i64,
) -> Result<LocalCryptoContext, StorageError> {
    let LocalCryptoIdentity {
        tenant_id,
        user_id,
        device_id,
    } = identity;
    if missing_required_list_key(db_path, db_key, &sync_keys)?.is_some() {
        return Err(StorageError::IncompatibleSchema(
            "local crypto context does not cover every local list".to_string(),
        ));
    }
    let connection = open_encrypted(db_path, db_key)?;
    let mut repository = SqliteLocalCryptoRepository::new(connection);
    let existing = repository.load_binding()?;
    let bound_at = existing.as_ref().map_or(now_ms, |binding| binding.bound_at);
    let binding = LocalProfileBinding {
        tenant_id,
        user_id,
        device_id,
        bound_at,
        updated_at: now_ms,
    };
    let bundles = wrapped_cache
        .list_entries
        .into_iter()
        .map(|(list_id, wrapped_list_dek)| LocalListKeyBundle {
            tenant_id,
            list_id,
            wrapped_list_dek,
            updated_at: now_ms,
        })
        .collect::<Vec<_>>();
    repository.bind_and_replace_bundles(binding, &wrapped_cache.tenant_root, &bundles)?;

    Ok(LocalCryptoContext {
        tenant_id,
        user_id,
        device_id,
        master_key: Zeroizing::new(master_key),
        sync_keys,
    })
}

fn missing_required_list_key(
    db_path: &Path,
    db_key: &[u8; 32],
    sync_keys: &LocalSyncKeys,
) -> Result<Option<Uuid>, StorageError> {
    let connection = open_encrypted(db_path, db_key)?;
    let lists = SqliteListRepository::new(connection);
    let mut local_lists = lists.list_all()?;
    local_lists.extend(lists.list_archived()?);
    Ok(local_lists
        .into_iter()
        .find(|list| !sync_keys.contains_list(list.id))
        .map(|list| list.id))
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;
    use todori_domain::{new_list, new_task};
    use todori_storage::{
        ListRepository, SqliteListRepository, SqliteSyncStateRepository, SqliteTaskRepository,
        SyncStateRepository, TaskRepository,
    };
    use todori_sync::account::{AccountKeyMaterial, AccountListDekMaterial};

    use super::*;

    const DB_KEY: [u8; 32] = [0x84; 32];
    const MASTER_KEY: [u8; KEY_LEN] = [0x52; KEY_LEN];
    const NOW: i64 = 1_799_000_000_000;

    fn account_keys(list_id: Uuid) -> AccountKeyMaterial {
        AccountKeyMaterial {
            master_key: Zeroizing::new(MASTER_KEY),
            user_secret_key: Zeroizing::new([0x11; KEY_LEN]),
            tenant_root_dek: Zeroizing::new([0x22; KEY_LEN]),
            list_deks: vec![AccountListDekMaterial {
                list_id: list_id.to_string(),
                dek: Zeroizing::new([0x33; KEY_LEN]),
            }],
        }
    }

    #[test]
    fn persisted_context_reopens_without_remote_session() {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("client.sqlite3");
        let list = new_list(
            "Inbox".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            NOW,
        )
        .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        SqliteListRepository::new(connection)
            .insert(list.clone())
            .unwrap();
        let task = new_task(
            list.id,
            None,
            "before".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            NOW,
        )
        .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        SqliteTaskRepository::new(connection)
            .insert(task.clone())
            .unwrap();
        let tenant_id = Uuid::now_v7();
        let user_id = Uuid::now_v7();
        let device_id = Uuid::now_v7();
        persist_account_crypto_context(
            &db_path,
            &DB_KEY,
            LocalCryptoIdentity {
                tenant_id,
                user_id,
                device_id,
            },
            &account_keys(list.id),
            NOW,
        )
        .unwrap();

        let loaded = load_local_crypto_context(&db_path, &DB_KEY, Some(MASTER_KEY)).unwrap();
        let LocalCryptoAvailability::Ready(context) = loaded else {
            panic!("expected ready local crypto context");
        };
        assert_eq!(context.tenant_id(), tenant_id);
        assert_eq!(context.user_id(), user_id);
        assert_eq!(context.device_id(), device_id);
        assert!(context.sync_keys().contains_list(list.id));

        crate::SqliteMutationService::new(&db_path, DB_KEY)
            .update_task(
                crate::UpdateTaskInput {
                    task_id: task.id,
                    title: "after restart".to_string(),
                    note: String::new(),
                    priority: 0,
                    due: None,
                    scheduled_at: None,
                    estimated_minutes: None,
                    now_ms: NOW + 1,
                },
                &context.mutation_context(),
            )
            .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        assert_eq!(
            SqliteTaskRepository::new(connection)
                .get(task.id)
                .unwrap()
                .title,
            "after restart"
        );
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        assert_eq!(
            SqliteSyncStateRepository::new(connection)
                .list_outbox_heads(10)
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn bound_profile_without_master_key_is_not_anonymous() {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("client.sqlite3");
        let list = new_list(
            "Inbox".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            NOW,
        )
        .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        SqliteListRepository::new(connection)
            .insert(list.clone())
            .unwrap();
        persist_account_crypto_context(
            &db_path,
            &DB_KEY,
            LocalCryptoIdentity {
                tenant_id: Uuid::now_v7(),
                user_id: Uuid::now_v7(),
                device_id: Uuid::now_v7(),
            },
            &account_keys(list.id),
            NOW,
        )
        .unwrap();

        assert!(matches!(
            load_local_crypto_context(&db_path, &DB_KEY, None).unwrap(),
            LocalCryptoAvailability::AccountBoundUnavailable(
                LocalCryptoUnavailable::MissingMasterKey
            )
        ));
    }

    #[test]
    fn missing_required_list_key_is_not_ready() {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("client.sqlite3");
        let cached_list = new_list(
            "Cached".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            NOW,
        )
        .unwrap();
        let missing_list = new_list(
            "Missing".to_string(),
            "bfffffffffffffffffffffffffffffff".to_string(),
            NOW,
        )
        .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        let mut lists = SqliteListRepository::new(connection);
        lists.insert(cached_list.clone()).unwrap();
        lists.insert(missing_list.clone()).unwrap();
        let tenant_id = Uuid::now_v7();
        let account_keys = account_keys(cached_list.id);
        let entries = account_keys
            .list_deks
            .iter()
            .map(|entry| {
                let list_id = Uuid::parse_str(&entry.list_id).unwrap();
                (
                    list_id,
                    wrap_local_list_dek_with_master_key(
                        &entry.list_id,
                        &entry.dek,
                        &account_keys.master_key,
                    )
                    .unwrap(),
                )
            })
            .collect::<Vec<_>>();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        let tenant_root = LocalTenantRootKeyBundle {
            tenant_id,
            key_version: 1,
            wrapped_tenant_root_dek: wrap_local_tenant_root_dek_with_master_key(
                &tenant_id.to_string(),
                &account_keys.tenant_root_dek,
                &account_keys.master_key,
            )
            .unwrap(),
            updated_at: NOW,
        };
        SqliteLocalCryptoRepository::new(connection)
            .bind_and_replace_bundles(
                LocalProfileBinding {
                    tenant_id,
                    user_id: Uuid::now_v7(),
                    device_id: Uuid::now_v7(),
                    bound_at: NOW,
                    updated_at: NOW,
                },
                &tenant_root,
                &[LocalListKeyBundle {
                    tenant_id,
                    list_id: entries[0].0,
                    wrapped_list_dek: entries[0].1.clone(),
                    updated_at: NOW,
                }],
            )
            .unwrap();

        assert!(matches!(
            load_local_crypto_context(&db_path, &DB_KEY, Some(MASTER_KEY)).unwrap(),
            LocalCryptoAvailability::AccountBoundUnavailable(
                LocalCryptoUnavailable::MissingListKey(id)
            ) if id == missing_list.id
        ));
    }

    #[test]
    fn corrupt_cached_bundle_is_typed_unavailable() {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("client.sqlite3");
        let list = new_list(
            "Inbox".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            NOW,
        )
        .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        SqliteListRepository::new(connection)
            .insert(list.clone())
            .unwrap();
        persist_account_crypto_context(
            &db_path,
            &DB_KEY,
            LocalCryptoIdentity {
                tenant_id: Uuid::now_v7(),
                user_id: Uuid::now_v7(),
                device_id: Uuid::now_v7(),
            },
            &account_keys(list.id),
            NOW,
        )
        .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        connection
            .execute(
                "UPDATE local_list_key_bundles SET wrapped_list_dek = x'00'",
                [],
            )
            .unwrap();

        assert!(matches!(
            load_local_crypto_context(&db_path, &DB_KEY, Some(MASTER_KEY)).unwrap(),
            LocalCryptoAvailability::AccountBoundUnavailable(
                LocalCryptoUnavailable::CorruptKeyCache
            )
        ));
    }
}
