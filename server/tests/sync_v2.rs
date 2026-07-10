use std::{
    future::Future,
    pin::Pin,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
};

use axum::{
    body::{to_bytes, Body},
    http::{Method, Request, StatusCode},
    Router,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::{Duration, Utc};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use sqlx_core::{query::query, row::Row};
use sqlx_postgres::PgPool;
use tempfile::TempDir;
use testcontainers_modules::{
    postgres,
    testcontainers::{runners::AsyncRunner, ContainerAsync},
};
use todori_app_bridge::BridgeSyncStore;
use todori_client::{Client, LocalMutationContext, UpdateTaskInput};
use todori_server::{
    auth::AuthContext,
    build_router, db,
    sync::{self, gc_tombstones},
    AppState,
};
use todori_storage::{
    open_encrypted, ListRepository, NewSyncOutboxEntry, SqliteListRepository,
    SqliteSyncStateRepository, SqliteTaskRepository, SyncOutboxState, SyncStateRepository,
    TaskRepository,
};
use todori_sync::{
    decrypt_plaintext, encrypt_plaintext,
    protocol::{PushOp, PushRequest, PushStatus, SyncCollection, SyncRecordState},
    run_sync_now, run_sync_now_with_key_refresh, ActiveSyncContext, Hlc, LocalMutationSyncStore,
    LocalSyncKeys, LocalSyncStore, SyncKeyRefresher, SyncPlaintext, SYNC_CURSOR_NAME,
};
use tower::ServiceExt;
use uuid::Uuid;

struct Fixture {
    app: Router,
    pool: PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    token: String,
    _postgres: ContainerAsync<postgres::Postgres>,
}

impl Fixture {
    async fn setup() -> Self {
        let postgres = postgres::Postgres::default().start().await.unwrap();
        let host = postgres.get_host().await.unwrap();
        let port = postgres.get_host_port_ipv4(5432).await.unwrap();
        let database_url = format!("postgres://postgres:postgres@{host}:{port}/postgres");
        let pool = db::connect(&database_url).await.unwrap();
        db::run_migrations(&pool).await.unwrap();

        let user_id = Uuid::now_v7();
        let tenant_id = Uuid::now_v7();
        let device_id = Uuid::now_v7();
        let token = "protocol-v2-test-token".to_string();
        query("INSERT INTO users (id, email, opaque_record) VALUES ($1, $2, $3)")
            .bind(user_id)
            .bind(format!("{user_id}@example.test"))
            .bind(vec![1_u8])
            .execute(&pool)
            .await
            .unwrap();
        query("INSERT INTO tenants (id, kind, owner_user_id) VALUES ($1, 'personal', $2)")
            .bind(tenant_id)
            .bind(user_id)
            .execute(&pool)
            .await
            .unwrap();
        query("INSERT INTO tenant_members (tenant_id, user_id, role) VALUES ($1, $2, 'owner')")
            .bind(tenant_id)
            .bind(user_id)
            .execute(&pool)
            .await
            .unwrap();
        query("INSERT INTO tenant_seq (tenant_id, last_seq) VALUES ($1, 0)")
            .bind(tenant_id)
            .execute(&pool)
            .await
            .unwrap();
        query("INSERT INTO devices (id, user_id, device_name) VALUES ($1, $2, 'test')")
            .bind(device_id)
            .bind(user_id)
            .execute(&pool)
            .await
            .unwrap();
        query(
            "INSERT INTO sessions (id, user_id, device_id, token_hash, expires_at)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(Uuid::now_v7())
        .bind(user_id)
        .bind(device_id)
        .bind(Sha256::digest(token.as_bytes()).to_vec())
        .bind(Utc::now() + Duration::days(1))
        .execute(&pool)
        .await
        .unwrap();

        let app = build_router(AppState { pool: pool.clone() });
        Self {
            app,
            pool,
            tenant_id,
            auth: AuthContext { user_id, device_id },
            token,
            _postgres: postgres,
        }
    }

    async fn push(&self, op: PushOp) -> todori_sync::protocol::PushResult {
        sync::push(
            &self.pool,
            self.tenant_id,
            self.auth.clone(),
            PushRequest { ops: vec![op] },
        )
        .await
        .unwrap()
        .results
        .pop()
        .unwrap()
    }

    async fn serve(&self) -> String {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let app = self.app.clone();
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        format!("http://{address}")
    }
}

struct TestKeyRefresher {
    calls: usize,
    keys: LocalSyncKeys,
    fail: bool,
}

impl SyncKeyRefresher for TestKeyRefresher {
    fn refresh<'a>(
        &'a mut self,
    ) -> Pin<Box<dyn Future<Output = Result<LocalSyncKeys, String>> + Send + 'a>> {
        self.calls += 1;
        let result = if self.fail {
            Err("refresh failed".to_string())
        } else {
            Ok(self.keys.clone())
        };
        Box::pin(async move { result })
    }
}

