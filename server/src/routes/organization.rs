use axum::{
    extract::{Path, State},
    http::HeaderMap,
    routing::{delete, get, post},
    Json, Router,
};
use todori_sync::organization::{
    OrganizationDeviceRevocationRequest, OrganizationDeviceRosterDto, OrganizationInviteRequest,
    OrganizationMemberResponse, OrganizationSafetyConfirmRequest, OrganizationSafetyResponse,
    RecipientPackageRequest, RecipientPackageResponse,
};
use uuid::Uuid;

use crate::{auth, organization, AppError, SharedState};

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/{tenant_id}/organization/invites", post(invite_member))
        .route(
            "/{tenant_id}/organization/safety/{member_user_id}",
            get(safety_number),
        )
        .route(
            "/{tenant_id}/organization/safety/confirm",
            post(confirm_safety_number),
        )
        .route(
            "/{tenant_id}/organization/devices/{member_user_id}",
            get(list_member_devices),
        )
        .route(
            "/{tenant_id}/organization/members/{member_user_id}",
            delete(remove_member),
        )
        .route(
            "/{tenant_id}/organization/device-revocations/{device_id}",
            post(revoke_device),
        )
        .route(
            "/{tenant_id}/organization/recipients/{scope_kind}/{scope_id}/{generation}",
            get(load_recipient_package).post(store_recipient_package),
        )
}

async fn remove_member(
    State(state): State<SharedState>,
    Path((tenant_id, member_user_id)): Path<(Uuid, Uuid)>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>, AppError> {
    let auth_context = authenticate(&state, &headers, tenant_id).await?;
    organization::remove_member(&state.pool, tenant_id, auth_context, member_user_id).await?;
    Ok(Json(serde_json::json!({})))
}

async fn revoke_device(
    State(state): State<SharedState>,
    Path((tenant_id, device_id)): Path<(Uuid, Uuid)>,
    headers: HeaderMap,
    Json(request): Json<OrganizationDeviceRevocationRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let auth_context = authenticate(&state, &headers, tenant_id).await?;
    organization::revoke_device(&state.pool, tenant_id, auth_context, device_id, request).await?;
    Ok(Json(serde_json::json!({})))
}

async fn invite_member(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    headers: HeaderMap,
    Json(request): Json<OrganizationInviteRequest>,
) -> Result<Json<OrganizationMemberResponse>, AppError> {
    let auth_context = authenticate(&state, &headers, tenant_id).await?;
    organization::invite_member(&state.pool, tenant_id, auth_context, request)
        .await
        .map(Json)
}

async fn safety_number(
    State(state): State<SharedState>,
    Path((tenant_id, member_user_id)): Path<(Uuid, Uuid)>,
    headers: HeaderMap,
) -> Result<Json<OrganizationSafetyResponse>, AppError> {
    let auth_context = authenticate(&state, &headers, tenant_id).await?;
    organization::safety_number(&state.pool, tenant_id, auth_context, member_user_id)
        .await
        .map(Json)
}

async fn confirm_safety_number(
    State(state): State<SharedState>,
    Path(tenant_id): Path<Uuid>,
    headers: HeaderMap,
    Json(request): Json<OrganizationSafetyConfirmRequest>,
) -> Result<Json<OrganizationSafetyResponse>, AppError> {
    let auth_context = authenticate(&state, &headers, tenant_id).await?;
    organization::confirm_safety_number(&state.pool, tenant_id, auth_context, request)
        .await
        .map(Json)
}

async fn list_member_devices(
    State(state): State<SharedState>,
    Path((tenant_id, member_user_id)): Path<(Uuid, Uuid)>,
    headers: HeaderMap,
) -> Result<Json<OrganizationDeviceRosterDto>, AppError> {
    let auth_context = authenticate(&state, &headers, tenant_id).await?;
    organization::list_member_devices(&state.pool, tenant_id, auth_context, member_user_id)
        .await
        .map(Json)
}

async fn store_recipient_package(
    State(state): State<SharedState>,
    Path((tenant_id, scope_kind, scope_id, generation)): Path<(Uuid, i16, Uuid, u64)>,
    headers: HeaderMap,
    Json(request): Json<RecipientPackageRequest>,
) -> Result<Json<RecipientPackageResponse>, AppError> {
    let auth_context = authenticate(&state, &headers, tenant_id).await?;
    organization::store_recipient_package(
        &state.pool,
        tenant_id,
        auth_context,
        scope_kind,
        scope_id,
        generation,
        request,
    )
    .await
    .map(Json)
}

async fn load_recipient_package(
    State(state): State<SharedState>,
    Path((tenant_id, scope_kind, scope_id, generation)): Path<(Uuid, i16, Uuid, u64)>,
    headers: HeaderMap,
) -> Result<Json<RecipientPackageResponse>, AppError> {
    let auth_context = authenticate(&state, &headers, tenant_id).await?;
    organization::load_recipient_package(
        &state.pool,
        tenant_id,
        auth_context,
        scope_kind,
        scope_id,
        generation,
    )
    .await
    .map(Json)
}

async fn authenticate(
    state: &SharedState,
    headers: &HeaderMap,
    tenant_id: Uuid,
) -> Result<auth::AuthContext, AppError> {
    require_current_protocol(headers)?;
    auth::authenticate(&state.pool, bearer_token(headers)?, tenant_id).await
}

fn require_current_protocol(headers: &HeaderMap) -> Result<(), AppError> {
    let value = headers
        .get(todori_sync::protocol::SYNC_PROTOCOL_VERSION_HEADER)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<u16>().ok());
    if value != Some(todori_sync::protocol::SYNC_PROTOCOL_VERSION) {
        return Err(AppError::bad_request("unsupported sync protocol"));
    }
    Ok(())
}

fn bearer_token(headers: &HeaderMap) -> Result<&str, AppError> {
    headers
        .get(axum::http::header::AUTHORIZATION)
        .ok_or_else(AppError::unauthorized)?
        .to_str()
        .map_err(|_| AppError::unauthorized())?
        .strip_prefix("Bearer ")
        .filter(|value| !value.is_empty())
        .ok_or_else(AppError::unauthorized)
}
