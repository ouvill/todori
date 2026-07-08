use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sqlx_core::{query::query, row::Row};
use sqlx_postgres::{PgPool, PgTransaction, Postgres};
use todori_sync::{Hlc, MAX_ENCRYPTED_BLOB_LEN};
use uuid::Uuid;

use crate::{auth::AuthContext, AppError};

pub const MAX_PUSH_OPS: usize = 100;
pub const MAX_PULL_LIMIT: i64 = 100;
pub const DEFAULT_PULL_LIMIT: i64 = 100;
const ALLOWED_FUTURE_SKEW_MS: i64 = 5 * 60 * 1000;

#[derive(Debug, Deserialize)]
pub struct PushRequest {
    pub ops: Vec<PushOpRequest>,
}

#[derive(Debug, Deserialize)]
pub struct PushOpRequest {
    pub record_id: Uuid,
    pub collection: String,
    pub hlc: String,
    pub deleted: bool,
    pub blob: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PushResponse {
    pub results: Vec<PushOpResult>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PushOpResult {
    pub record_id: Uuid,
    pub status: PushStatus,
    pub seq: Option<i64>,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PushStatus {
    Accepted,
    Superseded,
    NoOp,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PullResponse {
    pub records: Vec<PullRecord>,
    pub next_since: i64,
    pub has_more: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PullRecord {
    pub record_id: Uuid,
    pub collection: String,
    pub seq: i64,
    pub hlc: String,
    pub deleted: bool,
    pub blob: String,
}

struct PushOp {
    record_id: Uuid,
    collection: String,
    hlc: String,
    deleted: bool,
    blob: Vec<u8>,
}

struct StoredRecord {
    collection: String,
    seq: i64,
    hlc: String,
    encrypted_blob: Vec<u8>,
    deleted: bool,
}

pub async fn push(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    request: PushRequest,
) -> Result<PushResponse, AppError> {
    if request.ops.len() > MAX_PUSH_OPS {
        return Err(AppError::bad_request("push batch too large"));
    }
    let ops = request
        .ops
        .into_iter()
        .map(validate_push_op)
        .collect::<Result<Vec<_>, _>>()?;

    let mut tx = pool.begin().await?;
    let mut results = Vec::with_capacity(ops.len());
    for op in ops {
        let result = apply_push_op(&mut tx, tenant_id, auth.user_id, op).await?;
        results.push(result);
    }
    tx.commit().await?;
    Ok(PushResponse { results })
}

pub async fn pull(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    since: i64,
    limit: Option<i64>,
) -> Result<PullResponse, AppError> {
    if since < 0 {
        return Err(AppError::bad_request("invalid since"));
    }
    let limit = limit.unwrap_or(DEFAULT_PULL_LIMIT);
    if !(1..=MAX_PULL_LIMIT).contains(&limit) {
        return Err(AppError::bad_request("invalid pull limit"));
    }

    let rows = query::<Postgres>(
        "SELECT record_id, collection, seq, hlc, deleted, encrypted_blob
         FROM sync_records
         WHERE tenant_id = $1 AND seq > $2
         ORDER BY seq ASC
         LIMIT $3",
    )
    .bind(tenant_id)
    .bind(since)
    .bind(limit + 1)
    .fetch_all(pool)
    .await?;

    let has_more = rows.len() as i64 > limit;
    let mut records = Vec::with_capacity(rows.len().min(limit as usize));
    for row in rows.into_iter().take(limit as usize) {
        let blob: Vec<u8> = row
            .try_get("encrypted_blob")
            .map_err(|_| AppError::internal())?;
        records.push(PullRecord {
            record_id: row.try_get("record_id").map_err(|_| AppError::internal())?,
            collection: row
                .try_get("collection")
                .map_err(|_| AppError::internal())?,
            seq: row.try_get("seq").map_err(|_| AppError::internal())?,
            hlc: row.try_get("hlc").map_err(|_| AppError::internal())?,
            deleted: row.try_get("deleted").map_err(|_| AppError::internal())?,
            blob: STANDARD.encode(blob),
        });
    }
    let next_since = records.last().map(|record| record.seq).unwrap_or(since);

    query::<Postgres>("UPDATE devices SET last_pull_at = now() WHERE id = $1 AND user_id = $2")
        .bind(auth.device_id)
        .bind(auth.user_id)
        .execute(pool)
        .await?;

    Ok(PullResponse {
        records,
        next_since,
        has_more,
    })
}

fn validate_push_op(op: PushOpRequest) -> Result<PushOp, AppError> {
    if op.collection.trim().is_empty() || op.collection.len() > 64 {
        return Err(AppError::bad_request("invalid collection"));
    }
    let blob = STANDARD
        .decode(&op.blob)
        .map_err(|_| AppError::bad_request("invalid blob"))?;
    if blob.len() > MAX_ENCRYPTED_BLOB_LEN {
        return Err(AppError::bad_request("blob too large"));
    }
    let hlc = Hlc::decode(&op.hlc).map_err(|_| AppError::bad_request("invalid hlc"))?;
    if hlc.exceeds_future_skew(Utc::now().timestamp_millis(), ALLOWED_FUTURE_SKEW_MS) {
        return Err(AppError::bad_request("hlc too far in future"));
    }
    Ok(PushOp {
        record_id: op.record_id,
        collection: op.collection,
        hlc: op.hlc,
        deleted: op.deleted,
        blob,
    })
}

async fn apply_push_op(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    author_user_id: Uuid,
    op: PushOp,
) -> Result<PushOpResult, AppError> {
    let stored = fetch_stored_record(tx, tenant_id, op.record_id).await?;
    match stored {
        None => {
            let seq = next_tenant_seq(tx, tenant_id).await?;
            query::<Postgres>(
                "INSERT INTO sync_records
                 (tenant_id, record_id, collection, seq, hlc, encrypted_blob, deleted)
                 VALUES ($1, $2, $3, $4, $5, $6, $7)",
            )
            .bind(tenant_id)
            .bind(op.record_id)
            .bind(&op.collection)
            .bind(seq)
            .bind(&op.hlc)
            .bind(&op.blob)
            .bind(op.deleted)
            .execute(&mut **tx)
            .await?;
            Ok(PushOpResult {
                record_id: op.record_id,
                status: PushStatus::Accepted,
                seq: Some(seq),
            })
        }
        Some(stored) if op.hlc > stored.hlc => {
            insert_history(tx, tenant_id, op.record_id, author_user_id, &stored).await?;
            let seq = next_tenant_seq(tx, tenant_id).await?;
            query::<Postgres>(
                "UPDATE sync_records
                 SET collection = $3, seq = $4, hlc = $5, encrypted_blob = $6,
                     deleted = $7, updated_at = now()
                 WHERE tenant_id = $1 AND record_id = $2",
            )
            .bind(tenant_id)
            .bind(op.record_id)
            .bind(&op.collection)
            .bind(seq)
            .bind(&op.hlc)
            .bind(&op.blob)
            .bind(op.deleted)
            .execute(&mut **tx)
            .await?;
            Ok(PushOpResult {
                record_id: op.record_id,
                status: PushStatus::Accepted,
                seq: Some(seq),
            })
        }
        Some(stored) if op.hlc == stored.hlc => {
            if op.collection == stored.collection
                && op.deleted == stored.deleted
                && op.blob == stored.encrypted_blob
            {
                Ok(PushOpResult {
                    record_id: op.record_id,
                    status: PushStatus::NoOp,
                    seq: Some(stored.seq),
                })
            } else {
                Err(AppError::conflict("same hlc with different record content"))
            }
        }
        Some(stored) => Ok(PushOpResult {
            record_id: op.record_id,
            status: PushStatus::Superseded,
            seq: Some(stored.seq),
        }),
    }
}

async fn fetch_stored_record(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    record_id: Uuid,
) -> Result<Option<StoredRecord>, AppError> {
    let row = query::<Postgres>(
        "SELECT collection, seq, hlc, encrypted_blob, deleted
         FROM sync_records
         WHERE tenant_id = $1 AND record_id = $2
         FOR UPDATE",
    )
    .bind(tenant_id)
    .bind(record_id)
    .fetch_optional(&mut **tx)
    .await?;
    row.map(|row| {
        Ok(StoredRecord {
            collection: row
                .try_get("collection")
                .map_err(|_| AppError::internal())?,
            seq: row.try_get("seq").map_err(|_| AppError::internal())?,
            hlc: row.try_get("hlc").map_err(|_| AppError::internal())?,
            encrypted_blob: row
                .try_get("encrypted_blob")
                .map_err(|_| AppError::internal())?,
            deleted: row.try_get("deleted").map_err(|_| AppError::internal())?,
        })
    })
    .transpose()
}

async fn next_tenant_seq(tx: &mut PgTransaction<'_>, tenant_id: Uuid) -> Result<i64, AppError> {
    let row = query::<Postgres>(
        "UPDATE tenant_seq
         SET last_seq = last_seq + 1
         WHERE tenant_id = $1
         RETURNING last_seq",
    )
    .bind(tenant_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(AppError::forbidden)?;
    row.try_get("last_seq").map_err(|_| AppError::internal())
}

async fn insert_history(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    record_id: Uuid,
    author_user_id: Uuid,
    stored: &StoredRecord,
) -> Result<(), AppError> {
    query::<Postgres>(
        "INSERT INTO sync_records_history
         (tenant_id, record_id, collection, seq, hlc, encrypted_blob, deleted, author_user_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(tenant_id)
    .bind(record_id)
    .bind(&stored.collection)
    .bind(stored.seq)
    .bind(&stored.hlc)
    .bind(&stored.encrypted_blob)
    .bind(stored.deleted)
    .bind(author_user_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}
