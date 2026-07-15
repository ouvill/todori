//! Production OPAQUE authentication primitives for Todori's fixed RFC 9807
//! ciphersuite and Argon2id profile.

use opaque_ke::{key_exchange::tripledh::TripleDh, CipherSuite};
use std::sync::OnceLock;

pub const OPAQUE_SUITE_NAME: &str = "opaque-rfc9807-ristretto255-3dh-argon2id-64m-t3-p4-v1";
pub const ARGON2_MEMORY_KIB: u32 = 64 * 1024;
pub const ARGON2_ITERATIONS: u32 = 3;
pub const ARGON2_PARALLELISM: u32 = 4;

/// Todori's RFC 9807 OPAQUE ciphersuite.
///
/// OPRF and key exchange group: Ristretto255, matching the crate's default
/// modern prime-order group support and avoiding legacy finite-field groups.
/// KSF: Argon2id via `argon2::Argon2<'static>` so password records resist
/// offline guessing. Hash: the Ristretto255 VOPRF suite's SHA-512 hash, selected
/// by `opaque-ke` for this group and suitable for OPAQUE's HKDF transcript use.
pub struct TodoriCipherSuite;

impl CipherSuite for TodoriCipherSuite {
    type OprfCs = opaque_ke::Ristretto255;
    type KeyExchange = TripleDh<opaque_ke::Ristretto255, sha2::Sha512>;
    type Ksf = argon2::Argon2<'static>;
}

pub fn production_argon2() -> &'static argon2::Argon2<'static> {
    static ARGON2: OnceLock<argon2::Argon2<'static>> = OnceLock::new();
    ARGON2.get_or_init(|| {
        let params = argon2::Params::new(
            ARGON2_MEMORY_KIB,
            ARGON2_ITERATIONS,
            ARGON2_PARALLELISM,
            None,
        )
        .expect("fixed Todori Argon2 parameters are valid");
        argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params)
    })
}

pub fn registration_parameters(
) -> opaque_ke::ClientRegistrationFinishParameters<'static, 'static, TodoriCipherSuite> {
    opaque_ke::ClientRegistrationFinishParameters {
        ksf: Some(production_argon2()),
        ..Default::default()
    }
}

