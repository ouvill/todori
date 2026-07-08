use axum::{extract::State, routing::post, Json, Router};

use crate::{
    auth::{self, OpaqueFinishRequest, OpaqueStartRequest, OpaqueStartResponse, SessionResponse},
    AppError, SharedState,
};

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/register/start", post(register_start))
        .route("/register/finish", post(register_finish))
        .route("/login/start", post(login_start))
        .route("/login/finish", post(login_finish))
}

async fn register_start(
    State(state): State<SharedState>,
    Json(request): Json<OpaqueStartRequest>,
) -> Result<Json<OpaqueStartResponse>, AppError> {
    auth::register_start(&state.pool, request).await.map(Json)
}

async fn register_finish(
    State(state): State<SharedState>,
    Json(request): Json<OpaqueFinishRequest>,
) -> Result<Json<SessionResponse>, AppError> {
    auth::register_finish(&state.pool, request).await.map(Json)
}

async fn login_start(
    State(state): State<SharedState>,
    Json(request): Json<OpaqueStartRequest>,
) -> Result<Json<OpaqueStartResponse>, AppError> {
    auth::login_start(&state.pool, request).await.map(Json)
}

async fn login_finish(
    State(state): State<SharedState>,
    Json(request): Json<OpaqueFinishRequest>,
) -> Result<Json<SessionResponse>, AppError> {
    auth::login_finish(&state.pool, request).await.map(Json)
}
