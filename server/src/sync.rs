use std::{
    collections::{HashMap, HashSet},
    str::FromStr,
};

use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::{DateTime, Utc};
use sqlx_core::{query::query, row::Row};
use sqlx_postgres::{PgPool, PgTransaction, Postgres};
use taskveil_crypto::{
    organization::{AccountRootPublicKeys, DeviceCertificate},
    CRYPTO_SUITE_ID,
};
use taskveil_sync::{
    account::{ActiveKeyBundleDto, HistoricalKeyBundleDto},
    organization::OrganizationKeyManifest,
    parse_envelope_header,
    protocol::{
        BaseScanResponse, ClosureProof, ContinuityAckRequest, ContinuityAckResponse,
        KeyManifestDescriptor, PullResponse, PushOp, PushRequest, PushResponse, PushResult,
        PushStatus, ResyncStartResponse, StableRecordCursor, SyncCapabilities, SyncCollection,
        SyncRecord, SyncRecordState,
    },
    Hlc, KeyManifest, RotationStatus, MAX_ENCRYPTED_BLOB_LEN,
};
use uuid::Uuid;

use crate::{auth::AuthContext, db, AppError};

pub const MAX_PUSH_OPS: usize = 100;
pub const MAX_PULL_LIMIT: i64 = 100;
pub const DEFAULT_PULL_LIMIT: i64 = 100;
pub const TOMBSTONE_RETENTION_DAYS: i64 = 180;
pub const KEY_HISTORY_RETENTION_DAYS: i64 = 30;
const ALLOWED_FUTURE_SKEW_MS: i64 = 5 * 60 * 1000;

