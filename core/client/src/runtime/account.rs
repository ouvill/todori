use std::collections::HashSet;

use base64::{engine::general_purpose::STANDARD, Engine as _};
use taskveil_crypto::{
    delete_account_secret,
    key_hierarchy::{
        unwrap_account_root_private_key_with_master_key, unwrap_master_key_with_device_key,
        wrap_account_root_private_key_with_master_key, INITIAL_KEY_GENERATION,
    },
    load_account_secret,
    organization::{
        AccountRootPrivateKeys, AccountRootPublicKeys, DeviceCertificate, DeviceIdentity,
        SignedDeviceRevocation,
    },
    store_account_secret, AccountSecretKind, LocalKeyCapsuleSlot, LocalKeyCapsuleStore,
    PlatformLocalKeyCapsuleStore,
};
use taskveil_domain::Uuid;
use taskveil_storage::{
    open_encrypted, ListRepository, LocalCryptoRepository, RecurrenceRepository,
    SqliteLocalCryptoRepository, SqliteSyncStateRepository, StorageError, TaskRepository,
    TimerSessionRepository,
};
use taskveil_sync::{
    account::{
        unwrap_active_key_bundle, unwrap_historical_key_bundles, AccountClient, AccountClientError,
        AccountKeyMaterial, AccountListDekMaterial, BillingResponseDto, OrganizationRosterTrust,
    },
    organization::verify_organization_active_bundle,
    LocalMutationSyncStore, LocalSyncAtomicStore, LocalSyncKeys, LocalSyncWriteTransaction,
};
use zeroize::Zeroizing;

use super::{
    now_ms, CryptoRuntimeState, TaskveilClient, ACCOUNT_DEVICE_ID_SETTING_KEY,
    ACCOUNT_EMAIL_SETTING_KEY, ACCOUNT_MK_GENERATION_SETTING_KEY, ACCOUNT_ROOT_PUBLIC_SETTING_KEY,
    ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY, ACCOUNT_TENANT_ID_SETTING_KEY,
    ACCOUNT_USER_ID_SETTING_KEY,
};
use crate::{
    load_local_crypto_context, persist_account_crypto_context, persist_local_crypto_context,
    AccountAuthResult, AccountSessionState, BillingState, ClientError, LocalCryptoAvailability,
    LocalCryptoIdentity, LocalCryptoUnavailable, OrganizationSafetyState,
};

enum AccountAuthMode {
    Register,
    Login,
}

const BILLING_ENTITLEMENT_CACHE_SETTING_KEY: &str = "billing_entitlement_cache";

#[derive(Clone, Debug, PartialEq, Eq)]
struct OrganizationTrustPin {
    owner_root_public: String,
    member_root_public: String,
    digest: String,
    locally_confirmed: bool,
    minimum_generation: u64,
    required_generation: u64,
    owner_roster_revision: u64,
    owner_roster_head_hash: String,
    member_roster_revision: u64,
    member_roster_head_hash: String,
}

impl OrganizationTrustPin {
    fn candidate(response: &taskveil_sync::organization::OrganizationSafetyResponse) -> Self {
        Self {
            owner_root_public: response.owner_root_public.clone(),
            member_root_public: response.member_root_public.clone(),
            digest: response.digest.clone(),
            locally_confirmed: false,
            minimum_generation: 1,
            required_generation: 0,
            owner_roster_revision: 0,
            owner_roster_head_hash: STANDARD.encode([0u8; 32]),
            member_roster_revision: 0,
            member_roster_head_hash: STANDARD.encode([0u8; 32]),
        }
    }

    fn matches(&self, response: &taskveil_sync::organization::OrganizationSafetyResponse) -> bool {
        self.owner_root_public == response.owner_root_public
            && self.member_root_public == response.member_root_public
            && self.digest == response.digest
    }

    fn encode(&self) -> String {
        format!(
            "{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
            self.owner_root_public,
            self.member_root_public,
            self.digest,
            u8::from(self.locally_confirmed),
            self.minimum_generation,
            self.required_generation,
            self.owner_roster_revision,
            self.owner_roster_head_hash,
            self.member_roster_revision,
            self.member_roster_head_hash
        )
    }

    fn decode(value: &str) -> Option<Self> {
        let mut fields = value.split('|');
        let result = Self {
            owner_root_public: fields.next()?.to_string(),
            member_root_public: fields.next()?.to_string(),
            digest: fields.next()?.to_string(),
            locally_confirmed: match fields.next()? {
                "0" => false,
                "1" => true,
                _ => return None,
            },
            minimum_generation: fields.next()?.parse().ok()?,
            required_generation: fields.next()?.parse().ok()?,
            owner_roster_revision: fields.next()?.parse().ok()?,
            owner_roster_head_hash: fields.next()?.to_string(),
            member_roster_revision: fields.next()?.parse().ok()?,
            member_roster_head_hash: fields.next()?.to_string(),
        };
        if fields.next().is_some()
            || result.owner_root_public.is_empty()
            || result.member_root_public.is_empty()
            || result.digest.is_empty()
            || result.minimum_generation == 0
            || (result.required_generation != 0
                && result.required_generation <= result.minimum_generation)
            || STANDARD.decode(&result.owner_roster_head_hash).ok()?.len() != 32
            || STANDARD.decode(&result.member_roster_head_hash).ok()?.len() != 32
        {
            return None;
        }
        Some(result)
    }
}

fn organization_safety_state(
    mut response: taskveil_sync::organization::OrganizationSafetyResponse,
    locally_verified: bool,
) -> OrganizationSafetyState {
    if !locally_verified {
        response.verification_state = "unverified".to_string();
    }
    OrganizationSafetyState {
        owner_user_id: response.owner_user_id.to_string(),
        member_user_id: response.member_user_id.to_string(),
        digest: response.digest,
        decimal: response.decimal,
        qr_payload: response.qr_payload,
        verification_state: response.verification_state,
        owner_confirmed: response.owner_confirmed,
        member_confirmed: response.member_confirmed,
    }
}