pub fn login_parameters(
) -> opaque_ke::ClientLoginFinishParameters<'static, 'static, 'static, TodoriCipherSuite> {
    opaque_ke::ClientLoginFinishParameters {
        ksf: Some(production_argon2()),
        ..Default::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{decrypt, derive_key, encrypt};
    use opaque_ke::{
        errors::ProtocolError, ksf::Identity, ClientLogin, ClientLoginFinishParameters,
        ClientRegistration, ClientRegistrationFinishParameters, Identifiers, RegistrationRequest,
        RegistrationResponse, ServerLogin, ServerLoginParameters, ServerRegistration, ServerSetup,
    };
    use rand::{rngs::OsRng, CryptoRng, Error as RandError, RngCore};
    use std::sync::OnceLock;

    const PASSWORD: &[u8] = b"correct horse battery staple";
    const WRONG_PASSWORD: &[u8] = b"correct horse battery stapler";
    const CREDENTIAL_ID: &[u8] = b"user:alice@example.com";
    const KEK_INFO: &[u8] = b"todori/kek-pw/v1";
    const MK_AAD: &[u8] = b"todori/master-key-wrap/v1";

    type ServerRecord = ServerRegistration<TodoriCipherSuite>;

    struct Rfc9807CipherSuite;

    impl CipherSuite for Rfc9807CipherSuite {
        type OprfCs = opaque_ke::Ristretto255;
        type KeyExchange = TripleDh<opaque_ke::Ristretto255, sha2::Sha512>;
        type Ksf = Identity;
    }

    #[derive(Clone, Debug)]
    struct FixedRng(Vec<u8>);

    impl FixedRng {
        fn from_hex(value: &str) -> Self {
            Self(hex::decode(value).expect("valid RFC 9807 vector hex"))
        }
    }

    impl RngCore for FixedRng {
        fn next_u32(&mut self) -> u32 {
            unimplemented!("OPAQUE vector only requests byte slices")
        }

        fn next_u64(&mut self) -> u64 {
            unimplemented!("OPAQUE vector only requests byte slices")
        }

        fn fill_bytes(&mut self, dest: &mut [u8]) {
            assert!(!self.0.is_empty());
            let consumed = self.0.len().min(dest.len());
            dest[..consumed].copy_from_slice(&self.0[..consumed]);
            let steps = consumed % self.0.len();
            self.0[..steps].reverse();
            self.0[steps..].reverse();
            self.0.reverse();
        }

        fn try_fill_bytes(&mut self, dest: &mut [u8]) -> Result<(), RandError> {
            self.fill_bytes(dest);
            Ok(())
        }
    }

    impl CryptoRng for FixedRng {}

    struct RegistrationFixture {
        server_setup: ServerSetup<TodoriCipherSuite>,
        server_record: ServerRecord,
        registration_export_key: Vec<u8>,
    }

    struct LoginFixture {
        export_key: Vec<u8>,
        server_setup_bytes: Vec<u8>,
        server_login_state_bytes: Vec<u8>,
    }

    fn test_argon2() -> &'static argon2::Argon2<'static> {
        static ARGON2: OnceLock<argon2::Argon2<'static>> = OnceLock::new();
        ARGON2.get_or_init(|| {
            // Test-only parameters keep the PoC fast; production must tune these
            // for target devices before enabling account login.
            let params = argon2::Params::new(512, 1, 1, None).expect("valid test Argon2 params");
            argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params)
        })
    }

    fn registration_parameters<'a>() -> ClientRegistrationFinishParameters<'a, 'a, TodoriCipherSuite>
    {
        ClientRegistrationFinishParameters {
            ksf: Some(test_argon2()),
            ..Default::default()
        }
    }

    fn login_parameters<'a>() -> ClientLoginFinishParameters<'a, 'a, 'a, TodoriCipherSuite> {
        ClientLoginFinishParameters {
            ksf: Some(test_argon2()),
            ..Default::default()
        }
    }

    fn register(password: &[u8]) -> Result<RegistrationFixture, ProtocolError> {
        let mut client_rng = OsRng;
        let mut server_rng = OsRng;
        let server_setup = ServerSetup::<TodoriCipherSuite>::new(&mut server_rng);

        let client_start =
            ClientRegistration::<TodoriCipherSuite>::start(&mut client_rng, password)?;
        let server_start =
            ServerRegistration::start(&server_setup, client_start.message, CREDENTIAL_ID)?;
        let client_finish = client_start.state.finish(
            &mut client_rng,
            password,
            server_start.message,
            registration_parameters(),
        )?;
        let server_record = ServerRegistration::finish(client_finish.message);

        Ok(RegistrationFixture {
            server_setup,
            server_record,
            registration_export_key: client_finish.export_key.to_vec(),
        })
    }

    fn login(
        server_setup: &ServerSetup<TodoriCipherSuite>,
        server_record: ServerRecord,
        password: &[u8],
    ) -> Result<LoginFixture, ProtocolError> {
        let mut client_rng = OsRng;
        let mut server_rng = OsRng;

        let client_start = ClientLogin::<TodoriCipherSuite>::start(&mut client_rng, password)?;
        let server_start = ServerLogin::start(
            &mut server_rng,
            server_setup,
            Some(server_record),
            client_start.message,
            CREDENTIAL_ID,
            ServerLoginParameters::default(),
        )?;

        let server_setup_bytes = server_setup.serialize().to_vec();
        let server_login_state_bytes = server_start.state.serialize().to_vec();

        let restored_server_login =
            ServerLogin::<TodoriCipherSuite>::deserialize(&server_login_state_bytes)?;
        let client_finish = client_start.state.finish(
            &mut client_rng,
            password,
            server_start.message,
            login_parameters(),
        )?;
        restored_server_login.finish(client_finish.message, ServerLoginParameters::default())?;

        Ok(LoginFixture {
            export_key: client_finish.export_key.to_vec(),
            server_setup_bytes,
            server_login_state_bytes,
        })
    }

    #[test]
    fn registration_and_login_yield_same_export_key() -> Result<(), ProtocolError> {
        let fixture = register(PASSWORD)?;
        let login = login(&fixture.server_setup, fixture.server_record, PASSWORD)?;

        assert_eq!(fixture.registration_export_key, login.export_key);
        Ok(())
    }

    #[test]
    fn production_argon2_profile_is_fixed() {
        let params = production_argon2().params();
        assert_eq!(params.m_cost(), ARGON2_MEMORY_KIB);
        assert_eq!(params.t_cost(), ARGON2_ITERATIONS);
        assert_eq!(params.p_cost(), ARGON2_PARALLELISM);
    }

    #[test]
    fn rfc9807_appendix_c_real_vector_1_matches_registration_outputs() {
        // RFC 9807 Appendix C.1.1 uses Identity KSF so the core protocol can
        // be checked independently of Todori's production Argon2id profile.
        let decode = |value: &str| hex::decode(value).expect("valid RFC 9807 vector hex");
        let password = decode("436f7272656374486f72736542617474657279537461706c65");
        let credential_id = decode("31323334");
        let registration_request =
            decode("5059ff249eb1551b7ce4991f3336205bde44a105a032e747d21bf382e75f7a71");
        let registration_response = decode(concat!(
            "7408a268083e03abc7097fc05b587834539065e86fb0c7b6342fcf5e01e5b019",
            "b2fe7af9f48cc502d016729d2fe25cdd433f2c4bc904660b2a382c9b79df1a78"
        ));
        let registration_upload = decode(concat!(
            "76a845464c68a5d2f7e442436bb1424953b17d3e2e289ccbaccafb57ac5c3675",
            "1ac5844383c7708077dea41cbefe2fa15724f449e535dd7dd562e66f5ecfb958",
            "64eadddec9db5874959905117dad40a4524111849799281fefe3c51fa82785c5a",
            "c13171b2f17bc2c74997f0fce1e1f35bec6b91fe2e12dbd323d23ba7a38dfe",
            "c634b0f5b96109c198a8027da51854c35bee90d1e1c781806d07d49b76de6a2",
            "8b8d9e9b6c93b9f8b64d16dddd9c5bfb5fea48ee8fd2f75012a8b308605cdd",
            "8ba5"
        ));
        let expected_export_key = decode(concat!(
            "1ef15b4fa99e8a852412450ab78713aad30d21fa6966c9b8c9fb3262a970dc62",
            "950d4dd4ed62598229b1b72794fc0335199d9f7fcc6eaedde92cc04870e63f16"
        ));

        let mut registration_rng =
            FixedRng::from_hex("76cfbfe758db884bebb33582331ba9f159720ca8784a2a070a265d9c2d6abe01");
        let client_registration =
            ClientRegistration::<Rfc9807CipherSuite>::start(&mut registration_rng, &password)
                .unwrap();
        assert_eq!(
            client_registration.message.serialize().as_slice(),
            registration_request.as_slice()
        );

        let server_setup = ServerSetup::<Rfc9807CipherSuite>::deserialize(
            &[
                decode(concat!(
                    "f433d0227b0b9dd54f7c4422b600e764e47fb503f1f9a0f0a47c6606b054a7f",
                    "dc65347f1a08f277e22358bbabe26f823fca82c7848e9a75661f4ec5d5c1989ef"
                )),
                decode("47451a85372f8b3537e249d7b54188091fb18edde78094b43e2ba42b5eb89f0d"),
                decode("76a845464c68a5d2f7e442436bb1424953b17d3e2e289ccbaccafb57ac5c3675"),
            ]
            .concat(),
        )
        .unwrap();
        let server_registration = ServerRegistration::<Rfc9807CipherSuite>::start(
            &server_setup,
            RegistrationRequest::deserialize(&registration_request).unwrap(),
            &credential_id,
        )
        .unwrap();
        assert_eq!(
            server_registration.message.serialize().as_slice(),
            registration_response.as_slice()
        );

        let mut envelope_rng =
            FixedRng::from_hex("ac13171b2f17bc2c74997f0fce1e1f35bec6b91fe2e12dbd323d23ba7a38dfec");
        let client_registration_finish = client_registration
            .state
            .finish(
                &mut envelope_rng,
                &password,
                RegistrationResponse::deserialize(&registration_response).unwrap(),
                ClientRegistrationFinishParameters::new(
                    Identifiers {
                        client: None,
                        server: None,
                    },
                    None,
                ),
            )
            .unwrap();
        assert_eq!(
            client_registration_finish.message.serialize().as_slice(),
            registration_upload.as_slice()
        );
        assert_eq!(
            client_registration_finish.export_key.as_slice(),
            expected_export_key
        );
    }

    #[test]
    fn wrong_password_fails() -> Result<(), ProtocolError> {
        let fixture = register(PASSWORD)?;
        let mut client_rng = OsRng;
        let mut server_rng = OsRng;

        let client_start =
            ClientLogin::<TodoriCipherSuite>::start(&mut client_rng, WRONG_PASSWORD)?;
        let server_start = ServerLogin::start(
            &mut server_rng,
            &fixture.server_setup,
            Some(fixture.server_record),
            client_start.message,
            CREDENTIAL_ID,
            ServerLoginParameters::default(),
        )?;

        let result = client_start.state.finish(
            &mut client_rng,
            WRONG_PASSWORD,
            server_start.message,
            login_parameters(),
        );

        assert!(matches!(result, Err(ProtocolError::InvalidLoginError)));
        Ok(())
    }

    #[test]
    fn server_setup_roundtrips_through_bytes() -> Result<(), ProtocolError> {
        let fixture = register(PASSWORD)?;
        let bytes = fixture.server_setup.serialize();
        let restored_setup = ServerSetup::<TodoriCipherSuite>::deserialize(&bytes)?;
        let login = login(&restored_setup, fixture.server_record, PASSWORD)?;

        assert_eq!(bytes.as_slice(), login.server_setup_bytes.as_slice());
        assert_eq!(bytes.len(), 128);
        Ok(())
    }

    #[test]
    fn server_login_state_roundtrips_through_bytes() -> Result<(), ProtocolError> {
        let fixture = register(PASSWORD)?;
        let login = login(&fixture.server_setup, fixture.server_record, PASSWORD)?;

        assert_eq!(login.server_login_state_bytes.len(), 128);
        Ok(())
    }

    #[test]
    fn kek_wraps_and_unwraps_master_key() -> Result<(), ProtocolError> {
        let fixture = register(PASSWORD)?;
        let login = login(&fixture.server_setup, fixture.server_record, PASSWORD)?;
        let kek_pw = derive_key(&login.export_key, KEK_INFO);

        let mut master_key = [0u8; 32];
        OsRng.fill_bytes(&mut master_key);
        let wrapped = encrypt(&kek_pw, &master_key, MK_AAD).expect("wrap master key");
        let unwrapped = decrypt(&kek_pw, &wrapped, MK_AAD).expect("unwrap master key");

        assert_eq!(unwrapped, master_key);
        Ok(())
    }
}
