//! HKDF-SHA256 による鍵導出。
//!
//! `docs/03_技術仕様書.md` §4.3 の各鍵導出（KEK_pw, DEK 等）に用いる。

use hkdf::Hkdf;
use sha2::Sha256;

/// `ikm` (入力鍵材料) と `info` (文脈情報) から HKDF-SHA256 で32byteの鍵を導出する。
pub fn derive_key(ikm: &[u8], info: &[u8]) -> [u8; 32] {
    let hk = Hkdf::<Sha256>::new(None, ikm);
    let mut okm = [0u8; 32];
    hk.expand(info, &mut okm)
        .expect("32 bytes is a valid HKDF-SHA256 output length");
    okm
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derive_key_is_deterministic() {
        let ikm = b"some input key material";
        let info = b"taskveil/test";
        assert_eq!(derive_key(ikm, info), derive_key(ikm, info));
    }

    #[test]
    fn derive_key_differs_by_info() {
        let ikm = b"some input key material";
        assert_ne!(derive_key(ikm, b"context-a"), derive_key(ikm, b"context-b"));
    }

    #[test]
    fn derive_key_differs_by_ikm() {
        let info = b"taskveil/test";
        assert_ne!(derive_key(b"ikm-a", info), derive_key(b"ikm-b", info));
    }
}
