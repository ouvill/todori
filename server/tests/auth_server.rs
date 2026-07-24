use axum::{
    body::Body,
    http::{Method, Request, StatusCode},
    Router,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::Value;
use sqlx_core::{query::query, raw_sql::raw_sql, row::Row};
use sqlx_postgres::{PgPool, Postgres};
use taskveil_server::{
    billing::{BillingEnvironment, BillingService},
    build_router, db, AppState,
};
use taskveil_sync::account::{unwrap_login_key_bundle, AccountClient, AccountKeyBundleDto};
use testcontainers_modules::{
    postgres,
    testcontainers::{runners::AsyncRunner, ContainerAsync},
};
use tower::ServiceExt;
use uuid::Uuid;

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
    raw_sql(
        "CREATE ROLE taskveil_runtime_test LOGIN PASSWORD 'taskveil-runtime-test'
         NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOBYPASSRLS",
    )
    .execute(&pool)
    .await
    .unwrap();
    raw_sql("GRANT taskveil_app TO taskveil_runtime_test")
        .execute(&pool)
        .await
        .unwrap();
    let application_url =
        format!("postgres://taskveil_runtime_test:taskveil-runtime-test@{host}:{port}/postgres");
    let application_pool = db::connect_application(&application_url).await.unwrap();
    let app = build_router(AppState {
        pool: application_pool,
        billing: BillingService::unavailable_for_tests(BillingEnvironment::Sandbox),
    });
    TestApp {
        app,
        pool,
        _postgres: postgres,
    }
}

