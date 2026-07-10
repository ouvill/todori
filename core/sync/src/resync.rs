//! Pure full-resync state-machine conditions shared by all clients.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FullResyncReason {
    NewProfile,
    GcHorizonExceeded,
}

/// Selects full resync without treating a new profile (`since == 0`) as a
/// continuity error.
pub const fn full_resync_reason(since: i64, gc_horizon_seq: i64) -> Option<FullResyncReason> {
    if since == 0 {
        Some(FullResyncReason::NewProfile)
    } else if since > 0 && since < gc_horizon_seq {
        Some(FullResyncReason::GcHorizonExceeded)
    } else {
        None
    }
}

/// Delta catch-up closes only when the page is exhausted and its cursor has
/// reached the high-water observed in the same server transaction.
pub const fn delta_reached_closure(cursor: i64, has_more: bool, high_water: i64) -> bool {
    !has_more && cursor == high_water
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn closure_requires_both_exhaustion_and_high_water() {
        assert!(!delta_reached_closure(10, true, 10));
        assert!(!delta_reached_closure(9, false, 10));
        assert!(delta_reached_closure(10, false, 10));
        assert!(!delta_reached_closure(11, false, 10));
    }

    #[test]
    fn new_and_garbage_collected_cursors_are_distinguished() {
        assert_eq!(
            full_resync_reason(0, 100),
            Some(FullResyncReason::NewProfile)
        );
        assert_eq!(
            full_resync_reason(4, 5),
            Some(FullResyncReason::GcHorizonExceeded)
        );
        assert_eq!(full_resync_reason(5, 5), None);
        assert_eq!(full_resync_reason(6, 5), None);
    }
}
