//! Account registration/login client and key bundle DTOs.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::{DateTime, Utc};
use opaque_ke::{ClientLogin, ClientRegistration, CredentialResponse, RegistrationResponse};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use todori_crypto::{
    key_hierarchy::{
        derive_kek_pw, derive_recovery_wrap_key, generate_device_public_key, generate_list_dek,
        generate_master_key, generate_recovery_key, generate_tenant_root_dek,
        generate_user_x25519_key_pair, unwrap_list_dek_with_master_key,
        unwrap_master_key_with_kek_pw, unwrap_tenant_root_dek_with_master_key,
        unwrap_user_secret_key_with_master_key, wrap_list_dek_with_master_key,
        wrap_master_key_with_device_key, wrap_master_key_with_kek_pw,
        wrap_master_key_with_recovery_key, wrap_tenant_root_dek_with_master_key,
        wrap_user_secret_key_with_master_key, KeyHierarchyError, KEY_LEN,
    },
    TodoriCipherSuite,
};
use uuid::Uuid;
use zeroize::{Zeroize, Zeroizing};

#[derive(Debug, Error)]
pub enum AccountClientError {
    #[error("server URL is empty")]
    EmptyServerUrl,
    #[error("HTTP request failed")]
    Http(#[from] reqwest::Error),
    #[error("server returned account error")]
    Server,
    #[error("invalid base64 field")]
    Base64,
    #[error("OPAQUE protocol error")]
    Opaque,
    #[error("key hierarchy error")]
    KeyHierarchy(#[from] KeyHierarchyError),
}

pub struct AccountClient {
    base_url: String,
    http: reqwest::Client,
}

pub struct AccountRegisterOutcome {
    pub session: AccountSession,
    pub recovery_key: Zeroizing<String>,
    pub local_wrapped_master_key: Vec<u8>,
    pub keys: AccountKeyMaterial,
}

pub struct AccountLoginOutcome {
    pub session: AccountSession,
    pub local_wrapped_master_key: Vec<u8>,
    pub keys: AccountKeyMaterial,
}

pub struct AccountSession {
    pub user_id: String,
    pub tenant_id: String,
    pub device_id: String,
    pub email: String,
    pub session_token: Zeroizing<String>,
    pub expires_at_ms: i64,
}

pub struct AccountKeyMaterial {
    pub master_key: Zeroizing<[u8; KEY_LEN]>,
    pub user_secret_key: Zeroizing<[u8; KEY_LEN]>,
    pub tenant_root_dek: Zeroizing<[u8; KEY_LEN]>,
    pub list_deks: Vec<AccountListDekMaterial>,
}

pub struct AccountListDekMaterial {
    pub list_id: String,
    pub dek: Zeroizing<[u8; KEY_LEN]>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AccountKeyBundleDto {
    pub wrapped_master_key_by_password: String,
    pub wrapped_master_key_by_recovery: String,
    pub user_public_key: String,
    pub wrapped_user_secret_key: String,
    pub wrapped_tenant_root_dek: String,
    pub list_deks: Vec<ListDekBundleDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ListDekBundleDto {
    pub list_id: Uuid,
    pub wrapped_list_dek: String,
}

impl AccountClient {
    pub fn new(server_url: impl Into<String>) -> Result<Self, AccountClientError> {
        let base_url = normalize_base_url(server_url.into())?;
        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()?;
        Ok(Self { base_url, http })
    }

    pub async fn register(
        &self,
        email: &str,
        password: &str,
        device_name: Option<&str>,
        device_key: &[u8; KEY_LEN],
        initial_list_ids: Vec<Uuid>,
    ) -> Result<AccountRegisterOutcome, AccountClientError> {
        let mut rng = OsRng;
        let password = Zeroizing::new(password.as_bytes().to_vec());
        let client_start = ClientRegistration::<TodoriCipherSuite>::start(&mut rng, &password)
            .map_err(|_| AccountClientError::Opaque)?;
        let start = self
            .post_json::<OpaqueStartResponse>(
                "/v1/auth/register/start",
                &OpaqueStartRequest {
                    email: email.to_string(),
                    device_name: device_name.map(ToOwned::to_owned),
                    message: STANDARD.encode(client_start.message.serialize()),
                },
                None,
            )
            .await?;
        let server_message =
            RegistrationResponse::<TodoriCipherSuite>::deserialize(&decode_base64(&start.message)?)
                .map_err(|_| AccountClientError::Opaque)?;
        let client_finish = client_start
            .state
            .finish(&mut rng, &password, server_message, Default::default())
            .map_err(|_| AccountClientError::Opaque)?;
        let mut export_key = Zeroizing::new(client_finish.export_key.to_vec());
        let key_setup = build_registration_key_bundle(&export_key, device_key, &initial_list_ids)?;
        export_key.zeroize();

        let device_public_key = generate_device_public_key();
        let session = self
            .post_json::<SessionResponse>(
                "/v1/auth/register/finish",
                &RegisterFinishRequest {
                    state_id: start.state_id,
                    message: STANDARD.encode(client_finish.message.serialize()),
                    key_bundle: key_setup.bundle,
                    device_public_key: STANDARD.encode(device_public_key),
                },
                None,
            )
            .await?;

        Ok(AccountRegisterOutcome {
            session: session.into_account_session(email),
            recovery_key: key_setup.recovery_key,
            local_wrapped_master_key: key_setup.local_wrapped_master_key,
            keys: key_setup.keys,
        })
    }

    pub async fn login(
        &self,
        email: &str,
        password: &str,
        device_name: Option<&str>,
        device_key: &[u8; KEY_LEN],
    ) -> Result<AccountLoginOutcome, AccountClientError> {
        let mut rng = OsRng;
        let password = Zeroizing::new(password.as_bytes().to_vec());
        let client_start = ClientLogin::<TodoriCipherSuite>::start(&mut rng, &password)
            .map_err(|_| AccountClientError::Opaque)?;
        let start = self
            .post_json::<OpaqueStartResponse>(
                "/v1/auth/login/start",
                &OpaqueStartRequest {
                    email: email.to_string(),
                    device_name: device_name.map(ToOwned::to_owned),
                    message: STANDARD.encode(client_start.message.serialize()),
                },
                None,
            )
            .await?;
        let server_message =
            CredentialResponse::<TodoriCipherSuite>::deserialize(&decode_base64(&start.message)?)
                .map_err(|_| AccountClientError::Opaque)?;
        let client_finish = client_start
            .state
            .finish(&password, server_message, Default::default())
            .map_err(|_| AccountClientError::Opaque)?;
        let mut export_key = Zeroizing::new(client_finish.export_key.to_vec());
        let device_public_key = generate_device_public_key();
        let response = self
            .post_json::<LoginFinishResponse>(
                "/v1/auth/login/finish",
                &LoginFinishRequest {
                    state_id: start.state_id,
                    message: STANDARD.encode(client_finish.message.serialize()),
                    device_public_key: STANDARD.encode(device_public_key),
                },
                None,
            )
            .await?;
        let keys = unwrap_login_key_bundle(&response.key_bundle, &export_key)?;
        export_key.zeroize();
        let local_wrapped_master_key =
            wrap_master_key_with_device_key(&keys.master_key, device_key)?;

        Ok(AccountLoginOutcome {
            session: response.session.into_account_session(email),
            local_wrapped_master_key,
            keys,
        })
    }

    pub async fn logout(&self, session_token: &str) -> Result<(), AccountClientError> {
        self.post_json::<LogoutResponse>(
            "/v1/auth/logout",
            &serde_json::json!({}),
            Some(session_token),
        )
        .await?;
        Ok(())
    }

    pub async fn upsert_list_key_bundle(
        &self,
        tenant_id: Uuid,
        session_token: &str,
        list_key: ListDekBundleDto,
    ) -> Result<(), AccountClientError> {
        self.post_json::<UpsertListKeyResponse>(
            &format!("/v1/tenants/{tenant_id}/list-keys"),
            &list_key,
            Some(session_token),
        )
        .await?;
        Ok(())
    }

    pub async fn list_key_bundles(
        &self,
        tenant_id: Uuid,
        session_token: &str,
    ) -> Result<Vec<ListDekBundleDto>, AccountClientError> {
        self.get_json::<Vec<ListDekBundleDto>>(
            &format!("/v1/tenants/{tenant_id}/list-keys"),
            Some(session_token),
        )
        .await
    }

    async fn get_json<T: for<'de> Deserialize<'de>>(
        &self,
        path: &str,
        bearer_token: Option<&str>,
    ) -> Result<T, AccountClientError> {
        let mut request = self.http.get(format!("{}{}", self.base_url, path));
        if let Some(token) = bearer_token {
            request = request.bearer_auth(token);
        }
        let response = request.send().await?;
        if !response.status().is_success() {
            return Err(AccountClientError::Server);
        }
        response.json::<T>().await.map_err(AccountClientError::Http)
    }

    async fn post_json<T: for<'de> Deserialize<'de>>(
        &self,
        path: &str,
        body: &impl Serialize,
        bearer_token: Option<&str>,
    ) -> Result<T, AccountClientError> {
        let mut request = self
            .http
            .post(format!("{}{}", self.base_url, path))
            .json(body);
        if let Some(token) = bearer_token {
            request = request.bearer_auth(token);
        }
        let response = request.send().await?;
        if !response.status().is_success() {
            return Err(AccountClientError::Server);
        }
        response.json::<T>().await.map_err(AccountClientError::Http)
    }
}

pub fn unwrap_login_key_bundle(
    bundle: &AccountKeyBundleDto,
    export_key: &[u8],
) -> Result<AccountKeyMaterial, AccountClientError> {
    let mut kek_pw = Zeroizing::new(derive_kek_pw(export_key));
    let master_key = Zeroizing::new(unwrap_master_key_with_kek_pw(
        &decode_base64(&bundle.wrapped_master_key_by_password)?,
        &kek_pw,
    )?);
    kek_pw.zeroize();

    let user_secret_key = Zeroizing::new(unwrap_user_secret_key_with_master_key(
        &decode_base64(&bundle.wrapped_user_secret_key)?,
        &master_key,
    )?);
    let tenant_root_dek = Zeroizing::new(unwrap_tenant_root_dek_with_master_key(
        &decode_base64(&bundle.wrapped_tenant_root_dek)?,
        &master_key,
    )?);
    let list_deks = unwrap_list_dek_bundles(&bundle.list_deks, &master_key)?;

    Ok(AccountKeyMaterial {
        master_key,
        user_secret_key,
        tenant_root_dek,
        list_deks,
    })
}

pub fn unwrap_list_dek_bundles(
    bundles: &[ListDekBundleDto],
    master_key: &[u8; KEY_LEN],
) -> Result<Vec<AccountListDekMaterial>, AccountClientError> {
    let mut list_deks = Vec::with_capacity(bundles.len());
    for bundle in bundles {
        list_deks.push(AccountListDekMaterial {
            list_id: bundle.list_id.to_string(),
            dek: Zeroizing::new(unwrap_list_dek_with_master_key(
                &decode_base64(&bundle.wrapped_list_dek)?,
                master_key,
            )?),
        });
    }
    Ok(list_deks)
}

pub fn wrap_list_dek_bundle(
    list_id: Uuid,
    list_dek: &[u8; KEY_LEN],
    master_key: &[u8; KEY_LEN],
) -> Result<ListDekBundleDto, AccountClientError> {
    let wrapped_list_dek = wrap_list_dek_with_master_key(list_dek, master_key)?;
    Ok(ListDekBundleDto {
        list_id,
        wrapped_list_dek: STANDARD.encode(wrapped_list_dek),
    })
}

fn build_registration_key_bundle(
    export_key: &[u8],
    device_key: &[u8; KEY_LEN],
    initial_list_ids: &[Uuid],
) -> Result<RegistrationKeySetup, AccountClientError> {
    let mut kek_pw = Zeroizing::new(derive_kek_pw(export_key));
    let master_key = Zeroizing::new(generate_master_key());
    let recovery_key = Zeroizing::new(generate_recovery_key());
    let mut recovery_wrap_key = Zeroizing::new(derive_recovery_wrap_key(&recovery_key));
    let user_key_pair = generate_user_x25519_key_pair();
    let user_secret_key = Zeroizing::new(user_key_pair.secret_key);
    let tenant_root_dek = Zeroizing::new(generate_tenant_root_dek());

    let wrapped_master_key_by_password = wrap_master_key_with_kek_pw(&master_key, &kek_pw)?;
    let wrapped_master_key_by_recovery =
        wrap_master_key_with_recovery_key(&master_key, &recovery_wrap_key)?;
    let wrapped_user_secret_key =
        wrap_user_secret_key_with_master_key(&user_secret_key, &master_key)?;
    let wrapped_tenant_root_dek =
        wrap_tenant_root_dek_with_master_key(&tenant_root_dek, &master_key)?;
    let local_wrapped_master_key = wrap_master_key_with_device_key(&master_key, device_key)?;
    let mut list_dek_bundles = Vec::with_capacity(initial_list_ids.len());
    let mut list_deks = Vec::with_capacity(initial_list_ids.len());
    for list_id in initial_list_ids {
        let list_dek = Zeroizing::new(generate_list_dek());
        list_dek_bundles.push(wrap_list_dek_bundle(*list_id, &list_dek, &master_key)?);
        list_deks.push(AccountListDekMaterial {
            list_id: list_id.to_string(),
            dek: list_dek,
        });
    }

    kek_pw.zeroize();
    recovery_wrap_key.zeroize();

    Ok(RegistrationKeySetup {
        bundle: AccountKeyBundleDto {
            wrapped_master_key_by_password: STANDARD.encode(wrapped_master_key_by_password),
            wrapped_master_key_by_recovery: STANDARD.encode(wrapped_master_key_by_recovery),
            user_public_key: STANDARD.encode(user_key_pair.public_key),
            wrapped_user_secret_key: STANDARD.encode(wrapped_user_secret_key),
            wrapped_tenant_root_dek: STANDARD.encode(wrapped_tenant_root_dek),
            list_deks: list_dek_bundles,
        },
        recovery_key,
        local_wrapped_master_key,
        keys: AccountKeyMaterial {
            master_key,
            user_secret_key,
            tenant_root_dek,
            list_deks,
        },
    })
}

fn normalize_base_url(mut value: String) -> Result<String, AccountClientError> {
    value = value.trim().trim_end_matches('/').to_string();
    if value.is_empty() {
        return Err(AccountClientError::EmptyServerUrl);
    }
    Ok(value)
}

fn decode_base64(value: &str) -> Result<Vec<u8>, AccountClientError> {
    STANDARD
        .decode(value)
        .map_err(|_| AccountClientError::Base64)
}

struct RegistrationKeySetup {
    bundle: AccountKeyBundleDto,
    recovery_key: Zeroizing<String>,
    local_wrapped_master_key: Vec<u8>,
    keys: AccountKeyMaterial,
}

#[derive(Debug, Serialize)]
struct OpaqueStartRequest {
    email: String,
    device_name: Option<String>,
    message: String,
}

#[derive(Debug, Deserialize)]
struct OpaqueStartResponse {
    state_id: Uuid,
    message: String,
    #[allow(dead_code)]
    expires_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
struct RegisterFinishRequest {
    state_id: Uuid,
    message: String,
    key_bundle: AccountKeyBundleDto,
    device_public_key: String,
}

#[derive(Debug, Serialize)]
struct LoginFinishRequest {
    state_id: Uuid,
    message: String,
    device_public_key: String,
}

#[derive(Debug, Deserialize)]
struct LoginFinishResponse {
    #[serde(flatten)]
    session: SessionResponse,
    key_bundle: AccountKeyBundleDto,
}

#[derive(Debug, Deserialize)]
struct SessionResponse {
    user_id: Uuid,
    tenant_id: Uuid,
    device_id: Uuid,
    session_token: String,
    expires_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
struct LogoutResponse {}

#[derive(Debug, Deserialize)]
struct UpsertListKeyResponse {}

impl SessionResponse {
    fn into_account_session(self, email: &str) -> AccountSession {
        AccountSession {
            user_id: self.user_id.to_string(),
            tenant_id: self.tenant_id.to_string(),
            device_id: self.device_id.to_string(),
            email: email.to_string(),
            session_token: Zeroizing::new(self.session_token),
            expires_at_ms: self.expires_at.timestamp_millis(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registration_bundle_unwraps_with_export_key_and_rejects_wrong_key() {
        let export_key = b"opaque export key";
        let wrong_export_key = b"wrong opaque export key";
        let device_key = [0x44; KEY_LEN];

        let list_id = Uuid::now_v7();
        let setup = build_registration_key_bundle(export_key, &device_key, &[list_id]).unwrap();
        let unwrapped = unwrap_login_key_bundle(&setup.bundle, export_key).unwrap();

        assert_eq!(*unwrapped.master_key, *setup.keys.master_key);
        assert_eq!(*unwrapped.user_secret_key, *setup.keys.user_secret_key);
        assert_eq!(*unwrapped.tenant_root_dek, *setup.keys.tenant_root_dek);
        assert_eq!(unwrapped.list_deks.len(), 1);
        assert_eq!(unwrapped.list_deks[0].list_id, list_id.to_string());
        assert_eq!(*unwrapped.list_deks[0].dek, *setup.keys.list_deks[0].dek);
        assert!(unwrap_login_key_bundle(&setup.bundle, wrong_export_key).is_err());
    }

    #[test]
    fn local_wrapped_master_key_uses_device_key_only_locally() {
        let setup = build_registration_key_bundle(
            b"opaque export key",
            &[0x44; KEY_LEN],
            &[Uuid::now_v7()],
        )
        .unwrap();

        assert!(!setup.local_wrapped_master_key.is_empty());
        assert!(!setup
            .bundle
            .wrapped_master_key_by_password
            .contains(&STANDARD.encode(&setup.local_wrapped_master_key)));
    }

    #[test]
    fn list_dek_bundle_unwrap_roundtrips_with_master_key() {
        let list_id = Uuid::now_v7();
        let list_dek = [0x31; KEY_LEN];
        let master_key = [0x62; KEY_LEN];
        let bundle = wrap_list_dek_bundle(list_id, &list_dek, &master_key).unwrap();

        let unwrapped = unwrap_list_dek_bundles(&[bundle], &master_key).unwrap();

        assert_eq!(unwrapped.len(), 1);
        assert_eq!(unwrapped[0].list_id, list_id.to_string());
        assert_eq!(*unwrapped[0].dek, list_dek);
        assert!(unwrap_list_dek_bundles(
            &[wrap_list_dek_bundle(list_id, &list_dek, &master_key).unwrap()],
            &[0xff; KEY_LEN],
        )
        .is_err());
    }
}
