use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{delete, get, post},
    Extension, Json, Router,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::{
    auth,
    sync::{self, RetireListKeyResponse, UpsertListKeyResponse},
    AppError, SharedState,
};
use todori_sync::{
    account::ListDekBundleDto,
    protocol::{
        BaseScanResponse, ContinuityAckRequest, ContinuityAckResponse, PullResponse, PushRequest,
        PushResponse, PushStatus, ResyncStartResponse, StableRecordCursor, SyncCollection,
        SYNC_PROTOCOL_VERSION, SYNC_PROTOCOL_VERSION_HEADER,
    },
};

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/{tenant_id}/preflight", get(preflight))
        .route("/{tenant_id}/push", post(push))
        .route("/{tenant_id}/pull", get(pull))
        .route("/{tenant_id}/resync/start", post(begin_full_resync))
        .route("/{tenant_id}/resync/base", get(scan_base))
        .route("/{tenant_id}/continuity/ack", post(ack_continuity))
        .route(
            "/{tenant_id}/list-keys",
            get(list_key_bundles).post(upsert_list_key_bundle),
        )
        .route(
            "/{tenant_id}/list-keys/{list_id}",
            delete(retire_list_key_bundle),
        )
}

async fn preflight(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    Query(query): Query<PreflightQuery>,
    headers: HeaderMap,
) -> Result<Response, AppError> {
    let token = bearer_token(&headers)?;
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    require_current_protocol(&headers)?;
    let capabilities = sync::preflight(&state.pool, tenant_id, auth_context, query.since).await?;
    let status = if capabilities.full_resync_required {
        StatusCode::GONE
    } else {
        StatusCode::OK
    };
    Ok((status, Json(capabilities)).into_response())
}

#[derive(Debug, Deserialize)]
struct PreflightQuery {
    since: i64,
}

#[derive(Debug, Deserialize)]
struct PullQuery {
    since: i64,
    limit: Option<i64>,
    generation: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct BaseScanQuery {
    generation: i64,
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
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    require_current_protocol(&headers)?;
    sync::begin_full_resync(&state.pool, tenant_id, auth_context)
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
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    require_current_protocol(&headers)?;
    let cursor = match (query.after_collection, query.after_record_id) {
        (None, None) => None,
        (Some(collection), Some(record_id)) => Some(StableRecordCursor {
            collection,
            record_id,
        }),
        _ => return Err(AppError::bad_request("incomplete base cursor")),
    };
    sync::scan_base(
        &state.pool,
        tenant_id,
        auth_context,
        query.generation,
        cursor,
        query.limit,
    )
    .await
    .map(Json)
}

async fn push(
    State(state): State<SharedState>,
    Extension(realtime): Extension<crate::realtime::RealtimeGateway>,
    Path(tenant_id): Path<Uuid>,
    headers: HeaderMap,
    Json(request): Json<PushRequest>,
) -> Result<Json<PushResponse>, AppError> {
    let token = bearer_token(&headers)?;
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    require_current_protocol(&headers)?;
    let device_id = auth_context.device_id;
    let response = sync::push(&state.pool, tenant_id, auth_context, request).await?;
    if should_publish(&response) {
        realtime.publish_change(tenant_id, device_id).await;
    }
    Ok(Json(response))
}

fn should_publish(response: &PushResponse) -> bool {
    response
        .results
        .iter()
        .any(|result| result.status == PushStatus::Accepted)
}

async fn pull(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    Query(query): Query<PullQuery>,
    headers: HeaderMap,
) -> Result<Json<PullResponse>, AppError> {
    let token = bearer_token(&headers)?;
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    require_current_protocol(&headers)?;
    sync::pull(
        &state.pool,
        tenant_id,
        auth_context,
        query.since,
        query.limit,
        query.generation,
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
    require_current_protocol(&headers)?;
    sync::upsert_list_key_bundle(&state.pool, tenant_id, auth_context, request)
        .await
        .map(Json)
}

async fn ack_continuity(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    headers: HeaderMap,
    Json(request): Json<ContinuityAckRequest>,
) -> Result<Json<ContinuityAckResponse>, AppError> {
    let token = bearer_token(&headers)?;
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    require_current_protocol(&headers)?;
    sync::ack_continuity(&state.pool, tenant_id, auth_context, request)
        .await
        .map(Json)
}

async fn retire_list_key_bundle(
    State(state): State<SharedState>,
    Path((tenant_id, list_id)): Path<(Uuid, Uuid)>,
    headers: HeaderMap,
) -> Result<Json<RetireListKeyResponse>, AppError> {
    let token = bearer_token(&headers)?;
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    require_current_protocol(&headers)?;
    sync::retire_list_key_bundle(&state.pool, tenant_id, auth_context, list_id)
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

pub(super) fn bearer_token(headers: &HeaderMap) -> Result<&str, AppError> {
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

fn require_current_protocol(headers: &HeaderMap) -> Result<(), AppError> {
    let version = headers
        .get(SYNC_PROTOCOL_VERSION_HEADER)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<u16>().ok());
    if version != Some(SYNC_PROTOCOL_VERSION) {
        return Err(AppError::conflict("sync protocol upgrade required"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use todori_sync::protocol::{PushResult, SyncCollection};

    #[test]
    fn publish_is_attempted_only_when_at_least_one_result_is_accepted() {
        for status in [
            PushStatus::NoOp,
            PushStatus::Conflict,
            PushStatus::Superseded,
        ] {
            assert!(!should_publish(&response_with(status)));
        }
        assert!(should_publish(&response_with(PushStatus::Accepted)));
        assert!(should_publish(&PushResponse {
            results: vec![result(PushStatus::NoOp), result(PushStatus::Accepted),],
        }));
    }

    fn response_with(status: PushStatus) -> PushResponse {
        PushResponse {
            results: vec![result(status)],
        }
    }

    fn result(status: PushStatus) -> PushResult {
        PushResult {
            op_id: Uuid::nil(),
            record_id: Uuid::nil(),
            collection: SyncCollection::Tasks,
            status,
            seq: None,
            current: None,
        }
    }
}
