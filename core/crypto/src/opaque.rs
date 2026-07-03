//! OPAQUE authentication PoC primitives.
//!
//! This module intentionally exposes only the Todori ciphersuite for now. The
//! registration/login flow is exercised in tests until the server API is built.

use opaque_ke::{key_exchange::tripledh::TripleDh, CipherSuite};

/// Todori's OPAQUE ciphersuite for the Phase 0 PoC.
///
/// OPRF and key exchange group: Ristretto255, matching the crate's default
/// modern prime-order group support and avoiding legacy finite-field groups.
/// KSF: Argon2id via `argon2::Argon2<'static>` so password records resist
/// offline guessing. Hash: the Ristretto255 VOPRF suite's SHA-512 hash, selected
/// by `opaque-ke` for this group and suitable for OPAQUE's HKDF transcript use.
pub struct TodoriCipherSuite;

impl CipherSuite for TodoriCipherSuite {
    type OprfCs = opaque_ke::Ristretto255;
    type KeGroup = opaque_ke::Ristretto255;
    type KeyExchange = TripleDh;
    type Ksf = argon2::Argon2<'static>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{decrypt, derive_key, encrypt};
    use opaque_ke::{
        errors::ProtocolError, ClientLogin, ClientLoginFinishParameters, ClientRegistration,
        ClientRegistrationFinishParameters, ServerLogin, ServerLoginStartParameters,
        ServerRegistration, ServerSetup,
    };
    use rand::{rngs::OsRng, RngCore};
    use std::sync::OnceLock;

    const PASSWORD: &[u8] = b"correct horse battery staple";
    const WRONG_PASSWORD: &[u8] = b"correct horse battery stapler";
    const CREDENTIAL_ID: &[u8] = b"user:alice@example.com";
    const KEK_INFO: &[u8] = b"todori/kek-pw/v1";
    const MK_AAD: &[u8] = b"todori/master-key-wrap/v1";

    type ServerRecord = ServerRegistration<TodoriCipherSuite>;

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
            ServerLoginStartParameters::default(),
        )?;

        let server_setup_bytes = server_setup.serialize().to_vec();
        let server_login_state_bytes = server_start.state.serialize().to_vec();

        let restored_server_login =
            ServerLogin::<TodoriCipherSuite>::deserialize(&server_login_state_bytes)?;
        let client_finish =
            client_start
                .state
                .finish(password, server_start.message, login_parameters())?;
        restored_server_login.finish(client_finish.message)?;

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
            ServerLoginStartParameters::default(),
        )?;

        let result =
            client_start
                .state
                .finish(WRONG_PASSWORD, server_start.message, login_parameters());

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

        assert_eq!(login.server_login_state_bytes.len(), 192);
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
