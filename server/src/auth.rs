use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::{DateTime, Duration, Utc};
use opaque_ke::{
    CredentialFinalization, CredentialRequest, RegistrationRequest, RegistrationUpload,
    ServerLogin, ServerLoginParameters, ServerRegistration, ServerSetup,
};
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx_core::{query::query, row::Row};
use sqlx_postgres::{PgPool, PgTransaction, Postgres};
use taskveil_crypto::{
    key_hierarchy::INITIAL_KEY_GENERATION,
    organization::{
        verify_device_certificate, verify_device_proof, AccountRootPublicKeys, DeviceCertificate,
        DeviceProofOfPossession, DEVICE_CHALLENGE_LEN, DEVICE_FINGERPRINT_LEN,
        ED25519_SIGNATURE_LEN,
    },
    TaskveilCipherSuite, CRYPTO_SUITE_ID,
};
use taskveil_sync::account::{AccountKeyBundleDto, DeviceEnrollmentDto, UpdateKeyWrappersRequest};
use uuid::Uuid;

use crate::{db, AppError};

const OPAQUE_STATE_TTL_MINUTES: i64 = 10;
const SESSION_TTL_DAYS: i64 = 30;

type TaskveilServerSetup = ServerSetup<TaskveilCipherSuite>;
type TaskveilServerRegistration = ServerRegistration<TaskveilCipherSuite>;
type TaskveilServerLogin = ServerLogin<TaskveilCipherSuite>;

#[derive(Debug, Deserialize)]
pub struct OpaqueStartRequest {
    pub email: String,
    pub device_name: Option<String>,
    pub opaque_suite_id: u16,
    pub message: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OpaqueStartResponse {
    pub state_id: Uuid,
    pub opaque_suite_id: u16,
    pub user_id: Uuid,
    pub tenant_id: Uuid,
    pub device_id: Uuid,
    pub device_challenge: String,
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
    pub device_enrollment: DeviceEnrollmentDto,
}

#[derive(Debug, Deserialize)]
pub struct LoginFinishRequest {
    pub state_id: Uuid,
    pub message: String,
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
    pub device_challenge: String,
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
    validate_opaque_suite(request.opaque_suite_id)?;
    let email = normalize_email(&request.email)?;
    let device_name = normalize_device_name(request.device_name);
    let client_message = decode_opaque_message(&request.message)?;
    let registration_request =
        RegistrationRequest::<TaskveilCipherSuite>::deserialize(&client_message)
            .map_err(|_| AppError::bad_request("invalid opaque message"))?;
    let server_setup = get_or_create_server_setup(pool).await?;
    let server_start =
        ServerRegistration::start(&server_setup, registration_request, email.as_bytes())
            .map_err(|_| AppError::bad_request("invalid opaque message"))?;
    let state_id = Uuid::now_v7();
    let user_id = Uuid::now_v7();
    let tenant_id = Uuid::now_v7();
    let device_id = Uuid::now_v7();
    let device_challenge = random_device_challenge();
    let expires_at = Utc::now() + Duration::minutes(OPAQUE_STATE_TTL_MINUTES);

