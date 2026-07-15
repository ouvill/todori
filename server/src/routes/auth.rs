use axum::{extract::State, http::HeaderMap, routing::post, Json, Router};

use crate::{
    auth::{
        self, LoginFinishRequest, LoginSessionResponse, LogoutResponse, OpaqueStartRequest,
        OpaqueStartResponse, RegisterFinishRequest, SessionResponse,
    },
    AppError, SharedState,
};

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/register/start", post(register_start))
        .route("/register/finish", post(register_finish))
        .route("/login/start", post(login_start))
        .route("/login/finish", post(login_finish))
        .route("/logout", post(logout))
        .route("/key-wrappers", post(update_key_wrappers))
}

async fn update_key_wrappers(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(request): Json<todori_sync::account::UpdateKeyWrappersRequest>,
) -> Result<Json<LogoutResponse>, AppError> {
    let token = bearer_token(&headers)?;
    auth::update_key_wrappers(&state.pool, token, request)
        .await
        .map(Json)
}

async fn register_start(
    State(state): State<SharedState>,
    Json(request): Json<OpaqueStartRequest>,
) -> Result<Json<OpaqueStartResponse>, AppError> {
    auth::register_start(&state.pool, request).await.map(Json)
}

async fn register_finish(
    State(state): State<SharedState>,
    Json(request): Json<RegisterFinishRequest>,
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
    Json(request): Json<LoginFinishRequest>,
) -> Result<Json<LoginSessionResponse>, AppError> {
    auth::login_finish(&state.pool, request).await.map(Json)
}

async fn logout(
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Result<Json<LogoutResponse>, AppError> {
    let token = bearer_token(&headers)?;
    auth::logout(&state.pool, token).await.map(Json)
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
