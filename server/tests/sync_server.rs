use axum::{
    body::{to_bytes, Body},
    http::{Method, Request, StatusCode},
    Router,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::Utc;
use opaque_ke::{
    ClientLogin, ClientLoginFinishParameters, ClientRegistration,
    ClientRegistrationFinishParameters, CredentialResponse, RegistrationResponse,
};
use rand::rngs::OsRng;
use serde::de::DeserializeOwned;
use serde_json::{json, Value};
use sqlx_core::{query::query, raw_sql::raw_sql, row::Row};
use sqlx_postgres::{PgPool, Postgres};
use std::sync::OnceLock;
use testcontainers_modules::{
    postgres,
    testcontainers::{runners::AsyncRunner, ContainerAsync},
};
use todori_crypto::TodoriCipherSuite;
use todori_server::{
    auth::{
        cleanup_expired_opaque_states, LoginSessionResponse, OpaqueStartResponse, SessionResponse,
    },
    build_router, db,
    sync::MAX_PUSH_OPS,
    AppState,
};
use todori_sync::account::{
    unwrap_login_key_bundle, AccountClient, AccountKeyBundleDto, ListDekBundleDto,
};
use todori_sync::{Hlc, MAX_ENCRYPTED_BLOB_LEN};
use tower::ServiceExt;
use uuid::Uuid;

const PASSWORD: &[u8] = b"correct horse battery staple";
const WRONG_PASSWORD: &[u8] = b"correct horse battery stapler";

struct TestApp {
    app: Router,
    pool: PgPool,
    _postgres: ContainerAsync<postgres::Postgres>,
}

async fn setup() -> TestApp {
    let postgres = postgres::Postgres::default().start().await.unwrap();
    let host = postgres.get_host().await.unwrap();
    let port = postgres.get_host_port_ipv4(5432).await.unwrap();
    let database_url = format!("postgres://postgres:postgres@{host}:{port}/postgres");
    let pool = db::connect(&database_url).await.unwrap();
    db::run_migrations(&pool).await.unwrap();
    let app = build_router(AppState { pool: pool.clone() });
    TestApp {
        app,
        pool,
        _postgres: postgres,
    }
}

fn test_argon2() -> &'static argon2::Argon2<'static> {
    static ARGON2: OnceLock<argon2::Argon2<'static>> = OnceLock::new();
    ARGON2.get_or_init(|| {
        let params = argon2::Params::new(512, 1, 1, None).unwrap();
        argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params)
    })
}

fn registration_parameters<'a>() -> ClientRegistrationFinishParameters<'a, 'a, TodoriCipherSuite> {
    ClientRegistrationFinishParameters {
        ksf: Some(test_argon2()),
        ..Default::default()
    }
}

fn login_parameters<'a>() -> ClientLoginFinishParameters<'a, 'a, 'a, TodoriCipherSuite> {
    ClientLoginFinishParameters {
        ksf: Some(test_argon2()),
        ..Default::default()
    }
}

fn test_key_bundle() -> AccountKeyBundleDto {
    AccountKeyBundleDto {
        wrapped_master_key_by_password: STANDARD.encode(b"wrapped-mk-password"),
        wrapped_master_key_by_recovery: STANDARD.encode(b"wrapped-mk-recovery"),
        user_public_key: STANDARD.encode([0x11; 32]),
        wrapped_user_secret_key: STANDARD.encode(b"wrapped-user-secret-key"),
        wrapped_tenant_root_dek: STANDARD.encode(b"wrapped-tenant-root-dek"),
        list_deks: vec![ListDekBundleDto {
            list_id: Uuid::now_v7(),
            wrapped_list_dek: STANDARD.encode(b"wrapped-list-dek"),
        }],
    }
}

fn test_device_public_key() -> String {
    STANDARD.encode([0x22; 32])
}

async fn request_json<T: DeserializeOwned>(
    app: &Router,
    method: Method,
    uri: String,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, T) {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    if body.is_some() {
        builder = builder.header("content-type", "application/json");
    }
    let body = body
        .map(|value| Body::from(serde_json::to_vec(&value).unwrap()))
        .unwrap_or_else(Body::empty);
    let response = app
        .clone()
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}

async fn request_status(
    app: &Router,
    method: Method,
    uri: String,
    token: Option<&str>,
    body: Option<Value>,
) -> StatusCode {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    if body.is_some() {
        builder = builder.header("content-type", "application/json");
    }
    let body = body
        .map(|value| Body::from(serde_json::to_vec(&value).unwrap()))
        .unwrap_or_else(Body::empty);
    app.clone()
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap()
        .status()
}