fn decode_trust_hash(value: &str) -> Result<[u8; 32], ClientError> {
    STANDARD
        .decode(value)
        .map_err(|_| ClientError::AccountRequest)?
        .try_into()
        .map_err(|_| ClientError::AccountRequest)
}

fn decode_trust_root(value: &str) -> Result<AccountRootPublicKeys, ClientError> {
    AccountRootPublicKeys::decode(
        &STANDARD
            .decode(value)
            .map_err(|_| ClientError::AccountRequest)?,
    )
    .map_err(|_| ClientError::AccountRequest)
}

impl TaskveilClient {
    pub async fn organization_safety_number(
        &self,
        tenant_id: String,
        member_user_id: String,
    ) -> Result<OrganizationSafetyState, ClientError> {
        let _operation = self.begin_operation()?;
        self.ensure_account_runtime_restored()?;
        let tenant_id = parse_uuid(&tenant_id)?;
        let member_user_id = parse_uuid(&member_user_id)?;
        let session_token = load_secret_string(&self.db_dir, AccountSecretKind::SessionToken)?
            .ok_or(ClientError::AccountRequest)?;
        let client =
            AccountClient::new(self.sync_server_url()?).map_err(|_| ClientError::AccountRequest)?;
        let response = client
            .organization_safety_number(tenant_id, member_user_id, &session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        self.verify_local_safety_participant(&response)?;
        let locally_verified = self
            .load_organization_trust_pin(tenant_id, member_user_id)?
            .is_some_and(|pin| {
                pin.locally_confirmed
                    && pin.matches(&response)
                    && response.verification_state == "verified"
            });
        Ok(organization_safety_state(response, locally_verified))
    }

    pub async fn confirm_organization_safety_number(
        &self,
        tenant_id: String,
        member_user_id: String,
        digest: String,
    ) -> Result<OrganizationSafetyState, ClientError> {
        let _operation = self.begin_operation()?;
        self.ensure_account_runtime_restored()?;
        let tenant_id = parse_uuid(&tenant_id)?;
        let member_user_id = parse_uuid(&member_user_id)?;
        let session_token = load_secret_string(&self.db_dir, AccountSecretKind::SessionToken)?
            .ok_or(ClientError::AccountRequest)?;
        let client =
            AccountClient::new(self.sync_server_url()?).map_err(|_| ClientError::AccountRequest)?;
        let current = client
            .organization_safety_number(tenant_id, member_user_id, &session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        self.verify_local_safety_participant(&current)?;
        if current.digest != digest {
            return Err(ClientError::AccountRequest);
        }
        let response = client
            .confirm_organization_safety_number(tenant_id, member_user_id, digest, &session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        self.verify_local_safety_participant(&response)?;
        if !OrganizationTrustPin::candidate(&current).matches(&response) {
            return Err(ClientError::AccountRequest);
        }
        let mut pin = OrganizationTrustPin::candidate(&response);
        pin.locally_confirmed = true;
        self.store_organization_trust_pin(tenant_id, member_user_id, &pin)?;
        let locally_verified = response.verification_state == "verified";
        Ok(organization_safety_state(response, locally_verified))
    }

    pub async fn verify_organization_device_rosters(
        &self,
        tenant_id: String,
        member_user_id: String,
    ) -> Result<(), ClientError> {
        let _operation = self.begin_operation()?;
        self.ensure_account_runtime_restored()?;
        let tenant_id = parse_uuid(&tenant_id)?;
        let member_user_id = parse_uuid(&member_user_id)?;
        let session_token = load_secret_string(&self.db_dir, AccountSecretKind::SessionToken)?
            .ok_or(ClientError::AccountRequest)?;
        let client =
            AccountClient::new(self.sync_server_url()?).map_err(|_| ClientError::AccountRequest)?;
        let safety = client
            .organization_safety_number(tenant_id, member_user_id, &session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        self.verify_local_safety_participant(&safety)?;
        let mut pin = self
            .load_organization_trust_pin(tenant_id, member_user_id)?
            .filter(|pin| {
                pin.locally_confirmed
                    && pin.matches(&safety)
                    && safety.verification_state == "verified"
            })
            .ok_or(ClientError::AccountRequest)?;
        let owner_root = decode_trust_root(&pin.owner_root_public)?;
        let member_root = decode_trust_root(&pin.member_root_public)?;
        if member_root.user_id != member_user_id {
            return Err(ClientError::AccountRequest);
        }
        let owner = client
            .organization_owner_devices(
                tenant_id,
                member_user_id,
                OrganizationRosterTrust {
                    user_id: owner_root.user_id,
                    root_public: &pin.owner_root_public,
                    minimum_revision: pin.owner_roster_revision,
                    minimum_head_hash: decode_trust_hash(&pin.owner_roster_head_hash)?,
                },
                &session_token,
            )
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        let member = client
            .organization_member_devices(
                tenant_id,
                member_user_id,
                OrganizationRosterTrust {
                    user_id: member_root.user_id,
                    root_public: &pin.member_root_public,
                    minimum_revision: pin.member_roster_revision,
                    minimum_head_hash: decode_trust_hash(&pin.member_roster_head_hash)?,
                },
                &session_token,
            )
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        if owner.revision != pin.owner_roster_revision
            || owner.head_hash != decode_trust_hash(&pin.owner_roster_head_hash)?
            || member.revision != pin.member_roster_revision
            || member.head_hash != decode_trust_hash(&pin.member_roster_head_hash)?
        {
            pin.required_generation = pin
                .minimum_generation
                .checked_add(1)
                .ok_or(ClientError::AccountRequest)?;
        }
        pin.owner_roster_revision = owner.revision;
        pin.owner_roster_head_hash = STANDARD.encode(owner.head_hash);
        pin.member_roster_revision = member.revision;
        pin.member_roster_head_hash = STANDARD.encode(member.head_hash);
        self.store_organization_trust_pin(tenant_id, member_user_id, &pin)
    }

    pub async fn verify_organization_active_key_bundle(
        &self,
        tenant_id: String,
        member_user_id: String,
    ) -> Result<u64, ClientError> {
        let _operation = self.begin_operation()?;
        self.ensure_account_runtime_restored()?;
        let tenant_id = parse_uuid(&tenant_id)?;
        let member_user_id = parse_uuid(&member_user_id)?;
        let session_token = load_secret_string(&self.db_dir, AccountSecretKind::SessionToken)?
            .ok_or(ClientError::AccountRequest)?;
        let client =
            AccountClient::new(self.sync_server_url()?).map_err(|_| ClientError::AccountRequest)?;
        let safety = client
            .organization_safety_number(tenant_id, member_user_id, &session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        self.verify_local_safety_participant(&safety)?;
        let mut pin = self
            .load_organization_trust_pin(tenant_id, member_user_id)?
            .filter(|pin| {
                pin.locally_confirmed
                    && pin.matches(&safety)
                    && safety.verification_state == "verified"
            })
            .ok_or(ClientError::AccountRequest)?;
        let owner_root = decode_trust_root(&pin.owner_root_public)?;
        let member_root = decode_trust_root(&pin.member_root_public)?;
        if member_root.user_id != member_user_id {
            return Err(ClientError::AccountRequest);
        }
        let device_identity = DeviceIdentity::decode(
            &load_account_secret(&self.db_dir, AccountSecretKind::DeviceIdentity)
                .map_err(ClientError::KeyStore)?
                .ok_or(ClientError::AccountRequest)?,
        )
        .map_err(|_| ClientError::AccountRequest)?;
        let owner_roster = client
            .organization_owner_devices(
                tenant_id,
                member_user_id,
                OrganizationRosterTrust {
                    user_id: owner_root.user_id,
                    root_public: &pin.owner_root_public,
                    minimum_revision: pin.owner_roster_revision,
                    minimum_head_hash: decode_trust_hash(&pin.owner_roster_head_hash)?,
                },
                &session_token,
            )
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        let member_roster = client
            .organization_member_devices(
                tenant_id,
                member_user_id,
                OrganizationRosterTrust {
                    user_id: member_root.user_id,
                    root_public: &pin.member_root_public,
                    minimum_revision: pin.member_roster_revision,
                    minimum_head_hash: decode_trust_hash(&pin.member_roster_head_hash)?,
                },
                &session_token,
            )
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        if owner_roster.revision != pin.owner_roster_revision
            || owner_roster.head_hash != decode_trust_hash(&pin.owner_roster_head_hash)?
            || member_roster.revision != pin.member_roster_revision
            || member_roster.head_hash != decode_trust_hash(&pin.member_roster_head_hash)?
        {
            pin.required_generation = pin
                .minimum_generation
                .checked_add(1)
                .ok_or(ClientError::AccountRequest)?;
        }
        let expected_recipients = owner_roster
            .devices
            .iter()
            .chain(member_roster.devices.iter())
            .map(|device| {
                DeviceCertificate::decode(
                    &STANDARD
                        .decode(&device.certificate)
                        .map_err(|_| ClientError::AccountRequest)?,
                )
                .and_then(|certificate| certificate.recipient_key_fingerprint())
                .map_err(|_| ClientError::AccountRequest)
            })
            .collect::<Result<Vec<_>, _>>()?;
        let bundle = client
            .active_key_bundle(tenant_id, &session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        verify_organization_active_bundle(
            &bundle,
            tenant_id,
            pin.required_generation.max(pin.minimum_generation),
            &owner_root,
            device_identity.certificate(),
            &expected_recipients,
        )
        .map_err(|_| ClientError::AccountRequest)?;
        pin.minimum_generation = bundle.generation;
        pin.required_generation = 0;
        pin.owner_roster_revision = owner_roster.revision;
        pin.owner_roster_head_hash = STANDARD.encode(owner_roster.head_hash);
        pin.member_roster_revision = member_roster.revision;
        pin.member_roster_head_hash = STANDARD.encode(member_roster.head_hash);
        self.store_organization_trust_pin(tenant_id, member_user_id, &pin)?;
        Ok(bundle.generation)
    }

    pub async fn revoke_organization_device(
        &self,
        tenant_id: String,
        member_user_id: String,
        device_id: String,
    ) -> Result<(), ClientError> {
        let _operation = self.begin_operation()?;
        self.ensure_account_runtime_restored()?;
        let tenant_id = parse_uuid(&tenant_id)?;
        let member_user_id = parse_uuid(&member_user_id)?;
        let device_id = parse_uuid(&device_id)?;
        let local_user_id = parse_uuid(
            &self
                .non_empty_setting(ACCOUNT_USER_ID_SETTING_KEY)?
                .ok_or(ClientError::IncompleteAccountState)?,
        )?;
        let session_token = load_secret_string(&self.db_dir, AccountSecretKind::SessionToken)?
            .ok_or(ClientError::AccountRequest)?;
        let client =
            AccountClient::new(self.sync_server_url()?).map_err(|_| ClientError::AccountRequest)?;
        let safety = client
            .organization_safety_number(tenant_id, member_user_id, &session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        self.verify_local_safety_participant(&safety)?;
        let mut pin = self
            .load_organization_trust_pin(tenant_id, member_user_id)?
            .filter(|pin| {
                pin.locally_confirmed
                    && pin.matches(&safety)
                    && safety.verification_state == "verified"
            })
            .ok_or(ClientError::AccountRequest)?;
        let owner_root = decode_trust_root(&pin.owner_root_public)?;
        let member_root = decode_trust_root(&pin.member_root_public)?;
        if member_root.user_id != member_user_id {
            return Err(ClientError::AccountRequest);
        }
        let (roster, is_owner) = if safety.owner_user_id == local_user_id {
            (
                client
                    .organization_owner_devices(
                        tenant_id,
                        member_user_id,
                        OrganizationRosterTrust {
                            user_id: owner_root.user_id,
                            root_public: &pin.owner_root_public,
                            minimum_revision: pin.owner_roster_revision,
                            minimum_head_hash: decode_trust_hash(&pin.owner_roster_head_hash)?,
                        },
                        &session_token,
                    )
                    .await
                    .map_err(|_| ClientError::AccountRequest)?,
                true,
            )
        } else if safety.member_user_id == local_user_id {
            (
                client
                    .organization_member_devices(
                        tenant_id,
                        member_user_id,
                        OrganizationRosterTrust {
                            user_id: member_root.user_id,
                            root_public: &pin.member_root_public,
                            minimum_revision: pin.member_roster_revision,
                            minimum_head_hash: decode_trust_hash(&pin.member_roster_head_hash)?,
                        },
                        &session_token,
                    )
                    .await
                    .map_err(|_| ClientError::AccountRequest)?,
                false,
            )
        } else {
            return Err(ClientError::AccountRequest);
        };
        let device = roster
            .devices
            .iter()
            .find(|device| device.device_id == device_id && device.user_id == local_user_id)
            .ok_or(ClientError::AccountRequest)?;
        let certificate_fingerprint: [u8; 48] = STANDARD
            .decode(&device.certificate_fingerprint)
            .map_err(|_| ClientError::AccountRequest)?
            .try_into()
            .map_err(|_| ClientError::AccountRequest)?;
        let (root_private, root_public) = self.load_account_root_keys()?;
        let next_revision = roster
            .revision
            .checked_add(1)
            .ok_or(ClientError::AccountRequest)?;
        let statement = SignedDeviceRevocation::sign(
            &root_private,
            &root_public,
            device_id,
            certificate_fingerprint,
            next_revision,
            now_ms()?,
            roster.head_hash,
        )
        .map_err(|_| ClientError::AccountRequest)?;
        client
            .revoke_organization_device(tenant_id, device_id, &statement, &session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        pin.required_generation = pin
            .minimum_generation
            .checked_add(1)
            .ok_or(ClientError::AccountRequest)?;
        if is_owner {
            pin.owner_roster_revision = statement.revision;
            pin.owner_roster_head_hash = STANDARD.encode(
                statement
                    .authenticated_hash()
                    .map_err(|_| ClientError::AccountRequest)?,
            );
        } else {
            pin.member_roster_revision = statement.revision;
            pin.member_roster_head_hash = STANDARD.encode(
                statement
                    .authenticated_hash()
                    .map_err(|_| ClientError::AccountRequest)?,
            );
        }
        self.store_organization_trust_pin(tenant_id, member_user_id, &pin)
    }

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

    pub async fn billing_bootstrap(&self) -> Result<BillingState, ClientError> {
        let _operation = self.begin_operation()?;
        self.fetch_billing(false).await
    }

    pub async fn refresh_billing(&self) -> Result<BillingState, ClientError> {
        let _operation = self.begin_operation()?;
        self.fetch_billing(true).await
    }

    pub fn cached_billing(&self) -> Result<Option<BillingState>, ClientError> {
        self.setting(BILLING_ENTITLEMENT_CACHE_SETTING_KEY)?
            .map(|value| serde_json::from_str(&value).map_err(|_| ClientError::AccountRequest))
            .transpose()
    }

    async fn fetch_billing(&self, refresh: bool) -> Result<BillingState, ClientError> {
        self.ensure_account_runtime_restored()?;
        let session = self
            .account_state()?
            .session
            .clone()
            .filter(|session| session.logged_in)
            .ok_or(ClientError::AccountRequest)?;
        let tenant_id = parse_uuid(
            session
                .tenant_id
                .as_deref()
                .ok_or(ClientError::AccountRequest)?,
        )?;
        let token = load_secret_string(&self.db_dir, AccountSecretKind::SessionToken)?
            .ok_or(ClientError::AccountRequest)?;
        let client =
            AccountClient::new(self.sync_server_url()?).map_err(|_| ClientError::AccountRequest)?;
        let response = if refresh {
            client.refresh_billing(tenant_id, &token).await
        } else {
            client.billing(tenant_id, &token).await
        }
        .map_err(map_account_client_error)?;
        let state = billing_state(response);
        self.set_setting_value(
            BILLING_ENTITLEMENT_CACHE_SETTING_KEY,
            &serde_json::to_string(&state).map_err(|_| ClientError::AccountRequest)?,
        )?;
        Ok(state)
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
        let device_key = Zeroizing::new(*self.active_capsule()?.device_key());
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
                let encoded_identity = outcome
                    .device_identity
                    .encode()
                    .map_err(|_| ClientError::AccountRequest)?;
                store_account_secret(
                    &self.db_dir,
                    AccountSecretKind::DeviceIdentity,
                    &encoded_identity,
                )
                .map_err(ClientError::KeyStore)?;
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
                let encoded_identity = outcome
                    .device_identity
                    .encode()
                    .map_err(|_| ClientError::AccountRequest)?;
                store_account_secret(
                    &self.db_dir,
                    AccountSecretKind::DeviceIdentity,
                    &encoded_identity,
                )
                .map_err(ClientError::KeyStore)?;
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

    pub(crate) fn ensure_account_runtime_restored(&self) -> Result<(), ClientError> {
        let restore_crypto = matches!(self.account_state()?.crypto, CryptoRuntimeState::Unloaded);
        if restore_crypto {
            let active_capsule = self.active_capsule()?;
            let master_key = match active_capsule.wrapped_master_key() {
                Some(local_wrapped_master_key) => {
                    let user_id = self
                        .non_empty_setting(ACCOUNT_USER_ID_SETTING_KEY)?
                        .ok_or(ClientError::IncompleteAccountState)
                        .and_then(|value| parse_uuid(&value))?;
                    let device_key = Zeroizing::new(*active_capsule.device_key());
                    unwrap_master_key_with_device_key(
                        user_id,
                        INITIAL_KEY_GENERATION,
                        local_wrapped_master_key,
                        &device_key,
                    )
                    .ok()
                }
                None => None,
            };
            let availability =
                load_local_crypto_context(&self.db_path, &self.db_key(), master_key)?;
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
        let bundle = client
            .active_key_bundle(tenant_id, &session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        let (tenant_root_dek, materials) =
            unwrap_active_key_bundle(tenant_id, &bundle, &master_key)
                .map_err(|_| ClientError::AccountBoundUnavailable)?;
        let historical =
            unwrap_historical_key_bundles(tenant_id, &bundle.migrating_generations, &master_key)
                .map_err(|_| ClientError::AccountBoundUnavailable)?;
        let list_generations = materials
            .iter()
            .map(|material| Ok((parse_uuid(&material.list_id)?, material.generation)))
            .collect::<Result<Vec<_>, ClientError>>()?;
        let remote_keys = LocalSyncKeys {
            tenant_id,
            list_deks: materials
                .into_iter()
                .map(|material| Ok((parse_uuid(&material.list_id)?, material.dek)))
                .collect::<Result<Vec<_>, ClientError>>()?,
            list_generations,
            tenant_root_dek: Some(tenant_root_dek),
            tenant_generation: bundle.generation,
            historical_list_deks: historical
                .iter()
                .flat_map(|historical| {
                    historical.list_deks.iter().map(|material| {
                        Ok((
                            parse_uuid(&material.list_id)?,
                            material.generation,
                            material.dek.clone(),
                        ))
                    })
                })
                .collect::<Result<Vec<_>, ClientError>>()?,
            historical_tenant_root_deks: historical
                .into_iter()
                .map(|historical| (historical.generation, historical.tenant_root_dek))
                .collect(),
        };
        let local_keys = {
            let account = self.account_state()?;
            let CryptoRuntimeState::Ready(crypto) = &account.crypto else {
                return Err(ClientError::AccountBoundUnavailable);
            };
            crypto.sync_keys().clone()
        };
        let previous_generation = local_keys.tenant_generation;
        let pending = self.pending_list_key_ids(tenant_id)?;
        let retained = retained_deleted_list_key_ids_on(&self.db_path, &self.db_key())?;
        let sync_keys =
            merge_remote_and_pending_local_keys(remote_keys, local_keys, &pending, &retained)?;
        if sync_keys.tenant_generation > previous_generation {
            if !pending.is_empty() {
                return Err(ClientError::AccountBoundUnavailable);
            }
            let lists = self.local_lists_including_archived()?;
            let templates =
                self.with_recurrence_repository(|repository| Ok(repository.list_templates()?))?;
            let schedules =
                self.with_recurrence_repository(|repository| Ok(repository.list_schedules()?))?;
            let tasks =
                self.with_task_repository(|repository| Ok(repository.list_all_for_sync()?))?;
            let timer_sessions =
                self.with_timer_repository(|repository| Ok(repository.list_completed()?))?;
            if lists.iter().any(|list| !sync_keys.contains_list(list.id)) {
                return Err(ClientError::AccountBoundUnavailable);
            }
            let mut store = crate::SqliteSyncStore::new_secret(self.db_path.clone(), self.db_key());
            let mut transaction = store
                .begin_write_transaction()
                .map_err(|_| ClientError::SyncRun)?;
            let mut clock = || now_ms().map_err(|error| error.to_string());
            taskveil_sync::enqueue_rotation_backfill(
                &mut transaction,
                &sync_keys,
                &device_id.to_string(),
                taskveil_sync::BackfillRecords {
                    lists: &lists,
                    templates: &templates,
                    schedules: &schedules,
                    tasks: &tasks,
                    timer_sessions: &timer_sessions,
                },
                &mut clock,
            )
            .map_err(|_| ClientError::SyncRun)?;
            transaction.commit().map_err(|_| ClientError::SyncRun)?;
        }
        let crypto = persist_local_crypto_context(
            &self.db_path,
            &self.db_key(),
            LocalCryptoIdentity {
                tenant_id,
                user_id,
                device_id,
            },
            &master_key,
            sync_keys.clone(),
            now_ms()?,
        )?;
        let mut marker_store =
            crate::SqliteSyncStore::new_secret(self.db_path.clone(), self.db_key());
        marker_store
            .set_setting(
                taskveil_sync::KEY_ROTATION_PENDING_SETTING_KEY,
                "0",
                now_ms()?,
            )
            .map_err(|_| ClientError::SyncRun)?;
        self.account_state()?.crypto = CryptoRuntimeState::Ready(Box::new(crypto));
        Ok(sync_keys)
    }

    pub(super) fn local_lists_including_archived(
        &self,
    ) -> Result<Vec<taskveil_domain::List>, ClientError> {
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
        match load_local_crypto_context(&self.db_path, &self.db_key(), Some(*keys.master_key))? {
            LocalCryptoAvailability::Ready(local) => {
                let pending = self.pending_list_key_ids(tenant_id)?;
                let retained = retained_deleted_list_key_ids_on(&self.db_path, &self.db_key())?;
                let merged = merge_remote_and_pending_local_keys(
                    LocalSyncKeys::from_account_keys(tenant_id, keys),
                    local.sync_keys().clone(),
                    &pending,
                    &retained,
                )?;
                keys.generation = merged.tenant_generation;
                let list_generations = merged.list_generations;
                keys.list_deks = merged
                    .list_deks
                    .into_iter()
                    .map(|(list_id, dek)| AccountListDekMaterial {
                        list_id: list_id.to_string(),
                        generation: list_generations
                            .iter()
                            .find(|(id, _)| *id == list_id)
                            .map(|(_, generation)| *generation)
                            .unwrap_or(INITIAL_KEY_GENERATION),
                        dek,
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
            if let Some(material) = taskveil_sync::ensure_list_dek_for_list(
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
        pending_list_key_ids_on(&self.db_path, &self.db_key(), tenant_id)
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
        let connection = open_encrypted(&self.db_path, &self.db_key())?;
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

    fn verify_local_safety_participant(
        &self,
        response: &taskveil_sync::organization::OrganizationSafetyResponse,
    ) -> Result<(), ClientError> {
        let local_user_id = parse_uuid(
            &self
                .non_empty_setting(ACCOUNT_USER_ID_SETTING_KEY)?
                .ok_or(ClientError::IncompleteAccountState)?,
        )?;
        let local_root = self
            .non_empty_setting(ACCOUNT_ROOT_PUBLIC_SETTING_KEY)?
            .ok_or(ClientError::IncompleteAccountState)?;
        let expected_local_root = if response.owner_user_id == local_user_id {
            &response.owner_root_public
        } else if response.member_user_id == local_user_id {
            &response.member_root_public
        } else {
            return Err(ClientError::AccountRequest);
        };
        if expected_local_root != &local_root {
            return Err(ClientError::AccountRequest);
        }
        let decoded = AccountRootPublicKeys::decode(
            &STANDARD
                .decode(local_root)
                .map_err(|_| ClientError::AccountRequest)?,
        )
        .map_err(|_| ClientError::AccountRequest)?;
        if decoded.user_id != local_user_id {
            return Err(ClientError::AccountRequest);
        }
        Ok(())
    }

    fn organization_trust_pin_key(tenant_id: Uuid, member_user_id: Uuid) -> String {
        format!("organization_trust:{tenant_id}:{member_user_id}")
    }

    fn load_organization_trust_pin(
        &self,
        tenant_id: Uuid,
        member_user_id: Uuid,
    ) -> Result<Option<OrganizationTrustPin>, ClientError> {
        let Some(value) =
            self.setting(&Self::organization_trust_pin_key(tenant_id, member_user_id))?
        else {
            return Ok(None);
        };
        OrganizationTrustPin::decode(&value)
            .map(Some)
            .ok_or(ClientError::AccountRequest)
    }

    fn store_organization_trust_pin(
        &self,
        tenant_id: Uuid,
        member_user_id: Uuid,
        pin: &OrganizationTrustPin,
    ) -> Result<(), ClientError> {
        self.set_setting_value(
            &Self::organization_trust_pin_key(tenant_id, member_user_id),
            &pin.encode(),
        )
    }

    fn load_account_root_keys(
        &self,
    ) -> Result<(AccountRootPrivateKeys, AccountRootPublicKeys), ClientError> {
        let (user_id, master_key) = {
            let state = self.account_state()?;
            let CryptoRuntimeState::Ready(crypto) = &state.crypto else {
                return Err(ClientError::AccountBoundUnavailable);
            };
            (crypto.user_id(), Zeroizing::new(*crypto.master_key()))
        };
        let generation = self
            .non_empty_setting(ACCOUNT_MK_GENERATION_SETTING_KEY)?
            .ok_or(ClientError::IncompleteAccountState)?
            .parse::<u64>()
            .map_err(|_| ClientError::IncompleteAccountState)?;
        let wrapped = load_account_secret(&self.db_dir, AccountSecretKind::WrappedAccountRoot)
            .map_err(ClientError::KeyStore)?
            .ok_or(ClientError::IncompleteAccountState)?;
        let private_bytes = unwrap_account_root_private_key_with_master_key(
            user_id,
            generation,
            &wrapped,
            &master_key,
        )
        .map_err(|_| ClientError::AccountBoundUnavailable)?;
        let private = AccountRootPrivateKeys::decode(&*private_bytes)
            .map_err(|_| ClientError::AccountBoundUnavailable)?;
        let public = AccountRootPublicKeys::decode(
            &STANDARD
                .decode(
                    self.non_empty_setting(ACCOUNT_ROOT_PUBLIC_SETTING_KEY)?
                        .ok_or(ClientError::IncompleteAccountState)?,
                )
                .map_err(|_| ClientError::IncompleteAccountState)?,
        )
        .map_err(|_| ClientError::IncompleteAccountState)?;
        if private
            .public_keys(user_id)
            .map_err(|_| ClientError::AccountBoundUnavailable)?
            != public
        {
            return Err(ClientError::AccountBoundUnavailable);
        }
        Ok((private, public))
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
        let crypto = persist_account_crypto_context(
            &self.db_path,
            &self.db_key(),
            identity,
            keys,
            now_ms()?,
        )?;
        self.store_active_wrapped_master_key(local_wrapped_master_key.to_vec())?;
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
        self.set_setting_value(
            ACCOUNT_ROOT_PUBLIC_SETTING_KEY,
            &STANDARD.encode(
                keys.account_root_public
                    .encode()
                    .map_err(|_| ClientError::AccountBoundUnavailable)?,
            ),
        )?;
        self.set_setting_value(
            ACCOUNT_MK_GENERATION_SETTING_KEY,
            &keys.generation.to_string(),
        )?;
        store_account_secret(&self.db_dir, AccountSecretKind::SessionToken, session_token)
            .map_err(ClientError::KeyStore)?;
        let root_private = keys.account_root_private.encode();
        let wrapped_root = wrap_account_root_private_key_with_master_key(
            identity.user_id,
            keys.generation,
            &root_private,
            &keys.master_key,
        )
        .map_err(|_| ClientError::AccountBoundUnavailable)?;
        store_account_secret(
            &self.db_dir,
            AccountSecretKind::WrappedAccountRoot,
            &wrapped_root,
        )
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
        state.crypto = CryptoRuntimeState::Ready(Box::new(crypto));
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
        if self.active_capsule()?.wrapped_master_key().is_some() {
            return Ok(true);
        }
        Ok(false)
    }

    fn active_capsule(&self) -> Result<taskveil_crypto::LocalKeyCapsule, ClientError> {
        PlatformLocalKeyCapsuleStore::new(&self.db_dir)
            .load(LocalKeyCapsuleSlot::Active)
            .map_err(ClientError::KeyStore)?
            .ok_or(ClientError::LocalKeyState)
    }

    fn store_active_wrapped_master_key(
        &self,
        wrapped_master_key: Vec<u8>,
    ) -> Result<(), ClientError> {
        let mut store = PlatformLocalKeyCapsuleStore::new(&self.db_dir);
        let active = store
            .load(LocalKeyCapsuleSlot::Active)
            .map_err(ClientError::KeyStore)?
            .ok_or(ClientError::LocalKeyState)?;
        let updated = active
            .with_wrapped_master_key(Some(wrapped_master_key))
            .map_err(ClientError::KeyStore)?;
        store
            .store(LocalKeyCapsuleSlot::Active, &updated)
            .map_err(ClientError::KeyStore)
    }
}

fn map_account_client_error(error: AccountClientError) -> ClientError {
    match error {
        AccountClientError::EntitlementRequired => ClientError::EntitlementRequired,
        _ => ClientError::AccountRequest,
    }
}

fn billing_state(response: BillingResponseDto) -> BillingState {
    BillingState {
        provider: response.provider,
        provider_app_user_id: response.provider_app_user_id.to_string(),
        lookup_key: response.entitlement.lookup_key,
        status: response.entitlement.status,
        sync_allowed: response.entitlement.sync_allowed,
        store_product_identifier: response.entitlement.store_product_identifier,
        expires_at: response.entitlement.expires_at,
        grace_expires_at: response.entitlement.grace_expires_at,
        will_renew: response.entitlement.will_renew,
        environment: response.entitlement.environment,
        updated_at: response.entitlement.updated_at,
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
    if remote.tenant_id != local.tenant_id || remote.tenant_generation < local.tenant_generation {
        return Err(ClientError::AccountBoundUnavailable);
    }
    let local_generations = local.list_generations;
    for (list_id, local_dek) in local.list_deks {
        if let Some((_, remote_dek)) = remote
            .list_deks
            .iter()
            .find(|(remote_id, _)| *remote_id == list_id)
        {
            let remote_generation = remote
                .generation_for_list(list_id)
                .ok_or(ClientError::AccountBoundUnavailable)?;
            let local_generation = local_generations
                .iter()
                .find(|(id, _)| *id == list_id)
                .map(|(_, generation)| *generation)
                .ok_or(ClientError::AccountBoundUnavailable)?;
            if remote_generation < local_generation
                || (remote_generation == local_generation && remote_dek != &local_dek)
            {
                return Err(ClientError::AccountBoundUnavailable);
            }
        } else if pending.contains(&list_id) || retained_deleted.contains(&list_id) {
            let local_generation = local_generations
                .iter()
                .find(|(id, _)| *id == list_id)
                .map(|(_, generation)| *generation)
                .ok_or(ClientError::AccountBoundUnavailable)?;
            remote.list_deks.push((list_id, local_dek));
            remote.list_generations.push((list_id, local_generation));
        } else {
            return Err(ClientError::AccountBoundUnavailable);
        }
    }
    remote.list_deks.sort_by_key(|(list_id, _)| *list_id);
    remote.list_deks.dedup_by_key(|(list_id, _)| *list_id);
    remote.list_generations.sort_by_key(|(list_id, _)| *list_id);
    remote
        .list_generations
        .dedup_by_key(|(list_id, _)| *list_id);
    Ok(remote)
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use taskveil_domain::new_list;
    use taskveil_storage::{ListRepository, SqliteListRepository};
    use taskveil_sync::LocalSyncStore;
    use tempfile::TempDir;

    use super::*;
    use crate::{LocalMutationContext, SqliteMutationService, SqliteSyncStore};

    fn open_test_client(db_dir: &std::path::Path, db_key: [u8; 32]) -> TaskveilClient {
        let db_path = db_dir.join("taskveil.db");
        drop(open_encrypted(&db_path, &db_key).expect("open encrypted test database"));
        TaskveilClient {
            db_dir: db_dir.to_path_buf(),
            db_path,
            db_key: Mutex::new(Zeroizing::new(db_key)),
            account: Mutex::new(super::super::AccountRuntimeState {
                session: None,
                session_restored: false,
                crypto: CryptoRuntimeState::Anonymous,
            }),
            sync: Mutex::new(super::super::SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        }
    }

    #[test]
    fn billing_cache_round_trips_through_encrypted_profile_and_rejects_corruption() {
        let temp = TempDir::new().expect("temp profile");
        let db_key = [0x42; 32];
        let expected = BillingState {
            provider: "revenuecat".to_string(),
            provider_app_user_id: "00000000-0000-4000-8000-000000000001".to_string(),
            lookup_key: "pro".to_string(),
            status: "in_grace_period".to_string(),
            sync_allowed: true,
            store_product_identifier: Some("com.taskveil.app.pro.monthly".to_string()),
            expires_at: Some(1_800_000_000_000),
            grace_expires_at: Some(1_801_382_400_000),
            will_renew: Some(false),
            environment: "sandbox".to_string(),
            updated_at: Some(1_799_999_999_000),
        };

        let client = open_test_client(temp.path(), db_key);
        client
            .set_setting_value(
                BILLING_ENTITLEMENT_CACHE_SETTING_KEY,
                &serde_json::to_string(&expected).expect("serialize billing state"),
            )
            .expect("persist billing cache");
        assert_eq!(
            client.cached_billing().expect("read cache"),
            Some(expected.clone())
        );
        drop(client);

        let reopened = open_test_client(temp.path(), db_key);
        assert_eq!(
            reopened.cached_billing().expect("read reopened cache"),
            Some(expected)
        );
        reopened
            .set_setting_value(BILLING_ENTITLEMENT_CACHE_SETTING_KEY, "{not-json")
            .expect("persist corrupt cache fixture");
        assert!(matches!(
            reopened.cached_billing(),
            Err(ClientError::AccountRequest)
        ));
    }

    #[test]
    fn organization_trust_pin_is_strict_and_root_changes_require_reconfirmation() {
        let owner = Uuid::now_v7();
        let member = Uuid::now_v7();
        let response = taskveil_sync::organization::OrganizationSafetyResponse {
            owner_user_id: owner,
            member_user_id: member,
            owner_root_public: "owner-root".to_string(),
            member_root_public: "member-root".to_string(),
            digest: "digest".to_string(),
            decimal: "decimal".to_string(),
            qr_payload: "qr".to_string(),
            verification_state: "verified".to_string(),
            owner_confirmed: true,
            member_confirmed: true,
        };
        let mut pin = OrganizationTrustPin::candidate(&response);
        pin.locally_confirmed = true;
        pin.minimum_generation = 7;
        pin.owner_roster_revision = 3;
        pin.member_roster_revision = 4;
        assert_eq!(
            OrganizationTrustPin::decode(&pin.encode()),
            Some(pin.clone())
        );
        assert!(pin.matches(&response));

        let mut substituted = response;
        substituted.member_root_public = "server-substituted-root".to_string();
        assert!(!pin.matches(&substituted));
        assert!(OrganizationTrustPin::decode("partial|pin").is_none());
        assert!(OrganizationTrustPin::decode("a|b|c|1|0|0|0").is_none());
    }

    #[test]
    fn remote_key_refresh_preserves_only_verified_pending_local_keys() {
        let remote_id = Uuid::now_v7();
        let pending_id = Uuid::now_v7();
        let tenant_id = Uuid::now_v7();
        let remote = LocalSyncKeys {
            tenant_id,
            list_deks: vec![(remote_id, [0x11; 32].into())],
            list_generations: vec![(remote_id, 1)],
            tenant_root_dek: None,
            tenant_generation: 1,
            historical_list_deks: Vec::new(),
            historical_tenant_root_deks: Vec::new(),
        };
        let local = LocalSyncKeys {
            tenant_id,
            list_deks: vec![
                (remote_id, [0x11; 32].into()),
                (pending_id, [0x22; 32].into()),
            ],
            list_generations: vec![(remote_id, 1), (pending_id, 1)],
            tenant_root_dek: None,
            tenant_generation: 1,
            historical_list_deks: Vec::new(),
            historical_tenant_root_deks: Vec::new(),
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
        let tenant_id = Uuid::now_v7();
        assert!(merge_remote_and_pending_local_keys(
            LocalSyncKeys {
                tenant_id,
                list_deks: vec![(list_id, [0x11; 32].into())],
                list_generations: vec![(list_id, 1)],
                tenant_root_dek: None,
                tenant_generation: 1,
                historical_list_deks: Vec::new(),
                historical_tenant_root_deks: Vec::new(),
            },
            LocalSyncKeys {
                tenant_id,
                list_deks: vec![(list_id, [0x22; 32].into())],
                list_generations: vec![(list_id, 1)],
                tenant_root_dek: None,
                tenant_generation: 1,
                historical_list_deks: Vec::new(),
                historical_tenant_root_deks: Vec::new(),
            },
            &HashSet::new(),
            &HashSet::new(),
        )
        .is_err());
        assert!(merge_remote_and_pending_local_keys(
            LocalSyncKeys {
                tenant_id,
                ..LocalSyncKeys::default()
            },
            LocalSyncKeys {
                tenant_id,
                list_deks: vec![(list_id, [0x22; 32].into())],
                list_generations: vec![(list_id, 1)],
                tenant_root_dek: None,
                tenant_generation: 1,
                historical_list_deks: Vec::new(),
                historical_tenant_root_deks: Vec::new(),
            },
            &HashSet::new(),
            &HashSet::new(),
        )
        .is_err());
    }

    #[test]
    fn remote_key_refresh_retains_tombstoned_list_key_for_late_descendants() {
        let list_id = Uuid::now_v7();
        let tenant_id = Uuid::now_v7();
        let merged = merge_remote_and_pending_local_keys(
            LocalSyncKeys {
                tenant_id,
                ..LocalSyncKeys::default()
            },
            LocalSyncKeys {
                tenant_id,
                list_deks: vec![(list_id, [0x33; 32].into())],
                list_generations: vec![(list_id, 1)],
                tenant_root_dek: None,
                tenant_generation: 1,
                historical_list_deks: Vec::new(),
                historical_tenant_root_deks: Vec::new(),
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
            tenant_id,
            list_deks: vec![(initial.id, [0x93; 32].into())],
            list_generations: vec![(initial.id, 1)],
            tenant_root_dek: Some(Zeroizing::new([0x94; 32])),
            tenant_generation: 1,
            historical_list_deks: Vec::new(),
            historical_tenant_root_deks: Vec::new(),
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
            LocalSyncKeys {
                tenant_id: identity.tenant_id,
                list_deks: Vec::new(),
                list_generations: Vec::new(),
                tenant_root_dek: Some(Zeroizing::new([0x73; 32])),
                tenant_generation: 1,
                historical_list_deks: Vec::new(),
                historical_tenant_root_deks: Vec::new(),
            },
            1,
        )
        .unwrap();
        let mut store = SqliteSyncStore::new(db_path.clone(), DB_KEY);
        store
            .set_cursor(super::super::INITIAL_BACKFILL_CURSOR_NAME, 1, 10)
            .unwrap();

        let client = TaskveilClient {
            db_dir: temp.path().to_path_buf(),
            db_path,
            db_key: Mutex::new(Zeroizing::new(DB_KEY)),
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