#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PrepareRotationRequest {
    pub suite_id: u16,
    pub generation: u64,
    pub signed_manifest: String,
    pub wrapped_tenant_root_dek: String,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActivateRotationRequest {
    pub generation: u64,
    pub signed_manifest: String,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RotationGenerationRequest {
    pub generation: u64,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RotationStateResponse {
    pub active_generation: u64,
    pub minimum_write_generation: u64,
    pub migrating_generation: Option<u64>,
    pub live_heads_remaining: u64,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DeviceKeyExpiryRequest {
    pub expires_at: Option<DateTime<Utc>>,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct DeviceKeyExpiryResponse {
    pub device_id: Uuid,
    pub expires_at: Option<DateTime<Utc>>,
}

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
        suite_id: u16,
        key_generation: u64,
    },
    Tombstone {
        delete_hlc: String,
    },
}

type StoredStateColumns<'a> = (
    Option<&'a str>,
    Option<&'a str>,
    Option<&'a [u8]>,
    Option<i16>,
    Option<i64>,
);

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
    let tenant_key = query::<Postgres>(
        "SELECT suite_id, generation, minimum_write_generation, signed_manifest, prepared_manifest
         FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'active'",
    )
    .bind(tenant_id)
    .fetch_one(&mut *tx)
    .await?;
    let suite_id = u16::try_from(tenant_key.try_get::<i16, _>("suite_id")?)
        .map_err(|_| AppError::internal())?;
    let active_key_generation = u64::try_from(tenant_key.try_get::<i64, _>("generation")?)
        .map_err(|_| AppError::internal())?;
    let minimum_write_generation =
        u64::try_from(tenant_key.try_get::<i64, _>("minimum_write_generation")?)
            .map_err(|_| AppError::internal())?;
    let migrating_key_generation = query::<Postgres>(
        "SELECT generation FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'migrating'
         ORDER BY generation DESC LIMIT 1",
    )
    .bind(tenant_id)
    .fetch_optional(&mut *tx)
    .await?
    .map(|row| {
        u64::try_from(row.try_get::<i64, _>("generation")?).map_err(|_| AppError::internal())
    })
    .transpose()?;
    let key_manifests = vec![KeyManifestDescriptor {
        suite_id,
        generation: active_key_generation,
        status: RotationStatus::Active,
        minimum_write_generation,
        signed_manifest: STANDARD.encode(tenant_key.try_get::<Vec<u8>, _>("signed_manifest")?),
        predecessor_manifests: tenant_key
            .try_get::<Option<Vec<u8>>, _>("prepared_manifest")?
            .into_iter()
            .map(|bytes| STANDARD.encode(bytes))
            .collect(),
    }];
    tx.commit().await?;
    Ok(SyncCapabilities {
        protocol_version: taskveil_sync::protocol::SYNC_PROTOCOL_VERSION,
        envelope_version: taskveil_sync::ENVELOPE_VERSION,
        gc_horizon_seq,
        continuity_seq,
        continuity_generation,
        required_generation,
        full_resync_required,
        suite_id,
        active_key_generation,
        minimum_write_generation,
        migrating_key_generation,
        key_manifests,
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
                    delete_hlc, encrypted_blob, suite_id, key_generation
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
                    delete_hlc, encrypted_blob, suite_id, key_generation
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
    let rotation_required: bool =
        query::<Postgres>("SELECT rotation_required FROM tenants WHERE id = $1")
            .bind(tenant_id)
            .fetch_one(&mut *tx)
            .await?
            .try_get("rotation_required")?;
    if rotation_required {
        return Err(AppError::conflict("key rotation is required"));
    }
    require_push_continuity(&mut tx, tenant_id, auth.device_id).await?;
    require_live_write_generation(&mut tx, tenant_id, &ops).await?;
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
                delete_hlc, encrypted_blob, suite_id, key_generation
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

pub async fn prepare_rotation(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    request: PrepareRotationRequest,
) -> Result<RotationStateResponse, AppError> {
    if request.suite_id != CRYPTO_SUITE_ID || request.generation == 0 {
        return Err(AppError::bad_request("invalid rotation generation"));
    }
    let generation = i64::try_from(request.generation)
        .map_err(|_| AppError::bad_request("invalid rotation generation"))?;
    let tenant_manifest_bytes = decode_rotation_bytes(&request.signed_manifest, true)?;
    let wrapped_tenant_root_dek = decode_rotation_bytes(&request.wrapped_tenant_root_dek, false)?;

    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    require_rotation_owner(&mut tx, tenant_id, auth.user_id).await?;
    let manifest_mode = rotation_manifest_mode(&mut tx, tenant_id).await?;
    require_rotation_wrapper_shape(&manifest_mode, &wrapped_tenant_root_dek)?;
    let tenant_manifest = validate_rotation_manifest(
        &tenant_manifest_bytes,
        &manifest_mode,
        tenant_id,
        request.generation,
        RotationStatus::Prepared,
        request.generation - 1,
    )?;
    let active_generation: i64 = query::<Postgres>(
        "SELECT generation FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'active' FOR UPDATE",
    )
    .bind(tenant_id)
    .fetch_one(&mut *tx)
    .await?
    .try_get("generation")?;
    if generation != active_generation + 1 {
        return Err(AppError::conflict("rotation generation is not monotonic"));
    }
    let rotation_in_progress: bool = query::<Postgres>(
        "SELECT EXISTS (
             SELECT 1 FROM tenant_key_generations
             WHERE tenant_id = $1 AND status IN ('prepared', 'migrating')
         ) AS in_progress",
    )
    .bind(tenant_id)
    .fetch_one(&mut *tx)
    .await?
    .try_get("in_progress")?;
    if rotation_in_progress {
        return Err(AppError::conflict("key rotation is already in progress"));
    }
    let active_tenant_manifest: Vec<u8> = query::<Postgres>(
        "SELECT signed_manifest FROM tenant_key_generations
         WHERE tenant_id = $1 AND generation = $2 AND status = 'active'",
    )
    .bind(tenant_id)
    .bind(active_generation)
    .fetch_one(&mut *tx)
    .await?
    .try_get("signed_manifest")?;
    let active_tenant_manifest = decode_rotation_manifest(&active_tenant_manifest, &manifest_mode)?;
    if tenant_manifest.manifest.previous_manifest_hash != active_tenant_manifest.hash {
        return Err(AppError::conflict("rotation manifest chain mismatch"));
    }
    query::<Postgres>(
        "INSERT INTO tenant_key_generations
         (tenant_id, generation, suite_id, status, minimum_write_generation,
          signed_manifest, wrapped_tenant_root_dek)
         VALUES ($1, $2, $3, 'prepared', $4, $5, $6)",
    )
    .bind(tenant_id)
    .bind(generation)
    .bind(i16::try_from(CRYPTO_SUITE_ID).map_err(|_| AppError::internal())?)
    .bind(active_generation)
    .bind(tenant_manifest_bytes)
    .bind(wrapped_tenant_root_dek)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::conflict("rotation is already prepared"))?;
    tx.commit().await?;
    Ok(RotationStateResponse {
        active_generation: u64::try_from(active_generation).map_err(|_| AppError::internal())?,
        minimum_write_generation: u64::try_from(active_generation)
            .map_err(|_| AppError::internal())?,
        migrating_generation: None,
        live_heads_remaining: 0,
    })
}

pub async fn activate_rotation(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    request: ActivateRotationRequest,
) -> Result<RotationStateResponse, AppError> {
    let generation = i64::try_from(request.generation)
        .map_err(|_| AppError::bad_request("invalid rotation generation"))?;
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    require_rotation_owner(&mut tx, tenant_id, auth.user_id).await?;
    let manifest_mode = rotation_manifest_mode(&mut tx, tenant_id).await?;
    let active_generation: i64 = query::<Postgres>(
        "SELECT generation FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'active' FOR UPDATE",
    )
    .bind(tenant_id)
    .fetch_one(&mut *tx)
    .await?
    .try_get("generation")?;
    if generation != active_generation + 1 {
        return Err(AppError::conflict("rotation generation is not prepared"));
    }
    let prepared_tenant_bytes: Vec<u8> = query::<Postgres>(
        "SELECT signed_manifest FROM tenant_key_generations
         WHERE tenant_id = $1 AND generation = $2 AND status = 'prepared' FOR UPDATE",
    )
    .bind(tenant_id)
    .bind(generation)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::conflict("rotation generation is not prepared"))?
    .try_get("signed_manifest")?;
    let prepared_tenant = decode_rotation_manifest(&prepared_tenant_bytes, &manifest_mode)?;
    let active_tenant_bytes = decode_rotation_bytes(&request.signed_manifest, true)?;
    let active_tenant = validate_rotation_manifest(
        &active_tenant_bytes,
        &manifest_mode,
        tenant_id,
        request.generation,
        RotationStatus::Active,
        request.generation,
    )?;
    if active_tenant.manifest.previous_manifest_hash != prepared_tenant.hash {
        return Err(AppError::conflict("rotation manifest chain mismatch"));
    }
    let prepared_tenant: bool = query::<Postgres>(
        "SELECT EXISTS (
             SELECT 1 FROM tenant_key_generations
             WHERE tenant_id = $1 AND generation = $2 AND status = 'prepared'
         ) AS exists",
    )
    .bind(tenant_id)
    .bind(generation)
    .fetch_one(&mut *tx)
    .await?
    .try_get("exists")?;
    if !prepared_tenant {
        return Err(AppError::conflict("rotation generation is not prepared"));
    }
    if matches!(manifest_mode, RotationManifestMode::Organization(_)) {
        require_organization_recipient_coverage(
            &mut tx,
            tenant_id,
            request.generation,
            &active_tenant.manifest,
        )
        .await?;
    }
    let live_heads: i64 = query::<Postgres>(
        "SELECT count(*)::BIGINT AS count FROM sync_records
         WHERE tenant_id = $1 AND key_generation = $2",
    )
    .bind(tenant_id)
    .bind(active_generation)
    .fetch_one(&mut *tx)
    .await?
    .try_get("count")?;
    query::<Postgres>(
        "UPDATE tenant_key_generations
         SET status = 'migrating', live_heads_remaining = $3,
             history_retain_until = NULL, migration_completed_at = NULL, updated_at = now()
         WHERE tenant_id = $1 AND generation = $2 AND status = 'active'",
    )
    .bind(tenant_id)
    .bind(active_generation)
    .bind(live_heads)
    .execute(&mut *tx)
    .await?;
    query::<Postgres>(
        "UPDATE tenant_key_generations
         SET status = 'active', minimum_write_generation = $2,
             prepared_manifest = signed_manifest, signed_manifest = $3,
             activated_at = now(), updated_at = now()
         WHERE tenant_id = $1 AND generation = $2 AND status = 'prepared'",
    )
    .bind(tenant_id)
    .bind(generation)
    .bind(active_tenant_bytes)
    .execute(&mut *tx)
    .await?;
    query::<Postgres>("UPDATE tenants SET rotation_required = FALSE WHERE id = $1")
        .bind(tenant_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(RotationStateResponse {
        active_generation: request.generation,
        minimum_write_generation: request.generation,
        migrating_generation: Some(
            u64::try_from(active_generation).map_err(|_| AppError::internal())?,
        ),
        live_heads_remaining: u64::try_from(live_heads).map_err(|_| AppError::internal())?,
    })
}