    query::<Postgres>(
        "INSERT INTO opaque_registration_states
            (id, user_id, tenant_id, device_id, device_challenge, email, device_name,
             opaque_suite_id, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(state_id)
    .bind(user_id)
    .bind(tenant_id)
    .bind(device_id)
    .bind(device_challenge.as_slice())
    .bind(&email)
    .bind(&device_name)
    .bind(i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())?)
    .bind(expires_at)
    .execute(pool)
    .await?;

    Ok(OpaqueStartResponse {
        state_id,
        opaque_suite_id: CRYPTO_SUITE_ID,
        user_id,
        tenant_id,
        device_id,
        device_challenge: STANDARD.encode(device_challenge),
        message: STANDARD.encode(server_start.message.serialize()),
        expires_at,
    })
}

pub async fn register_finish(
    pool: &PgPool,
    request: RegisterFinishRequest,
) -> Result<SessionResponse, AppError> {
    let upload = decode_opaque_message(&request.message)?;
    let registration_upload = RegistrationUpload::<TaskveilCipherSuite>::deserialize(&upload)
        .map_err(|_| AppError::bad_request("invalid opaque message"))?;
    let server_record = ServerRegistration::finish(registration_upload);
    let server_record_bytes = server_record.serialize().to_vec();
    let key_bundle = decode_account_key_bundle(&request.key_bundle)?;

    let mut tx = pool.begin().await?;
    let state = consume_registration_state(&mut tx, request.state_id).await?;
    let user_id = state.user_id;
    let tenant_id = state.tenant_id;
    let device_id = state.device_id;
    let enrollment = verify_device_enrollment(
        &request.device_enrollment,
        user_id,
        device_id,
        &state.device_challenge,
        Utc::now().timestamp_millis(),
    )?;
    if key_bundle.account_root_public != enrollment.account_root_public {
        return Err(AppError::bad_request("account root mismatch"));
    }

    query::<Postgres>(
        "INSERT INTO users
            (id, email, opaque_suite_id, opaque_record, account_root_public)
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(user_id)
    .bind(&state.email)
    .bind(i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())?)
    .bind(&server_record_bytes)
    .bind(&enrollment.account_root_public)
    .execute(&mut *tx)
    .await
    .map_err(map_insert_user_error)?;

    query::<Postgres>("INSERT INTO billing_customers (user_id) VALUES ($1)")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

    db::set_user_context(&mut tx, user_id).await?;
    db::set_tenant_context(&mut tx, tenant_id).await?;

    query::<Postgres>("INSERT INTO tenants (id, kind, owner_user_id) VALUES ($1, 'personal', $2)")
        .bind(tenant_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    query::<Postgres>(
        "INSERT INTO tenant_members
            (tenant_id, user_id, role, verification_state, verified_at)
         VALUES ($1, $2, 'owner', 'verified', now())",
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
    insert_certified_device(&mut tx, device_id, user_id, &state.device_name, &enrollment).await?;
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
    validate_opaque_suite(request.opaque_suite_id)?;
    let email = normalize_email(&request.email)?;
    let device_name = normalize_device_name(request.device_name);
    let client_message = decode_opaque_message(&request.message)?;
    let credential_request = CredentialRequest::<TaskveilCipherSuite>::deserialize(&client_message)
        .map_err(|_| AppError::bad_request("invalid opaque message"))?;

    let row = query::<Postgres>(
        "SELECT u.id, u.opaque_record, u.opaque_suite_id
             FROM users u WHERE lower(u.email) = lower($1)",
    )
    .bind(&email)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| AppError::not_found("account not found"))?;
    let user_id: Uuid = row.try_get("id").map_err(|_| AppError::internal())?;
    let stored_suite: i16 = row
        .try_get("opaque_suite_id")
        .map_err(|_| AppError::internal())?;
    if stored_suite != i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())? {
        return Err(AppError::bad_request("unsupported opaque suite"));
    }
    let mut membership_tx = pool.begin().await?;
    db::set_user_context(&mut membership_tx, user_id).await?;
    let tenant_id: Uuid = query::<Postgres>(
        "SELECT tenant_id FROM tenant_members
         WHERE user_id = $1 ORDER BY joined_at ASC LIMIT 1",
    )
    .bind(user_id)
    .fetch_one(&mut *membership_tx)
    .await?
    .try_get("tenant_id")
    .map_err(|_| AppError::internal())?;
    membership_tx.commit().await?;
    let record_bytes: Vec<u8> = row
        .try_get("opaque_record")
        .map_err(|_| AppError::internal())?;
    let server_record =
        TaskveilServerRegistration::deserialize(&record_bytes).map_err(|_| AppError::internal())?;
    let server_setup = get_or_create_server_setup(pool).await?;
    let mut rng = OsRng;
    let login_start = ServerLogin::start(
        &mut rng,
        &server_setup,
        Some(server_record),
        credential_request,
        email.as_bytes(),
        ServerLoginParameters::default(),
    )
    .map_err(|_| AppError::bad_request("invalid opaque message"))?;

    let state_id = Uuid::now_v7();
    let device_id = Uuid::now_v7();
    let device_challenge = random_device_challenge();
    let expires_at = Utc::now() + Duration::minutes(OPAQUE_STATE_TTL_MINUTES);
    query::<Postgres>(
        "INSERT INTO opaque_login_states
            (id, user_id, tenant_id, device_id, device_challenge, device_name,
             opaque_suite_id, server_login_state, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(state_id)
    .bind(user_id)
    .bind(tenant_id)
    .bind(device_id)
    .bind(device_challenge.as_slice())
    .bind(&device_name)
    .bind(i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())?)
    .bind(login_start.state.serialize().to_vec())
    .bind(expires_at)
    .execute(pool)
    .await?;

    Ok(OpaqueStartResponse {
        state_id,
        opaque_suite_id: CRYPTO_SUITE_ID,
        user_id,
        tenant_id,
        device_id,
        device_challenge: STANDARD.encode(device_challenge),
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
        CredentialFinalization::<TaskveilCipherSuite>::deserialize(&finalization)
            .map_err(|_| AppError::bad_request("invalid opaque message"))?;

    let mut tx = pool.begin().await?;
    let state = consume_login_state(&mut tx, request.state_id).await?;
    let server_login = TaskveilServerLogin::deserialize(&state.server_login_state)
        .map_err(|_| AppError::internal())?;
    server_login
        .finish(credential_finalization, ServerLoginParameters::default())
        .map_err(|_| AppError::unauthorized())?;

    db::set_user_context(&mut tx, state.user_id).await?;

    let tenant_id = state.tenant_id;
    db::set_tenant_context(&mut tx, tenant_id).await?;
    let key_bundle = load_account_key_bundle(&mut tx, state.user_id, tenant_id).await?;
    let device_id = state.device_id;
    insert_pending_device(
        &mut tx,
        device_id,
        state.user_id,
        &state.device_name,
        &state.device_challenge,
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
        device_challenge: STANDARD.encode(state.device_challenge),
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

pub async fn certify_device(
    pool: &PgPool,
    bearer_token: &str,
    enrollment: DeviceEnrollmentDto,
) -> Result<LogoutResponse, AppError> {
    let token_hash = hash_token(bearer_token);
    let mut tx = pool.begin().await?;
    let row = query::<Postgres>(
        "SELECT s.user_id, s.device_id, d.enrollment_challenge,
                d.enrollment_challenge_expires_at, u.account_root_public
         FROM sessions s
         JOIN devices d ON d.id = s.device_id AND d.user_id = s.user_id
         JOIN users u ON u.id = s.user_id
         WHERE s.token_hash = $1 AND s.expires_at > now()
           AND s.revoked_at IS NULL AND d.revoked_at IS NULL
           AND d.certificate IS NULL
           AND d.enrollment_challenge_expires_at > now()",
    )
    .bind(token_hash.as_slice())
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(AppError::unauthorized)?;
    let user_id: Uuid = row.try_get("user_id")?;
    let device_id: Uuid = row.try_get("device_id")?;
    let challenge: [u8; DEVICE_CHALLENGE_LEN] = row
        .try_get::<Vec<u8>, _>("enrollment_challenge")?
        .try_into()
        .map_err(|_| AppError::internal())?;
    let verified = verify_device_enrollment(
        &enrollment,
        user_id,
        device_id,
        &challenge,
        Utc::now().timestamp_millis(),
    )?;
    let stored_root: Vec<u8> = row.try_get("account_root_public")?;
    if stored_root != verified.account_root_public {
        return Err(AppError::bad_request("account root mismatch"));
    }
    db::set_user_context(&mut tx, user_id).await?;
    let updated = query::<Postgres>(
        "UPDATE devices
         SET certificate = $3, certificate_fingerprint = $4,
             key_expires_at = $5, certified_at = now(),
             enrollment_challenge = NULL,
             enrollment_challenge_expires_at = NULL
         WHERE id = $1 AND user_id = $2 AND certificate IS NULL
           AND revoked_at IS NULL",
    )
    .bind(device_id)
    .bind(user_id)
    .bind(&verified.certificate)
    .bind(verified.certificate_fingerprint.as_slice())
    .bind(verified.expires_at)
    .execute(&mut *tx)
    .await?;
    if updated.rows_affected() != 1 {
        return Err(AppError::conflict("device enrollment changed"));
    }
    tx.commit().await?;
    Ok(LogoutResponse {})
}

pub async fn update_key_wrappers(
    pool: &PgPool,
    bearer_token: &str,
    request: UpdateKeyWrappersRequest,
) -> Result<LogoutResponse, AppError> {
    if request.suite_id != CRYPTO_SUITE_ID
        || request.generation == 0
        || request.expected_wrapper_revision == 0
        || request.wrapper_revision != request.expected_wrapper_revision + 1
    {
        return Err(AppError::bad_request("invalid wrapper revision"));
    }
    let wrapped_password = STANDARD
        .decode(&request.wrapped_master_key_by_password)
        .map_err(|_| AppError::bad_request("invalid key wrapper"))?;
    let wrapped_recovery = STANDARD
        .decode(&request.wrapped_master_key_by_recovery)
        .map_err(|_| AppError::bad_request("invalid key wrapper"))?;
    if wrapped_password.is_empty() || wrapped_recovery.is_empty() {
        return Err(AppError::bad_request("invalid key wrapper"));
    }
    let token_hash = hash_token(bearer_token);
    let mut tx = pool.begin().await?;
    let session = query::<Postgres>(
        "SELECT s.user_id
         FROM sessions s
         JOIN devices d ON d.id = s.device_id AND d.user_id = s.user_id
         WHERE s.token_hash = $1 AND s.expires_at > now()
           AND s.revoked_at IS NULL AND d.revoked_at IS NULL
           AND d.certificate IS NOT NULL AND d.certified_at IS NOT NULL
           AND (d.key_expires_at IS NULL OR d.key_expires_at > now())",
    )
    .bind(token_hash.as_slice())
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(AppError::unauthorized)?;
    let user_id: Uuid = session.try_get("user_id")?;
    db::set_user_context(&mut tx, user_id).await?;
    let updated = query::<Postgres>(
        "UPDATE user_key_generations
         SET wrapper_revision = $4, wrapped_mk_by_password = $5,
             wrapped_mk_by_recovery = $6, updated_at = now()
         WHERE user_id = $1 AND generation = $2 AND suite_id = $3
           AND status = 'active' AND wrapper_revision = $7",
    )
    .bind(user_id)
    .bind(
        i64::try_from(request.generation)
            .map_err(|_| AppError::bad_request("invalid generation"))?,
    )
    .bind(i16::try_from(request.suite_id).map_err(|_| AppError::bad_request("invalid suite"))?)
    .bind(
        i64::try_from(request.wrapper_revision)
            .map_err(|_| AppError::bad_request("invalid wrapper revision"))?,
    )
    .bind(wrapped_password)
    .bind(wrapped_recovery)
    .bind(
        i64::try_from(request.expected_wrapper_revision)
            .map_err(|_| AppError::bad_request("invalid wrapper revision"))?,
    )
    .execute(&mut *tx)
    .await?;
    if updated.rows_affected() != 1 {
        return Err(AppError::conflict("stale wrapper revision"));
    }
    tx.commit().await?;
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
           AND d.revoked_at IS NULL
           AND d.certificate IS NOT NULL AND d.certified_at IS NOT NULL
           AND (d.key_expires_at IS NULL OR d.key_expires_at > now())",
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
        .unwrap_or_else(|| "Taskveil device".to_string())
        .trim()
        .to_string();
    if trimmed.is_empty() {
        "Taskveil device".to_string()
    } else {
        trimmed.chars().take(120).collect()
    }
}

fn validate_opaque_suite(suite_id: u16) -> Result<(), AppError> {
    if suite_id != CRYPTO_SUITE_ID {
        return Err(AppError::bad_request("unsupported opaque suite"));
    }
    Ok(())
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

fn decode_account_root_public(message: &str, error: &'static str) -> Result<Vec<u8>, AppError> {
    let bytes = decode_bytes_field(message, error)?;
    AccountRootPublicKeys::decode(&bytes).map_err(|_| AppError::bad_request(error))?;
    Ok(bytes)
}

fn random_device_challenge() -> [u8; DEVICE_CHALLENGE_LEN] {
    let mut challenge = [0u8; DEVICE_CHALLENGE_LEN];
    OsRng.fill_bytes(&mut challenge);
    challenge
}

async fn get_or_create_server_setup(pool: &PgPool) -> Result<TaskveilServerSetup, AppError> {
    let mut rng = OsRng;
    let generated = TaskveilServerSetup::new(&mut rng).serialize().to_vec();
    query::<Postgres>(
        "INSERT INTO opaque_server_setup (singleton, opaque_suite_id, setup)
         VALUES (TRUE, $1, $2)
         ON CONFLICT (singleton) DO NOTHING",
    )
    .bind(i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())?)
    .bind(&generated)
    .execute(pool)
    .await?;

    let bytes: Vec<u8> = query::<Postgres>(
        "SELECT setup FROM opaque_server_setup
             WHERE singleton = TRUE AND opaque_suite_id = $1",
    )
    .bind(i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())?)
    .fetch_one(pool)
    .await?
    .try_get("setup")
    .map_err(|_| AppError::internal())?;
    TaskveilServerSetup::deserialize(&bytes).map_err(|_| AppError::internal())
}

struct RegistrationState {
    user_id: Uuid,
    tenant_id: Uuid,
    device_id: Uuid,
    device_challenge: [u8; DEVICE_CHALLENGE_LEN],
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
         RETURNING user_id, tenant_id, device_id, device_challenge, email, device_name,
                   opaque_suite_id",
    )
    .bind(state_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| AppError::bad_request("invalid or expired opaque state"))?;
    let suite_id: i16 = row
        .try_get("opaque_suite_id")
        .map_err(|_| AppError::internal())?;
    if suite_id != i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())? {
        return Err(AppError::bad_request("unsupported opaque suite"));
    }
    Ok(RegistrationState {
        user_id: row.try_get("user_id").map_err(|_| AppError::internal())?,
        tenant_id: row.try_get("tenant_id").map_err(|_| AppError::internal())?,
        device_id: row.try_get("device_id").map_err(|_| AppError::internal())?,
        device_challenge: row
            .try_get::<Vec<u8>, _>("device_challenge")
            .map_err(|_| AppError::internal())?
            .try_into()
            .map_err(|_| AppError::internal())?,
        email: row.try_get("email").map_err(|_| AppError::internal())?,
        device_name: row
            .try_get("device_name")
            .map_err(|_| AppError::internal())?,
    })
}

struct LoginState {
    user_id: Uuid,
    tenant_id: Uuid,
    device_id: Uuid,
    device_challenge: [u8; DEVICE_CHALLENGE_LEN],
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
         RETURNING user_id, tenant_id, device_id, device_challenge, device_name,
                   opaque_suite_id, server_login_state",
    )
    .bind(state_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| AppError::bad_request("invalid or expired opaque state"))?;
    let suite_id: i16 = row
        .try_get("opaque_suite_id")
        .map_err(|_| AppError::internal())?;
    if suite_id != i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())? {
        return Err(AppError::bad_request("unsupported opaque suite"));
    }
    Ok(LoginState {
        user_id: row.try_get("user_id").map_err(|_| AppError::internal())?,
        tenant_id: row.try_get("tenant_id").map_err(|_| AppError::internal())?,
        device_id: row.try_get("device_id").map_err(|_| AppError::internal())?,
        device_challenge: row
            .try_get::<Vec<u8>, _>("device_challenge")
            .map_err(|_| AppError::internal())?
            .try_into()
            .map_err(|_| AppError::internal())?,
        device_name: row
            .try_get("device_name")
            .map_err(|_| AppError::internal())?,
        server_login_state: row
            .try_get("server_login_state")
            .map_err(|_| AppError::internal())?,
    })
}

struct DecodedAccountKeyBundle {
    suite_id: i16,
    generation: i64,
    tenant_generation: i64,
    wrapper_revision: i64,
    wrapped_master_key_by_password: Vec<u8>,
    wrapped_master_key_by_recovery: Vec<u8>,
    account_root_public: Vec<u8>,
    wrapped_account_root_private: Vec<u8>,
    wrapped_tenant_root_dek: Vec<u8>,
    tenant_key_manifest: Vec<u8>,
}

fn decode_account_key_bundle(
    bundle: &AccountKeyBundleDto,
) -> Result<DecodedAccountKeyBundle, AppError> {
    if bundle.suite_id != CRYPTO_SUITE_ID
        || bundle.generation != INITIAL_KEY_GENERATION
        || bundle.tenant_generation != INITIAL_KEY_GENERATION
        || bundle.wrapper_revision == 0
    {
        return Err(AppError::bad_request("invalid key bundle"));
    }
    Ok(DecodedAccountKeyBundle {
        suite_id: i16::try_from(bundle.suite_id)
            .map_err(|_| AppError::bad_request("invalid key bundle"))?,
        generation: i64::try_from(bundle.generation)
            .map_err(|_| AppError::bad_request("invalid key bundle"))?,
        tenant_generation: i64::try_from(bundle.tenant_generation)
            .map_err(|_| AppError::bad_request("invalid key bundle"))?,
        wrapper_revision: i64::try_from(bundle.wrapper_revision)
            .map_err(|_| AppError::bad_request("invalid key bundle"))?,
        wrapped_master_key_by_password: decode_bytes_field(
            &bundle.wrapped_master_key_by_password,
            "invalid key bundle",
        )?,
        wrapped_master_key_by_recovery: decode_bytes_field(
            &bundle.wrapped_master_key_by_recovery,
            "invalid key bundle",
        )?,
        account_root_public: decode_account_root_public(
            &bundle.account_root_public,
            "invalid key bundle",
        )?,
        wrapped_account_root_private: decode_bytes_field(
            &bundle.wrapped_account_root_private,
            "invalid key bundle",
        )?,
        wrapped_tenant_root_dek: decode_bytes_field(
            &bundle.wrapped_tenant_root_dek,
            "invalid key bundle",
        )?,
        tenant_key_manifest: decode_bytes_field(&bundle.tenant_key_manifest, "invalid key bundle")?,
    })
}

async fn insert_account_key_bundle(
    tx: &mut PgTransaction<'_>,
    user_id: Uuid,
    tenant_id: Uuid,
    bundle: DecodedAccountKeyBundle,
) -> Result<(), AppError> {
    query::<Postgres>(
        "INSERT INTO user_key_generations (
            user_id,
            status,
            suite_id,
            generation,
            wrapper_revision,
            wrapped_mk_by_password,
            wrapped_mk_by_recovery,
            account_root_public,
            wrapped_account_root_private
         ) VALUES ($1, 'active', $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(user_id)
    .bind(bundle.suite_id)
    .bind(bundle.generation)
    .bind(bundle.wrapper_revision)
    .bind(&bundle.wrapped_master_key_by_password)
    .bind(&bundle.wrapped_master_key_by_recovery)
    .bind(&bundle.account_root_public)
    .bind(&bundle.wrapped_account_root_private)
    .execute(&mut **tx)
    .await?;

    query::<Postgres>(
        "INSERT INTO tenant_key_generations
            (tenant_id, suite_id, generation, status, minimum_write_generation,
             signed_manifest, wrapped_tenant_root_dek, activated_at)
         VALUES ($1, $2, $3, 'active', $3, $4, $5, now())",
    )
    .bind(tenant_id)
    .bind(bundle.suite_id)
    .bind(bundle.tenant_generation)
    .bind(&bundle.tenant_key_manifest)
    .bind(&bundle.wrapped_tenant_root_dek)
    .execute(&mut **tx)
    .await?;

    Ok(())
}

async fn load_account_key_bundle(
    tx: &mut PgTransaction<'_>,
    user_id: Uuid,
    tenant_id: Uuid,
) -> Result<AccountKeyBundleDto, AppError> {
    let user = query::<Postgres>(
        "SELECT
            suite_id,
            generation,
            wrapper_revision,
            wrapped_mk_by_password AS wrapped_master_key_by_password,
            wrapped_mk_by_recovery AS wrapped_master_key_by_recovery,
            account_root_public,
            wrapped_account_root_private
         FROM user_key_generations
         WHERE user_id = $1 AND status = 'active'",
    )
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await?;
    let tenant = query::<Postgres>(
        "SELECT suite_id, generation, signed_manifest, wrapped_tenant_root_dek
         FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'active'",
    )
    .bind(tenant_id)
    .fetch_one(&mut **tx)
    .await?;
    let expected_suite: i16 = user.try_get("suite_id").map_err(|_| AppError::internal())?;
    let tenant_suite: i16 = tenant
        .try_get("suite_id")
        .map_err(|_| AppError::internal())?;
    let tenant_generation: i64 = tenant
        .try_get("generation")
        .map_err(|_| AppError::internal())?;
    if expected_suite != i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())?
        || expected_suite != tenant_suite
    {
        return Err(AppError::internal());
    }

    Ok(AccountKeyBundleDto {
        suite_id: u16::try_from(
            user.try_get::<i16, _>("suite_id")
                .map_err(|_| AppError::internal())?,
        )
        .map_err(|_| AppError::internal())?,
        generation: u64::try_from(
            user.try_get::<i64, _>("generation")
                .map_err(|_| AppError::internal())?,
        )
        .map_err(|_| AppError::internal())?,
        tenant_generation: u64::try_from(tenant_generation).map_err(|_| AppError::internal())?,
        wrapper_revision: u64::try_from(
            user.try_get::<i64, _>("wrapper_revision")
                .map_err(|_| AppError::internal())?,
        )
        .map_err(|_| AppError::internal())?,
        wrapped_master_key_by_password: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_master_key_by_password")
                .map_err(|_| AppError::internal())?,
        ),
        wrapped_master_key_by_recovery: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_master_key_by_recovery")
                .map_err(|_| AppError::internal())?,
        ),
        account_root_public: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("account_root_public")
                .map_err(|_| AppError::internal())?,
        ),
        wrapped_account_root_private: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_account_root_private")
                .map_err(|_| AppError::internal())?,
        ),
        wrapped_tenant_root_dek: STANDARD.encode(
            tenant
                .try_get::<Vec<u8>, _>("wrapped_tenant_root_dek")
                .map_err(|_| AppError::internal())?,
        ),
        tenant_key_manifest: STANDARD.encode(
            tenant
                .try_get::<Vec<u8>, _>("signed_manifest")
                .map_err(|_| AppError::internal())?,
        ),
    })
}

