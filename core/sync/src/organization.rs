//! Organization verification and per-device recipient wire contracts.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use todori_crypto::organization::{
    sign_account_root_payload, verify_account_root_payload, AccountRootPrivateKeys,
    AccountRootPublicKeys, AccountRootSignature, OrganizationCryptoError, ED25519_SIGNATURE_LEN,
    ML_DSA_65_SIGNATURE_LEN, ROOT_FINGERPRINT_LEN,
};
use uuid::Uuid;

use crate::{account::ActiveKeyBundleDto, KeyScope, RotationStatus};
use crate::{KeyManifest, KeyManifestError};

const ORGANIZATION_MANIFEST_MAGIC: &[u8; 4] = b"TOM1";
const ORGANIZATION_MANIFEST_DOMAIN: &[u8] = b"todori/organization-key-manifest/v1";

#[derive(Debug, thiserror::Error)]
pub enum OrganizationManifestError {
    #[error("invalid organization manifest encoding")]
    InvalidEncoding,
    #[error("key manifest error")]
    KeyManifest(#[from] KeyManifestError),
    #[error("organization signature error")]
    Signature(#[from] OrganizationCryptoError),
}

#[derive(Debug, thiserror::Error)]
pub enum OrganizationBundleError {
    #[error("invalid organization bundle encoding")]
    InvalidEncoding,
    #[error("organization bundle generation was replayed")]
    GenerationReplay,
    #[error("organization manifest error")]
    Manifest(#[from] OrganizationManifestError),
}

pub fn verify_organization_active_bundle(
    bundle: &ActiveKeyBundleDto,
    tenant_id: Uuid,
    minimum_generation: u64,
    owner_root: &AccountRootPublicKeys,
    recipient_certificate: &todori_crypto::organization::DeviceCertificate,
    expected_recipient_fingerprints: &[[u8; 32]],
) -> Result<(), OrganizationBundleError> {
    if bundle.suite_id != todori_crypto::CRYPTO_SUITE_ID
        || bundle.generation == 0
        || bundle.generation < minimum_generation
        || !bundle.wrapped_tenant_root_dek.is_empty()
    {
        return if bundle.generation < minimum_generation {
            Err(OrganizationBundleError::GenerationReplay)
        } else {
            Err(OrganizationBundleError::InvalidEncoding)
        };
    }
    let recipient_fingerprint = recipient_certificate
        .recipient_key_fingerprint()
        .map_err(OrganizationManifestError::Signature)?;
    let mut expected_recipients = expected_recipient_fingerprints.to_vec();
    expected_recipients.sort_unstable();
    let original_len = expected_recipients.len();
    expected_recipients.dedup();
    if expected_recipients.is_empty() || expected_recipients.len() != original_len {
        return Err(OrganizationBundleError::InvalidEncoding);
    }
    verify_active_manifest(
        &bundle.signed_manifest,
        owner_root,
        KeyScope::Tenant,
        tenant_id,
        None,
        bundle.generation,
        recipient_fingerprint,
        &expected_recipients,
    )?;
    for list in &bundle.list_deks {
        if list.generation != bundle.generation || !list.wrapped_list_dek.is_empty() {
            return Err(OrganizationBundleError::InvalidEncoding);
        }
        verify_active_manifest(
            &list.signed_manifest,
            owner_root,
            KeyScope::List,
            tenant_id,
            Some(list.list_id),
            bundle.generation,
            recipient_fingerprint,
            &expected_recipients,
        )?;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn verify_active_manifest(
    encoded: &str,
    owner_root: &AccountRootPublicKeys,
    scope: KeyScope,
    tenant_id: Uuid,
    list_id: Option<Uuid>,
    generation: u64,
    recipient_fingerprint: [u8; 32],
    expected_recipients: &[[u8; 32]],
) -> Result<(), OrganizationBundleError> {
    let bytes = STANDARD
        .decode(encoded)
        .map_err(|_| OrganizationBundleError::InvalidEncoding)?;
    let signed = OrganizationKeyManifest::decode(&bytes)?;
    signed.verify(owner_root)?;
    if signed.manifest.scope != scope
        || signed.manifest.tenant_id != tenant_id
        || signed.manifest.list_id != list_id
        || signed.manifest.generation != generation
        || signed.manifest.status != RotationStatus::Active
        || signed.manifest.minimum_write_generation != generation
        || signed
            .manifest
            .recipient_fingerprints
            .binary_search(&recipient_fingerprint)
            .is_err()
        || signed.manifest.recipient_fingerprints != expected_recipients
    {
        return Err(OrganizationBundleError::InvalidEncoding);
    }
    Ok(())
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OrganizationKeyManifest {
    pub manifest: KeyManifest,
    pub root_fingerprint: [u8; ROOT_FINGERPRINT_LEN],
    pub signature: AccountRootSignature,
}

impl OrganizationKeyManifest {
    pub fn sign(
        manifest: KeyManifest,
        root_private: &AccountRootPrivateKeys,
        root_public: &AccountRootPublicKeys,
    ) -> Result<Self, OrganizationManifestError> {
        if manifest.authenticator != [0u8; 32] {
            return Err(OrganizationManifestError::InvalidEncoding);
        }
        let root_fingerprint = root_public.fingerprint()?;
        let transcript = manifest_transcript(&manifest, &root_fingerprint)?;
        let signature = sign_account_root_payload(root_private, root_public, &transcript)?;
        Ok(Self {
            manifest,
            root_fingerprint,
            signature,
        })
    }

    pub fn verify(
        &self,
        root_public: &AccountRootPublicKeys,
    ) -> Result<(), OrganizationManifestError> {
        if self.manifest.authenticator != [0u8; 32]
            || self.root_fingerprint != root_public.fingerprint()?
        {
            return Err(OrganizationManifestError::InvalidEncoding);
        }
        verify_account_root_payload(
            root_public,
            &manifest_transcript(&self.manifest, &self.root_fingerprint)?,
            &self.signature,
        )?;
        Ok(())
    }

    pub fn encode(&self) -> Result<Vec<u8>, OrganizationManifestError> {
        if self.signature.ml_dsa_65_signature.len() != ML_DSA_65_SIGNATURE_LEN {
            return Err(OrganizationManifestError::InvalidEncoding);
        }
        let payload = self.manifest.canonical_payload()?;
        let mut output = Vec::with_capacity(
            4 + 4
                + payload.len()
                + ROOT_FINGERPRINT_LEN
                + ED25519_SIGNATURE_LEN
                + ML_DSA_65_SIGNATURE_LEN,
        );
        output.extend_from_slice(ORGANIZATION_MANIFEST_MAGIC);
        output.extend_from_slice(
            &u32::try_from(payload.len())
                .map_err(|_| OrganizationManifestError::InvalidEncoding)?
                .to_be_bytes(),
        );
        output.extend_from_slice(&payload);
        output.extend_from_slice(&self.root_fingerprint);
        output.extend_from_slice(&self.signature.ed25519_signature);
        output.extend_from_slice(&self.signature.ml_dsa_65_signature);
        Ok(output)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, OrganizationManifestError> {
        const TRAILER: usize =
            ROOT_FINGERPRINT_LEN + ED25519_SIGNATURE_LEN + ML_DSA_65_SIGNATURE_LEN;
        if bytes.len() <= 8 + TRAILER || &bytes[..4] != ORGANIZATION_MANIFEST_MAGIC {
            return Err(OrganizationManifestError::InvalidEncoding);
        }
        let payload_len = usize::try_from(u32::from_be_bytes(
            bytes[4..8]
                .try_into()
                .map_err(|_| OrganizationManifestError::InvalidEncoding)?,
        ))
        .map_err(|_| OrganizationManifestError::InvalidEncoding)?;
        let payload_end = 8usize
            .checked_add(payload_len)
            .ok_or(OrganizationManifestError::InvalidEncoding)?;
        if bytes.len() != payload_end + TRAILER {
            return Err(OrganizationManifestError::InvalidEncoding);
        }
        let mut personal_shape = bytes[8..payload_end].to_vec();
        personal_shape.extend_from_slice(&[0u8; 32]);
        let manifest = KeyManifest::from_authenticated_bytes(&personal_shape)?;
        if manifest.authenticator != [0u8; 32] {
            return Err(OrganizationManifestError::InvalidEncoding);
        }
        let root_end = payload_end + ROOT_FINGERPRINT_LEN;
        let ed_end = root_end + ED25519_SIGNATURE_LEN;
        Ok(Self {
            manifest,
            root_fingerprint: bytes[payload_end..root_end]
                .try_into()
                .map_err(|_| OrganizationManifestError::InvalidEncoding)?,
            signature: AccountRootSignature {
                ed25519_signature: bytes[root_end..ed_end]
                    .try_into()
                    .map_err(|_| OrganizationManifestError::InvalidEncoding)?,
                ml_dsa_65_signature: bytes[ed_end..].to_vec(),
            },
        })
    }

    pub fn authenticated_hash(&self) -> Result<[u8; 32], OrganizationManifestError> {
        Ok(Sha256::digest(self.encode()?).into())
    }
}

fn manifest_transcript(
    manifest: &KeyManifest,
    root_fingerprint: &[u8; ROOT_FINGERPRINT_LEN],
) -> Result<Vec<u8>, OrganizationManifestError> {
    let payload = manifest.canonical_payload()?;
    let mut output = Vec::with_capacity(
        ORGANIZATION_MANIFEST_DOMAIN.len() + ROOT_FINGERPRINT_LEN + 4 + payload.len(),
    );
    output.extend_from_slice(ORGANIZATION_MANIFEST_DOMAIN);
    output.extend_from_slice(root_fingerprint);
    output.extend_from_slice(
        &u32::try_from(payload.len())
            .map_err(|_| OrganizationManifestError::InvalidEncoding)?
            .to_be_bytes(),
    );
    output.extend_from_slice(&payload);
    Ok(output)
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct OrganizationInviteRequest {
    pub email: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct OrganizationMemberResponse {
    pub member_user_id: Uuid,
    pub verification_state: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct OrganizationSafetyResponse {
    pub owner_user_id: Uuid,
    pub member_user_id: Uuid,
    pub owner_root_public: String,
    pub member_root_public: String,
    pub digest: String,
    pub decimal: String,
    pub qr_payload: String,
    pub verification_state: String,
    pub owner_confirmed: bool,
    pub member_confirmed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct OrganizationSafetyConfirmRequest {
    pub member_user_id: Uuid,
    pub digest: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct OrganizationDeviceDto {
    pub user_id: Uuid,
    pub device_id: Uuid,
    pub account_root_public: String,
    pub certificate: String,
    pub certificate_fingerprint: String,
    pub revoked: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct OrganizationDeviceRosterDto {
    pub user_id: Uuid,
    pub account_root_public: String,
    pub revision: u64,
    pub devices: Vec<OrganizationDeviceDto>,
    pub signed_revocations: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct OrganizationDeviceRevocationRequest {
    pub signed_revocation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct RecipientPackageRequest {
    pub device_id: Uuid,
    pub package: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct RecipientPackageResponse {
    pub package: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use todori_crypto::organization::{
        generate_account_root, generate_device_keys, issue_device_certificate,
    };

    #[test]
    fn organization_manifest_rejects_recipient_addition_generation_replay_and_root_substitution() {
        let tenant_id = Uuid::now_v7();
        let root = generate_account_root(Uuid::now_v7()).unwrap();
        let manifest = KeyManifest::organization_unsigned(
            KeyScope::Tenant,
            tenant_id,
            None,
            3,
            RotationStatus::Active,
            3,
            [0x11; 32],
            vec![[0x22; 32]],
        )
        .unwrap();
        let signed = OrganizationKeyManifest::sign(manifest, &root.private, &root.public).unwrap();
        let decoded = OrganizationKeyManifest::decode(&signed.encode().unwrap()).unwrap();
        decoded.verify(&root.public).unwrap();

        let mut recipient_added = decoded.clone();
        recipient_added
            .manifest
            .recipient_fingerprints
            .push([0x33; 32]);
        assert!(recipient_added.verify(&root.public).is_err());

        let mut replayed_generation = decoded.clone();
        replayed_generation.manifest.generation = 4;
        replayed_generation.manifest.minimum_write_generation = 4;
        assert!(replayed_generation.verify(&root.public).is_err());

        let substituted_root = generate_account_root(root.public.user_id).unwrap();
        assert!(decoded.verify(&substituted_root.public).is_err());
    }

    #[test]
    fn active_bundle_requires_current_generation_signature_and_recipient_membership() {
        let tenant_id = Uuid::now_v7();
        let user_id = Uuid::now_v7();
        let root = generate_account_root(user_id).unwrap();
        let device = generate_device_keys().unwrap();
        let certificate = issue_device_certificate(
            &root.private,
            &root.public,
            Uuid::now_v7(),
            &device,
            1_000,
            10_000,
        )
        .unwrap();
        let recipient = certificate.recipient_key_fingerprint().unwrap();
        let manifest = KeyManifest::organization_unsigned(
            KeyScope::Tenant,
            tenant_id,
            None,
            3,
            RotationStatus::Active,
            3,
            [0x11; 32],
            vec![recipient],
        )
        .unwrap();
        let signed = OrganizationKeyManifest::sign(manifest, &root.private, &root.public).unwrap();
        let bundle = ActiveKeyBundleDto {
            suite_id: todori_crypto::CRYPTO_SUITE_ID,
            generation: 3,
            wrapped_tenant_root_dek: String::new(),
            signed_manifest: STANDARD.encode(signed.encode().unwrap()),
            list_deks: Vec::new(),
            migrating_generations: Vec::new(),
        };
        verify_organization_active_bundle(
            &bundle,
            tenant_id,
            3,
            &root.public,
            &certificate,
            &[recipient],
        )
        .unwrap();
        assert!(matches!(
            verify_organization_active_bundle(
                &bundle,
                tenant_id,
                3,
                &root.public,
                &certificate,
                &[recipient, [0x99; 32]],
            ),
            Err(OrganizationBundleError::InvalidEncoding)
        ));
        assert!(matches!(
            verify_organization_active_bundle(
                &bundle,
                tenant_id,
                4,
                &root.public,
                &certificate,
                &[recipient],
            ),
            Err(OrganizationBundleError::GenerationReplay)
        ));

        let outsider = generate_device_keys().unwrap();
        let outsider_certificate = issue_device_certificate(
            &root.private,
            &root.public,
            Uuid::now_v7(),
            &outsider,
            1_000,
            10_000,
        )
        .unwrap();
        assert!(matches!(
            verify_organization_active_bundle(
                &bundle,
                tenant_id,
                3,
                &root.public,
                &outsider_certificate,
                &[recipient],
            ),
            Err(OrganizationBundleError::InvalidEncoding)
        ));
    }
}