async fn register(app: &Router, email: &str, password: &[u8]) -> SessionResponse {
    let mut rng = OsRng;
    let client_start = ClientRegistration::<TodoriCipherSuite>::start(&mut rng, password).unwrap();
    let (_, start): (StatusCode, OpaqueStartResponse) = request_json(
        app,
        Method::POST,
        "/v1/auth/register/start".to_string(),
        None,
        Some(json!({
            "email": email,
            "device_name": "test device",
            "message": STANDARD.encode(client_start.message.serialize()),
        })),
    )
    .await;
    let server_message = RegistrationResponse::<TodoriCipherSuite>::deserialize(
        &STANDARD.decode(start.message).unwrap(),
    )
    .unwrap();
    let client_finish = client_start
        .state
        .finish(
            &mut rng,
            password,
            server_message,
            registration_parameters(),
        )
        .unwrap();
    let (status, session): (StatusCode, SessionResponse) = request_json(
        app,
        Method::POST,
        "/v1/auth/register/finish".to_string(),
        None,
        Some(json!({
            "state_id": start.state_id,
            "message": STANDARD.encode(client_finish.message.serialize()),
            "key_bundle": test_key_bundle(),
            "device_public_key": test_device_public_key(),
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    session
}

async fn login(app: &Router, email: &str, password: &[u8]) -> SessionResponse {
    let mut rng = OsRng;
    let client_start = ClientLogin::<TodoriCipherSuite>::start(&mut rng, password).unwrap();
    let (status, start): (StatusCode, OpaqueStartResponse) = request_json(
        app,
        Method::POST,
        "/v1/auth/login/start".to_string(),
        None,
        Some(json!({
            "email": email,
            "device_name": "second device",
            "message": STANDARD.encode(client_start.message.serialize()),
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let server_message = CredentialResponse::<TodoriCipherSuite>::deserialize(
        &STANDARD.decode(start.message).unwrap(),
    )
    .unwrap();
    let client_finish = client_start
        .state
        .finish(password, server_message, login_parameters())
        .unwrap();
    let (status, login_response): (StatusCode, LoginSessionResponse) = request_json(
        app,
        Method::POST,
        "/v1/auth/login/finish".to_string(),
        None,
        Some(json!({
            "state_id": start.state_id,
            "message": STANDARD.encode(client_finish.message.serialize()),
            "device_public_key": test_device_public_key(),
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    login_response.session
}

fn encoded_hlc(wall_delta_ms: i64, counter: u32, device: &str) -> String {
    Hlc {
        wall_ms: Utc::now().timestamp_millis() + wall_delta_ms,
        counter,
        device_id: device.to_string(),
    }
    .encode()
    .unwrap()
}

fn push_body(record_id: Uuid, hlc: &str, blob: &[u8]) -> Value {
    json!({
        "ops": [{
            "record_id": record_id,
            "collection": "tasks",
            "hlc": hlc,
            "deleted": false,
            "blob": STANDARD.encode(blob),
        }]
    })
}

#[tokio::test]
async fn migration_creates_sync_server_schema_and_health_works() {
    let test = setup().await;
    let (status, body): (StatusCode, Value) =
        request_json(&test.app, Method::GET, "/health".to_string(), None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, json!({ "status": "ok" }));

    for table in [
        "users",
        "devices",
        "tenants",
        "sessions",
        "opaque_registration_states",
        "opaque_login_states",
        "user_key_bundles",
        "tenant_key_bundles",
        "list_key_bundles",
        "sync_records",
        "tenant_seq",
        "sync_records_history",
    ] {
        let exists: bool = query::<Postgres>(
            "SELECT EXISTS (
                 SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'public' AND table_name = $1
             )",
        )
        .bind(table)
        .fetch_one(&test.pool)
        .await
        .unwrap()
        .try_get("exists")
        .unwrap();
        assert!(exists, "{table} should exist");
    }
}

#[tokio::test]
async fn opaque_registration_login_reuse_expiry_and_cleanup_are_enforced() {
    let test = setup().await;
    let session = register(&test.app, "alice@example.com", PASSWORD).await;
    assert!(!session.session_token.is_empty());

    let reused_status = request_status(
        &test.app,
        Method::POST,
        "/v1/auth/register/finish".to_string(),
        None,
        Some(json!({
            "state_id": Uuid::now_v7(),
            "message": STANDARD.encode([0u8; 64]),
            "key_bundle": test_key_bundle(),
            "device_public_key": test_device_public_key(),
        })),
    )
    .await;
    assert_eq!(reused_status, StatusCode::BAD_REQUEST);

    let login_session = login(&test.app, "alice@example.com", PASSWORD).await;
    assert_ne!(login_session.device_id, session.device_id);

    let mut rng = OsRng;
    let wrong_start = ClientLogin::<TodoriCipherSuite>::start(&mut rng, WRONG_PASSWORD).unwrap();
    let (_, start): (StatusCode, OpaqueStartResponse) = request_json(
        &test.app,
        Method::POST,
        "/v1/auth/login/start".to_string(),
        None,
        Some(json!({
            "email": "alice@example.com",
            "device_name": "wrong device",
            "message": STANDARD.encode(wrong_start.message.serialize()),
        })),
    )
    .await;
    let server_message = CredentialResponse::<TodoriCipherSuite>::deserialize(
        &STANDARD.decode(start.message).unwrap(),
    )
    .unwrap();
    assert!(wrong_start
        .state
        .finish(WRONG_PASSWORD, server_message, login_parameters())
        .is_err());

    let expired_start = ClientLogin::<TodoriCipherSuite>::start(&mut rng, PASSWORD).unwrap();
    let (_, expired): (StatusCode, OpaqueStartResponse) = request_json(
        &test.app,
        Method::POST,
        "/v1/auth/login/start".to_string(),
        None,
        Some(json!({
            "email": "alice@example.com",
            "device_name": "expired device",
            "message": STANDARD.encode(expired_start.message.serialize()),
        })),
    )
    .await;
    raw_sql("UPDATE opaque_login_states SET expires_at = now() - interval '1 second'")
        .execute(&test.pool)
        .await
        .unwrap();
    let expired_finish = request_status(
        &test.app,
        Method::POST,
        "/v1/auth/login/finish".to_string(),
        None,
        Some(json!({
            "state_id": expired.state_id,
            "message": STANDARD.encode([0u8; 64]),
            "device_public_key": test_device_public_key(),
        })),
    )
    .await;
    assert_eq!(expired_finish, StatusCode::BAD_REQUEST);
    assert_eq!(cleanup_expired_opaque_states(&test.pool).await.unwrap(), 2);
}

#[tokio::test]
async fn push_pull_seq_invariants_tenant_isolation_and_revoked_devices_are_enforced() {
    let test = setup().await;
    let alice = register(&test.app, "alice-sync@example.com", PASSWORD).await;
    let bob = register(&test.app, "bob-sync@example.com", PASSWORD).await;
    let record_id = Uuid::now_v7();
    let hlc1 = encoded_hlc(0, 0, "device-a");
    let blob1 = b"encrypted-state-v1".to_vec();

    let (status, accepted): (StatusCode, Value) = request_json(
        &test.app,
        Method::POST,
        format!("/v1/tenants/{}/push", alice.tenant_id),
        Some(&alice.session_token),
        Some(push_body(record_id, &hlc1, &blob1)),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(accepted["results"][0]["status"], "accepted");
    assert_eq!(accepted["results"][0]["seq"], 1);

    let (status, pulled): (StatusCode, Value) = request_json(
        &test.app,
        Method::GET,
        format!("/v1/tenants/{}/pull?since=0&limit=1", alice.tenant_id),
        Some(&alice.session_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(pulled["records"][0]["record_id"], record_id.to_string());
    assert_eq!(pulled["records"][0]["seq"], 1);
    assert_eq!(pulled["has_more"], false);

    let (status, no_op): (StatusCode, Value) = request_json(
        &test.app,
        Method::POST,
        format!("/v1/tenants/{}/push", alice.tenant_id),
        Some(&alice.session_token),
        Some(push_body(record_id, &hlc1, &blob1)),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(no_op["results"][0]["status"], "no_op");

    let lower_hlc = encoded_hlc(-1_000, 0, "device-a");
    let (status, superseded): (StatusCode, Value) = request_json(
        &test.app,
        Method::POST,
        format!("/v1/tenants/{}/push", alice.tenant_id),
        Some(&alice.session_token),
        Some(push_body(record_id, &lower_hlc, b"older")),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(superseded["results"][0]["status"], "superseded");

    let conflict_status = request_status(
        &test.app,
        Method::POST,
        format!("/v1/tenants/{}/push", alice.tenant_id),
        Some(&alice.session_token),
        Some(push_body(record_id, &hlc1, b"different")),
    )
    .await;
    assert_eq!(conflict_status, StatusCode::CONFLICT);

    let hlc2 = encoded_hlc(0, 1, "device-a");
    let (status, updated): (StatusCode, Value) = request_json(
        &test.app,
        Method::POST,
        format!("/v1/tenants/{}/push", alice.tenant_id),
        Some(&alice.session_token),
        Some(push_body(record_id, &hlc2, b"encrypted-state-v2")),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(updated["results"][0]["status"], "accepted");
    assert_eq!(updated["results"][0]["seq"], 2);
    let history_author: Uuid =
        query::<Postgres>("SELECT author_user_id FROM sync_records_history WHERE tenant_id = $1")
            .bind(alice.tenant_id)
            .fetch_one(&test.pool)
            .await
            .unwrap()
            .try_get("author_user_id")
            .unwrap();
    assert_eq!(history_author, alice.user_id);

    let other_tenant_status = request_status(
        &test.app,
        Method::POST,
        format!("/v1/tenants/{}/push", bob.tenant_id),
        Some(&alice.session_token),
        Some(push_body(
            Uuid::now_v7(),
            &encoded_hlc(0, 0, "device-a"),
            b"x",
        )),
    )
    .await;
    assert_eq!(other_tenant_status, StatusCode::UNAUTHORIZED);

    let missing_token_status = request_status(
        &test.app,
        Method::GET,
        format!("/v1/tenants/{}/pull?since=0&limit=1", alice.tenant_id),
        None,
        None,
    )
    .await;
    assert_eq!(missing_token_status, StatusCode::UNAUTHORIZED);

    let future_status = request_status(
        &test.app,
        Method::POST,
        format!("/v1/tenants/{}/push", alice.tenant_id),
        Some(&alice.session_token),
        Some(push_body(
            Uuid::now_v7(),
            &encoded_hlc(6 * 60 * 1000, 0, "device-a"),
            b"x",
        )),
    )
    .await;
    assert_eq!(future_status, StatusCode::BAD_REQUEST);

    let large_blob = vec![0u8; MAX_ENCRYPTED_BLOB_LEN + 1];
    let blob_status = request_status(
        &test.app,
        Method::POST,
        format!("/v1/tenants/{}/push", alice.tenant_id),
        Some(&alice.session_token),
        Some(push_body(
            Uuid::now_v7(),
            &encoded_hlc(0, 0, "device-a"),
            &large_blob,
        )),
    )
    .await;
    assert_eq!(blob_status, StatusCode::BAD_REQUEST);

    let ops = (0..=MAX_PUSH_OPS)
        .map(|_| {
            json!({
                "record_id": Uuid::now_v7(),
                "collection": "tasks",
                "hlc": encoded_hlc(0, 0, "device-a"),
                "deleted": false,
                "blob": STANDARD.encode(b"x"),
            })
        })
        .collect::<Vec<_>>();
    let batch_status = request_status(
        &test.app,
        Method::POST,
        format!("/v1/tenants/{}/push", alice.tenant_id),
        Some(&alice.session_token),
        Some(json!({ "ops": ops })),
    )
    .await;
    assert_eq!(batch_status, StatusCode::BAD_REQUEST);

    let limit_status = request_status(
        &test.app,
        Method::GET,
        format!("/v1/tenants/{}/pull?since=0&limit=101", alice.tenant_id),
        Some(&alice.session_token),
        None,
    )
    .await;
    assert_eq!(limit_status, StatusCode::BAD_REQUEST);

    let delete_status = request_status(
        &test.app,
        Method::DELETE,
        format!("/v1/tenants/{}/push", alice.tenant_id),
        Some(&alice.session_token),
        None,
    )
    .await;
    assert_eq!(delete_status, StatusCode::METHOD_NOT_ALLOWED);

    query::<Postgres>("UPDATE devices SET revoked_at = now() WHERE id = $1")
        .bind(alice.device_id)
        .execute(&test.pool)
        .await
        .unwrap();
    let revoked_status = request_status(
        &test.app,
        Method::GET,
        format!("/v1/tenants/{}/pull?since=0&limit=1", alice.tenant_id),
        Some(&alice.session_token),
        None,
    )
    .await;
    assert_eq!(revoked_status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn account_client_register_logout_login_restores_keys_and_rejects_invalid_states() {
    let test = setup().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let server_url = format!("http://{}", listener.local_addr().unwrap());
    let app = test.app.clone();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let client = AccountClient::new(&server_url).unwrap();
    let device_key_a = [0x51; 32];
    let registered = client
        .register(
            "account-client@example.com",
            "correct horse battery staple",
            Some("first test device"),
            &device_key_a,
        )
        .await
        .unwrap();
    assert_eq!(registered.recovery_key.split_whitespace().count(), 24);
    assert_eq!(registered.keys.list_deks.len(), 1);

    let stored_bundle = stored_key_bundle(
        &test.pool,
        Uuid::parse_str(&registered.session.user_id).unwrap(),
        Uuid::parse_str(&registered.session.tenant_id).unwrap(),
    )
    .await;
    assert!(unwrap_login_key_bundle(&stored_bundle, b"wrong export key").is_err());

    client
        .logout(&registered.session.session_token)
        .await
        .unwrap();
    let revoked_status = request_status(
        &test.app,
        Method::GET,
        format!(
            "/v1/tenants/{}/pull?since=0&limit=1",
            registered.session.tenant_id
        ),
        Some(&registered.session.session_token),
        None,
    )
    .await;
    assert_eq!(revoked_status, StatusCode::UNAUTHORIZED);

    let device_key_b = [0x52; 32];
    let logged_in = client
        .login(
            "account-client@example.com",
            "correct horse battery staple",
            Some("second test device"),
            &device_key_b,
        )
        .await
        .unwrap();
    assert_eq!(*registered.keys.master_key, *logged_in.keys.master_key);
    assert_eq!(
        *registered.keys.user_secret_key,
        *logged_in.keys.user_secret_key
    );
    assert_eq!(
        *registered.keys.tenant_root_dek,
        *logged_in.keys.tenant_root_dek
    );
    assert_eq!(
        *registered.keys.list_deks[0].dek,
        *logged_in.keys.list_deks[0].dek
    );
    assert_ne!(
        registered.local_wrapped_master_key,
        logged_in.local_wrapped_master_key
    );

    assert!(client
        .login(
            "account-client@example.com",
            "wrong password",
            Some("wrong test device"),
            &device_key_b,
        )
        .await
        .is_err());

    let device_count: i64 = query::<Postgres>(
        "SELECT count(*) FROM devices WHERE user_id = $1 AND public_key IS NOT NULL",
    )
    .bind(Uuid::parse_str(&registered.session.user_id).unwrap())
    .fetch_one(&test.pool)
    .await
    .unwrap()
    .try_get("count")
    .unwrap();
    assert_eq!(device_count, 2);
}

async fn stored_key_bundle(pool: &PgPool, user_id: Uuid, tenant_id: Uuid) -> AccountKeyBundleDto {
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
    .fetch_one(pool)
    .await
    .unwrap();
    let tenant = query::<Postgres>(
        "SELECT wrapped_tenant_root_dek
         FROM tenant_key_bundles
         WHERE tenant_id = $1",
    )
    .bind(tenant_id)
    .fetch_one(pool)
    .await
    .unwrap();
    let list_rows = query::<Postgres>(
        "SELECT list_id, wrapped_list_dek
         FROM list_key_bundles
         WHERE tenant_id = $1
         ORDER BY created_at ASC, list_id ASC",
    )
    .bind(tenant_id)
    .fetch_all(pool)
    .await
    .unwrap();

    AccountKeyBundleDto {
        wrapped_master_key_by_password: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_master_key_by_password")
                .unwrap(),
        ),
        wrapped_master_key_by_recovery: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_master_key_by_recovery")
                .unwrap(),
        ),
        user_public_key: STANDARD.encode(user.try_get::<Vec<u8>, _>("user_public_key").unwrap()),
        wrapped_user_secret_key: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_user_secret_key")
                .unwrap(),
        ),
        wrapped_tenant_root_dek: STANDARD.encode(
            tenant
                .try_get::<Vec<u8>, _>("wrapped_tenant_root_dek")
                .unwrap(),
        ),
        list_deks: list_rows
            .into_iter()
            .map(|row| ListDekBundleDto {
                list_id: row.try_get("list_id").unwrap(),
                wrapped_list_dek: STANDARD
                    .encode(row.try_get::<Vec<u8>, _>("wrapped_list_dek").unwrap()),
            })
            .collect(),
    }
}
