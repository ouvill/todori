use base64::{engine::general_purpose::STANDARD, Engine as _};
use sqlx_core::{query::query, row::Row};
use sqlx_postgres::{PgPool, PgTransaction, Postgres};
use todori_crypto::organization::{
    derive_safety_number, AccountRootPublicKeys, DeviceCertificate, HybridDekPackage,
    HybridScopeKind, SignedDeviceRevocation,
};
use todori_sync::organization::{
    OrganizationDeviceDto, OrganizationDeviceRevocationRequest, OrganizationDeviceRosterDto,
    OrganizationInviteRequest, OrganizationKeyManifest, OrganizationMemberResponse,
    OrganizationSafetyConfirmRequest, OrganizationSafetyResponse, RecipientPackageRequest,
    RecipientPackageResponse,
};
use uuid::Uuid;

use crate::{auth::AuthContext, db, AppError};

pub async fn invite_member(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    request: OrganizationInviteRequest,
) -> Result<OrganizationMemberResponse, AppError> {
    let email = request.email.trim().to_ascii_lowercase();
    if email.is_empty() || email.len() > 320 || !email.contains('@') {
        return Err(AppError::bad_request("invalid email"));
    }
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let owner_user_id = require_org_admin(&mut tx, tenant_id, auth.user_id).await?;
    let member_user_id: Uuid =
        query::<Postgres>("SELECT id FROM users WHERE lower(email) = lower($1)")
            .bind(email)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| AppError::not_found("account not found"))?
            .try_get("id")?;
    if member_user_id == owner_user_id {
        return Err(AppError::conflict("owner is already a member"));
    }
    query::<Postgres>(
        "INSERT INTO tenant_members
            (tenant_id, user_id, role, verification_state)
         VALUES ($1, $2, 'member', 'unverified')
         ON CONFLICT (tenant_id, user_id) DO NOTHING",
    )
    .bind(tenant_id)
    .bind(member_user_id)
    .execute(&mut *tx)
    .await?;
    let verification_state: String = query::<Postgres>(
        "SELECT verification_state FROM tenant_members
         WHERE tenant_id = $1 AND user_id = $2",
    )
    .bind(tenant_id)
    .bind(member_user_id)
    .fetch_one(&mut *tx)
    .await?
    .try_get("verification_state")?;
    tx.commit().await?;
    Ok(OrganizationMemberResponse {
        member_user_id,
        verification_state,
    })
}

pub async fn safety_number(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    member_user_id: Uuid,
) -> Result<OrganizationSafetyResponse, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let owner_user_id =
        require_safety_participant(&mut tx, tenant_id, auth.user_id, member_user_id).await?;
    let response = load_safety_response(&mut tx, tenant_id, owner_user_id, member_user_id).await?;
    tx.commit().await?;
    Ok(response)
}

