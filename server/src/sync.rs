use std::{collections::HashSet, str::FromStr};

use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::{DateTime, Utc};
use sqlx_core::{query::query, row::Row};
use sqlx_postgres::{PgPool, PgTransaction, Postgres};
use todori_crypto::{key_hierarchy::INITIAL_KEY_GENERATION, CRYPTO_SUITE_ID};
use todori_sync::{
    account::ListDekBundleDto,
    protocol::{
        BaseScanResponse, ClosureProof, ContinuityAckRequest, ContinuityAckResponse, PullResponse,
        PushOp, PushRequest, PushResponse, PushResult, PushStatus, ResyncStartResponse,
        StableRecordCursor, SyncCapabilities, SyncCollection, SyncRecord, SyncRecordState,
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

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct RetireListKeyResponse {}

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
    auth: AuthContext,
    since: i64,
) -> Result<SyncCapabilities, AppError> {
    if since < 0 {
        return Err(AppError::bad_request("invalid since"));
    }
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    ensure_device_continuity(&mut tx, tenant_id, auth.device_id).await?;
    let row = query::<Postgres>(
        "SELECT seq.gc_horizon_seq, seq.last_seq,
                continuity.continuity_seq, continuity.continuity_generation,
                continuity.required_generation, continuity.initialized
         FROM tenant_seq AS seq
         JOIN tenant_device_continuity AS continuity
           ON continuity.tenant_id = seq.tenant_id
          AND continuity.device_id = $2
         WHERE seq.tenant_id = $1",
    )
    .bind(tenant_id)
    .bind(auth.device_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(AppError::forbidden)?;
    let gc_horizon_seq = row
        .try_get("gc_horizon_seq")
        .map_err(|_| AppError::internal())?;
    let last_seq: i64 = row.try_get("last_seq").map_err(|_| AppError::internal())?;
    let continuity_seq: i64 = row
        .try_get("continuity_seq")
        .map_err(|_| AppError::internal())?;
    let continuity_generation: i64 = row
        .try_get("continuity_generation")
        .map_err(|_| AppError::internal())?;
    let required_generation: i64 = row
        .try_get("required_generation")
        .map_err(|_| AppError::internal())?;
    let initialized: bool = row
        .try_get("initialized")
        .map_err(|_| AppError::internal())?;
    let full_resync_required = (!initialized && last_seq > 0)
        || continuity_seq < gc_horizon_seq
        || continuity_generation != required_generation;
    tx.commit().await?;
    Ok(SyncCapabilities {
        protocol_version: todori_sync::protocol::SYNC_PROTOCOL_VERSION,
        envelope_version: todori_sync::ENVELOPE_VERSION,
        gc_horizon_seq,
        continuity_seq,
        continuity_generation,
        required_generation,
        full_resync_required,
    })
}

pub async fn begin_full_resync(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
) -> Result<ResyncStartResponse, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    ensure_device_continuity(&mut tx, tenant_id, auth.device_id).await?;
    let row = query::<Postgres>(
        "SELECT seq.last_seq, continuity.required_generation
         FROM tenant_seq AS seq
         JOIN tenant_device_continuity AS continuity
           ON continuity.tenant_id = seq.tenant_id
          AND continuity.device_id = $2
         WHERE seq.tenant_id = $1
         FOR UPDATE OF seq, continuity",
    )
    .bind(tenant_id)
    .bind(auth.device_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(AppError::forbidden)?;
    let base_seq = row.try_get("last_seq").map_err(|_| AppError::internal())?;
    let required_generation: i64 = row
        .try_get("required_generation")
        .map_err(|_| AppError::internal())?;
    let generation = required_generation
        .checked_add(1)
        .ok_or_else(AppError::internal)?;
    query::<Postgres>(
        "UPDATE tenant_device_continuity
         SET required_generation = $3, updated_at = now()
         WHERE tenant_id = $1 AND device_id = $2",
    )
    .bind(tenant_id)
    .bind(auth.device_id)
    .bind(generation)
    .execute(&mut *tx)
    .await?;
    query::<Postgres>(
        "INSERT INTO device_resync_sessions
         (tenant_id, device_id, generation, base_seq)
         VALUES ($1, $2, $3, $4)",
    )
    .bind(tenant_id)
    .bind(auth.device_id)
    .bind(generation)
    .bind(base_seq)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(ResyncStartResponse {
        base_seq,
        generation,
    })
}

pub async fn scan_base(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    generation: i64,
    cursor: Option<StableRecordCursor>,
    limit: Option<i64>,
) -> Result<BaseScanResponse, AppError> {
    if generation <= 0 {
        return Err(AppError::bad_request("invalid resync generation"));
    }
    let limit = validated_page_limit(limit)?;
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let session = query::<Postgres>(
        "SELECT session.base_cursor_collection, session.base_cursor_record_id,
                session.base_complete, continuity.required_generation
         FROM device_resync_sessions AS session
         JOIN tenant_device_continuity AS continuity
           ON continuity.tenant_id = session.tenant_id
          AND continuity.device_id = session.device_id
         WHERE session.tenant_id = $1 AND session.device_id = $2
           AND session.generation = $3
         FOR UPDATE OF session, continuity",
    )
    .bind(tenant_id)
    .bind(auth.device_id)
    .bind(generation)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::conflict("invalid resync generation"))?;
    let expected_collection: Option<String> = session
        .try_get("base_cursor_collection")
        .map_err(|_| AppError::internal())?;
    let expected_record_id: Option<Uuid> = session
        .try_get("base_cursor_record_id")
        .map_err(|_| AppError::internal())?;
    let base_complete: bool = session
        .try_get("base_complete")
        .map_err(|_| AppError::internal())?;
    let required_generation: i64 = session
        .try_get("required_generation")
        .map_err(|_| AppError::internal())?;
    let presented_cursor = cursor
        .as_ref()
        .map(|value| (value.collection.as_str().to_string(), value.record_id));
    if base_complete
        || required_generation != generation
        || presented_cursor != expected_collection.zip(expected_record_id)
    {
        return Err(AppError::conflict("invalid resync cursor"));
    }
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
    let next_collection = next_cursor.as_ref().map(|value| value.collection.as_str());
    let next_record_id = next_cursor.as_ref().map(|value| value.record_id);
    query::<Postgres>(
        "UPDATE device_resync_sessions
         SET base_cursor_collection = $4, base_cursor_record_id = $5,
             base_complete = $6, updated_at = now()
         WHERE tenant_id = $1 AND device_id = $2 AND generation = $3",
    )
    .bind(tenant_id)
    .bind(auth.device_id)
    .bind(generation)
    .bind(next_collection)
    .bind(next_record_id)
    .bind(!has_more)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
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
    require_push_continuity(&mut tx, tenant_id, auth.device_id).await?;
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
    generation: Option<i64>,
) -> Result<PullResponse, AppError> {
    if since < 0 {
        return Err(AppError::bad_request("invalid since"));
    }
    let limit = validated_page_limit(limit)?;

    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    ensure_device_continuity(&mut tx, tenant_id, auth.device_id).await?;
    let continuity = query::<Postgres>(
        "SELECT continuity_generation, required_generation
         FROM tenant_device_continuity
         WHERE tenant_id = $1 AND device_id = $2",
    )
    .bind(tenant_id)
    .bind(auth.device_id)
    .fetch_one(&mut *tx)
    .await?;
    let continuity_generation: i64 = continuity
        .try_get("continuity_generation")
        .map_err(|_| AppError::internal())?;
    let required_generation: i64 = continuity
        .try_get("required_generation")
        .map_err(|_| AppError::internal())?;
    let proof_generation = if let Some(generation) = generation {
        let base_complete: bool = query::<Postgres>(
            "SELECT base_complete
             FROM device_resync_sessions
             WHERE tenant_id = $1 AND device_id = $2 AND generation = $3",
        )
        .bind(tenant_id)
        .bind(auth.device_id)
        .bind(generation)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::conflict("invalid resync generation"))?
        .try_get("base_complete")
        .map_err(|_| AppError::internal())?;
        if generation != required_generation || !base_complete {
            return Err(AppError::conflict("resync base is incomplete"));
        }
        generation
    } else {
        if continuity_generation != required_generation {
            return Err(AppError::gone("full resync required"));
        }
        required_generation
    };
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

    let closure_proof = if !has_more && next_since == high_water {
        query::<Postgres>(
            "DELETE FROM continuity_closure_proofs
             WHERE tenant_id = $1 AND device_id = $2 AND acknowledged_at IS NULL",
        )
        .bind(tenant_id)
        .bind(auth.device_id)
        .execute(&mut *tx)
        .await?;
        let proof = ClosureProof {
            proof_id: Uuid::now_v7(),
            tenant_id,
            device_id: auth.device_id,
            high_water,
            generation: proof_generation,
        };
        query::<Postgres>(
            "INSERT INTO continuity_closure_proofs
             (proof_id, tenant_id, device_id, high_water, generation)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(proof.proof_id)
        .bind(proof.tenant_id)
        .bind(proof.device_id)
        .bind(proof.high_water)
        .bind(proof.generation)
        .execute(&mut *tx)
        .await?;
        Some(proof)
    } else {
        None
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
        closure_proof,
    })
}

