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

pub use apply::{run_sync_now, ActiveSyncContext};
pub use engine::{
    PullPage, PullRecord, PushBatchOutcome, PushOp, PushOpOutcome, PushStatus, SyncEngine,
    SyncEngineError, SyncRunSummary,
};
pub use enqueue::{
    enqueue_backfill, enqueue_list_sync, enqueue_task_sync, BackfillSummary,
    LocalMutationSyncStore, LocalSyncOutboxEntry, LocalSyncStore, NewLocalSyncOutboxEntry,
};
pub use envelope::{
    decrypt_plaintext, encrypt_plaintext, EnvelopeError, ENVELOPE_VERSION, MAX_ENCRYPTED_BLOB_LEN,
};
pub use field_map::{
    FieldMapError, SyncPlaintext, LIST_LWW_FIELDS, SORT_ORDER_FIELD, TASK_LWW_FIELDS,
};
pub use hlc::{Hlc, HlcError};
pub use keys::{
    dek_for_list, ensure_list_dek_for_list, LocalSyncKeys, LISTS_COLLECTION, SYNC_CURSOR_NAME,
    SYNC_LOCAL_HLC_SETTING_KEY, TASKS_COLLECTION,
};
pub use merge::{merge_lww, MergeResult};

#[cfg(test)]
mod convergence_tests {
    use std::collections::BTreeMap;

    use proptest::{prelude::*, test_runner::Config};
    use serde_json::{json, Value};

    use crate::{merge_lww, Hlc, SyncPlaintext};

    const DEVICE_COUNT: usize = 3;

    #[derive(Debug, Clone)]
    struct EditOp {
        device: usize,
        field: &'static str,
        value: Value,
        physical_ms: i64,
    }

    #[derive(Clone)]
    struct Replica {
        clock: Hlc,
        plaintext: SyncPlaintext,
    }

    #[derive(Clone)]
    struct ServerRecord {
        plaintext: SyncPlaintext,
        hlc: Hlc,
        seq: i64,
    }

    proptest! {
        #![proptest_config(Config::with_cases(64))]

        #[test]
        fn replicas_converge_after_arbitrary_edits_pull_order_and_repush(
            ops in prop::collection::vec(edit_strategy(), 1..32),
            pull_order in prop::collection::vec(0usize..DEVICE_COUNT, 1..48),
        ) {
            let mut replicas = (0..DEVICE_COUNT)
                .map(|index| Replica {
                    clock: Hlc::new(format!("device-{index}")),
                    plaintext: initial_plaintext(),
                })
                .collect::<Vec<_>>();
            let mut server = ServerRecord {
                plaintext: initial_plaintext(),
                hlc: initial_plaintext().record_hlc().unwrap().clone(),
                seq: 0,
            };

            for op in ops {
                let replica = &mut replicas[op.device];
                let hlc = replica.clock.now(op.physical_ms);
                replica.plaintext.fields.insert(op.field.to_string(), op.value);
                replica.plaintext.field_hlcs.insert(op.field.to_string(), hlc);
                replica.plaintext.validate().unwrap();
                push_latest_state(&mut server, &replica.plaintext);
            }

            converge(&mut replicas, &mut server, &pull_order);

            let expected = replicas[0].plaintext.clone();
            for replica in &replicas[1..] {
                prop_assert_eq!(&replica.plaintext, &expected);
            }
            prop_assert_eq!(&server.plaintext, &expected);
        }
    }

    fn edit_strategy() -> impl Strategy<Value = EditOp> {
        (
            0usize..DEVICE_COUNT,
            0usize..4,
            0u16..1000,
            1_799_000_000_000i64..1_799_000_010_000i64,
        )
            .prop_map(|(device, field_index, value, physical_ms)| {
                let field = match field_index {
                    0 => "title",
                    1 => "note",
                    2 => "priority",
                    _ => "status",
                };
                let value = match field {
                    "priority" => json!((value % 4) as i64),
                    "status" => match value % 4 {
                        0 => json!("todo"),
                        1 => json!("in_progress"),
                        2 => json!("done"),
                        _ => json!("wont_do"),
                    },
                    _ => json!(format!("{field}-{value}")),
                };
                EditOp {
                    device,
                    field,
                    value,
                    physical_ms,
                }
            })
    }

    fn initial_plaintext() -> SyncPlaintext {
        SyncPlaintext::from_single_hlc(
            BTreeMap::from([
                ("title".to_string(), json!("")),
                ("note".to_string(), json!("")),
                ("priority".to_string(), json!(0)),
                ("status".to_string(), json!("todo")),
            ]),
            Hlc {
                wall_ms: 0,
                counter: 0,
                device_id: "initial".to_string(),
            },
        )
        .unwrap()
    }

    fn converge(replicas: &mut [Replica], server: &mut ServerRecord, pull_order: &[usize]) {
        let mut made_progress = true;
        let mut rounds = 0;
        while made_progress && rounds < 64 {
            rounds += 1;
            made_progress = false;
            for device_index in pull_order.iter().copied().chain(0..replicas.len()) {
                let device_index = device_index % replicas.len();
                let merge =
                    merge_lww(&replicas[device_index].plaintext, &server.plaintext).unwrap();
                if merge.plaintext != replicas[device_index].plaintext {
                    replicas[device_index].plaintext = merge.plaintext.clone();
                    made_progress = true;
                }
                if merge.needs_repush() {
                    made_progress |= push_latest_state(server, &merge.plaintext);
                }
            }
        }
    }

    fn push_latest_state(server: &mut ServerRecord, plaintext: &SyncPlaintext) -> bool {
        let hlc = plaintext.record_hlc().unwrap().clone();
        let merged = merge_lww(&server.plaintext, plaintext).unwrap().plaintext;
        let should_store = hlc > server.hlc || merged != server.plaintext;
        if should_store {
            server.plaintext = merged;
            server.hlc = server.plaintext.record_hlc().unwrap().clone();
            server.seq += 1;
        }
        should_store
    }
}