pub async fn confirm_safety_number(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    request: OrganizationSafetyConfirmRequest,
) -> Result<OrganizationSafetyResponse, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let owner_user_id =
        require_safety_participant(&mut tx, tenant_id, auth.user_id, request.member_user_id)
            .await?;
    if auth.user_id != owner_user_id && auth.user_id != request.member_user_id {
        return Err(AppError::forbidden());
    }
    let current =
        load_safety_response(&mut tx, tenant_id, owner_user_id, request.member_user_id).await?;
    let supplied_digest = STANDARD
        .decode(&request.digest)
        .map_err(|_| AppError::bad_request("invalid Safety number"))?;
    let expected_digest = STANDARD
        .decode(&current.digest)
        .map_err(|_| AppError::internal())?;
    if supplied_digest != expected_digest {
        return Err(AppError::conflict("Safety number changed"));
    }
    let owner_root = AccountRootPublicKeys::decode(
        &STANDARD
            .decode(&current.owner_root_public)
            .map_err(|_| AppError::internal())?,
    )
    .map_err(|_| AppError::internal())?;
    let member_root = AccountRootPublicKeys::decode(
        &STANDARD
            .decode(&current.member_root_public)
            .map_err(|_| AppError::internal())?,
    )
    .map_err(|_| AppError::internal())?;
    let owner_fingerprint = owner_root.fingerprint().map_err(|_| AppError::internal())?;
    let member_fingerprint = member_root
        .fingerprint()
        .map_err(|_| AppError::internal())?;

    query::<Postgres>(
        "UPDATE tenant_members
         SET verification_state = 'unverified', owner_confirmed_at = NULL,
             member_confirmed_at = NULL, verified_at = NULL,
             safety_number_digest = $3,
             safety_owner_root_fingerprint = $4,
             safety_member_root_fingerprint = $5
         WHERE tenant_id = $1 AND user_id = $2
           AND (safety_owner_root_fingerprint IS DISTINCT FROM $4
                OR safety_member_root_fingerprint IS DISTINCT FROM $5)",
    )
    .bind(tenant_id)
    .bind(request.member_user_id)
    .bind(&expected_digest)
    .bind(owner_fingerprint.as_slice())
    .bind(member_fingerprint.as_slice())
    .execute(&mut *tx)
    .await?;
    if auth.user_id == owner_user_id {
        query::<Postgres>(
            "UPDATE tenant_members SET owner_confirmed_at = now(),
                 safety_number_digest = $3,
                 safety_owner_root_fingerprint = $4,
                 safety_member_root_fingerprint = $5
             WHERE tenant_id = $1 AND user_id = $2",
        )
        .bind(tenant_id)
        .bind(request.member_user_id)
        .bind(&expected_digest)
        .bind(owner_fingerprint.as_slice())
        .bind(member_fingerprint.as_slice())
        .execute(&mut *tx)
        .await?;
    } else {
        query::<Postgres>(
            "UPDATE tenant_members SET member_confirmed_at = now(),
                 safety_number_digest = $3,
                 safety_owner_root_fingerprint = $4,
                 safety_member_root_fingerprint = $5
             WHERE tenant_id = $1 AND user_id = $2",
        )
        .bind(tenant_id)
        .bind(request.member_user_id)
        .bind(&expected_digest)
        .bind(owner_fingerprint.as_slice())
        .bind(member_fingerprint.as_slice())
        .execute(&mut *tx)
        .await?;
    }
    query::<Postgres>(
        "UPDATE tenant_members
         SET verification_state = 'verified', verified_at = now()
         WHERE tenant_id = $1 AND user_id = $2
           AND owner_confirmed_at IS NOT NULL AND member_confirmed_at IS NOT NULL
           AND safety_number_digest = $3
           AND safety_owner_root_fingerprint = $4
           AND safety_member_root_fingerprint = $5",
    )
    .bind(tenant_id)
    .bind(request.member_user_id)
    .bind(&expected_digest)
    .bind(owner_fingerprint.as_slice())
    .bind(member_fingerprint.as_slice())
    .execute(&mut *tx)
    .await?;
    let response =
        load_safety_response(&mut tx, tenant_id, owner_user_id, request.member_user_id).await?;
    tx.commit().await?;
    Ok(response)
}