pub async fn upsert_list_key_bundle(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    bundle: ListDekBundleDto,
) -> Result<UpsertListKeyResponse, AppError> {
    let wrapped_list_dek = STANDARD
        .decode(&bundle.wrapped_list_dek)
        .map_err(|_| AppError::bad_request("invalid list key bundle"))?;
    if wrapped_list_dek.is_empty() {
        return Err(AppError::bad_request("invalid list key bundle"));
    }
    if bundle.generation != INITIAL_KEY_GENERATION {
        return Err(AppError::bad_request("invalid list key generation"));
    }
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    require_push_continuity(&mut tx, tenant_id, auth.device_id).await?;
    let inserted = query::<Postgres>(
        "INSERT INTO list_key_bundles
            (tenant_id, list_id, suite_id, generation, wrapped_list_dek)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (tenant_id, list_id) DO NOTHING",
    )
    .bind(tenant_id)
    .bind(bundle.list_id)
    .bind(i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())?)
    .bind(i64::try_from(bundle.generation).map_err(|_| AppError::internal())?)
    .bind(&wrapped_list_dek)
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        let existing = query::<Postgres>(
            "SELECT suite_id, generation, wrapped_list_dek
             FROM list_key_bundles
             WHERE tenant_id = $1 AND list_id = $2",
        )
        .bind(tenant_id)
        .bind(bundle.list_id)
        .fetch_one(&mut *tx)
        .await?;
        let existing_suite: i16 = existing.try_get("suite_id")?;
        let existing_generation: i64 = existing.try_get("generation")?;
        let existing_wrapped: Vec<u8> = existing.try_get("wrapped_list_dek")?;
        if existing_suite != i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())?
            || existing_generation
                != i64::try_from(bundle.generation).map_err(|_| AppError::internal())?
            || existing_wrapped != wrapped_list_dek
        {
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
        "SELECT list_id, generation, wrapped_list_dek
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
                generation: u64::try_from(
                    row.try_get::<i64, _>("generation")
                        .map_err(|_| AppError::internal())?,
                )
                .map_err(|_| AppError::internal())?,
                wrapped_list_dek: STANDARD.encode(wrapped_list_dek),
            })
        })
        .collect()
}

