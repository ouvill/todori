use sqlx_core::raw_sql::raw_sql;
use sqlx_postgres::{PgPool, PgPoolOptions};

pub async fn connect(database_url: &str) -> Result<PgPool, sqlx_core::Error> {
    PgPoolOptions::new()
        .max_connections(10)
        .connect(database_url)
        .await
}

pub async fn run_migrations(pool: &PgPool) -> Result<(), sqlx_core::Error> {
    raw_sql(include_str!("../migrations/202607080001_sync_server.sql"))
        .execute(pool)
        .await?;
    raw_sql(include_str!(
        "../migrations/202607080002_account_key_bundles.sql"
    ))
    .execute(pool)
    .await?;
    raw_sql(include_str!(
        "../migrations/202607100001_sync_protocol_v2.sql"
    ))
    .execute(pool)
    .await?;
    raw_sql(include_str!("../migrations/202607100002_fuzzy_resync.sql"))
        .execute(pool)
        .await?;
    Ok(())
}
