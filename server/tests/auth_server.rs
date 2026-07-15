use axum::{
    body::Body,
    http::{Method, Request, StatusCode},
    Router,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::Value;
use sqlx_core::{query::query, raw_sql::raw_sql, row::Row};
use sqlx_postgres::{PgPool, Postgres};
use testcontainers_modules::{
    postgres,
    testcontainers::{runners::AsyncRunner, ContainerAsync},
};
use todori_server::{build_router, db, AppState};
use todori_sync::account::{
    unwrap_login_key_bundle, wrap_list_dek_bundle, AccountClient, AccountClientError,
    AccountKeyBundleDto, ListDekBundleDto,
};
use todori_sync::SyncEngine;
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
        "CREATE ROLE todori_runtime_test LOGIN PASSWORD 'todori-runtime-test'
         NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOBYPASSRLS",
    )
    .execute(&pool)
    .await
    .unwrap();
    raw_sql("GRANT todori_app TO todori_runtime_test")
        .execute(&pool)
        .await
        .unwrap();
    let application_url =
        format!("postgres://todori_runtime_test:todori-runtime-test@{host}:{port}/postgres");
    let application_pool = db::connect_application(&application_url).await.unwrap();
    let app = build_router(AppState {
        pool: application_pool,
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
            vec![Uuid::now_v7()],
        )
        .await
        .unwrap();
    assert_eq!(registered.recovery_key.split_whitespace().count(), 24);
    assert_eq!(registered.keys.list_deks.len(), 1);
    assert!(client
        .register(
            "account-v2@example.com",
            "correct horse battery staple",
            Some("duplicate device"),
            &[0x52; 32],
            vec![],
        )
        .await
        .is_err());

    let user_id = Uuid::parse_str(&registered.session.user_id).unwrap();
    let tenant_id = Uuid::parse_str(&registered.session.tenant_id).unwrap();
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
    assert!(client
        .login(
            "account-v2@example.com",
            "wrong password",
            Some("wrong device"),
            &[0x54; 32],
        )
        .await
        .is_err());

    let sync = SyncEngine::new(
        &server_url,
        tenant_id,
        logged_in.session.session_token.to_string(),
    )
    .unwrap();
    sync.preflight(0).await.unwrap();
    let closure = sync.pull_page(0, 100).await.unwrap();
    sync.ack_continuity(closure.closure_proof.unwrap())
        .await
        .unwrap();

    let added_list_id = Uuid::now_v7();
    let added_list_dek = [0x7a; 32];
    let added_bundle = wrap_list_dek_bundle(
        tenant_id,
        added_list_id,
        1,
        &added_list_dek,
        &logged_in.keys.master_key,
    )
    .unwrap();
    client
        .upsert_list_key_bundle(
            tenant_id,
            &logged_in.session.session_token,
            added_bundle.clone(),
        )
        .await
        .unwrap();
    client
        .upsert_list_key_bundle(
            tenant_id,
            &logged_in.session.session_token,
            added_bundle.clone(),
        )
        .await
        .unwrap();
    let conflicting = wrap_list_dek_bundle(
        tenant_id,
        added_list_id,
        1,
        &[0x7b; 32],
        &logged_in.keys.master_key,
    )
    .unwrap();
    assert!(matches!(
        client
            .upsert_list_key_bundle(tenant_id, &logged_in.session.session_token, conflicting,)
            .await,
        Err(AccountClientError::KeyBundleConflict)
    ));
    let listed = client
        .list_key_bundles(tenant_id, &logged_in.session.session_token)
        .await
        .unwrap();
    assert!(listed.iter().any(|bundle| bundle.list_id == added_list_id));
    assert_eq!(
        listed.iter().find(|bundle| bundle.list_id == added_list_id),
        Some(&added_bundle)
    );

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
                user_public_key, wrapped_user_secret_key
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
    let list_rows = query::<Postgres>(
        "SELECT list_id, generation, signed_manifest, wrapped_list_dek
         FROM list_key_generations
         WHERE tenant_id = $1 AND status = 'active'
         ORDER BY created_at ASC, list_id ASC",
    )
    .bind(tenant_id)
    .fetch_all(pool)
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
        tenant_key_manifest: STANDARD
            .encode(tenant.try_get::<Vec<u8>, _>("signed_manifest").unwrap()),
        list_deks: list_rows
            .into_iter()
            .map(|row| ListDekBundleDto {
                list_id: row.try_get("list_id").unwrap(),
                generation: u64::try_from(row.try_get::<i64, _>("generation").unwrap()).unwrap(),
                wrapped_list_dek: STANDARD
                    .encode(row.try_get::<Vec<u8>, _>("wrapped_list_dek").unwrap()),
                signed_manifest: STANDARD
                    .encode(row.try_get::<Vec<u8>, _>("signed_manifest").unwrap()),
            })
            .collect(),
    }
}
