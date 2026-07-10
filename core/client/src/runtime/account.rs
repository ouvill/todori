use std::collections::HashSet;

use todori_crypto::{
    delete_account_secret, key_hierarchy::unwrap_master_key_with_device_key, load_account_secret,
    load_or_create_device_key, store_account_secret, AccountSecretKind,
};
use todori_domain::Uuid;
use todori_storage::{
    open_encrypted, ListRepository, LocalCryptoRepository, SqliteLocalCryptoRepository,
    SqliteSyncStateRepository, StorageError,
};
use todori_sync::{
    account::{unwrap_list_dek_bundles, AccountClient, AccountKeyMaterial, AccountListDekMaterial},
    LocalSyncKeys,
};
use zeroize::Zeroizing;

use super::{
    now_ms, CryptoRuntimeState, TodoriClient, ACCOUNT_DEVICE_ID_SETTING_KEY,
    ACCOUNT_EMAIL_SETTING_KEY, ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY,
    ACCOUNT_TENANT_ID_SETTING_KEY, ACCOUNT_USER_ID_SETTING_KEY,
};
use crate::{
    load_local_crypto_context, persist_account_crypto_context, persist_local_crypto_context,
    AccountAuthResult, AccountSessionState, ClientError, LocalCryptoAvailability,
    LocalCryptoIdentity, LocalCryptoUnavailable,
};

enum AccountAuthMode {
    Register,
    Login,
}

impl TodoriClient {
    pub fn account_session_state(&self) -> Result<AccountSessionState, ClientError> {
        self.ensure_account_runtime_restored()?;
        Ok(self
            .account_state()?
            .session
            .clone()
            .unwrap_or_else(AccountSessionState::logged_out))
    }

    pub async fn account_register(
        &self,
        email: String,
        password: String,
        server_url: Option<String>,
        device_name: Option<String>,
    ) -> Result<AccountAuthResult, ClientError> {
        self.account_auth(
            email,
            password,
            server_url,
            device_name,
            AccountAuthMode::Register,
        )
        .await
    }

    pub async fn account_login(
        &self,
        email: String,
        password: String,
        server_url: Option<String>,
        device_name: Option<String>,
    ) -> Result<AccountAuthResult, ClientError> {
        self.account_auth(
            email,
            password,
            server_url,
            device_name,
            AccountAuthMode::Login,
        )
        .await
    }

    pub async fn account_logout(&self) -> Result<(), ClientError> {
        let _operation = self.begin_operation()?;
        let server_url = self.sync_server_url()?;
        let token = load_secret_string(&self.db_dir, AccountSecretKind::SessionToken)?;
        if let Some(token) = token.as_ref() {
            if let Ok(client) = AccountClient::new(server_url) {
                let _ = client.logout(token).await;
            }
        }
        delete_account_secret(&self.db_dir, AccountSecretKind::SessionToken)
            .map_err(ClientError::KeyStore)?;
        // Logout revokes only the remote session. The account binding, wrapped
        // master key and verified local List DEK cache deliberately survive so
        // offline mutation remains available.
        let mut account = self.account_state()?;
        account.session = None;
        account.session_restored = true;
        Ok(())
    }