struct VerifiedEnrollment {
    account_root_public: Vec<u8>,
    certificate: Vec<u8>,
    certificate_fingerprint: [u8; DEVICE_FINGERPRINT_LEN],
    expires_at: DateTime<Utc>,
}

fn verify_device_enrollment(
    enrollment: &DeviceEnrollmentDto,
    user_id: Uuid,
    device_id: Uuid,
    challenge: &[u8; DEVICE_CHALLENGE_LEN],
    now_ms: i64,
) -> Result<VerifiedEnrollment, AppError> {
    if enrollment.suite_id != CRYPTO_SUITE_ID {
        return Err(AppError::bad_request("unsupported device suite"));
    }
    let account_root_public =
        decode_account_root_public(&enrollment.account_root_public, "invalid account root")?;
    let root = AccountRootPublicKeys::decode(&account_root_public)
        .map_err(|_| AppError::bad_request("invalid account root"))?;
    let certificate =
        decode_bytes_field(&enrollment.device_certificate, "invalid device certificate")?;
    let certificate_value = DeviceCertificate::decode(&certificate)
        .map_err(|_| AppError::bad_request("invalid device certificate"))?;
    if root.user_id != user_id
        || certificate_value.user_id != user_id
        || certificate_value.device_id != device_id
    {
        return Err(AppError::bad_request("device identity mismatch"));
    }
    verify_device_certificate(&certificate_value, &root, now_ms, false)
        .map_err(|_| AppError::bad_request("invalid device certificate"))?;
    let certificate_fingerprint: [u8; DEVICE_FINGERPRINT_LEN] = STANDARD
        .decode(&enrollment.certificate_fingerprint)
        .map_err(|_| AppError::bad_request("invalid device proof"))?
        .try_into()
        .map_err(|_| AppError::bad_request("invalid device proof"))?;
    let proof_signature: [u8; ED25519_SIGNATURE_LEN] = STANDARD
        .decode(&enrollment.proof_signature)
        .map_err(|_| AppError::bad_request("invalid device proof"))?
        .try_into()
        .map_err(|_| AppError::bad_request("invalid device proof"))?;
    let proof = DeviceProofOfPossession {
        certificate_fingerprint,
        signature: proof_signature,
    };
    verify_device_proof(&certificate_value, challenge, &proof)
        .map_err(|_| AppError::bad_request("invalid device proof"))?;
    let expires_at = DateTime::from_timestamp_millis(certificate_value.expires_at_ms)
        .ok_or_else(|| AppError::bad_request("invalid device certificate"))?;
    Ok(VerifiedEnrollment {
        account_root_public,
        certificate,
        certificate_fingerprint,
        expires_at,
    })
}

