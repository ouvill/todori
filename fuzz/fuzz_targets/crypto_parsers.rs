#![no_main]

use std::sync::OnceLock;

use libfuzzer_sys::fuzz_target;
use taskveil_crypto::organization::{
    generate_account_root, generate_device_keys, issue_device_certificate, AccountRootPrivateKeys,
    AccountRootPublicKeys, DeviceCertificate, DeviceIdentity, HybridDekPackage, HybridScopeKind,
    SignedDeviceRevocation, ML_KEM_768_CIPHERTEXT_LEN,
};
use taskveil_sync::{
    envelope::parse_envelope_header, organization::OrganizationKeyManifest, KeyManifest,
    RotationStatus,
};
use uuid::Uuid;

static CANONICAL_TEMPLATES: OnceLock<Vec<Vec<u8>>> = OnceLock::new();

fn exercise_parsers(data: &[u8]) {
    let _ = parse_envelope_header(data);
    let _ = KeyManifest::from_authenticated_bytes(data);
    let _ = OrganizationKeyManifest::decode(data);
    let _ = AccountRootPublicKeys::decode(data);
    let _ = AccountRootPrivateKeys::decode(data);
    let _ = DeviceCertificate::decode(data);
    let _ = DeviceIdentity::decode(data);
    let _ = HybridDekPackage::decode(data);
    let _ = SignedDeviceRevocation::decode(data);
}

fn canonical_templates() -> Vec<Vec<u8>> {
    let user_id = Uuid::from_u128(1);
    let tenant_id = Uuid::from_u128(2);
    let device_id = Uuid::from_u128(3);
    let root = generate_account_root(user_id).expect("canonical fuzz root");
    let device = generate_device_keys().expect("canonical fuzz device");
    let certificate =
        issue_device_certificate(&root.private, &root.public, device_id, &device, 1, 10_000)
            .expect("canonical fuzz certificate");
    let certificate_fingerprint = certificate
        .fingerprint()
        .expect("canonical certificate fingerprint");
    let revocation = SignedDeviceRevocation::sign(
        &root.private,
        &root.public,
        device_id,
        certificate_fingerprint,
        1,
        2,
        [0; 32],
    )
    .expect("canonical fuzz revocation");
    let organization_manifest = OrganizationKeyManifest::sign(
        KeyManifest::organization_unsigned(
            tenant_id,
            1,
            RotationStatus::Active,
            1,
            [0; 32],
            vec![[7; 32]],
        )
        .expect("canonical organization manifest"),
        &root.private,
        &root.public,
    )
    .expect("signed canonical organization manifest");
    let personal_manifest = KeyManifest::authenticate_personal(
        tenant_id,
        1,
        RotationStatus::Active,
        1,
        [0; 32],
        Vec::new(),
        &[9; 32],
    )
    .expect("canonical personal manifest");
    let hybrid_package = HybridDekPackage {
        suite_id: taskveil_crypto::CRYPTO_SUITE_ID,
        scope_kind: HybridScopeKind::Tenant,
        scope_id: tenant_id,
        generation: 1,
        sender_certificate_fingerprint: certificate_fingerprint,
        recipient_certificate_fingerprint: certificate_fingerprint,
        recipient_key_fingerprint: [8; 32],
        ml_kem_768_ciphertext: vec![6; ML_KEM_768_CIPHERTEXT_LEN],
        wrapped_dek: vec![5; 48],
    };
    let identity =
        DeviceIdentity::new(device.private, certificate.clone()).expect("canonical fuzz identity");
    let mut envelope = vec![0; 54];
    envelope[..4].copy_from_slice(b"TDE5");
    envelope[4..6].copy_from_slice(&taskveil_crypto::CRYPTO_SUITE_ID.to_be_bytes());
    envelope[6..14].copy_from_slice(&1u64.to_be_bytes());

    vec![
        envelope,
        personal_manifest
            .authenticated_bytes()
            .expect("encoded personal manifest"),
        organization_manifest
            .encode()
            .expect("encoded organization manifest"),
        root.public.encode().expect("encoded root public"),
        root.private.encode().to_vec(),
        certificate.encode().expect("encoded certificate"),
        identity.encode().expect("encoded identity").to_vec(),
        hybrid_package.encode().expect("encoded hybrid package"),
        revocation.encode().expect("encoded revocation"),
    ]
}

fuzz_target!(|data: &[u8]| {
    exercise_parsers(data);
    let Some((&selector, mutation)) = data.split_first() else {
        return;
    };
    let templates = CANONICAL_TEMPLATES.get_or_init(canonical_templates);
    for template in templates {
        exercise_parsers(template);
    }
    let mut shaped = templates[usize::from(selector) % templates.len()].clone();
    if shaped.len() > 4 {
        let mutable_len = shaped.len() - 4;
        for (index, byte) in mutation.iter().enumerate() {
            shaped[4 + index % mutable_len] ^= byte;
        }
    }
    exercise_parsers(&shaped);
});