pub async fn retire_list_key_bundle(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    list_id: Uuid,
) -> Result<RetireListKeyResponse, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    require_push_continuity(&mut tx, tenant_id, auth.device_id).await?;
    let row = query::<Postgres>(
        "SELECT bundle.deletion_seq, seq.gc_horizon_seq
         FROM list_key_bundles AS bundle
         JOIN tenant_seq AS seq ON seq.tenant_id = bundle.tenant_id
         WHERE bundle.tenant_id = $1 AND bundle.list_id = $2
         FOR UPDATE OF bundle, seq",
    )
    .bind(tenant_id)
    .bind(list_id)
    .fetch_optional(&mut *tx)
    .await?;
    let Some(row) = row else {
        tx.commit().await?;
        return Ok(RetireListKeyResponse {});
    };
    let deletion_seq: Option<i64> = row
        .try_get("deletion_seq")
        .map_err(|_| AppError::internal())?;
    let gc_horizon_seq: i64 = row
        .try_get("gc_horizon_seq")
        .map_err(|_| AppError::internal())?;
    let Some(deletion_seq) = deletion_seq else {
        return Err(AppError::conflict("list key retirement is not safe"));
    };
    let current_exists: bool = query::<Postgres>(
        "SELECT EXISTS (
             SELECT 1 FROM sync_records
             WHERE tenant_id = $1 AND record_id = $2
         ) AS current_exists",
    )
    .bind(tenant_id)
    .bind(list_id)
    .fetch_one(&mut *tx)
    .await?
    .try_get("current_exists")
    .map_err(|_| AppError::internal())?;
    let unsafe_device_exists: bool = query::<Postgres>(
        "SELECT EXISTS (
             SELECT 1 FROM tenant_device_continuity
             WHERE tenant_id = $1
               AND continuity_seq < $2
               AND required_generation <= continuity_generation
         ) AS unsafe_device_exists",
    )
    .bind(tenant_id)
    .bind(deletion_seq)
    .fetch_one(&mut *tx)
    .await?
    .try_get("unsafe_device_exists")
    .map_err(|_| AppError::internal())?;
    let unacknowledged_proof_exists: bool = query::<Postgres>(
        "SELECT EXISTS (
             SELECT 1 FROM continuity_closure_proofs
             WHERE tenant_id = $1 AND acknowledged_at IS NULL
         ) AS unacknowledged_proof_exists",
    )
    .bind(tenant_id)
    .fetch_one(&mut *tx)
    .await?
    .try_get("unacknowledged_proof_exists")
    .map_err(|_| AppError::internal())?;
    if current_exists
        || deletion_seq > gc_horizon_seq
        || unsafe_device_exists
        || unacknowledged_proof_exists
    {
        return Err(AppError::conflict("list key retirement is not safe"));
    }
    query::<Postgres>(
        "DELETE FROM list_key_bundles
         WHERE tenant_id = $1 AND list_id = $2 AND deletion_seq = $3",
    )
    .bind(tenant_id)
    .bind(list_id)
    .bind(deletion_seq)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(RetireListKeyResponse {})
}