pub async fn acknowledge_key_generation(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    request: RotationGenerationRequest,
) -> Result<RotationStateResponse, AppError> {
    let generation = i64::try_from(request.generation)
        .map_err(|_| AppError::bad_request("invalid rotation generation"))?;
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let active = load_active_key_generation(&mut tx, tenant_id).await?;
    if generation != active {
        return Err(AppError::conflict("stale key generation acknowledgement"));
    }
    query::<Postgres>(
        "INSERT INTO key_generation_acks (tenant_id, generation, device_id)
         VALUES ($1, $2, $3)
         ON CONFLICT (tenant_id, generation, device_id)
         DO UPDATE SET acknowledged_at = now()",
    )
    .bind(tenant_id)
    .bind(generation)
    .bind(auth.device_id)
    .execute(&mut *tx)
    .await?;
    let state = rotation_state(&mut tx, tenant_id, active).await?;
    tx.commit().await?;
    Ok(state)
}

pub async fn set_device_key_expiry(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    device_id: Uuid,
    request: DeviceKeyExpiryRequest,
) -> Result<DeviceKeyExpiryResponse, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    require_rotation_owner(&mut tx, tenant_id, auth.user_id).await?;
    let updated = query::<Postgres>(
        "UPDATE devices d
         SET key_expires_at = $3
         WHERE d.id = $2
           AND EXISTS (
               SELECT 1 FROM tenant_members m
               WHERE m.tenant_id = $1 AND m.user_id = d.user_id
           )",
    )
    .bind(tenant_id)
    .bind(device_id)
    .bind(request.expires_at)
    .execute(&mut *tx)
    .await?;
    if updated.rows_affected() != 1 {
        return Err(AppError::not_found("device not found"));
    }
    if request
        .expires_at
        .is_some_and(|expiry| expiry <= Utc::now())
    {
        query::<Postgres>(
            "UPDATE sessions SET revoked_at = coalesce(revoked_at, now()) WHERE device_id = $1",
        )
        .bind(device_id)
        .execute(&mut *tx)
        .await?;
        query::<Postgres>(
            "UPDATE tenants SET rotation_required = TRUE WHERE id = $1 AND kind = 'org'",
        )
        .bind(tenant_id)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(DeviceKeyExpiryResponse {
        device_id,
        expires_at: request.expires_at,
    })
}

