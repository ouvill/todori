//! Typed field-group Last-Write-Wins merge.

use crate::field_map::{
    Clocked, FieldMapError, ListPlaintext, ScheduleCursorValue, SchedulePlaintext, SyncPlaintext,
    TaskPlaintext, TemplatePlaintext,
};
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
            due: choose("due", &a.due, &b.due, &mut local_won, &mut incoming_won),
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
            recurrence: choose(
                "recurrence",
                &a.recurrence,
                &b.recurrence,
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
        (SyncPlaintext::Template(a), SyncPlaintext::Template(b)) => {
            SyncPlaintext::Template(TemplatePlaintext {
                name: choose("name", &a.name, &b.name, &mut local_won, &mut incoming_won),
                default_list_id: choose(
                    "default_list_id",
                    &a.default_list_id,
                    &b.default_list_id,
                    &mut local_won,
                    &mut incoming_won,
                ),
                snapshot: choose(
                    "snapshot",
                    &a.snapshot,
                    &b.snapshot,
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
            })
        }
        (SyncPlaintext::Schedule(a), SyncPlaintext::Schedule(b)) => {
            let config = choose(
                "config",
                &a.config,
                &b.config,
                &mut local_won,
                &mut incoming_won,
            );
            let cursor = if a.config.value.revision == b.config.value.revision {
                let merged = a.cursor.value.cursor.merge(b.cursor.value.cursor);
                let (hlc, local_selected) = if a.cursor.hlc >= b.cursor.hlc {
                    (a.cursor.hlc.clone(), true)
                } else {
                    (b.cursor.hlc.clone(), false)
                };
                if a.cursor != b.cursor {
                    if local_selected && merged == a.cursor.value.cursor {
                        local_won.insert("cursor".to_string());
                    } else if !local_selected && merged == b.cursor.value.cursor {
                        incoming_won.insert("cursor".to_string());
                    } else {
                        local_won.insert("cursor".to_string());
                        incoming_won.insert("cursor".to_string());
                    }
                }
                Clocked::new(
                    ScheduleCursorValue {
                        config_revision: config.value.revision.clone(),
                        cursor: merged,
                    },
                    hlc,
                )
            } else if config.value.revision == a.config.value.revision {
                if a.cursor != b.cursor {
                    local_won.insert("cursor".to_string());
                }
                a.cursor.clone()
            } else {
                if a.cursor != b.cursor {
                    incoming_won.insert("cursor".to_string());
                }
                b.cursor.clone()
            };
            SyncPlaintext::Schedule(SchedulePlaintext { config, cursor })
        }
        (SyncPlaintext::TimerSession(a), SyncPlaintext::TimerSession(b)) => {
            if a.value != b.value {
                return Err(FieldMapError::ImmutableConflict);
            }
            SyncPlaintext::TimerSession(if a.hlc >= b.hlc { a.clone() } else { b.clone() })
        }
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
    use taskveil_domain::{
        new_task, RecurrenceSchedule, ScheduleCursor, TaskDue, TaskStatus, Uuid,
    };
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

    #[test]
    fn due_mode_switch_merges_as_one_atomic_field() {
        let mut task = new_task(
            Uuid::now_v7(),
            None,
            "base".into(),
            "7fffffffffffffffffffffffffffffff".into(),
            1,
        )
        .unwrap();
        let base = SyncPlaintext::from_task(&task, h(0, "base")).unwrap();
        task.due = Some(TaskDue::date("2026-07-12").unwrap());
        let date = base.stamp_task_changes(&task, h(1, "a")).unwrap();
        task.due = Some(TaskDue::date_time(1_783_798_200_000, "Asia/Tokyo").unwrap());
        let date_time = base.stamp_task_changes(&task, h(2, "b")).unwrap();

        let merged = merge_lww(&date, &date_time).unwrap().plaintext;
        let SyncPlaintext::Task(value) = merged else {
            unreachable!()
        };
        assert_eq!(
            value.due.value,
            Some(TaskDue::date_time(1_783_798_200_000, "Asia/Tokyo").unwrap())
        );
        assert_eq!(value.due.hlc, h(2, "b"));
    }

    #[test]
    fn timer_session_merge_is_idempotent_but_never_merges_different_content() {
        use taskveil_domain::{CompletedTimerSession, TimerFinishKind, TimerMode};

        let session = CompletedTimerSession {
            id: Uuid::now_v7(),
            task_id: Uuid::now_v7(),
            mode: TimerMode::Stopwatch,
            finish_kind: TimerFinishKind::Completed,
            started_at: 1,
            ended_at: 10,
            active_duration_ms: 8,
            created_at: 11,
        };
        let local = SyncPlaintext::from_timer_session(&session, h(1, "a")).unwrap();
        let identical = SyncPlaintext::from_timer_session(&session, h(2, "b")).unwrap();
        assert!(merge_lww(&local, &identical).is_ok());

        let mut conflicting = session;
        conflicting.active_duration_ms = 7;
        let conflicting = SyncPlaintext::from_timer_session(&conflicting, h(3, "c")).unwrap();
        assert_eq!(
            merge_lww(&local, &conflicting),
            Err(FieldMapError::ImmutableConflict)
        );
    }

    #[test]
    fn schedule_cursor_is_monotonic_within_revision_and_follows_new_config() {
        let template_id = Uuid::now_v7();
        let mut schedule = RecurrenceSchedule {
            id: Uuid::now_v7(),
            template_id,
            rrule: "FREQ=DAILY".to_string(),
            starts_at: 1_800_000_000_000,
            time_zone: "UTC".to_string(),
            cursor: ScheduleCursor::Pending(1_800_000_000_000),
            enabled: true,
            config_revision: "revision-a".to_string(),
            config_parent_revision: None,
            config_effective_from: 1,
            lineage: Vec::new(),
            created_at: 1,
            updated_at: 1,
        };
        let base = SyncPlaintext::from_schedule(&schedule, h(0, "base")).unwrap();
        schedule.cursor = ScheduleCursor::Pending(1_800_172_800_000);
        let ahead = base
            .stamp_schedule_changes(&schedule, h(1, "ahead"))
            .unwrap();
        schedule.cursor = ScheduleCursor::Pending(1_800_086_400_000);
        let behind = base
            .stamp_schedule_changes(&schedule, h(2, "behind"))
            .unwrap();
        let merged = merge_lww(&ahead, &behind).unwrap().plaintext;
        let reverse = merge_lww(&behind, &ahead).unwrap().plaintext;
        assert_eq!(merged, reverse);
        let SyncPlaintext::Schedule(value) = merged else {
            unreachable!()
        };
        assert_eq!(
            value.cursor.value.cursor,
            ScheduleCursor::Pending(1_800_172_800_000)
        );

        schedule.config_revision = "revision-b".to_string();
        schedule.config_parent_revision = Some("revision-a".to_string());
        schedule.config_effective_from = 2;
        schedule.cursor = ScheduleCursor::Pending(1_800_100_000_000);
        let new_config = base
            .stamp_schedule_changes(&schedule, h(3, "config"))
            .unwrap();
        let merged = merge_lww(&ahead, &new_config).unwrap().plaintext;
        let SyncPlaintext::Schedule(value) = merged else {
            unreachable!()
        };
        assert_eq!(value.config.value.revision, "revision-b");
        assert_eq!(value.cursor.value.config_revision, "revision-b");
        assert_eq!(
            value.cursor.value.cursor,
            ScheduleCursor::Pending(1_800_100_000_000)
        );
    }
}
