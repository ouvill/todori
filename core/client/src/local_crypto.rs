use std::path::Path;

use taskveil_crypto::key_hierarchy::{
    unwrap_local_tenant_root_dek_with_master_key, wrap_local_tenant_root_dek_with_master_key,
    KEY_LEN,
};
use taskveil_domain::Uuid;
use taskveil_storage::{
    open_encrypted, LocalCryptoRepository, LocalProfileBinding, LocalTenantRootKeyBundle,
    SqliteLocalCryptoRepository, StorageError,
};
use taskveil_sync::{account::AccountKeyMaterial, LocalSyncKeys};
use zeroize::Zeroizing;

use crate::LocalMutationContext;

pub enum LocalCryptoAvailability {
    Anonymous,
    Ready(Box<LocalCryptoContext>),
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
    let Some(tenant_root) = repository.load_tenant_root(binding.tenant_id)? else {
        return Ok(LocalCryptoAvailability::AccountBoundUnavailable(
            LocalCryptoUnavailable::MissingTenantRootKey,
        ));
    };
    let sync_keys = match unwrap_local_cache_entries(
        binding.tenant_id,
        tenant_root.generation,
        &tenant_root.wrapped_tenant_root_dek,
        &master_key,
    ) {
        Ok(keys) => keys,
        Err(_) => {
            return Ok(LocalCryptoAvailability::AccountBoundUnavailable(
                LocalCryptoUnavailable::CorruptKeyCache,
            ));
        }
    };

    Ok(LocalCryptoAvailability::Ready(Box::new(
        LocalCryptoContext {
            tenant_id: binding.tenant_id,
            user_id: binding.user_id,
            device_id: binding.device_id,
            master_key: Zeroizing::new(master_key),
            sync_keys,
        },
    )))
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
        LocalSyncKeys::from_account_keys(identity.tenant_id, keys),
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
    let tenant_root_dek = sync_keys.tenant_root_dek.as_deref().ok_or_else(|| {
        StorageError::IncompatibleSchema("local Tenant Root DEK is missing".to_string())
    })?;
    let wrapped_tenant_root_dek = wrap_local_tenant_root_dek_with_master_key(
        identity.tenant_id,
        sync_keys.tenant_generation,
        tenant_root_dek,
        master_key,
    )
    .map_err(|_| {
        StorageError::IncompatibleSchema("invalid local Tenant Root DEK material".to_string())
    })?;
    let tenant_root = LocalTenantRootKeyBundle {
        tenant_id: identity.tenant_id,
        generation: sync_keys.tenant_generation,
        wrapped_tenant_root_dek,
        updated_at: now_ms,
    };
    persist_wrapped_context(
        db_path,
        db_key,
        identity,
        *master_key,
        WrappedLocalKeyCache { tenant_root },
        sync_keys,
        now_ms,
    )
}

fn unwrap_local_cache_entries(
    tenant_id: Uuid,
    tenant_generation: u64,
    wrapped_tenant_root_dek: &[u8],
    master_key: &[u8; KEY_LEN],
) -> Result<LocalSyncKeys, ()> {
    let tenant_root_dek = unwrap_local_tenant_root_dek_with_master_key(
        tenant_id,
        tenant_generation,
        wrapped_tenant_root_dek,
        master_key,
    )
    .map_err(|_| ())?;
    Ok(LocalSyncKeys {
        tenant_id,
        tenant_root_dek: Some(Zeroizing::new(tenant_root_dek)),
        tenant_generation,
        historical_tenant_root_deks: Vec::new(),
    })
}

struct WrappedLocalKeyCache {
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
    repository.bind_tenant_root(binding, &wrapped_cache.tenant_root)?;

    Ok(LocalCryptoContext {
        tenant_id,
        user_id,
        device_id,
        master_key: Zeroizing::new(master_key),
        sync_keys,
    })
}

#[cfg(test)]
mod tests {
    use taskveil_domain::{new_list, new_task};
    use taskveil_storage::{
        ListRepository, SqliteListRepository, SqliteSyncStateRepository, SqliteTaskRepository,
        SyncStateRepository, TaskRepository,
    };
    use taskveil_sync::account::AccountKeyMaterial;
    use tempfile::TempDir;

    use super::*;

    const DB_KEY: [u8; 32] = [0x84; 32];
    const MASTER_KEY: [u8; KEY_LEN] = [0x52; KEY_LEN];
    const NOW: i64 = 1_799_000_000_000;

    fn account_keys() -> AccountKeyMaterial {
        let root = taskveil_crypto::organization::generate_account_root(Uuid::now_v7()).unwrap();
        AccountKeyMaterial {
            generation: 1,
            tenant_generation: 1,
            master_key: Zeroizing::new(MASTER_KEY),
            account_root_private: root.private,
            account_root_public: root.public,
            tenant_root_dek: Zeroizing::new([0x22; KEY_LEN]),
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
            &account_keys(),
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
        assert!(context.sync_keys().tenant_root_dek.is_some());

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
            &account_keys(),
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
            &account_keys(),
            NOW,
        )
        .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        connection
            .execute(
                "UPDATE local_tenant_root_key_cache SET wrapped_tenant_root_dek = x'00'",
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
