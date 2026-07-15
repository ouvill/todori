use std::fmt;

use todori_crypto::key_hierarchy::{generate_list_dek, INITIAL_KEY_GENERATION, KEY_LEN};
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::account::{
    wrap_list_dek_bundle, AccountClient, AccountKeyMaterial, AccountListDekMaterial,
};

pub const SYNC_CURSOR_NAME: &str = "main";
pub const SYNC_LOCAL_HLC_SETTING_KEY: &str = "sync_local_hlc";
pub const SYNC_UPGRADE_REQUIRED_SETTING_KEY: &str = "sync_upgrade_required_v2";
pub const TASKS_COLLECTION: &str = "tasks";
pub const LISTS_COLLECTION: &str = "lists";
pub const TIMER_SESSIONS_COLLECTION: &str = "timer_sessions";

#[derive(Clone, Default, PartialEq, Eq)]
pub struct LocalSyncKeys {
    pub list_deks: Vec<(Uuid, Zeroizing<[u8; KEY_LEN]>)>,
    pub tenant_root_dek: Option<Zeroizing<[u8; KEY_LEN]>>,
}

impl fmt::Debug for LocalSyncKeys {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LocalSyncKeys")
            .field("list_count", &self.list_deks.len())
            .field(
                "list_ids",
                &self
                    .list_deks
                    .iter()
                    .map(|(list_id, _)| list_id)
                    .collect::<Vec<_>>(),
            )
            .field("has_tenant_root_dek", &self.tenant_root_dek.is_some())
            .finish()
    }
}

impl LocalSyncKeys {
    pub fn from_account_keys(keys: &AccountKeyMaterial) -> Self {
        Self {
            list_deks: keys
                .list_deks
                .iter()
                .filter_map(|entry| {
                    entry
                        .list_id
                        .parse::<Uuid>()
                        .ok()
                        .map(|id| (id, entry.dek.clone()))
                })
                .collect(),
            tenant_root_dek: Some(keys.tenant_root_dek.clone()),
        }
    }

    pub fn contains_list(&self, list_id: Uuid) -> bool {
        self.list_deks.iter().any(|(id, _)| *id == list_id)
    }
}

pub fn dek_for_list(keys: &LocalSyncKeys, list_id: Uuid) -> Option<&[u8; KEY_LEN]> {
    keys.list_deks
        .iter()
        .find(|(id, _)| *id == list_id)
        .map(|(_, dek)| &**dek)
}

pub fn tenant_root_dek(keys: &LocalSyncKeys) -> Option<&[u8; KEY_LEN]> {
    keys.tenant_root_dek.as_deref()
}

pub async fn ensure_list_dek_for_list(
    server_url: impl Into<String>,
    tenant_id: Uuid,
    session_token: &str,
    master_key: &[u8; KEY_LEN],
    existing_list_ids: &[String],
    list_id: Uuid,
) -> Result<Option<AccountListDekMaterial>, String> {
    if existing_list_ids
        .iter()
        .any(|existing| existing == &list_id.to_string())
    {
        return Ok(None);
    }

    let list_dek = Zeroizing::new(generate_list_dek());
    let bundle = wrap_list_dek_bundle(
        tenant_id,
        list_id,
        INITIAL_KEY_GENERATION,
        &list_dek,
        master_key,
    )
    .map_err(|_| "list key registration failed".to_string())?;
    let client =
        AccountClient::new(server_url).map_err(|_| "list key registration failed".to_string())?;
    client
        .upsert_list_key_bundle(tenant_id, session_token, bundle)
        .await
        .map_err(|_| "list key registration failed".to_string())?;

    Ok(Some(AccountListDekMaterial {
        list_id: list_id.to_string(),
        dek: list_dek,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_sync_keys_debug_redacts_key_material() {
        let list_id = Uuid::now_v7();
        let keys = LocalSyncKeys {
            list_deks: vec![(list_id, Zeroizing::new([0x5a; KEY_LEN]))],
            tenant_root_dek: Some(Zeroizing::new([0xa5; KEY_LEN])),
        };

        let debug = format!("{keys:?}");

        assert_eq!(
            debug,
            format!("LocalSyncKeys {{ list_count: 1, list_ids: [{list_id}], has_tenant_root_dek: true }}")
        );
    }
}