pub async fn list_member_devices(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    member_user_id: Uuid,
) -> Result<OrganizationDeviceRosterDto, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    require_membership(&mut tx, tenant_id, auth.user_id).await?;
    require_membership(&mut tx, tenant_id, member_user_id).await?;
    let root_row = query::<Postgres>(
        "SELECT account_root_public, device_roster_revision FROM users WHERE id = $1",
    )
    .bind(member_user_id)
    .fetch_one(&mut *tx)
    .await?;
    let root: Vec<u8> = root_row.try_get("account_root_public")?;
    let roster_revision: i64 = root_row.try_get("device_roster_revision")?;
    AccountRootPublicKeys::decode(&root).map_err(|_| AppError::internal())?;
    let rows = query::<Postgres>(
        "SELECT id, certificate, certificate_fingerprint, revoked_at IS NOT NULL AS revoked
         FROM devices WHERE user_id = $1 AND certificate IS NOT NULL
           AND revoked_at IS NULL AND (key_expires_at IS NULL OR key_expires_at > now())
         ORDER BY created_at, id",
    )
    .bind(member_user_id)
    .fetch_all(&mut *tx)
    .await?;
    let mut result = Vec::with_capacity(rows.len());
    for row in rows {
        let certificate: Vec<u8> = row.try_get("certificate")?;
        DeviceCertificate::decode(&certificate).map_err(|_| AppError::internal())?;
        result.push(OrganizationDeviceDto {
            user_id: member_user_id,
            device_id: row.try_get("id")?,
            account_root_public: STANDARD.encode(&root),
            certificate: STANDARD.encode(certificate),
            certificate_fingerprint: STANDARD
                .encode(row.try_get::<Vec<u8>, _>("certificate_fingerprint")?),
            revoked: row.try_get("revoked")?,
        });
    }
    let revocation_rows = query::<Postgres>(
        "SELECT signed_revocation FROM devices
         WHERE user_id = $1 AND signed_revocation IS NOT NULL
         ORDER BY revocation_revision",
    )
    .bind(member_user_id)
    .fetch_all(&mut *tx)
    .await?;
    let signed_revocations = revocation_rows
        .into_iter()
        .map(|row| {
            row.try_get::<Vec<u8>, _>("signed_revocation")
                .map(|value| STANDARD.encode(value))
        })
        .collect::<Result<Vec<_>, _>>()?;
    tx.commit().await?;
    Ok(OrganizationDeviceRosterDto {
        user_id: member_user_id,
        account_root_public: STANDARD.encode(root),
        revision: u64::try_from(roster_revision).map_err(|_| AppError::internal())?,
        devices: result,
        signed_revocations,
    })
}

pub async fn store_recipient_package(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    scope_kind: i16,
    scope_id: Uuid,
    generation: u64,
    request: RecipientPackageRequest,
) -> Result<RecipientPackageResponse, AppError> {
    let package_bytes = STANDARD
        .decode(&request.package)
        .map_err(|_| AppError::bad_request("invalid recipient package"))?;
    let package = HybridDekPackage::decode(&package_bytes)
        .map_err(|_| AppError::bad_request("invalid recipient package"))?;
    validate_package_scope(&package, tenant_id, scope_kind, scope_id, generation)?;
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    require_org_admin(&mut tx, tenant_id, auth.user_id).await?;
    require_generation(&mut tx, tenant_id, scope_kind, scope_id, generation).await?;
    let sender_fingerprint: Vec<u8> = query::<Postgres>(
        "SELECT certificate_fingerprint FROM devices
         WHERE id = $1 AND user_id = $2 AND certificate IS NOT NULL
           AND revoked_at IS NULL AND (key_expires_at IS NULL OR key_expires_at > now())",
    )
    .bind(auth.device_id)
    .bind(auth.user_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(AppError::forbidden)?
    .try_get("certificate_fingerprint")?;
    if sender_fingerprint != package.sender_certificate_fingerprint {
        return Err(AppError::bad_request("sender certificate mismatch"));
    }
    let recipient = query::<Postgres>(
        "SELECT d.certificate, d.certificate_fingerprint, d.user_id
         FROM devices d
         JOIN tenant_members m ON m.user_id = d.user_id AND m.tenant_id = $1
         WHERE d.id = $2 AND d.certificate IS NOT NULL AND d.revoked_at IS NULL
           AND (d.key_expires_at IS NULL OR d.key_expires_at > now())",
    )
    .bind(tenant_id)
    .bind(request.device_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::bad_request("invalid recipient device"))?;
    let recipient_user_id: Uuid = recipient.try_get("user_id")?;
    require_verified_recipient(&mut tx, tenant_id, recipient_user_id).await?;
    let recipient_fingerprint: Vec<u8> = recipient.try_get("certificate_fingerprint")?;
    let recipient_certificate =
        DeviceCertificate::decode(&recipient.try_get::<Vec<u8>, _>("certificate")?)
            .map_err(|_| AppError::internal())?;
    let recipient_key_fingerprint = recipient_certificate
        .recipient_key_fingerprint()
        .map_err(|_| AppError::internal())?;
    if recipient_fingerprint != package.recipient_certificate_fingerprint
        || recipient_key_fingerprint != package.recipient_key_fingerprint
    {
        return Err(AppError::bad_request("recipient certificate mismatch"));
    }
    require_manifest_recipient(
        &mut tx,
        tenant_id,
        scope_kind,
        scope_id,
        generation,
        &recipient_key_fingerprint,
    )
    .await?;
    let list_id = (scope_kind == HybridScopeKind::List as i16).then_some(scope_id);
    let inserted = query::<Postgres>(
        "INSERT INTO key_recipients
            (scope_kind, tenant_id, list_id, generation, device_id,
             recipient_key_fingerprint, wrapped_dek)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT DO NOTHING",
    )
    .bind(scope_kind)
    .bind(tenant_id)
    .bind(list_id)
    .bind(i64::try_from(generation).map_err(|_| AppError::bad_request("invalid generation"))?)
    .bind(request.device_id)
    .bind(recipient_key_fingerprint.as_slice())
    .bind(&package_bytes)
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        let existing: Vec<u8> = query::<Postgres>(
            "SELECT wrapped_dek FROM key_recipients
             WHERE scope_kind = $1 AND tenant_id = $2
               AND list_id IS NOT DISTINCT FROM $3 AND generation = $4 AND device_id = $5",
        )
        .bind(scope_kind)
        .bind(tenant_id)
        .bind(list_id)
        .bind(i64::try_from(generation).map_err(|_| AppError::internal())?)
        .bind(request.device_id)
        .fetch_one(&mut *tx)
        .await?
        .try_get("wrapped_dek")?;
        if existing != package_bytes {
            return Err(AppError::conflict("recipient package changed"));
        }
    }
    tx.commit().await?;
    Ok(RecipientPackageResponse {
        package: request.package,
    })
}