    async fn account_auth(
        &self,
        email: String,
        password: String,
        server_url: Option<String>,
        device_name: Option<String>,
        mode: AccountAuthMode,
    ) -> Result<AccountAuthResult, ClientError> {
        let _operation = self.begin_operation()?;
        let server_url = match server_url {
            Some(server_url) => {
                self.set_sync_server_url(server_url)?;
                self.sync_server_url()?
            }
            None => self.sync_server_url()?,
        };
        let device_key =
            Zeroizing::new(load_or_create_device_key(&self.db_dir).map_err(ClientError::KeyStore)?);
        let client = AccountClient::new(&server_url).map_err(|_| ClientError::AccountRequest)?;
        let password = Zeroizing::new(password);

        match mode {
            AccountAuthMode::Register => {
                self.ensure_profile_is_unbound_for_registration()?;
                let initial_list_ids = self.local_list_ids_for_registration()?;
                let outcome = client
                    .register(
                        &email,
                        &password,
                        device_name.as_deref(),
                        &device_key,
                        initial_list_ids,
                    )
                    .await
                    .map_err(|_| ClientError::AccountRequest)?;
                let session = account_session_state(
                    outcome.session.email.clone(),
                    outcome.session.user_id.clone(),
                    outcome.session.tenant_id.clone(),
                    outcome.session.device_id.clone(),
                );
                let crypto = self.persist_account_state(
                    &session,
                    outcome.session.expires_at_ms,
                    outcome.session.session_token.as_bytes(),
                    &outcome.local_wrapped_master_key,
                    &outcome.keys,
                )?;
                self.replace_account_runtime(Some(session.clone()), crypto)?;
                // A new profile has no initial-backfill cursor. Do not delete a
                // durable cursor here: same-profile authentication must be
                // idempotent and must never replay a completed backfill.
                Ok(AccountAuthResult {
                    session,
                    recovery_key: Some(outcome.recovery_key.to_string()),
                })
            }
            AccountAuthMode::Login => {
                let mut outcome = client
                    .login(&email, &password, device_name.as_deref(), &device_key)
                    .await
                    .map_err(|_| ClientError::AccountRequest)?;
                let tenant_id = parse_uuid(&outcome.session.tenant_id)?;
                let user_id = parse_uuid(&outcome.session.user_id)?;
                self.validate_existing_profile_identity(tenant_id, user_id)?;
                self.ensure_key_material_covers_local_lists(
                    &server_url,
                    tenant_id,
                    &outcome.session.session_token,
                    &mut outcome.keys,
                )
                .await?;
                let session = account_session_state(
                    outcome.session.email.clone(),
                    outcome.session.user_id.clone(),
                    outcome.session.tenant_id.clone(),
                    outcome.session.device_id.clone(),
                );
                let crypto = self.persist_account_state(
                    &session,
                    outcome.session.expires_at_ms,
                    outcome.session.session_token.as_bytes(),
                    &outcome.local_wrapped_master_key,
                    &outcome.keys,
                )?;
                self.replace_account_runtime(Some(session.clone()), crypto)?;
                Ok(AccountAuthResult {
                    session,
                    recovery_key: None,
                })
            }
        }
    }

    pub(super) fn ensure_account_runtime_restored(&self) -> Result<(), ClientError> {
        let restore_crypto = matches!(self.account_state()?.crypto, CryptoRuntimeState::Unloaded);
        if restore_crypto {
            let master_key =
                match load_account_secret(&self.db_dir, AccountSecretKind::MasterKeyWrap)
                    .map_err(ClientError::KeyStore)?
                {
                    Some(local_wrapped_master_key) => {
                        let device_key = Zeroizing::new(
                            load_or_create_device_key(&self.db_dir)
                                .map_err(ClientError::KeyStore)?,
                        );
                        unwrap_master_key_with_device_key(&local_wrapped_master_key, &device_key)
                            .ok()
                    }
                    None => None,
                };
            let availability = load_local_crypto_context(&self.db_path, &self.db_key, master_key)?;
            let crypto = match availability {
                LocalCryptoAvailability::Ready(crypto) => CryptoRuntimeState::Ready(crypto),
                LocalCryptoAvailability::AccountBoundUnavailable(reason) => {
                    CryptoRuntimeState::Unavailable(reason)
                }
                LocalCryptoAvailability::Anonymous if self.has_legacy_account_binding()? => {
                    CryptoRuntimeState::Unavailable(LocalCryptoUnavailable::MissingMasterKey)
                }
                LocalCryptoAvailability::Anonymous => CryptoRuntimeState::Anonymous,
            };
            self.account_state()?.crypto = crypto;
        }

        if self.account_state()?.session_restored {
            return Ok(());
        }
        let session_token = load_secret_string(&self.db_dir, AccountSecretKind::SessionToken)?;
        self.account_state()?.session_restored = true;
        let Some(_session_token) = session_token.filter(|token| !token.is_empty()) else {
            return Ok(());
        };
        let Some(email) = self.non_empty_setting(ACCOUNT_EMAIL_SETTING_KEY)? else {
            return Ok(());
        };
        let Some(user_id) = self.non_empty_setting(ACCOUNT_USER_ID_SETTING_KEY)? else {
            return Ok(());
        };
        let Some(tenant_id) = self.non_empty_setting(ACCOUNT_TENANT_ID_SETTING_KEY)? else {
            return Ok(());
        };
        let Some(device_id) = self.non_empty_setting(ACCOUNT_DEVICE_ID_SETTING_KEY)? else {
            return Ok(());
        };
        let Some(expires_at) = self
            .non_empty_setting(ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY)?
            .and_then(|value| value.parse::<i64>().ok())
        else {
            return Ok(());
        };
        if expires_at <= now_ms()? {
            return Ok(());
        }
        self.account_state()?.session =
            Some(account_session_state(email, user_id, tenant_id, device_id));
        Ok(())
    }

