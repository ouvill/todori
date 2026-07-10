//! `todori-sync`: HLC・差分検出・push/pull同期エンジンを提供する crate。
//!
//! 詳細は `docs/03_技術仕様書.md` §6 同期プロトコル を参照。
//!
//! `outbox` によるpush/pullフローの永続化は `todori-storage` が担う。

pub mod account;
pub mod apply;
pub mod engine;
pub mod enqueue;
pub mod envelope;
pub mod field_map;
pub mod hlc;
pub mod keys;
pub mod merge;
pub mod protocol;

pub use apply::{run_sync_now, ActiveSyncContext};
pub use engine::{
    EncryptedSyncState, PullPage, PullRecord, PushBatchOutcome, PushOp, PushOpOutcome, PushStatus,
    SyncEngine, SyncEngineError, SyncRunSummary,
};
pub use enqueue::{
    enqueue_backfill, enqueue_list_sync, enqueue_task_sync, BackfillSummary,
    LocalMutationSyncStore, LocalSyncAtomicStore, LocalSyncOutboxEntry, LocalSyncRecordState,
    LocalSyncSemanticState, LocalSyncStore, LocalSyncWriteTransaction, NewLocalSyncOutboxEntry,
};
pub use envelope::{
    decrypt_plaintext, encrypt_plaintext, EnvelopeError, ENVELOPE_VERSION, MAX_ENCRYPTED_BLOB_LEN,
};
pub use field_map::{
    validate_rank, Clocked, FieldMapError, ListPlacement, ListPlaintext, SyncPlaintext,
    TaskCompletion, TaskPlacement, TaskPlaintext, LIST_FIELD_GROUPS, TASK_FIELD_GROUPS,
};
pub use hlc::{Hlc, HlcError};
pub use keys::{
    dek_for_list, ensure_list_dek_for_list, LocalSyncKeys, LISTS_COLLECTION, SYNC_CURSOR_NAME,
    SYNC_LOCAL_HLC_SETTING_KEY, TASKS_COLLECTION,
};
pub use merge::{merge_lww, MergeResult};
pub use protocol::SyncCollection;

#[cfg(test)]
mod convergence_tests {
    use crate::{merge_lww, Hlc, SyncPlaintext};
    use proptest::{prelude::*, test_runner::Config};
    use todori_domain::{new_task, Uuid};

    proptest! {
        #![proptest_config(Config::with_cases(64))]

        #[test]
        fn distinct_field_merge_is_commutative_and_idempotent(
            title in ".{0,64}", note in ".{0,128}", a_counter in 1u32..1000, b_counter in 1u32..1000,
        ) {
            let mut task = new_task(Uuid::now_v7(), None, "base".into(), "7fffffffffffffffffffffffffffffff".into(), 1).unwrap();
            let base = SyncPlaintext::from_task(&task, h(0,"base")).unwrap();
            task.title = title.clone();
            let a = base.stamp_task_changes(&task, h(a_counter,"a")).unwrap();
            task.title = "base".into(); task.note = note.clone();
            let b = base.stamp_task_changes(&task, h(b_counter,"b")).unwrap();
            let ab = merge_lww(&a,&b).unwrap().plaintext;
            let ba = merge_lww(&b,&a).unwrap().plaintext;
            prop_assert_eq!(&ab,&ba);
            prop_assert_eq!(merge_lww(&ab,&ab).unwrap().plaintext,ab.clone());
            let SyncPlaintext::Task(value)=ab else { unreachable!() };
            prop_assert_eq!(value.title.value,title);
            prop_assert_eq!(value.note.value,note);
        }
    }
    fn h(counter: u32, device: &str) -> Hlc {
        Hlc {
            wall_ms: 1,
            counter,
            device_id: device.into(),
        }
    }
}
