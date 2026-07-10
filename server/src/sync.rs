use std::{collections::HashSet, str::FromStr};

use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::{DateTime, Utc};
use sqlx_core::{query::query, row::Row};
use sqlx_postgres::{PgPool, PgTransaction, Postgres};
use todori_sync::{
    account::ListDekBundleDto,
    protocol::{
        BaseScanResponse, PullResponse, PushOp, PushRequest, PushResponse, PushResult, PushStatus,
        ResyncStartResponse, StableRecordCursor, SyncCapabilities, SyncCollection, SyncRecord,
        SyncRecordState,
    },
    Hlc, MAX_ENCRYPTED_BLOB_LEN,
};
use uuid::Uuid;

use crate::{auth::AuthContext, db, AppError};

pub const MAX_PUSH_OPS: usize = 100;
pub const MAX_PULL_LIMIT: i64 = 100;
pub const DEFAULT_PULL_LIMIT: i64 = 100;
pub const TOMBSTONE_RETENTION_DAYS: i64 = 180;
const ALLOWED_FUTURE_SKEW_MS: i64 = 5 * 60 * 1000;

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct UpsertListKeyResponse {}

struct ValidatedPushOp {
    op_id: Uuid,
    record_id: Uuid,
    collection: SyncCollection,
    base_revision_hlc: Option<String>,
    revision_hlc: String,
    state: StoredState,
}

#[derive(Clone, PartialEq, Eq)]
enum StoredState {
    Live {
        mutation_hlc: String,
        encrypted_blob: Vec<u8>,
    },
    Tombstone {
        delete_hlc: String,
    },
}

struct StoredRecord {
    record_id: Uuid,
    collection: SyncCollection,
    seq: i64,
    revision_hlc: String,
    state: StoredState,
}