pub async fn load_recipient_package(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    scope_kind: i16,
    scope_id: Uuid,
    generation: u64,
) -> Result<RecipientPackageResponse, AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    require_verified_recipient(&mut tx, tenant_id, auth.user_id).await?;
    let list_id = (scope_kind == HybridScopeKind::List as i16).then_some(scope_id);
    let package_bytes: Vec<u8> = query::<Postgres>(
        "SELECT wrapped_dek FROM key_recipients
         WHERE scope_kind = $1 AND tenant_id = $2
           AND list_id IS NOT DISTINCT FROM $3 AND generation = $4 AND device_id = $5",
    )
    .bind(scope_kind)
    .bind(tenant_id)
    .bind(list_id)
    .bind(i64::try_from(generation).map_err(|_| AppError::bad_request("invalid generation"))?)
    .bind(auth.device_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::not_found("recipient package not found"))?
    .try_get("wrapped_dek")?;
    let package = HybridDekPackage::decode(&package_bytes).map_err(|_| AppError::internal())?;
    validate_package_scope(&package, tenant_id, scope_kind, scope_id, generation)?;
    tx.commit().await?;
    Ok(RecipientPackageResponse {
        package: STANDARD.encode(package_bytes),
    })
}

pub async fn remove_member(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    member_user_id: Uuid,
) -> Result<(), AppError> {
    let mut tx = db::begin_tenant_transaction(pool, tenant_id).await?;
    let owner_user_id = require_org_admin(&mut tx, tenant_id, auth.user_id).await?;
    if member_user_id == owner_user_id {
        return Err(AppError::conflict("organization owner cannot be removed"));
    }
    let deleted =
        query::<Postgres>("DELETE FROM tenant_members WHERE tenant_id = $1 AND user_id = $2")
            .bind(tenant_id)
            .bind(member_user_id)
            .execute(&mut *tx)
            .await?;
    if deleted.rows_affected() != 1 {
        return Err(AppError::not_found("organization member not found"));
    }
    mark_rotation_required(&mut tx, tenant_id).await?;
    tx.commit().await?;
    Ok(())
}