pub async fn rotation_state_for_tenant(
    pool: &PgPool,
    tenant_id: Uuid,
    _auth: AuthContext,
) -> Result<RotationStateResponse, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let active = load_active_key_generation(&mut tx, tenant_id).await?;
    let state = rotation_state(&mut tx, tenant_id, active).await?;
    tx.commit().await?;
    Ok(state)
}

pub async fn retire_rotation(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    request: RotationGenerationRequest,
) -> Result<RotationStateResponse, AppError> {
    let generation = i64::try_from(request.generation)
        .map_err(|_| AppError::bad_request("invalid rotation generation"))?;
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    require_rotation_owner(&mut tx, tenant_id, auth.user_id).await?;
    let active = load_active_key_generation(&mut tx, tenant_id).await?;
    if active != generation || active <= 1 {
        return Err(AppError::conflict("rotation is not active"));
    }
    // Establish the migration-completion timestamp before evaluating the
    // retention gate. The 30-day window starts when the final live head has
    // moved, never when the new generation was activated.
    let _ = rotation_state(&mut tx, tenant_id, active).await?;
    let old_generation = active - 1;
    let unsafe_live: i64 = query::<Postgres>(
        "SELECT count(*)::BIGINT AS count FROM sync_records
         WHERE tenant_id = $1 AND key_generation < $2",
    )
    .bind(tenant_id)
    .bind(active)
    .fetch_one(&mut *tx)
    .await?
    .try_get("count")?;
    let missing_ack: bool = query::<Postgres>(
        "SELECT EXISTS (
             SELECT 1 FROM devices d
             JOIN tenant_members m ON m.user_id = d.user_id AND m.tenant_id = $1
             WHERE d.revoked_at IS NULL
               AND (d.key_expires_at IS NULL OR d.key_expires_at > now())
               AND NOT EXISTS (
                   SELECT 1 FROM key_generation_acks a
                   WHERE a.tenant_id = $1 AND a.generation = $2 AND a.device_id = d.id
               )
         ) AS missing",
    )
    .bind(tenant_id)
    .bind(active)
    .fetch_one(&mut *tx)
    .await?
    .try_get("missing")?;
    let retention_pending: bool = query::<Postgres>(
        "SELECT history_retain_until IS NULL OR history_retain_until > now() AS pending
         FROM tenant_key_generations
         WHERE tenant_id = $1 AND generation = $2 AND status = 'migrating'
         FOR UPDATE",
    )
    .bind(tenant_id)
    .bind(old_generation)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::conflict("rotation is not migrating"))?
    .try_get("pending")?;
    if unsafe_live != 0 || missing_ack || retention_pending {
        return Err(AppError::conflict("rotation retirement is not safe"));
    }
    query::<Postgres>(
        "UPDATE tenant_key_generations
         SET status = 'retired', wrapped_tenant_root_dek = ''::bytea,
             live_heads_remaining = 0, migration_completed_at = coalesce(migration_completed_at, now()),
             retired_at = now(), updated_at = now()
         WHERE tenant_id = $1 AND generation = $2 AND status = 'migrating'",
    )
    .bind(tenant_id)
    .bind(old_generation)
    .execute(&mut *tx)
    .await?;
    query::<Postgres>("DELETE FROM key_recipients WHERE tenant_id = $1 AND generation = $2")
        .bind(tenant_id)
        .bind(old_generation)
        .execute(&mut *tx)
        .await?;
    let state = rotation_state(&mut tx, tenant_id, active).await?;
    tx.commit().await?;
    Ok(state)
}

