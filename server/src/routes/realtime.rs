use axum::{
    extract::{Path, State},
    http::HeaderMap,
    routing::post,
    Extension, Json, Router,
};
use uuid::Uuid;

use crate::{
    auth,
    realtime::{RealtimeGateway, RealtimeTicketResponse},
    AppError, SharedState,
};

pub fn router() -> Router<SharedState> {
    Router::new().route("/{tenant_id}/realtime/ticket", post(ticket))
}

async fn ticket(
    State(state): State<SharedState>,
    Extension(realtime): Extension<RealtimeGateway>,
    Path(tenant_id): Path<Uuid>,
    headers: HeaderMap,
) -> Result<Json<RealtimeTicketResponse>, AppError> {
    let token = super::sync::bearer_token(&headers)?;
    let auth_context = auth::authenticate(&state.pool, token, tenant_id).await?;
    let Some(response) = realtime.issue_ticket(tenant_id, auth_context.device_id) else {
        tracing::warn!(
            event = "realtime_ticket_unavailable",
            "realtime ticket unavailable"
        );
        return Err(AppError::service_unavailable("realtime unavailable"));
    };
    tracing::info!(event = "realtime_ticket_issued", "realtime ticket issued");
    Ok(Json(response))
}