pub async fn revoke_device(
    pool: &PgPool,
    tenant_id: Uuid,
    auth: AuthContext,
    device_id: Uuid,
    request: OrganizationDeviceRevocationRequest,
) -> Result<(), AppError> {
    let mut tx = pool.begin().await?;
    db::set_user_context(&mut tx, auth.user_id).await?;
    require_membership(&mut tx, tenant_id, auth.user_id).await?;
    let target = query::<Postgres>(
        "SELECT d.user_id, d.certificate_fingerprint, d.revoked_at,
                u.account_root_public, u.device_roster_revision,
                (SELECT previous.signed_revocation FROM devices previous
                 WHERE previous.user_id = d.user_id
                   AND previous.revocation_revision = u.device_roster_revision)
                    AS previous_signed_revocation
         FROM devices d
         JOIN users u ON u.id = d.user_id
         JOIN tenant_members m ON m.user_id = d.user_id AND m.tenant_id = $1
         WHERE d.id = $2",
    )
    .bind(tenant_id)
    .bind(device_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::not_found("device not found"))?;
    let target_user_id: Uuid = target.try_get("user_id")?;
    if target_user_id != auth.user_id {
        return Err(AppError::forbidden());
    }
    if target
        .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("revoked_at")?
        .is_some()
    {
        return Err(AppError::conflict("device is already revoked"));
    }
    let root_bytes: Vec<u8> = target.try_get("account_root_public")?;
    let root = AccountRootPublicKeys::decode(&root_bytes)
        .map_err(|_| AppError::bad_request("invalid account root"))?;
    let statement_bytes = STANDARD
        .decode(&request.signed_revocation)
        .map_err(|_| AppError::bad_request("invalid device revocation"))?;
    let statement = SignedDeviceRevocation::decode(&statement_bytes)
        .map_err(|_| AppError::bad_request("invalid device revocation"))?;
    statement
        .verify(&root)
        .map_err(|_| AppError::bad_request("invalid device revocation"))?;
    let certificate_fingerprint: Vec<u8> = target.try_get("certificate_fingerprint")?;
    let roster_revision: i64 = target.try_get("device_roster_revision")?;
    let previous_statement_hash =
        match target.try_get::<Option<Vec<u8>>, _>("previous_signed_revocation")? {
            Some(bytes) => SignedDeviceRevocation::decode(&bytes)
                .and_then(|previous| previous.authenticated_hash())
                .map_err(|_| AppError::internal())?,
            None if roster_revision == 0 => [0; 32],
            None => return Err(AppError::internal()),
        };
    let next_revision = roster_revision
        .checked_add(1)
        .ok_or_else(AppError::internal)?;
    if statement.user_id != target_user_id
        || statement.device_id != device_id
        || statement.certificate_fingerprint.as_slice() != certificate_fingerprint
        || statement.revision != u64::try_from(next_revision).map_err(|_| AppError::internal())?
        || statement.previous_statement_hash != previous_statement_hash
    {
        return Err(AppError::conflict("device revocation revision mismatch"));
    }
    let updated = query::<Postgres>(
        "UPDATE users SET device_roster_revision = $2
         WHERE id = $1 AND device_roster_revision = $3",
    )
    .bind(target_user_id)
    .bind(next_revision)
    .bind(roster_revision)
    .execute(&mut *tx)
    .await?;
    if updated.rows_affected() != 1 {
        return Err(AppError::conflict("device roster changed"));
    }
    query::<Postgres>(
        "UPDATE devices
         SET revoked_at = now(), revocation_revision = $2, signed_revocation = $3
         WHERE id = $1 AND revoked_at IS NULL",
    )
    .bind(device_id)
    .bind(next_revision)
    .bind(&statement_bytes)
    .execute(&mut *tx)
    .await?;
    query::<Postgres>(
        "UPDATE sessions SET revoked_at = coalesce(revoked_at, now()) WHERE device_id = $1",
    )
    .bind(device_id)
    .execute(&mut *tx)
    .await?;
    mark_all_organization_rotations_required(&mut tx, target_user_id).await?;
    tx.commit().await?;
    Ok(())
}

