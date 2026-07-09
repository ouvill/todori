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
    protocol::{PullResponse, PushRequest, PushResponse},
};

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/{tenant_id}/push", post(push))
        .route("/{tenant_id}/pull", get(pull))
}

pub fn key_router() -> Router<SharedState> {
    Router::new().route(
        "/{tenant_id}/list-keys",
        get(list_key_bundles).post(upsert_list_key_bundle),
    )
}

#[derive(Debug, Deserialize)]
struct PullQuery {
    since: i64,
    limit: Option<i64>,
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
