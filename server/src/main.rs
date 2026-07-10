//! Local HTTP entrypoint for `todori-server`.
//!
//! Lambda-specific adapters stay outside this binary. The reusable router and
//! services live in the library crate.

use todori_server::{build_router, db, AppState};
use tokio::signal;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let database_url =
        std::env::var("DATABASE_URL").expect("DATABASE_URL is required for todori-server");
    let migration_database_url = std::env::var("DATABASE_MIGRATION_URL")
        .expect("DATABASE_MIGRATION_URL is required for todori-server");
    let migration_pool = db::connect(&migration_database_url)
        .await
        .expect("failed to connect to migration database");
    db::run_migrations(&migration_pool)
        .await
        .expect("failed to run migrations");
    migration_pool.close().await;
    let pool = db::connect_application(&database_url)
        .await
        .expect("failed to connect with todori_app role");

    let app = build_router(AppState { pool });
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);
    let listener = tokio::net::TcpListener::bind(("0.0.0.0", port))
        .await
        .expect("failed to bind listener");

    tracing::info!("todori-server listening on port {port}");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .expect("server error");
}

async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }

    tracing::info!("shutdown signal received, shutting down gracefully");
}
