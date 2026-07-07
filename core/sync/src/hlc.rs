//! Hybrid Logical Clock (HLC)。
//!
//! 各デバイスが保持し、書込のたびにインクリメントする（`docs/03_技術仕様書.md` §6.3）。
//! 比較順序は `wall_ms` -> `counter` -> `device_id` の辞書順。

use serde::{Deserialize, Serialize};
use thiserror::Error;

const ENCODED_PREFIX: &str = "01";
const BIASED_WALL_WIDTH: usize = 20;
const COUNTER_WIDTH: usize = 10;
const DEVICE_ID_MAX_BYTES: usize = 64;
const DEVICE_HEX_WIDTH: usize = DEVICE_ID_MAX_BYTES * 2;
const ENCODED_LEN: usize =
    ENCODED_PREFIX.len() + BIASED_WALL_WIDTH + COUNTER_WIDTH + DEVICE_HEX_WIDTH;

/// HLC encode/decode error.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum HlcError {
    #[error("HLC device id must be 1..=64 printable ASCII bytes")]
    InvalidDeviceId,
    #[error("encoded HLC has invalid length")]
    InvalidLength,
    #[error("encoded HLC has unsupported version prefix")]
    UnsupportedVersion,
    #[error("encoded HLC contains invalid digits")]
    InvalidDigits,
}

/// Hybrid Logical Clockの値。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Hash)]
pub struct Hlc {
    /// 物理時刻由来のミリ秒 (UTC epoch millis)。
    pub wall_ms: i64,
    /// 同一 `wall_ms` 内での論理カウンタ。
    pub counter: u32,
    /// 発行元デバイスID（タイブレーク用）。
    pub device_id: String,
}

impl Hlc {
    /// 新しいHLCを初期値 (`wall_ms: 0, counter: 0`) で生成する。
    pub fn new(device_id: impl Into<String>) -> Self {
        Self {
            wall_ms: 0,
            counter: 0,
            device_id: device_id.into(),
        }
    }

    /// 物理時刻 `physical_ms` に基づき時計を進め、新しいHLC値を返す。
    ///
    /// - 物理時刻が現在保持している `wall_ms` より進んでいれば `wall_ms` を更新し `counter` を0にリセットする。
    /// - 物理時刻が同一（または後退）していれば `wall_ms` は維持し `counter` を1つ進める。
    pub fn now(&mut self, physical_ms: i64) -> Hlc {
        if physical_ms > self.wall_ms {
            self.wall_ms = physical_ms;
            self.counter = 0;
        } else {
            self.counter = self
                .counter
                .checked_add(1)
                .expect("HLC logical counter exhausted");
        }
        self.clone()
    }

    /// 受信したHLCと物理時刻に基づきローカル時計を進め、新しいローカルHLCを返す。
    pub fn merge(&mut self, remote: &Hlc, physical_ms: i64) -> Hlc {
        let max_wall_ms = physical_ms.max(self.wall_ms).max(remote.wall_ms);
        self.counter = if max_wall_ms == self.wall_ms && max_wall_ms == remote.wall_ms {
            self.counter.max(remote.counter)
        } else if max_wall_ms == self.wall_ms {
            self.counter
        } else if max_wall_ms == remote.wall_ms {
            remote.counter
        } else {
            0
        };
        if max_wall_ms == self.wall_ms || max_wall_ms == remote.wall_ms {
            self.counter = self
                .counter
                .checked_add(1)
                .expect("HLC logical counter exhausted");
        }
        self.wall_ms = max_wall_ms;
        self.clone()
    }

    /// 固定幅・文字列順ソート可能なHLC表現へエンコードする。
    ///
    /// 形式は `01 || biased_wall_ms(20 decimal) || counter(10 decimal)
    /// || device_id_utf8_bytes(64 bytes, NUL padded, hex)`。
    pub fn encode(&self) -> Result<String, HlcError> {
        validate_device_id(&self.device_id)?;
        let biased_wall_ms = biased_wall_ms(self.wall_ms);
        let mut device_bytes = [0u8; DEVICE_ID_MAX_BYTES];
        let raw_device_id = self.device_id.as_bytes();
        device_bytes[..raw_device_id.len()].copy_from_slice(raw_device_id);

        Ok(format!(
            "{ENCODED_PREFIX}{biased_wall_ms:0BIASED_WALL_WIDTH$}{counter:0COUNTER_WIDTH$}{device_hex}",
            counter = self.counter,
            device_hex = encode_hex(&device_bytes),
        ))
    }