pub async fn preflight(
    pool: &PgPool,
    tenant_id: Uuid,
    since: i64,
) -> Result<SyncCapabilities, AppError> {
    if since < 0 {
        return Err(AppError::bad_request("invalid since"));
    }
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let row = query::<Postgres>(
        "SELECT gc_horizon_seq
         FROM tenant_seq
         WHERE tenant_id = $1",
    )
    .bind(tenant_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(AppError::forbidden)?;
    let gc_horizon_seq = row
        .try_get("gc_horizon_seq")
        .map_err(|_| AppError::internal())?;
    if since > 0 && since < gc_horizon_seq {
        return Err(AppError::gone("full resync required"));
    }
    tx.commit().await?;
    Ok(SyncCapabilities {
        protocol_version: todori_sync::protocol::SYNC_PROTOCOL_VERSION,
        envelope_version: todori_sync::ENVELOPE_VERSION,
        gc_horizon_seq,
    })
}

pub async fn begin_full_resync(
    pool: &PgPool,
    tenant_id: Uuid,
) -> Result<ResyncStartResponse, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let row = query::<Postgres>("SELECT last_seq FROM tenant_seq WHERE tenant_id = $1")
        .bind(tenant_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(AppError::forbidden)?;
    let base_seq = row.try_get("last_seq").map_err(|_| AppError::internal())?;
    tx.commit().await?;
    Ok(ResyncStartResponse { base_seq })
}

pub async fn scan_base(
    pool: &PgPool,
    tenant_id: Uuid,
    cursor: Option<StableRecordCursor>,
    limit: Option<i64>,
) -> Result<BaseScanResponse, AppError> {
    let limit = validated_page_limit(limit)?;
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let rows = if let Some(cursor) = cursor {
        query::<Postgres>(
            "SELECT record_id, collection, seq, revision_hlc, mutation_hlc,
                    delete_hlc, encrypted_blob
             FROM sync_records
             WHERE tenant_id = $1
               AND (collection, record_id) > ($2, $3)
             ORDER BY collection ASC, record_id ASC
             LIMIT $4",
        )
        .bind(tenant_id)
        .bind(cursor.collection.as_str())
        .bind(cursor.record_id)
        .bind(limit + 1)
        .fetch_all(&mut *tx)
        .await?
    } else {
        query::<Postgres>(
            "SELECT record_id, collection, seq, revision_hlc, mutation_hlc,
                    delete_hlc, encrypted_blob
             FROM sync_records
             WHERE tenant_id = $1
             ORDER BY collection ASC, record_id ASC
             LIMIT $2",
        )
        .bind(tenant_id)
        .bind(limit + 1)
        .fetch_all(&mut *tx)
        .await?
    };
    tx.commit().await?;
    let has_more = rows.len() as i64 > limit;
    let records = rows
        .into_iter()
        .take(limit as usize)
        .map(stored_record_from_row)
        .map(|record| record.map(StoredRecord::into_wire))
        .collect::<Result<Vec<_>, _>>()?;
    let next_cursor = records.last().map(|record| StableRecordCursor {
        collection: record.collection,
        record_id: record.record_id,
    });
    Ok(BaseScanResponse {
        records,
        next_cursor,
        has_more,
    })
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
    let mut op_ids = HashSet::with_capacity(request.ops.len());
    let ops = request
        .ops
        .into_iter()
        .map(|op| {
            if !op_ids.insert(op.op_id) {
                return Err(AppError::bad_request("duplicate op id"));
            }
            validate_push_op(op)
        })
        .collect::<Result<Vec<_>, _>>()?;

    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let mut results = Vec::with_capacity(ops.len());
    for op in ops {
        results.push(apply_push_op(&mut tx, tenant_id, auth.user_id, op).await?);
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
    let limit = validated_page_limit(limit)?;

    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let high_water: i64 = query::<Postgres>("SELECT last_seq FROM tenant_seq WHERE tenant_id = $1")
        .bind(tenant_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(AppError::forbidden)?
        .try_get("last_seq")
        .map_err(|_| AppError::internal())?;
    if since > high_water {
        return Err(AppError::bad_request("invalid since"));
    }

    let rows = query::<Postgres>(
        "SELECT record_id, collection, seq, revision_hlc, mutation_hlc,
                delete_hlc, encrypted_blob
         FROM sync_records
         WHERE tenant_id = $1 AND seq > $2 AND seq <= $3
         ORDER BY seq ASC
         LIMIT $4",
    )
    .bind(tenant_id)
    .bind(since)
    .bind(high_water)
    .bind(limit + 1)
    .fetch_all(&mut *tx)
    .await?;

    let has_more = rows.len() as i64 > limit;
    let records = rows
        .into_iter()
        .take(limit as usize)
        .map(stored_record_from_row)
        .map(|record| record.map(StoredRecord::into_wire))
        .collect::<Result<Vec<_>, _>>()?;
    let next_since = if has_more {
        records.last().map(|record| record.seq).unwrap_or(since)
    } else {
        high_water
    };

    query::<Postgres>("UPDATE devices SET last_pull_at = now() WHERE id = $1 AND user_id = $2")
        .bind(auth.device_id)
        .bind(auth.user_id)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;

    Ok(PullResponse {
        records,
        next_since,
        has_more,
        high_water,
    })
}

pub async fn upsert_list_key_bundle(
    pool: &PgPool,
    tenant_id: Uuid,
    _auth: AuthContext,
    bundle: ListDekBundleDto,
) -> Result<UpsertListKeyResponse, AppError> {
    let wrapped_list_dek = STANDARD
        .decode(&bundle.wrapped_list_dek)
        .map_err(|_| AppError::bad_request("invalid list key bundle"))?;
    if wrapped_list_dek.is_empty() {
        return Err(AppError::bad_request("invalid list key bundle"));
    }
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let inserted = query::<Postgres>(
        "INSERT INTO list_key_bundles (tenant_id, list_id, wrapped_list_dek)
         VALUES ($1, $2, $3)
         ON CONFLICT (tenant_id, list_id) DO NOTHING",
    )
    .bind(tenant_id)
    .bind(bundle.list_id)
    .bind(&wrapped_list_dek)
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        let existing = query::<Postgres>(
            "SELECT wrapped_list_dek
             FROM list_key_bundles
             WHERE tenant_id = $1 AND list_id = $2",
        )
        .bind(tenant_id)
        .bind(bundle.list_id)
        .fetch_one(&mut *tx)
        .await?
        .try_get::<Vec<u8>, _>("wrapped_list_dek")?;
        if existing != wrapped_list_dek {
            return Err(AppError::conflict("list key bundle conflict"));
        }
    }
    tx.commit().await?;
    Ok(UpsertListKeyResponse {})
}

pub async fn list_key_bundles(
    pool: &PgPool,
    tenant_id: Uuid,
    _auth: AuthContext,
) -> Result<Vec<ListDekBundleDto>, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let rows = query::<Postgres>(
        "SELECT list_id, wrapped_list_dek
         FROM list_key_bundles
         WHERE tenant_id = $1
         ORDER BY created_at ASC, list_id ASC",
    )
    .bind(tenant_id)
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;

    rows.into_iter()
        .map(|row| {
            let list_id = row.try_get("list_id").map_err(|_| AppError::internal())?;
            let wrapped_list_dek: Vec<u8> = row
                .try_get("wrapped_list_dek")
                .map_err(|_| AppError::internal())?;
            Ok(ListDekBundleDto {
                list_id,
                wrapped_list_dek: STANDARD.encode(wrapped_list_dek),
            })
        })
        .collect()
}

pub async fn gc_tombstones(pool: &PgPool, cutoff: DateTime<Utc>) -> Result<u64, AppError> {
    let row = query::<Postgres>(
        "WITH deleted AS (
             DELETE FROM sync_records
             WHERE delete_hlc IS NOT NULL AND updated_at < $1
             RETURNING tenant_id, seq
         ), horizons AS (
             SELECT tenant_id, max(seq) AS gc_horizon_seq, count(*) AS deleted_count
             FROM deleted
             GROUP BY tenant_id
         ), advanced AS (
             UPDATE tenant_seq AS target
             SET gc_horizon_seq = greatest(target.gc_horizon_seq, horizons.gc_horizon_seq)
             FROM horizons
             WHERE target.tenant_id = horizons.tenant_id
             RETURNING target.tenant_id
         )
         SELECT coalesce(sum(horizons.deleted_count), 0)::BIGINT AS deleted_count
         FROM horizons
         JOIN advanced USING (tenant_id)",
    )
    .bind(cutoff)
    .fetch_one(pool)
    .await?;
    let deleted: i64 = row
        .try_get("deleted_count")
        .map_err(|_| AppError::internal())?;
    u64::try_from(deleted).map_err(|_| AppError::internal())
}