#[tokio::test]
async fn production_pull_refreshes_once_then_atomically_applies_and_quarantines() {
    const DB_KEY: [u8; 32] = [0xc3; 32];
    let fixture = Fixture::setup().await;
    let server_url = fixture.serve().await;
    let temp = TempDir::new().unwrap();
    let db_path = temp.path().join("quarantine.sqlite3");
    let now = Utc::now().timestamp_millis() - 20_000;
    let good = todori_domain::new_list(
        "Recovered".to_string(),
        "3fffffffffffffffffffffffffffffff".to_string(),
        now,
    )
    .unwrap();
    let missing = todori_domain::new_list(
        "Waiting".to_string(),
        "7fffffffffffffffffffffffffffffff".to_string(),
        now + 1,
    )
    .unwrap();
    let corrupt = todori_domain::new_list(
        "Corrupt".to_string(),
        "bfffffffffffffffffffffffffffffff".to_string(),
        now + 2,
    )
    .unwrap();
    let good_dek = [0x31; 32];
    let missing_dek = [0x32; 32];
    let corrupt_dek = [0x33; 32];
    for (index, (list, dek)) in [
        (&good, good_dek),
        (&missing, missing_dek),
        (&corrupt, corrupt_dek),
    ]
    .into_iter()
    .enumerate()
    {
        let mutation = Hlc {
            wall_ms: now + 100 + index as i64,
            counter: 0,
            device_id: "remote".to_string(),
        };
        let revision = Hlc {
            wall_ms: now + 200 + index as i64,
            counter: 0,
            device_id: "remote".to_string(),
        };
        let plaintext = SyncPlaintext::from_list(list, mutation.clone()).unwrap();
        let blob = if list.id == corrupt.id {
            let mut blob =
                encrypt_plaintext(&dek, "lists", &list.id.to_string(), &plaintext).unwrap();
            let last = blob.len() - 1;
            blob[last] ^= 0x40;
            blob
        } else {
            encrypt_plaintext(&dek, "lists", &list.id.to_string(), &plaintext).unwrap()
        };
        fixture
            .push(PushOp {
                op_id: Uuid::now_v7(),
                record_id: list.id,
                collection: SyncCollection::Lists,
                base_revision_hlc: None,
                revision_hlc: revision.encode().unwrap(),
                state: SyncRecordState::Live {
                    mutation_hlc: mutation.encode().unwrap(),
                    blob: STANDARD.encode(blob),
                },
            })
            .await;
    }

    let mut store = BridgeSyncStore::new(db_path.clone(), DB_KEY);
    let mut key_refresher = TestKeyRefresher {
        calls: 0,
        keys: LocalSyncKeys {
            list_deks: vec![(good.id, good_dek), (corrupt.id, corrupt_dek)],
        },
        fail: false,
    };
    let context = ActiveSyncContext {
        server_url,
        tenant_id: fixture.tenant_id,
        device_id: "quarantine-client".to_string(),
        session_token: fixture.token.clone(),
        keys: LocalSyncKeys::default(),
    };
    let mut clock = now + 1_000;
    let mut ticking_now = || {
        clock += 1;
        Ok(clock)
    };
    let summary =
        run_sync_now_with_key_refresh(context, &mut store, &mut ticking_now, &mut key_refresher)
            .await
            .unwrap();
    assert_eq!(key_refresher.calls, 1);
    assert_eq!(summary.applied_count, 1);
    assert_eq!(summary.missing_key_quarantined_count, 1);
    assert_eq!(summary.corruption_quarantined_count, 1);
    let repository = SqliteSyncStateRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
    assert_eq!(
        repository
            .get_cursor(SYNC_CURSOR_NAME)
            .unwrap()
            .unwrap()
            .seq,
        3
    );
    let quarantined = repository.list_quarantine(10).unwrap();
    assert_eq!(quarantined.len(), 2);
    assert!(quarantined
        .iter()
        .any(|row| row.record_id == missing.id && row.reason == "missing_dek"));
    assert!(quarantined
        .iter()
        .any(|row| row.record_id == corrupt.id && row.reason == "authentication_failed"));
    assert_eq!(
        SqliteListRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .get(good.id)
            .unwrap()
            .name,
        "Recovered"
    );
}

