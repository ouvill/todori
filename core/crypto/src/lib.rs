//! `todori-crypto`: 鍵導出・レコード暗号化を提供する crate。
//!
//! 詳細は `docs/03_技術仕様書.md` §4 暗号設計 を参照。
//!
//! TODO: OPAQUE (opaque-ke) によるパスワード認証プロトコルの統合は PoC タスクで
//! 追加予定（`docs/03_技術仕様書.md` §4.7）。本crateは現時点ではAEAD暗号化と
//! HKDF鍵導出のみを提供する。

pub mod aead;
pub mod kdf;
pub mod opaque;

pub use aead::{decrypt, encrypt, CryptoError};
pub use kdf::derive_key;
pub use opaque::TodoriCipherSuite;
