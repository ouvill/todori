//! Plaintext field map stored inside the encrypted sync blob.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

use crate::hlc::Hlc;

pub const SORT_ORDER_FIELD: &str = "sort_order";

pub const TASK_LWW_FIELDS: &[&str] = &[
    "list_id",
    "parent_task_id",
    "title",
    "note",
    "status",
    "priority",
    "due_at",
    "scheduled_at",
    "estimated_minutes",
    "completed_at",
    "closed_reason",
    "deleted_at",
    "assignee",
    "created_at",
    "updated_at",
];

pub const LIST_LWW_FIELDS: &[&str] = &[
    "name",
    "color",
    "icon",
    "org_id",
    "is_default",
    "archived_at",
    "created_at",
    "updated_at",
];

#[derive(Debug, Error, PartialEq, Eq)]
pub enum FieldMapError {
    #[error("fields and field_hlcs must contain the same keys")]
    KeyMismatch,
    #[error("sort_order is handled by fractional indexing and is not LWW-merged")]
    SortOrderIsNotLww,
}

/// Decrypted plaintext payload for one sync record.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyncPlaintext {
    pub fields: BTreeMap<String, Value>,
    pub field_hlcs: BTreeMap<String, Hlc>,
}

impl SyncPlaintext {
    pub fn new(
        fields: BTreeMap<String, Value>,
        field_hlcs: BTreeMap<String, Hlc>,
    ) -> Result<Self, FieldMapError> {
        let plaintext = Self { fields, field_hlcs };
        plaintext.validate()?;
        Ok(plaintext)
    }

    pub fn from_single_hlc(
        fields: BTreeMap<String, Value>,
        hlc: Hlc,
    ) -> Result<Self, FieldMapError> {
        let field_hlcs = fields
            .keys()
            .map(|field| (field.clone(), hlc.clone()))
            .collect::<BTreeMap<_, _>>();
        Self::new(fields, field_hlcs)
    }

    pub fn validate(&self) -> Result<(), FieldMapError> {
        if self.fields.contains_key(SORT_ORDER_FIELD)
            || self.field_hlcs.contains_key(SORT_ORDER_FIELD)
        {
            return Err(FieldMapError::SortOrderIsNotLww);
        }
        if self.fields.keys().ne(self.field_hlcs.keys()) {
            return Err(FieldMapError::KeyMismatch);
        }
        Ok(())
    }

    pub fn record_hlc(&self) -> Option<&Hlc> {
        self.field_hlcs.values().max()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hlc(counter: u32) -> Hlc {
        Hlc {
            wall_ms: 1_000,
            counter,
            device_id: "device-a".to_string(),
        }
    }

    #[test]
    fn plaintext_requires_matching_field_and_hlc_keys() {
        let fields = BTreeMap::from([("title".to_string(), Value::String("A".to_string()))]);
        let field_hlcs = BTreeMap::new();

        assert_eq!(
            SyncPlaintext::new(fields, field_hlcs),
            Err(FieldMapError::KeyMismatch)
        );
    }

    #[test]
    fn plaintext_rejects_sort_order_as_lww_field() {
        let fields = BTreeMap::from([(SORT_ORDER_FIELD.to_string(), Value::String("a0".into()))]);
        let field_hlcs = BTreeMap::from([(SORT_ORDER_FIELD.to_string(), hlc(0))]);

        assert_eq!(
            SyncPlaintext::new(fields, field_hlcs),
            Err(FieldMapError::SortOrderIsNotLww)
        );
    }

    #[test]
    fn record_hlc_is_max_field_hlc() {
        let fields = BTreeMap::from([
            ("title".to_string(), Value::String("A".to_string())),
            ("note".to_string(), Value::String("B".to_string())),
        ]);
        let field_hlcs =
            BTreeMap::from([("title".to_string(), hlc(1)), ("note".to_string(), hlc(3))]);
        let plaintext = SyncPlaintext::new(fields, field_hlcs).unwrap();

        assert_eq!(plaintext.record_hlc(), Some(&hlc(3)));
    }

    #[test]
    fn field_constants_do_not_include_sort_order() {
        assert!(!TASK_LWW_FIELDS.contains(&SORT_ORDER_FIELD));
        assert!(!LIST_LWW_FIELDS.contains(&SORT_ORDER_FIELD));
    }
}
