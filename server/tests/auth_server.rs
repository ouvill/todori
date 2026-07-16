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
use todori_crypto::organization::{
    generate_account_root, AccountRootPublicKeys, DeviceCertificate, HybridScopeKind,
    SignedDeviceRevocation,
};
use todori_server::{
    auth::AuthContext,
    billing::{BillingEnvironment, BillingService},
    build_router, db, sync, AppState,
};
use todori_sync::account::{
    unwrap_login_key_bundle, unwrap_organization_dek_from_verified_device, wrap_list_dek_bundle,
    wrap_organization_dek_for_verified_device, AccountClient, AccountClientError,
    AccountKeyBundleDto, ListDekBundleDto, OrganizationDekDelivery, OrganizationRosterTrust,
};
use todori_sync::organization::{
    verify_organization_active_bundle, OrganizationDeviceDto, OrganizationKeyManifest,
};
use todori_sync::{KeyManifest, KeyScope, RotationStatus, SyncEngine};
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
        registered.keys.account_root_public,
        logged_in.keys.account_root_public
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

    // Sync and realtime are Pro-only. This account test exercises those
    // authenticated APIs after explicitly granting the fixture entitlement;
    // registration itself must continue to create a Free account.
    query::<Postgres>(
        "WITH subscription AS (
             INSERT INTO billing_subscriptions
                (user_id, provider, environment, provider_subscription_id,
                 store_product_identifier, provider_product_id, status, gives_access,
                 current_period_ends_at, access_expires_at, will_renew,
                 provider_observed_at, last_seen_at)
             VALUES ($1, 'revenuecat', 'sandbox', 'auth-server-fixture',
                     'dev.todori.todori.pro.monthly', 'test-product', 'active', TRUE,
                     now() + interval '30 days', now() + interval '30 days', TRUE,
                     now(), now())
             RETURNING id
         )
         INSERT INTO account_entitlements
            (user_id, environment, lookup_key, status, gives_access,
             source_subscription_id, store_product_identifier, expires_at,
             will_renew, provider_observed_at)
         SELECT $1, 'sandbox', 'pro', 'active', TRUE, id,
                'dev.todori.todori.pro.monthly', now() + interval '30 days',
                TRUE, now()
         FROM subscription",
    )
    .bind(user_id)
    .execute(&test.pool)
    .await
    .unwrap();

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

    let member = client
        .register(
            "org-member@example.com",
            "member correct horse battery staple",
            Some("member device"),
            &[0x61; 32],
            vec![Uuid::now_v7()],
        )
        .await
        .unwrap();
    let member_user_id = Uuid::parse_str(&member.session.user_id).unwrap();
    let org_tenant_id = Uuid::now_v7();
    let initial_manifest = KeyManifest::organization_unsigned(
        KeyScope::Tenant,
        org_tenant_id,
        None,
        1,
        RotationStatus::Active,
        1,
        [0; 32],
        vec![
            registered
                .device_identity
                .certificate()
                .recipient_key_fingerprint()
                .unwrap(),
            logged_in
                .device_identity
                .certificate()
                .recipient_key_fingerprint()
                .unwrap(),
        ],
    )
    .unwrap();
    let initial_signed_manifest = OrganizationKeyManifest::sign(
        initial_manifest,
        &logged_in.keys.account_root_private,
        &logged_in.keys.account_root_public,
    )
    .unwrap();
    query::<Postgres>("INSERT INTO tenants (id, kind, owner_user_id) VALUES ($1, 'org', $2)")
        .bind(org_tenant_id)
        .bind(user_id)
        .execute(&test.pool)
        .await
        .unwrap();
    query::<Postgres>(
        "INSERT INTO tenant_members
            (tenant_id, user_id, role, verification_state, verified_at)
         VALUES ($1, $2, 'owner', 'verified', now())",
    )
    .bind(org_tenant_id)
    .bind(user_id)
    .execute(&test.pool)
    .await
    .unwrap();
    query::<Postgres>("INSERT INTO tenant_seq (tenant_id, last_seq) VALUES ($1, 0)")
        .bind(org_tenant_id)
        .execute(&test.pool)
        .await
        .unwrap();
    query::<Postgres>(
        "INSERT INTO tenant_key_generations
            (tenant_id, generation, suite_id, status, minimum_write_generation,
             signed_manifest, wrapped_tenant_root_dek, activated_at)
         VALUES ($1, 1, 2, 'active', 1, $2, ''::bytea, now())",
    )
    .bind(org_tenant_id)
    .bind(initial_signed_manifest.encode().unwrap())
    .execute(&test.pool)
    .await
    .unwrap();

    let invited = client
        .invite_organization_member(
            org_tenant_id,
            "org-member@example.com".to_string(),
            &logged_in.session.session_token,
        )
        .await
        .unwrap();
    assert_eq!(invited.member_user_id, member_user_id);
    assert_eq!(invited.verification_state, "unverified");
    assert!(matches!(
        client
            .organization_member_devices(
                org_tenant_id,
                member_user_id,
                OrganizationRosterTrust {
                    user_id: member_user_id,
                    root_public: &STANDARD
                        .encode(member.keys.account_root_public.encode().unwrap()),
                    minimum_revision: 0,
                    minimum_head_hash: [0; 32],
                },
                &logged_in.session.session_token,
            )
            .await,
        Err(AccountClientError::OrganizationVerification)
    ));
    let unverified_recipient = OrganizationDeviceDto {
        user_id: member_user_id,
        device_id: Uuid::parse_str(&member.session.device_id).unwrap(),
        account_root_public: STANDARD.encode(member.keys.account_root_public.encode().unwrap()),
        certificate: STANDARD.encode(member.device_identity.certificate().encode().unwrap()),
        certificate_fingerprint: STANDARD
            .encode(member.device_identity.certificate().fingerprint().unwrap()),
        revoked: false,
    };
    let tenant_dek = [0x91; 32];
    let unverified_package = wrap_organization_dek_for_verified_device(OrganizationDekDelivery {
        sender_identity: &logged_in.device_identity,
        sender_root: &logged_in.keys.account_root_public,
        recipient: &unverified_recipient,
        expected_recipient_root: &member.keys.account_root_public,
        scope_kind: HybridScopeKind::Tenant,
        scope_id: org_tenant_id,
        generation: 1,
        dek: &tenant_dek,
        now_ms: chrono::Utc::now().timestamp_millis(),
    })
    .unwrap();
    assert!(matches!(
        client
            .store_recipient_package(
                org_tenant_id,
                unverified_recipient.device_id,
                &unverified_package,
                &logged_in.session.session_token,
            )
            .await,
        Err(AccountClientError::Server(403))
    ));

    let owner_safety = client
        .organization_safety_number(
            org_tenant_id,
            member_user_id,
            &logged_in.session.session_token,
        )
        .await
        .unwrap();
    let owner_confirmed = client
        .confirm_organization_safety_number(
            org_tenant_id,
            member_user_id,
            owner_safety.digest.clone(),
            &logged_in.session.session_token,
        )
        .await
        .unwrap();
    assert_eq!(owner_confirmed.verification_state, "unverified");
    let member_safety = client
        .organization_safety_number(org_tenant_id, member_user_id, &member.session.session_token)
        .await
        .unwrap();
    assert_eq!(owner_safety.digest, member_safety.digest);
    let mutually_confirmed = client
        .confirm_organization_safety_number(
            org_tenant_id,
            member_user_id,
            member_safety.digest.clone(),
            &member.session.session_token,
        )
        .await
        .unwrap();
    assert_eq!(mutually_confirmed.verification_state, "verified");

    let substituted_root = generate_account_root(Uuid::now_v7()).unwrap().public;
    let substituted_root_encoded = STANDARD.encode(substituted_root.encode().unwrap());
    assert!(matches!(
        client
            .organization_member_devices(
                org_tenant_id,
                member_user_id,
                OrganizationRosterTrust {
                    user_id: member_user_id,
                    root_public: &substituted_root_encoded,
                    minimum_revision: 0,
                    minimum_head_hash: [0; 32],
                },
                &logged_in.session.session_token,
            )
            .await,
        Err(AccountClientError::OrganizationVerification)
    ));
    assert!(matches!(
        client
            .organization_owner_devices(
                org_tenant_id,
                member_user_id,
                OrganizationRosterTrust {
                    user_id: substituted_root.user_id,
                    root_public: &substituted_root_encoded,
                    minimum_revision: 0,
                    minimum_head_hash: [0; 32],
                },
                &member.session.session_token,
            )
            .await,
        Err(AccountClientError::OrganizationVerification)
    ));

    let recipient_devices = client
        .organization_member_devices(
            org_tenant_id,
            member_user_id,
            OrganizationRosterTrust {
                user_id: member_user_id,
                root_public: &mutually_confirmed.member_root_public,
                minimum_revision: 0,
                minimum_head_hash: [0; 32],
            },
            &logged_in.session.session_token,
        )
        .await
        .unwrap();
    let recipient_root = AccountRootPublicKeys::decode(
        &STANDARD
            .decode(&mutually_confirmed.member_root_public)
            .unwrap(),
    )
    .unwrap();
    let owner_roster = client
        .organization_owner_devices(
            org_tenant_id,
            member_user_id,
            OrganizationRosterTrust {
                user_id: logged_in.keys.account_root_public.user_id,
                root_public: &mutually_confirmed.owner_root_public,
                minimum_revision: 0,
                minimum_head_hash: [0; 32],
            },
            &member.session.session_token,
        )
        .await
        .unwrap();
    let owner_roster_revision = owner_roster.revision;
    let owner_devices = owner_roster.devices;
    let recipient_devices = recipient_devices.devices;
    let owner_root = AccountRootPublicKeys::decode(
        &STANDARD
            .decode(&mutually_confirmed.owner_root_public)
            .unwrap(),
    )
    .unwrap();
    let recipient_fingerprints = owner_devices
        .iter()
        .chain(recipient_devices.iter())
        .map(|device| {
            DeviceCertificate::decode(&STANDARD.decode(&device.certificate).unwrap())
                .unwrap()
                .recipient_key_fingerprint()
                .unwrap()
        })
        .collect::<Vec<_>>();
    let prepared_manifest = KeyManifest::organization_unsigned(
        KeyScope::Tenant,
        org_tenant_id,
        None,
        2,
        RotationStatus::Prepared,
        1,
        initial_signed_manifest.authenticated_hash().unwrap(),
        recipient_fingerprints.clone(),
    )
    .unwrap();
    let prepared_signed = OrganizationKeyManifest::sign(
        prepared_manifest,
        &logged_in.keys.account_root_private,
        &logged_in.keys.account_root_public,
    )
    .unwrap();
    let active_manifest = KeyManifest::organization_unsigned(
        KeyScope::Tenant,
        org_tenant_id,
        None,
        2,
        RotationStatus::Active,
        2,
        prepared_signed.authenticated_hash().unwrap(),
        recipient_fingerprints.clone(),
    )
    .unwrap();
    let active_signed = OrganizationKeyManifest::sign(
        active_manifest,
        &logged_in.keys.account_root_private,
        &logged_in.keys.account_root_public,
    )
    .unwrap();
    let rotation_auth = AuthContext {
        user_id,
        device_id: Uuid::parse_str(&logged_in.session.device_id).unwrap(),
    };
    sync::prepare_rotation(
        &test.pool,
        org_tenant_id,
        rotation_auth.clone(),
        sync::PrepareRotationRequest {
            suite_id: todori_crypto::CRYPTO_SUITE_ID,
            generation: 2,
            signed_manifest: STANDARD.encode(prepared_signed.encode().unwrap()),
            wrapped_tenant_root_dek: String::new(),
            list_keys: Vec::new(),
        },
    )
    .await
    .unwrap();

    let extra_owner = client
        .login(
            "account-v2@example.com",
            "correct horse battery staple",
            Some("recipient injection device"),
            &[0x55; 32],
        )
        .await
        .unwrap();
    let extra_owner_device = OrganizationDeviceDto {
        user_id,
        device_id: Uuid::parse_str(&extra_owner.session.device_id).unwrap(),
        account_root_public: STANDARD
            .encode(extra_owner.keys.account_root_public.encode().unwrap()),
        certificate: STANDARD.encode(extra_owner.device_identity.certificate().encode().unwrap()),
        certificate_fingerprint: STANDARD.encode(
            extra_owner
                .device_identity
                .certificate()
                .fingerprint()
                .unwrap(),
        ),
        revoked: false,
    };
    let injected_package = wrap_organization_dek_for_verified_device(OrganizationDekDelivery {
        sender_identity: &logged_in.device_identity,
        sender_root: &logged_in.keys.account_root_public,
        recipient: &extra_owner_device,
        expected_recipient_root: &owner_root,
        scope_kind: HybridScopeKind::Tenant,
        scope_id: org_tenant_id,
        generation: 2,
        dek: &tenant_dek,
        now_ms: chrono::Utc::now().timestamp_millis(),
    })
    .unwrap();
    assert!(matches!(
        client
            .store_recipient_package(
                org_tenant_id,
                extra_owner_device.device_id,
                &injected_package,
                &logged_in.session.session_token,
            )
            .await,
        Err(AccountClientError::Server(400))
    ));
    let second_org_tenant_id = Uuid::now_v7();
    query::<Postgres>("INSERT INTO tenants (id, kind, owner_user_id) VALUES ($1, 'org', $2)")
        .bind(second_org_tenant_id)
        .bind(user_id)
        .execute(&test.pool)
        .await
        .unwrap();
    query::<Postgres>(
        "INSERT INTO tenant_members
            (tenant_id, user_id, role, verification_state, verified_at)
         VALUES ($1, $2, 'owner', 'verified', now())",
    )
    .bind(second_org_tenant_id)
    .bind(user_id)
    .execute(&test.pool)
    .await
    .unwrap();
    let signed_revocation = SignedDeviceRevocation::sign(
        &logged_in.keys.account_root_private,
        &logged_in.keys.account_root_public,
        extra_owner_device.device_id,
        extra_owner
            .device_identity
            .certificate()
            .fingerprint()
            .unwrap(),
        owner_roster_revision + 1,
        chrono::Utc::now().timestamp_millis(),
        [0; 32],
    )
    .unwrap();
    client
        .revoke_organization_device(
            org_tenant_id,
            extra_owner_device.device_id,
            &signed_revocation,
            &logged_in.session.session_token,
        )
        .await
        .unwrap();
    let rotation_rows = query::<Postgres>(
        "SELECT id, rotation_required FROM tenants WHERE id = ANY($1) ORDER BY id",
    )
    .bind(vec![org_tenant_id, second_org_tenant_id])
    .fetch_all(&test.pool)
    .await
    .unwrap();
    assert_eq!(rotation_rows.len(), 2);
    assert!(rotation_rows
        .iter()
        .all(|row| row.try_get::<bool, _>("rotation_required").unwrap()));
    let refreshed_owner_roster = client
        .organization_owner_devices(
            org_tenant_id,
            member_user_id,
            OrganizationRosterTrust {
                user_id: logged_in.keys.account_root_public.user_id,
                root_public: &mutually_confirmed.owner_root_public,
                minimum_revision: 1,
                minimum_head_hash: signed_revocation.authenticated_hash().unwrap(),
            },
            &member.session.session_token,
        )
        .await
        .unwrap();
    assert_eq!(refreshed_owner_roster.revision, 1);
    assert!(refreshed_owner_roster
        .devices
        .iter()
        .all(|device| device.device_id != extra_owner_device.device_id));
    assert!(matches!(
        client
            .organization_owner_devices(
                org_tenant_id,
                member_user_id,
                OrganizationRosterTrust {
                    user_id: logged_in.keys.account_root_public.user_id,
                    root_public: &mutually_confirmed.owner_root_public,
                    minimum_revision: 2,
                    minimum_head_hash: signed_revocation.authenticated_hash().unwrap(),
                },
                &member.session.session_token,
            )
            .await,
        Err(AccountClientError::OrganizationVerification)
    ));

    for device in &owner_devices {
        let package = wrap_organization_dek_for_verified_device(OrganizationDekDelivery {
            sender_identity: &logged_in.device_identity,
            sender_root: &logged_in.keys.account_root_public,
            recipient: device,
            expected_recipient_root: &owner_root,
            scope_kind: HybridScopeKind::Tenant,
            scope_id: org_tenant_id,
            generation: 2,
            dek: &tenant_dek,
            now_ms: chrono::Utc::now().timestamp_millis(),
        })
        .unwrap();
        client
            .store_recipient_package(
                org_tenant_id,
                device.device_id,
                &package,
                &logged_in.session.session_token,
            )
            .await
            .unwrap();
    }
    for device in &recipient_devices {
        let package = wrap_organization_dek_for_verified_device(OrganizationDekDelivery {
            sender_identity: &logged_in.device_identity,
            sender_root: &logged_in.keys.account_root_public,
            recipient: device,
            expected_recipient_root: &recipient_root,
            scope_kind: HybridScopeKind::Tenant,
            scope_id: org_tenant_id,
            generation: 2,
            dek: &tenant_dek,
            now_ms: chrono::Utc::now().timestamp_millis(),
        })
        .unwrap();
        client
            .store_recipient_package(
                org_tenant_id,
                device.device_id,
                &package,
                &logged_in.session.session_token,
            )
            .await
            .unwrap();
    }
    sync::activate_rotation(
        &test.pool,
        org_tenant_id,
        rotation_auth,
        sync::ActivateRotationRequest {
            generation: 2,
            signed_manifest: STANDARD.encode(active_signed.encode().unwrap()),
            list_manifests: Vec::new(),
        },
    )
    .await
    .unwrap();
    let active_bundle = client
        .active_key_bundle(org_tenant_id, &member.session.session_token)
        .await
        .unwrap();
    verify_organization_active_bundle(
        &active_bundle,
        org_tenant_id,
        2,
        &owner_root,
        member.device_identity.certificate(),
        &recipient_fingerprints,
    )
    .unwrap();
    let received = client
        .load_recipient_package(
            org_tenant_id,
            HybridScopeKind::Tenant,
            org_tenant_id,
            2,
            &member.session.session_token,
        )
        .await
        .unwrap();
    let sender = owner_devices
        .iter()
        .find(|device| device.device_id.to_string() == logged_in.session.device_id)
        .unwrap();
    assert_eq!(
        *unwrap_organization_dek_from_verified_device(
            &member.device_identity,
            &member.keys.account_root_public,
            sender,
            &owner_root,
            &received,
            chrono::Utc::now().timestamp_millis(),
        )
        .unwrap(),
        tenant_dek
    );
    let changed_member_root =
        todori_crypto::organization::generate_account_root(member_user_id).unwrap();
    query::<Postgres>("UPDATE users SET account_root_public = $2 WHERE id = $1")
        .bind(member_user_id)
        .bind(changed_member_root.public.encode().unwrap())
        .execute(&test.pool)
        .await
        .unwrap();
    let changed_safety = client
        .organization_safety_number(org_tenant_id, member_user_id, &member.session.session_token)
        .await
        .unwrap();
    assert_eq!(changed_safety.verification_state, "unverified");
    assert_ne!(changed_safety.digest, mutually_confirmed.digest);

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
    assert_eq!(device_count, 3);
    let revoked_device_count: i64 = query::<Postgres>(
        "SELECT count(*) AS count FROM devices WHERE user_id = $1 AND revoked_at IS NOT NULL",
    )
    .bind(user_id)
    .fetch_one(&test.pool)
    .await
    .unwrap()
    .try_get("count")
    .unwrap();
    assert_eq!(revoked_device_count, 1);
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
