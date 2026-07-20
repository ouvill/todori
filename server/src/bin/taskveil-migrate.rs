use taskveil_server::db;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();
    if run().await.is_err() {
        tracing::error!(event = "database_migration_failed");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), ()> {
    let database_url = std::env::var("DATABASE_MIGRATION_URL").map_err(|_| ())?;
    let pool = db::connect(&database_url).await.map_err(|_| ())?;
    db::run_migrations(&pool).await.map_err(|_| ())?;
    pool.close().await;
    tracing::info!(event = "database_migration_completed");
    Ok(())
}
