//! Strict, collection-specific plaintext stored inside encrypted sync blobs.

use serde::{Deserialize, Serialize};
use taskveil_domain::{
    validate_completed_timer_session, CompletedTimerSession, List, RevisionBoundary, SeriesCursor,
    SeriesOccurrenceRef, Task, TaskBlueprint, TaskDue, TaskSeries, TaskSeriesConfig, TaskStatus,
    TaskTemplate, Uuid,
};
use thiserror::Error;

use crate::hlc::Hlc;

pub const TASK_FIELD_GROUPS: &[&str] = &[
    "title",
    "note",
    "priority",
    "due",
    "scheduled_at",
    "estimated_minutes",
    "assignee",
    "series_occurrence",
    "created_at",
    "updated_at",
    "completion",
    "placement",
];
pub const LIST_FIELD_GROUPS: &[&str] = &[
    "name",
    "color",
    "icon",
    "is_default",
    "archived_at",
    "created_at",
    "updated_at",
    "placement",
];
pub const TEMPLATE_FIELD_GROUPS: &[&str] = &[
    "name",
    "default_list_id",
    "blueprint",
    "created_at",
    "updated_at",
];
pub const TASK_SERIES_FIELD_GROUPS: &[&str] = &["config", "cursor"];

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
    #[error("timer session is invalid")]
    InvalidTimerSession,
    #[error("immutable timer session contents conflict")]
    ImmutableConflict,
    #[error("template plaintext is invalid")]
    InvalidTemplate,
    #[error("task series plaintext is invalid")]
    InvalidTaskSeries,
    #[error("task series cursor is bound to a different config revision")]
    CursorRevisionMismatch,
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
    pub due: Clocked<Option<TaskDue>>,
    pub scheduled_at: Clocked<Option<i64>>,
    pub estimated_minutes: Clocked<Option<i32>>,
    pub assignee: Clocked<Option<Uuid>>,
    pub series_occurrence: Clocked<Option<SeriesOccurrenceRef>>,
    pub created_at: Clocked<i64>,
    pub updated_at: Clocked<i64>,
    pub completion: Clocked<TaskCompletion>,
    pub placement: Clocked<TaskPlacement>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskBlueprintValue {
    pub blueprint: TaskBlueprint,
    pub revision: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TemplatePlaintext {
    pub name: Clocked<String>,
    pub default_list_id: Clocked<Option<Uuid>>,
    pub blueprint: Clocked<TaskBlueprintValue>,
    pub created_at: Clocked<i64>,
    pub updated_at: Clocked<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskSeriesConfigValue {
    pub blueprint: TaskBlueprint,
    pub target_list_id: Option<Uuid>,
    pub rrule: String,
    pub starts_at: i64,
    pub time_zone: String,
    pub enabled: bool,
    pub revision: String,
    pub parent_revision: Option<String>,
    pub effective_from: i64,
    pub lineage: Vec<RevisionBoundary>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SeriesCursorValue {
    pub config_revision: String,
    pub cursor: SeriesCursor,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskSeriesPlaintext {
    pub config: Clocked<TaskSeriesConfigValue>,
    pub cursor: Clocked<SeriesCursorValue>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListPlaintext {
    pub name: Clocked<String>,
    pub color: Clocked<String>,
    pub icon: Clocked<String>,
    pub is_default: Clocked<bool>,
    pub archived_at: Clocked<Option<i64>>,
    pub created_at: Clocked<i64>,
    pub updated_at: Clocked<i64>,
    pub placement: Clocked<ListPlacement>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TimerSessionPlaintext {
    pub value: CompletedTimerSession,
    pub hlc: Hlc,
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
// Plaintexts are decoded, merged, and immediately serialized. Keeping the
// variants inline avoids a heap allocation on every task merge; the largest
// current variant remains below 1 KiB.
#[allow(clippy::large_enum_variant)]
pub enum SyncPlaintext {
    Task(TaskPlaintext),
    List(ListPlaintext),
    Template(TemplatePlaintext),
    TaskSeries(TaskSeriesPlaintext),
    TimerSession(TimerSessionPlaintext),
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
                    &task.due.hlc,
                    &task.scheduled_at.hlc,
                    &task.estimated_minutes.hlc,
                    &task.assignee.hlc,
                    &task.series_occurrence.hlc,
                    &task.created_at.hlc,
                    &task.updated_at.hlc,
                    &task.completion.hlc,
                    &task.placement.hlc,
                ])
            }
            ("templates", Self::Template(template)) => {
                let value = TaskTemplate {
                    id: record_id,
                    name: template.name.value.clone(),
                    default_list_id: template.default_list_id.value,
                    blueprint: template.blueprint.value.blueprint.clone(),
                    blueprint_revision: template.blueprint.value.revision.clone(),
                    created_at: template.created_at.value,
                    updated_at: template.updated_at.value,
                };
                value
                    .validate()
                    .map_err(|_| FieldMapError::InvalidTemplate)?;
                validate_hlcs([
                    &template.name.hlc,
                    &template.default_list_id.hlc,
                    &template.blueprint.hlc,
                    &template.created_at.hlc,
                    &template.updated_at.hlc,
                ])
            }
            ("task_series", Self::TaskSeries(series)) => {
                if series.cursor.value.config_revision != series.config.value.revision {
                    return Err(FieldMapError::CursorRevisionMismatch);
                }
                let value = TaskSeries {
                    id: record_id,
                    config: TaskSeriesConfig {
                        blueprint: series.config.value.blueprint.clone(),
                        target_list_id: series.config.value.target_list_id,
                        rrule: series.config.value.rrule.clone(),
                        starts_at: series.config.value.starts_at,
                        time_zone: series.config.value.time_zone.clone(),
                        enabled: series.config.value.enabled,
                        config_revision: series.config.value.revision.clone(),
                        config_parent_revision: series.config.value.parent_revision.clone(),
                        config_effective_from: series.config.value.effective_from,
                        lineage: series.config.value.lineage.clone(),
                    },
                    cursor: series.cursor.value.cursor,
                    created_at: series.config.value.created_at,
                    updated_at: series.config.value.updated_at,
                };
                value
                    .validate()
                    .map_err(|_| FieldMapError::InvalidTaskSeries)?;
                validate_hlcs([&series.config.hlc, &series.cursor.hlc])
            }
            ("lists", Self::List(list)) => {
                validate_rank(&list.placement.value.rank)?;
                validate_hlcs([
                    &list.name.hlc,
                    &list.color.hlc,
                    &list.icon.hlc,
                    &list.is_default.hlc,
                    &list.archived_at.hlc,
                    &list.created_at.hlc,
                    &list.updated_at.hlc,
                    &list.placement.hlc,
                ])
            }
            ("timer_sessions", Self::TimerSession(timer)) => {
                if timer.value.id != record_id
                    || validate_completed_timer_session(&timer.value).is_err()
                {
                    return Err(FieldMapError::InvalidTimerSession);
                }
                validate_hlcs([&timer.hlc])
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
                &value.due.hlc,
                &value.scheduled_at.hlc,
                &value.estimated_minutes.hlc,
                &value.assignee.hlc,
                &value.series_occurrence.hlc,
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
                &value.is_default.hlc,
                &value.archived_at.hlc,
                &value.created_at.hlc,
                &value.updated_at.hlc,
                &value.placement.hlc,
            ]
            .into_iter()
            .max()
            .expect("list plaintext has fields"),
            Self::Template(value) => [
                &value.name.hlc,
                &value.default_list_id.hlc,
                &value.blueprint.hlc,
                &value.created_at.hlc,
                &value.updated_at.hlc,
            ]
            .into_iter()
            .max()
            .expect("template plaintext has fields"),
            Self::TaskSeries(value) => [&value.config.hlc, &value.cursor.hlc]
                .into_iter()
                .max()
                .expect("task series plaintext has fields"),
            Self::TimerSession(value) => &value.hlc,
        }
    }

    pub fn from_task(task: &Task, hlc: Hlc) -> Result<Self, FieldMapError> {
        validate_rank(&task.sort_order)?;
        Ok(Self::Task(TaskPlaintext {
            title: Clocked::new(task.title.clone(), hlc.clone()),
            note: Clocked::new(task.note.clone(), hlc.clone()),
            priority: Clocked::new(task.priority, hlc.clone()),
            due: Clocked::new(task.due.clone(), hlc.clone()),
            scheduled_at: Clocked::new(task.scheduled_at, hlc.clone()),
            estimated_minutes: Clocked::new(task.estimated_minutes, hlc.clone()),
            assignee: Clocked::new(task.assignee, hlc.clone()),
            series_occurrence: Clocked::new(task.series_occurrence.clone(), hlc.clone()),
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

    pub fn from_template(template: &TaskTemplate, hlc: Hlc) -> Result<Self, FieldMapError> {
        template
            .validate()
            .map_err(|_| FieldMapError::InvalidTemplate)?;
        Ok(Self::Template(TemplatePlaintext {
            name: Clocked::new(template.name.clone(), hlc.clone()),
            default_list_id: Clocked::new(template.default_list_id, hlc.clone()),
            blueprint: Clocked::new(
                TaskBlueprintValue {
                    blueprint: template.blueprint.clone(),
                    revision: template.blueprint_revision.clone(),
                },
                hlc.clone(),
            ),
            created_at: Clocked::new(template.created_at, hlc.clone()),
            updated_at: Clocked::new(template.updated_at, hlc),
        }))
    }

    pub fn from_series(series: &TaskSeries, hlc: Hlc) -> Result<Self, FieldMapError> {
        series
            .validate()
            .map_err(|_| FieldMapError::InvalidTaskSeries)?;
        Ok(Self::TaskSeries(TaskSeriesPlaintext {
            config: Clocked::new(
                TaskSeriesConfigValue {
                    blueprint: series.config.blueprint.clone(),
                    target_list_id: series.config.target_list_id,
                    rrule: series.config.rrule.clone(),
                    starts_at: series.config.starts_at,
                    time_zone: series.config.time_zone.clone(),
                    enabled: series.config.enabled,
                    revision: series.config.config_revision.clone(),
                    parent_revision: series.config.config_parent_revision.clone(),
                    effective_from: series.config.config_effective_from,
                    lineage: series.config.lineage.clone(),
                    created_at: series.created_at,
                    updated_at: series.updated_at,
                },
                hlc.clone(),
            ),
            cursor: Clocked::new(
                SeriesCursorValue {
                    config_revision: series.config.config_revision.clone(),
                    cursor: series.cursor,
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

    pub fn from_timer_session(
        session: &CompletedTimerSession,
        hlc: Hlc,
    ) -> Result<Self, FieldMapError> {
        validate_completed_timer_session(session)
            .map_err(|_| FieldMapError::InvalidTimerSession)?;
        Ok(Self::TimerSession(TimerSessionPlaintext {
            value: session.clone(),
            hlc,
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
        retain_unchanged(&mut next.due, &previous.due);
        retain_unchanged(&mut next.scheduled_at, &previous.scheduled_at);
        retain_unchanged(&mut next.estimated_minutes, &previous.estimated_minutes);
        retain_unchanged(&mut next.assignee, &previous.assignee);
        retain_unchanged(&mut next.series_occurrence, &previous.series_occurrence);
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
        retain_unchanged(&mut next.is_default, &previous.is_default);
        retain_unchanged(&mut next.archived_at, &previous.archived_at);
        retain_unchanged(&mut next.created_at, &previous.created_at);
        retain_unchanged(&mut next.updated_at, &previous.updated_at);
        retain_unchanged(&mut next.placement, &previous.placement);
        Ok(Self::List(next))
    }

    pub fn stamp_template_changes(
        &self,
        template: &TaskTemplate,
        hlc: Hlc,
    ) -> Result<Self, FieldMapError> {
        let Self::Template(previous) = self else {
            return Err(FieldMapError::KindMismatch);
        };
        let mut next = match Self::from_template(template, hlc)? {
            Self::Template(value) => value,
            _ => unreachable!(),
        };
        retain_unchanged(&mut next.name, &previous.name);
        retain_unchanged(&mut next.default_list_id, &previous.default_list_id);
        retain_unchanged(&mut next.blueprint, &previous.blueprint);
        retain_unchanged(&mut next.created_at, &previous.created_at);
        retain_unchanged(&mut next.updated_at, &previous.updated_at);
        Ok(Self::Template(next))
    }

    pub fn stamp_series_changes(
        &self,
        series: &TaskSeries,
        hlc: Hlc,
    ) -> Result<Self, FieldMapError> {
        let Self::TaskSeries(previous) = self else {
            return Err(FieldMapError::KindMismatch);
        };
        let mut next = match Self::from_series(series, hlc)? {
            Self::TaskSeries(value) => value,
            _ => unreachable!(),
        };
        retain_unchanged(&mut next.config, &previous.config);
        retain_unchanged(&mut next.cursor, &previous.cursor);
        Ok(Self::TaskSeries(next))
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
    use taskveil_domain::{new_task, TimerFinishKind, TimerMode};

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

    #[test]
    fn timer_plaintext_is_strictly_bound_to_record_id_and_completed_validation() {
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
        let plaintext = SyncPlaintext::from_timer_session(&session, hlc(1)).unwrap();
        assert_eq!(
            plaintext.validate_for_collection("timer_sessions", &session.id.to_string()),
            Ok(())
        );
        assert_eq!(
            plaintext.validate_for_collection("timer_sessions", &Uuid::now_v7().to_string()),
            Err(FieldMapError::InvalidTimerSession)
        );
        assert_eq!(
            plaintext.validate_for_collection("tasks", &session.id.to_string()),
            Err(FieldMapError::KindMismatch)
        );
    }
}
