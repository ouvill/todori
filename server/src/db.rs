use sqlx_core::{query::query, raw_sql::raw_sql, row::Row};
use sqlx_postgres::{PgPool, PgPoolOptions, PgTransaction, Postgres};
use uuid::Uuid;

pub async fn connect(database_url: &str) -> Result<PgPool, sqlx_core::Error> {
    PgPoolOptions::new()
        .max_connections(10)
        .connect(database_url)
        .await
}

pub async fn connect_application(database_url: &str) -> Result<PgPool, sqlx_core::Error> {
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(database_url)
        .await?;
    let role = query::<Postgres>(
        "SELECT r.rolcanlogin, r.rolsuper, r.rolinherit, r.rolbypassrls,
                pg_has_role(current_user, 'todori_app', 'USAGE') AS has_app_privileges,
                EXISTS (
                    SELECT 1
                    FROM pg_class c
                    WHERE c.relnamespace = 'public'::regnamespace
                      AND c.relname = ANY($1)
                      AND c.relowner = r.oid
                ) AS owns_protected_table
         FROM pg_roles r
         WHERE r.rolname = current_user",
    )
    .bind(vec![
        "tenants",
        "tenant_members",
        "tenant_seq",
        "tenant_key_bundles",
        "list_key_bundles",
        "sync_records",
        "sync_records_history",
        "tenant_device_continuity",
        "device_resync_sessions",
        "continuity_closure_proofs",
    ])
    .fetch_one(&pool)
    .await?;
    let is_safe = role.try_get::<bool, _>("rolcanlogin")?
        && !role.try_get::<bool, _>("rolsuper")?
        && role.try_get::<bool, _>("rolinherit")?
        && !role.try_get::<bool, _>("rolbypassrls")?
        && role.try_get::<bool, _>("has_app_privileges")?
        && !role.try_get::<bool, _>("owns_protected_table")?;
    if !is_safe {
        pool.close().await;
        return Err(sqlx_core::Error::InvalidArgument(
            "DATABASE_URL must use a non-owner LOGIN role that inherits todori_app and cannot bypass RLS"
                .to_string(),
        ));
    }
    Ok(pool)
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
    raw_sql(include_str!("../migrations/202607110001_rls_hardening.sql"))
        .execute(pool)
        .await?;
    raw_sql(include_str!(
        "../migrations/202607110002_archive_first_deletion.sql"
    ))
    .execute(pool)
    .await?;
    raw_sql(include_str!(
        "../migrations/202607130001_timer_sessions.sql"
    ))
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn begin_tenant_transaction(
    pool: &PgPool,
    tenant_id: Uuid,
) -> Result<PgTransaction<'_>, sqlx_core::Error> {
    let mut tx = pool.begin().await?;
    set_tenant_context(&mut tx, tenant_id).await?;
    Ok(tx)
}

pub async fn set_tenant_context(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
) -> Result<(), sqlx_core::Error> {
    query::<Postgres>("SELECT set_config('todori.tenant_id', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut **tx)
        .await?;
    Ok(())
}

pub async fn set_user_context(
    tx: &mut PgTransaction<'_>,
    user_id: Uuid,
) -> Result<(), sqlx_core::Error> {
    query::<Postgres>("SELECT set_config('todori.user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut **tx)
        .await?;
    Ok(())
}