fn decode_rotation_bytes(value: &str, manifest: bool) -> Result<Vec<u8>, AppError> {
    let bytes = STANDARD
        .decode(value)
        .map_err(|_| AppError::bad_request("invalid rotation payload"))?;
    if manifest && bytes.len() < taskveil_sync::MIN_AUTHENTICATED_MANIFEST_LEN {
        return Err(AppError::bad_request("invalid rotation payload"));
    }
    Ok(bytes)
}

enum RotationManifestMode {
    Personal,
    Organization(AccountRootPublicKeys),
}

struct ValidatedRotationManifest {
    manifest: KeyManifest,
    hash: [u8; 32],
}

fn decode_rotation_manifest(
    bytes: &[u8],
    mode: &RotationManifestMode,
) -> Result<ValidatedRotationManifest, AppError> {
    match mode {
        RotationManifestMode::Personal => {
            let manifest = KeyManifest::from_authenticated_bytes(bytes)
                .map_err(|_| AppError::bad_request("invalid rotation manifest"))?;
            let hash = manifest
                .authenticated_hash()
                .map_err(|_| AppError::bad_request("invalid rotation manifest"))?;
            Ok(ValidatedRotationManifest { manifest, hash })
        }
        RotationManifestMode::Organization(root) => {
            let signed = OrganizationKeyManifest::decode(bytes)
                .map_err(|_| AppError::bad_request("invalid rotation manifest"))?;
            signed
                .verify(root)
                .map_err(|_| AppError::bad_request("invalid rotation manifest"))?;
            let hash = signed
                .authenticated_hash()
                .map_err(|_| AppError::bad_request("invalid rotation manifest"))?;
            Ok(ValidatedRotationManifest {
                manifest: signed.manifest,
                hash,
            })
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn validate_rotation_manifest(
    bytes: &[u8],
    mode: &RotationManifestMode,
    tenant_id: Uuid,
    generation: u64,
    status: RotationStatus,
    minimum_write_generation: u64,
) -> Result<ValidatedRotationManifest, AppError> {
    let validated = decode_rotation_manifest(bytes, mode)?;
    let manifest = &validated.manifest;
    if manifest.tenant_id != tenant_id
        || manifest.suite_id != CRYPTO_SUITE_ID
        || manifest.generation != generation
        || manifest.status != status
        || manifest.minimum_write_generation != minimum_write_generation
    {
        return Err(AppError::bad_request("invalid rotation manifest"));
    }
    Ok(validated)
}

async fn rotation_manifest_mode(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
) -> Result<RotationManifestMode, AppError> {
    let row = query::<Postgres>(
        "SELECT t.kind, u.account_root_public
         FROM tenants t JOIN users u ON u.id = t.owner_user_id WHERE t.id = $1",
    )
    .bind(tenant_id)
    .fetch_one(&mut **tx)
    .await?;
    match row.try_get::<String, _>("kind")?.as_str() {
        "personal" => Ok(RotationManifestMode::Personal),
        "org" => Ok(RotationManifestMode::Organization(
            AccountRootPublicKeys::decode(&row.try_get::<Vec<u8>, _>("account_root_public")?)
                .map_err(|_| AppError::internal())?,
        )),
        _ => Err(AppError::internal()),
    }
}

fn require_rotation_wrapper_shape(
    mode: &RotationManifestMode,
    tenant_wrapper: &[u8],
) -> Result<(), AppError> {
    let valid = match mode {
        RotationManifestMode::Personal => !tenant_wrapper.is_empty(),
        RotationManifestMode::Organization(_) => tenant_wrapper.is_empty(),
    };
    if !valid {
        return Err(AppError::bad_request("invalid rotation key wrapper"));
    }
    Ok(())
}

async fn require_organization_recipient_coverage(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    generation: u64,
    tenant_manifest: &KeyManifest,
) -> Result<(), AppError> {
    let required = query::<Postgres>(
        "SELECT d.id, d.certificate
         FROM devices d
         JOIN tenant_members m ON m.user_id = d.user_id AND m.tenant_id = $1
         JOIN tenants t ON t.id = m.tenant_id
         WHERE d.certificate IS NOT NULL AND d.certificate_fingerprint IS NOT NULL
           AND d.revoked_at IS NULL AND (d.key_expires_at IS NULL OR d.key_expires_at > now())
           AND (d.user_id = t.owner_user_id OR m.verification_state = 'verified')",
    )
    .bind(tenant_id)
    .fetch_all(&mut **tx)
    .await?
    .into_iter()
    .map(|row| {
        let certificate = DeviceCertificate::decode(&row.try_get::<Vec<u8>, _>("certificate")?)
            .map_err(|_| sqlx_core::Error::Decode("invalid device certificate".into()))?;
        let fingerprint = certificate
            .recipient_key_fingerprint()
            .map_err(|_| sqlx_core::Error::Decode("invalid recipient key fingerprint".into()))?;
        Ok((row.try_get::<Uuid, _>("id")?, fingerprint))
    })
    .collect::<Result<HashMap<_, _>, sqlx_core::Error>>()?;
    if required.is_empty() {
        return Err(AppError::conflict(
            "rotation recipient coverage is incomplete",
        ));
    }
    let required_fingerprints = required.values().copied().collect::<HashSet<_>>();
    if tenant_manifest
        .recipient_fingerprints
        .iter()
        .copied()
        .collect::<HashSet<_>>()
        != required_fingerprints
    {
        return Err(AppError::conflict(
            "rotation recipient coverage is incomplete",
        ));
    }
    require_scope_recipient_rows(tx, tenant_id, generation, &required).await?;
    Ok(())
}

async fn require_scope_recipient_rows(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    generation: u64,
    required: &HashMap<Uuid, [u8; 32]>,
) -> Result<(), AppError> {
    let rows = query::<Postgres>(
        "SELECT device_id, recipient_key_fingerprint, wrapped_dek
         FROM key_recipients
         WHERE tenant_id = $1 AND generation = $2",
    )
    .bind(tenant_id)
    .bind(i64::try_from(generation).map_err(|_| AppError::internal())?)
    .fetch_all(&mut **tx)
    .await?;
    if rows.len() != required.len() {
        return Err(AppError::conflict(
            "rotation recipient coverage is incomplete",
        ));
    }
    for row in rows {
        let device_id: Uuid = row.try_get("device_id")?;
        let fingerprint: [u8; 32] = row
            .try_get::<Vec<u8>, _>("recipient_key_fingerprint")?
            .try_into()
            .map_err(|_| AppError::internal())?;
        if required.get(&device_id) != Some(&fingerprint) {
            return Err(AppError::conflict(
                "rotation recipient coverage is incomplete",
            ));
        }
        let wrapped: Vec<u8> = row.try_get("wrapped_dek")?;
        if taskveil_crypto::organization::HybridDekPackage::decode(&wrapped).is_err() {
            return Err(AppError::conflict(
                "rotation recipient coverage is incomplete",
            ));
        }
    }
    Ok(())
}

async fn require_rotation_owner(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let allowed: bool = query::<Postgres>(
        "SELECT EXISTS (
             SELECT 1 FROM tenant_members
             WHERE tenant_id = $1 AND user_id = $2 AND role IN ('owner', 'admin')
         ) AS allowed",
    )
    .bind(tenant_id)
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await?
    .try_get("allowed")?;
    if !allowed {
        return Err(AppError::forbidden());
    }
    Ok(())
}

async fn load_active_key_generation(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
) -> Result<i64, AppError> {
    query::<Postgres>(
        "SELECT generation FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'active'",
    )
    .bind(tenant_id)
    .fetch_one(&mut **tx)
    .await?
    .try_get("generation")
    .map_err(|_| AppError::internal())
}

async fn rotation_state(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    active: i64,
) -> Result<RotationStateResponse, AppError> {
    let migrating = query::<Postgres>(
        "SELECT generation FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'migrating' ORDER BY generation DESC LIMIT 1",
    )
    .bind(tenant_id)
    .fetch_optional(&mut **tx)
    .await?
    .map(|row| row.try_get::<i64, _>("generation"))
    .transpose()?;
    let live_heads: i64 = if let Some(generation) = migrating {
        query::<Postgres>(
            "SELECT count(*)::BIGINT AS count FROM sync_records
             WHERE tenant_id = $1 AND key_generation = $2",
        )
        .bind(tenant_id)
        .bind(generation)
        .fetch_one(&mut **tx)
        .await?
        .try_get("count")?
    } else {
        0
    };
    if let Some(generation) = migrating {
        query::<Postgres>(
            "UPDATE tenant_key_generations
             SET live_heads_remaining = $3,
                 migration_completed_at = CASE WHEN $3 = 0 THEN coalesce(migration_completed_at, now()) ELSE NULL END,
                 history_retain_until = CASE
                     WHEN $3 = 0 THEN coalesce(history_retain_until, now() + ($4 * interval '1 day'))
                     ELSE NULL
                 END,
                 updated_at = now()
             WHERE tenant_id = $1 AND generation = $2",
        )
        .bind(tenant_id)
        .bind(generation)
        .bind(live_heads)
        .bind(KEY_HISTORY_RETENTION_DAYS)
        .execute(&mut **tx)
        .await?;
    }
    Ok(RotationStateResponse {
        active_generation: u64::try_from(active).map_err(|_| AppError::internal())?,
        minimum_write_generation: u64::try_from(active).map_err(|_| AppError::internal())?,
        migrating_generation: migrating
            .map(|generation| u64::try_from(generation).map_err(|_| AppError::internal()))
            .transpose()?,
        live_heads_remaining: u64::try_from(live_heads).map_err(|_| AppError::internal())?,
    })
}

pub async fn active_key_bundle(
    pool: &PgPool,
    tenant_id: Uuid,
    _auth: AuthContext,
) -> Result<ActiveKeyBundleDto, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let tenant = query::<Postgres>(
        "SELECT suite_id, generation, signed_manifest, wrapped_tenant_root_dek
         FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'active'",
    )
    .bind(tenant_id)
    .fetch_one(&mut *tx)
    .await?;
    let historical_tenants = query::<Postgres>(
        "SELECT generation, signed_manifest, wrapped_tenant_root_dek
         FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'migrating'
         ORDER BY generation ASC",
    )
    .bind(tenant_id)
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;

    let suite_id =
        u16::try_from(tenant.try_get::<i16, _>("suite_id")?).map_err(|_| AppError::internal())?;
    let generation =
        u64::try_from(tenant.try_get::<i64, _>("generation")?).map_err(|_| AppError::internal())?;
    let mut migrating_generations = Vec::with_capacity(historical_tenants.len());
    for historical in historical_tenants {
        let historical_generation = u64::try_from(historical.try_get::<i64, _>("generation")?)
            .map_err(|_| AppError::internal())?;
        migrating_generations.push(HistoricalKeyBundleDto {
            generation: historical_generation,
            wrapped_tenant_root_dek: STANDARD
                .encode(historical.try_get::<Vec<u8>, _>("wrapped_tenant_root_dek")?),
            signed_manifest: STANDARD.encode(historical.try_get::<Vec<u8>, _>("signed_manifest")?),
        });
    }
    Ok(ActiveKeyBundleDto {
        suite_id,
        generation,
        wrapped_tenant_root_dek: STANDARD
            .encode(tenant.try_get::<Vec<u8>, _>("wrapped_tenant_root_dek")?),
        signed_manifest: STANDARD.encode(tenant.try_get::<Vec<u8>, _>("signed_manifest")?),
        migrating_generations,
    })
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

async fn require_live_write_generation(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    ops: &[ValidatedPushOp],
) -> Result<(), AppError> {
    if !ops
        .iter()
        .any(|op| matches!(op.state, StoredState::Live { .. }))
    {
        return Ok(());
    }
    let row = query::<Postgres>(
        "SELECT suite_id, generation, minimum_write_generation
         FROM tenant_key_generations
         WHERE tenant_id = $1 AND status = 'active'
         FOR SHARE",
    )
    .bind(tenant_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| AppError::conflict("active key generation required"))?;
    let suite_id: u16 = u16::try_from(
        row.try_get::<i16, _>("suite_id")
            .map_err(|_| AppError::internal())?,
    )
    .map_err(|_| AppError::internal())?;
    let active_generation: u64 = u64::try_from(
        row.try_get::<i64, _>("generation")
            .map_err(|_| AppError::internal())?,
    )
    .map_err(|_| AppError::internal())?;
    let minimum_write_generation: u64 = u64::try_from(
        row.try_get::<i64, _>("minimum_write_generation")
            .map_err(|_| AppError::internal())?,
    )
    .map_err(|_| AppError::internal())?;
    for op in ops {
        if let StoredState::Live {
            suite_id: envelope_suite,
            key_generation,
            ..
        } = op.state
        {
            if envelope_suite != suite_id
                || key_generation != active_generation
                || key_generation < minimum_write_generation
            {
                return Err(AppError::conflict("stale key generation"));
            }
        }
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
            let header = parse_envelope_header(&encrypted_blob)
                .map_err(|_| AppError::bad_request("invalid live blob"))?;
            StoredState::Live {
                mutation_hlc,
                encrypted_blob,
                suite_id: header.suite_id,
                key_generation: header.key_generation,
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
        && !matches!(
            (&stored.state, &op.state),
            (
                StoredState::Live {
                    key_generation: old_generation,
                    ..
                },
                StoredState::Live {
                    key_generation: new_generation,
                    ..
                }
            ) if new_generation > old_generation
        )
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
                ..
            } => SyncRecordState::Live {
                mutation_hlc,
                blob: STANDARD.encode(encrypted_blob),
            },
            Self::Tombstone { delete_hlc } => SyncRecordState::Tombstone { delete_hlc },
        }
    }

    fn columns(&self) -> StoredStateColumns<'_> {
        match self {
            Self::Live {
                mutation_hlc,
                encrypted_blob,
                suite_id,
                key_generation,
            } => (
                Some(mutation_hlc),
                None,
                Some(encrypted_blob),
                i16::try_from(*suite_id).ok(),
                i64::try_from(*key_generation).ok(),
            ),
            Self::Tombstone { delete_hlc } => (None, Some(delete_hlc), None, None, None),
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
                delete_hlc, encrypted_blob, suite_id, key_generation
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
    let suite_id: Option<i16> = row.try_get("suite_id").map_err(|_| AppError::internal())?;
    let key_generation: Option<i64> = row
        .try_get("key_generation")
        .map_err(|_| AppError::internal())?;
    let state = match (
        mutation_hlc,
        delete_hlc,
        encrypted_blob,
        suite_id,
        key_generation,
    ) {
        (Some(mutation_hlc), None, Some(encrypted_blob), Some(suite_id), Some(key_generation)) => {
            StoredState::Live {
                mutation_hlc,
                encrypted_blob,
                suite_id: u16::try_from(suite_id).map_err(|_| AppError::internal())?,
                key_generation: u64::try_from(key_generation).map_err(|_| AppError::internal())?,
            }
        }
        (None, Some(delete_hlc), None, None, None) => StoredState::Tombstone { delete_hlc },
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
    let (mutation_hlc, delete_hlc, encrypted_blob, suite_id, key_generation) = op.state.columns();
    query::<Postgres>(
        "INSERT INTO sync_records
         (tenant_id, record_id, collection, seq, revision_hlc, mutation_hlc,
          delete_hlc, encrypted_blob, suite_id, key_generation)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)",
    )
    .bind(tenant_id)
    .bind(op.record_id)
    .bind(op.collection.as_str())
    .bind(seq)
    .bind(&op.revision_hlc)
    .bind(mutation_hlc)
    .bind(delete_hlc)
    .bind(encrypted_blob)
    .bind(suite_id)
    .bind(key_generation)
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
    let (mutation_hlc, delete_hlc, encrypted_blob, suite_id, key_generation) = op.state.columns();
    query::<Postgres>(
        "UPDATE sync_records
         SET seq = $3, revision_hlc = $4, mutation_hlc = $5,
             delete_hlc = $6, encrypted_blob = $7, suite_id = $8,
             key_generation = $9, updated_at = now()
         WHERE tenant_id = $1 AND record_id = $2",
    )
    .bind(tenant_id)
    .bind(op.record_id)
    .bind(seq)
    .bind(&op.revision_hlc)
    .bind(mutation_hlc)
    .bind(delete_hlc)
    .bind(encrypted_blob)
    .bind(suite_id)
    .bind(key_generation)
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
    let (mutation_hlc, delete_hlc, encrypted_blob, suite_id, key_generation) =
        stored.state.columns();
    query::<Postgres>(
        "INSERT INTO sync_records_history
         (tenant_id, record_id, collection, seq, revision_hlc, mutation_hlc,
          delete_hlc, encrypted_blob, suite_id, key_generation, author_user_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
    )
    .bind(tenant_id)
    .bind(stored.record_id)
    .bind(stored.collection.as_str())
    .bind(stored.seq)
    .bind(&stored.revision_hlc)
    .bind(mutation_hlc)
    .bind(delete_hlc)
    .bind(encrypted_blob)
    .bind(suite_id)
    .bind(key_generation)
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