async fn insert_certified_device(
    tx: &mut PgTransaction<'_>,
    device_id: Uuid,
    user_id: Uuid,
    device_name: &str,
    enrollment: &VerifiedEnrollment,
) -> Result<(), AppError> {
    query::<Postgres>(
        "INSERT INTO devices
            (id, user_id, device_name, certificate, certificate_fingerprint,
             key_expires_at, certified_at)
         VALUES ($1, $2, $3, $4, $5, $6, now())",
    )
    .bind(device_id)
    .bind(user_id)
    .bind(device_name)
    .bind(&enrollment.certificate)
    .bind(enrollment.certificate_fingerprint.as_slice())
    .bind(enrollment.expires_at)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn insert_pending_device(
    tx: &mut PgTransaction<'_>,
    device_id: Uuid,
    user_id: Uuid,
    device_name: &str,
    challenge: &[u8; DEVICE_CHALLENGE_LEN],
) -> Result<(), AppError> {
    query::<Postgres>(
        "INSERT INTO devices
            (id, user_id, device_name, enrollment_challenge,
             enrollment_challenge_expires_at)
         VALUES ($1, $2, $3, $4, now() + interval '10 minutes')",
    )
    .bind(device_id)
    .bind(user_id)
    .bind(device_name)
    .bind(challenge.as_slice())
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
