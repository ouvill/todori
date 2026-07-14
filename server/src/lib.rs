pub mod auth;
pub mod db;
pub mod realtime;
pub mod routes;
pub mod sync;

use axum::{http::StatusCode, response::IntoResponse, Extension, Json, Router};
use realtime::RealtimeGateway;
use serde::Serialize;
use sqlx_postgres::PgPool;
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
}

pub type SharedState = Arc<AppState>;

pub fn build_router(state: AppState) -> Router {
    build_router_with_realtime(state, RealtimeGateway::disabled())
}

pub fn build_router_with_realtime(state: AppState, realtime: RealtimeGateway) -> Router {
    routes::router()
        .layer(Extension(realtime))
        .with_state(Arc::new(state))
}

#[derive(Debug)]
pub struct AppError {
    status: StatusCode,
    message: &'static str,
}

#[derive(Serialize)]
struct ErrorBody {
    error: &'static str,
}

impl AppError {
    pub fn bad_request(message: &'static str) -> Self {
        Self {
            status: StatusCode::BAD_REQUEST,
            message,
        }
    }

    pub fn unauthorized() -> Self {
        Self {
            status: StatusCode::UNAUTHORIZED,
            message: "unauthorized",
        }
    }

    pub fn forbidden() -> Self {
        Self {
            status: StatusCode::FORBIDDEN,
            message: "forbidden",
        }
    }

    pub fn not_found(message: &'static str) -> Self {
        Self {
            status: StatusCode::NOT_FOUND,
            message,
        }
    }

    pub fn conflict(message: &'static str) -> Self {
        Self {
            status: StatusCode::CONFLICT,
            message,
        }
    }

    pub fn gone(message: &'static str) -> Self {
        Self {
            status: StatusCode::GONE,
            message,
        }
    }

    pub fn internal() -> Self {
        Self {
            status: StatusCode::INTERNAL_SERVER_ERROR,
            message: "internal server error",
        }
    }

    pub fn service_unavailable(message: &'static str) -> Self {
        Self {
            status: StatusCode::SERVICE_UNAVAILABLE,
            message,
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        (
            self.status,
            Json(ErrorBody {
                error: self.message,
            }),
        )
            .into_response()
    }
}

impl From<sqlx_core::Error> for AppError {
    fn from(error: sqlx_core::Error) -> Self {
        tracing::error!(kind = "sqlx", error = %error, "server database error");
        Self::internal()
    }
}
