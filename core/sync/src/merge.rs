//! Typed field-group Last-Write-Wins merge.

use crate::field_map::{Clocked, FieldMapError, ListPlaintext, SyncPlaintext, TaskPlaintext};
use serde::Serialize;
use std::collections::BTreeSet;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MergeResult {
    pub plaintext: SyncPlaintext,
    pub local_won_fields: BTreeSet<String>,
    pub incoming_won_fields: BTreeSet<String>,
}

impl MergeResult {
    pub fn needs_repush(&self) -> bool {
        !self.local_won_fields.is_empty()
    }
}

pub fn merge_lww(
    local: &SyncPlaintext,
    incoming: &SyncPlaintext,
) -> Result<MergeResult, FieldMapError> {
    let mut local_won = BTreeSet::new();
    let mut incoming_won = BTreeSet::new();
    let plaintext = match (local, incoming) {
        (SyncPlaintext::Task(a), SyncPlaintext::Task(b)) => SyncPlaintext::Task(TaskPlaintext {
            title: choose(
                "title",
                &a.title,
                &b.title,
                &mut local_won,
                &mut incoming_won,
            ),
            note: choose("note", &a.note, &b.note, &mut local_won, &mut incoming_won),
            priority: choose(
                "priority",
                &a.priority,
                &b.priority,
                &mut local_won,
                &mut incoming_won,
            ),
            due_at: choose(
                "due_at",
                &a.due_at,
                &b.due_at,
                &mut local_won,
                &mut incoming_won,
            ),
            scheduled_at: choose(
                "scheduled_at",
                &a.scheduled_at,
                &b.scheduled_at,
                &mut local_won,
                &mut incoming_won,
            ),
            estimated_minutes: choose(
                "estimated_minutes",
                &a.estimated_minutes,
                &b.estimated_minutes,
                &mut local_won,
                &mut incoming_won,
            ),
            assignee: choose(
                "assignee",
                &a.assignee,
                &b.assignee,
                &mut local_won,
                &mut incoming_won,
            ),
            created_at: choose(
                "created_at",
                &a.created_at,
                &b.created_at,
                &mut local_won,
                &mut incoming_won,
            ),
            updated_at: choose(
                "updated_at",
                &a.updated_at,
                &b.updated_at,
                &mut local_won,
                &mut incoming_won,
            ),
            completion: choose(
                "completion",
                &a.completion,
                &b.completion,
                &mut local_won,
                &mut incoming_won,
            ),
            placement: choose(
                "placement",
                &a.placement,
                &b.placement,
                &mut local_won,
                &mut incoming_won,
            ),
        }),
        (SyncPlaintext::List(a), SyncPlaintext::List(b)) => SyncPlaintext::List(ListPlaintext {
            name: choose("name", &a.name, &b.name, &mut local_won, &mut incoming_won),
            color: choose(
                "color",
                &a.color,
                &b.color,
                &mut local_won,
                &mut incoming_won,
            ),
            icon: choose("icon", &a.icon, &b.icon, &mut local_won, &mut incoming_won),
            org_id: choose(
                "org_id",
                &a.org_id,
                &b.org_id,
                &mut local_won,
                &mut incoming_won,
            ),
            is_default: choose(
                "is_default",
                &a.is_default,
                &b.is_default,
                &mut local_won,
                &mut incoming_won,
            ),
            archived_at: choose(
                "archived_at",
                &a.archived_at,
                &b.archived_at,
                &mut local_won,
                &mut incoming_won,
            ),
            created_at: choose(
                "created_at",
                &a.created_at,
                &b.created_at,
                &mut local_won,
                &mut incoming_won,
            ),
            updated_at: choose(
                "updated_at",
                &a.updated_at,
                &b.updated_at,
                &mut local_won,
                &mut incoming_won,
            ),
            placement: choose(
                "placement",
                &a.placement,
                &b.placement,
                &mut local_won,
                &mut incoming_won,
            ),
        }),
        _ => return Err(FieldMapError::KindMismatch),
    };
    Ok(MergeResult {
        plaintext,
        local_won_fields: local_won,
        incoming_won_fields: incoming_won,
    })
}