#[tokio::test]
async fn unsupported_preflight_durably_blocks_outbox_before_push() {
    const DB_KEY: [u8; 32] = [0xd4; 32];
    let preflight_count = Arc::new(AtomicUsize::new(0));
    let push_count = Arc::new(AtomicUsize::new(0));
    let preflight_counter = preflight_count.clone();
    let push_counter = push_count.clone();
    let app = Router::new()
        .route(
            "/v2/tenants/{tenant_id}/preflight",
            axum::routing::get(move || {
                let counter = preflight_counter.clone();
                async move {
                    counter.fetch_add(1, Ordering::SeqCst);
                    axum::Json(todori_sync::protocol::SyncCapabilities {
                        protocol_version: todori_sync::protocol::SYNC_PROTOCOL_VERSION + 1,
                        envelope_version: todori_sync::ENVELOPE_VERSION,
                    })
                }
            }),
        )
        .route(
            "/v2/tenants/{tenant_id}/push",
            axum::routing::post(move || {
                let counter = push_counter.clone();
                async move {
                    counter.fetch_add(1, Ordering::SeqCst);
                    axum::Json(todori_sync::protocol::PushResponse { results: vec![] })
                }
            }),
        );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });

    let temp = TempDir::new().unwrap();
    let db_path = temp.path().join("upgrade.sqlite3");
    let record_id = Uuid::now_v7();
    let op_id = Uuid::now_v7();
    let revision = hlc(-100, 0, "local-revision");
    let mutation = hlc(-200, 0, "local-mutation");
    let mut repository = SqliteSyncStateRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
    repository
        .put_outbox_head(NewSyncOutboxEntry {
            op_id,
            record_id,
            collection: "tasks".to_string(),
            base_revision_hlc: None,
            revision_hlc: revision,
            state: SyncOutboxState::Live {
                mutation_hlc: mutation,
                blob: vec![todori_sync::ENVELOPE_VERSION, 1],
            },
            created_at: Utc::now().timestamp_millis(),
        })
        .unwrap();
    drop(repository);
    let context = ActiveSyncContext {
        server_url: format!("http://{address}"),
        tenant_id: Uuid::now_v7(),
        device_id: "upgrade-client".to_string(),
        session_token: "token".to_string(),
        keys: LocalSyncKeys::default(),
    };
    let mut store = BridgeSyncStore::new(db_path.clone(), DB_KEY);
    let mut now = || Ok(Utc::now().timestamp_millis());
    assert_eq!(
        run_sync_now(context.clone(), &mut store, &mut now).await,
        Err("upgrade required".to_string())
    );
    assert_eq!(preflight_count.load(Ordering::SeqCst), 1);
    assert_eq!(push_count.load(Ordering::SeqCst), 0);
    assert!(store
        .has_outbox_head(SyncCollection::Tasks, record_id)
        .unwrap());
    assert!(store.get_cursor_seq(SYNC_CURSOR_NAME).unwrap().is_none());
    assert!(store
        .get_setting(todori_sync::SYNC_UPGRADE_REQUIRED_SETTING_KEY)
        .unwrap()
        .is_some());

    assert_eq!(
        run_sync_now(context, &mut store, &mut now).await,
        Err("upgrade required".to_string())
    );
    assert_eq!(preflight_count.load(Ordering::SeqCst), 1);
    assert_eq!(push_count.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn production_two_client_distinct_field_crud_survives_cas_conflict() {
    const DB_KEY_A: [u8; 32] = [0xa1; 32];
    const DB_KEY_B: [u8; 32] = [0xb2; 32];
    let fixture = Fixture::setup().await;
    let server_url = fixture.serve().await;
    let temp = TempDir::new().unwrap();
    let path_a = temp.path().join("client-a.sqlite3");
    let path_b = temp.path().join("client-b.sqlite3");
    let now = Utc::now().timestamp_millis() - 10_000;
    let list = todori_domain::new_list(
        "Shared".to_string(),
        "7fffffffffffffffffffffffffffffff".to_string(),
        now,
    )
    .unwrap();
    for (path, key) in [(&path_a, &DB_KEY_A), (&path_b, &DB_KEY_B)] {
        SqliteListRepository::new(open_encrypted(path, key).unwrap())
            .insert(list.clone())
            .unwrap();
    }
    let list_dek = [0x5a; 32];
    let sync_a = LocalMutationContext {
        device_id: "production-client-a".to_string(),
        keys: LocalSyncKeys {
            list_deks: vec![(list.id, list_dek)],
        },
    };
    let sync_b = LocalMutationContext {
        device_id: "production-client-b".to_string(),
        keys: sync_a.keys.clone(),
    };
    let client_a = Client::new(path_a.clone(), DB_KEY_A);
    let client_b = Client::new(path_b.clone(), DB_KEY_B);
    let task = client_a
        .create_task(
            todori_client::CreateTaskInput {
                list_id: list.id,
                title: "Base title".to_string(),
                parent_task_id: None,
                due_at: None,
                note: Some("Base note".to_string()),
                now_ms: now + 1,
            },
            &sync_a,
        )
        .unwrap();
    let context = |device_id: &str, keys: LocalSyncKeys| ActiveSyncContext {
        server_url: server_url.clone(),
        tenant_id: fixture.tenant_id,
        device_id: device_id.to_string(),
        session_token: fixture.token.clone(),
        keys,
    };
    let mut clock = now + 100;
    let mut ticking_now = || {
        clock += 1;
        Ok(clock)
    };
    let mut store_a = BridgeSyncStore::new(path_a.clone(), DB_KEY_A);
    run_sync_now(
        context("production-client-a", sync_a.keys.clone()),
        &mut store_a,
        &mut ticking_now,
    )
    .await
    .unwrap();
    let mut store_b = BridgeSyncStore::new(path_b.clone(), DB_KEY_B);
    run_sync_now(
        context("production-client-b", sync_b.keys.clone()),
        &mut store_b,
        &mut ticking_now,
    )
    .await
    .unwrap();
    assert_eq!(
        SqliteTaskRepository::new(open_encrypted(&path_b, &DB_KEY_B).unwrap())
            .get(task.id)
            .unwrap()
            .title,
        "Base title"
    );

    client_a
        .update_task(
            UpdateTaskInput {
                task_id: task.id,
                title: "Title from A".to_string(),
                note: "Base note".to_string(),
                priority: 0,
                due_at: None,
                now_ms: now + 200,
            },
            &sync_a,
        )
        .unwrap();
    client_b
        .update_task(
            UpdateTaskInput {
                task_id: task.id,
                title: "Base title".to_string(),
                note: "Note from B".to_string(),
                priority: 0,
                due_at: None,
                now_ms: now + 201,
            },
            &sync_b,
        )
        .unwrap();

    let first = run_sync_now(
        context("production-client-a", sync_a.keys.clone()),
        &mut store_a,
        &mut ticking_now,
    )
    .await
    .unwrap();
    assert_eq!(first.push_acked_count, 1);
    drop(store_a);
    let second = run_sync_now(
        context("production-client-b", sync_b.keys.clone()),
        &mut store_b,
        &mut ticking_now,
    )
    .await
    .unwrap();
    assert_eq!(second.push_conflict_count, 1);
    assert!(second.push_acked_count >= 1);

    let row = query(
        "SELECT encrypted_blob FROM sync_records
         WHERE tenant_id = $1 AND collection = 'tasks' AND record_id = $2",
    )
    .bind(fixture.tenant_id)
    .bind(task.id)
    .fetch_one(&fixture.pool)
    .await
    .unwrap();
    let blob: Vec<u8> = row.get("encrypted_blob");
    let plaintext = decrypt_plaintext(&list_dek, "tasks", &task.id.to_string(), &blob).unwrap();
    let SyncPlaintext::Task(plaintext) = plaintext else {
        panic!("task plaintext");
    };
    assert_eq!(plaintext.title.value, "Title from A");
    assert_eq!(plaintext.note.value, "Note from B");
}

#[tokio::test]
async fn equal_rank_clients_converge_then_common_reorder_rebalances_and_reconverges() {
    const DB_KEY_A: [u8; 32] = [0xc1; 32];
    const DB_KEY_B: [u8; 32] = [0xd2; 32];
    let fixture = Fixture::setup().await;
    let server_url = fixture.serve().await;
    let temp = TempDir::new().unwrap();
    let path_a = temp.path().join("rank-client-a.sqlite3");
    let path_b = temp.path().join("rank-client-b.sqlite3");
    let now = Utc::now().timestamp_millis() - 10_000;
    let list = todori_domain::new_list(
        "Shared ranks".to_string(),
        "7fffffffffffffffffffffffffffffff".to_string(),
        now,
    )
    .unwrap();
    for (path, key) in [(&path_a, &DB_KEY_A), (&path_b, &DB_KEY_B)] {
        SqliteListRepository::new(open_encrypted(path, key).unwrap())
            .insert(list.clone())
            .unwrap();
    }
    let list_dek = [0x6b; 32];
    let sync_a = LocalMutationContext {
        device_id: "rank-client-a".to_string(),
        keys: LocalSyncKeys {
            list_deks: vec![(list.id, list_dek)],
        },
    };
    let sync_b = LocalMutationContext {
        device_id: "rank-client-b".to_string(),
        keys: sync_a.keys.clone(),
    };
    let client_a = Client::new(path_a.clone(), DB_KEY_A);
    let client_b = Client::new(path_b.clone(), DB_KEY_B);
    let target = client_a
        .create_task(
            todori_client::CreateTaskInput {
                list_id: list.id,
                title: "reorder target".to_string(),
                parent_task_id: None,
                due_at: None,
                note: None,
                now_ms: now + 1,
            },
            &sync_a,
        )
        .unwrap();
    let context = |device_id: &str, keys: LocalSyncKeys| ActiveSyncContext {
        server_url: server_url.clone(),
        tenant_id: fixture.tenant_id,
        device_id: device_id.to_string(),
        session_token: fixture.token.clone(),
        keys,
    };
    let mut clock = now + 100;
    let mut ticking_now = || {
        clock += 1;
        Ok(clock)
    };
    let mut store_a = BridgeSyncStore::new(path_a.clone(), DB_KEY_A);
    let mut store_b = BridgeSyncStore::new(path_b.clone(), DB_KEY_B);
    run_sync_now(
        context("rank-client-a", sync_a.keys.clone()),
        &mut store_a,
        &mut ticking_now,
    )
    .await
    .unwrap();
    run_sync_now(
        context("rank-client-b", sync_b.keys.clone()),
        &mut store_b,
        &mut ticking_now,
    )
    .await
    .unwrap();

    let concurrent_a = client_a
        .create_task(
            todori_client::CreateTaskInput {
                list_id: list.id,
                title: "same gap A".to_string(),
                parent_task_id: None,
                due_at: None,
                note: None,
                now_ms: now + 200,
            },
            &sync_a,
        )
        .unwrap();
    let concurrent_b = client_b
        .create_task(
            todori_client::CreateTaskInput {
                list_id: list.id,
                title: "same gap B".to_string(),
                parent_task_id: None,
                due_at: None,
                note: None,
                now_ms: now + 201,
            },
            &sync_b,
        )
        .unwrap();
    assert_eq!(concurrent_a.sort_order, concurrent_b.sort_order);
    run_sync_now(
        context("rank-client-a", sync_a.keys.clone()),
        &mut store_a,
        &mut ticking_now,
    )
    .await
    .unwrap();
    run_sync_now(
        context("rank-client-b", sync_b.keys.clone()),
        &mut store_b,
        &mut ticking_now,
    )
    .await
    .unwrap();
    run_sync_now(
        context("rank-client-a", sync_a.keys.clone()),
        &mut store_a,
        &mut ticking_now,
    )
    .await
    .unwrap();
    let order = |path: &std::path::Path, key: &[u8; 32]| {
        SqliteTaskRepository::new(open_encrypted(path, key).unwrap())
            .list_active_by_list(list.id)
            .unwrap()
            .into_iter()
            .map(|task| task.id)
            .collect::<Vec<_>>()
    };
    assert_eq!(order(&path_a, &DB_KEY_A), order(&path_b, &DB_KEY_B));
    let (previous, next) = if concurrent_a.id < concurrent_b.id {
        (concurrent_a.id, concurrent_b.id)
    } else {
        (concurrent_b.id, concurrent_a.id)
    };

    client_a
        .reorder_task(
            todori_client::ReorderTaskInput {
                task_id: target.id,
                previous_task_id: Some(previous),
                next_task_id: Some(next),
                now_ms: now + 300,
            },
            &sync_a,
        )
        .unwrap();
    run_sync_now(
        context("rank-client-a", sync_a.keys.clone()),
        &mut store_a,
        &mut ticking_now,
    )
    .await
    .unwrap();
    run_sync_now(
        context("rank-client-b", sync_b.keys.clone()),
        &mut store_b,
        &mut ticking_now,
    )
    .await
    .unwrap();
    run_sync_now(
        context("rank-client-a", sync_a.keys.clone()),
        &mut store_a,
        &mut ticking_now,
    )
    .await
    .unwrap();

    let order_a = order(&path_a, &DB_KEY_A);
    let order_b = order(&path_b, &DB_KEY_B);
    assert_eq!(order_a, order_b);
    assert_eq!(order_a, vec![previous, target.id, next]);
    let ranks = SqliteTaskRepository::new(open_encrypted(&path_a, &DB_KEY_A).unwrap())
        .list_active_by_list(list.id)
        .unwrap()
        .into_iter()
        .map(|task| task.sort_order)
        .collect::<Vec<_>>();
    assert!(ranks.windows(2).all(|pair| pair[0] < pair[1]));
}

fn hlc(delta: i64, counter: u32, device: &str) -> String {
    Hlc {
        wall_ms: Utc::now().timestamp_millis() + delta,
        counter,
        device_id: device.to_string(),
    }
    .encode()
    .unwrap()
}

fn live_op(
    record_id: Uuid,
    base_revision_hlc: Option<String>,
    revision_hlc: String,
    mutation_hlc: String,
    blob: &[u8],
) -> PushOp {
    PushOp {
        op_id: Uuid::now_v7(),
        record_id,
        collection: SyncCollection::Tasks,
        base_revision_hlc,
        revision_hlc,
        state: SyncRecordState::Live {
            mutation_hlc,
            blob: STANDARD.encode(blob),
        },
    }
}

fn tombstone_op(
    record_id: Uuid,
    base_revision_hlc: Option<String>,
    revision_hlc: String,
    delete_hlc: String,
) -> PushOp {
    PushOp {
        op_id: Uuid::now_v7(),
        record_id,
        collection: SyncCollection::Tasks,
        base_revision_hlc,
        revision_hlc,
        state: SyncRecordState::Tombstone { delete_hlc },
    }
}

#[tokio::test]
async fn cas_retry_semantic_fences_and_pull_preserve_the_current_head() {
    let fixture = Fixture::setup().await;
    let record_id = Uuid::now_v7();
    let mutation_1 = hlc(-4_000, 0, "semantic-a");
    let revision_1 = hlc(-3_900, 0, "revision-a");
    let create = live_op(
        record_id,
        None,
        revision_1.clone(),
        mutation_1.clone(),
        b"cipher-a",
    );
    let accepted = fixture.push(create.clone()).await;
    assert_eq!(accepted.status, PushStatus::Accepted);
    assert_eq!(accepted.seq, Some(1));

    let retry = fixture.push(create).await;
    assert_eq!(retry.status, PushStatus::NoOp);
    assert_eq!(retry.seq, Some(1));

    let same_revision_different_blob = fixture
        .push(live_op(
            record_id,
            None,
            revision_1.clone(),
            mutation_1.clone(),
            b"same-revision-corruption",
        ))
        .await;
    assert_eq!(same_revision_different_blob.status, PushStatus::Conflict);
    assert_eq!(same_revision_different_blob.seq, Some(1));

    let stale = live_op(
        record_id,
        None,
        hlc(-3_000, 0, "revision-stale"),
        hlc(-3_100, 0, "semantic-stale"),
        b"must-not-overwrite",
    );
    let stale_result = fixture.push(stale).await;
    assert_eq!(stale_result.status, PushStatus::Conflict);
    assert_eq!(
        stale_result.current.as_ref().unwrap().revision_hlc,
        revision_1
    );

    let delete_old = tombstone_op(
        record_id,
        Some(revision_1.clone()),
        hlc(-2_900, 0, "revision-delete-old"),
        hlc(-5_000, 0, "delete-old"),
    );
    let superseded = fixture.push(delete_old).await;
    assert_eq!(superseded.status, PushStatus::Superseded);
    assert_eq!(
        superseded.current.as_ref().unwrap().revision_hlc,
        revision_1
    );

    let delete_hlc = hlc(-2_500, 0, "delete-new");
    let delete_revision = hlc(-2_400, 0, "revision-delete-new");
    let deleted = fixture
        .push(tombstone_op(
            record_id,
            Some(revision_1),
            delete_revision.clone(),
            delete_hlc.clone(),
        ))
        .await;
    assert_eq!(deleted.status, PushStatus::Accepted);
    assert_eq!(deleted.seq, Some(2));

    let live_old = fixture
        .push(live_op(
            record_id,
            Some(delete_revision.clone()),
            hlc(-2_000, 0, "revision-live-old"),
            mutation_1,
            b"must-stay-deleted",
        ))
        .await;
    assert_eq!(live_old.status, PushStatus::Superseded);
    assert!(matches!(
        live_old.current.unwrap().state,
        SyncRecordState::Tombstone { .. }
    ));

    let live_revision = hlc(-1_500, 0, "revision-live-new");
    let resurrected = fixture
        .push(live_op(
            record_id,
            Some(delete_revision),
            live_revision.clone(),
            hlc(-1_600, 0, "semantic-live-new"),
            b"cipher-resurrected",
        ))
        .await;
    assert_eq!(resurrected.status, PushStatus::Accepted);
    assert_eq!(resurrected.seq, Some(3));

    let page = sync::pull(
        &fixture.pool,
        fixture.tenant_id,
        fixture.auth.clone(),
        0,
        Some(100),
    )
    .await
    .unwrap();
    assert_eq!(page.records.len(), 1);
    assert_eq!(page.records[0].revision_hlc, live_revision);
    assert!(matches!(
        &page.records[0].state,
        SyncRecordState::Live { blob, .. } if blob == &STANDARD.encode(b"cipher-resurrected")
    ));
    assert_eq!(page.next_since, 3);

    let history_count: i64 = query(
        "SELECT count(*) AS count FROM sync_records_history
         WHERE tenant_id = $1 AND record_id = $2",
    )
    .bind(fixture.tenant_id)
    .bind(record_id)
    .fetch_one(&fixture.pool)
    .await
    .unwrap()
    .try_get("count")
    .unwrap();
    assert_eq!(history_count, 2);
}

#[tokio::test]
async fn v2_route_rejects_v1_unknown_collection_invalid_blob_and_collection_changes() {
    let fixture = Fixture::setup().await;
    let record_id = Uuid::now_v7();
    let revision = hlc(-1_000, 0, "route-revision");
    let mutation = hlc(-1_100, 0, "route-mutation");
    let valid_body = json!({
        "ops": [{
            "op_id": Uuid::now_v7(),
            "record_id": record_id,
            "collection": "tasks",
            "base_revision_hlc": null,
            "revision_hlc": revision,
            "state": {
                "kind": "live",
                "mutation_hlc": mutation,
                "blob": STANDARD.encode(b"cipher")
            }
        }]
    });
    assert_eq!(
        request_status(
            &fixture.app,
            Method::POST,
            format!("/v1/tenants/{}/push", fixture.tenant_id),
            Some(&fixture.token),
            Some(valid_body.clone()),
        )
        .await,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        request_status(
            &fixture.app,
            Method::POST,
            format!("/v2/tenants/{}/push", fixture.tenant_id),
            None,
            Some(valid_body.clone()),
        )
        .await,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        request_status(
            &fixture.app,
            Method::POST,
            format!("/v2/tenants/{}/push", fixture.tenant_id),
            Some(&fixture.token),
            Some(valid_body),
        )
        .await,
        StatusCode::OK
    );

    let unknown_collection = json!({
        "ops": [{
            "op_id": Uuid::now_v7(),
            "record_id": Uuid::now_v7(),
            "collection": "reminders",
            "base_revision_hlc": null,
            "revision_hlc": hlc(-900, 0, "unknown"),
            "state": {
                "kind": "tombstone",
                "delete_hlc": hlc(-950, 0, "unknown-delete")
            }
        }]
    });
    assert_eq!(
        request_status(
            &fixture.app,
            Method::POST,
            format!("/v2/tenants/{}/push", fixture.tenant_id),
            Some(&fixture.token),
            Some(unknown_collection),
        )
        .await,
        StatusCode::UNPROCESSABLE_ENTITY
    );

    let invalid_blob = json!({
        "ops": [{
            "op_id": Uuid::now_v7(),
            "record_id": Uuid::now_v7(),
            "collection": "tasks",
            "base_revision_hlc": null,
            "revision_hlc": hlc(-800, 0, "invalid-blob"),
            "state": {
                "kind": "live",
                "mutation_hlc": hlc(-850, 0, "invalid-blob-mutation"),
                "blob": "***"
            }
        }]
    });
    assert_eq!(
        request_status(
            &fixture.app,
            Method::POST,
            format!("/v2/tenants/{}/push", fixture.tenant_id),
            Some(&fixture.token),
            Some(invalid_blob),
        )
        .await,
        StatusCode::BAD_REQUEST
    );

    let invalid_clock = json!({
        "ops": [{
            "op_id": Uuid::now_v7(),
            "record_id": Uuid::now_v7(),
            "collection": "tasks",
            "base_revision_hlc": null,
            "revision_hlc": "not-an-hlc",
            "state": {
                "kind": "tombstone",
                "delete_hlc": hlc(-700, 0, "invalid-clock-delete")
            }
        }]
    });
    assert_eq!(
        request_status(
            &fixture.app,
            Method::POST,
            format!("/v2/tenants/{}/push", fixture.tenant_id),
            Some(&fixture.token),
            Some(invalid_clock),
        )
        .await,
        StatusCode::BAD_REQUEST
    );

    let changed_collection = PushOp {
        op_id: Uuid::now_v7(),
        record_id,
        collection: SyncCollection::Lists,
        base_revision_hlc: Some(revision),
        revision_hlc: hlc(-700, 0, "changed-collection"),
        state: SyncRecordState::Tombstone {
            delete_hlc: hlc(-750, 0, "changed-delete"),
        },
    };
    assert!(sync::push(
        &fixture.pool,
        fixture.tenant_id,
        fixture.auth.clone(),
        PushRequest {
            ops: vec![changed_collection]
        },
    )
    .await
    .is_err());
}

#[tokio::test]
async fn v2_schema_enforces_tagged_state_and_gc_only_removes_tombstones() {
    let fixture = Fixture::setup().await;
    let invalid = query(
        "INSERT INTO sync_records
         (tenant_id, record_id, collection, seq, revision_hlc, mutation_hlc,
          delete_hlc, encrypted_blob)
         VALUES ($1, $2, 'tasks', 1, 'revision', NULL, 'delete', $3)",
    )
    .bind(fixture.tenant_id)
    .bind(Uuid::now_v7())
    .bind(vec![1_u8])
    .execute(&fixture.pool)
    .await;
    assert!(invalid.is_err());

    let live_id = Uuid::now_v7();
    let tombstone_id = Uuid::now_v7();
    fixture
        .push(live_op(
            live_id,
            None,
            hlc(-1_000, 0, "gc-live-revision"),
            hlc(-1_100, 0, "gc-live-mutation"),
            b"live",
        ))
        .await;
    fixture
        .push(tombstone_op(
            tombstone_id,
            None,
            hlc(-900, 0, "gc-delete-revision"),
            hlc(-950, 0, "gc-delete"),
        ))
        .await;
    db::run_migrations(&fixture.pool).await.unwrap();
    let preserved_after_rerun: i64 =
        query("SELECT count(*) AS count FROM sync_records WHERE tenant_id = $1")
            .bind(fixture.tenant_id)
            .fetch_one(&fixture.pool)
            .await
            .unwrap()
            .try_get("count")
            .unwrap();
    assert_eq!(preserved_after_rerun, 2);
    query("UPDATE sync_records SET updated_at = $1 WHERE tenant_id = $2")
        .bind(Utc::now() - Duration::days(181))
        .bind(fixture.tenant_id)
        .execute(&fixture.pool)
        .await
        .unwrap();

    assert_eq!(gc_tombstones(&fixture.pool, Utc::now()).await.unwrap(), 1);
    let remaining: Vec<Uuid> =
        query("SELECT record_id FROM sync_records WHERE tenant_id = $1 ORDER BY record_id")
            .bind(fixture.tenant_id)
            .fetch_all(&fixture.pool)
            .await
            .unwrap()
            .into_iter()
            .map(|row| row.try_get("record_id").unwrap())
            .collect();
    assert_eq!(remaining, vec![live_id]);
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
    let response = app
        .clone()
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let _ = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    status
}