#[tokio::test]
async fn account_register_login_logout_and_key_bundles_remain_available() {
    let test = setup().await;
    let health = test
        .app
        .clone()
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(health.status(), StatusCode::OK);
    let ready = test
        .app
        .clone()
        .oneshot(Request::get("/ready").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(ready.status(), StatusCode::OK);
    assert_eq!(
        request_status(
            &test.app,
            Method::POST,
            "/v1/auth/register/start".to_string(),
            None,
            Some(serde_json::json!({
                "email": "downgrade@example.com",
                "device_name": "downgrade",
                "opaque_suite_id": 1,
                "message": "invalid-but-suite-is-checked-first"
            })),
        )
        .await,
        StatusCode::BAD_REQUEST
    );

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let server_url = format!("http://{}", listener.local_addr().unwrap());
    let app = test.app.clone();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let client = AccountClient::new(&server_url).unwrap();
    let registered = client
        .register(
            "account-v2@example.com",
            "correct horse battery staple",
            Some("first device"),
            &[0x51; 32],
        )
        .await
        .unwrap();
    assert_eq!(registered.recovery_key.split_whitespace().count(), 24);
    assert!(client
        .register(
            "account-v2@example.com",
            "correct horse battery staple",
            Some("duplicate device"),
            &[0x52; 32],
        )
        .await
        .is_err());

    let user_id = Uuid::parse_str(&registered.session.user_id).unwrap();
    let tenant_id = Uuid::parse_str(&registered.session.tenant_id).unwrap();
    let tenant = query::<Postgres>(
        "SELECT kind, owner_user_id,
                (SELECT count(*) FROM tenant_members WHERE tenant_id = tenants.id) AS member_count,
                (SELECT count(*) FROM tenant_members
                 WHERE tenant_id = tenants.id AND user_id = $2 AND role = 'owner') AS owner_count
         FROM tenants WHERE id = $1",
    )
    .bind(tenant_id)
    .bind(user_id)
    .fetch_one(&test.pool)
    .await
    .unwrap();
    assert_eq!(tenant.try_get::<String, _>("kind").unwrap(), "personal");
    assert_eq!(tenant.try_get::<Uuid, _>("owner_user_id").unwrap(), user_id);
    assert_eq!(tenant.try_get::<i64, _>("member_count").unwrap(), 1);
    assert_eq!(tenant.try_get::<i64, _>("owner_count").unwrap(), 1);
    let stored = stored_key_bundle(&test.pool, user_id, tenant_id).await;
    assert!(unwrap_login_key_bundle(&stored, user_id, tenant_id, b"wrong export key").is_err());

    let logged_in = client
        .login(
            "account-v2@example.com",
            "correct horse battery staple",
            Some("second device"),
            &[0x53; 32],
        )
        .await
        .unwrap();
    assert_eq!(*registered.keys.master_key, *logged_in.keys.master_key);
    assert_eq!(
        registered.keys.account_root_public,
        logged_in.keys.account_root_public
    );
    assert_eq!(
        *registered.keys.tenant_root_dek,
        *logged_in.keys.tenant_root_dek
    );
    assert!(client
        .login(
            "account-v2@example.com",
            "wrong password",
            Some("wrong device"),
            &[0x54; 32],
        )
        .await
        .is_err());

    client
        .logout(&logged_in.session.session_token)
        .await
        .unwrap();
    assert_eq!(
        request_status(
            &test.app,
            Method::GET,
            format!("/v2/tenants/{tenant_id}/pull?since=0&limit=1"),
            Some(&logged_in.session.session_token),
            None,
        )
        .await,
        StatusCode::UNAUTHORIZED
    );

    let device_count: i64 =
        query::<Postgres>("SELECT count(*) AS count FROM devices WHERE user_id = $1")
            .bind(user_id)
            .fetch_one(&test.pool)
            .await
            .unwrap()
            .try_get("count")
            .unwrap();
    assert_eq!(device_count, 2);
    let revoked_device_count: i64 = query::<Postgres>(
        "SELECT count(*) AS count FROM devices WHERE user_id = $1 AND revoked_at IS NOT NULL",
    )
    .bind(user_id)
    .fetch_one(&test.pool)
    .await
    .unwrap()
    .try_get("count")
    .unwrap();
    assert_eq!(revoked_device_count, 0);
    let obsolete_public_key_columns: i64 = query::<Postgres>(
        "SELECT count(*) AS count FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = 'devices'
           AND column_name = 'public_key'",
    )
    .fetch_one(&test.pool)
    .await
    .unwrap()
    .try_get("count")
    .unwrap();
    assert_eq!(obsolete_public_key_columns, 0);
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

async fn stored_key_bundle(pool: &PgPool, user_id: Uuid, tenant_id: Uuid) -> AccountKeyBundleDto {
    let user = query::<Postgres>(
        "SELECT generation, wrapper_revision,
                wrapped_mk_by_password AS wrapped_master_key_by_password,
                wrapped_mk_by_recovery AS wrapped_master_key_by_recovery,
                account_root_public, wrapped_account_root_private
         FROM user_key_generations
         WHERE user_id = $1 AND status = 'active'",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .unwrap();
    let tenant = query::<Postgres>(
        "SELECT generation, signed_manifest, wrapped_tenant_root_dek
         FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'active'",
    )
    .bind(tenant_id)
    .fetch_one(pool)
    .await
    .unwrap();
    AccountKeyBundleDto {
        suite_id: 2,
        generation: u64::try_from(user.try_get::<i64, _>("generation").unwrap()).unwrap(),
        tenant_generation: u64::try_from(tenant.try_get::<i64, _>("generation").unwrap()).unwrap(),
        wrapper_revision: u64::try_from(user.try_get::<i64, _>("wrapper_revision").unwrap())
            .unwrap(),
        wrapped_master_key_by_password: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_master_key_by_password")
                .unwrap(),
        ),
        wrapped_master_key_by_recovery: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_master_key_by_recovery")
                .unwrap(),
        ),
        account_root_public: STANDARD
            .encode(user.try_get::<Vec<u8>, _>("account_root_public").unwrap()),
        wrapped_account_root_private: STANDARD.encode(
            user.try_get::<Vec<u8>, _>("wrapped_account_root_private")
                .unwrap(),
        ),
        wrapped_tenant_root_dek: STANDARD.encode(
            tenant
                .try_get::<Vec<u8>, _>("wrapped_tenant_root_dek")
                .unwrap(),
        ),
        tenant_key_manifest: STANDARD
            .encode(tenant.try_get::<Vec<u8>, _>("signed_manifest").unwrap()),
    }
}