fn choose<T: Clone + Eq + Serialize>(
    name: &str,
    local: &Clocked<T>,
    incoming: &Clocked<T>,
    local_won: &mut BTreeSet<String>,
    incoming_won: &mut BTreeSet<String>,
) -> Clocked<T> {
    let take_local = local.hlc > incoming.hlc
        || (local.hlc == incoming.hlc && canonical(&local.value) >= canonical(&incoming.value));
    if take_local {
        if local != incoming {
            local_won.insert(name.into());
        }
        local.clone()
    } else {
        if local != incoming {
            incoming_won.insert(name.into());
        }
        incoming.clone()
    }
}

fn canonical<T: Serialize>(value: &T) -> Vec<u8> {
    serde_json::to_vec(value).expect("typed plaintext serializes")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Hlc;
    use todori_domain::{new_task, TaskStatus, Uuid};
    fn h(counter: u32, device: &str) -> Hlc {
        Hlc {
            wall_ms: 1,
            counter,
            device_id: device.into(),
        }
    }
    #[test]
    fn completion_is_atomic_and_distinct_fields_converge() {
        let mut task = new_task(
            Uuid::now_v7(),
            None,
            "old".into(),
            "7fffffffffffffffffffffffffffffff".into(),
            1,
        )
        .unwrap();
        let base = SyncPlaintext::from_task(&task, h(0, "base")).unwrap();
        task.title = "title-a".into();
        let a = base.stamp_task_changes(&task, h(1, "a")).unwrap();
        task.title = "old".into();
        task.status = TaskStatus::Done;
        task.completed_at = Some(9);
        let b = base.stamp_task_changes(&task, h(1, "b")).unwrap();
        let ab = merge_lww(&a, &b).unwrap().plaintext;
        let ba = merge_lww(&b, &a).unwrap().plaintext;
        assert_eq!(ab, ba);
        let SyncPlaintext::Task(value) = ab else {
            unreachable!()
        };
        assert_eq!(value.title.value, "title-a");
        assert_eq!(value.completion.value.status, TaskStatus::Done);
        assert_eq!(value.completion.value.completed_at, Some(9));
    }

    #[test]
    fn same_field_later_clock_wins_independent_of_argument_order() {
        let mut task = new_task(
            Uuid::now_v7(),
            None,
            "base".into(),
            "7fffffffffffffffffffffffffffffff".into(),
            1,
        )
        .unwrap();
        let base = SyncPlaintext::from_task(&task, h(0, "base")).unwrap();
        task.title = "older".into();
        let older = base.stamp_task_changes(&task, h(1, "a")).unwrap();
        task.title = "newer".into();
        let newer = base.stamp_task_changes(&task, h(2, "b")).unwrap();
        let ab = merge_lww(&older, &newer).unwrap().plaintext;
        let ba = merge_lww(&newer, &older).unwrap().plaintext;
        assert_eq!(ab, ba);
        let SyncPlaintext::Task(value) = ab else {
            unreachable!()
        };
        assert_eq!(value.title.value, "newer");
    }

    #[test]
    fn placement_and_note_merge_without_partial_placement() {
        let list_id = Uuid::now_v7();
        let mut task = new_task(
            list_id,
            None,
            "base".into(),
            "7fffffffffffffffffffffffffffffff".into(),
            1,
        )
        .unwrap();
        let base = SyncPlaintext::from_task(&task, h(0, "base")).unwrap();
        task.parent_task_id = Some(Uuid::now_v7());
        task.sort_order = "bfffffffffffffffffffffffffffffff".into();
        let placed = base.stamp_task_changes(&task, h(1, "a")).unwrap();
        task.parent_task_id = None;
        task.sort_order = "7fffffffffffffffffffffffffffffff".into();
        task.note = "remote note".into();
        let noted = base.stamp_task_changes(&task, h(1, "b")).unwrap();
        let merged = merge_lww(&placed, &noted).unwrap().plaintext;
        let SyncPlaintext::Task(value) = merged else {
            unreachable!()
        };
        assert_eq!(value.note.value, "remote note");
        assert_eq!(value.placement.value.list_id, list_id);
        assert!(value.placement.value.parent_task_id.is_some());
        assert_eq!(
            value.placement.value.rank,
            "bfffffffffffffffffffffffffffffff"
        );
    }
}
