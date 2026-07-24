use std::collections::{HashMap, HashSet};
use std::str::FromStr;

use chrono::{DateTime, TimeZone, Utc};
use chrono_tz::Tz as ChronoTz;
use rrule::{Frequency, RRule, RRuleSet, Tz as RRuleTz, Unvalidated};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

use crate::TaskStatus;

pub const TASK_BLUEPRINT_SCHEMA_REVISION: u16 = 1;
pub const MAX_TASK_BLUEPRINT_NODES: usize = 100;
pub const MAX_TASK_BLUEPRINT_BYTES: usize = 48 * 1024;
pub const SETTLEMENT_BATCH_SIZE: u16 = 100;

const ALLOWED_RRULE_PARTS: &[&str] = &["FREQ", "INTERVAL", "BYDAY", "BYMONTHDAY", "COUNT", "UNTIL"];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskContent {
    pub title: String,
    pub note: String,
    pub priority: i32,
    pub estimated_minutes: Option<i32>,
}

impl TaskContent {
    pub fn validate(&self) -> Result<(), RecurrenceError> {
        if self.title.trim().is_empty() {
            return Err(RecurrenceError::EmptyTaskTitle);
        }
        if !(0..=3).contains(&self.priority) {
            return Err(RecurrenceError::InvalidPriority);
        }
        if self
            .estimated_minutes
            .is_some_and(|minutes| minutes <= 0 || minutes % 5 != 0)
        {
            return Err(RecurrenceError::InvalidEstimatedMinutes);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskBlueprintNode {
    pub node_key: String,
    pub parent_node_key: Option<String>,
    pub sibling_order: u32,
    pub content: TaskContent,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskBlueprint {
    pub schema_revision: u16,
    pub nodes: Vec<TaskBlueprintNode>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RevisionBoundary {
    pub revision: String,
    pub parent_revision: Option<String>,
    pub effective_from: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskTemplate {
    pub id: Uuid,
    pub name: String,
    pub default_list_id: Option<Uuid>,
    pub blueprint: TaskBlueprint,
    pub blueprint_revision: String,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SeriesCursor {
    Pending(i64),
    Exhausted,
}

impl SeriesCursor {
    #[must_use]
    pub fn merge(self, other: Self) -> Self {
        match (self, other) {
            (Self::Exhausted, _) | (_, Self::Exhausted) => Self::Exhausted,
            (Self::Pending(left), Self::Pending(right)) => Self::Pending(left.max(right)),
        }
    }

    #[must_use]
    pub fn next_run_at(self) -> Option<i64> {
        match self {
            Self::Pending(instant) => Some(instant),
            Self::Exhausted => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskSeriesConfig {
    pub blueprint: TaskBlueprint,
    pub target_list_id: Option<Uuid>,
    pub rrule: String,
    pub starts_at: i64,
    pub time_zone: String,
    pub enabled: bool,
    pub config_revision: String,
    pub config_parent_revision: Option<String>,
    pub config_effective_from: i64,
    pub lineage: Vec<RevisionBoundary>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskSeries {
    pub id: Uuid,
    pub config: TaskSeriesConfig,
    pub cursor: SeriesCursor,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SeriesOccurrenceRef {
    pub series_id: Uuid,
    pub series_revision: String,
    pub occurrence_at: i64,
    pub blueprint_node_key: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StreakOccurrence {
    pub occurrence_at: i64,
    pub deadline_at: i64,
    pub status: TaskStatus,
    pub completed_at: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Streak {
    pub current: u32,
    pub finalized: bool,
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum RecurrenceError {
    #[error("task blueprint schema revision must be 1")]
    UnsupportedBlueprintRevision,
    #[error("task blueprint must contain 1 to 100 nodes")]
    InvalidNodeCount,
    #[error("task blueprint exceeds 49,152 UTF-8 bytes")]
    BlueprintTooLarge,
    #[error("task blueprint node key must be non-empty and unique")]
    InvalidNodeKey,
    #[error("task blueprint must contain exactly one root")]
    InvalidRootCount,
    #[error("task blueprint node references a missing or cyclic parent")]
    InvalidParent,
    #[error("task blueprint sibling order must be unique within each parent")]
    DuplicateSiblingOrder,
    #[error("task blueprint titles must be non-empty")]
    EmptyTaskTitle,
    #[error("task blueprint priority must be between 0 and 3")]
    InvalidPriority,
    #[error("estimated minutes must be a positive multiple of 5")]
    InvalidEstimatedMinutes,
    #[error("task template name must be non-empty")]
    EmptyTemplateName,
    #[error("RRULE must contain exactly one rule and no DTSTART/RDATE/EXDATE/EXRULE")]
    InvalidRuleShape,
    #[error("RRULE part is not supported in v1: {0}")]
    UnsupportedRulePart(String),
    #[error("RRULE FREQ must be DAILY, WEEKLY, MONTHLY, or YEARLY")]
    UnsupportedFrequency,
    #[error("RRULE part is duplicated: {0}")]
    DuplicateRulePart(String),
    #[error("RRULE is invalid: {0}")]
    InvalidRule(String),
    #[error("IANA timezone is invalid: {0}")]
    InvalidTimeZone(String),
    #[error("instant is outside the supported chrono range")]
    InvalidInstant,
    #[error("revision identity must be non-empty")]
    InvalidRevision,
}

impl TaskBlueprint {
    pub fn validate(&self) -> Result<usize, RecurrenceError> {
        if self.schema_revision != TASK_BLUEPRINT_SCHEMA_REVISION {
            return Err(RecurrenceError::UnsupportedBlueprintRevision);
        }
        if self.nodes.is_empty() || self.nodes.len() > MAX_TASK_BLUEPRINT_NODES {
            return Err(RecurrenceError::InvalidNodeCount);
        }

        let mut keys = HashSet::with_capacity(self.nodes.len());
        let mut roots = 0;
        let mut sibling_orders = HashSet::with_capacity(self.nodes.len());
        for node in &self.nodes {
            if node.node_key.trim().is_empty() || !keys.insert(node.node_key.as_str()) {
                return Err(RecurrenceError::InvalidNodeKey);
            }
            if node.parent_node_key.is_none() {
                roots += 1;
            }
            node.content.validate()?;
            if !sibling_orders.insert((node.parent_node_key.as_deref(), node.sibling_order)) {
                return Err(RecurrenceError::DuplicateSiblingOrder);
            }
        }
        if roots != 1 {
            return Err(RecurrenceError::InvalidRootCount);
        }

        let by_key = self
            .nodes
            .iter()
            .map(|node| (node.node_key.as_str(), node.parent_node_key.as_deref()))
            .collect::<HashMap<_, _>>();
        for node in &self.nodes {
            let mut seen = HashSet::new();
            let mut parent = node.parent_node_key.as_deref();
            while let Some(parent_key) = parent {
                if !seen.insert(parent_key) || parent_key == node.node_key {
                    return Err(RecurrenceError::InvalidParent);
                }
                parent = *by_key
                    .get(parent_key)
                    .ok_or(RecurrenceError::InvalidParent)?;
            }
        }

        let encoded = serde_json::to_vec(self)
            .map_err(|error| RecurrenceError::InvalidRule(error.to_string()))?;
        if encoded.len() > MAX_TASK_BLUEPRINT_BYTES {
            return Err(RecurrenceError::BlueprintTooLarge);
        }
        Ok(encoded.len())
    }
}

impl TaskTemplate {
    pub fn validate(&self) -> Result<(), RecurrenceError> {
        if self.name.trim().is_empty() {
            return Err(RecurrenceError::EmptyTemplateName);
        }
        validate_revision(&self.blueprint_revision)?;
        self.blueprint.validate()?;
        Ok(())
    }
}

impl TaskSeriesConfig {
    pub fn validate(&self) -> Result<(), RecurrenceError> {
        validate_revision(&self.config_revision)?;
        if let Some(parent) = &self.config_parent_revision {
            validate_revision(parent)?;
        }
        validate_and_normalize_rrule(&self.rrule, self.starts_at, &self.time_zone)?;
        self.blueprint.validate()?;
        Ok(())
    }
}

impl TaskSeries {
    pub fn validate(&self) -> Result<(), RecurrenceError> {
        self.config.validate()?;
        Ok(())
    }
}

fn validate_revision(revision: &str) -> Result<(), RecurrenceError> {
    if revision.trim().is_empty() {
        Err(RecurrenceError::InvalidRevision)
    } else {
        Ok(())
    }
}

pub fn validate_and_normalize_rrule(
    input: &str,
    starts_at: i64,
    time_zone: &str,
) -> Result<String, RecurrenceError> {
    let trimmed = input.trim();
    if trimmed.is_empty()
        || trimmed.contains('\n')
        || trimmed.contains('\r')
        || trimmed.to_ascii_uppercase().starts_with("DTSTART")
        || trimmed.to_ascii_uppercase().starts_with("RDATE")
        || trimmed.to_ascii_uppercase().starts_with("EXDATE")
        || trimmed.to_ascii_uppercase().starts_with("EXRULE")
    {
        return Err(RecurrenceError::InvalidRuleShape);
    }
    let body = trimmed
        .strip_prefix("RRULE:")
        .or_else(|| trimmed.strip_prefix("rrule:"))
        .unwrap_or(trimmed);
    if body.contains(':') {
        return Err(RecurrenceError::InvalidRuleShape);
    }

    let mut parts = HashMap::<String, String>::new();
    for raw_part in body.split(';') {
        let (raw_key, raw_value) = raw_part
            .split_once('=')
            .ok_or(RecurrenceError::InvalidRuleShape)?;
        let key = raw_key.trim().to_ascii_uppercase();
        let value = raw_value.trim().to_ascii_uppercase();
        if !ALLOWED_RRULE_PARTS.contains(&key.as_str()) {
            return Err(RecurrenceError::UnsupportedRulePart(key));
        }
        if value.is_empty() {
            return Err(RecurrenceError::InvalidRuleShape);
        }
        if parts.insert(key.clone(), value).is_some() {
            return Err(RecurrenceError::DuplicateRulePart(key));
        }
    }

    let frequency = parts.get("FREQ").ok_or(RecurrenceError::InvalidRuleShape)?;
    if !matches!(
        frequency.as_str(),
        "DAILY" | "WEEKLY" | "MONTHLY" | "YEARLY"
    ) {
        return Err(RecurrenceError::UnsupportedFrequency);
    }

    for list_key in ["BYDAY", "BYMONTHDAY"] {
        if let Some(value) = parts.get_mut(list_key) {
            let mut values = value.split(',').collect::<Vec<_>>();
            values.sort_unstable();
            values.dedup();
            *value = values.join(",");
        }
    }

    let canonical = ALLOWED_RRULE_PARTS
        .iter()
        .filter_map(|key| parts.get(*key).map(|value| format!("{key}={value}")))
        .collect::<Vec<_>>()
        .join(";");

    let dt_start = recurrence_start(starts_at, time_zone)?;
    let parsed = RRule::<Unvalidated>::from_str(&canonical)
        .and_then(|rule| rule.validate(dt_start))
        .map_err(|error| RecurrenceError::InvalidRule(error.to_string()))?;
    if !matches!(
        parsed.get_freq(),
        Frequency::Daily | Frequency::Weekly | Frequency::Monthly | Frequency::Yearly
    ) {
        return Err(RecurrenceError::UnsupportedFrequency);
    }
    Ok(canonical)
}

pub fn occurrences_after(
    normalized_rrule: &str,
    starts_at: i64,
    time_zone: &str,
    after_exclusive: i64,
    limit: u16,
) -> Result<(Vec<i64>, bool), RecurrenceError> {
    if limit == 0 {
        return Ok((Vec::new(), false));
    }
    let canonical = validate_and_normalize_rrule(normalized_rrule, starts_at, time_zone)?;
    let subsecond_offset = starts_at.rem_euclid(1_000);
    let dt_start = recurrence_start(starts_at, time_zone)?;
    let recurrence_after = after_exclusive.saturating_sub(subsecond_offset);
    let after = instant_in_zone(recurrence_after, time_zone)?;
    let rule = RRule::<Unvalidated>::from_str(&canonical)
        .and_then(|rule| rule.validate(dt_start))
        .map_err(|error| RecurrenceError::InvalidRule(error.to_string()))?;
    let result = RRuleSet::new(dt_start)
        .rrule(rule)
        .after(after)
        .all(limit.saturating_add(1));
    let mut dates = result
        .dates
        .into_iter()
        .map(|date| {
            date.with_timezone(&Utc)
                .timestamp_millis()
                .saturating_add(subsecond_offset)
        })
        .filter(|instant| *instant > after_exclusive)
        .collect::<Vec<_>>();
    let has_more = result.limited || dates.len() > usize::from(limit);
    dates.truncate(usize::from(limit));
    Ok((dates, has_more))
}

pub fn next_occurrence_after(
    normalized_rrule: &str,
    starts_at: i64,
    time_zone: &str,
    after_exclusive: i64,
) -> Result<Option<i64>, RecurrenceError> {
    occurrences_after(normalized_rrule, starts_at, time_zone, after_exclusive, 1)
        .map(|(dates, _)| dates.into_iter().next())
}

pub fn virtual_next_occurrence_after_end(
    normalized_rrule: &str,
    starts_at: i64,
    time_zone: &str,
    final_occurrence: i64,
) -> Result<Option<i64>, RecurrenceError> {
    let without_end = normalized_rrule
        .split(';')
        .filter(|part| !part.starts_with("COUNT=") && !part.starts_with("UNTIL="))
        .collect::<Vec<_>>()
        .join(";");
    next_occurrence_after(&without_end, starts_at, time_zone, final_occurrence)
}

fn recurrence_start(starts_at: i64, time_zone: &str) -> Result<DateTime<RRuleTz>, RecurrenceError> {
    let whole_second = starts_at.saturating_sub(starts_at.rem_euclid(1_000));
    let utc = DateTime::<Utc>::from_timestamp_millis(whole_second)
        .ok_or(RecurrenceError::InvalidInstant)?;
    let zone = parse_time_zone(time_zone)?;
    let rrule_zone = RRuleTz::from(zone);
    Ok(rrule_zone.from_utc_datetime(&utc.naive_utc()))
}

fn instant_in_zone(instant: i64, time_zone: &str) -> Result<DateTime<RRuleTz>, RecurrenceError> {
    let utc =
        DateTime::<Utc>::from_timestamp_millis(instant).ok_or(RecurrenceError::InvalidInstant)?;
    let zone = RRuleTz::from(parse_time_zone(time_zone)?);
    Ok(zone.from_utc_datetime(&utc.naive_utc()))
}

fn parse_time_zone(time_zone: &str) -> Result<ChronoTz, RecurrenceError> {
    time_zone
        .parse::<ChronoTz>()
        .map_err(|_| RecurrenceError::InvalidTimeZone(time_zone.to_string()))
}

#[must_use]
pub fn series_task_id(
    series_id: Uuid,
    series_revision: &str,
    occurrence_at: i64,
    node_key: &str,
) -> Uuid {
    let mut name = Vec::with_capacity(4 + series_revision.len() + node_key.len() + 20);
    name.extend_from_slice(b"TSR1");
    append_sized(&mut name, series_revision.as_bytes());
    name.extend_from_slice(&occurrence_at.to_be_bytes());
    append_sized(&mut name, node_key.as_bytes());
    Uuid::new_v5(&series_id, &name)
}

fn append_sized(target: &mut Vec<u8>, value: &[u8]) {
    let len = u32::try_from(value.len()).unwrap_or(u32::MAX);
    target.extend_from_slice(&len.to_be_bytes());
    target.extend_from_slice(value);
}

#[must_use]
pub fn calculate_streak(occurrences: &[StreakOccurrence], now_ms: i64) -> Streak {
    let mut ordered = occurrences.to_vec();
    ordered.sort_by_key(|occurrence| occurrence.occurrence_at);
    let mut current = 0_u32;
    let mut finalized = true;

    for occurrence in ordered {
        let achieved = occurrence.status == TaskStatus::Done
            && occurrence
                .completed_at
                .is_some_and(|completed_at| completed_at < occurrence.deadline_at);
        let pending = matches!(occurrence.status, TaskStatus::Todo | TaskStatus::InProgress)
            && now_ms < occurrence.deadline_at;
        if achieved {
            current = current.saturating_add(1);
        } else if pending {
            finalized = false;
        } else {
            current = 0;
        }
    }
    Streak { current, finalized }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn blueprint() -> TaskBlueprint {
        TaskBlueprint {
            schema_revision: TASK_BLUEPRINT_SCHEMA_REVISION,
            nodes: vec![
                TaskBlueprintNode {
                    node_key: "root".to_string(),
                    parent_node_key: None,
                    sibling_order: 0,
                    content: TaskContent {
                        title: "Weekly review".to_string(),
                        note: "".to_string(),
                        priority: 1,
                        estimated_minutes: Some(30),
                    },
                },
                TaskBlueprintNode {
                    node_key: "child".to_string(),
                    parent_node_key: Some("root".to_string()),
                    sibling_order: 0,
                    content: TaskContent {
                        title: "Collect notes".to_string(),
                        note: "Only content".to_string(),
                        priority: 0,
                        estimated_minutes: None,
                    },
                },
            ],
        }
    }

    #[test]
    fn blueprint_validates_content_only_tree() {
        assert!(blueprint().validate().is_ok());
    }

    #[test]
    fn blueprint_rejects_cycles_and_duplicate_sibling_order() {
        let mut cyclic = blueprint();
        cyclic.nodes[0].parent_node_key = Some("child".to_string());
        assert_eq!(cyclic.validate(), Err(RecurrenceError::InvalidRootCount));

        let mut duplicate = blueprint();
        duplicate.nodes.push(TaskBlueprintNode {
            node_key: "child-2".to_string(),
            parent_node_key: Some("root".to_string()),
            sibling_order: 0,
            content: TaskContent {
                title: "Duplicate".to_string(),
                note: String::new(),
                priority: 0,
                estimated_minutes: None,
            },
        });
        assert_eq!(
            duplicate.validate(),
            Err(RecurrenceError::DuplicateSiblingOrder)
        );
    }

    #[test]
    fn blueprint_and_template_reject_invalid_task_content_and_name() {
        let mut invalid = blueprint();
        invalid.nodes[0].content.title = " ".to_string();
        assert_eq!(invalid.validate(), Err(RecurrenceError::EmptyTaskTitle));

        let mut invalid = blueprint();
        invalid.nodes[0].content.priority = 4;
        assert_eq!(invalid.validate(), Err(RecurrenceError::InvalidPriority));

        let mut invalid = blueprint();
        invalid.nodes[0].content.estimated_minutes = Some(1);
        assert_eq!(
            invalid.validate(),
            Err(RecurrenceError::InvalidEstimatedMinutes)
        );

        let template = TaskTemplate {
            id: Uuid::now_v7(),
            name: " ".to_string(),
            default_list_id: None,
            blueprint: blueprint(),
            blueprint_revision: "r1".to_string(),
            created_at: 1,
            updated_at: 1,
        };
        assert_eq!(template.validate(), Err(RecurrenceError::EmptyTemplateName));
    }

    #[test]
    fn rrule_allowlist_normalizes_and_rejects_unsupported_parts() {
        let starts_at = Utc
            .with_ymd_and_hms(2026, 1, 1, 0, 0, 0)
            .unwrap()
            .timestamp_millis();
        assert_eq!(
            validate_and_normalize_rrule(
                "rrule:freq=weekly;byday=WE,MO;interval=2",
                starts_at,
                "Asia/Tokyo"
            )
            .unwrap(),
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE"
        );
        assert!(matches!(
            validate_and_normalize_rrule("FREQ=HOURLY", starts_at, "UTC"),
            Err(RecurrenceError::UnsupportedFrequency)
        ));
        assert!(matches!(
            validate_and_normalize_rrule("FREQ=DAILY;BYHOUR=9", starts_at, "UTC"),
            Err(RecurrenceError::UnsupportedRulePart(_))
        ));
        assert_eq!(
            validate_and_normalize_rrule("RRULE:FREQ=DAILY\nRRULE:FREQ=WEEKLY", starts_at, "UTC"),
            Err(RecurrenceError::InvalidRuleShape)
        );
    }

    #[test]
    fn daily_occurrence_preserves_wall_time_across_dst() {
        let starts_at = Utc
            .with_ymd_and_hms(2026, 3, 7, 14, 0, 0)
            .unwrap()
            .timestamp_millis(); // 09:00 America/New_York
        let after = starts_at - 1;
        let (dates, _) = occurrences_after(
            "FREQ=DAILY;COUNT=3",
            starts_at,
            "America/New_York",
            after,
            10,
        )
        .unwrap();
        assert_eq!(dates.len(), 3);
        assert_eq!(dates[1] - dates[0], 23 * 60 * 60 * 1000);
        assert_eq!(dates[2] - dates[1], 24 * 60 * 60 * 1000);
    }

    #[test]
    fn occurrence_generation_preserves_subsecond_start_offset() {
        let starts_at = Utc
            .with_ymd_and_hms(2026, 1, 1, 9, 0, 0)
            .unwrap()
            .timestamp_millis()
            + 425;
        let (dates, _) =
            occurrences_after("FREQ=DAILY", starts_at, "UTC", starts_at - 1, 2).unwrap();
        assert_eq!(dates, [starts_at, starts_at + 24 * 60 * 60 * 1_000]);
    }

    #[test]
    fn monthly_missing_day_is_skipped() {
        let starts_at = Utc
            .with_ymd_and_hms(2026, 1, 31, 9, 0, 0)
            .unwrap()
            .timestamp_millis();
        let (dates, _) = occurrences_after(
            "FREQ=MONTHLY;COUNT=3;BYMONTHDAY=31",
            starts_at,
            "UTC",
            starts_at - 1,
            10,
        )
        .unwrap();
        let rendered = dates
            .iter()
            .map(|instant| {
                DateTime::<Utc>::from_timestamp_millis(*instant)
                    .unwrap()
                    .date_naive()
            })
            .collect::<Vec<_>>();
        assert_eq!(
            rendered,
            vec![
                chrono::NaiveDate::from_ymd_opt(2026, 1, 31).unwrap(),
                chrono::NaiveDate::from_ymd_opt(2026, 3, 31).unwrap(),
                chrono::NaiveDate::from_ymd_opt(2026, 5, 31).unwrap(),
            ]
        );
    }

    #[test]
    fn supported_frequencies_intervals_and_endings_are_accepted() {
        let starts_at = Utc
            .with_ymd_and_hms(2026, 1, 1, 9, 0, 0)
            .unwrap()
            .timestamp_millis();
        for rule in [
            "FREQ=DAILY;INTERVAL=2",
            "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4",
            "FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3",
            "FREQ=YEARLY;COUNT=2",
            "FREQ=DAILY;UNTIL=20260105T090000Z",
        ] {
            assert!(validate_and_normalize_rrule(rule, starts_at, "UTC").is_ok());
        }
        let (yearly, has_more) =
            occurrences_after("FREQ=YEARLY;COUNT=2", starts_at, "UTC", starts_at - 1, 10).unwrap();
        assert_eq!(yearly.len(), 2);
        assert!(!has_more);
        let (until, has_more) = occurrences_after(
            "FREQ=DAILY;UNTIL=20260105T090000Z",
            starts_at,
            "UTC",
            starts_at - 1,
            10,
        )
        .unwrap();
        assert_eq!(until.len(), 5);
        assert!(!has_more);
    }

    #[test]
    fn stored_timezone_keeps_occurrences_stable_after_device_zone_move() {
        let starts_at = Utc
            .with_ymd_and_hms(2026, 10, 31, 13, 0, 0)
            .unwrap()
            .timestamp_millis(); // 09:00 America/New_York before fall-back.
        let before_move = occurrences_after(
            "FREQ=DAILY;COUNT=3",
            starts_at,
            "America/New_York",
            starts_at - 1,
            10,
        )
        .unwrap();
        // Device-local timezone is intentionally not an input. Reopening the same
        // persisted task series after travel must therefore produce identical instants.
        let after_move = occurrences_after(
            "FREQ=DAILY;COUNT=3",
            starts_at,
            "America/New_York",
            starts_at - 1,
            10,
        )
        .unwrap();
        assert_eq!(before_move, after_move);
        assert_eq!(before_move.0[1] - before_move.0[0], 25 * 60 * 60 * 1000);
    }

    #[test]
    fn exhausted_cursor_is_terminal_maximum() {
        assert_eq!(
            SeriesCursor::Pending(200).merge(SeriesCursor::Pending(100)),
            SeriesCursor::Pending(200)
        );
        assert_eq!(
            SeriesCursor::Exhausted.merge(SeriesCursor::Pending(i64::MAX)),
            SeriesCursor::Exhausted
        );
    }

    #[test]
    fn series_ids_are_deterministic_and_revision_bound() {
        let series_id = Uuid::now_v7();
        let first = series_task_id(series_id, "r1", 42, "root");
        assert_eq!(first, series_task_id(series_id, "r1", 42, "root"));
        assert_ne!(first, series_task_id(series_id, "r2", 42, "root"));
        assert_eq!(first.get_version_num(), 5);
    }

    #[test]
    fn pending_latest_occurrence_preserves_previous_streak() {
        let streak = calculate_streak(
            &[
                StreakOccurrence {
                    occurrence_at: 100,
                    deadline_at: 200,
                    status: TaskStatus::Done,
                    completed_at: Some(150),
                },
                StreakOccurrence {
                    occurrence_at: 200,
                    deadline_at: 300,
                    status: TaskStatus::Todo,
                    completed_at: None,
                },
            ],
            250,
        );
        assert_eq!(
            streak,
            Streak {
                current: 1,
                finalized: false
            }
        );
    }

    #[test]
    fn late_done_and_wont_do_break_streak() {
        let late = StreakOccurrence {
            occurrence_at: 100,
            deadline_at: 200,
            status: TaskStatus::Done,
            completed_at: Some(200),
        };
        assert_eq!(calculate_streak(&[late], 300).current, 0);
        let wont_do = StreakOccurrence {
            occurrence_at: 200,
            deadline_at: 300,
            status: TaskStatus::WontDo,
            completed_at: Some(250),
        };
        assert_eq!(calculate_streak(&[wont_do], 300).current, 0);
    }

    #[test]
    fn virtual_deadline_ignores_count() {
        let starts_at = Utc
            .with_ymd_and_hms(2026, 7, 1, 9, 0, 0)
            .unwrap()
            .timestamp_millis();
        let final_occurrence = Utc
            .with_ymd_and_hms(2026, 7, 3, 9, 0, 0)
            .unwrap()
            .timestamp_millis();
        let deadline = virtual_next_occurrence_after_end(
            "FREQ=DAILY;COUNT=3",
            starts_at,
            "UTC",
            final_occurrence,
        )
        .unwrap();
        assert_eq!(
            deadline,
            Some(
                Utc.with_ymd_and_hms(2026, 7, 4, 9, 0, 0)
                    .unwrap()
                    .timestamp_millis()
            )
        );
    }
}