pub async fn ack_continuity(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    request: ContinuityAckRequest,
) -> Result<ContinuityAckResponse, AppError> {
    let proof = request.proof;
    if proof.tenant_id != tenant_id || proof.device_id != auth.device_id {
        return Err(AppError::forbidden());
    }
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    ensure_device_continuity(&mut tx, tenant_id, auth.device_id).await?;
    let row = query::<Postgres>(
        "SELECT proof.high_water, proof.generation, proof.acknowledged_at,
                continuity.continuity_seq, continuity.continuity_generation,
                continuity.required_generation
         FROM continuity_closure_proofs AS proof
         JOIN tenant_device_continuity AS continuity
           ON continuity.tenant_id = proof.tenant_id
          AND continuity.device_id = proof.device_id
         WHERE proof.proof_id = $1 AND proof.tenant_id = $2 AND proof.device_id = $3
         FOR UPDATE OF proof, continuity",
    )
    .bind(proof.proof_id)
    .bind(tenant_id)
    .bind(auth.device_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(AppError::forbidden)?;
    let stored_high_water: i64 = row
        .try_get("high_water")
        .map_err(|_| AppError::internal())?;
    let stored_generation: i64 = row
        .try_get("generation")
        .map_err(|_| AppError::internal())?;
    let required_generation: i64 = row
        .try_get("required_generation")
        .map_err(|_| AppError::internal())?;
    if stored_high_water != proof.high_water
        || stored_generation != proof.generation
        || proof.generation != required_generation
    {
        return Err(AppError::conflict("invalid continuity proof"));
    }
    query::<Postgres>(
        "UPDATE tenant_device_continuity
         SET continuity_seq = greatest(continuity_seq, $3),
             continuity_generation = $4, initialized = true, updated_at = now()
         WHERE tenant_id = $1 AND device_id = $2",
    )
    .bind(tenant_id)
    .bind(auth.device_id)
    .bind(proof.high_water)
    .bind(proof.generation)
    .execute(&mut *tx)
    .await?;
    query::<Postgres>(
        "UPDATE continuity_closure_proofs
         SET acknowledged_at = coalesce(acknowledged_at, now())
         WHERE proof_id = $1",
    )
    .bind(proof.proof_id)
    .execute(&mut *tx)
    .await?;
    let continuity_seq = std::cmp::max(
        row.try_get("continuity_seq")
            .map_err(|_| AppError::internal())?,
        proof.high_water,
    );
    tx.commit().await?;
    Ok(ContinuityAckResponse {
        continuity_seq,
        continuity_generation: proof.generation,
    })
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
         ), expired AS (
             UPDATE tenant_device_continuity AS continuity
             SET required_generation = greatest(
                     continuity.required_generation,
                     continuity.continuity_generation + 1
                 ),
                 updated_at = now()
             FROM tenant_seq AS seq, advanced
             WHERE continuity.tenant_id = advanced.tenant_id
               AND seq.tenant_id = continuity.tenant_id
               AND continuity.continuity_seq < seq.gc_horizon_seq
             RETURNING continuity.tenant_id
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

async fn ensure_device_continuity(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    device_id: Uuid,
) -> Result<(), AppError> {
    query::<Postgres>(
        "INSERT INTO tenant_device_continuity (tenant_id, device_id)
         VALUES ($1, $2)
         ON CONFLICT (tenant_id, device_id) DO NOTHING",
    )
    .bind(tenant_id)
    .bind(device_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn require_push_continuity(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    device_id: Uuid,
) -> Result<(), AppError> {
    ensure_device_continuity(tx, tenant_id, device_id).await?;
    let row = query::<Postgres>(
        "SELECT seq.last_seq, seq.gc_horizon_seq, continuity.continuity_seq,
                continuity.continuity_generation, continuity.required_generation,
                continuity.initialized
         FROM tenant_seq AS seq
         JOIN tenant_device_continuity AS continuity
           ON continuity.tenant_id = seq.tenant_id
          AND continuity.device_id = $2
         WHERE seq.tenant_id = $1
         FOR UPDATE OF seq, continuity",
    )
    .bind(tenant_id)
    .bind(device_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(AppError::forbidden)?;
    let last_seq: i64 = row.try_get("last_seq").map_err(|_| AppError::internal())?;
    let gc_horizon_seq: i64 = row
        .try_get("gc_horizon_seq")
        .map_err(|_| AppError::internal())?;
    let continuity_seq: i64 = row
        .try_get("continuity_seq")
        .map_err(|_| AppError::internal())?;
    let continuity_generation: i64 = row
        .try_get("continuity_generation")
        .map_err(|_| AppError::internal())?;
    let required_generation: i64 = row
        .try_get("required_generation")
        .map_err(|_| AppError::internal())?;
    let initialized: bool = row
        .try_get("initialized")
        .map_err(|_| AppError::internal())?;
    if !initialized
        || continuity_seq < gc_horizon_seq
        || continuity_seq != last_seq
        || continuity_generation != required_generation
    {
        return Err(AppError::conflict("device continuity closure required"));
    }
    Ok(())
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
        if matches!(op.state, StoredState::Tombstone { .. }) {
            purge_record_history(tx, tenant_id, op.record_id).await?;
        }
        let seq = next_tenant_seq(tx, tenant_id).await?;
        insert_record(tx, tenant_id, &op, seq).await?;
        mark_list_key_deletion(tx, tenant_id, &op, seq).await?;
        return Ok(op.result(PushStatus::Accepted, Some((seq, None))));
    };

    if stored.collection != op.collection {
        return Err(AppError::bad_request("record collection is immutable"));
    }
    if stored.revision_hlc == op.revision_hlc && stored.state == op.state {
        return Ok(op.result(PushStatus::NoOp, Some((stored.seq, None))));
    }
    if op.collection == SyncCollection::TimerSessions
        && matches!(stored.state, StoredState::Live { .. })
        && matches!(op.state, StoredState::Live { .. })
    {
        let seq = stored.seq;
        return Ok(op.result(PushStatus::Conflict, Some((seq, Some(stored)))));
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

    if matches!(op.state, StoredState::Tombstone { .. }) {
        purge_record_history(tx, tenant_id, op.record_id).await?;
    } else {
        insert_history(tx, tenant_id, author_user_id, &stored).await?;
    }
    let seq = next_tenant_seq(tx, tenant_id).await?;
    update_record(tx, tenant_id, &op, seq).await?;
    mark_list_key_deletion(tx, tenant_id, &op, seq).await?;
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
        (StoredState::Live { .. }, StoredState::Tombstone { .. }) => true,
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

async fn purge_record_history(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    record_id: Uuid,
) -> Result<(), AppError> {
    query::<Postgres>(
        "DELETE FROM sync_records_history
         WHERE tenant_id = $1 AND record_id = $2",
    )
    .bind(tenant_id)
    .bind(record_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn mark_list_key_deletion(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    op: &ValidatedPushOp,
    seq: i64,
) -> Result<(), AppError> {
    if op.collection == SyncCollection::Lists && matches!(op.state, StoredState::Tombstone { .. }) {
        query::<Postgres>(
            "UPDATE list_key_bundles
             SET deletion_seq = $3
             WHERE tenant_id = $1 AND list_id = $2",
        )
        .bind(tenant_id)
        .bind(op.record_id)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}