fn validated_page_limit(limit: Option<i64>) -> Result<i64, AppError> {
    let limit = limit.unwrap_or(DEFAULT_PULL_LIMIT);
    if !(1..=MAX_PULL_LIMIT).contains(&limit) {
        return Err(AppError::bad_request("invalid page limit"));
    }
    Ok(limit)
}

fn validate_push_op(op: PushOp) -> Result<ValidatedPushOp, AppError> {
    validate_hlc(&op.revision_hlc)?;
    if let Some(base) = &op.base_revision_hlc {
        validate_hlc(base)?;
    }
    let state = match op.state {
        SyncRecordState::Live { mutation_hlc, blob } => {
            validate_hlc(&mutation_hlc)?;
            if op.revision_hlc < mutation_hlc {
                return Err(AppError::bad_request(
                    "revision clock precedes semantic clock",
                ));
            }
            let encrypted_blob = STANDARD
                .decode(blob)
                .map_err(|_| AppError::bad_request("invalid blob"))?;
            if encrypted_blob.is_empty() {
                return Err(AppError::bad_request("invalid live blob"));
            }
            if encrypted_blob.len() > MAX_ENCRYPTED_BLOB_LEN {
                return Err(AppError::bad_request("blob too large"));
            }
            StoredState::Live {
                mutation_hlc,
                encrypted_blob,
            }
        }
        SyncRecordState::Tombstone { delete_hlc } => {
            validate_hlc(&delete_hlc)?;
            if op.revision_hlc < delete_hlc {
                return Err(AppError::bad_request(
                    "revision clock precedes semantic clock",
                ));
            }
            StoredState::Tombstone { delete_hlc }
        }
    };
    Ok(ValidatedPushOp {
        op_id: op.op_id,
        record_id: op.record_id,
        collection: op.collection,
        base_revision_hlc: op.base_revision_hlc,
        revision_hlc: op.revision_hlc,
        state,
    })
}

fn validate_hlc(value: &str) -> Result<(), AppError> {
    let hlc = Hlc::decode(value).map_err(|_| AppError::bad_request("invalid hlc"))?;
    if hlc.exceeds_future_skew(Utc::now().timestamp_millis(), ALLOWED_FUTURE_SKEW_MS) {
        return Err(AppError::bad_request("hlc too far in future"));
    }
    Ok(())
}

