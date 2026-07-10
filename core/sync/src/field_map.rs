//! Strict, collection-specific plaintext stored inside encrypted sync blobs.

use serde::{Deserialize, Serialize};
use thiserror::Error;
use todori_domain::{List, Task, TaskStatus, Uuid};

use crate::hlc::Hlc;

pub const TASK_FIELD_GROUPS: &[&str] = &[
    "title",
    "note",
    "priority",
    "due_at",
    "scheduled_at",
    "estimated_minutes",
    "assignee",
    "created_at",
    "updated_at",
    "completion",
    "placement",
];
pub const LIST_FIELD_GROUPS: &[&str] = &[
    "name",
    "color",
    "icon",
    "org_id",
    "is_default",
    "archived_at",
    "created_at",
    "updated_at",
    "placement",
];

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum FieldMapError {
    #[error("plaintext collection kind mismatch")]
    KindMismatch,
    #[error("rank must be exactly 32 lowercase hexadecimal digits")]
    InvalidRank,
    #[error("field clock cannot be encoded")]
    InvalidHlc,
    #[error("task completion fields are inconsistent with status")]
    InvalidCompletion,
    #[error("task placement is invalid for this record")]
    InvalidPlacement,
    #[error("record id must be a UUID")]
    InvalidRecordId,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Clocked<T> {
    pub value: T,
    pub hlc: Hlc,
}

impl<T> Clocked<T> {
    pub fn new(value: T, hlc: Hlc) -> Self {
        Self { value, hlc }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskCompletion {
    pub status: TaskStatus,
    pub completed_at: Option<i64>,
    pub closed_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskPlacement {
    pub list_id: Uuid,
    pub parent_task_id: Option<Uuid>,
    pub rank: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListPlacement {
    pub rank: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskPlaintext {
    pub title: Clocked<String>,
    pub note: Clocked<String>,
    pub priority: Clocked<i32>,
    pub due_at: Clocked<Option<i64>>,
    pub scheduled_at: Clocked<Option<i64>>,
    pub estimated_minutes: Clocked<Option<i32>>,
    pub assignee: Clocked<Option<Uuid>>,
    pub created_at: Clocked<i64>,
    pub updated_at: Clocked<i64>,
    pub completion: Clocked<TaskCompletion>,
    pub placement: Clocked<TaskPlacement>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListPlaintext {
    pub name: Clocked<String>,
    pub color: Clocked<String>,
    pub icon: Clocked<String>,
    pub org_id: Clocked<Option<Uuid>>,
    pub is_default: Clocked<bool>,
    pub archived_at: Clocked<Option<i64>>,
    pub created_at: Clocked<i64>,
    pub updated_at: Clocked<i64>,
    pub placement: Clocked<ListPlacement>,
}

/// The `kind` tag is authenticated inside the envelope and is checked against
/// the wire collection before a value is accepted.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "fields",
    rename_all = "snake_case",
    deny_unknown_fields
)]
pub enum SyncPlaintext {
    Task(TaskPlaintext),
    List(ListPlaintext),
}

impl SyncPlaintext {
    pub fn validate_for_collection(
        &self,
        collection: &str,
        record_id: &str,
    ) -> Result<(), FieldMapError> {
        let record_id = Uuid::parse_str(record_id).map_err(|_| FieldMapError::InvalidRecordId)?;
        match (collection, self) {
            ("tasks", Self::Task(task)) => {
                validate_rank(&task.placement.value.rank)?;
                validate_task_completion(&task.completion.value)?;
                if task.placement.value.parent_task_id == Some(record_id) {
                    return Err(FieldMapError::InvalidPlacement);
                }
                validate_hlcs([
                    &task.title.hlc,
                    &task.note.hlc,
                    &task.priority.hlc,
                    &task.due_at.hlc,
                    &task.scheduled_at.hlc,
                    &task.estimated_minutes.hlc,
                    &task.assignee.hlc,
                    &task.created_at.hlc,
                    &task.updated_at.hlc,
                    &task.completion.hlc,
                    &task.placement.hlc,
                ])
            }
            ("lists", Self::List(list)) => {
                validate_rank(&list.placement.value.rank)?;
                validate_hlcs([
                    &list.name.hlc,
                    &list.color.hlc,
                    &list.icon.hlc,
                    &list.org_id.hlc,
                    &list.is_default.hlc,
                    &list.archived_at.hlc,
                    &list.created_at.hlc,
                    &list.updated_at.hlc,
                    &list.placement.hlc,
                ])
            }
            _ => Err(FieldMapError::KindMismatch),
        }
    }

    pub fn record_hlc(&self) -> &Hlc {
        match self {
            Self::Task(value) => [
                &value.title.hlc,
                &value.note.hlc,
                &value.priority.hlc,
                &value.due_at.hlc,
                &value.scheduled_at.hlc,
                &value.estimated_minutes.hlc,
                &value.assignee.hlc,
                &value.created_at.hlc,
                &value.updated_at.hlc,
                &value.completion.hlc,
                &value.placement.hlc,
            ]
            .into_iter()
            .max()
            .expect("task plaintext has fields"),
            Self::List(value) => [
                &value.name.hlc,
                &value.color.hlc,
                &value.icon.hlc,
                &value.org_id.hlc,
                &value.is_default.hlc,
                &value.archived_at.hlc,
                &value.created_at.hlc,
                &value.updated_at.hlc,
                &value.placement.hlc,
            ]
            .into_iter()
            .max()
            .expect("list plaintext has fields"),
        }
    }

    pub fn from_task(task: &Task, hlc: Hlc) -> Result<Self, FieldMapError> {
        validate_rank(&task.sort_order)?;
        Ok(Self::Task(TaskPlaintext {
            title: Clocked::new(task.title.clone(), hlc.clone()),
            note: Clocked::new(task.note.clone(), hlc.clone()),
            priority: Clocked::new(task.priority, hlc.clone()),
            due_at: Clocked::new(task.due_at, hlc.clone()),
            scheduled_at: Clocked::new(task.scheduled_at, hlc.clone()),
            estimated_minutes: Clocked::new(task.estimated_minutes, hlc.clone()),
            assignee: Clocked::new(task.assignee, hlc.clone()),
            created_at: Clocked::new(task.created_at, hlc.clone()),
            updated_at: Clocked::new(task.updated_at, hlc.clone()),
            completion: Clocked::new(
                TaskCompletion {
                    status: task.status,
                    completed_at: task.completed_at,
                    closed_reason: task.closed_reason.clone(),
                },
                hlc.clone(),
            ),
            placement: Clocked::new(
                TaskPlacement {
                    list_id: task.list_id,
                    parent_task_id: task.parent_task_id,
                    rank: task.sort_order.clone(),
                },
                hlc,
            ),
        }))
    }

    pub fn from_list(list: &List, hlc: Hlc) -> Result<Self, FieldMapError> {
        validate_rank(&list.sort_order)?;
        Ok(Self::List(ListPlaintext {
            name: Clocked::new(list.name.clone(), hlc.clone()),
            color: Clocked::new(list.color.clone(), hlc.clone()),
            icon: Clocked::new(list.icon.clone(), hlc.clone()),
            org_id: Clocked::new(list.org_id, hlc.clone()),
            is_default: Clocked::new(list.is_default, hlc.clone()),
            archived_at: Clocked::new(list.archived_at, hlc.clone()),
            created_at: Clocked::new(list.created_at, hlc.clone()),
            updated_at: Clocked::new(list.updated_at, hlc.clone()),
            placement: Clocked::new(
                ListPlacement {
                    rank: list.sort_order.clone(),
                },
                hlc,
            ),
        }))
    }

    pub fn stamp_task_changes(&self, task: &Task, hlc: Hlc) -> Result<Self, FieldMapError> {
        let Self::Task(previous) = self else {
            return Err(FieldMapError::KindMismatch);
        };
        let mut next = match Self::from_task(task, hlc.clone())? {
            Self::Task(v) => v,
            _ => unreachable!(),
        };
        retain_unchanged(&mut next.title, &previous.title);
        retain_unchanged(&mut next.note, &previous.note);
        retain_unchanged(&mut next.priority, &previous.priority);
        retain_unchanged(&mut next.due_at, &previous.due_at);
        retain_unchanged(&mut next.scheduled_at, &previous.scheduled_at);
        retain_unchanged(&mut next.estimated_minutes, &previous.estimated_minutes);
        retain_unchanged(&mut next.assignee, &previous.assignee);
        retain_unchanged(&mut next.created_at, &previous.created_at);
        retain_unchanged(&mut next.updated_at, &previous.updated_at);
        retain_unchanged(&mut next.completion, &previous.completion);
        retain_unchanged(&mut next.placement, &previous.placement);
        Ok(Self::Task(next))
    }

    pub fn stamp_list_changes(&self, list: &List, hlc: Hlc) -> Result<Self, FieldMapError> {
        let Self::List(previous) = self else {
            return Err(FieldMapError::KindMismatch);
        };
        let mut next = match Self::from_list(list, hlc)? {
            Self::List(v) => v,
            _ => unreachable!(),
        };
        retain_unchanged(&mut next.name, &previous.name);
        retain_unchanged(&mut next.color, &previous.color);
        retain_unchanged(&mut next.icon, &previous.icon);
        retain_unchanged(&mut next.org_id, &previous.org_id);
        retain_unchanged(&mut next.is_default, &previous.is_default);
        retain_unchanged(&mut next.archived_at, &previous.archived_at);
        retain_unchanged(&mut next.created_at, &previous.created_at);
        retain_unchanged(&mut next.updated_at, &previous.updated_at);
        retain_unchanged(&mut next.placement, &previous.placement);
        Ok(Self::List(next))
    }
}

fn retain_unchanged<T: PartialEq>(next: &mut Clocked<T>, previous: &Clocked<T>) {
    if next.value == previous.value {
        next.hlc = previous.hlc.clone();
    }
}

pub fn validate_rank(rank: &str) -> Result<(), FieldMapError> {
    if rank.len() == 32
        && rank
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        Ok(())
    } else {
        Err(FieldMapError::InvalidRank)
    }
}

fn validate_hlcs<'a>(hlcs: impl IntoIterator<Item = &'a Hlc>) -> Result<(), FieldMapError> {
    for hlc in hlcs {
        hlc.encode().map_err(|_| FieldMapError::InvalidHlc)?;
    }
    Ok(())
}

fn validate_task_completion(completion: &TaskCompletion) -> Result<(), FieldMapError> {
    let valid = match completion.status {
        TaskStatus::Todo | TaskStatus::InProgress => {
            completion.completed_at.is_none() && completion.closed_reason.is_none()
        }
        TaskStatus::Done => completion.completed_at.is_some() && completion.closed_reason.is_none(),
        TaskStatus::WontDo => completion.completed_at.is_some(),
    };
    if valid {
        Ok(())
    } else {
        Err(FieldMapError::InvalidCompletion)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use todori_domain::new_task;

    fn hlc(counter: u32) -> Hlc {
        Hlc {
            wall_ms: 1_000,
            counter,
            device_id: "a".into(),
        }
    }

    #[test]
    fn strict_payload_rejects_unknown_fields_and_bad_rank() {
        let task = new_task(
            Uuid::now_v7(),
            None,
            "x".into(),
            "7fffffffffffffffffffffffffffffff".into(),
            1,
        )
        .unwrap();
        let value = SyncPlaintext::from_task(&task, hlc(0)).unwrap();
        let mut json = serde_json::to_value(value).unwrap();
        json["fields"]["unknown"] = serde_json::json!(1);
        assert!(serde_json::from_value::<SyncPlaintext>(json).is_err());
        assert_eq!(
            validate_rank("A0000000000000000000000000000000"),
            Err(FieldMapError::InvalidRank)
        );
    }

    #[test]
    fn strict_payload_rejects_unencodable_clock_invalid_completion_and_self_parent() {
        let mut task = new_task(
            Uuid::now_v7(),
            None,
            "x".into(),
            "7fffffffffffffffffffffffffffffff".into(),
            1,
        )
        .unwrap();
        let record_id = task.id;
        let mut value = SyncPlaintext::from_task(&task, hlc(0)).unwrap();
        let SyncPlaintext::Task(fields) = &mut value else {
            unreachable!()
        };
        fields.note.hlc.device_id.clear();
        assert_eq!(
            value.validate_for_collection("tasks", &record_id.to_string()),
            Err(FieldMapError::InvalidHlc)
        );

        task.status = TaskStatus::Done;
        let mut value = SyncPlaintext::from_task(&task, hlc(0)).unwrap();
        assert_eq!(
            value.validate_for_collection("tasks", &record_id.to_string()),
            Err(FieldMapError::InvalidCompletion)
        );
        let SyncPlaintext::Task(fields) = &mut value else {
            unreachable!()
        };
        fields.completion.value.completed_at = Some(2);
        fields.completion.value.closed_reason = Some("not valid for done".into());
        assert_eq!(
            value.validate_for_collection("tasks", &record_id.to_string()),
            Err(FieldMapError::InvalidCompletion)
        );

        let mut task = new_task(
            Uuid::now_v7(),
            None,
            "x".into(),
            "7fffffffffffffffffffffffffffffff".into(),
            1,
        )
        .unwrap();
        task.parent_task_id = Some(record_id);
        let value = SyncPlaintext::from_task(&task, hlc(0)).unwrap();
        assert_eq!(
            value.validate_for_collection("tasks", &record_id.to_string()),
            Err(FieldMapError::InvalidPlacement)
        );
    }

    #[test]
    fn completion_semantics_accept_only_domain_reachable_shapes() {
        for completion in [
            TaskCompletion {
                status: TaskStatus::Todo,
                completed_at: None,
                closed_reason: None,
            },
            TaskCompletion {
                status: TaskStatus::InProgress,
                completed_at: None,
                closed_reason: None,
            },
            TaskCompletion {
                status: TaskStatus::Done,
                completed_at: Some(1),
                closed_reason: None,
            },
            TaskCompletion {
                status: TaskStatus::WontDo,
                completed_at: Some(1),
                closed_reason: Some("reason".into()),
            },
        ] {
            assert_eq!(validate_task_completion(&completion), Ok(()));
        }
        for completion in [
            TaskCompletion {
                status: TaskStatus::Todo,
                completed_at: Some(1),
                closed_reason: None,
            },
            TaskCompletion {
                status: TaskStatus::InProgress,
                completed_at: None,
                closed_reason: Some("stale".into()),
            },
            TaskCompletion {
                status: TaskStatus::Done,
                completed_at: None,
                closed_reason: None,
            },
            TaskCompletion {
                status: TaskStatus::Done,
                completed_at: Some(1),
                closed_reason: Some("invalid".into()),
            },
            TaskCompletion {
                status: TaskStatus::WontDo,
                completed_at: None,
                closed_reason: Some("reason".into()),
            },
        ] {
            assert_eq!(
                validate_task_completion(&completion),
                Err(FieldMapError::InvalidCompletion)
            );
        }
    }

    #[test]
    fn changed_field_stamping_keeps_unchanged_clocks_and_compounds_completion() {
        let mut task = new_task(
            Uuid::now_v7(),
            None,
            "x".into(),
            "7fffffffffffffffffffffffffffffff".into(),
            1,
        )
        .unwrap();
        let before = SyncPlaintext::from_task(&task, hlc(1)).unwrap();
        task.note = "changed".into();
        task.status = TaskStatus::Done;
        task.completed_at = Some(2);
        let after = before.stamp_task_changes(&task, hlc(2)).unwrap();
        let (SyncPlaintext::Task(before), SyncPlaintext::Task(after)) = (before, after) else {
            unreachable!()
        };
        assert_eq!(after.title.hlc, before.title.hlc);
        assert_eq!(after.note.hlc, hlc(2));
        assert_eq!(after.completion.hlc, hlc(2));
    }
}
