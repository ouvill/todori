//! Organization identity, device-certificate, Safety number, and hybrid PQC primitives.
//!
//! The wire encodings in this module are deliberately canonical and versioned.
//! Unknown suites, trailing bytes, partial hybrid signatures, and mismatched
//! certificate/private-key pairs are rejected rather than downgraded.

use aws_lc_rs::{
    kem::{Ciphertext, DecapsulationKey, EncapsulationKey, ML_KEM_768},
    signature::{Ed25519KeyPair, KeyPair, UnparsedPublicKey, ED25519},
    unstable::signature::{PqdsaKeyPair, ML_DSA_65, ML_DSA_65_SIGNING},
};
use hkdf::Hkdf;
use rand::{rngs::OsRng, RngCore};
use sha2::{Digest, Sha256, Sha384};
use thiserror::Error;
use uuid::Uuid;
use x25519_dalek::{PublicKey as X25519PublicKey, StaticSecret};
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::{decrypt, encrypt, CRYPTO_SUITE_ID};

const ROOT_PUBLIC_MAGIC: &[u8; 4] = b"TRP1";
const DEVICE_CERT_MAGIC: &[u8; 4] = b"TDC1";
const DEVICE_PROOF_MAGIC: &[u8; 4] = b"TDP1";
const DEVICE_IDENTITY_MAGIC: &[u8; 4] = b"TDI1";
const DEVICE_REVOCATION_MAGIC: &[u8; 4] = b"TDR1";
const HYBRID_PACKAGE_MAGIC: &[u8; 4] = b"THP1";
const HYBRID_TRANSCRIPT_MAGIC: &[u8] = b"todori-hybrid-dek-wrap-v1";
const HYBRID_WRAP_INFO: &[u8] = b"todori/hybrid-dek-wrap-key/v1";
const SAFETY_NUMBER_MAGIC: &[u8] = b"todori-safety-number-v1";
const RECIPIENT_KEY_FINGERPRINT_MAGIC: &[u8] = b"todori-recipient-key-fingerprint-v1";
const DEVICE_REVOCATION_DOMAIN: &[u8] = b"todori/device-revocation/v1";

pub const ED25519_PUBLIC_KEY_LEN: usize = 32;
pub const ED25519_SIGNATURE_LEN: usize = 64;
pub const ML_DSA_65_PUBLIC_KEY_LEN: usize = 1_952;
pub const ML_DSA_65_SIGNATURE_LEN: usize = 3_309;
pub const ML_KEM_768_PUBLIC_KEY_LEN: usize = 1_184;
pub const ML_KEM_768_PRIVATE_KEY_LEN: usize = 2_400;
pub const ML_KEM_768_CIPHERTEXT_LEN: usize = 1_088;
pub const ROOT_FINGERPRINT_LEN: usize = 48;
pub const DEVICE_FINGERPRINT_LEN: usize = 48;
pub const RECIPIENT_KEY_FINGERPRINT_LEN: usize = 32;
pub const DEVICE_CHALLENGE_LEN: usize = 32;
pub const SAFETY_NUMBER_QR_LEN: usize = 49;
pub const DEK_LEN: usize = 32;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum OrganizationCryptoError {
    #[error("unsupported organization crypto suite")]
    UnsupportedSuite,
    #[error("invalid organization key material")]
    InvalidKey,
    #[error("invalid canonical organization encoding")]
    InvalidEncoding,
    #[error("hybrid signature verification failed")]
    InvalidSignature,
    #[error("device proof-of-possession verification failed")]
    InvalidProof,
    #[error("device certificate is not currently valid")]
    CertificateNotValid,
    #[error("device certificate is revoked")]
    CertificateRevoked,
    #[error("hybrid recipient does not match its certificate")]
    RecipientMismatch,
    #[error("hybrid key agreement failed")]
    HybridAgreement,
    #[error("hybrid DEK authentication failed")]
    Decryption,
}

#[derive(Zeroize, ZeroizeOnDrop)]
pub struct AccountRootPrivateKeys {
    ed25519_seed: [u8; 32],
    ml_dsa_65_seed: [u8; 32],
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccountRootPublicKeys {
    pub suite_id: u16,
    pub user_id: Uuid,
    pub ed25519_public_key: [u8; ED25519_PUBLIC_KEY_LEN],
    pub ml_dsa_65_public_key: Vec<u8>,
}

pub struct AccountRootKeyPair {
    pub private: AccountRootPrivateKeys,
    pub public: AccountRootPublicKeys,
}

#[derive(Zeroize, ZeroizeOnDrop)]
pub struct DevicePrivateKeys {
    signing_seed: [u8; 32],
    x25519_secret_key: [u8; 32],
    ml_kem_768_decapsulation_key: Vec<u8>,
    ml_kem_768_public_key: Vec<u8>,
}

pub struct DeviceKeyPair {
    pub private: DevicePrivateKeys,
    pub signing_public_key: [u8; ED25519_PUBLIC_KEY_LEN],
    pub x25519_public_key: [u8; 32],
    pub ml_kem_768_public_key: Vec<u8>,
}

pub struct DeviceIdentity {
    private: DevicePrivateKeys,
    certificate: DeviceCertificate,
}

impl DeviceIdentity {
    pub fn new(
        private: DevicePrivateKeys,
        certificate: DeviceCertificate,
    ) -> Result<Self, OrganizationCryptoError> {
        ensure_private_matches_certificate(&private, &certificate)?;
        Ok(Self {
            private,
            certificate,
        })
    }

    pub fn private(&self) -> &DevicePrivateKeys {
        &self.private
    }

    pub fn certificate(&self) -> &DeviceCertificate {
        &self.certificate
    }

