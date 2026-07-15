use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

use crate::SharedState;

pub mod auth;
pub mod organization;
pub mod realtime;
pub mod sync;

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/health", get(health))
        .nest("/v1/auth", auth::router())
        .nest(
            "/v2/tenants",
            sync::router()
                .merge(realtime::router())
                .merge(organization::router()),
        )
}

async fn health() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}
