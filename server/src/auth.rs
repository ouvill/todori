use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::{DateTime, Duration, Utc};
use opaque_ke::{
    CredentialFinalization, CredentialRequest, RegistrationRequest, RegistrationUpload,
    ServerLogin, ServerLoginStartParameters, ServerRegistration, ServerSetup,
};
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx_core::{query::query, row::Row};
use sqlx_postgres::{PgPool, PgTransaction, Postgres};
use todori_crypto::TodoriCipherSuite;
use todori_sync::account::{AccountKeyBundleDto, ListDekBundleDto};
use uuid::Uuid;

use crate::{db, AppError};

const OPAQUE_STATE_TTL_MINUTES: i64 = 10;
const SESSION_TTL_DAYS: i64 = 30;

type TodoriServerSetup = ServerSetup<TodoriCipherSuite>;
type TodoriServerRegistration = ServerRegistration<TodoriCipherSuite>;
type TodoriServerLogin = ServerLogin<TodoriCipherSuite>;

#[derive(Debug, Deserialize)]
pub struct OpaqueStartRequest {
    pub email: String,
    pub device_name: Option<String>,
    pub message: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OpaqueStartResponse {
    pub state_id: Uuid,
    pub message: String,
    pub expires_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct OpaqueFinishRequest {
    pub state_id: Uuid,
    pub message: String,
}

#[derive(Debug, Deserialize)]
pub struct RegisterFinishRequest {
    pub state_id: Uuid,
    pub message: String,
    pub key_bundle: AccountKeyBundleDto,
    pub device_public_key: String,
}

#[derive(Debug, Deserialize)]
pub struct LoginFinishRequest {
    pub state_id: Uuid,
    pub message: String,
    pub device_public_key: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SessionResponse {
    pub user_id: Uuid,
    pub tenant_id: Uuid,
    pub device_id: Uuid,
    pub session_token: String,
    pub expires_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginSessionResponse {
    #[serde(flatten)]
    pub session: SessionResponse,
    pub key_bundle: AccountKeyBundleDto,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LogoutResponse {}

#[derive(Debug, Clone)]
pub struct AuthContext {
    pub user_id: Uuid,
    pub device_id: Uuid,
}

pub async fn register_start(
    pool: &PgPool,
    request: OpaqueStartRequest,
) -> Result<OpaqueStartResponse, AppError> {
    let email = normalize_email(&request.email)?;
    let device_name = normalize_device_name(request.device_name);
    let client_message = decode_opaque_message(&request.message)?;
    let registration_request =
        RegistrationRequest::<TodoriCipherSuite>::deserialize(&client_message)
            .map_err(|_| AppError::bad_request("invalid opaque message"))?;
    let server_setup = get_or_create_server_setup(pool).await?;
    let server_start =
        ServerRegistration::start(&server_setup, registration_request, email.as_bytes())
            .map_err(|_| AppError::bad_request("invalid opaque message"))?;
    let state_id = Uuid::now_v7();
    let expires_at = Utc::now() + Duration::minutes(OPAQUE_STATE_TTL_MINUTES);

    query::<Postgres>(
        "INSERT INTO opaque_registration_states (id, email, device_name, expires_at)
         VALUES ($1, $2, $3, $4)",
    )
    .bind(state_id)
    .bind(&email)
    .bind(&device_name)
    .bind(expires_at)
    .execute(pool)
    .await?;

    Ok(OpaqueStartResponse {
        state_id,
        message: STANDARD.encode(server_start.message.serialize()),
        expires_at,
    })
}

pub async fn register_finish(
    pool: &PgPool,
    request: RegisterFinishRequest,
) -> Result<SessionResponse, AppError> {
    let upload = decode_opaque_message(&request.message)?;
    let registration_upload = RegistrationUpload::<TodoriCipherSuite>::deserialize(&upload)
        .map_err(|_| AppError::bad_request("invalid opaque message"))?;
    let server_record = ServerRegistration::finish(registration_upload);
    let server_record_bytes = server_record.serialize().to_vec();
    let key_bundle = decode_account_key_bundle(&request.key_bundle)?;
    let device_public_key = decode_fixed_key(&request.device_public_key, "invalid device key")?;

    let mut tx = pool.begin().await?;
    let state = consume_registration_state(&mut tx, request.state_id).await?;
    let user_id = Uuid::now_v7();
    let tenant_id = Uuid::now_v7();
    let device_id = Uuid::now_v7();

    query::<Postgres>("INSERT INTO users (id, email, opaque_record) VALUES ($1, $2, $3)")
        .bind(user_id)
        .bind(&state.email)
        .bind(&server_record_bytes)
        .execute(&mut *tx)
        .await
        .map_err(map_insert_user_error)?;

    db::set_user_context(&mut tx, user_id).await?;
    db::set_tenant_context(&mut tx, tenant_id).await?;

    query::<Postgres>("INSERT INTO tenants (id, kind, owner_user_id) VALUES ($1, 'personal', $2)")
        .bind(tenant_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    query::<Postgres>(
        "INSERT INTO tenant_members (tenant_id, user_id, role) VALUES ($1, $2, 'owner')",
    )
    .bind(tenant_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await?;
    query::<Postgres>("INSERT INTO tenant_seq (tenant_id, last_seq) VALUES ($1, 0)")
        .bind(tenant_id)
        .execute(&mut *tx)
        .await?;
    insert_account_key_bundle(&mut tx, user_id, tenant_id, key_bundle).await?;
    insert_device(
        &mut tx,
        device_id,
        user_id,
        &state.device_name,
        Some(&device_public_key),
    )
    .await?;
    let session = create_session(&mut tx, user_id, device_id).await?;
    tx.commit().await?;

    Ok(SessionResponse {
        user_id,
        tenant_id,
        device_id,
        session_token: session.token,
        expires_at: session.expires_at,
    })
}

pub async fn login_start(
    pool: &PgPool,
    request: OpaqueStartRequest,
) -> Result<OpaqueStartResponse, AppError> {
    let email = normalize_email(&request.email)?;
    let device_name = normalize_device_name(request.device_name);
    let client_message = decode_opaque_message(&request.message)?;
    let credential_request = CredentialRequest::<TodoriCipherSuite>::deserialize(&client_message)
        .map_err(|_| AppError::bad_request("invalid opaque message"))?;

    let row =
        query::<Postgres>("SELECT id, opaque_record FROM users WHERE lower(email) = lower($1)")
            .bind(&email)
            .fetch_optional(pool)
            .await?
            .ok_or_else(|| AppError::not_found("account not found"))?;
    let user_id: Uuid = row.try_get("id").map_err(|_| AppError::internal())?;
    let record_bytes: Vec<u8> = row
        .try_get("opaque_record")
        .map_err(|_| AppError::internal())?;
    let server_record =
        TodoriServerRegistration::deserialize(&record_bytes).map_err(|_| AppError::internal())?;
    let server_setup = get_or_create_server_setup(pool).await?;
    let mut rng = OsRng;
    let login_start = ServerLogin::start(
        &mut rng,
        &server_setup,
        Some(server_record),
        credential_request,
        email.as_bytes(),
        ServerLoginStartParameters::default(),
    )
    .map_err(|_| AppError::bad_request("invalid opaque message"))?;

    let state_id = Uuid::now_v7();
    let expires_at = Utc::now() + Duration::minutes(OPAQUE_STATE_TTL_MINUTES);
    query::<Postgres>(
        "INSERT INTO opaque_login_states (id, user_id, device_name, server_login_state, expires_at)
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(state_id)
    .bind(user_id)
    .bind(&device_name)
    .bind(login_start.state.serialize().to_vec())
    .bind(expires_at)
    .execute(pool)
    .await?;

    Ok(OpaqueStartResponse {
        state_id,
        message: STANDARD.encode(login_start.message.serialize()),
        expires_at,
    })
}

pub async fn login_finish(
    pool: &PgPool,
    request: LoginFinishRequest,
) -> Result<LoginSessionResponse, AppError> {
    let finalization = decode_opaque_message(&request.message)?;
    let credential_finalization =
        CredentialFinalization::<TodoriCipherSuite>::deserialize(&finalization)
            .map_err(|_| AppError::bad_request("invalid opaque message"))?;
    let device_public_key = decode_fixed_key(&request.device_public_key, "invalid device key")?;

    let mut tx = pool.begin().await?;
    let state = consume_login_state(&mut tx, request.state_id).await?;
    let server_login = TodoriServerLogin::deserialize(&state.server_login_state)
        .map_err(|_| AppError::internal())?;
    server_login
        .finish(credential_finalization)
        .map_err(|_| AppError::unauthorized())?;

    db::set_user_context(&mut tx, state.user_id).await?;

    let tenant_id: Uuid = query::<Postgres>(
        "SELECT tenant_id FROM tenant_members WHERE user_id = $1 ORDER BY joined_at ASC LIMIT 1",
    )
    .bind(state.user_id)
    .fetch_one(&mut *tx)
    .await?
    .try_get("tenant_id")
    .map_err(|_| AppError::internal())?;
    db::set_tenant_context(&mut tx, tenant_id).await?;
    let key_bundle = load_account_key_bundle(&mut tx, state.user_id, tenant_id).await?;
    let device_id = Uuid::now_v7();
    insert_device(
        &mut tx,
        device_id,
        state.user_id,
        &state.device_name,
        Some(&device_public_key),
    )
    .await?;
    let session = create_session(&mut tx, state.user_id, device_id).await?;
    tx.commit().await?;

    Ok(LoginSessionResponse {
        session: SessionResponse {
            user_id: state.user_id,
            tenant_id,
            device_id,
            session_token: session.token,
            expires_at: session.expires_at,
        },
        key_bundle,
    })
}

pub async fn logout(pool: &PgPool, bearer_token: &str) -> Result<LogoutResponse, AppError> {
    let token_hash = hash_token(bearer_token);
    let rows = query::<Postgres>(
        "UPDATE sessions
         SET revoked_at = now()
         WHERE token_hash = $1 AND revoked_at IS NULL",
    )
    .bind(token_hash.as_slice())
    .execute(pool)
    .await?
    .rows_affected();
    if rows == 0 {
        return Err(AppError::unauthorized());
    }
    Ok(LogoutResponse {})
}

pub async fn authenticate(
    pool: &PgPool,
    bearer_token: &str,
    tenant_id: Uuid,
) -> Result<AuthContext, AppError> {
    let token_hash = hash_token(bearer_token);
    let mut tx = pool.begin().await?;
    let row = query::<Postgres>(
        "SELECT s.user_id, s.device_id
         FROM sessions s
         JOIN devices d ON d.id = s.device_id AND d.user_id = s.user_id
         WHERE s.token_hash = $1
           AND s.expires_at > now()
           AND s.revoked_at IS NULL
           AND d.revoked_at IS NULL",
    )
    .bind(token_hash.as_slice())
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(AppError::unauthorized)?;

    let user_id = row.try_get("user_id").map_err(|_| AppError::internal())?;
    let device_id = row.try_get("device_id").map_err(|_| AppError::internal())?;
    db::set_user_context(&mut tx, user_id).await?;
    let membership = query::<Postgres>(
        "SELECT 1
         FROM tenant_members
         WHERE tenant_id = $1 AND user_id = $2",
    )
    .bind(tenant_id)
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await?;
    if membership.is_none() {
        return Err(AppError::unauthorized());
    }
    db::set_tenant_context(&mut tx, tenant_id).await?;
    query::<Postgres>("UPDATE sessions SET last_seen_at = now() WHERE token_hash = $1")
        .bind(token_hash.as_slice())
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    Ok(AuthContext { user_id, device_id })
}

pub async fn cleanup_expired_opaque_states(pool: &PgPool) -> Result<u64, AppError> {
    let registration =
        query::<Postgres>("DELETE FROM opaque_registration_states WHERE expires_at <= now()")
            .execute(pool)
            .await?
            .rows_affected();
    let login = query::<Postgres>("DELETE FROM opaque_login_states WHERE expires_at <= now()")
        .execute(pool)
        .await?
        .rows_affected();
    Ok(registration + login)
}

fn normalize_email(email: &str) -> Result<String, AppError> {
    let email = email.trim().to_ascii_lowercase();
    if email.is_empty() || email.len() > 320 || !email.contains('@') {
        return Err(AppError::bad_request("invalid email"));
    }
    Ok(email)
}

fn normalize_device_name(device_name: Option<String>) -> String {
    let trimmed = device_name
        .unwrap_or_else(|| "Todori device".to_string())
        .trim()
        .to_string();
    if trimmed.is_empty() {
        "Todori device".to_string()
    } else {
        trimmed.chars().take(120).collect()
    }
}

fn decode_opaque_message(message: &str) -> Result<Vec<u8>, AppError> {
    STANDARD
        .decode(message)
        .map_err(|_| AppError::bad_request("invalid base64 message"))
}

fn decode_bytes_field(message: &str, error: &'static str) -> Result<Vec<u8>, AppError> {
    STANDARD
        .decode(message)
        .map_err(|_| AppError::bad_request(error))
}

fn decode_fixed_key(message: &str, error: &'static str) -> Result<Vec<u8>, AppError> {
    let bytes = decode_bytes_field(message, error)?;
    if bytes.len() != 32 {
        return Err(AppError::bad_request(error));
    }
    Ok(bytes)
}

async fn get_or_create_server_setup(pool: &PgPool) -> Result<TodoriServerSetup, AppError> {
    let mut rng = OsRng;
    let generated = TodoriServerSetup::new(&mut rng).serialize().to_vec();
    query::<Postgres>(
        "INSERT INTO opaque_server_setup (singleton, setup)
         VALUES (TRUE, $1)
         ON CONFLICT (singleton) DO NOTHING",
    )
    .bind(&generated)
    .execute(pool)
    .await?;

    let bytes: Vec<u8> =
        query::<Postgres>("SELECT setup FROM opaque_server_setup WHERE singleton = TRUE")
            .fetch_one(pool)
            .await?
            .try_get("setup")
            .map_err(|_| AppError::internal())?;
    TodoriServerSetup::deserialize(&bytes).map_err(|_| AppError::internal())
}

struct RegistrationState {
    email: String,
    device_name: String,
}

async fn consume_registration_state(
    tx: &mut PgTransaction<'_>,
    state_id: Uuid,
) -> Result<RegistrationState, AppError> {
    let row = query::<Postgres>(
        "DELETE FROM opaque_registration_states
         WHERE id = $1 AND expires_at > now()
         RETURNING email, device_name",
    )
    .bind(state_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| AppError::bad_request("invalid or expired opaque state"))?;
    Ok(RegistrationState {
        email: row.try_get("email").map_err(|_| AppError::internal())?,
        device_name: row
            .try_get("device_name")
            .map_err(|_| AppError::internal())?,
    })
}

struct LoginState {
    user_id: Uuid,
    device_name: String,
    server_login_state: Vec<u8>,
}

async fn consume_login_state(
    tx: &mut PgTransaction<'_>,
    state_id: Uuid,
) -> Result<LoginState, AppError> {
    let row = query::<Postgres>(
        "DELETE FROM opaque_login_states
         WHERE id = $1 AND expires_at > now()
         RETURNING user_id, device_name, server_login_state",
    )
    .bind(state_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| AppError::bad_request("invalid or expired opaque state"))?;
    Ok(LoginState {
        user_id: row.try_get("user_id").map_err(|_| AppError::internal())?,
        device_name: row
            .try_get("device_name")
            .map_err(|_| AppError::internal())?,
        server_login_state: row
            .try_get("server_login_state")
            .map_err(|_| AppError::internal())?,
    })
}

struct DecodedAccountKeyBundle {
    wrapped_master_key_by_password: Vec<u8>,
    wrapped_master_key_by_recovery: Vec<u8>,
    user_public_key: Vec<u8>,
    wrapped_user_secret_key: Vec<u8>,
    wrapped_tenant_root_dek: Vec<u8>,
    list_deks: Vec<DecodedListDekBundle>,
}

struct DecodedListDekBundle {
    list_id: Uuid,
    wrapped_list_dek: Vec<u8>,
}

fn decode_account_key_bundle(
    bundle: &AccountKeyBundleDto,
) -> Result<DecodedAccountKeyBundle, AppError> {
    if bundle.list_deks.is_empty() {
        return Err(AppError::bad_request("missing list key bundle"));
    }
    Ok(DecodedAccountKeyBundle {
        wrapped_master_key_by_password: decode_bytes_field(
            &bundle.wrapped_master_key_by_password,
            "invalid key bundle",
        )?,
        wrapped_master_key_by_recovery: decode_bytes_field(
            &bundle.wrapped_master_key_by_recovery,
            "invalid key bundle",
        )?,
        user_public_key: decode_fixed_key(&bundle.user_public_key, "invalid key bundle")?,
        wrapped_user_secret_key: decode_bytes_field(
            &bundle.wrapped_user_secret_key,
            "invalid key bundle",
        )?,
        wrapped_tenant_root_dek: decode_bytes_field(
            &bundle.wrapped_tenant_root_dek,
            "invalid key bundle",
        )?,
        list_deks: bundle
            .list_deks
            .iter()
            .map(|list_dek| {
                Ok(DecodedListDekBundle {
                    list_id: list_dek.list_id,
                    wrapped_list_dek: decode_bytes_field(
                        &list_dek.wrapped_list_dek,
                        "invalid key bundle",
                    )?,
                })
            })
            .collect::<Result<Vec<_>, AppError>>()?,
    })
}

async fn insert_account_key_bundle(
    tx: &mut PgTransaction<'_>,
    user_id: Uuid,
    tenant_id: Uuid,
    bundle: DecodedAccountKeyBundle,
) -> Result<(), AppError> {
    query::<Postgres>(
        "INSERT INTO user_key_bundles (
            user_id,
            wrapped_master_key_by_password,
            wrapped_master_key_by_recovery,
            user_public_key,
            wrapped_user_secret_key
         ) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(user_id)
    .bind(&bundle.wrapped_master_key_by_password)
    .bind(&bundle.wrapped_master_key_by_recovery)
    .bind(&bundle.user_public_key)
    .bind(&bundle.wrapped_user_secret_key)
    .execute(&mut **tx)
    .await?;

    query::<Postgres>(
        "INSERT INTO tenant_key_bundles (tenant_id, wrapped_tenant_root_dek)
         VALUES ($1, $2)",
    )
    .bind(tenant_id)
    .bind(&bundle.wrapped_tenant_root_dek)
    .execute(&mut **tx)
    .await?;

    for list_dek in bundle.list_deks {
        query::<Postgres>(
            "INSERT INTO list_key_bundles (tenant_id, list_id, wrapped_list_dek)
             VALUES ($1, $2, $3)",
        )
        .bind(tenant_id)
        .bind(list_dek.list_id)
        .bind(&list_dek.wrapped_list_dek)
        .execute(&mut **tx)
        .await?;
    }

    Ok(())
}

async fn load_account_key_bundle(
    tx: &mut PgTransaction<'_>,
    user_id: Uuid,
    tenant_id: Uuid,
) -> Result<AccountKeyBundleDto, AppError> {
    let user = query::<Postgres>(
        "SELECT
            wrapped_master_key_by_password,
            wrapped_master_key_by_recovery,
            user_public_key,
            wrapped_user_secret_key
         FROM user_key_bundles
         WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await?;
    let tenant = query::<Postgres>(
        "SELECT wrapped_tenant_root_dek
         FROM tenant_key_bundles
         WHERE tenant_id = $1",
    )
    .bind(tenant_id)
    .fetch_one(&mut **tx)
    .await?;
    let list_rows = query::<Postgres>(
        "SELECT list_id, wrapped_list_dek
         FROM list_key_bundles
         WHERE tenant_id = $1
         ORDER BY created_at ASC, list_id ASC",
    )
    .bind(tenant_id)
    .fetch_all(&mut **tx)
    .await?;

    let mut list_deks = Vec::with_capacity(list_rows.len());
    for row in list_rows {
        let list_id: Uuid = row.try_get("list_id").map_err(|_| AppError::internal())?;
        let wrapped_list_dek: Vec<u8> = row
            .try_get("wrapped_list_dek")
            .map_err(|_| AppError::internal())?;
        list_deks.push(ListDekBundleDto {
            list_id,
            wrapped_list_dek: STANDARD.encode(wrapped_list_dek),
        });
    }

    Ok(AccountKeyBundleDto {
        wrapped_master_key_by_password: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_master_key_by_password")
                .map_err(|_| AppError::internal())?,
        ),
        wrapped_master_key_by_recovery: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_master_key_by_recovery")
                .map_err(|_| AppError::internal())?,
        ),
        user_public_key: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("user_public_key")
                .map_err(|_| AppError::internal())?,
        ),
        wrapped_user_secret_key: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_user_secret_key")
                .map_err(|_| AppError::internal())?,
        ),
        wrapped_tenant_root_dek: STANDARD.encode(
            tenant
                .try_get::<Vec<u8>, _>("wrapped_tenant_root_dek")
                .map_err(|_| AppError::internal())?,
        ),
        list_deks,
    })
}

async fn insert_device(
    tx: &mut PgTransaction<'_>,
    device_id: Uuid,
    user_id: Uuid,
    device_name: &str,
    public_key: Option<&[u8]>,
) -> Result<(), AppError> {
    query::<Postgres>(
        "INSERT INTO devices (id, user_id, device_name, public_key)
         VALUES ($1, $2, $3, $4)",
    )
    .bind(device_id)
    .bind(user_id)
    .bind(device_name)
    .bind(public_key)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

struct CreatedSession {
    token: String,
    expires_at: DateTime<Utc>,
}

async fn create_session(
    tx: &mut PgTransaction<'_>,
    user_id: Uuid,
    device_id: Uuid,
) -> Result<CreatedSession, AppError> {
    let token = generate_session_token();
    let token_hash = hash_token(&token);
    let expires_at = Utc::now() + Duration::days(SESSION_TTL_DAYS);
    query::<Postgres>(
        "INSERT INTO sessions (id, user_id, device_id, token_hash, expires_at)
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(Uuid::now_v7())
    .bind(user_id)
    .bind(device_id)
    .bind(token_hash.as_slice())
    .bind(expires_at)
    .execute(&mut **tx)
    .await?;
    Ok(CreatedSession { token, expires_at })
}

fn generate_session_token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

fn hash_token(token: &str) -> [u8; 32] {
    Sha256::digest(token.as_bytes()).into()
}

fn map_insert_user_error(error: sqlx_core::Error) -> AppError {
    if let sqlx_core::Error::Database(db_error) = &error {
        if db_error.constraint() == Some("users_email_lower_unique") {
            return AppError::conflict("account already exists");
        }
    }
    AppError::from(error)
}