    pub fn encode(&self) -> Result<Zeroizing<Vec<u8>>, OrganizationCryptoError> {
        ensure_private_matches_certificate(&self.private, &self.certificate)?;
        let private = self.private.encode()?;
        let certificate = self.certificate.encode()?;
        let mut output = Zeroizing::new(Vec::with_capacity(8 + private.len() + certificate.len()));
        output.extend_from_slice(DEVICE_IDENTITY_MAGIC);
        output.extend_from_slice(
            &u32::try_from(private.len())
                .map_err(|_| OrganizationCryptoError::InvalidEncoding)?
                .to_be_bytes(),
        );
        output.extend_from_slice(&private);
        output.extend_from_slice(&certificate);
        Ok(output)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, OrganizationCryptoError> {
        if bytes.len() < 8 || &bytes[..4] != DEVICE_IDENTITY_MAGIC {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let private_len = usize::try_from(u32::from_be_bytes(copy_array(&bytes[4..8])?))
            .map_err(|_| OrganizationCryptoError::InvalidEncoding)?;
        let private_end = 8usize
            .checked_add(private_len)
            .ok_or(OrganizationCryptoError::InvalidEncoding)?;
        if private_end >= bytes.len() {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        Self::new(
            DevicePrivateKeys::decode(&bytes[8..private_end])?,
            DeviceCertificate::decode(&bytes[private_end..])?,
        )
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeviceCertificate {
    pub suite_id: u16,
    pub user_id: Uuid,
    pub device_id: Uuid,
    pub valid_from_ms: i64,
    pub expires_at_ms: i64,
    pub signing_public_key: [u8; ED25519_PUBLIC_KEY_LEN],
    pub x25519_public_key: [u8; 32],
    pub ml_kem_768_public_key: Vec<u8>,
    pub root_ed25519_signature: [u8; ED25519_SIGNATURE_LEN],
    pub root_ml_dsa_65_signature: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeviceProofOfPossession {
    pub certificate_fingerprint: [u8; DEVICE_FINGERPRINT_LEN],
    pub signature: [u8; ED25519_SIGNATURE_LEN],
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccountRootSignature {
    pub ed25519_signature: [u8; ED25519_SIGNATURE_LEN],
    pub ml_dsa_65_signature: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SignedDeviceRevocation {
    pub suite_id: u16,
    pub user_id: Uuid,
    pub device_id: Uuid,
    pub certificate_fingerprint: [u8; DEVICE_FINGERPRINT_LEN],
    pub revision: u64,
    pub issued_at_ms: i64,
    pub previous_statement_hash: [u8; 32],
    pub root_fingerprint: [u8; ROOT_FINGERPRINT_LEN],
    pub signature: AccountRootSignature,
}

impl SignedDeviceRevocation {
    pub fn sign(
        root_private: &AccountRootPrivateKeys,
        root_public: &AccountRootPublicKeys,
        device_id: Uuid,
        certificate_fingerprint: [u8; DEVICE_FINGERPRINT_LEN],
        revision: u64,
        issued_at_ms: i64,
        previous_statement_hash: [u8; 32],
    ) -> Result<Self, OrganizationCryptoError> {
        require_non_nil(device_id)?;
        if revision == 0 || issued_at_ms < 0 {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let root_fingerprint = root_public.fingerprint()?;
        let mut statement = Self {
            suite_id: CRYPTO_SUITE_ID,
            user_id: root_public.user_id,
            device_id,
            certificate_fingerprint,
            revision,
            issued_at_ms,
            previous_statement_hash,
            root_fingerprint,
            signature: AccountRootSignature {
                ed25519_signature: [0; ED25519_SIGNATURE_LEN],
                ml_dsa_65_signature: Vec::new(),
            },
        };
        statement.signature =
            sign_account_root_payload(root_private, root_public, &statement.signed_payload()?)?;
        statement.verify(root_public)?;
        Ok(statement)
    }

    pub fn verify(
        &self,
        root_public: &AccountRootPublicKeys,
    ) -> Result<(), OrganizationCryptoError> {
        if self.suite_id != CRYPTO_SUITE_ID
            || self.user_id != root_public.user_id
            || self.device_id.is_nil()
            || self.revision == 0
            || self.issued_at_ms < 0
            || self.root_fingerprint != root_public.fingerprint()?
            || self.signature.ml_dsa_65_signature.len() != ML_DSA_65_SIGNATURE_LEN
        {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        verify_account_root_payload(root_public, &self.signed_payload()?, &self.signature)
    }

    pub fn encode(&self) -> Result<Vec<u8>, OrganizationCryptoError> {
        if self.signature.ml_dsa_65_signature.len() != ML_DSA_65_SIGNATURE_LEN {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let mut output = self.canonical_fields()?;
        output.extend_from_slice(&self.signature.ed25519_signature);
        output.extend_from_slice(&self.signature.ml_dsa_65_signature);
        Ok(output)
    }

    pub fn authenticated_hash(&self) -> Result<[u8; 32], OrganizationCryptoError> {
        Ok(Sha256::digest(self.encode()?).into())
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, OrganizationCryptoError> {
        const FIELDS_LEN: usize =
            4 + 2 + 16 + 16 + DEVICE_FINGERPRINT_LEN + 8 + 8 + 32 + ROOT_FINGERPRINT_LEN;
        const ENCODED_LEN: usize = FIELDS_LEN + ED25519_SIGNATURE_LEN + ML_DSA_65_SIGNATURE_LEN;
        if bytes.len() != ENCODED_LEN || &bytes[..4] != DEVICE_REVOCATION_MAGIC {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let mut offset = 4;
        let suite_id = u16::from_be_bytes(copy_array(&bytes[offset..offset + 2])?);
        offset += 2;
        let user_id = Uuid::from_bytes(copy_array(&bytes[offset..offset + 16])?);
        offset += 16;
        let device_id = Uuid::from_bytes(copy_array(&bytes[offset..offset + 16])?);
        offset += 16;
        let certificate_fingerprint = copy_array(&bytes[offset..offset + DEVICE_FINGERPRINT_LEN])?;
        offset += DEVICE_FINGERPRINT_LEN;
        let revision = u64::from_be_bytes(copy_array(&bytes[offset..offset + 8])?);
        offset += 8;
        let issued_at_ms = i64::from_be_bytes(copy_array(&bytes[offset..offset + 8])?);
        offset += 8;
        let previous_statement_hash = copy_array(&bytes[offset..offset + 32])?;
        offset += 32;
        let root_fingerprint = copy_array(&bytes[offset..offset + ROOT_FINGERPRINT_LEN])?;
        offset += ROOT_FINGERPRINT_LEN;
        let ed25519_signature = copy_array(&bytes[offset..offset + ED25519_SIGNATURE_LEN])?;
        offset += ED25519_SIGNATURE_LEN;
        let result = Self {
            suite_id,
            user_id,
            device_id,
            certificate_fingerprint,
            revision,
            issued_at_ms,
            previous_statement_hash,
            root_fingerprint,
            signature: AccountRootSignature {
                ed25519_signature,
                ml_dsa_65_signature: bytes[offset..].to_vec(),
            },
        };
        result.canonical_fields()?;
        Ok(result)
    }

    fn canonical_fields(&self) -> Result<Vec<u8>, OrganizationCryptoError> {
        if self.suite_id != CRYPTO_SUITE_ID
            || self.user_id.is_nil()
            || self.device_id.is_nil()
            || self.revision == 0
            || self.issued_at_ms < 0
        {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let mut output = Vec::with_capacity(150);
        output.extend_from_slice(DEVICE_REVOCATION_MAGIC);
        output.extend_from_slice(&self.suite_id.to_be_bytes());
        output.extend_from_slice(self.user_id.as_bytes());
        output.extend_from_slice(self.device_id.as_bytes());
        output.extend_from_slice(&self.certificate_fingerprint);
        output.extend_from_slice(&self.revision.to_be_bytes());
        output.extend_from_slice(&self.issued_at_ms.to_be_bytes());
        output.extend_from_slice(&self.previous_statement_hash);
        output.extend_from_slice(&self.root_fingerprint);
        Ok(output)
    }

    fn signed_payload(&self) -> Result<Vec<u8>, OrganizationCryptoError> {
        let fields = self.canonical_fields()?;
        let mut payload = Vec::with_capacity(DEVICE_REVOCATION_DOMAIN.len() + fields.len());
        payload.extend_from_slice(DEVICE_REVOCATION_DOMAIN);
        payload.extend_from_slice(&fields);
        Ok(payload)
    }
}

pub fn sign_account_root_payload(
    private: &AccountRootPrivateKeys,
    public: &AccountRootPublicKeys,
    payload: &[u8],
) -> Result<AccountRootSignature, OrganizationCryptoError> {
    if private.public_keys(public.user_id)? != *public {
        return Err(OrganizationCryptoError::InvalidKey);
    }
    Ok(AccountRootSignature {
        ed25519_signature: sign_ed25519(&private.ed25519_seed, payload)?,
        ml_dsa_65_signature: sign_ml_dsa(&private.ml_dsa_65_seed, payload)?,
    })
}

pub fn verify_account_root_payload(
    public: &AccountRootPublicKeys,
    payload: &[u8],
    signature: &AccountRootSignature,
) -> Result<(), OrganizationCryptoError> {
    validate_root_public(public)?;
    if signature.ml_dsa_65_signature.len() != ML_DSA_65_SIGNATURE_LEN {
        return Err(OrganizationCryptoError::InvalidSignature);
    }
    verify_ed25519(
        &public.ed25519_public_key,
        payload,
        &signature.ed25519_signature,
    )?;
    verify_ml_dsa(
        &public.ml_dsa_65_public_key,
        payload,
        &signature.ml_dsa_65_signature,
    )
}

/// A device certificate that has passed both account-root signatures,
/// validity, suite, and revocation checks for the current operation.
///
/// Keeping this marker opaque prevents key-delivery callers from accidentally
/// using an unsigned server-supplied certificate.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VerifiedDeviceCertificate<'a> {
    certificate: &'a DeviceCertificate,
}

impl<'a> VerifiedDeviceCertificate<'a> {
    pub fn certificate(self) -> &'a DeviceCertificate {
        self.certificate
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum HybridScopeKind {
    Tenant = 1,
    List = 2,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HybridDekPackage {
    pub suite_id: u16,
    pub scope_kind: HybridScopeKind,
    pub scope_id: Uuid,
    pub generation: u64,
    pub sender_certificate_fingerprint: [u8; DEVICE_FINGERPRINT_LEN],
    pub recipient_certificate_fingerprint: [u8; DEVICE_FINGERPRINT_LEN],
    pub recipient_key_fingerprint: [u8; RECIPIENT_KEY_FINGERPRINT_LEN],
    pub ml_kem_768_ciphertext: Vec<u8>,
    pub wrapped_dek: Vec<u8>,
}

impl HybridDekPackage {
    pub fn encode(&self) -> Result<Vec<u8>, OrganizationCryptoError> {
        if self.suite_id != CRYPTO_SUITE_ID
            || self.scope_id.is_nil()
            || self.generation == 0
            || self.ml_kem_768_ciphertext.len() != ML_KEM_768_CIPHERTEXT_LEN
            || self.wrapped_dek.is_empty()
        {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let mut output = Vec::with_capacity(1_300);
        output.extend_from_slice(HYBRID_PACKAGE_MAGIC);
        output.extend_from_slice(&self.suite_id.to_be_bytes());
        output.push(self.scope_kind as u8);
        output.extend_from_slice(self.scope_id.as_bytes());
        output.extend_from_slice(&self.generation.to_be_bytes());
        output.extend_from_slice(&self.sender_certificate_fingerprint);
        output.extend_from_slice(&self.recipient_certificate_fingerprint);
        output.extend_from_slice(&self.recipient_key_fingerprint);
        output.extend_from_slice(&self.ml_kem_768_ciphertext);
        output.extend_from_slice(
            &u32::try_from(self.wrapped_dek.len())
                .map_err(|_| OrganizationCryptoError::InvalidEncoding)?
                .to_be_bytes(),
        );
        output.extend_from_slice(&self.wrapped_dek);
        Ok(output)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, OrganizationCryptoError> {
        const SENDER_START: usize = 31;
        const RECIPIENT_START: usize = SENDER_START + DEVICE_FINGERPRINT_LEN;
        const KEY_START: usize = RECIPIENT_START + DEVICE_FINGERPRINT_LEN;
        const CIPHERTEXT_START: usize = KEY_START + RECIPIENT_KEY_FINGERPRINT_LEN;
        const FIXED: usize = CIPHERTEXT_START + ML_KEM_768_CIPHERTEXT_LEN + 4;
        if bytes.len() <= FIXED || &bytes[..4] != HYBRID_PACKAGE_MAGIC {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let suite_id = u16::from_be_bytes(copy_array(&bytes[4..6])?);
        if suite_id != CRYPTO_SUITE_ID {
            return Err(OrganizationCryptoError::UnsupportedSuite);
        }
        let scope_kind = match bytes[6] {
            1 => HybridScopeKind::Tenant,
            2 => HybridScopeKind::List,
            _ => return Err(OrganizationCryptoError::InvalidEncoding),
        };
        let wrapped_len_offset = FIXED - 4;
        let wrapped_len = usize::try_from(u32::from_be_bytes(copy_array(
            &bytes[wrapped_len_offset..FIXED],
        )?))
        .map_err(|_| OrganizationCryptoError::InvalidEncoding)?;
        let encoded_len = FIXED
            .checked_add(wrapped_len)
            .ok_or(OrganizationCryptoError::InvalidEncoding)?;
        if wrapped_len == 0 || bytes.len() != encoded_len {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let result = Self {
            suite_id,
            scope_kind,
            scope_id: Uuid::from_bytes(copy_array(&bytes[7..23])?),
            generation: u64::from_be_bytes(copy_array(&bytes[23..31])?),
            sender_certificate_fingerprint: copy_array(&bytes[SENDER_START..RECIPIENT_START])?,
            recipient_certificate_fingerprint: copy_array(&bytes[RECIPIENT_START..KEY_START])?,
            recipient_key_fingerprint: copy_array(&bytes[KEY_START..CIPHERTEXT_START])?,
            ml_kem_768_ciphertext: bytes
                [CIPHERTEXT_START..CIPHERTEXT_START + ML_KEM_768_CIPHERTEXT_LEN]
                .to_vec(),
            wrapped_dek: bytes[FIXED..].to_vec(),
        };
        result.encode()?;
        Ok(result)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SafetyNumber {
    pub digest: [u8; ROOT_FINGERPRINT_LEN],
    pub decimal: String,
    pub qr_payload: [u8; SAFETY_NUMBER_QR_LEN],
}

pub fn generate_account_root(user_id: Uuid) -> Result<AccountRootKeyPair, OrganizationCryptoError> {
    require_non_nil(user_id)?;
    let mut ed25519_seed = [0u8; 32];
    let mut ml_dsa_65_seed = [0u8; 32];
    OsRng.fill_bytes(&mut ed25519_seed);
    OsRng.fill_bytes(&mut ml_dsa_65_seed);
    account_root_from_seeds(user_id, ed25519_seed, ml_dsa_65_seed)
}

fn account_root_from_seeds(
    user_id: Uuid,
    ed25519_seed: [u8; 32],
    ml_dsa_65_seed: [u8; 32],
) -> Result<AccountRootKeyPair, OrganizationCryptoError> {
    let ed_key = Ed25519KeyPair::from_seed_unchecked(&ed25519_seed)
        .map_err(|_| OrganizationCryptoError::InvalidKey)?;
    let ml_key = PqdsaKeyPair::from_seed(&ML_DSA_65_SIGNING, &ml_dsa_65_seed)
        .map_err(|_| OrganizationCryptoError::InvalidKey)?;
    let ed25519_public_key = copy_array(ed_key.public_key().as_ref())?;
    let ml_dsa_65_public_key = ml_key.public_key().as_ref().to_vec();
    if ml_dsa_65_public_key.len() != ML_DSA_65_PUBLIC_KEY_LEN {
        return Err(OrganizationCryptoError::InvalidKey);
    }
    Ok(AccountRootKeyPair {
        private: AccountRootPrivateKeys {
            ed25519_seed,
            ml_dsa_65_seed,
        },
        public: AccountRootPublicKeys {
            suite_id: CRYPTO_SUITE_ID,
            user_id,
            ed25519_public_key,
            ml_dsa_65_public_key,
        },
    })
}

pub fn generate_device_keys() -> Result<DeviceKeyPair, OrganizationCryptoError> {
    let mut signing_seed = [0u8; 32];
    OsRng.fill_bytes(&mut signing_seed);
    let signing_key = Ed25519KeyPair::from_seed_unchecked(&signing_seed)
        .map_err(|_| OrganizationCryptoError::InvalidKey)?;
    let signing_public_key = copy_array(signing_key.public_key().as_ref())?;

    let x25519_secret = StaticSecret::random_from_rng(OsRng);
    let x25519_public_key = X25519PublicKey::from(&x25519_secret).to_bytes();

    let ml_private =
        DecapsulationKey::generate(&ML_KEM_768).map_err(|_| OrganizationCryptoError::InvalidKey)?;
    let ml_public = ml_private
        .encapsulation_key()
        .map_err(|_| OrganizationCryptoError::InvalidKey)?;
    let ml_kem_768_decapsulation_key = ml_private
        .key_bytes()
        .map_err(|_| OrganizationCryptoError::InvalidKey)?
        .as_ref()
        .to_vec();
    let ml_kem_768_public_key = ml_public
        .key_bytes()
        .map_err(|_| OrganizationCryptoError::InvalidKey)?
        .as_ref()
        .to_vec();
    if ml_kem_768_decapsulation_key.len() != ML_KEM_768_PRIVATE_KEY_LEN
        || ml_kem_768_public_key.len() != ML_KEM_768_PUBLIC_KEY_LEN
    {
        return Err(OrganizationCryptoError::InvalidKey);
    }

    Ok(DeviceKeyPair {
        private: DevicePrivateKeys {
            signing_seed,
            x25519_secret_key: x25519_secret.to_bytes(),
            ml_kem_768_decapsulation_key,
            ml_kem_768_public_key: ml_kem_768_public_key.clone(),
        },
        signing_public_key,
        x25519_public_key,
        ml_kem_768_public_key,
    })
}

pub fn issue_device_certificate(
    root_private: &AccountRootPrivateKeys,
    root_public: &AccountRootPublicKeys,
    device_id: Uuid,
    device: &DeviceKeyPair,
    valid_from_ms: i64,
    expires_at_ms: i64,
) -> Result<DeviceCertificate, OrganizationCryptoError> {
    validate_root_public(root_public)?;
    require_non_nil(device_id)?;
    if valid_from_ms < 0 || expires_at_ms <= valid_from_ms {
        return Err(OrganizationCryptoError::CertificateNotValid);
    }
    validate_device_public_lengths(&device.ml_kem_768_public_key)?;
    let mut certificate = DeviceCertificate {
        suite_id: CRYPTO_SUITE_ID,
        user_id: root_public.user_id,
        device_id,
        valid_from_ms,
        expires_at_ms,
        signing_public_key: device.signing_public_key,
        x25519_public_key: device.x25519_public_key,
        ml_kem_768_public_key: device.ml_kem_768_public_key.clone(),
        root_ed25519_signature: [0u8; ED25519_SIGNATURE_LEN],
        root_ml_dsa_65_signature: Vec::new(),
    };
    let payload = certificate.signed_payload()?;
    certificate.root_ed25519_signature = sign_ed25519(&root_private.ed25519_seed, &payload)?;
    certificate.root_ml_dsa_65_signature = sign_ml_dsa(&root_private.ml_dsa_65_seed, &payload)?;
    verify_device_certificate(&certificate, root_public, valid_from_ms, false)?;
    Ok(certificate)
}

pub fn verify_device_certificate<'a>(
    certificate: &'a DeviceCertificate,
    root_public: &AccountRootPublicKeys,
    now_ms: i64,
    revoked: bool,
) -> Result<VerifiedDeviceCertificate<'a>, OrganizationCryptoError> {
    if revoked {
        return Err(OrganizationCryptoError::CertificateRevoked);
    }
    validate_root_public(root_public)?;
    if certificate.suite_id != CRYPTO_SUITE_ID
        || certificate.user_id != root_public.user_id
        || certificate.device_id.is_nil()
        || certificate.valid_from_ms < 0
        || certificate.expires_at_ms <= certificate.valid_from_ms
        || now_ms < certificate.valid_from_ms
        || now_ms >= certificate.expires_at_ms
    {
        return Err(OrganizationCryptoError::CertificateNotValid);
    }
    validate_device_public_lengths(&certificate.ml_kem_768_public_key)?;
    if certificate.root_ml_dsa_65_signature.len() != ML_DSA_65_SIGNATURE_LEN {
        return Err(OrganizationCryptoError::InvalidSignature);
    }
    let payload = certificate.signed_payload()?;
    verify_ed25519(
        &root_public.ed25519_public_key,
        &payload,
        &certificate.root_ed25519_signature,
    )?;
    verify_ml_dsa(
        &root_public.ml_dsa_65_public_key,
        &payload,
        &certificate.root_ml_dsa_65_signature,
    )?;
    Ok(VerifiedDeviceCertificate { certificate })
}

pub fn create_device_proof(
    private: &DevicePrivateKeys,
    certificate: &DeviceCertificate,
    challenge: &[u8; DEVICE_CHALLENGE_LEN],
) -> Result<DeviceProofOfPossession, OrganizationCryptoError> {
    let certificate_fingerprint = certificate.fingerprint()?;
    let payload = proof_payload(certificate, challenge, &certificate_fingerprint)?;
    Ok(DeviceProofOfPossession {
        certificate_fingerprint,
        signature: sign_ed25519(&private.signing_seed, &payload)?,
    })
}

pub fn verify_device_proof(
    certificate: &DeviceCertificate,
    challenge: &[u8; DEVICE_CHALLENGE_LEN],
    proof: &DeviceProofOfPossession,
) -> Result<(), OrganizationCryptoError> {
    let expected = certificate.fingerprint()?;
    if proof.certificate_fingerprint != expected {
        return Err(OrganizationCryptoError::InvalidProof);
    }
    let payload = proof_payload(certificate, challenge, &expected)?;
    verify_ed25519(&certificate.signing_public_key, &payload, &proof.signature)
        .map_err(|_| OrganizationCryptoError::InvalidProof)
}

pub fn derive_safety_number(
    first: &AccountRootPublicKeys,
    second: &AccountRootPublicKeys,
) -> Result<SafetyNumber, OrganizationCryptoError> {
    let mut fingerprints = [first.fingerprint()?, second.fingerprint()?];
    fingerprints.sort_unstable();
    let mut hasher = Sha384::new();
    hasher.update(SAFETY_NUMBER_MAGIC);
    hasher.update(fingerprints[0]);
    hasher.update(fingerprints[1]);
    let digest: [u8; ROOT_FINGERPRINT_LEN] = hasher.finalize().into();
    let decimal = decimal_safety_number(&digest[..30]);
    let mut qr_payload = [0u8; SAFETY_NUMBER_QR_LEN];
    qr_payload[0] = 1;
    qr_payload[1..].copy_from_slice(&digest);
    Ok(SafetyNumber {
        digest,
        decimal,
        qr_payload,
    })
}

pub fn wrap_dek_for_device(
    sender_private: &DevicePrivateKeys,
    sender: VerifiedDeviceCertificate<'_>,
    recipient: VerifiedDeviceCertificate<'_>,
    scope_kind: HybridScopeKind,
    scope_id: Uuid,
    generation: u64,
    dek: &[u8; DEK_LEN],
) -> Result<HybridDekPackage, OrganizationCryptoError> {
    let sender_certificate = sender.certificate();
    let recipient_certificate = recipient.certificate();
    validate_hybrid_context(
        sender_certificate,
        recipient_certificate,
        scope_id,
        generation,
    )?;
    ensure_private_matches_certificate(sender_private, sender_certificate)?;
    let recipient_ml_key =
        EncapsulationKey::new(&ML_KEM_768, &recipient_certificate.ml_kem_768_public_key)
            .map_err(|_| OrganizationCryptoError::InvalidKey)?;
    let (ml_ciphertext, ml_shared) = recipient_ml_key
        .encapsulate()
        .map_err(|_| OrganizationCryptoError::HybridAgreement)?;
    let ml_kem_768_ciphertext = ml_ciphertext.as_ref().to_vec();
    if ml_kem_768_ciphertext.len() != ML_KEM_768_CIPHERTEXT_LEN {
        return Err(OrganizationCryptoError::HybridAgreement);
    }
    let sender_fingerprint = sender_certificate.fingerprint()?;
    let recipient_fingerprint = recipient_certificate.fingerprint()?;
    let recipient_key_fingerprint = recipient_certificate.recipient_key_fingerprint()?;
    let transcript = hybrid_transcript(
        sender_certificate,
        recipient_certificate,
        &ml_kem_768_ciphertext,
        scope_kind,
        scope_id,
        generation,
        &recipient_key_fingerprint,
    )?;
    let x_shared = x25519_shared(
        &sender_private.x25519_secret_key,
        &recipient_certificate.x25519_public_key,
    )?;
    let wrap_key = hybrid_wrap_key(&x_shared, ml_shared.as_ref(), &transcript)?;
    let wrapped_dek =
        encrypt(&wrap_key, dek, &transcript).map_err(|_| OrganizationCryptoError::Decryption)?;
    Ok(HybridDekPackage {
        suite_id: CRYPTO_SUITE_ID,
        scope_kind,
        scope_id,
        generation,
        sender_certificate_fingerprint: sender_fingerprint,
        recipient_certificate_fingerprint: recipient_fingerprint,
        recipient_key_fingerprint,
        ml_kem_768_ciphertext,
        wrapped_dek,
    })
}

pub fn unwrap_dek_for_device(
    recipient_private: &DevicePrivateKeys,
    sender: VerifiedDeviceCertificate<'_>,
    recipient: VerifiedDeviceCertificate<'_>,
    package: &HybridDekPackage,
) -> Result<Zeroizing<[u8; DEK_LEN]>, OrganizationCryptoError> {
    let sender_certificate = sender.certificate();
    let recipient_certificate = recipient.certificate();
    validate_hybrid_context(
        sender_certificate,
        recipient_certificate,
        package.scope_id,
        package.generation,
    )?;
    if package.suite_id != CRYPTO_SUITE_ID
        || package.generation == 0
        || package.sender_certificate_fingerprint != sender_certificate.fingerprint()?
        || package.recipient_certificate_fingerprint != recipient_certificate.fingerprint()?
        || package.recipient_key_fingerprint != recipient_certificate.recipient_key_fingerprint()?
        || package.ml_kem_768_ciphertext.len() != ML_KEM_768_CIPHERTEXT_LEN
    {
        return Err(OrganizationCryptoError::RecipientMismatch);
    }
    ensure_private_matches_certificate(recipient_private, recipient_certificate)?;
    let transcript = hybrid_transcript(
        sender_certificate,
        recipient_certificate,
        &package.ml_kem_768_ciphertext,
        package.scope_kind,
        package.scope_id,
        package.generation,
        &package.recipient_key_fingerprint,
    )?;
    let ml_private =
        DecapsulationKey::new(&ML_KEM_768, &recipient_private.ml_kem_768_decapsulation_key)
            .map_err(|_| OrganizationCryptoError::InvalidKey)?;
    let ml_shared = ml_private
        .decapsulate(Ciphertext::from(package.ml_kem_768_ciphertext.as_slice()))
        .map_err(|_| OrganizationCryptoError::HybridAgreement)?;
    let x_shared = x25519_shared(
        &recipient_private.x25519_secret_key,
        &sender_certificate.x25519_public_key,
    )?;
    let wrap_key = hybrid_wrap_key(&x_shared, ml_shared.as_ref(), &transcript)?;
    let plaintext = Zeroizing::new(
        decrypt(&wrap_key, &package.wrapped_dek, &transcript)
            .map_err(|_| OrganizationCryptoError::Decryption)?,
    );
    if plaintext.len() != DEK_LEN {
        return Err(OrganizationCryptoError::Decryption);
    }
    let mut dek = Zeroizing::new([0u8; DEK_LEN]);
    dek.copy_from_slice(&plaintext);
    Ok(dek)
}

impl AccountRootPrivateKeys {
    pub fn encode(&self) -> Zeroizing<[u8; 64]> {
        let mut bytes = Zeroizing::new([0u8; 64]);
        bytes[..32].copy_from_slice(&self.ed25519_seed);
        bytes[32..].copy_from_slice(&self.ml_dsa_65_seed);
        bytes
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, OrganizationCryptoError> {
        if bytes.len() != 64 {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        Ok(Self {
            ed25519_seed: copy_array(&bytes[..32])?,
            ml_dsa_65_seed: copy_array(&bytes[32..])?,
        })
    }

    pub fn public_keys(
        &self,
        user_id: Uuid,
    ) -> Result<AccountRootPublicKeys, OrganizationCryptoError> {
        Ok(account_root_from_seeds(user_id, self.ed25519_seed, self.ml_dsa_65_seed)?.public)
    }
}

impl AccountRootPublicKeys {
    pub fn encode(&self) -> Result<Vec<u8>, OrganizationCryptoError> {
        validate_root_public(self)?;
        let mut output = Vec::with_capacity(4 + 2 + 16 + 32 + ML_DSA_65_PUBLIC_KEY_LEN);
        output.extend_from_slice(ROOT_PUBLIC_MAGIC);
        output.extend_from_slice(&self.suite_id.to_be_bytes());
        output.extend_from_slice(self.user_id.as_bytes());
        output.extend_from_slice(&self.ed25519_public_key);
        output.extend_from_slice(&self.ml_dsa_65_public_key);
        Ok(output)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, OrganizationCryptoError> {
        let expected = 4 + 2 + 16 + ED25519_PUBLIC_KEY_LEN + ML_DSA_65_PUBLIC_KEY_LEN;
        if bytes.len() != expected || &bytes[..4] != ROOT_PUBLIC_MAGIC {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let suite_id = u16::from_be_bytes(copy_array(&bytes[4..6])?);
        if suite_id != CRYPTO_SUITE_ID {
            return Err(OrganizationCryptoError::UnsupportedSuite);
        }
        let result = Self {
            suite_id,
            user_id: Uuid::from_bytes(copy_array(&bytes[6..22])?),
            ed25519_public_key: copy_array(&bytes[22..54])?,
            ml_dsa_65_public_key: bytes[54..].to_vec(),
        };
        validate_root_public(&result)?;
        Ok(result)
    }

    pub fn fingerprint(&self) -> Result<[u8; ROOT_FINGERPRINT_LEN], OrganizationCryptoError> {
        Ok(Sha384::digest(self.encode()?).into())
    }
}

impl DevicePrivateKeys {
    pub fn encode(&self) -> Result<Zeroizing<Vec<u8>>, OrganizationCryptoError> {
        if self.ml_kem_768_decapsulation_key.len() != ML_KEM_768_PRIVATE_KEY_LEN {
            return Err(OrganizationCryptoError::InvalidKey);
        }
        if self.ml_kem_768_public_key.len() != ML_KEM_768_PUBLIC_KEY_LEN {
            return Err(OrganizationCryptoError::InvalidKey);
        }
        let mut output = Zeroizing::new(Vec::with_capacity(
            64 + ML_KEM_768_PRIVATE_KEY_LEN + ML_KEM_768_PUBLIC_KEY_LEN,
        ));
        output.extend_from_slice(&self.signing_seed);
        output.extend_from_slice(&self.x25519_secret_key);
        output.extend_from_slice(&self.ml_kem_768_decapsulation_key);
        output.extend_from_slice(&self.ml_kem_768_public_key);
        Ok(output)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, OrganizationCryptoError> {
        if bytes.len() != 64 + ML_KEM_768_PRIVATE_KEY_LEN + ML_KEM_768_PUBLIC_KEY_LEN {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        Ok(Self {
            signing_seed: copy_array(&bytes[..32])?,
            x25519_secret_key: copy_array(&bytes[32..64])?,
            ml_kem_768_decapsulation_key: bytes[64..64 + ML_KEM_768_PRIVATE_KEY_LEN].to_vec(),
            ml_kem_768_public_key: bytes[64 + ML_KEM_768_PRIVATE_KEY_LEN..].to_vec(),
        })
    }
}

impl DeviceCertificate {
    fn signed_payload(&self) -> Result<Vec<u8>, OrganizationCryptoError> {
        if self.suite_id != CRYPTO_SUITE_ID {
            return Err(OrganizationCryptoError::UnsupportedSuite);
        }
        validate_device_public_lengths(&self.ml_kem_768_public_key)?;
        let mut output = Vec::with_capacity(4 + 2 + 32 + 16 + 32 + ML_KEM_768_PUBLIC_KEY_LEN + 16);
        output.extend_from_slice(DEVICE_CERT_MAGIC);
        output.extend_from_slice(&self.suite_id.to_be_bytes());
        output.extend_from_slice(self.user_id.as_bytes());
        output.extend_from_slice(self.device_id.as_bytes());
        output.extend_from_slice(&self.valid_from_ms.to_be_bytes());
        output.extend_from_slice(&self.expires_at_ms.to_be_bytes());
        output.extend_from_slice(&self.signing_public_key);
        output.extend_from_slice(&self.x25519_public_key);
        output.extend_from_slice(&self.ml_kem_768_public_key);
        Ok(output)
    }

    pub fn encode(&self) -> Result<Vec<u8>, OrganizationCryptoError> {
        if self.root_ml_dsa_65_signature.len() != ML_DSA_65_SIGNATURE_LEN {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let mut output = self.signed_payload()?;
        output.extend_from_slice(&self.root_ed25519_signature);
        output.extend_from_slice(&self.root_ml_dsa_65_signature);
        Ok(output)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, OrganizationCryptoError> {
        const PREFIX: usize = 4 + 2 + 16 + 16 + 8 + 8 + 32 + 32;
        let signed_len = PREFIX + ML_KEM_768_PUBLIC_KEY_LEN;
        let expected = signed_len + ED25519_SIGNATURE_LEN + ML_DSA_65_SIGNATURE_LEN;
        if bytes.len() != expected || &bytes[..4] != DEVICE_CERT_MAGIC {
            return Err(OrganizationCryptoError::InvalidEncoding);
        }
        let suite_id = u16::from_be_bytes(copy_array(&bytes[4..6])?);
        if suite_id != CRYPTO_SUITE_ID {
            return Err(OrganizationCryptoError::UnsupportedSuite);
        }
        let certificate = Self {
            suite_id,
            user_id: Uuid::from_bytes(copy_array(&bytes[6..22])?),
            device_id: Uuid::from_bytes(copy_array(&bytes[22..38])?),
            valid_from_ms: i64::from_be_bytes(copy_array(&bytes[38..46])?),
            expires_at_ms: i64::from_be_bytes(copy_array(&bytes[46..54])?),
            signing_public_key: copy_array(&bytes[54..86])?,
            x25519_public_key: copy_array(&bytes[86..118])?,
            ml_kem_768_public_key: bytes[118..signed_len].to_vec(),
            root_ed25519_signature: copy_array(&bytes[signed_len..signed_len + 64])?,
            root_ml_dsa_65_signature: bytes[signed_len + 64..].to_vec(),
        };
        certificate.signed_payload()?;
        Ok(certificate)
    }

    pub fn fingerprint(&self) -> Result<[u8; DEVICE_FINGERPRINT_LEN], OrganizationCryptoError> {
        Ok(Sha384::digest(self.signed_payload()?).into())
    }

    pub fn recipient_key_fingerprint(
        &self,
    ) -> Result<[u8; RECIPIENT_KEY_FINGERPRINT_LEN], OrganizationCryptoError> {
        validate_device_public_lengths(&self.ml_kem_768_public_key)?;
        let mut hasher = Sha256::new();
        hasher.update(RECIPIENT_KEY_FINGERPRINT_MAGIC);
        hasher.update(self.suite_id.to_be_bytes());
        hasher.update(self.x25519_public_key);
        hasher.update(&self.ml_kem_768_public_key);
        Ok(hasher.finalize().into())
    }
}

fn validate_root_public(root: &AccountRootPublicKeys) -> Result<(), OrganizationCryptoError> {
    if root.suite_id != CRYPTO_SUITE_ID {
        return Err(OrganizationCryptoError::UnsupportedSuite);
    }
    if root.user_id.is_nil() || root.ml_dsa_65_public_key.len() != ML_DSA_65_PUBLIC_KEY_LEN {
        return Err(OrganizationCryptoError::InvalidKey);
    }
    Ok(())
}

fn validate_device_public_lengths(ml_kem_public: &[u8]) -> Result<(), OrganizationCryptoError> {
    if ml_kem_public.len() != ML_KEM_768_PUBLIC_KEY_LEN {
        return Err(OrganizationCryptoError::InvalidKey);
    }
    Ok(())
}

fn sign_ed25519(
    seed: &[u8; 32],
    message: &[u8],
) -> Result<[u8; ED25519_SIGNATURE_LEN], OrganizationCryptoError> {
    let key = Ed25519KeyPair::from_seed_unchecked(seed)
        .map_err(|_| OrganizationCryptoError::InvalidKey)?;
    copy_array(key.sign(message).as_ref())
}

fn verify_ed25519(
    public_key: &[u8; ED25519_PUBLIC_KEY_LEN],
    message: &[u8],
    signature: &[u8; ED25519_SIGNATURE_LEN],
) -> Result<(), OrganizationCryptoError> {
    UnparsedPublicKey::new(&ED25519, public_key)
        .verify(message, signature)
        .map_err(|_| OrganizationCryptoError::InvalidSignature)
}

fn sign_ml_dsa(seed: &[u8; 32], message: &[u8]) -> Result<Vec<u8>, OrganizationCryptoError> {
    let key = PqdsaKeyPair::from_seed(&ML_DSA_65_SIGNING, seed)
        .map_err(|_| OrganizationCryptoError::InvalidKey)?;
    let mut signature = vec![0u8; ML_DSA_65_SIGNATURE_LEN];
    let length = key
        .sign(message, &mut signature)
        .map_err(|_| OrganizationCryptoError::InvalidKey)?;
    if length != ML_DSA_65_SIGNATURE_LEN {
        return Err(OrganizationCryptoError::InvalidKey);
    }
    Ok(signature)
}

fn verify_ml_dsa(
    public_key: &[u8],
    message: &[u8],
    signature: &[u8],
) -> Result<(), OrganizationCryptoError> {
    if public_key.len() != ML_DSA_65_PUBLIC_KEY_LEN || signature.len() != ML_DSA_65_SIGNATURE_LEN {
        return Err(OrganizationCryptoError::InvalidSignature);
    }
    UnparsedPublicKey::new(&ML_DSA_65, public_key)
        .verify(message, signature)
        .map_err(|_| OrganizationCryptoError::InvalidSignature)
}

fn proof_payload(
    certificate: &DeviceCertificate,
    challenge: &[u8; DEVICE_CHALLENGE_LEN],
    certificate_fingerprint: &[u8; DEVICE_FINGERPRINT_LEN],
) -> Result<Vec<u8>, OrganizationCryptoError> {
    if certificate.suite_id != CRYPTO_SUITE_ID {
        return Err(OrganizationCryptoError::UnsupportedSuite);
    }
    let mut output = Vec::with_capacity(4 + 2 + 16 + 16 + 32 + 32);
    output.extend_from_slice(DEVICE_PROOF_MAGIC);
    output.extend_from_slice(&certificate.suite_id.to_be_bytes());
    output.extend_from_slice(certificate.user_id.as_bytes());
    output.extend_from_slice(certificate.device_id.as_bytes());
    output.extend_from_slice(challenge);
    output.extend_from_slice(certificate_fingerprint);
    Ok(output)
}

fn validate_hybrid_context(
    sender: &DeviceCertificate,
    recipient: &DeviceCertificate,
    scope_id: Uuid,
    generation: u64,
) -> Result<(), OrganizationCryptoError> {
    if sender.suite_id != CRYPTO_SUITE_ID
        || recipient.suite_id != CRYPTO_SUITE_ID
        || scope_id.is_nil()
        || generation == 0
    {
        return Err(OrganizationCryptoError::InvalidEncoding);
    }
    validate_device_public_lengths(&sender.ml_kem_768_public_key)?;
    validate_device_public_lengths(&recipient.ml_kem_768_public_key)
}

fn ensure_private_matches_certificate(
    private: &DevicePrivateKeys,
    certificate: &DeviceCertificate,
) -> Result<(), OrganizationCryptoError> {
    let signing_key = Ed25519KeyPair::from_seed_unchecked(&private.signing_seed)
        .map_err(|_| OrganizationCryptoError::InvalidKey)?;
    let signing_public: [u8; 32] = copy_array(signing_key.public_key().as_ref())?;
    let x_public = X25519PublicKey::from(&StaticSecret::from(private.x25519_secret_key)).to_bytes();
    if signing_public != certificate.signing_public_key || x_public != certificate.x25519_public_key
    {
        return Err(OrganizationCryptoError::RecipientMismatch);
    }
    if private.ml_kem_768_decapsulation_key.len() != ML_KEM_768_PRIVATE_KEY_LEN {
        return Err(OrganizationCryptoError::InvalidKey);
    }
    if private.ml_kem_768_public_key != certificate.ml_kem_768_public_key {
        return Err(OrganizationCryptoError::RecipientMismatch);
    }
    Ok(())
}

fn hybrid_transcript(
    sender: &DeviceCertificate,
    recipient: &DeviceCertificate,
    ml_ciphertext: &[u8],
    scope_kind: HybridScopeKind,
    scope_id: Uuid,
    generation: u64,
    recipient_key_fingerprint: &[u8; RECIPIENT_KEY_FINGERPRINT_LEN],
) -> Result<Vec<u8>, OrganizationCryptoError> {
    if ml_ciphertext.len() != ML_KEM_768_CIPHERTEXT_LEN {
        return Err(OrganizationCryptoError::InvalidEncoding);
    }
    let fields = [
        sender.fingerprint()?.to_vec(),
        recipient.fingerprint()?.to_vec(),
        sender.x25519_public_key.to_vec(),
        recipient.x25519_public_key.to_vec(),
        sender.ml_kem_768_public_key.clone(),
        recipient.ml_kem_768_public_key.clone(),
        ml_ciphertext.to_vec(),
        vec![scope_kind as u8],
        scope_id.as_bytes().to_vec(),
        generation.to_be_bytes().to_vec(),
        recipient_key_fingerprint.to_vec(),
    ];
    let mut output = Vec::with_capacity(4_000);
    output.extend_from_slice(HYBRID_TRANSCRIPT_MAGIC);
    for field in fields {
        let length =
            u32::try_from(field.len()).map_err(|_| OrganizationCryptoError::InvalidEncoding)?;
        output.extend_from_slice(&length.to_be_bytes());
        output.extend_from_slice(&field);
    }
    Ok(output)
}

fn x25519_shared(
    private_key: &[u8; 32],
    public_key: &[u8; 32],
) -> Result<Zeroizing<[u8; 32]>, OrganizationCryptoError> {
    let shared = StaticSecret::from(*private_key)
        .diffie_hellman(&X25519PublicKey::from(*public_key))
        .to_bytes();
    if shared == [0u8; 32] {
        return Err(OrganizationCryptoError::HybridAgreement);
    }
    Ok(Zeroizing::new(shared))
}

fn hybrid_wrap_key(
    x25519_shared: &[u8; 32],
    ml_kem_shared: &[u8],
    transcript: &[u8],
) -> Result<Zeroizing<[u8; 32]>, OrganizationCryptoError> {
    let mut ikm = Zeroizing::new(Vec::with_capacity(
        x25519_shared.len() + ml_kem_shared.len(),
    ));
    ikm.extend_from_slice(x25519_shared);
    ikm.extend_from_slice(ml_kem_shared);
    let salt = Sha384::digest(transcript);
    let hkdf = Hkdf::<Sha384>::new(Some(&salt), &ikm);
    let mut output = Zeroizing::new([0u8; 32]);
    hkdf.expand(HYBRID_WRAP_INFO, &mut *output)
        .map_err(|_| OrganizationCryptoError::HybridAgreement)?;
    Ok(output)
}

fn decimal_safety_number(bytes: &[u8]) -> String {
    let mut digits = vec![0u8];
    for byte in bytes {
        let mut carry = u16::from(*byte);
        for digit in &mut digits {
            let value = u16::from(*digit) * 256 + carry;
            *digit = (value % 10) as u8;
            carry = value / 10;
        }
        while carry > 0 {
            digits.push((carry % 10) as u8);
            carry /= 10;
        }
    }
    digits.resize(60, 0);
    let raw: String = digits
        .iter()
        .rev()
        .map(|digit| char::from(b'0' + *digit))
        .collect();
    raw.as_bytes()
        .chunks(5)
        .map(|chunk| std::str::from_utf8(chunk).expect("decimal digits are UTF-8"))
        .collect::<Vec<_>>()
        .join(" ")
}

fn require_non_nil(id: Uuid) -> Result<(), OrganizationCryptoError> {
    if id.is_nil() {
        Err(OrganizationCryptoError::InvalidEncoding)
    } else {
        Ok(())
    }
}

fn copy_array<const N: usize>(bytes: &[u8]) -> Result<[u8; N], OrganizationCryptoError> {
    bytes
        .try_into()
        .map_err(|_| OrganizationCryptoError::InvalidEncoding)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn certificate_fixture() -> (
        AccountRootKeyPair,
        DeviceKeyPair,
        DeviceCertificate,
        DeviceKeyPair,
        DeviceCertificate,
    ) {
        let user_id = Uuid::now_v7();
        let root = generate_account_root(user_id).unwrap();
        let first = generate_device_keys().unwrap();
        let second = generate_device_keys().unwrap();
        let first_cert = issue_device_certificate(
            &root.private,
            &root.public,
            Uuid::now_v7(),
            &first,
            1_000,
            10_000,
        )
        .unwrap();
        let second_cert = issue_device_certificate(
            &root.private,
            &root.public,
            Uuid::now_v7(),
            &second,
            1_000,
            10_000,
        )
        .unwrap();
        (root, first, first_cert, second, second_cert)
    }

    #[test]
    fn hybrid_root_signatures_reject_certificate_tampering_and_partial_downgrade() {
        let (root, _first, certificate, _second, _second_cert) = certificate_fixture();
        verify_device_certificate(&certificate, &root.public, 2_000, false).unwrap();
        assert_eq!(
            DeviceCertificate::decode(&certificate.encode().unwrap()).unwrap(),
            certificate
        );

        let mut tampered = certificate.clone();
        tampered.x25519_public_key[0] ^= 1;
        assert_eq!(
            verify_device_certificate(&tampered, &root.public, 2_000, false),
            Err(OrganizationCryptoError::InvalidSignature)
        );

        let mut missing_pq = certificate.clone();
        missing_pq.root_ml_dsa_65_signature.clear();
        assert_eq!(
            verify_device_certificate(&missing_pq, &root.public, 2_000, false),
            Err(OrganizationCryptoError::InvalidSignature)
        );
        let mut signature_changed = certificate.clone();
        signature_changed.root_ed25519_signature[0] ^= 1;
        assert_eq!(
            signature_changed.fingerprint().unwrap(),
            certificate.fingerprint().unwrap()
        );
        assert_eq!(
            verify_device_certificate(&signature_changed, &root.public, 2_000, false),
            Err(OrganizationCryptoError::InvalidSignature)
        );
        assert_eq!(
            verify_device_certificate(&certificate, &root.public, 2_000, true),
            Err(OrganizationCryptoError::CertificateRevoked)
        );
    }

    #[test]
    fn device_proof_binds_challenge_device_and_certificate_fingerprint() {
        let (_root, first, certificate, _second, _second_cert) = certificate_fixture();
        let challenge = [0x42; DEVICE_CHALLENGE_LEN];
        let proof = create_device_proof(&first.private, &certificate, &challenge).unwrap();
        verify_device_proof(&certificate, &challenge, &proof).unwrap();
        let wrong_challenge = [0x43; DEVICE_CHALLENGE_LEN];
        assert_eq!(
            verify_device_proof(&certificate, &wrong_challenge, &proof),
            Err(OrganizationCryptoError::InvalidProof)
        );
    }

    #[test]
    fn root_signed_device_revocation_is_canonical_and_rejects_replay_mutation() {
        let (root, _first, certificate, _second, _second_cert) = certificate_fixture();
        let statement = SignedDeviceRevocation::sign(
            &root.private,
            &root.public,
            certificate.device_id,
            certificate.fingerprint().unwrap(),
            3,
            2_500,
            [0; 32],
        )
        .unwrap();
        let decoded = SignedDeviceRevocation::decode(&statement.encode().unwrap()).unwrap();
        decoded.verify(&root.public).unwrap();

        let mut changed_revision = decoded.clone();
        changed_revision.revision += 1;
        assert_eq!(
            changed_revision.verify(&root.public),
            Err(OrganizationCryptoError::InvalidSignature)
        );
        let substituted_root = generate_account_root(root.public.user_id).unwrap();
        assert!(decoded.verify(&substituted_root.public).is_err());
    }

    #[test]
    fn safety_number_is_symmetric_fixed_width_and_changes_with_root() {
        let first = generate_account_root(Uuid::now_v7()).unwrap();
        let second = generate_account_root(Uuid::now_v7()).unwrap();
        let forward = derive_safety_number(&first.public, &second.public).unwrap();
        let reverse = derive_safety_number(&second.public, &first.public).unwrap();
        assert_eq!(forward, reverse);
        assert_eq!(forward.decimal.len(), 71);
        assert_eq!(forward.decimal.replace(' ', "").len(), 60);
        assert_eq!(forward.qr_payload[0], 1);

        let changed = generate_account_root(second.public.user_id).unwrap();
        assert_ne!(
            forward.digest,
            derive_safety_number(&first.public, &changed.public)
                .unwrap()
                .digest
        );
    }

    #[test]
    fn hybrid_kem_wrap_binds_both_keys_scope_generation_and_recipient() {
        let (root, first, first_cert, second, second_cert) = certificate_fixture();
        let scope_id = Uuid::now_v7();
        let dek = [0x6d; DEK_LEN];
        let verified_first =
            verify_device_certificate(&first_cert, &root.public, 2_000, false).unwrap();
        let verified_second =
            verify_device_certificate(&second_cert, &root.public, 2_000, false).unwrap();
        let package = wrap_dek_for_device(
            &first.private,
            verified_first,
            verified_second,
            HybridScopeKind::List,
            scope_id,
            7,
            &dek,
        )
        .unwrap();
        assert_eq!(
            HybridDekPackage::decode(&package.encode().unwrap()).unwrap(),
            package
        );
        assert_eq!(
            *unwrap_dek_for_device(&second.private, verified_first, verified_second, &package)
                .unwrap(),
            dek
        );

        let mut wrong_generation = package.clone();
        wrong_generation.generation += 1;
        assert_eq!(
            unwrap_dek_for_device(
                &second.private,
                verified_first,
                verified_second,
                &wrong_generation
            ),
            Err(OrganizationCryptoError::Decryption)
        );

        let outsider = generate_device_keys().unwrap();
        assert_eq!(
            unwrap_dek_for_device(&outsider.private, verified_first, verified_second, &package),
            Err(OrganizationCryptoError::RecipientMismatch)
        );

        let self_package = wrap_dek_for_device(
            &first.private,
            verified_first,
            verified_first,
            HybridScopeKind::Tenant,
            scope_id,
            8,
            &dek,
        )
        .unwrap();
        assert_eq!(
            *unwrap_dek_for_device(
                &first.private,
                verified_first,
                verified_first,
                &self_package,
            )
            .unwrap(),
            dek
        );
    }

    #[test]
    fn hybrid_package_rejects_overflowing_wrapped_length() {
        const FIXED: usize = 31
            + DEVICE_FINGERPRINT_LEN
            + DEVICE_FINGERPRINT_LEN
            + RECIPIENT_KEY_FINGERPRINT_LEN
            + ML_KEM_768_CIPHERTEXT_LEN
            + 4;
        let mut encoded = vec![0; FIXED + 1];
        encoded[..4].copy_from_slice(b"THP1");
        encoded[4..6].copy_from_slice(&CRYPTO_SUITE_ID.to_be_bytes());
        encoded[6] = HybridScopeKind::Tenant as u8;
        encoded[FIXED - 4..FIXED].copy_from_slice(&u32::MAX.to_be_bytes());

        assert!(HybridDekPackage::decode(&encoded).is_err());
    }

    #[test]
    fn fips_203_204_operational_roundtrip_has_fixed_parameter_sizes() {
        let seed = [0x01; 32];
        let first = PqdsaKeyPair::from_seed(&ML_DSA_65_SIGNING, &seed).unwrap();
        let second = PqdsaKeyPair::from_seed(&ML_DSA_65_SIGNING, &seed).unwrap();
        assert_eq!(first.public_key().as_ref(), second.public_key().as_ref());
        assert_eq!(first.public_key().as_ref().len(), ML_DSA_65_PUBLIC_KEY_LEN);
        let mut signature = vec![0u8; ML_DSA_65_SIGNATURE_LEN];
        first.sign(b"FIPS 204 ML-DSA-65", &mut signature).unwrap();
        UnparsedPublicKey::new(&ML_DSA_65, first.public_key().as_ref())
            .verify(b"FIPS 204 ML-DSA-65", &signature)
            .unwrap();

        let decapsulation = DecapsulationKey::generate(&ML_KEM_768).unwrap();
        let public = decapsulation.encapsulation_key().unwrap();
        let (ciphertext, sender_secret) = public.encapsulate().unwrap();
        let recipient_secret = decapsulation.decapsulate(ciphertext).unwrap();
        assert_eq!(sender_secret.as_ref(), recipient_secret.as_ref());
        assert_eq!(
            public.key_bytes().unwrap().as_ref().len(),
            ML_KEM_768_PUBLIC_KEY_LEN
        );
        assert_eq!(
            decapsulation.key_bytes().unwrap().as_ref().len(),
            ML_KEM_768_PRIVATE_KEY_LEN
        );
    }

    #[test]
    fn aws_lc_official_acvp_known_answer_tests_pass() {
        // AWS-LC's BORINGSSL_self_test runs its embedded ACVP-derived FIPS 203
        // ML-KEM and FIPS 204 ML-DSA known-answer tests. Keeping this call in
        // Todori's gate verifies the exact aws-lc-sys artifact selected by the
        // pinned aws-lc-rs dependency, in addition to our ML-KEM-768 / ML-DSA-65
        // operational test above.
        assert_eq!(unsafe { aws_lc_sys::BORINGSSL_self_test() }, 1);
    }
}