async fn apply_push_op(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    author_user_id: Uuid,
    op: ValidatedPushOp,
) -> Result<PushResult, AppError> {
    lock_tenant_sequence(tx, tenant_id).await?;
    let stored = fetch_stored_record(tx, tenant_id, op.record_id).await?;
    let Some(stored) = stored else {
        if op.base_revision_hlc.is_some() {
            return Ok(op.result(PushStatus::Conflict, None));
        }
        let seq = next_tenant_seq(tx, tenant_id).await?;
        insert_record(tx, tenant_id, &op, seq).await?;
        return Ok(op.result(PushStatus::Accepted, Some((seq, None))));
    };

    if stored.collection != op.collection {
        return Err(AppError::bad_request("record collection is immutable"));
    }
    if stored.revision_hlc == op.revision_hlc && stored.state == op.state {
        return Ok(op.result(PushStatus::NoOp, Some((stored.seq, None))));
    }
    if stored.revision_hlc == op.revision_hlc
        || op.base_revision_hlc.as_deref() != Some(stored.revision_hlc.as_str())
        || op.revision_hlc <= stored.revision_hlc
    {
        let seq = stored.seq;
        return Ok(op.result(PushStatus::Conflict, Some((seq, Some(stored)))));
    }
    if semantic_state_is_superseded(&op.state, &stored.state) {
        let seq = stored.seq;
        return Ok(op.result(PushStatus::Superseded, Some((seq, Some(stored)))));
    }

    insert_history(tx, tenant_id, author_user_id, &stored).await?;
    let seq = next_tenant_seq(tx, tenant_id).await?;
    update_record(tx, tenant_id, &op, seq).await?;
    Ok(op.result(PushStatus::Accepted, Some((seq, None))))
}

fn semantic_state_is_superseded(incoming: &StoredState, current: &StoredState) -> bool {
    match (incoming, current) {
        (
            StoredState::Live {
                mutation_hlc: incoming,
                ..
            },
            StoredState::Live {
                mutation_hlc: current,
                ..
            },
        ) => incoming < current,
        (
            StoredState::Tombstone {
                delete_hlc: incoming,
            },
            StoredState::Tombstone {
                delete_hlc: current,
            },
        ) => incoming <= current,
        (
            StoredState::Live {
                mutation_hlc: incoming,
                ..
            },
            StoredState::Tombstone {
                delete_hlc: current,
            },
        ) => incoming <= current,
        (
            StoredState::Tombstone {
                delete_hlc: incoming,
            },
            StoredState::Live {
                mutation_hlc: current,
                ..
            },
        ) => incoming <= current,
    }
}

impl ValidatedPushOp {
    fn result(
        &self,
        status: PushStatus,
        stored: Option<(i64, Option<StoredRecord>)>,
    ) -> PushResult {
        let (seq, current) = stored.map_or((None, None), |(seq, current)| {
            (Some(seq), current.map(StoredRecord::into_wire))
        });
        PushResult {
            op_id: self.op_id,
            record_id: self.record_id,
            collection: self.collection,
            status,
            seq,
            current,
        }
    }
}

impl StoredRecord {
    fn into_wire(self) -> SyncRecord {
        SyncRecord {
            record_id: self.record_id,
            collection: self.collection,
            seq: self.seq,
            revision_hlc: self.revision_hlc,
            state: self.state.into_wire(),
        }
    }
}

impl StoredState {
    fn into_wire(self) -> SyncRecordState {
        match self {
            Self::Live {
                mutation_hlc,
                encrypted_blob,
            } => SyncRecordState::Live {
                mutation_hlc,
                blob: STANDARD.encode(encrypted_blob),
            },
            Self::Tombstone { delete_hlc } => SyncRecordState::Tombstone { delete_hlc },
        }
    }

    fn columns(&self) -> (Option<&str>, Option<&str>, Option<&[u8]>) {
        match self {
            Self::Live {
                mutation_hlc,
                encrypted_blob,
            } => (Some(mutation_hlc), None, Some(encrypted_blob)),
            Self::Tombstone { delete_hlc } => (None, Some(delete_hlc), None),
        }
    }
}

async fn lock_tenant_sequence(tx: &mut PgTransaction<'_>, tenant_id: Uuid) -> Result<(), AppError> {
    query::<Postgres>("SELECT last_seq FROM tenant_seq WHERE tenant_id = $1 FOR UPDATE")
        .bind(tenant_id)
        .fetch_optional(&mut **tx)
        .await?
        .ok_or_else(AppError::forbidden)?;
    Ok(())
}