    pub(super) async fn refresh_list_deks_for_sync(&self) -> Result<LocalSyncKeys, ClientError> {
        self.ensure_account_runtime_restored()?;
        let server_url = self.sync_server_url()?;
        let session_token = load_secret_string(&self.db_dir, AccountSecretKind::SessionToken)?
            .ok_or(ClientError::AccountRequest)?;
        let (tenant_id, user_id, device_id, master_key) = {
            let account = self.account_state()?;
            let Some(_session) = account.session.as_ref().filter(|session| session.logged_in)
            else {
                return Err(ClientError::AccountRequest);
            };
            let CryptoRuntimeState::Ready(crypto) = &account.crypto else {
                return Err(ClientError::AccountBoundUnavailable);
            };
            (
                crypto.tenant_id(),
                crypto.user_id(),
                crypto.device_id(),
                Zeroizing::new(*crypto.master_key()),
            )
        };

        let client = AccountClient::new(server_url).map_err(|_| ClientError::AccountRequest)?;
        let bundles = client
            .list_key_bundles(tenant_id, &session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        let materials = unwrap_list_dek_bundles(&bundles, &master_key)
            .map_err(|_| ClientError::AccountBoundUnavailable)?;
        let remote_keys = LocalSyncKeys {
            list_deks: materials
                .into_iter()
                .map(|material| Ok((parse_uuid(&material.list_id)?, *material.dek)))
                .collect::<Result<Vec<_>, ClientError>>()?,
        };
        let local_keys = {
            let account = self.account_state()?;
            let CryptoRuntimeState::Ready(crypto) = &account.crypto else {
                return Err(ClientError::AccountBoundUnavailable);
            };
            crypto.sync_keys().clone()
        };
        let pending = self.pending_list_key_ids(tenant_id)?;
        let retained = retained_deleted_list_key_ids_on(&self.db_path, &self.db_key)?;
        let sync_keys =
            merge_remote_and_pending_local_keys(remote_keys, local_keys, &pending, &retained)?;
        let crypto = persist_local_crypto_context(
            &self.db_path,
            &self.db_key,
            LocalCryptoIdentity {
                tenant_id,
                user_id,
                device_id,
            },
            &master_key,
            sync_keys.clone(),
            now_ms()?,
        )?;
        self.account_state()?.crypto = CryptoRuntimeState::Ready(crypto);
        Ok(sync_keys)
    }

    pub(super) fn local_lists_including_archived(
        &self,
    ) -> Result<Vec<todori_domain::List>, ClientError> {
        self.with_list_repository(|repository| {
            let mut lists = repository.list_all()?;
            lists.extend(repository.list_archived()?);
            Ok(lists)
        })
    }

    fn local_list_ids_for_registration(&self) -> Result<Vec<Uuid>, ClientError> {
        Ok(self
            .local_lists_including_archived()?
            .into_iter()
            .map(|list| list.id)
            .collect())
    }

    async fn ensure_key_material_covers_local_lists(
        &self,
        server_url: &str,
        tenant_id: Uuid,
        session_token: &str,
        keys: &mut AccountKeyMaterial,
    ) -> Result<(), ClientError> {
        match load_local_crypto_context(&self.db_path, &self.db_key, Some(*keys.master_key))? {
            LocalCryptoAvailability::Ready(local) => {
                let pending = self.pending_list_key_ids(tenant_id)?;
                let retained = retained_deleted_list_key_ids_on(&self.db_path, &self.db_key)?;
                let merged = merge_remote_and_pending_local_keys(
                    LocalSyncKeys::from_account_keys(keys),
                    local.sync_keys().clone(),
                    &pending,
                    &retained,
                )?;
                keys.list_deks = merged
                    .list_deks
                    .into_iter()
                    .map(|(list_id, dek)| AccountListDekMaterial {
                        list_id: list_id.to_string(),
                        dek: Zeroizing::new(dek),
                    })
                    .collect();
                return Ok(());
            }
            LocalCryptoAvailability::AccountBoundUnavailable(_) => {
                return Err(ClientError::AccountBoundUnavailable);
            }
            LocalCryptoAvailability::Anonymous => {}
        }
        for list_id in self.local_list_ids_for_registration()? {
            let existing = keys
                .list_deks
                .iter()
                .map(|entry| entry.list_id.clone())
                .collect::<Vec<_>>();
            if let Some(material) = todori_sync::ensure_list_dek_for_list(
                server_url,
                tenant_id,
                session_token,
                &keys.master_key,
                &existing,
                list_id,
            )
            .await
            .map_err(|_| ClientError::SyncRun)?
            {
                keys.list_deks.push(material);
            }
        }
        Ok(())
    }

    fn pending_list_key_ids(&self, tenant_id: Uuid) -> Result<HashSet<Uuid>, ClientError> {
        pending_list_key_ids_on(&self.db_path, &self.db_key, tenant_id)
    }

    fn ensure_profile_is_unbound_for_registration(&self) -> Result<(), ClientError> {
        if self.has_profile_binding()? || self.has_legacy_account_binding()? {
            return Err(ClientError::ProfileAlreadyBound);
        }
        Ok(())
    }

    fn validate_existing_profile_identity(
        &self,
        tenant_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), ClientError> {
        let connection = open_encrypted(&self.db_path, &self.db_key)?;
        if let Some(binding) = SqliteLocalCryptoRepository::new(connection).load_binding()? {
            if binding.tenant_id != tenant_id || binding.user_id != user_id {
                return Err(ClientError::ProfileIdentityMismatch);
            }
        } else if self.has_legacy_account_binding()? {
            let legacy_tenant = self
                .non_empty_setting(ACCOUNT_TENANT_ID_SETTING_KEY)?
                .ok_or(ClientError::IncompleteAccountState)?;
            let legacy_user = self
                .non_empty_setting(ACCOUNT_USER_ID_SETTING_KEY)?
                .ok_or(ClientError::IncompleteAccountState)?;
            if parse_uuid(&legacy_tenant)? != tenant_id || parse_uuid(&legacy_user)? != user_id {
                return Err(ClientError::ProfileIdentityMismatch);
            }
        }
        Ok(())
    }

    fn persist_account_state(
        &self,
        session: &AccountSessionState,
        expires_at_ms: i64,
        session_token: &[u8],
        local_wrapped_master_key: &[u8],
        keys: &AccountKeyMaterial,
    ) -> Result<crate::LocalCryptoContext, ClientError> {
        let identity = LocalCryptoIdentity {
            tenant_id: parse_session_id(session.tenant_id.as_deref())?,
            user_id: parse_session_id(session.user_id.as_deref())?,
            device_id: parse_session_id(session.device_id.as_deref())?,
        };
        let crypto =
            persist_account_crypto_context(&self.db_path, &self.db_key, identity, keys, now_ms()?)?;
        store_account_secret(
            &self.db_dir,
            AccountSecretKind::MasterKeyWrap,
            local_wrapped_master_key,
        )
        .map_err(ClientError::KeyStore)?;
        self.set_setting_value(
            ACCOUNT_EMAIL_SETTING_KEY,
            session.email.as_deref().unwrap_or_default(),
        )?;
        self.set_setting_value(
            ACCOUNT_USER_ID_SETTING_KEY,
            session.user_id.as_deref().unwrap_or_default(),
        )?;
        self.set_setting_value(
            ACCOUNT_TENANT_ID_SETTING_KEY,
            session.tenant_id.as_deref().unwrap_or_default(),
        )?;
        self.set_setting_value(
            ACCOUNT_DEVICE_ID_SETTING_KEY,
            session.device_id.as_deref().unwrap_or_default(),
        )?;
        self.set_setting_value(
            ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY,
            &expires_at_ms.to_string(),
        )?;
        store_account_secret(&self.db_dir, AccountSecretKind::SessionToken, session_token)
            .map_err(ClientError::KeyStore)?;
        Ok(crypto)
    }

    fn replace_account_runtime(
        &self,
        session: Option<AccountSessionState>,
        crypto: crate::LocalCryptoContext,
    ) -> Result<(), ClientError> {
        let mut state = self.account_state()?;
        state.session = session;
        state.session_restored = true;
        state.crypto = CryptoRuntimeState::Ready(crypto);
        Ok(())
    }

    fn has_legacy_account_binding(&self) -> Result<bool, ClientError> {
        for key in [
            ACCOUNT_EMAIL_SETTING_KEY,
            ACCOUNT_USER_ID_SETTING_KEY,
            ACCOUNT_TENANT_ID_SETTING_KEY,
            ACCOUNT_DEVICE_ID_SETTING_KEY,
            ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY,
        ] {
            if self.non_empty_setting(key)?.is_some() {
                return Ok(true);
            }
        }
        for kind in [
            AccountSecretKind::MasterKeyWrap,
            AccountSecretKind::SessionToken,
        ] {
            if load_account_secret(&self.db_dir, kind)
                .map_err(ClientError::KeyStore)?
                .is_some()
            {
                return Ok(true);
            }
        }
        Ok(false)
    }
}

fn load_secret_string(
    db_dir: &std::path::Path,
    kind: AccountSecretKind,
) -> Result<Option<Zeroizing<String>>, ClientError> {
    load_account_secret(db_dir, kind)
        .map_err(ClientError::KeyStore)?
        .map(|bytes| String::from_utf8(bytes).map(Zeroizing::new))
        .transpose()
        .map_err(|_| ClientError::IncompleteAccountState)
}

fn account_session_state(
    email: String,
    user_id: String,
    tenant_id: String,
    device_id: String,
) -> AccountSessionState {
    AccountSessionState {
        logged_in: true,
        email: Some(email),
        user_id: Some(user_id),
        tenant_id: Some(tenant_id),
        device_id: Some(device_id),
    }
}

fn parse_session_id(value: Option<&str>) -> Result<Uuid, ClientError> {
    parse_uuid(value.ok_or(ClientError::IncompleteAccountState)?)
}

fn parse_uuid(value: &str) -> Result<Uuid, ClientError> {
    value
        .parse::<Uuid>()
        .map_err(|_| ClientError::IncompleteAccountState)
}

fn pending_list_key_ids_on(
    db_path: &std::path::Path,
    db_key: &[u8; 32],
    tenant_id: Uuid,
) -> Result<HashSet<Uuid>, ClientError> {
    let connection = open_encrypted(db_path, db_key)?;
    Ok(SqliteSyncStateRepository::new(connection)
        .list_pending_list_key_bundles(tenant_id, usize::MAX)?
        .into_iter()
        .map(|row| row.list_id)
        .collect())
}

pub(super) fn retained_deleted_list_key_ids_on(
    db_path: &std::path::Path,
    db_key: &[u8; 32],
) -> Result<HashSet<Uuid>, ClientError> {
    let connection = open_encrypted(db_path, db_key)?;
    let mut statement = connection
        .prepare(
            "SELECT record_id FROM sync_record_states
         WHERE collection = 'lists' AND state_kind = 'tombstone'",
        )
        .map_err(StorageError::from)?;
    let result = statement
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(StorageError::from)?
        .map(|row| {
            let value = row.map_err(StorageError::from)?;
            parse_uuid(&value)
        })
        .collect();
    result
}

fn merge_remote_and_pending_local_keys(
    mut remote: LocalSyncKeys,
    local: LocalSyncKeys,
    pending: &HashSet<Uuid>,
    retained_deleted: &HashSet<Uuid>,
) -> Result<LocalSyncKeys, ClientError> {
    for (list_id, local_dek) in local.list_deks {
        if let Some((_, remote_dek)) = remote
            .list_deks
            .iter()
            .find(|(remote_id, _)| *remote_id == list_id)
        {
            if remote_dek != &local_dek {
                return Err(ClientError::AccountBoundUnavailable);
            }
        } else if pending.contains(&list_id) || retained_deleted.contains(&list_id) {
            remote.list_deks.push((list_id, local_dek));
        } else {
            return Err(ClientError::AccountBoundUnavailable);
        }
    }
    remote.list_deks.sort_by_key(|(list_id, _)| *list_id);
    remote.list_deks.dedup_by_key(|(list_id, _)| *list_id);
    Ok(remote)
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;
    use todori_domain::new_list;
    use todori_storage::{ListRepository, SqliteListRepository};
    use todori_sync::LocalSyncStore;

    use super::*;
    use crate::{LocalMutationContext, SqliteMutationService, SqliteSyncStore};

    #[test]
    fn remote_key_refresh_preserves_only_verified_pending_local_keys() {
        let remote_id = Uuid::now_v7();
        let pending_id = Uuid::now_v7();
        let remote = LocalSyncKeys {
            list_deks: vec![(remote_id, [0x11; 32])],
        };
        let local = LocalSyncKeys {
            list_deks: vec![(remote_id, [0x11; 32]), (pending_id, [0x22; 32])],
        };
        let merged = merge_remote_and_pending_local_keys(
            remote,
            local,
            &HashSet::from([pending_id]),
            &HashSet::new(),
        )
        .unwrap();
        assert!(merged.contains_list(remote_id));
        assert!(merged.contains_list(pending_id));
    }

    #[test]
    fn remote_key_refresh_rejects_mismatch_and_unqueued_local_only_keys() {
        let list_id = Uuid::now_v7();
        assert!(merge_remote_and_pending_local_keys(
            LocalSyncKeys {
                list_deks: vec![(list_id, [0x11; 32])],
            },
            LocalSyncKeys {
                list_deks: vec![(list_id, [0x22; 32])],
            },
            &HashSet::new(),
            &HashSet::new(),
        )
        .is_err());
        assert!(merge_remote_and_pending_local_keys(
            LocalSyncKeys::default(),
            LocalSyncKeys {
                list_deks: vec![(list_id, [0x22; 32])],
            },
            &HashSet::new(),
            &HashSet::new(),
        )
        .is_err());
    }

    #[test]
    fn remote_key_refresh_retains_tombstoned_list_key_for_late_descendants() {
        let list_id = Uuid::now_v7();
        let merged = merge_remote_and_pending_local_keys(
            LocalSyncKeys::default(),
            LocalSyncKeys {
                list_deks: vec![(list_id, [0x33; 32])],
            },
            &HashSet::new(),
            &HashSet::from([list_id]),
        )
        .unwrap();
        assert!(merged.contains_list(list_id));
    }

    #[test]
    fn logout_restart_relogin_reconciliation_keeps_durable_pending_list_key() {
        const DB_KEY: [u8; 32] = [0x91; 32];
        const MASTER_KEY: [u8; 32] = [0x92; 32];
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("relogin.sqlite3");
        let tenant_id = Uuid::now_v7();
        let initial = new_list(
            "Initial".to_string(),
            "3fffffffffffffffffffffffffffffff".to_string(),
            10,
        )
        .unwrap();
        SqliteListRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .insert(initial.clone())
            .unwrap();
        let initial_keys = LocalSyncKeys {
            list_deks: vec![(initial.id, [0x93; 32])],
        };
        persist_local_crypto_context(
            &db_path,
            &DB_KEY,
            LocalCryptoIdentity {
                tenant_id,
                user_id: Uuid::now_v7(),
                device_id: Uuid::now_v7(),
            },
            &MASTER_KEY,
            initial_keys.clone(),
            10,
        )
        .unwrap();
        let created = SqliteMutationService::new(db_path.clone(), DB_KEY)
            .create_list(
                "Offline after logout".to_string(),
                11,
                tenant_id,
                &MASTER_KEY,
                &LocalMutationContext {
                    device_id: "device".to_string(),
                    keys: initial_keys.clone(),
                },
            )
            .unwrap();

        let LocalCryptoAvailability::Ready(restarted) =
            load_local_crypto_context(&db_path, &DB_KEY, Some(MASTER_KEY)).unwrap()
        else {
            panic!("restarted local crypto context");
        };
        let pending = pending_list_key_ids_on(&db_path, &DB_KEY, tenant_id).unwrap();
        let merged = merge_remote_and_pending_local_keys(
            initial_keys,
            restarted.sync_keys().clone(),
            &pending,
            &HashSet::new(),
        )
        .unwrap();
        assert!(pending.contains(&created.id));
        assert!(merged.contains_list(created.id));
    }

    #[test]
    fn authentication_completion_never_deletes_initial_backfill_cursor() {
        const DB_KEY: [u8; 32] = [0x71; 32];
        const MASTER_KEY: [u8; 32] = [0x72; 32];
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("cursor.sqlite3");
        let identity = LocalCryptoIdentity {
            tenant_id: Uuid::now_v7(),
            user_id: Uuid::now_v7(),
            device_id: Uuid::now_v7(),
        };
        let crypto = persist_local_crypto_context(
            &db_path,
            &DB_KEY,
            identity,
            &MASTER_KEY,
            LocalSyncKeys::default(),
            1,
        )
        .unwrap();
        let mut store = SqliteSyncStore::new(db_path.clone(), DB_KEY);
        store
            .set_cursor(super::super::INITIAL_BACKFILL_CURSOR_NAME, 1, 10)
            .unwrap();

        let client = TodoriClient {
            db_dir: temp.path().to_path_buf(),
            db_path,
            db_key: Zeroizing::new(DB_KEY),
            account: std::sync::Mutex::new(super::super::AccountRuntimeState {
                session: None,
                session_restored: false,
                crypto: CryptoRuntimeState::Unloaded,
            }),
            sync: std::sync::Mutex::new(super::super::SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        };
        client
            .replace_account_runtime(
                Some(account_session_state(
                    "user@example.com".into(),
                    identity.user_id.to_string(),
                    identity.tenant_id.to_string(),
                    identity.device_id.to_string(),
                )),
                crypto,
            )
            .unwrap();

        // Runtime replacement is the final login/register boundary. It must
        // not reset durable backfill progress for a same-profile relogin.
        assert_eq!(
            store
                .get_cursor_seq(super::super::INITIAL_BACKFILL_CURSOR_NAME)
                .unwrap(),
            Some(1)
        );
    }
}
