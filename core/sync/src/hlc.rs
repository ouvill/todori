//! Hybrid Logical Clock (HLC)。
//!
//! 各デバイスが保持し、書込のたびにインクリメントする（`docs/03_技術仕様書.md` §6.3）。
//! 比較順序は `wall_ms` -> `counter` -> `device_id` の辞書順。

use serde::{Deserialize, Serialize};

/// Hybrid Logical Clockの値。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
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
            self.counter += 1;
        }
        self.clone()
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
}