    /// [`Hlc::encode`] で生成された固定幅文字列からHLCを復元する。
    pub fn decode(encoded: &str) -> Result<Self, HlcError> {
        if encoded.len() != ENCODED_LEN {
            return Err(HlcError::InvalidLength);
        }
        if !encoded.starts_with(ENCODED_PREFIX) {
            return Err(HlcError::UnsupportedVersion);
        }

        let wall_start = ENCODED_PREFIX.len();
        let counter_start = wall_start + BIASED_WALL_WIDTH;
        let device_start = counter_start + COUNTER_WIDTH;

        let biased_wall = encoded[wall_start..counter_start]
            .parse::<u64>()
            .map_err(|_| HlcError::InvalidDigits)?;
        let counter = encoded[counter_start..device_start]
            .parse::<u32>()
            .map_err(|_| HlcError::InvalidDigits)?;
        let device_bytes = decode_hex(&encoded[device_start..])?;
        let unpadded_len = device_bytes
            .iter()
            .position(|byte| *byte == 0)
            .unwrap_or(device_bytes.len());
        let device_id = String::from_utf8(device_bytes[..unpadded_len].to_vec())
            .map_err(|_| HlcError::InvalidDeviceId)?;
        validate_device_id(&device_id)?;

        Ok(Self {
            wall_ms: unbias_wall_ms(biased_wall),
            counter,
            device_id,
        })
    }

    /// `server_now_ms + allowed_future_skew_ms` より未来のHLCかを判定する。
    pub fn exceeds_future_skew(&self, server_now_ms: i64, allowed_future_skew_ms: i64) -> bool {
        self.wall_ms > server_now_ms.saturating_add(allowed_future_skew_ms)
    }
}

fn validate_device_id(device_id: &str) -> Result<(), HlcError> {
    if device_id.is_empty()
        || device_id.len() > DEVICE_ID_MAX_BYTES
        || !device_id.bytes().all(|byte| byte.is_ascii_graphic())
    {
        return Err(HlcError::InvalidDeviceId);
    }
    Ok(())
}

fn biased_wall_ms(wall_ms: i64) -> u64 {
    (wall_ms as i128 - i64::MIN as i128) as u64
}

fn unbias_wall_ms(value: u64) -> i64 {
    (value as i128 + i64::MIN as i128) as i64
}

fn encode_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}

fn decode_hex(encoded: &str) -> Result<Vec<u8>, HlcError> {
    if !encoded.len().is_multiple_of(2) {
        return Err(HlcError::InvalidDigits);
    }
    encoded
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let high = hex_digit(pair[0])?;
            let low = hex_digit(pair[1])?;
            Ok((high << 4) | low)
        })
        .collect()
}

fn hex_digit(byte: u8) -> Result<u8, HlcError> {
    match byte {
        b'0'..=b'9' => Ok(byte - b'0'),
        b'a'..=b'f' => Ok(byte - b'a' + 10),
        _ => Err(HlcError::InvalidDigits),
    }
}