async fn fetch_stored_record(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    record_id: Uuid,
) -> Result<Option<StoredRecord>, AppError> {
    query::<Postgres>(
        "SELECT record_id, collection, seq, revision_hlc, mutation_hlc,
                delete_hlc, encrypted_blob
         FROM sync_records
         WHERE tenant_id = $1 AND record_id = $2
         FOR UPDATE",
    )
    .bind(tenant_id)
    .bind(record_id)
    .fetch_optional(&mut **tx)
    .await?
    .map(stored_record_from_row)
    .transpose()
}

fn stored_record_from_row(row: sqlx_postgres::PgRow) -> Result<StoredRecord, AppError> {
    let record_id = row.try_get("record_id").map_err(|_| AppError::internal())?;
    let collection: String = row
        .try_get("collection")
        .map_err(|_| AppError::internal())?;
    let collection = SyncCollection::from_str(&collection).map_err(|_| AppError::internal())?;
    let seq = row.try_get("seq").map_err(|_| AppError::internal())?;
    let revision_hlc = row
        .try_get("revision_hlc")
        .map_err(|_| AppError::internal())?;
    let mutation_hlc: Option<String> = row
        .try_get("mutation_hlc")
        .map_err(|_| AppError::internal())?;
    let delete_hlc: Option<String> = row
        .try_get("delete_hlc")
        .map_err(|_| AppError::internal())?;
    let encrypted_blob: Option<Vec<u8>> = row
        .try_get("encrypted_blob")
        .map_err(|_| AppError::internal())?;
    let state = match (mutation_hlc, delete_hlc, encrypted_blob) {
        (Some(mutation_hlc), None, Some(encrypted_blob)) => StoredState::Live {
            mutation_hlc,
            encrypted_blob,
        },
        (None, Some(delete_hlc), None) => StoredState::Tombstone { delete_hlc },
        _ => return Err(AppError::internal()),
    };
    Ok(StoredRecord {
        record_id,
        collection,
        seq,
        revision_hlc,
        state,
    })
}

async fn insert_record(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    op: &ValidatedPushOp,
    seq: i64,
) -> Result<(), AppError> {
    let (mutation_hlc, delete_hlc, encrypted_blob) = op.state.columns();
    query::<Postgres>(
        "INSERT INTO sync_records
         (tenant_id, record_id, collection, seq, revision_hlc, mutation_hlc,
          delete_hlc, encrypted_blob)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(tenant_id)
    .bind(op.record_id)
    .bind(op.collection.as_str())
    .bind(seq)
    .bind(&op.revision_hlc)
    .bind(mutation_hlc)
    .bind(delete_hlc)
    .bind(encrypted_blob)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn update_record(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    op: &ValidatedPushOp,
    seq: i64,
) -> Result<(), AppError> {
    let (mutation_hlc, delete_hlc, encrypted_blob) = op.state.columns();
    query::<Postgres>(
        "UPDATE sync_records
         SET seq = $3, revision_hlc = $4, mutation_hlc = $5,
             delete_hlc = $6, encrypted_blob = $7, updated_at = now()
         WHERE tenant_id = $1 AND record_id = $2",
    )
    .bind(tenant_id)
    .bind(op.record_id)
    .bind(seq)
    .bind(&op.revision_hlc)
    .bind(mutation_hlc)
    .bind(delete_hlc)
    .bind(encrypted_blob)
    .execute(&mut **tx)
    .await?;
    Ok(())
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
    author_user_id: Uuid,
    stored: &StoredRecord,
) -> Result<(), AppError> {
    let (mutation_hlc, delete_hlc, encrypted_blob) = stored.state.columns();
    query::<Postgres>(
        "INSERT INTO sync_records_history
         (tenant_id, record_id, collection, seq, revision_hlc, mutation_hlc,
          delete_hlc, encrypted_blob, author_user_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(tenant_id)
    .bind(stored.record_id)
    .bind(stored.collection.as_str())
    .bind(stored.seq)
    .bind(&stored.revision_hlc)
    .bind(mutation_hlc)
    .bind(delete_hlc)
    .bind(encrypted_blob)
    .bind(author_user_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}
