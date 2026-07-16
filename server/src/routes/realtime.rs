use axum::{
    extract::{Path, State},
    http::HeaderMap,
    routing::post,
    Extension, Json, Router,
};
use uuid::Uuid;

use crate::{
    billing,
    realtime::{observe_realtime, RealtimeEvent, RealtimeGateway, RealtimeTicketResponse},
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
    let auth_context =
        billing::authenticate_sync_request(&state.pool, &state.billing, token, tenant_id).await?;
    let Some(response) = realtime.issue_ticket(tenant_id, auth_context.device_id) else {
        observe_realtime(RealtimeEvent::TicketUnavailable);
        return Err(AppError::service_unavailable("realtime unavailable"));
    };
    observe_realtime(RealtimeEvent::TicketIssued);
    Ok(Json(response))
}
