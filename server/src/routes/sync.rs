use axum::{
    extract::{Path, Query, State},
    http::HeaderMap,
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::{
    auth,
    sync::{self, UpsertListKeyResponse},
    AppError, SharedState,
};
use todori_sync::{
    account::ListDekBundleDto,
    protocol::{
        BaseScanResponse, PullResponse, PushRequest, PushResponse, ResyncStartResponse,
        StableRecordCursor, SyncCollection,
    },
};

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/{tenant_id}/preflight", get(preflight))
        .route("/{tenant_id}/push", post(push))
        .route("/{tenant_id}/pull", get(pull))
        .route("/{tenant_id}/resync/start", post(begin_full_resync))
        .route("/{tenant_id}/resync/base", get(scan_base))
        .route(
            "/{tenant_id}/list-keys",
            get(list_key_bundles).post(upsert_list_key_bundle),
        )
}

async fn preflight(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    Query(query): Query<PreflightQuery>,
    headers: HeaderMap,
) -> Result<Json<todori_sync::protocol::SyncCapabilities>, AppError> {
    let token = bearer_token(&headers)?;
    let _auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    sync::preflight(&state.pool, tenant_id, query.since)
        .await
        .map(Json)
}

#[derive(Debug, Deserialize)]
struct PreflightQuery {
    since: i64,
}

#[derive(Debug, Deserialize)]
struct PullQuery {
    since: i64,
    limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct BaseScanQuery {
    after_collection: Option<SyncCollection>,
    after_record_id: Option<Uuid>,
    limit: Option<i64>,
}

async fn begin_full_resync(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    headers: HeaderMap,
) -> Result<Json<ResyncStartResponse>, AppError> {
    let token = bearer_token(&headers)?;
    let _auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    sync::begin_full_resync(&state.pool, tenant_id)
        .await
        .map(Json)
}

async fn scan_base(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    Query(query): Query<BaseScanQuery>,
    headers: HeaderMap,
) -> Result<Json<BaseScanResponse>, AppError> {
    let token = bearer_token(&headers)?;
    let _auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    let cursor = match (query.after_collection, query.after_record_id) {
        (None, None) => None,
        (Some(collection), Some(record_id)) => Some(StableRecordCursor {
            collection,
            record_id,
        }),
        _ => return Err(AppError::bad_request("incomplete base cursor")),
    };
    sync::scan_base(&state.pool, tenant_id, cursor, query.limit)
        .await
        .map(Json)
}

async fn push(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    headers: HeaderMap,
    Json(request): Json<PushRequest>,
) -> Result<Json<PushResponse>, AppError> {
    let token = bearer_token(&headers)?;
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    sync::push(&state.pool, tenant_id, auth_context, request)
        .await
        .map(Json)
}

async fn pull(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    Query(query): Query<PullQuery>,
    headers: HeaderMap,
) -> Result<Json<PullResponse>, AppError> {
    let token = bearer_token(&headers)?;
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    sync::pull(
        &state.pool,
        tenant_id,
        auth_context,
        query.since,
        query.limit,
    )
    .await
    .map(Json)
}

async fn upsert_list_key_bundle(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    headers: HeaderMap,
    Json(request): Json<ListDekBundleDto>,
) -> Result<Json<UpsertListKeyResponse>, AppError> {
    let token = bearer_token(&headers)?;
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    sync::upsert_list_key_bundle(&state.pool, tenant_id, auth_context, request)
        .await
        .map(Json)
}

async fn list_key_bundles(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    headers: HeaderMap,
) -> Result<Json<Vec<ListDekBundleDto>>, AppError> {
    let token = bearer_token(&headers)?;
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    sync::list_key_bundles(&state.pool, tenant_id, auth_context)
        .await
        .map(Json)
}

fn bearer_token(headers: &HeaderMap) -> Result<&str, AppError> {
    let value = headers
        .get(axum::http::header::AUTHORIZATION)
        .ok_or_else(AppError::unauthorized)?
        .to_str()
        .map_err(|_| AppError::unauthorized())?;
    value
        .strip_prefix("Bearer ")
        .filter(|token| !token.is_empty())
        .ok_or_else(AppError::unauthorized)
}
