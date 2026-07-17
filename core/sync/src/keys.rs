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
pub const KEY_ROTATION_PENDING_SETTING_KEY: &str = "key_rotation_pending_generation";
pub const TASKS_COLLECTION: &str = "tasks";
pub const LISTS_COLLECTION: &str = "lists";
pub const TEMPLATES_COLLECTION: &str = "templates";
pub const SCHEDULES_COLLECTION: &str = "schedules";
pub const TIMER_SESSIONS_COLLECTION: &str = "timer_sessions";

#[derive(Clone, PartialEq, Eq)]
pub struct LocalSyncKeys {
    pub tenant_id: Uuid,
    pub list_deks: Vec<(Uuid, Zeroizing<[u8; KEY_LEN]>)>,
    pub list_generations: Vec<(Uuid, u64)>,
    pub tenant_root_dek: Option<Zeroizing<[u8; KEY_LEN]>>,
    pub tenant_generation: u64,
    pub historical_list_deks: Vec<(Uuid, u64, Zeroizing<[u8; KEY_LEN]>)>,
    pub historical_tenant_root_deks: Vec<(u64, Zeroizing<[u8; KEY_LEN]>)>,
}

impl Default for LocalSyncKeys {
    fn default() -> Self {
        Self {
            tenant_id: Uuid::nil(),
            list_deks: Vec::new(),
            list_generations: Vec::new(),
            tenant_root_dek: None,
            tenant_generation: INITIAL_KEY_GENERATION,
            historical_list_deks: Vec::new(),
            historical_tenant_root_deks: Vec::new(),
        }
    }
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
            .field("tenant_generation", &self.tenant_generation)
            .field(
                "historical_generation_count",
                &self.historical_tenant_root_deks.len(),
            )
            .finish()
    }
}

impl LocalSyncKeys {
    pub fn from_account_keys(tenant_id: Uuid, keys: &AccountKeyMaterial) -> Self {
        Self {
            tenant_id,
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
            list_generations: keys
                .list_deks
                .iter()
                .filter_map(|entry| {
                    entry
                        .list_id
                        .parse::<Uuid>()
                        .ok()
                        .map(|id| (id, entry.generation))
                })
                .collect(),
            tenant_root_dek: Some(keys.tenant_root_dek.clone()),
            tenant_generation: keys.tenant_generation,
            historical_list_deks: Vec::new(),
            historical_tenant_root_deks: Vec::new(),
        }
    }

    pub fn contains_list(&self, list_id: Uuid) -> bool {
        self.list_deks.iter().any(|(id, _)| *id == list_id)
    }

    pub fn generation_for_list(&self, list_id: Uuid) -> Option<u64> {
        self.list_generations
            .iter()
            .find(|(id, _)| *id == list_id)
            .map(|(_, generation)| *generation)
            .filter(|generation| *generation > 0)
    }

    pub fn validate_for_write(&self) -> Result<(), &'static str> {
        if self.tenant_id.is_nil() || self.tenant_generation == 0 {
            return Err("invalid active key generation");
        }
        if self
            .list_deks
            .iter()
            .any(|(list_id, _)| self.generation_for_list(*list_id).is_none())
        {
            return Err("missing active list key generation");
        }
        Ok(())
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

pub fn dek_for_list_generation(
    keys: &LocalSyncKeys,
    list_id: Uuid,
    generation: u64,
) -> Option<&[u8; KEY_LEN]> {
    if keys.generation_for_list(list_id) == Some(generation) {
        return dek_for_list(keys, list_id);
    }
    keys.historical_list_deks
        .iter()
        .find(|(id, candidate_generation, _)| *id == list_id && *candidate_generation == generation)
        .map(|(_, _, dek)| &**dek)
}

pub fn tenant_root_dek_for_generation(
    keys: &LocalSyncKeys,
    generation: u64,
) -> Option<&[u8; KEY_LEN]> {
    if keys.tenant_generation == generation {
        return tenant_root_dek(keys);
    }
    keys.historical_tenant_root_deks
        .iter()
        .find(|(candidate_generation, _)| *candidate_generation == generation)
        .map(|(_, dek)| &**dek)
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
        generation: INITIAL_KEY_GENERATION,
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
            tenant_id: Uuid::now_v7(),
            list_deks: vec![(list_id, Zeroizing::new([0x5a; KEY_LEN]))],
            list_generations: vec![(list_id, INITIAL_KEY_GENERATION)],
            tenant_root_dek: Some(Zeroizing::new([0xa5; KEY_LEN])),
            tenant_generation: INITIAL_KEY_GENERATION,
            historical_list_deks: Vec::new(),
            historical_tenant_root_deks: Vec::new(),
        };

        let debug = format!("{keys:?}");

        assert_eq!(
            debug,
            format!("LocalSyncKeys {{ list_count: 1, list_ids: [{list_id}], has_tenant_root_dek: true, tenant_generation: 1, historical_generation_count: 0 }}")
        );
    }
}