impl PartialOrd for Hlc {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Hlc {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.wall_ms
            .cmp(&other.wall_ms)
            .then_with(|| self.counter.cmp(&other.counter))
            .then_with(|| self.device_id.cmp(&other.device_id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn now_advances_wall_ms_and_resets_counter_when_physical_time_moves_forward() {
        let mut clock = Hlc::new("device-a");
        let first = clock.now(1_000);
        assert_eq!(first.wall_ms, 1_000);
        assert_eq!(first.counter, 0);

        let second = clock.now(2_000);
        assert_eq!(second.wall_ms, 2_000);
        assert_eq!(second.counter, 0);
    }

    #[test]
    fn now_increments_counter_when_physical_time_does_not_advance() {
        let mut clock = Hlc::new("device-a");
        let first = clock.now(1_000);
        let second = clock.now(1_000);
        let third = clock.now(500); // 物理時刻の後退（クロックスキュー）も許容

        assert_eq!(first.counter, 0);
        assert_eq!(second.counter, 1);
        assert_eq!(third.counter, 2);
        assert_eq!(second.wall_ms, 1_000);
        assert_eq!(third.wall_ms, 1_000);
    }

    #[test]
    fn successive_values_are_monotonically_increasing() {
        let mut clock = Hlc::new("device-a");
        let mut previous = clock.now(1_000);
        for physical_ms in [1_000, 1_000, 1_500, 1_500, 1_500, 2_000] {
            let next = clock.now(physical_ms);
            assert!(
                next > previous,
                "{next:?} should be greater than {previous:?}"
            );
            previous = next;
        }
    }

    #[test]
    fn ordering_breaks_ties_by_device_id() {
        let a = Hlc {
            wall_ms: 100,
            counter: 1,
            device_id: "device-a".to_string(),
        };
        let b = Hlc {
            wall_ms: 100,
            counter: 1,
            device_id: "device-b".to_string(),
        };
        assert!(a < b);
    }

    #[test]
    fn merge_advances_past_remote_clock() {
        let mut clock = Hlc {
            wall_ms: 1_000,
            counter: 2,
            device_id: "device-a".to_string(),
        };
        let remote = Hlc {
            wall_ms: 1_500,
            counter: 4,
            device_id: "device-b".to_string(),
        };

        let merged = clock.merge(&remote, 1_200);

        assert_eq!(merged.wall_ms, 1_500);
        assert_eq!(merged.counter, 5);
        assert_eq!(merged.device_id, "device-a");
    }

    #[test]
    fn merge_handles_equal_wall_times_deterministically() {
        let mut clock = Hlc {
            wall_ms: 1_000,
            counter: 2,
            device_id: "device-a".to_string(),
        };
        let remote = Hlc {
            wall_ms: 1_000,
            counter: 4,
            device_id: "device-b".to_string(),
        };

        let merged = clock.merge(&remote, 1_000);

        assert_eq!(merged.wall_ms, 1_000);
        assert_eq!(merged.counter, 5);
    }

    #[test]
    fn encode_decode_roundtrips() {
        let hlc = Hlc {
            wall_ms: 1_799_000_000_000,
            counter: 42,
            device_id: "device-a".to_string(),
        };

        assert_eq!(Hlc::decode(&hlc.encode().unwrap()).unwrap(), hlc);
    }

    #[test]
    fn encoded_string_order_matches_hlc_order() {
        let mut values = vec![
            Hlc {
                wall_ms: 1,
                counter: 0,
                device_id: "device-b".to_string(),
            },
            Hlc {
                wall_ms: 0,
                counter: 9,
                device_id: "device-z".to_string(),
            },
            Hlc {
                wall_ms: 1,
                counter: 0,
                device_id: "device-a".to_string(),
            },
            Hlc {
                wall_ms: -1,
                counter: u32::MAX,
                device_id: "device-z".to_string(),
            },
        ];
        let mut encoded = values
            .iter()
            .map(|hlc| hlc.encode().unwrap())
            .collect::<Vec<_>>();

        values.sort();
        encoded.sort();

        let decoded = encoded
            .iter()
            .map(|value| Hlc::decode(value).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(decoded, values);
    }

    #[test]
    fn encoded_values_are_fixed_width() {
        let short = Hlc {
            wall_ms: 1,
            counter: 1,
            device_id: "a".to_string(),
        };
        let long = Hlc {
            wall_ms: i64::MAX,
            counter: u32::MAX,
            device_id: "device-abcdefghijklmnopqrstuvwxyz-0123456789".to_string(),
        };

        assert_eq!(short.encode().unwrap().len(), long.encode().unwrap().len());
    }

    #[test]
    fn future_skew_detection_uses_physical_component_only() {
        let hlc = Hlc {
            wall_ms: 1_000,
            counter: 0,
            device_id: "device-a".to_string(),
        };

        assert!(!hlc.exceeds_future_skew(500, 500));
        assert!(hlc.exceeds_future_skew(499, 500));
    }
}