async fn mark_all_organization_rotations_required(
    tx: &mut PgTransaction<'_>,
    user_id: Uuid,
) -> Result<(), AppError> {
    let tenant_rows = query::<Postgres>(
        "SELECT tenant_id FROM tenant_members WHERE user_id = $1 ORDER BY tenant_id",
    )
    .bind(user_id)
    .fetch_all(&mut **tx)
    .await?;
    for row in tenant_rows {
        let tenant_id: Uuid = row.try_get("tenant_id")?;
        db::set_tenant_context(tx, tenant_id).await?;
        mark_rotation_required(tx, tenant_id).await?;
    }
    Ok(())
}

async fn mark_rotation_required(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
) -> Result<(), AppError> {
    query::<Postgres>("UPDATE tenants SET rotation_required = TRUE WHERE id = $1 AND kind = 'org'")
        .bind(tenant_id)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

async fn require_manifest_recipient(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    scope_kind: i16,
    scope_id: Uuid,
    generation: u64,
    recipient_key_fingerprint: &[u8; 32],
) -> Result<(), AppError> {
    let list_id = (scope_kind == HybridScopeKind::List as i16).then_some(scope_id);
    let row = if let Some(list_id) = list_id {
        query::<Postgres>(
            "SELECT g.signed_manifest, u.account_root_public
             FROM list_key_generations g JOIN tenants t ON t.id = g.tenant_id
             JOIN users u ON u.id = t.owner_user_id
             WHERE g.tenant_id = $1 AND g.list_id = $2 AND g.generation = $3",
        )
        .bind(tenant_id)
        .bind(list_id)
        .bind(i64::try_from(generation).map_err(|_| AppError::internal())?)
        .fetch_one(&mut **tx)
        .await?
    } else {
        query::<Postgres>(
            "SELECT g.signed_manifest, u.account_root_public
             FROM tenant_key_generations g JOIN tenants t ON t.id = g.tenant_id
             JOIN users u ON u.id = t.owner_user_id
             WHERE g.tenant_id = $1 AND g.generation = $2",
        )
        .bind(tenant_id)
        .bind(i64::try_from(generation).map_err(|_| AppError::internal())?)
        .fetch_one(&mut **tx)
        .await?
    };
    let root = AccountRootPublicKeys::decode(&row.try_get::<Vec<u8>, _>("account_root_public")?)
        .map_err(|_| AppError::internal())?;
    let signed = OrganizationKeyManifest::decode(&row.try_get::<Vec<u8>, _>("signed_manifest")?)
        .map_err(|_| AppError::bad_request("invalid key manifest"))?;
    signed
        .verify(&root)
        .map_err(|_| AppError::bad_request("invalid key manifest"))?;
    if signed.manifest.tenant_id != tenant_id
        || signed.manifest.list_id != list_id
        || signed.manifest.generation != generation
        || signed
            .manifest
            .recipient_fingerprints
            .binary_search(recipient_key_fingerprint)
            .is_err()
    {
        return Err(AppError::bad_request("recipient is not in signed manifest"));
    }
    Ok(())
}

async fn load_safety_response(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    owner_user_id: Uuid,
    member_user_id: Uuid,
) -> Result<OrganizationSafetyResponse, AppError> {
    let roots = query::<Postgres>(
        "SELECT
            (SELECT account_root_public FROM users WHERE id = $1) AS owner_root,
            (SELECT account_root_public FROM users WHERE id = $2) AS member_root",
    )
    .bind(owner_user_id)
    .bind(member_user_id)
    .fetch_one(&mut **tx)
    .await?;
    let owner_bytes: Vec<u8> = roots.try_get("owner_root")?;
    let member_bytes: Vec<u8> = roots.try_get("member_root")?;
    let owner_root =
        AccountRootPublicKeys::decode(&owner_bytes).map_err(|_| AppError::internal())?;
    let member_root =
        AccountRootPublicKeys::decode(&member_bytes).map_err(|_| AppError::internal())?;
    if owner_root.user_id != owner_user_id || member_root.user_id != member_user_id {
        return Err(AppError::internal());
    }
    let safety =
        derive_safety_number(&owner_root, &member_root).map_err(|_| AppError::internal())?;
    let membership = query::<Postgres>(
        "SELECT verification_state, owner_confirmed_at IS NOT NULL AS owner_confirmed,
                member_confirmed_at IS NOT NULL AS member_confirmed,
                safety_owner_root_fingerprint, safety_member_root_fingerprint
         FROM tenant_members WHERE tenant_id = $1 AND user_id = $2",
    )
    .bind(tenant_id)
    .bind(member_user_id)
    .fetch_one(&mut **tx)
    .await?;
    let owner_fingerprint = owner_root.fingerprint().map_err(|_| AppError::internal())?;
    let member_fingerprint = member_root
        .fingerprint()
        .map_err(|_| AppError::internal())?;
    let fingerprints_current = membership
        .try_get::<Option<Vec<u8>>, _>("safety_owner_root_fingerprint")?
        .is_some_and(|value| value == owner_fingerprint)
        && membership
            .try_get::<Option<Vec<u8>>, _>("safety_member_root_fingerprint")?
            .is_some_and(|value| value == member_fingerprint);
    Ok(OrganizationSafetyResponse {
        owner_user_id,
        member_user_id,
        owner_root_public: STANDARD.encode(owner_bytes),
        member_root_public: STANDARD.encode(member_bytes),
        digest: STANDARD.encode(safety.digest),
        decimal: safety.decimal,
        qr_payload: STANDARD.encode(safety.qr_payload),
        verification_state: if fingerprints_current {
            membership.try_get("verification_state")?
        } else {
            "unverified".to_string()
        },
        owner_confirmed: fingerprints_current && membership.try_get("owner_confirmed")?,
        member_confirmed: fingerprints_current && membership.try_get("member_confirmed")?,
    })
}

async fn require_org_admin(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    user_id: Uuid,
) -> Result<Uuid, AppError> {
    let row = query::<Postgres>(
        "SELECT t.owner_user_id, t.kind, m.role
         FROM tenants t JOIN tenant_members m ON m.tenant_id = t.id
         WHERE t.id = $1 AND m.user_id = $2",
    )
    .bind(tenant_id)
    .bind(user_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(AppError::forbidden)?;
    let kind: String = row.try_get("kind")?;
    let role: String = row.try_get("role")?;
    if kind != "org" || (role != "owner" && role != "admin") {
        return Err(AppError::forbidden());
    }
    row.try_get("owner_user_id").map_err(AppError::from)
}

async fn require_membership(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let exists: bool = query::<Postgres>(
        "SELECT EXISTS (SELECT 1 FROM tenant_members WHERE tenant_id = $1 AND user_id = $2) AS e",
    )
    .bind(tenant_id)
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await?
    .try_get("e")?;
    if !exists {
        return Err(AppError::forbidden());
    }
    Ok(())
}

async fn require_safety_participant(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    actor_user_id: Uuid,
    member_user_id: Uuid,
) -> Result<Uuid, AppError> {
    let owner_user_id: Uuid =
        query::<Postgres>("SELECT owner_user_id FROM tenants WHERE id = $1 AND kind = 'org'")
            .bind(tenant_id)
            .fetch_optional(&mut **tx)
            .await?
            .ok_or_else(AppError::forbidden)?
            .try_get("owner_user_id")?;
    require_membership(tx, tenant_id, member_user_id).await?;
    if actor_user_id != owner_user_id && actor_user_id != member_user_id {
        return Err(AppError::forbidden());
    }
    Ok(owner_user_id)
}

async fn require_verified_recipient(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let row = query::<Postgres>(
        "SELECT t.owner_user_id, m.verification_state,
                m.safety_owner_root_fingerprint, m.safety_member_root_fingerprint,
                owner.account_root_public AS owner_root,
                member.account_root_public AS member_root
         FROM tenants t
         JOIN tenant_members m ON m.tenant_id = t.id AND m.user_id = $2
         JOIN users owner ON owner.id = t.owner_user_id
         JOIN users member ON member.id = m.user_id
         WHERE t.id = $1 AND t.kind = 'org'",
    )
    .bind(tenant_id)
    .bind(user_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(AppError::forbidden)?;
    let owner_user_id: Uuid = row.try_get("owner_user_id")?;
    if user_id == owner_user_id {
        return Ok(());
    }
    if row.try_get::<String, _>("verification_state")? != "verified" {
        return Err(AppError::forbidden());
    }
    let owner = AccountRootPublicKeys::decode(&row.try_get::<Vec<u8>, _>("owner_root")?)
        .map_err(|_| AppError::internal())?;
    let member = AccountRootPublicKeys::decode(&row.try_get::<Vec<u8>, _>("member_root")?)
        .map_err(|_| AppError::internal())?;
    if row.try_get::<Option<Vec<u8>>, _>("safety_owner_root_fingerprint")?
        != Some(
            owner
                .fingerprint()
                .map_err(|_| AppError::internal())?
                .to_vec(),
        )
        || row.try_get::<Option<Vec<u8>>, _>("safety_member_root_fingerprint")?
            != Some(
                member
                    .fingerprint()
                    .map_err(|_| AppError::internal())?
                    .to_vec(),
            )
    {
        return Err(AppError::forbidden());
    }
    Ok(())
}

async fn require_generation(
    tx: &mut PgTransaction<'_>,
    tenant_id: Uuid,
    scope_kind: i16,
    scope_id: Uuid,
    generation: u64,
) -> Result<(), AppError> {
    let generation =
        i64::try_from(generation).map_err(|_| AppError::bad_request("invalid generation"))?;
    let exists = match scope_kind {
        1 if scope_id == tenant_id => query::<Postgres>(
            "SELECT EXISTS (SELECT 1 FROM tenant_key_generations
             WHERE tenant_id = $1 AND generation = $2 AND status IN ('prepared', 'active')) AS e",
        )
        .bind(tenant_id)
        .bind(generation)
        .fetch_one(&mut **tx)
        .await?
        .try_get::<bool, _>("e")?,
        2 => query::<Postgres>(
            "SELECT EXISTS (SELECT 1 FROM list_key_generations
             WHERE tenant_id = $1 AND list_id = $2 AND generation = $3
               AND status IN ('prepared', 'active')) AS e",
        )
        .bind(tenant_id)
        .bind(scope_id)
        .bind(generation)
        .fetch_one(&mut **tx)
        .await?
        .try_get::<bool, _>("e")?,
        _ => false,
    };
    if !exists {
        return Err(AppError::conflict("key generation is not deliverable"));
    }
    Ok(())
}

fn validate_package_scope(
    package: &HybridDekPackage,
    tenant_id: Uuid,
    scope_kind: i16,
    scope_id: Uuid,
    generation: u64,
) -> Result<(), AppError> {
    let expected_kind = match scope_kind {
        1 => HybridScopeKind::Tenant,
        2 => HybridScopeKind::List,
        _ => return Err(AppError::bad_request("invalid recipient scope")),
    };
    if package.scope_kind != expected_kind
        || package.scope_id != scope_id
        || package.generation != generation
        || (expected_kind == HybridScopeKind::Tenant && scope_id != tenant_id)
    {
        return Err(AppError::bad_request("recipient scope mismatch"));
    }
    Ok(())
}
